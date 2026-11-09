-- Comportement d'un bot (#141), un par bot vivant : ce qu'il sait sans tricher (vue dans son champ de vision et en
-- ligne de vue dégagée, tirs entendus à position approximative, mémoire de la dernière position connue), et ce qu'il
-- fait de ce savoir (états chercher, enquêter, combattre, se replacer ; décision 3 de #133).
-- Il commande le suivi de chemin (destination choisie ou imposée, attente sur un point) et le regard de BotMotion.
-- En combat il garde sa course (pas de poursuite, bhop non coupé) et se tourne vers la cible le temps d'un tir, puis
-- rend son regard à sa course ; le tir lui-même vient avec #143 (onFire), ici il est seulement compté.
-- Règles pures : BotBehaviorRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotBehaviorRules = require(ReplicatedStorage.Shared.BotBehaviorRules)
local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local BotMotion = require(script.Parent.BotMotion)
local NavPlan = require(script.Parent.NavPlan)

type State = BotBehaviorRules.State
type Memory = BotBehaviorRules.Memory

-- Ce que le gestionnaire des bots fournit au comportement
export type Env = {
	id: number, -- id du participant (bot)
	-- Autres participants en vie : id, humain ou bot, personnage
	others: () -> { { id: number, isHuman: boolean, character: Model } },
	-- Destinations des autres bots (point → nombre)
	claimed: (selfId: number) -> { [number]: number },
	-- Murs d'air de la map : ne bloquent pas la vue
	clips: Instance?,
}

local BotBrain = {}
BotBrain.__index = BotBrain

export type BotBrain = typeof(setmetatable(
	{} :: {
		env: Env,
		char: Model,
		motion: BotMotion.BotMotion,
		rng: Random,
		rand: () -> number,
		params: RaycastParams,
		state: State,
		memory: { [number]: Memory },
		freshest: Memory?,
		heard: { { id: number, position: Vector3, isHuman: boolean } },
		lastContact: number,
		investigated: number,
		investigateQueue: { number }, -- points voisins encore à fouiller
		investigateDone: boolean,
		wantsReplace: boolean,
		replaceDone: boolean,
		lastVisit: { [number]: number },
		perceptionTimer: number,
		targetId: number?,
		targetPos: Vector3?,
		targetVisible: boolean, -- vue à ce regard (sinon gardée en tête un instant, sans tir)
		seenSince: number, -- instant où la cible courante a été vue
		lastShot: number?,
		holdLook: Vector3?, -- point regardé en tenant un angle
		lastHealth: number,
	},
	BotBrain
))

-- Bilan de tous les bots (debug : NavDebug l'affiche dans la console)
BotBrain.stats = { combats = 0, shots = 0, heard = 0, investigations = 0, replacements = 0, holds = 0, biased = 0 }

-- Rappel posé par le combat (#143) : appelé quand un bot tire (bot, participant visé, position visée)
BotBrain.onFire = nil :: ((BotBrain, number, Vector3) -> ())?

-- Cette méthode permet de lire un point de passage sous la forme attendue par les règles lorsqu'un choix de
-- destination les note.
local function waypointInfos(plan: NavPlan.Plan): { BotBehaviorRules.WaypointInfo }
	return plan.waypoints :: any
end

-- Cette méthode permet de créer le comportement d'un bot lorsqu'il apparaît, branché sur son mouvement.
function BotBrain.new(env: Env, char: Model, motion: BotMotion.BotMotion): BotBrain
	local rng = motion.rng
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if env.clips then { char, env.clips } else { char }
	params.RespectCanCollide = false
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local now = os.clock()
	local self = setmetatable({
		env = env,
		char = char,
		motion = motion,
		rng = rng,
		rand = function()
			return rng:NextNumber()
		end,
		params = params,
		state = "chercher" :: State,
		memory = {},
		freshest = nil,
		heard = {},
		lastContact = now,
		investigated = -math.huge,
		investigateQueue = {},
		investigateDone = true,
		wantsReplace = false,
		replaceDone = true,
		lastVisit = {},
		perceptionTimer = rng:NextNumber() * BotConfig.PERCEPTION_INTERVAL, -- bots décalés entre eux
		targetId = nil,
		targetPos = nil,
		targetVisible = false,
		seenSince = 0,
		lastShot = nil,
		holdLook = nil,
		lastHealth = if humanoid then humanoid.Health else 100,
	}, BotBrain)
	local navigator = motion.navigator
	navigator.chooseDestination = function(foot)
		return self:_chooseDestination(foot)
	end
	navigator.onArrive = function(waypoint)
		return self:_onArrive(waypoint)
	end
	if humanoid then
		humanoid.HealthChanged:Connect(function(health)
			self:_onHealth(health, humanoid.MaxHealth)
		end)
	end
	return self
end

-- Cette méthode permet de noter un tir entendu lorsqu'un participant tire (position du tireur) ; trié au prochain
-- regard autour de lui (rayon et flou de l'ouïe).
function BotBrain.hearShot(self: BotBrain, shooterId: number, position: Vector3, isHuman: boolean)
	if shooterId ~= self.env.id then
		table.insert(self.heard, { id = shooterId, position = position, isHuman = isHuman })
	end
end

-- Cette méthode permet de demander un repli lorsque ce bot vient de tuer (#143 l'appellera à chaque kill).
function BotBrain.notifyKill(self: BotBrain)
	self.wantsReplace = true
end

-- Cette méthode permet de réagir à une perte de PV lorsque le bot est touché : en combat et sous REPLACE_HEALTH de
-- ses PV, le duel est perdu d'avance, il se replace.
function BotBrain._onHealth(self: BotBrain, health: number, maxHealth: number)
	local lost = health < self.lastHealth
	self.lastHealth = health
	if lost and self.state == "combattre" and BotBehaviorRules.duelLost(health, maxHealth) then
		self.wantsReplace = true
	end
end

-- Cette méthode permet de lire la position des yeux du bot lorsqu'il regarde autour de lui.
function BotBrain._eye(self: BotBrain): Vector3
	return self.motion:position() + Vector3.new(0, BotConfig.EYE_HEIGHT, 0)
end

-- Cette méthode permet de savoir si une partie d'un personnage est en ligne de vue dégagée lorsque le bot regarde
-- une cible dans son champ de vision : rien entre ses yeux et elle, sauf le personnage lui-même.
function BotBrain._clearLine(self: BotBrain, eye: Vector3, point: Vector3, character: Model): boolean
	local hit = workspace:Raycast(eye, point - eye, self.params)
	return hit == nil or hit.Instance:IsDescendantOf(character)
end

-- Cette méthode permet de regarder autour de lui lorsque son intervalle de perception est passé : cibles vues
-- (champ de vision, portée, ligne de vue dégagée sur la tête ou le torse) notées en mémoire, cible choisie, tirs
-- entendus notés à position approximative.
function BotBrain._perceive(self: BotBrain, now: number)
	local eye = self:_eye()
	local yaw = self.motion.yaw
	local candidates: { BotBehaviorRules.Candidate } = {}
	local positions: { [number]: Vector3 } = {}
	for _, other in self.env.others() do
		local root = other.character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local head = other.character:FindFirstChild("Head") :: BasePart?
		if root then
			local torso = root.Position
			local distance = (torso - eye).Magnitude
			if
				distance <= BotConfig.VIEW_RANGE
				and BotBehaviorRules.inFieldOfView(eye, yaw, torso, BotConfig.VIEW_FOV)
				and (
					(head and self:_clearLine(eye, head.Position, other.character))
					or self:_clearLine(eye, torso, other.character)
				)
			then
				BotBehaviorRules.remember(self.memory, other.id, torso, now, true, other.isHuman)
				positions[other.id] = if head then head.Position else torso
				table.insert(candidates, { id = other.id, isHuman = other.isHuman, distance = distance })
				self.lastContact = now
			end
		end
	end

	local target = BotBehaviorRules.pickTarget(candidates)
	if target then
		if target.id ~= self.targetId then
			if not self.targetId then
				BotBrain.stats.combats += 1
			end
			-- Nouvelle cible : le temps de réaction repart de zéro
			self.targetId, self.seenSince, self.lastShot = target.id, now, nil
		end
		self.targetPos = positions[target.id]
		self.targetVisible = true
	elseif self.targetId then
		local last = self.memory[self.targetId]
		if last and last.seen and BotBehaviorRules.keepTarget(last.at, now) then
			-- Vue il y a un instant (sortie du champ en reprenant sa course) : il la garde en tête, regard vers sa
			-- dernière position vue, sans tirer tant qu'il ne la revoit pas
			self.targetPos = last.position + Vector3.new(0, BotConfig.EYE_HEIGHT, 0)
			self.targetVisible = false
		else
			-- Perdue de vue : il reprend sa course, et n'enquête que parfois (pas de poursuite systématique)
			self.targetId, self.targetPos, self.lastShot, self.targetVisible = nil, nil, nil, false
			if not BotBehaviorRules.investigateLost(self.rng:NextNumber()) then
				-- Contacts jusqu'ici tenus pour fouillés ; un tir entendu à ce même regard reste à enquêter
				self.investigated = now - 1e-3
			end
		end
	end

	for _, shot in self.heard do
		local pos = BotBehaviorRules.heardPosition(
			eye,
			shot.position,
			BotConfig.HEARING_RADIUS,
			BotConfig.HEARING_FUZZ,
			self.rand
		)
		if pos then
			BotBehaviorRules.remember(self.memory, shot.id, pos, now, false, shot.isHuman)
			self.lastContact = now
			BotBrain.stats.heard += 1
		end
	end
	table.clear(self.heard)
	self.freshest = BotBehaviorRules.forget(self.memory, now, BotConfig.MEMORY_TIME)
end

-- Cette méthode permet de trouver le point de passage le plus proche d'une position lorsque le bot doit y aller
-- (dernière position connue, souvent hors de la grille : tir entendu flou, cible en l'air).
function BotBrain._waypointNear(plan: NavPlan.Plan, position: Vector3): number?
	local cell = NavPlan.nearestCell(plan, position, BotConfig.NAV_NEAREST_RADIUS * 2)
	local wp = cell and plan.cellWaypoint[cell]
	if wp then
		return wp
	end
	local best, bestDist = nil, math.huge
	for i, point in plan.waypoints do
		local d = (point.position - position).Magnitude
		if d < bestDist then
			best, bestDist = i, d
		end
	end
	return best
end

-- Cette méthode permet de lancer une enquête lorsqu'un contact pas encore fouillé arrive : direction le point le
-- plus proche de la dernière position connue, puis INVESTIGATE_POINTS points voisins tirés au hasard.
function BotBrain._startInvestigation(self: BotBrain, plan: NavPlan.Plan, memory: Memory)
	self.investigated = memory.at
	self.investigateDone = false
	table.clear(self.investigateQueue)
	local wp = BotBrain._waypointNear(plan, memory.position)
	if not wp then
		self.investigateDone = true
		return
	end
	local neighbors = {}
	local edges = plan.waypointEdges[wp]
	if edges then
		for other in edges do
			table.insert(neighbors, other)
		end
	end
	for _ = 1, math.min(BotConfig.INVESTIGATE_POINTS, #neighbors) do
		local k = self.rng:NextInteger(1, #neighbors)
		table.insert(self.investigateQueue, table.remove(neighbors, k) :: number)
	end
	BotBrain.stats.investigations += 1
	self.motion.navigator:setDestination(wp)
end

-- Cette méthode permet de lancer un repli lorsque le bot doit se replacer : point couvert proche, loin de la menace
-- (dernière position connue) ; sans point à portée, il reste dans son état.
function BotBrain._startReplace(self: BotBrain, plan: NavPlan.Plan)
	self.wantsReplace = false
	local threat = self.freshest and self.freshest.position
	local wp = BotBehaviorRules.pickCover(
		waypointInfos(plan),
		self.motion:position(),
		threat,
		self.motion.navigator.lastWaypoint,
		self.rand
	)
	if not wp then
		self.replaceDone = true
		return
	end
	self.replaceDone = false
	BotBrain.stats.replacements += 1
	self.motion.navigator:setDestination(wp)
end

-- Cette méthode permet de choisir la prochaine destination lorsque le suivi de chemin n'en a plus : point voisin à
-- fouiller en enquête, sinon note dynamique (passages récents, autres bots, distance, hasard, biais vers les humains).
function BotBrain._chooseDestination(self: BotBrain, foot: Vector3): number?
	local plan = NavPlan.get()
	if not plan then
		return nil
	end
	if self.state == "enqueter" and #self.investigateQueue > 0 then
		return table.remove(self.investigateQueue, 1)
	end
	local now = os.clock()
	local biasCenter = nil
	if BotBehaviorRules.biasActive(now, self.lastContact) then
		local humans = {}
		for _, other in self.env.others() do
			if other.isHuman then
				local root = other.character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					table.insert(humans, root.Position)
				end
			end
		end
		biasCenter = BotBehaviorRules.biasCenter(foot, humans, self.rand)
		if biasCenter then
			BotBrain.stats.biased += 1
		end
	end
	return BotBehaviorRules.pickDestination(waypointInfos(plan), {
		from = foot,
		lastVisit = self.lastVisit,
		claimed = self.env.claimed(self.env.id),
		now = now,
		avoid = self.motion.navigator.lastWaypoint,
		biasCenter = biasCenter,
	}, self.rand)
end

-- Cette méthode permet de réagir à l'arrivée sur un point lorsque le suivi de chemin l'atteint : passage noté, fin
-- de repli ou de fouille, et en recherche parfois un angle tenu quelques secondes (regard vers un point visible).
-- Renvoie l'attente sur place (nil : courte pause).
function BotBrain._onArrive(self: BotBrain, waypoint: number?): number?
	local now = os.clock()
	if waypoint then
		self.lastVisit[waypoint] = now
	end
	if self.state == "replacer" then
		self.replaceDone = true
	elseif self.state == "enqueter" and #self.investigateQueue == 0 then
		self.investigateDone = true
	end
	local plan = NavPlan.get()
	if self.state ~= "chercher" or not waypoint or not plan or self.rng:NextNumber() >= BotConfig.HOLD_CHANCE then
		self.holdLook = nil
		return nil
	end
	local wp = plan.waypoints[waypoint]
	local visible = {}
	for _, other in wp.visible do
		table.insert(visible, plan.waypoints[other].position + Vector3.new(0, BotConfig.NAV_EYE_HEIGHT, 0))
	end
	self.holdLook = BotBehaviorRules.pickLookPoint(wp.position, visible, self.rand)
	if not self.holdLook then
		return nil
	end
	BotBrain.stats.holds += 1
	return BotConfig.HOLD_MIN + (BotConfig.HOLD_MAX - BotConfig.HOLD_MIN) * self.rng:NextNumber()
end

-- Cette méthode permet de faire réfléchir le bot lorsque Heartbeat passe (avant son mouvement) : perception à
-- intervalle fixe, état choisi, enquête ou repli lancés, regard imposé au mouvement (cible en combat, angle tenu).
function BotBrain.update(self: BotBrain, dt: number)
	local plan = NavPlan.get()
	if not plan then
		return
	end
	local now = os.clock()
	self.perceptionTimer -= dt
	if self.perceptionTimer <= 0 then
		self.perceptionTimer += BotConfig.PERCEPTION_INTERVAL
		self:_perceive(now)
	end

	local previous = self.state
	local state = BotBehaviorRules.nextState({
		state = previous,
		hasTarget = self.targetId ~= nil,
		freshest = self.freshest,
		investigated = self.investigated,
		wantsReplace = self.wantsReplace,
		replaceDone = self.replaceDone,
		investigateDone = self.investigateDone,
	})
	self.state = state
	if state == "replacer" and self.wantsReplace then
		self:_startReplace(plan)
	elseif state == "enqueter" and self.freshest and self.freshest.at > self.investigated then
		self:_startInvestigation(plan, self.freshest)
	end

	-- Regard : cible en combat le temps d'un tir, angle tenu à l'arrêt, sinon où il va
	local gaze = self.motion.gaze
	gaze.lookAt, gaze.aiming = nil, false
	if state == "combattre" and self.targetPos then
		local looking, fire =
			BotBehaviorRules.combatGaze(now - self.seenSince, if self.lastShot then now - self.lastShot else nil)
		if looking then
			gaze.lookAt, gaze.aiming = self.targetPos, true
		end
		if fire and self.targetVisible then
			self.lastShot = now
			BotBrain.stats.shots += 1
			local onFire = BotBrain.onFire
			if onFire and self.targetId then
				onFire(self, self.targetId, self.targetPos)
			end
		end
	elseif self.holdLook and self.motion.navigator:isHolding() then
		gaze.lookAt = self.holdLook
	end
end

-- Cette méthode permet de résumer l'état du bot lorsque l'affichage de debug l'écrit au-dessus de lui.
function BotBrain.describe(self: BotBrain): string
	local destination = self.motion.navigator.destination
	return string.format(
		"%s → %s%s",
		self.state,
		if destination then tostring(destination) else "-",
		if self.targetId then string.format(" (cible %d)", self.targetId) else ""
	)
end

return BotBrain

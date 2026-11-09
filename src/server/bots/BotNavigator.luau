-- Suivi de chemin d'un bot (#140) : choisit une destination (au hasard parmi les points de passage, en attendant les
-- états de #141), cherche le chemin de case à case (NavPlan), puis donne à chaque tick l'intention de mouvement à
-- BotMotion : direction (raccourcie en ligne droite quand les cases sont alignées), saut devant un rebord à monter,
-- grimpe d'une échelle. Un bot qui ne se rapproche plus de sa cible recalcule son chemin ; après NAV_MAX_REPATH
-- essais, l'arête ratée est écartée NAV_BAN_TIME secondes et il change de destination.
-- Après une apparition (lancé depuis le soleil), il attend d'être au sol puis repart de la case la plus proche.
-- Bunny hop (#151) : sur une portion de marche du chemin (tirage BHOP_CHANCE), il ressaute à chaque atterrissage sans
-- friction et, en l'air, vise un point du chemin devant lui (poursuite) à une vitesse réglée par les virages devant
-- et la marche restante (BotMotion strafe, plane ou freine en l'air pour la tenir). Il atterrit normalement quand le
-- saut suivant ne tient plus avant un saut, une échelle ou sa destination.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local BotRules = require(ReplicatedStorage.Shared.BotRules)
local NavRules = require(ReplicatedStorage.Shared.NavRules)
local StepTiming = require(ReplicatedStorage.Shared.StepTiming)
local NavPlan = require(script.Parent.NavPlan)

local BotNavigator = {}
BotNavigator.__index = BotNavigator

export type Intent = {
	wishdir: Vector3, -- direction horizontale voulue (zéro : rester sur place) ; en bhop : cap visé
	jump: boolean,
	climb: boolean, -- grimper si le bot est dans le volume d'une échelle
	airControl: boolean, -- en l'air, viser la cible (saut sur un rebord)
	bhop: boolean, -- série de sauts en cours : air strafe en l'air, pas de friction au saut
	strafeNoise: number, -- écart de strafe du saut en cours (part de la fenêtre de gain, −1 à 1)
	targetSpeed: number, -- en bhop : vitesse visée en l'air (studs/s)
}

export type BotNavigator = typeof(setmetatable(
	{} :: {
		rng: Random,
		destination: number?, -- point de passage visé
		lastWaypoint: number?,
		cells: { number }?,
		points: { Vector3 },
		kinds: { number },
		widths: { number }, -- largeur de passage de chaque case du chemin (studs)
		index: number,
		best: number,
		stalled: number,
		repaths: number,
		hold: number,
		banned: { [number]: number }, -- clé d'arête → fin de la mise à l'écart (os.clock)
		runSpeed: number, -- vitesse de course du bot (arme tenue)
		bhopAllowed: boolean, -- coupé par les états (#141) : combat, angle tenu
		bhopping: boolean,
		bhopRolled: number, -- bout de la dernière portion de marche déjà tirée (un tirage par portion)
		zigzagSide: number, -- 1 ou −1 : côté du décalage de cap du saut en cours
		strafeNoise: number,
		missDelay: number, -- saut raté : temps restant au sol avant de ressauter
	},
	BotNavigator
))

-- Bilan de tous les bots depuis le démarrage (debug Studio : NavDebug l'affiche dans la console)
-- passed : arêtes franchies par type ; bhopRuns / bhopJumps : séries de sauts commencées, sauts enchaînés ;
-- bhopTopSpeed : plus haute vitesse atteinte en bhop
BotNavigator.stats = { reached = 0, banned = 0, passed = { 0, 0, 0, 0 }, bhopRuns = 0, bhopJumps = 0, bhopTopSpeed = 0 }

local IDLE: Intent = {
	wishdir = Vector3.zero,
	jump = false,
	climb = false,
	airControl = false,
	bhop = false,
	strafeNoise = 0,
	targetSpeed = 0,
}

-- Cette méthode permet de créer le suivi de chemin d'un bot lorsqu'il apparaît (runSpeed : sa vitesse de course).
function BotNavigator.new(rng: Random, runSpeed: number): BotNavigator
	return setmetatable({
		runSpeed = runSpeed,
		bhopAllowed = true,
		bhopping = false,
		bhopRolled = 0,
		zigzagSide = 1,
		strafeNoise = 0,
		missDelay = 0,
		rng = rng,
		destination = nil,
		lastWaypoint = nil,
		cells = nil,
		points = {},
		kinds = {},
		widths = {},
		index = 1,
		best = math.huge,
		stalled = 0,
		repaths = 0,
		hold = 0,
		banned = {},
	}, BotNavigator)
end

-- Cette méthode permet de lire le chemin restant lorsqu'un affichage de debug le dessine (nil sans chemin).
function BotNavigator.remainingPath(self: BotNavigator): { Vector3 }?
	if not self.cells then
		return nil
	end
	return table.move(self.points, math.max(self.index - 1, 1), #self.points, 1, {})
end

-- Cette méthode permet de lister les arêtes écartées encore actives lorsqu'un chemin est cherché.
function BotNavigator._activeBans(self: BotNavigator): { [number]: boolean }
	local now = os.clock()
	local active = {}
	for key, untilTime in self.banned do
		if untilTime > now then
			active[key] = true
		else
			self.banned[key] = nil
		end
	end
	return active
end

-- Cette méthode permet de calculer un chemin de la case sous les pieds vers la destination lorsque le bot n'en a pas
-- (nouvelle destination tirée si besoin) ; renvoie false si aucun chemin n'est possible pour l'instant.
function BotNavigator._plan(self: BotNavigator, plan: NavPlan.Plan, foot: Vector3): boolean
	local start = NavPlan.nearestCell(plan, foot, BotConfig.NAV_NEAREST_RADIUS)
	if not start then
		return false
	end
	local bans = self:_activeBans()
	for _ = 1, 4 do
		if not self.destination then
			self.destination = NavPlan.randomWaypoint(plan, self.rng, self.lastWaypoint)
		end
		local wp = self.destination and plan.waypoints[self.destination]
		if not wp then
			return false
		end
		local cells = NavPlan.findPath(plan, start, wp.cell, bans)
		if cells then
			local positions, out, outKind = plan.graph.positions, plan.graph.out, plan.graph.outKind
			local points, kinds, widths = {}, {}, {}
			for i, cell in cells do
				points[i] = positions[cell]
				widths[i] = (plan.clearance[cell] or 0) * plan.grid
				kinds[i] = NavRules.WALK
				if i > 1 then
					local prev = cells[i - 1]
					local k = table.find(out[prev], cell)
					kinds[i] = if k then outKind[prev][k] else NavRules.WALK
				end
			end
			self.cells, self.points, self.kinds, self.widths = cells, points, kinds, widths
			self.index = math.min(2, #cells)
			self.best, self.stalled = math.huge, 0
			self.bhopping, self.bhopRolled = false, 0
			return true
		end
		self.destination = nil -- injoignable avec les arêtes écartées : autre tirage
	end
	return false
end

-- Cette méthode permet d'oublier le chemin courant lorsqu'il faut le recalculer (gêne, chute hors du trajet).
function BotNavigator._dropPath(self: BotNavigator)
	self.cells = nil
	self.best, self.stalled = math.huge, 0
	self.bhopping = false
end

-- Cette méthode permet d'autoriser ou d'interdire le bunny hop lorsque l'état du bot change (#141 : coupé en combat
-- ou quand il tient un angle) ; une série en cours s'arrête au prochain atterrissage.
function BotNavigator.setBhopAllowed(self: BotNavigator, allowed: boolean)
	self.bhopAllowed = allowed
end

-- Cette méthode permet d'avancer dans le chemin pendant une série de sauts lorsque le bot le survole : les cases sont
-- passées selon l'avancée le long du chemin (NavRules.advanceAlong), hauteur ignorée.
function BotNavigator._advance(self: BotNavigator, foot: Vector3)
	local last = NavRules.walkStretchEnd(self.points, self.kinds, self.index)
	local nextIndex = NavRules.advanceAlong(foot, self.points, self.index, last)
	if nextIndex > self.index then
		BotNavigator.stats.passed[NavRules.WALK] += nextIndex - self.index
		self.index = nextIndex
		self.best, self.stalled, self.repaths = math.huge, 0, 0
	end
end

-- Cette méthode permet de lancer le saut suivant d'une série lorsque le bot est au sol : côté du zigzag changé (le
-- plus souvent) et écart de strafe tiré pour ce saut.
function BotNavigator._nextHop(self: BotNavigator)
	if self.rng:NextNumber() < BotConfig.BHOP_ZIGZAG_FLIP then
		self.zigzagSide = -self.zigzagSide
	end
	local noise = BotConfig.BHOP_STRAFE_NOISE
	self.strafeNoise = if noise > 0 then self.rng:NextNumber(-noise, noise) else 0
	BotNavigator.stats.bhopJumps += 1
end

-- Cette méthode permet de décider du bunny hop du tick lorsque le bot suit une marche : renvoie l'intention de bhop
-- (point du chemin visé, saut au sol, vitesse visée en l'air), ou nil pour un pas normal. Au sol, une série continue
-- si le saut suivant tient dans la marche restante, et commence après un tirage par portion de marche.
function BotNavigator._bhop(
	self: BotNavigator,
	foot: Vector3,
	grounded: boolean,
	speed: number,
	verticalSpeed: number
): Intent?
	if not BotConfig.BHOP_ENABLED then
		return nil
	end
	local points = self.points
	local last = NavRules.walkStretchEnd(points, self.kinds, self.index)
	local remaining = NavRules.distanceAlong(foot, points, self.index, last)
	local jump = false
	if grounded and self.missDelay <= 0 then
		if self.bhopping then
			-- Atterrissage : ressauter si le saut suivant tient avant la fin de la marche, sinon atterrir normalement
			if not (self.bhopAllowed and BotRules.keepBhopping(remaining, speed)) then
				self.bhopping = false
				return nil
			end
			if self.rng:NextNumber() < BotConfig.BHOP_MISS_CHANCE then
				self.missDelay = BotConfig.BHOP_MISS_DELAY
			else
				self:_nextHop()
				jump = true
			end
		elseif
			self.bhopAllowed
			and last > self.bhopRolled
			and remaining >= BotConfig.BHOP_MIN_RUN
			and BotRules.keepBhopping(remaining, speed)
		then
			-- Nouvelle portion de marche : un seul tirage pour toute la portion
			self.bhopRolled = last
			if self.rng:NextNumber() >= BotConfig.BHOP_CHANCE then
				return nil
			end
			self.bhopping = true
			BotNavigator.stats.bhopRuns += 1
			self:_nextHop()
			jump = true
		else
			return nil
		end
	elseif not self.bhopping then
		return nil
	end

	-- Poursuite : point du chemin à vitesse × BHOP_LOOK_TIME devant, décalé du côté du zigzag
	local look = math.max(BotConfig.BHOP_LOOK_MIN, speed * BotConfig.BHOP_LOOK_TIME)
	local aim = NavRules.pointAlong(foot, points, self.index, last, look)
	local flat = Vector3.new(aim.X - foot.X, 0, aim.Z - foot.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	if grounded then
		-- Ressaut sans friction, ou saut raté : au sol avec friction jusqu'à la fin du retard
		return {
			wishdir = dir,
			jump = jump,
			climb = false,
			airControl = false,
			bhop = jump,
			strafeNoise = self.strafeNoise,
			targetSpeed = 0,
		}
	end
	local horizon = speed * BotConfig.BHOP_BRAKE_TIME + BotConfig.BHOP_LOOK_MIN
	local corner = NavRules.cornerSpeed(foot, points, self.widths, self.index, last, horizon, StepTiming.TICK)
	BotNavigator.stats.bhopTopSpeed = math.max(BotNavigator.stats.bhopTopSpeed, speed)
	return {
		wishdir = BotRules.rotateXZ(dir, self.zigzagSide * BotConfig.BHOP_ZIGZAG_ANGLE),
		jump = false,
		climb = false,
		airControl = true,
		bhop = true,
		strafeNoise = self.strafeNoise,
		targetSpeed = BotRules.bhopTargetSpeed(remaining, corner, self.runSpeed, BotRules.timeToLand(verticalSpeed)),
	}
end

-- Cette méthode permet de donner l'intention de mouvement du tick lorsque BotMotion joue un tick : foot = sous les
-- pieds, speed = vitesse horizontale, verticalSpeed = vitesse verticale. Sans plan (pas encore construit), le bot
-- attend.
function BotNavigator.update(
	self: BotNavigator,
	plan: NavPlan.Plan?,
	foot: Vector3,
	grounded: boolean,
	speed: number,
	verticalSpeed: number,
	dt: number
): Intent
	if not plan then
		return IDLE
	end
	if self.hold > 0 then
		self.hold -= dt
		return IDLE
	end
	if not self.cells then
		-- En l'air (lancement, chute) : on attend l'atterrissage pour repartir de la case la plus proche
		if not grounded or not self:_plan(plan, foot) then
			return IDLE
		end
	end

	local points, kinds = self.points, self.kinds
	if self.missDelay > 0 then
		self.missDelay -= dt
	end
	if self.bhopping and kinds[self.index] == NavRules.WALK then
		self:_advance(foot)
	end
	while self.index <= #points and NavRules.reached(foot, points[self.index]) do
		local passed = BotNavigator.stats.passed
		passed[kinds[self.index]] += 1
		self.index += 1
		self.best, self.stalled, self.repaths = math.huge, 0, 0
	end
	if self.index > #points then
		-- Arrivé : courte pause, puis destination suivante
		self.lastWaypoint = self.destination
		self.destination = nil
		BotNavigator.stats.reached += 1
		self:_dropPath()
		self.hold = BotConfig.NAV_HOLD_MIN + (BotConfig.NAV_HOLD_MAX - BotConfig.NAV_HOLD_MIN) * self.rng:NextNumber()
		return IDLE
	end

	local kind = kinds[self.index]
	local goal = points[self.index]
	-- Tombé sous le trajet (rebord raté) : chemin recalculé depuis là où il est
	if grounded and kind ~= NavRules.LADDER and goal.Y - foot.Y > BotConfig.NAV_JUMP_UP_MAX + 1 then
		self:_dropPath()
		return IDLE
	end

	local hop = if kind == NavRules.WALK then self:_bhop(foot, grounded, speed, verticalSpeed) else nil
	if not hop then
		self.bhopping = false
	end

	local targetIndex = if kind == NavRules.WALK
		then NavRules.lookAhead(foot, points, kinds, self.index)
		else self.index
	local target = points[targetIndex]
	local flat = Vector3.new(target.X - foot.X, 0, target.Z - foot.Z)
	local wishdir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero

	local jump = false
	if kind == NavRules.JUMP and grounded and self.index > 1 then
		local ledge = (points[self.index - 1] + goal) / 2
		local toLedge = Vector3.new(ledge.X - foot.X, 0, ledge.Z - foot.Z).Magnitude
		jump = NavRules.shouldJump(toLedge, speed)
	end

	-- En bhop, la gêne se mesure à l'horizontale (pieds au-dessus des cases pendant les sauts)
	local dist = if self.bhopping
		then Vector3.new(goal.X - foot.X, 0, goal.Z - foot.Z).Magnitude
		else (goal - foot).Magnitude
	self.best, self.stalled = NavRules.progress(self.best, self.stalled, dist, dt)
	if self.stalled >= BotConfig.NAV_STUCK_TIME then
		self.repaths += 1
		if self.repaths >= BotConfig.NAV_MAX_REPATH and self.cells and self.index > 1 then
			-- Arête ratée plusieurs fois : écartée un moment, et autre destination
			local cells = self.cells :: { number }
			local key = NavRules.edgeKey(cells[self.index - 1], cells[self.index])
			self.banned[key] = os.clock() + BotConfig.NAV_BAN_TIME
			BotNavigator.stats.banned += 1
			warn(
				string.format(
					"[Nav] arête %s ratée (%s → %s), écartée %d s",
					NavRules.KIND_NAMES[kind],
					tostring(points[self.index - 1]),
					tostring(goal),
					BotConfig.NAV_BAN_TIME
				)
			)
			self.repaths = 0
			self.destination = nil
		end
		self:_dropPath()
		return IDLE
	end

	if hop then
		return hop
	end
	return {
		wishdir = wishdir,
		jump = jump,
		climb = kind == NavRules.LADDER,
		airControl = kind == NavRules.JUMP or kind == NavRules.LADDER,
		bhop = false,
		strafeNoise = 0,
		targetSpeed = 0,
	}
end

return BotNavigator

-- Bots du round (#133), étapes 3/9 (#139) et 4/9 (#140) : un bot est un participant sans Player (Participants.addBot) dont le
-- personnage est construit par le serveur (rig de référence, skin commun, AWP), placé au sol comme un joueur
-- (SpawnManager.place), déplacé par BotMotion et branché comme un joueur sur l'arme 3P, la mort et le corps (onCharacter).
-- Il réapparaît RESPAWN_DELAY après sa mort, et au début de chaque round, tant que le round est actif.
-- Le plan de navigation de la map est construit au démarrage (NavPlan) ; chaque bot le suit (BotNavigator), guidé par
-- son comportement (BotBrain, #141 : perception, mémoire, états), qui entend les tirs relayés par hearShot.
-- Combat (#143) : armes du bot (BotArsenal), touches validées et appliquées par le serveur comme celles d'un joueur
-- (deps.hitscan, deps.melee), tirs entendus par les autres bots.
-- Population (#144) : les bots comblent les places vides (BotPopulationRules), un par un à l'arrivée d'un joueur, hors duel.
-- Outillage Studio : l'attribut Workspace DebugBots fixe le nombre de bots (nombre, "+", "-", 0 pour tous les retirer,
-- nil ou "auto" pour la population automatique), DebugBotsFreeze fige les bots, DebugBotsPassive les rend passifs, DebugNav affiche le plan (NavDebug).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local BotCharacters = require(ReplicatedStorage.Shared.BotCharacters)
local BotCombatRules = require(ReplicatedStorage.Shared.BotCombatRules)
local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local BotPopulationRules = require(ReplicatedStorage.Shared.BotPopulationRules)
local BotRules = require(ReplicatedStorage.Shared.BotRules)
local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local CharacterConfig = require(ReplicatedStorage.Shared.CharacterConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapGeometry = require(ReplicatedStorage.Shared.MapGeometry)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local Participants = require(ServerScriptService.Server.Participants)
local BotArsenal = require(script.Parent.BotArsenal)
local BotBrain = require(script.Parent.BotBrain)
local BotMotion = require(script.Parent.BotMotion)
local NavDebug = require(script.Parent.NavDebug)
local NavPlan = require(script.Parent.NavPlan)

type Participant = Participants.Participant

export type Deps = {
	-- Branchement commun joueur/bot du personnage (arme 3P, mort, corps), cf. init.server
	onCharacter: (Participant, Model, () -> ()) -> (),
	-- Placement à l'apparition (point au sol loin des ennemis, protection ; SpawnManager.place)
	place: (Model) -> (),
	-- Publication de la position aux clients (CharacterSync.relayBot)
	relay: (Model, BasePart, CFrame) -> (),
	-- Touches d'un bot, validées et appliquées comme celles d'un joueur (tireur, personnage visé, partie touchée) ;
	-- renvoient "hit", "kill", ou nil si la touche est refusée ou sans effet
	hitscan: (Participant, Model, BasePart) -> ("hit" | "kill")?,
	melee: (Participant, Model) -> ("hit" | "kill")?,
	-- Tir au fusil parti (touché ou manqué), relayé aux joueurs pour le son (#156) : tireur, origine, direction
	shotFired: (Participant, Vector3, Vector3) -> boolean,
	-- Oubli de l'état de combat d'un participant retiré (cadence, equip, chargeur, relais des tirs ; #218)
	forget: (Participant) -> (),
	roundManager: {
		isActive: () -> boolean,
		addParticipant: (Participant) -> (),
		removeParticipant: (Participant) -> (),
	},
}

type Bot = {
	participant: Participant,
	character: Model?,
	motion: BotMotion.BotMotion?,
	brain: BotBrain.BotBrain?,
	diedAt: number, -- os.clock() de la dernière mort (-inf : jamais mort, apparaît dès que le round est actif)
	frozen: boolean,
}

local BotManager = {}

local deps: Deps
local bots: { Bot } = {}
local seeThrough: { Instance } = {} -- murs d'air et grillages de la map jouée (n'arrêtent ni la vue ni les tirs, #292)
local debugCount: number? = nil -- nombre de bots fixé par DebugBots (nil : population automatique)
local pauseCount = 0 -- runs de DebugPlaytest en cours (population suspendue, aucun bot)
local passive = false -- DebugBotsPassive : les bots (présents et ajoutés ensuite) ne tirent pas sur les humains

-- Cette méthode permet de lire l'état de gel voulu par le debug lorsqu'un bot est créé : l'attribut DebugBotsFreeze
-- (Studio uniquement), pour qu'un bot ajouté après la pose de l'attribut soit figé comme les autres.
local function debugFrozen(): boolean
	return RunService:IsStudio() and workspace:GetAttribute(BotConfig.DEBUG_FREEZE_ATTRIBUTE) == true
end

-- Cette méthode permet de lister les autres participants en vie lorsqu'un bot regarde autour de lui ou cherche un
-- humain (biais) : id, humain ou bot, personnage, instant d'apparition (délai de grâce).
local function aliveOthers(selfId: number): { { id: number, isHuman: boolean, character: Model, spawnedAt: number? } }
	local list = {}
	for _, participant in Participants.all() do
		local char = Participants.characterOf(participant)
		local humanoid = char and char.Parent and char:FindFirstChildOfClass("Humanoid")
		if participant.id ~= selfId and humanoid and humanoid.Health > 0 then
			local spawnedAt = (char :: Model):GetAttribute(BotCombatRules.SPAWNED_AT_ATTRIBUTE)
			table.insert(list, {
				id = participant.id,
				isHuman = not participant.isBot,
				character = char :: Model,
				spawnedAt = if type(spawnedAt) == "number" then spawnedAt else nil,
			})
		end
	end
	return list
end

-- Cette méthode permet de compter les bots qui vont vers chaque point lorsqu'un bot choisit sa destination (malus :
-- les bots se répartissent sur la map).
local function claimedDestinations(selfId: number): { [number]: number }
	local claimed = {}
	for _, bot in bots do
		local destination = bot.motion and bot.motion.navigator.destination
		if destination and bot.participant.id ~= selfId then
			claimed[destination] = (claimed[destination] or 0) + 1
		end
	end
	return claimed
end

-- Cette méthode permet de construire un personnage de bot hors jeu lorsqu'il doit apparaître : copie du rig de
-- référence sans scripts (sinon rig généré), racine ancrée et déplacée à la main comme celle d'un joueur.
local function buildCharacter(name: string): Model?
	local template = CharacterAppearance.getTemplate()
	local model: Model
	if template then
		local wasArchivable = template.Archivable
		template.Archivable = true
		model = template:Clone()
		template.Archivable = wasArchivable
	else
		local ok, generated = pcall(function()
			return Players:CreateHumanoidModelFromDescription(
				CharacterAppearance.buildDescription(),
				CharacterConfig.RIG_TYPE
			)
		end)
		if not ok then
			warn("[BotManager] génération du rig impossible : " .. tostring(generated))
			return nil
		end
		model = generated
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		model:Destroy()
		warn("[BotManager] rig sans Humanoid ni HumanoidRootPart")
		return nil
	end
	model.Name = name
	-- Même étiquette qu'un joueur (décision 5 de #133 : rien ne trahit un bot en jeu)
	humanoid.DisplayName = name
	-- Comme le client pour son joueur : pas de physique Humanoid, la racine ancrée est déplacée par BotMotion
	root.Anchored = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoJumpEnabled = false
	-- PlatformStanding comme le joueur (init.client) ; la machine d'état reste active, sinon Died ne part pas
	humanoid.PlatformStand = true
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	CharacterAppearance.apply(model)
	return model
end

-- Cette méthode permet de retirer le personnage d'un bot et d'arrêter son mouvement lorsqu'il a disparu (corps
-- détruit après sa mort, fin de round) ou que le bot est retiré.
local function dropCharacter(bot: Bot)
	bot.motion = nil
	bot.brain = nil
	local char = bot.character
	bot.character = nil
	Participants.setCharacter(bot.participant, nil)
	if char and char.Parent then
		char:Destroy()
	end
end

-- Cette méthode permet de faire apparaître un bot lorsque le round est actif et que son délai de réapparition est
-- passé : personnage construit, inscrit, branché, mis en jeu puis placé au sol (SpawnManager.place).
local function spawnBot(bot: Bot)
	local char = buildCharacter(bot.participant.name)
	if not char then
		bot.diedAt = os.clock() -- nouvel essai après RESPAWN_DELAY, sans boucle à chaque frame
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	bot.character = char
	Participants.setCharacter(bot.participant, char)
	BotCharacters.mark(char, bot.participant.id)
	deps.roundManager.addParticipant(bot.participant)
	-- Réapparition gérée ici (diedAt), pas par le rappel du round : un bot réapparaît aussi au round suivant
	deps.onCharacter(bot.participant, char, function() end)
	humanoid.Died:Connect(function()
		bot.diedAt = os.clock()
		bot.motion = nil
		bot.brain = nil
	end)
	char.Parent = workspace
	deps.place(char)
	local motion = BotMotion.new(char, root, humanoid, BotCombatRules.RIFLE, deps.relay)
	motion:setFrozen(bot.frozen)
	bot.motion = motion
	local participant = bot.participant
	-- Armes : fusil en main (modèle 3P attaché par onCharacter), couteau rangé ; touches validées par le serveur
	local arsenal = BotArsenal.new(char, function(target: Model, hitPart: BasePart?)
		local outcome = if hitPart then deps.hitscan(participant, target, hitPart) else deps.melee(participant, target)
		if outcome then
			BotBrain.stats.hits += 1
			if outcome == "kill" then
				BotBrain.stats.kills += 1
			end
		end
	end, function(weaponName: string)
		motion:setWeapon(weaponName)
	end, function(origin: Vector3, direction: Vector3)
		return deps.shotFired(participant, origin, direction)
	end)
	local id = participant.id
	bot.brain = BotBrain.new({
		id = id,
		others = function()
			return aliveOthers(id)
		end,
		claimed = claimedDestinations,
		seeThrough = seeThrough,
		onShot = function(position: Vector3)
			BotManager.hearShot(participant, position)
		end,
		passive = function()
			return passive
		end,
	}, char, motion, arsenal)
	-- Première position publiée tout de suite : pas d'attente du premier envoi pour apparaître chez les clients
	deps.relay(char, root, root.CFrame)
end

-- Repères de coût (#145) : apparition, cerveau (perception, chemin) et mouvement, sous le repère « srv bots », pour
-- savoir d'où vient un pic de frame serveur.
local timedBrain: (BotBrain.BotBrain, number) -> () = PerfMarkers.wrap(
	"bots cerveau",
	function(brain: BotBrain.BotBrain, dt: number)
		brain:update(dt)
	end
)
local timedMotion: (BotMotion.BotMotion, number) -> () = PerfMarkers.wrap(
	"bots mouvement",
	function(motion: BotMotion.BotMotion, dt: number)
		motion:update(dt)
	end
)

-- Cette méthode permet de faire vivre les bots lorsque Heartbeat passe : mouvement des bots en jeu, personnages
-- disparus oubliés, apparition des bots morts depuis RESPAWN_DELAY quand le round est actif.
local function step(dt: number)
	local active = deps.roundManager.isActive()
	local now = os.clock()
	for _, bot in bots do
		local char = bot.character
		if char and not char.Parent then
			dropCharacter(bot)
		end
		if bot.motion then
			if bot.brain and not bot.frozen then
				timedBrain(bot.brain, dt)
			end
			timedMotion(bot.motion, dt)
		elseif not bot.character and active and now - bot.diedAt >= GameConfig.RESPAWN_DELAY then
			spawnBot(bot)
		end
	end
end

-- Cette méthode permet d'ajouter un bot au jeu lorsqu'on en demande un de plus ; il apparaît dès que le round est
-- actif. nil au-delà de MAX_BOTS.
function BotManager.add(): Participant?
	if #bots >= BotConfig.MAX_BOTS then
		return nil
	end
	local taken = {}
	for _, bot in bots do
		taken[bot.participant.name] = true
	end
	local participant = Participants.addBot(BotRules.pickName(taken))
	table.insert(bots, {
		participant = participant,
		character = nil,
		motion = nil,
		brain = nil,
		diedAt = -math.huge,
		frozen = debugFrozen(),
	})
	deps.roundManager.addParticipant(participant)
	return participant
end

-- Cette méthode permet de retirer un bot du jeu lorsqu'on en demande un de moins : le bot d'index donné (le dernier par
-- défaut), personnage détruit, sorti du classement et du registre, état de combat oublié (#218 : sans cela le
-- Validator et le relais des tirs gardent une entrée par bot retiré).
function BotManager.removeAt(index: number?)
	local bot = table.remove(bots, index or #bots)
	if not bot then
		return
	end
	dropCharacter(bot)
	deps.forget(bot.participant)
	deps.roundManager.removeParticipant(bot.participant)
	Participants.remove(bot.participant)
end

-- Cette méthode permet de faire entendre un tir aux bots lorsqu'un participant tire (position du tireur) ; chacun le
-- perçoit selon sa distance (BotBrain : rayon et flou de l'ouïe).
function BotManager.hearShot(shooter: Participant, position: Vector3)
	for _, bot in bots do
		if bot.brain then
			bot.brain:hearShot(shooter.id, position, not shooter.isBot)
		end
	end
end

-- Cette méthode permet de prévenir un bot qu'il vient de tuer lorsqu'une mort est attribuée (il se replace).
function BotManager.notifyKill(killer: Participant)
	for _, bot in bots do
		if bot.participant == killer and bot.brain then
			bot.brain:notifyKill()
		end
	end
end

-- Cette méthode permet de figer ou relâcher tous les bots lorsqu'un outil de debug le demande.
function BotManager.setFrozen(frozen: boolean)
	for _, bot in bots do
		bot.frozen = frozen
		if bot.motion then
			bot.motion:setFrozen(frozen)
		end
	end
end

-- Cette méthode permet de lire le nombre de bots en jeu lorsqu'un outil de debug le demande.
function BotManager.count(): number
	return #bots
end

-- Cette méthode permet de lire le nombre de bots en jeu (personnage vivant) lorsque la sonde de performance écrit son bilan.
function BotManager.aliveCount(): number
	local alive = 0
	for _, bot in bots do
		if bot.motion then
			alive += 1
		end
	end
	return alive
end

-- Cette méthode permet de lister les bots comme candidats au retrait lorsque la population est trop grande : en jeu ou
-- non, en duel ou non, temps depuis leur dernier contact avec une cible.
local function removalCandidates(): { BotPopulationRules.Candidate }
	local now = os.clock()
	local list = {}
	for index, bot in bots do
		local brain = bot.brain
		local sinceContact = if brain then now - brain.lastContact else math.huge
		table.insert(list, {
			index = index,
			alive = bot.motion ~= nil,
			inDuel = brain ~= nil and BotPopulationRules.isInDuel(brain.state, sinceContact),
			sinceContact = sinceContact,
		})
	end
	return list
end

-- Cette méthode permet d'ajuster le nombre de bots lorsque la population change (joueur arrivé ou parti, commande de
-- debug, pause) : tous les manquants arrivent d'un coup ; les surnuméraires partent un par un, hors duel (un retrait
-- reporté tant que tous combattent), ou tous d'un coup si la demande est forcée (debug, pause).
local function adjustPopulation()
	local forced = debugCount ~= nil or pauseCount > 0
	local wanted = debugCount or BotPopulationRules.wantedBots(#Players:GetPlayers(), pauseCount > 0)
	while #bots < wanted do
		if not BotManager.add() then
			break
		end
	end
	while #bots > wanted do
		local index = BotPopulationRules.pickRemoval(removalCandidates(), forced)
		if not index then
			break -- tous en duel : on réessaie au prochain passage
		end
		BotManager.removeAt(index)
		if not forced then
			break
		end
	end
end

-- Cette méthode permet de suspendre la population automatique lorsqu'un run de DebugPlaytest démarre (tous les bots
-- sont retirés, test déterministe), et de la rétablir quand il finit.
function BotManager.setPaused(paused: boolean)
	pauseCount = math.max(pauseCount + (if paused then 1 else -1), 0)
	adjustPopulation()
end

-- Cette méthode permet de lire la commande de debug Studio lorsque l'attribut DebugBots change : nombre fixe, "+" ou
-- "-", sinon (nil, "auto") retour à la population automatique ; "+" et "-" sont remplacés par le nombre obtenu.
local function applyDebugCommand()
	local value = workspace:GetAttribute(BotConfig.DEBUG_ATTRIBUTE)
	debugCount = BotPopulationRules.debugCommand(value, #bots)
	if type(value) == "string" and debugCount ~= nil then
		workspace:SetAttribute(BotConfig.DEBUG_ATTRIBUTE, debugCount) -- relance applyDebugCommand
		return
	end
	adjustPopulation()
end

-- Cette méthode permet de figer ou relâcher les bots lorsque l'attribut DebugBotsFreeze change (Studio).
local function applyDebugFreeze()
	BotManager.setFrozen(workspace:GetAttribute(BotConfig.DEBUG_FREEZE_ATTRIBUTE) == true)
end

-- Cette méthode permet de rendre les bots passifs ou de les rétablir lorsque l'attribut DebugBotsPassive change
-- (Studio) : ils continuent de se déplacer mais ne tirent plus sur les humains (lu à chaque tir, bots ajoutés compris).
local function applyDebugPassive()
	passive = workspace:GetAttribute(BotConfig.DEBUG_PASSIVE_ATTRIBUTE) == true
end

-- Cette méthode permet d'envoyer tous les bots vers un point lorsque l'attribut DebugBotsGoto change (Studio) : le
-- point de passage le plus proche de la position donnée devient leur destination (rampes de surf #142 comprises).
local function applyDebugGoto()
	local value = workspace:GetAttribute(BotConfig.DEBUG_GOTO_ATTRIBUTE)
	local plan = NavPlan.get()
	if typeof(value) ~= "Vector3" or not plan then
		return
	end
	local waypoint = NavPlan.waypointNear(plan, value)
	if not waypoint then
		return
	end
	for _, bot in bots do
		if bot.motion then
			bot.motion.navigator:pinDestination(waypoint)
		end
	end
end

-- Cette méthode permet de démarrer la gestion des bots lorsque le serveur démarre.
function BotManager.init(dependencies: Deps)
	deps = dependencies
	task.spawn(function()
		local map = MapSelection.waitForActive(30)
		if map then
			seeThrough = MapGeometry.bulletTransparent(map)
			NavPlan.start(map)
		else
			warn("[BotManager] pas de map jouée : pas de plan de navigation, les bots restent sur place")
		end
	end)
	NavDebug.init(function()
		local list = {}
		for _, bot in bots do
			if bot.motion then
				table.insert(list, { navigator = bot.motion.navigator, brain = bot.brain, root = bot.motion.root })
			end
		end
		return list
	end)
	RunService.Heartbeat:Connect(PerfMarkers.wrap("srv bots", step))
	-- Population automatique : bots qui comblent les places vides, réajustée régulièrement (retraits un par un)
	task.spawn(function()
		while true do
			adjustPopulation()
			task.wait(BotConfig.POPULATION_INTERVAL)
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal(BotConfig.DEBUG_ATTRIBUTE):Connect(applyDebugCommand)
		workspace:GetAttributeChangedSignal(BotConfig.DEBUG_FREEZE_ATTRIBUTE):Connect(applyDebugFreeze)
		workspace:GetAttributeChangedSignal(BotConfig.DEBUG_PASSIVE_ATTRIBUTE):Connect(applyDebugPassive)
		workspace:GetAttributeChangedSignal(BotConfig.DEBUG_GOTO_ATTRIBUTE):Connect(applyDebugGoto)
		applyDebugPassive()
		applyDebugFreeze() -- no-op sans bot ; ceux créés ensuite naissent figés (debugFrozen dans add)
		applyDebugCommand()
	end
end

return BotManager

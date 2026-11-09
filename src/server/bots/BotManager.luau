-- Bots du round (#133), étapes 3/9 (#139) et 4/9 (#140) : un bot est un participant sans Player (Participants.addBot) dont le
-- personnage est construit par le serveur (rig de référence, skin commun, AWP), lancé depuis le soleil comme un
-- joueur, déplacé par BotMotion et branché comme un joueur sur l'arme 3P, la mort et le corps (onCharacter).
-- Il réapparaît RESPAWN_DELAY après sa mort, et au début de chaque round, tant que le round est actif.
-- Le plan de navigation de la map est construit au démarrage (NavPlan) ; chaque bot le suit (BotNavigator).
-- Outillage Studio : l'attribut Workspace DebugBots fixe le nombre de bots (0 pour tous les retirer), DebugNav affiche
-- le plan (NavDebug).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPack = game:GetService("StarterPack")
local ServerScriptService = game:GetService("ServerScriptService")

local BotCharacters = require(ReplicatedStorage.Shared.BotCharacters)
local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local BotRules = require(ReplicatedStorage.Shared.BotRules)
local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local CharacterConfig = require(ReplicatedStorage.Shared.CharacterConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local Participants = require(ServerScriptService.Server.Participants)
local BotMotion = require(script.Parent.BotMotion)
local NavDebug = require(script.Parent.NavDebug)
local NavPlan = require(script.Parent.NavPlan)

-- Arme tenue par les bots (décision 4 de #133 : AWP ; le couteau viendra avec le combat, #143)
local BOT_WEAPON = "AWP"

type Participant = Participants.Participant

export type Deps = {
	-- Branchement commun joueur/bot du personnage (arme 3P, mort, corps), cf. init.server
	onCharacter: (Participant, Model, () -> ()) -> (),
	-- Placement à l'apparition (soleil ou sol) ; renvoie la vitesse du lancement
	place: (Model) -> Vector3?,
	-- Publication de la position aux clients (CharacterSync.relayBot)
	relay: (Model, BasePart, CFrame) -> (),
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
	diedAt: number, -- os.clock() de la dernière mort (-inf : jamais mort, apparaît dès que le round est actif)
	frozen: boolean,
}

local BotManager = {}

local deps: Deps
local bots: { Bot } = {}

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

-- Cette méthode permet de donner son arme au bot lorsqu'il apparaît : copie de l'outil du StarterPack, sans scripts
-- (logique d'arme côté client), mise en main ; le modèle 3P est attaché par onCharacter.
local function giveWeapon(char: Model): string?
	local source = StarterPack:FindFirstChild(BOT_WEAPON)
	if not source or not source:IsA("Tool") then
		warn("[BotManager] outil " .. BOT_WEAPON .. " introuvable dans StarterPack")
		return nil
	end
	local tool = source:Clone()
	for _, inst in tool:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		end
	end
	tool.Parent = char
	return BOT_WEAPON
end

-- Cette méthode permet de retirer le personnage d'un bot et d'arrêter son mouvement lorsqu'il a disparu (corps
-- détruit après sa mort, fin de round) ou que le bot est retiré.
local function dropCharacter(bot: Bot)
	bot.motion = nil
	local char = bot.character
	bot.character = nil
	Participants.setCharacter(bot.participant, nil)
	if char and char.Parent then
		char:Destroy()
	end
end

-- Cette méthode permet de faire apparaître un bot lorsque le round est actif et que son délai de réapparition est
-- passé : personnage construit, inscrit, branché, mis en jeu puis lancé depuis le soleil.
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
	end)
	char.Parent = workspace
	local weaponName = giveWeapon(char)
	local launchVelocity = deps.place(char)
	local motion = BotMotion.new(char, root, humanoid, launchVelocity, weaponName, deps.relay)
	motion:setFrozen(bot.frozen)
	bot.motion = motion
	-- Première position publiée tout de suite : pas d'attente du premier envoi pour apparaître chez les clients
	deps.relay(char, root, root.CFrame)
end

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
			bot.motion:update(dt)
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
	table.insert(
		bots,
		{ participant = participant, character = nil, motion = nil, diedAt = -math.huge, frozen = false }
	)
	deps.roundManager.addParticipant(participant)
	return participant
end

-- Cette méthode permet de retirer un bot du jeu lorsqu'on en demande un de moins : le dernier ajouté, personnage
-- détruit, sorti du classement et du registre.
function BotManager.removeLast()
	local bot = table.remove(bots)
	if not bot then
		return
	end
	dropCharacter(bot)
	deps.roundManager.removeParticipant(bot.participant)
	Participants.remove(bot.participant)
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

-- Cette méthode permet d'ajuster le nombre de bots à l'attribut de debug lorsqu'il change (Studio).
local function applyDebugCount()
	local wanted = BotRules.requestedCount(workspace:GetAttribute(BotConfig.DEBUG_ATTRIBUTE))
	while #bots < wanted do
		if not BotManager.add() then
			break
		end
	end
	while #bots > wanted do
		BotManager.removeLast()
	end
end

-- Cette méthode permet de démarrer la gestion des bots lorsque le serveur démarre.
function BotManager.init(dependencies: Deps)
	deps = dependencies
	task.spawn(function()
		local map = MapSelection.waitForActive(30)
		if map then
			NavPlan.start(map)
		else
			warn("[BotManager] pas de map jouée : pas de plan de navigation, les bots restent sur place")
		end
	end)
	NavDebug.init(function()
		local list = {}
		for _, bot in bots do
			if bot.motion then
				table.insert(list, bot.motion.navigator)
			end
		end
		return list
	end)
	RunService.Heartbeat:Connect(PerfMarkers.wrap("srv bots", step))
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal(BotConfig.DEBUG_ATTRIBUTE):Connect(applyDebugCount)
		applyDebugCount()
	end
end

return BotManager

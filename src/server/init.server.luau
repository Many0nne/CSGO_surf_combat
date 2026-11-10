local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MapSelection = require(Shared:WaitForChild("MapSelection"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))
local MemoryTracker = require(Shared:WaitForChild("MemoryTracker"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))
local ParticipantRules = require(Shared:WaitForChild("ParticipantRules"))

local SpawnManager = require(script.SpawnManager)
local RoundManager = require(script.RoundManager)
local StatsStore = require(script.StatsStore)
local SettingsStore = require(script.SettingsStore)
local Validator = require(script.Validator)
local Participants = require(script.Participants)
local FeedbackService = require(script.FeedbackService)
local DebugPlaytest = require(script.DebugPlaytest)
local KillZone = require(script.KillZone)
local CharacterSync = require(script.CharacterSync)
local BotManager = require(script.bots.BotManager)
local ServerPerf = require(script.ServerPerf)

-- Spawn contrôlé : on gère LoadCharacter nous-mêmes
Players.CharacterAutoLoads = false

-- ── Création des RemoteEvents ──────────────────────────────────────────────

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

local N = NetworkProtocol.Names
local meleeRmt = makeRemote(N.MELEE_DAMAGE)
local hitscanRmt = makeRemote(N.HITSCAN_DAMAGE)
local hitConfirmRmt = makeRemote(N.HIT_CONFIRM)
local spawnRmt = makeRemote(N.REQUEST_SPAWN)
local roundStateRmt = makeRemote(N.ROUND_STATE)
local scoreUpdateRmt = makeRemote(N.SCORE_UPDATE)
local roundResultRmt = makeRemote(N.ROUND_RESULT)
local playerDiedRmt = makeRemote(N.PLAYER_DIED)
local sendFeedbackRmt = makeRemote(N.SEND_FEEDBACK)
local feedbackAckRmt = makeRemote(N.FEEDBACK_ACK)
local weaponActionRmt = makeRemote(N.WEAPON_ACTION)
local saveSettingsRmt = makeRemote(N.SAVE_SETTINGS)
local getSettingsRmt = Instance.new("RemoteFunction")
getSettingsRmt.Name = N.GET_SETTINGS
getSettingsRmt.Parent = ReplicatedStorage
-- Non fiable : un paquet de position perdu est remplacé par le suivant (cf. CharacterSync)
local characterSyncRmt = Instance.new("UnreliableRemoteEvent")
characterSyncRmt.Name = N.CHARACTER_SYNC
characterSyncRmt.Parent = ReplicatedStorage

-- ── Initialisation des sous-systèmes ──────────────────────────────────────

StatsStore.init()
SettingsStore.init(getSettingsRmt, saveSettingsRmt)
FeedbackService.init(sendFeedbackRmt, feedbackAckRmt)

RoundManager.init({
	roundState = roundStateRmt,
	scoreUpdate = scoreUpdateRmt,
	roundResult = roundResultRmt,
	playerDied = playerDiedRmt,
})

-- ── Gestion du cycle de vie des personnages ────────────────────────────────

-- ── Arme 3e personne (#5) ─────────────────────────────────────────────────

-- Outil dont le modèle 3P est actuellement attaché, par personnage.
local equippedTools: { [Model]: Tool } = setmetatable({}, { __mode = "k" }) :: any
local lastWeaponAction: { [Player]: number } = {}
local WEAPON_ACTION_MIN_INTERVAL = 0.05
-- Délai (s) entre la mort et la destruction du personnage, le temps que les clients le clonent en ragdoll (#102)
local CORPSE_HANDOFF_DELAY = 0.3

-- Cette méthode permet d'attacher le modèle 3P lorsqu'un outil arrive dans le personnage (équipement) ;
-- les pièces propres de l'outil sont masquées pour ne pas doubler l'arme collée à la main.
local function onToolEquipped(char: Model, tool: Tool)
	local weaponName = tool:GetAttribute("WeaponName") or tool.Name
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	local gun = WeaponThirdPerson.attach(
		char,
		weaponName,
		if type(viewmodelName) == "string" and viewmodelName ~= "" then viewmodelName else weaponName
	)
	if not gun then
		equippedTools[char] = nil
		return
	end
	equippedTools[char] = tool
	for _, inst in tool:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Transparency = 1
		end
	end
end

-- Cette méthode permet de suivre l'équipement d'armes d'un personnage joueur lorsqu'il spawn :
-- modèle 3P attaché à l'équipement, retiré quand l'outil correspondant quitte le personnage.
local function trackWeapon3P(char: Model)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			onToolEquipped(char, child)
		end
	end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(char, child)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and equippedTools[char] == child then
			equippedTools[char] = nil
			WeaponThirdPerson.detach(char)
		end
	end)
end

weaponActionRmt.OnServerEvent:Connect(function(player, action)
	if action ~= "Shoot" and action ~= "Reload" then
		return
	end
	local char = player.Character
	if not char or not equippedTools[char] then
		return
	end
	local now = os.clock()
	if now - (lastWeaponAction[player] or 0) < WEAPON_ACTION_MIN_INTERVAL then
		return
	end
	lastWeaponAction[player] = now
	WeaponThirdPerson.setAction(char, action)
	if action == "Shoot" then
		-- Ouïe des bots (#141) : un tir s'entend autour du tireur
		BotManager.hearShot(Participants.fromPlayer(player), char:GetPivot().Position)
	end
end)

-- Cette méthode permet de brancher le personnage d'un participant (joueur ou bot, #139) lorsqu'il apparaît : arme 3P
-- suivie, mort comptée dans le round (et dans les stats pour un joueur), corps laissé aux clients le temps du ragdoll.
local function onParticipantCharacter(participant: Participants.Participant, char: Model, respawn: () -> ())
	Validator.forget(participant)
	trackWeapon3P(char)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		local killer = RoundManager.onCharacterDied(participant, respawn)
		if killer then
			-- Un bot qui vient de tuer se replace (#141)
			BotManager.notifyKill(killer)
		end
		-- Une mort infligée par un bot ne compte que dans le round (décision 6 de #133)
		local player = participant.player
		if player and ParticipantRules.countsInStats(participant.isBot, killer and killer.isBot) then
			StatsStore.recordDeath(player)
		end
		-- Pas tout de suite : les clients clonent le personnage pour en faire un ragdoll à la réception de PlayerDied (#102)
		task.delay(CORPSE_HANDOFF_DELAY, function()
			if Participants.characterOf(participant) == char then
				char:Destroy()
			end
		end)
	end)
end

local function onCharacterAdded(player: Player, char: Model)
	onParticipantCharacter(Participants.fromPlayer(player), char, function()
		SpawnManager.spawnPlayer(player)
	end)
end

-- ── SpawnManager ──────────────────────────────────────────────────────────

-- Position des joueurs envoyée par leur client, validée et relayée ; mort par chute hors de la map (attribut
-- KillHeight de la map jouée) testée sur chaque position acceptée
KillZone.init()
CharacterSync.init(characterSyncRmt, KillZone.check)

-- Une seule map est jouée (GameConfig.ACTIVE_MAP) : les autres sont retirées avant les premières apparitions
MapSelection.activate(workspace:FindFirstChild("Maps"), GameConfig.ACTIVE_MAP)

SpawnManager.init(spawnRmt, function(player: Player): boolean
	-- Refuser si déjà vivant
	if player.Character and player.Character.Parent then
		return false
	end
	-- Refuser si résultat en cours (bannière de fin)
	if RoundManager.getState() == "result" then
		return false
	end
	-- Démarrer le round si idle (1er joueur à cliquer Play)
	if RoundManager.getState() == "idle" then
		-- attribut Workspace RoundDuration : rounds courts pour suivre la mémoire sur plusieurs rounds (#95)
		RoundManager.startRound(
			PerfRules.roundDuration(GameConfig.ROUND_DURATION, workspace:GetAttribute("RoundDuration"))
		)
	end
	return true
end)

-- ── Combat : validation et attribution des dégâts ─────────────────────────

-- Cette méthode permet de lire le nom de l'arme en main du tireur lorsqu'une touche est attribuée (kill feed, #102).
local function weaponOf(attacker: Participants.Participant): string?
	local char = Participants.characterOf(attacker)
	local tool = char and equippedTools[char]
	if not tool then
		return nil
	end
	local name = tool:GetAttribute("WeaponName")
	return if type(name) == "string" and name ~= "" then name else tool.Name
end

-- Cette méthode permet d'attribuer une touche à son tireur (arme, tir à la tête) lorsqu'elle vise un participant.
local function recordHit(attacker: Participants.Participant, targetCharacter: Instance, isHeadshot: boolean)
	local target = Participants.fromCharacter(targetCharacter)
	if target then
		RoundManager.recordDamage(attacker, target, weaponOf(attacker), isHeadshot)
	end
end

-- Cette méthode permet d'appliquer des dégâts déjà validés (tireur joueur ou bot) et de confirmer la touche à un
-- tireur joueur, seulement si les PV de la cible ont réellement baissé (le hitmarker ne s'affiche pas sinon).
local function applyHit(
	attacker: Participants.Participant,
	targetCharacter: Instance,
	damage: number,
	isHeadshot: boolean
): ("hit" | "kill")?
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	-- Corps encore en place (CORPSE_HANDOFF_DELAY) : une touche ne doit pas créditer la prochaine mort de la victime
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	recordHit(attacker, targetCharacter, isHeadshot)
	local healthBefore = humanoid.Health
	humanoid:TakeDamage(damage)
	local outcome = Validator.hitOutcome(healthBefore, humanoid.Health)
	local player = attacker.player
	if outcome and player then
		hitConfirmRmt:FireClient(player, outcome == "kill", isHeadshot)
	end
	return outcome
end

-- Cette méthode permet de traiter le verdict du Validator lorsqu'une touche arrive : damage vaut nil si elle est refusée.
local function onHitVerdict(
	player: Player,
	remote: RemoteEvent,
	targetCharacter: Instance,
	damage: number?,
	isHeadshot: boolean
)
	DebugPlaytest.onHitReceived(player, remote.Name, targetCharacter, damage)
	if damage then
		applyHit(Participants.fromPlayer(player), targetCharacter, damage, isHeadshot)
	end
end

meleeRmt.OnServerEvent:Connect(function(player, targetCharacter, attackKind)
	local damage = Validator.authorizeMelee(Participants.fromPlayer(player), targetCharacter, attackKind, os.clock())
	onHitVerdict(player, meleeRmt, targetCharacter, damage, false)
end)

hitscanRmt.OnServerEvent:Connect(function(player, targetCharacter, hitPart)
	local damage, isHeadshot =
		Validator.authorizeHitscan(Participants.fromPlayer(player), targetCharacter, hitPart, os.clock())
	onHitVerdict(player, hitscanRmt, targetCharacter, damage, isHeadshot)
end)

-- ── Bots (#133) : personnages serveur, sans client ────────────────────────

BotManager.init({
	onCharacter = onParticipantCharacter,
	place = SpawnManager.place,
	relay = CharacterSync.relayBot,
	-- Touches d'un bot (#143) : même validation (arme en main, portée, cadence) et mêmes dégâts qu'un joueur
	hitscan = function(bot, targetCharacter, hitPart)
		local damage, isHeadshot = Validator.authorizeHitscan(bot, targetCharacter, hitPart, os.clock())
		return if damage then applyHit(bot, targetCharacter, damage, isHeadshot) else nil
	end,
	melee = function(bot, targetCharacter)
		local damage = Validator.authorizeMelee(bot, targetCharacter, "primary", os.clock())
		return if damage then applyHit(bot, targetCharacter, damage, false) else nil
	end,
	roundManager = RoundManager,
})

-- ── Helper de playtest debug (#30) : Studio uniquement ─────────────────────

if RunService:IsStudio() then
	DebugPlaytest.init({
		roundManager = RoundManager,
		validator = Validator,
		-- Bots retirés pendant un run, pour un test déterministe (#144)
		setBotsPaused = BotManager.setPaused,
	})
end

-- ── Lifecycle joueurs ─────────────────────────────────────────────────────

local function setupPlayer(player: Player)
	task.spawn(StatsStore.load, player)
	task.spawn(SettingsStore.load, player)
	RoundManager.addParticipant(Participants.fromPlayer(player))
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

-- Relevés mémoire du serveur : toujours actifs, la console serveur (F9) n'est lisible que par les développeurs du jeu.
MemoryTracker.enable()
MemoryTracker.snapshot("démarrage")
-- Sonde de coût du serveur (attribut Workspace PerfServer, #145) : inactive tant que l'attribut n'est pas posé
ServerPerf.init(function()
	return BotManager.count(), BotManager.aliveCount()
end)

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastWeaponAction[player] = nil
	local participant = Participants.fromPlayer(player)
	Validator.forget(participant)
	RoundManager.removeParticipant(participant)
	Participants.remove(participant)
	-- départ d'un joueur : ses Instances et connexions doivent avoir disparu au relevé (cf. docs/performance.md)
	task.delay(5, MemoryTracker.snapshot, "départ de " .. player.Name)
end)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

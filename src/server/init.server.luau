local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))

local SpawnManager = require(script.SpawnManager)
local RoundManager = require(script.RoundManager)
local StatsStore = require(script.StatsStore)
local Validator = require(script.Validator)
local FeedbackService = require(script.FeedbackService)
local DebugPlaytest = require(script.DebugPlaytest)
local KillZone = require(script.KillZone)
local MapTerrain = require(script.MapTerrain)

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
local fellOutRmt = makeRemote(N.FELL_OUT)

-- ── Initialisation des sous-systèmes ──────────────────────────────────────

StatsStore.init()
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
end)

local function onCharacterAdded(player: Player, char: Model)
	Validator.forgetPlayer(player)
	trackWeapon3P(char)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		RoundManager.onCharacterDied(player, SpawnManager.spawnPlayer)
		StatsStore.recordDeath(player)
		task.defer(function()
			if player.Character then
				player.Character:Destroy()
			end
		end)
	end)
end

-- ── SpawnManager ──────────────────────────────────────────────────────────

-- Mort par chute hors de l'île (Maps.Map.KillHeight)
KillZone.init(fellOutRmt)

-- Sable de la map en Terrain (dunes de l'Arène), posé avant les premières apparitions
local maps = workspace:FindFirstChild("Maps")
MapTerrain.build(maps and maps:FindFirstChild("Map"))

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
		RoundManager.startRound(GameConfig.ROUND_DURATION)
	end
	return true
end)

-- ── Combat : validation et attribution des dégâts ─────────────────────────

local function recordHit(player: Player, targetCharacter: Instance)
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then
		RoundManager.recordDamage(player, targetPlayer)
	end
end

-- Cette méthode permet d'appliquer des dégâts déjà validés et de confirmer la touche au tireur,
-- seulement si les PV de la cible ont réellement baissé (le hitmarker ne s'affiche pas sinon).
local function applyHit(player: Player, targetCharacter: Instance, damage: number, isHeadshot: boolean)
	recordHit(player, targetCharacter)
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if not humanoid then
		return
	end
	local healthBefore = humanoid.Health
	humanoid:TakeDamage(damage)
	local outcome = Validator.hitOutcome(healthBefore, humanoid.Health)
	if outcome then
		hitConfirmRmt:FireClient(player, outcome == "kill", isHeadshot)
	end
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
		applyHit(player, targetCharacter, damage, isHeadshot)
	end
end

meleeRmt.OnServerEvent:Connect(function(player, targetCharacter, attackKind)
	local damage = Validator.authorizeMelee(player, targetCharacter, attackKind, os.clock())
	onHitVerdict(player, meleeRmt, targetCharacter, damage, false)
end)

hitscanRmt.OnServerEvent:Connect(function(player, targetCharacter, hitPart)
	local damage, isHeadshot = Validator.authorizeHitscan(player, targetCharacter, hitPart, os.clock())
	onHitVerdict(player, hitscanRmt, targetCharacter, damage, isHeadshot)
end)

-- ── Helper de playtest debug (#30) : Studio uniquement ─────────────────────

if RunService:IsStudio() then
	DebugPlaytest.init({
		roundManager = RoundManager,
		validator = Validator,
	})
end

-- ── Lifecycle joueurs ─────────────────────────────────────────────────────

local function setupPlayer(player: Player)
	task.spawn(StatsStore.load, player)
	RoundManager.addPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastWeaponAction[player] = nil
	Validator.forgetPlayer(player)
	RoundManager.removePlayer(player)
end)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

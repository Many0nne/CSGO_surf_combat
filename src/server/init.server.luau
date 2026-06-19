local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared          = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig      = require(Shared:WaitForChild("GameConfig"))

local SpawnManager     = require(script.SpawnManager)
local RoundManager     = require(script.RoundManager)
local StatsStore       = require(script.StatsStore)
local Validator        = require(script.Validator)
local FeedbackService  = require(script.FeedbackService)

-- Spawn contrôlé : on gère LoadCharacter nous-mêmes
Players.CharacterAutoLoads = false

-- ── Création des RemoteEvents ──────────────────────────────────────────────

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

local N            = NetworkProtocol.Names
local meleeRmt     = makeRemote(N.MELEE_DAMAGE)
local hitscanRmt   = makeRemote(N.HITSCAN_DAMAGE)
local spawnRmt     = makeRemote(N.REQUEST_SPAWN)
local roundStateRmt  = makeRemote(N.ROUND_STATE)
local scoreUpdateRmt = makeRemote(N.SCORE_UPDATE)
local roundResultRmt = makeRemote(N.ROUND_RESULT)
local playerDiedRmt  = makeRemote(N.PLAYER_DIED)
local sendFeedbackRmt = makeRemote(N.SEND_FEEDBACK)
local feedbackAckRmt  = makeRemote(N.FEEDBACK_ACK)

-- ── Initialisation des sous-systèmes ──────────────────────────────────────

StatsStore.init()
FeedbackService.init(sendFeedbackRmt, feedbackAckRmt)

RoundManager.init({
	roundState  = roundStateRmt,
	scoreUpdate = scoreUpdateRmt,
	roundResult = roundResultRmt,
	playerDied  = playerDiedRmt,
})

-- ── Gestion du cycle de vie des personnages ────────────────────────────────

local function onCharacterAdded(player: Player, char: Model)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		StatsStore.recordDeath(player)
		RoundManager.onCharacterDied(player, SpawnManager.spawnPlayer)
	end)
end

-- ── SpawnManager ──────────────────────────────────────────────────────────

SpawnManager.init(spawnRmt, function(player: Player): boolean
	-- Refuser si déjà vivant
	if player.Character and player.Character.Parent then return false end
	-- Refuser si résultat en cours (bannière de fin)
	if RoundManager.getState() == "result" then return false end
	-- Démarrer le round si idle (1er joueur à cliquer Play)
	if RoundManager.getState() == "idle" then
		RoundManager.startRound(GameConfig.ROUND_DURATION)
	end
	return true
end)

-- ── Combat : validation et attribution des dégâts ─────────────────────────

meleeRmt.OnServerEvent:Connect(function(player, targetCharacter, damage)
	if not Validator.validateMelee(player, targetCharacter, damage) then return end
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then RoundManager.recordDamage(player, targetPlayer) end
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if humanoid then humanoid:TakeDamage(damage) end
end)

hitscanRmt.OnServerEvent:Connect(function(player, targetCharacter, damage)
	if not Validator.validateHitscan(player, targetCharacter, damage) then return end
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then RoundManager.recordDamage(player, targetPlayer) end
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if humanoid then humanoid:TakeDamage(damage) end
end)

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
	RoundManager.removePlayer(player)
end)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

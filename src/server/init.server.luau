local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))

local SpawnManager = require(script.SpawnManager)
local RoundManager = require(script.RoundManager)
local StatsStore = require(script.StatsStore)
local Validator = require(script.Validator)
local FeedbackService = require(script.FeedbackService)
local BotManager = require(script.BotManager)

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
local spawnRmt = makeRemote(N.REQUEST_SPAWN)
local roundStateRmt = makeRemote(N.ROUND_STATE)
local scoreUpdateRmt = makeRemote(N.SCORE_UPDATE)
local roundResultRmt = makeRemote(N.ROUND_RESULT)
local playerDiedRmt = makeRemote(N.PLAYER_DIED)
local sendFeedbackRmt = makeRemote(N.SEND_FEEDBACK)
local feedbackAckRmt = makeRemote(N.FEEDBACK_ACK)
local weaponActionRmt = makeRemote(N.WEAPON_ACTION)

-- ── Initialisation des sous-systèmes ──────────────────────────────────────

StatsStore.init()
FeedbackService.init(sendFeedbackRmt, feedbackAckRmt)

RoundManager.init({
	roundState = roundStateRmt,
	scoreUpdate = scoreUpdateRmt,
	roundResult = roundResultRmt,
	playerDied = playerDiedRmt,
})

BotManager.init({
	roundManager = RoundManager,
	spawnManager = SpawnManager,
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
	trackWeapon3P(char)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		local attackerId = RoundManager.onCharacterDied(player, SpawnManager.spawnPlayer)
		-- In-round only: do not persist deaths caused by bots (negative ids).
		if not attackerId or attackerId > 0 then
			StatsStore.recordDeath(player)
		end
		task.defer(function()
			if player.Character then
				player.Character:Destroy()
			end
		end)
	end)
end

-- ── SpawnManager ──────────────────────────────────────────────────────────

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
	task.defer(BotManager.maintainPopulation)
	return true
end)

-- ── Combat : validation et attribution des dégâts ─────────────────────────

local function recordHit(player: Player, targetCharacter: Instance)
	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then
		RoundManager.recordDamage(player, targetPlayer)
	else
		local botId = BotManager.getBotId(targetCharacter)
		if botId then
			RoundManager.recordDamageById(player.UserId, botId)
		end
	end
end

meleeRmt.OnServerEvent:Connect(function(player, targetCharacter, damage)
	if not Validator.validateMelee(player, targetCharacter, damage) then
		return
	end
	recordHit(player, targetCharacter)
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if humanoid then
		humanoid:TakeDamage(damage)
	end
end)

hitscanRmt.OnServerEvent:Connect(function(player, targetCharacter, damage)
	if not Validator.validateHitscan(player, targetCharacter, damage) then
		return
	end
	recordHit(player, targetCharacter)
	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if humanoid then
		humanoid:TakeDamage(damage)
	end
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

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
	task.defer(BotManager.maintainPopulation)
end)
Players.PlayerRemoving:Connect(function(player)
	lastWeaponAction[player] = nil
	RoundManager.removePlayer(player)
	task.defer(BotManager.maintainPopulation)
end)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

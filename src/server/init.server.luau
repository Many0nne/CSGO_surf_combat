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
local CheatLog = require(script.CheatLog)

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
local leaveRoundRmt = makeRemote(N.LEAVE_ROUND)
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
-- Fiable : renvoie un client dont la position est refusée à sa dernière position acceptée (#172)
local movementCorrectionRmt = makeRemote(N.MOVEMENT_CORRECTION)

-- ── Initialisation des sous-systèmes ──────────────────────────────────────

-- Journal anti-triche (#170) : avant les remotes, qui passent tous par CheatLog.admit
CheatLog.init()
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

-- Cette méthode permet de suivre l'équipement d'armes d'un personnage (joueur ou bot) lorsqu'il spawn : début de la
-- durée d'equip vérifiée par le Validator (#175), modèle 3P attaché à l'équipement, retiré quand l'outil correspondant
-- quitte le personnage (rechargement annulé).
local function trackWeapon3P(participant: Participants.Participant, char: Model)
	-- Cette méthode permet de savoir si un equip de ce personnage compte pour le Validator lorsqu'il change : joueur
	-- seulement (bots exclus des contrôles), et personnage encore le sien (pas l'ancien corps du ragdoll).
	local function tracksEquip(): boolean
		return not participant.isBot and Participants.characterOf(participant) == char
	end
	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			if tracksEquip() then
				Validator.noteEquip(participant, child, os.clock())
			end
			onToolEquipped(char, child)
		end
	end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			if tracksEquip() then
				Validator.noteEquip(participant, child, os.clock())
			end
			onToolEquipped(char, child)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if not child:IsA("Tool") then
			return
		end
		if tracksEquip() then
			Validator.noteUnequip(participant, child, os.clock())
		end
		if equippedTools[char] == child then
			equippedTools[char] = nil
			WeaponThirdPerson.detach(char)
		end
	end)
end

weaponActionRmt.OnServerEvent:Connect(function(player, action)
	if not CheatLog.admit(player, N.WEAPON_ACTION, action) then
		return
	end
	if action ~= "Shoot" and action ~= "Reload" then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	-- Chargeur vérifié par le serveur (#175) : avant les filtres de la pose 3P, qui peuvent écarter une action honnête
	if action == "Reload" then
		Validator.noteReload(Participants.fromPlayer(player), os.clock())
	end
	if not equippedTools[char] then
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
	trackWeapon3P(participant, char)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		local player = participant.player
		if player then
			-- En premier : une demande d'apparition est refusée pendant RESPAWN_DELAY (#171), même si la suite échoue
			SpawnManager.noteDeath(player)
		end
		local killer = RoundManager.onCharacterDied(participant, respawn)
		if killer then
			-- Un bot qui vient de tuer se replace (#141)
			BotManager.notifyKill(killer)
		end
		-- Une mort infligée par un bot ne compte que dans le round (décision 6 de #133)
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
		-- Jamais par-dessus un personnage vivant ni un spawn en vol (#171)
		SpawnManager.respawn(player)
	end)
end

-- ── SpawnManager ──────────────────────────────────────────────────────────

-- Position des joueurs envoyée par leur client, validée et relayée ; mort par chute hors de la map (attribut
-- KillHeight de la map jouée) testée sur chaque position acceptée, et sur un joueur silencieux tombé dans le vide
KillZone.init()
CharacterSync.init(
	characterSyncRmt,
	movementCorrectionRmt,
	KillZone.check,
	{ height = KillZone.height, kill = KillZone.kill }
)

-- Une seule map est jouée (GameConfig.ACTIVE_MAP) : les autres sont retirées avant les premières apparitions
MapSelection.activate(workspace:FindFirstChild("Maps"), GameConfig.ACTIVE_MAP)

-- Règles de la demande (déjà vivant, spawn en vol, bannière de fin, délai depuis la mort) : SpawnRules (#171)
SpawnManager.init(spawnRmt, {
	roundState = RoundManager.getState,
	beforeSpawn = function(player)
		-- Démarrer le round si idle (1er joueur à cliquer Play)
		if RoundManager.getState() == "idle" then
			-- attribut Workspace RoundDuration : rounds courts pour suivre la mémoire sur plusieurs rounds (#95)
			RoundManager.startRound(
				PerfRules.roundDuration(GameConfig.ROUND_DURATION, workspace:GetAttribute("RoundDuration"))
			)
		end
		-- Au classement dès l'apparition, retour du menu en partie compris (#157)
		RoundManager.addParticipant(Participants.fromPlayer(player))
	end,
})

-- Retour au menu principal depuis le menu en partie (#157) : retiré du round (score, coups en attente) avant la
-- destruction de son personnage, qui ne compte donc pas comme une mort ; plus de réapparition jusqu'à JOUER
leaveRoundRmt.OnServerEvent:Connect(function(player)
	if not CheatLog.admit(player, N.LEAVE_ROUND) then
		return
	end
	local participant = Participants.fromPlayer(player)
	RoundManager.withdraw(participant)
	Validator.forget(participant)
	SpawnManager.withdraw(player)
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
	if not CheatLog.admit(player, N.MELEE_DAMAGE, targetCharacter, attackKind) then
		return
	end
	local damage = Validator.authorizeMelee(Participants.fromPlayer(player), targetCharacter, attackKind, os.clock())
	onHitVerdict(player, meleeRmt, targetCharacter, damage, false)
end)

-- Cette méthode permet de tester la ligne de vue d'un tir ou d'un coup de mêlée (#176) lorsque le Validator la vérifie
-- (#174) : raycast limité à la géométrie de la map jouée (Workspace.Maps, en inclusion : personnages et objets
-- mobiles ignorés).
-- Paramètres réutilisés tant que le dossier des maps est le même (reconstruits s'il est remplacé).
local shotParams: RaycastParams? = nil
local shotParamsMaps: Instance? = nil
local warnedNoMaps = false
local function isShotObstructed(from: Vector3, delta: Vector3): boolean
	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		-- Sans map, rien à tester : signalé une fois, la ligne de vue ne disparaît pas en silence
		if not warnedNoMaps then
			warnedNoMaps = true
			warn("[Validator] Workspace.Maps introuvable : ligne de vue des tirs non vérifiée")
		end
		return false
	end
	if not shotParams or shotParamsMaps ~= maps then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { maps }
		shotParams = params
		shotParamsMaps = maps
	end
	return workspace:Raycast(from, delta, shotParams) ~= nil
end

-- Validation des tirs de joueurs (#174) : cible rembobinée sur l'historique de CharacterSync, échecs au journal
Validator.setShotWorld({
	-- Cette méthode permet de lire l'horloge serveur lorsqu'un tir est rembobiné (même horloge que l'historique).
	serverNow = function()
		return workspace:GetServerTimeNow()
	end,
	positionAt = CharacterSync.positionAt,
	isObstructed = isShotObstructed,
	-- Cette méthode permet de journaliser un contrôle de tir en échec lorsqu'il est constaté (catégorie Hitscan, une
	-- source par contrôle pour le décompte des violations fortes).
	-- Catégorie Melee pour l'equip d'une arme de mêlée (#175), l'orientation et la ligne de vue d'un coup (#176).
	report = function(attacker, check, severity, detail, category)
		local cat = category or CheatLog.Category.HITSCAN
		CheatLog.report(attacker, cat, severity, detail, cat .. ":" .. check)
	end,
})

hitscanRmt.OnServerEvent:Connect(function(player, targetCharacter, hitPart, origin, direction, hitPos, shotTime)
	if not CheatLog.admit(player, N.HITSCAN_DAMAGE, targetCharacter, hitPart, origin, direction, hitPos, shotTime) then
		return
	end
	local shot = { origin = origin, direction = direction, hitPos = hitPos, shotTime = shotTime }
	local damage, isHeadshot =
		Validator.authorizeHitscan(Participants.fromPlayer(player), targetCharacter, hitPart, os.clock(), shot)
	-- Tir validé (damage non nil) : point de branchement du relais aux autres clients (#156)
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
	SpawnManager.forget(player)
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

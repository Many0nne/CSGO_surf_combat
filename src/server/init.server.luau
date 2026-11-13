local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MapGeometry = require(Shared:WaitForChild("MapGeometry"))
local MapSelection = require(Shared:WaitForChild("MapSelection"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local MemoryTracker = require(Shared:WaitForChild("MemoryTracker"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))
local ParticipantRules = require(Shared:WaitForChild("ParticipantRules"))
local CollisionGroups = require(Shared:WaitForChild("CollisionGroups"))

local SpawnManager = require(script.SpawnManager)
local RoundManager = require(script.RoundManager)
local StatsStore = require(script.StatsStore)
local SettingsStore = require(script.SettingsStore)
local InventoryStore = require(script.InventoryStore)
local Roles = require(script.Roles)
local Validator = require(script.Validator)
local Participants = require(script.Participants)
local FeedbackService = require(script.FeedbackService)
local DebugPlaytest = require(script.DebugPlaytest)
local KillZone = require(script.KillZone)
local CharacterSync = require(script.CharacterSync)
local BotManager = require(script.bots.BotManager)
local ServerPerf = require(script.ServerPerf)
local CheatLog = require(script.CheatLog)
local ShotRelayRules = require(script.ShotRelayRules)
local AimStats = require(script.AimStats)

-- Spawn contrôlé : on gère LoadCharacter nous-mêmes
Players.CharacterAutoLoads = false

-- Les personnages se traversent (#312) : groupe enregistré avant qu'un personnage n'y soit rangé
CollisionGroups.register()

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
-- Tirs entendus par les autres clients (#156) : client → serveur (tir), serveur → autres clients (relais)
local shotFiredRmt = makeRemote(N.SHOT_FIRED)
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
-- Équipement choisi à l'accueil (#280) : client → serveur, validé par InventoryStore
local equipItemRmt = makeRemote(N.EQUIP_ITEM)
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
-- Inventaire (#267) : StarterPack vidé, Tools donnés selon l'équipement (#280), armes non possédées refusées par le
-- Validator
InventoryStore.init(equipItemRmt, SpawnManager.isSpawning)
Validator.setOwnership(InventoryStore.ownsTool)
FeedbackService.init(sendFeedbackRmt, feedbackAckRmt)

RoundManager.init({
	roundState = roundStateRmt,
	scoreUpdate = scoreUpdateRmt,
	roundResult = roundResultRmt,
	playerDied = playerDiedRmt,
	-- Stats persistantes (#296) : une manche jouée pour chaque joueur en jeu à la fin, gagnée pour le vainqueur (par id)
	onRoundEnd = function(participants, winner)
		for _, participant in participants do
			if participant.player then
				StatsStore.recordRoundEnd(participant.player, winner ~= nil and winner.id == participant.id)
			end
		end
	end,
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
	-- Cette méthode permet de suivre un outil arrivé en main (equip) lorsqu'il est vu par le serveur ; un outil non
	-- possédé par un joueur (#267) est journalisé et retiré, sans equip ni modèle 3P.
	local function onToolAdded(tool: Tool)
		if not participant.isBot and not InventoryStore.ownsTool(participant, tool.Name) then
			CheatLog.report(
				participant,
				CheatLog.Category.INVENTORY,
				CheatLog.Severity.LOW,
				"outil non possédé en main : " .. tool.Name
			)
			-- Différé : détruire un enfant pendant son ChildAdded échoue (parent en cours de changement)
			task.defer(tool.Destroy, tool)
			return
		end
		if tracksEquip() then
			Validator.noteEquip(participant, tool, os.clock())
		end
		onToolEquipped(char, tool)
	end
	for _, child in char:GetChildren() do
		if child:IsA("Tool") then
			onToolAdded(child)
		end
	end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolAdded(child)
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

-- Cette méthode permet de savoir si un outil est une arme de mêlée (fiche WeaponConfig) lorsqu'une action de pose 3P
-- arrive du client.
local function isMeleeTool(tool: Tool): boolean
	local cfg = WeaponConfig.Weapons[tool:GetAttribute("WeaponName") or tool.Name]
	return cfg ~= nil and cfg.IsMelee == true
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
	local tool = equippedTools[char]
	if not tool then
		return
	end
	-- Tir d'une arme à distance : pose 3P jouée par le relais d'un ShotFired accepté (relayShot, #215), pas sur la
	-- parole du client. Seul le coup de couteau (manqué compris, sans remote de tir) passe encore par ici
	if action == "Shoot" and not isMeleeTool(tool) then
		return
	end
	local now = os.clock()
	if now - (lastWeaponAction[player] or 0) < WEAPON_ACTION_MIN_INTERVAL then
		return
	end
	lastWeaponAction[player] = now
	-- Pose 3P seulement : l'ouïe des bots (#141) part des tirs acceptés par le serveur (relayShot, ShotFired, #156)
	WeaponThirdPerson.setAction(char, action)
end)

-- ── Tirs entendus par les autres clients (#156) ───────────────────────────

-- Cadence du dernier tir relayé, par tireur et par arme (ShotRelayRules)
local shotRelay = ShotRelayRules.new()

-- Cette méthode permet de relayer un tir à distance (joueur ou bot, touché ou manqué) aux autres clients lorsqu'il
-- part et que le serveur l'accepte (Validator, ShotRelayRules) : compté dans le chargeur (#215, shotTime du joueur
-- pour rattacher sa touche, #216), pose 3P de tir jouée chez tous ; celui d'un joueur est aussi entendu par les bots.
local function relayShot(
	participant: Participants.Participant,
	origin: Vector3,
	direction: Vector3,
	shotTime: number?
): boolean
	local char = Participants.characterOf(participant)
	local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return false
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local weaponName = tool and (tool:GetAttribute("WeaponName") or tool.Name)
	if type(weaponName) ~= "string" then
		return false
	end
	local now = os.clock()
	if not Validator.isReadyToFire(participant, now, shotTime) then
		return false
	end
	if not ShotRelayRules.admit(shotRelay, participant, weaponName, origin, direction, root.Position, now) then
		return false
	end
	if shotTime then
		Validator.noteShotFired(participant, shotTime, now)
	end
	-- Recul de l'arme 3P vu par les autres : seulement pour un tir accepté, à sa cadence (#215)
	WeaponThirdPerson.setAction(char, "Shoot")
	for _, recipient in ShotRelayRules.recipients(Players:GetPlayers(), participant.player) do
		shotFiredRmt:FireClient(recipient, char, weaponName, origin, direction)
	end
	if not participant.isBot then
		BotManager.hearShot(participant, root.Position)
	end
	return true
end

-- ── Statistiques de visée (#178) : journal pour revue humaine, jamais de sanction ni de tir refusé ──────

local aimStats = AimStats.new()
-- Période (s) du résumé des statistiques de visée (console, et CheatLog pour les joueurs signalés).
local AIM_REPORT_INTERVAL = 120

-- Cette méthode permet d'écrire le résumé de visée d'un joueur lorsqu'il est produit (périodique ou fin de session) :
-- console pour tous, CheatLog (catégorie Aim, gravité faible) pour un joueur signalé (au départ : signalé un jour).
local function logAim(participant: Participants.Participant, entry: AimStats.Entry, final: boolean)
	print(
		string.format(
			"[AimStats] %s%s (%d) : %s",
			if final then "fin de session, " else "",
			entry.stats.name,
			entry.id,
			entry.line
		)
	)
	if entry.report then
		CheatLog.report(participant, CheatLog.Category.AIM, CheatLog.Severity.LOW, entry.line, CheatLog.Category.AIM)
	end
end

task.spawn(function()
	while true do
		task.wait(AIM_REPORT_INTERVAL)
		-- Une erreur ne doit pas arrêter les résumés suivants
		local ok, err = pcall(function()
			for _, entry in AimStats.periodic(aimStats) do
				-- Joueur retrouvé par Players, pas par le registre (qu'un départ en cours peut déjà avoir vidé) ; parti :
				-- son relevé final est fait par la clôture
				local player = Players:GetPlayerByUserId(entry.id)
				if player then
					logAim({ id = entry.id, name = player.Name, isBot = false, player = player }, entry, false)
				end
			end
		end)
		if not ok then
			warn("[AimStats] résumé périodique en échec :", err)
		end
	end
end)

-- Résumé final avant la clôture du bilan CheatLog (le signalement y entre) ; statistiques oubliées au départ. À
-- l'arrêt du serveur, tous les joueurs restants sont jugés ensemble, contre la même population, puis plus rien n'est
-- compté (pas de relevé partiel recréé par un tir pendant l'attente de l'arrêt).
CheatLog.onClosing(function(players, shuttingDown)
	local byId: { [number]: Player } = {}
	local ids = {}
	for _, player in players do
		byId[player.UserId] = player
		table.insert(ids, player.UserId)
	end
	for _, entry in AimStats.close(aimStats, ids) do
		local player = byId[entry.id]
		-- Participant reconstruit : celui du registre peut déjà être retiré (ordre des PlayerRemoving non garanti)
		logAim({ id = entry.id, name = player.Name, isBot = false, player = player }, entry, true)
	end
	if shuttingDown then
		AimStats.freeze(aimStats)
	end
end)

shotFiredRmt.OnServerEvent:Connect(function(player, origin, direction, shotTime)
	if not CheatLog.admit(player, N.SHOT_FIRED, origin, direction, shotTime) then
		return
	end
	local participant = Participants.fromPlayer(player)
	-- Compté après la décision du relais, qu'il ne change pas : un tir accepté (forme, cadence, chargeur) entre aux
	-- statistiques
	if relayShot(participant, origin, direction, shotTime) then
		-- Cap figé à l'arrivée du tir, avant sa touche (flick), retrouvée par shotTime (#216)
		local yaw, yawAt = CharacterSync.lastYaw(player)
		AimStats.noteShot(aimStats, participant, os.clock(), yaw, yawAt, shotTime)
	end
end)

-- Cette méthode permet d'oublier l'état de combat d'un participant (Validator, relais des tirs) lorsqu'il réapparaît
-- ou s'en va (joueur parti, bot retiré, #218) ; AimStats ignore les bots, CheatLog.onClosing clôt les joueurs.
local function forgetCombatState(participant: Participants.Participant)
	Validator.forget(participant)
	ShotRelayRules.forget(shotRelay, participant)
end

-- Cette méthode permet d'appliquer les suites d'une mort (bot tueur replacé, stats persistantes) lorsqu'un personnage
-- meurt, ou qu'un joueur part par MENU PRINCIPAL juste après un coup reçu (#217).
local function onDeathCounted(participant: Participants.Participant, killer: Participants.Participant?)
	if killer then
		-- Un bot qui vient de tuer se replace (#141)
		BotManager.notifyKill(killer)
	end
	-- Une mort infligée par un bot ne compte que dans le round (décision 6 de #133)
	local player = participant.player
	if player and ParticipantRules.countsInStats(participant.isBot, killer and killer.isBot) then
		StatsStore.recordDeath(player)
	end
	-- Le tueur joueur est crédité d'un kill sous la même règle (un bot tué ou tueur ne compte pas)
	if killer and killer.player and ParticipantRules.killCountsInStats(participant.isBot, killer.isBot) then
		StatsStore.recordKill(killer.player)
	end
end

-- Cette méthode permet de brancher le personnage d'un participant (joueur ou bot, #139) lorsqu'il apparaît : pièces
-- rangées dans le groupe des personnages (#312), arme 3P suivie, mort comptée dans le round (et dans les stats pour un
-- joueur), corps laissé aux clients le temps du ragdoll.
local function onParticipantCharacter(participant: Participants.Participant, char: Model, respawn: () -> ())
	CollisionGroups.assignCharacter(char)
	forgetCombatState(participant)
	trackWeapon3P(participant, char)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		local player = participant.player
		if player then
			-- En premier : une demande d'apparition est refusée pendant RESPAWN_DELAY (#171), même si la suite échoue
			SpawnManager.noteDeath(player)
		end
		local killer = RoundManager.onCharacterDied(participant, respawn)
		onDeathCounted(participant, killer)
		-- Pas tout de suite : les clients clonent le personnage pour en faire un ragdoll à la réception de PlayerDied (#102)
		task.delay(CORPSE_HANDOFF_DELAY, function()
			if Participants.characterOf(participant) == char then
				char:Destroy()
			end
		end)
	end)
end

local function onCharacterAdded(player: Player, char: Model)
	-- Sac rempli des seuls Tools possédés (#267), à chaque apparition : le StarterPack est vide
	task.spawn(InventoryStore.syncTools, player)
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
-- destruction de son personnage, qui ne compte donc pas comme une mort ; plus de réapparition jusqu'à JOUER.
-- Touché depuis moins de GameConfig.LEAVE_DEATH_WINDOW (#217) : le départ compte d'abord comme une mort, avec les
-- suites d'une mort normale (kill du dernier attaquant, kill feed, stats), sans ragdoll ni caméra de mort pour lui.
leaveRoundRmt.OnServerEvent:Connect(function(player)
	if not CheatLog.admit(player, N.LEAVE_ROUND) then
		return
	end
	local participant = Participants.fromPlayer(player)
	local died, killer = RoundManager.withdraw(participant)
	if died then
		onDeathCounted(participant, killer)
	end
	forgetCombatState(participant)
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
		-- Protection d'apparition (TakeDamage l'ignore) : pas un coup reçu pour un départ par MENU PRINCIPAL (#217)
		local shielded = targetCharacter:FindFirstChildWhichIsA("ForceField") ~= nil
		RoundManager.recordDamage(attacker, target, weaponOf(attacker), isHeadshot, shielded)
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
-- Renvoie le résultat des dégâts (nil si refusée ou sans effet : cible déjà morte, ForceField).
local function onHitVerdict(
	player: Player,
	remote: RemoteEvent,
	targetCharacter: Instance,
	damage: number?,
	isHeadshot: boolean
): ("hit" | "kill")?
	DebugPlaytest.onHitReceived(player, remote.Name, targetCharacter, damage)
	if damage then
		return applyHit(Participants.fromPlayer(player), targetCharacter, damage, isHeadshot)
	end
	return nil
end

meleeRmt.OnServerEvent:Connect(function(player, targetCharacter, attackKind, hitTime)
	if not CheatLog.admit(player, N.MELEE_DAMAGE, targetCharacter, attackKind, hitTime) then
		return
	end
	local damage =
		Validator.authorizeMelee(Participants.fromPlayer(player), targetCharacter, attackKind, os.clock(), hitTime)
	onHitVerdict(player, meleeRmt, targetCharacter, damage, false)
end)

-- Lignes de vue des tirs et des coups de mêlée (#174, #176) : raycast limité à la géométrie de la map jouée
-- (Workspace.Maps, en inclusion : personnages et objets mobiles ignorés). Le tir traverse les murs d'air et les grillages
-- (#292, même règle que le tir du client et des bots : MapGeometry.bulletTransparent) ; la mêlée garde toute la map,
-- comme le coup du client (MeleeHitDetection).
-- Paramètres réutilisés tant que le dossier des maps et la map jouée sont les mêmes (reconstruits sinon).
local shotParams: RaycastParams? = nil
local meleeParams: RaycastParams? = nil
local sightParamsMaps: Instance? = nil
local sightParamsMap: Instance? = nil
local warnedNoMaps = false

-- Cette méthode permet de préparer les rayons de ligne de vue lorsqu'un tir ou un coup est vérifié : paramètres du tir
-- et de la mêlée, nil sans Workspace.Maps (signalé une fois).
local function sightParams(): (RaycastParams?, RaycastParams?)
	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		-- Sans map, rien à tester : signalé une fois, la ligne de vue ne disparaît pas en silence
		if not warnedNoMaps then
			warnedNoMaps = true
			warn("[Validator] Workspace.Maps introuvable : ligne de vue des tirs non vérifiée")
		end
		return nil, nil
	end
	local active = maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	local map = if type(active) == "string" then maps:FindFirstChild(active) else nil
	if not shotParams or not meleeParams or sightParamsMaps ~= maps or sightParamsMap ~= map then
		local shot = RaycastParams.new()
		shot.FilterType = Enum.RaycastFilterType.Include
		shot.FilterDescendantsInstances = if map
			then MapGeometry.includeAllBut(maps, MapGeometry.bulletTransparent(map))
			else { maps }
		local melee = RaycastParams.new()
		melee.FilterType = Enum.RaycastFilterType.Include
		melee.FilterDescendantsInstances = { maps }
		shotParams, meleeParams = shot, melee
		sightParamsMaps, sightParamsMap = maps, map
	end
	return shotParams, meleeParams
end

-- Cette méthode permet de tester la ligne de vue d'un tir lorsque le Validator la vérifie (#174) : murs d'air et
-- grillages traversés (#292).
local function isShotObstructed(from: Vector3, delta: Vector3): boolean
	local params = sightParams()
	return params ~= nil and workspace:Raycast(from, delta, params) ~= nil
end

-- Cette méthode permet de tester la ligne de vue d'un coup de mêlée lorsque le Validator la vérifie (#176) : toute la
-- map, murs d'air compris.
local function isMeleeObstructed(from: Vector3, delta: Vector3): boolean
	local _, params = sightParams()
	return params ~= nil and workspace:Raycast(from, delta, params) ~= nil
end

-- Validation des tirs de joueurs (#174) : cible rembobinée sur l'historique de CharacterSync, échecs au journal
Validator.setShotWorld({
	-- Cette méthode permet de lire l'horloge serveur lorsqu'un tir est rembobiné (même horloge que l'historique).
	serverNow = function()
		return workspace:GetServerTimeNow()
	end,
	positionAt = CharacterSync.positionAt,
	isObstructed = isShotObstructed,
	isMeleeObstructed = isMeleeObstructed,
	-- Cette méthode permet de lire l'aller-retour réseau d'un joueur (s) lorsqu'on borne l'instant annoncé d'un tir ou
	-- d'un coup (#214) : mesuré par le moteur (Player:GetNetworkPing, même lecture que le ping du journal, #297), nil
	-- pour un bot ou en cas d'erreur.
	pingOf = function(attacker)
		local player = attacker.player
		return if player then CheatLog.pingOf(player) else nil
	end,
	-- Cette méthode permet de journaliser un contrôle de tir en échec lorsqu'il est constaté (catégorie Hitscan, compté
	-- par contrôle au journal et pour le décompte des violations fortes, #297).
	-- Catégorie Melee pour l'equip d'une arme de mêlée (#175), l'orientation et la ligne de vue d'un coup (#176).
	report = function(attacker, check, severity, detail, category)
		CheatLog.report(attacker, category or CheatLog.Category.HITSCAN, severity, detail, check)
	end,
	-- Touches et coups soumis aux contrôles : dénominateurs des taux du journal (#297)
	judged = CheatLog.judged,
})

hitscanRmt.OnServerEvent:Connect(function(player, targetCharacter, hitPart, origin, direction, hitPos, shotTime)
	if not CheatLog.admit(player, N.HITSCAN_DAMAGE, targetCharacter, hitPart, origin, direction, hitPos, shotTime) then
		return
	end
	local participant = Participants.fromPlayer(player)
	local shot = { origin = origin, direction = direction, hitPos = hitPos, shotTime = shotTime }
	local damage, isHeadshot, linkedShotTime =
		Validator.authorizeHitscan(participant, targetCharacter, hitPart, os.clock(), shot)
	-- Le son du tir chez les autres (#156) ne part pas d'ici : chaque tir, touché ou manqué, arrive d'abord par ShotFired
	-- Statistiques de visée (#178), après coup et sans effet sur la touche : seulement une touche qui a fait des dégâts
	-- (pas un corps déjà mort), rattachée à son tir par le Validator (#216), flick mesuré sur sa direction validée
	if onHitVerdict(player, hitscanRmt, targetCharacter, damage, isHeadshot) then
		AimStats.noteHit(aimStats, participant, isHeadshot, os.clock(), direction, linkedShotTime)
		-- Taux de touches orphelines (#246) : un client qui n'envoie jamais ShotFired, violation moyenne (journal seul)
		local orphanDetail = AimStats.orphanAlert(aimStats, participant)
		if orphanDetail then
			CheatLog.report(
				participant,
				CheatLog.Category.HITSCAN,
				CheatLog.Severity.MEDIUM,
				orphanDetail,
				"orphanRate"
			)
		end
	end
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
	-- Tirs d'un bot entendus par les joueurs (#156), touchés ou manqués : même relais que ceux d'un joueur
	shotFired = function(bot, origin, direction)
		return relayShot(bot, origin, direction)
	end,
	forget = forgetCombatState,
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
	Roles.setup(player)
	-- Après les rôles : l'inventaire d'un admin en dépend (#267)
	InventoryStore.setup(player)
	task.spawn(InventoryStore.load, player)
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
	return BotManager.count(), BotManager.aliveCount(), Validator.trackedCount()
end)

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastWeaponAction[player] = nil
	SpawnManager.forget(player)
	local participant = Participants.fromPlayer(player)
	forgetCombatState(participant)
	RoundManager.removeParticipant(participant)
	Participants.remove(participant)
	-- départ d'un joueur : ses Instances et connexions doivent avoir disparu au relevé (cf. docs/performance.md)
	task.delay(5, MemoryTracker.snapshot, "départ de " .. player.Name)
end)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

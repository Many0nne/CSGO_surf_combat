local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local BotCombatRules = require(ReplicatedStorage.Shared.BotCombatRules)
local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local Participants = require(ServerScriptService.Server.Participants)
local SpawnPointRules = require(ServerScriptService.Server.SpawnPointRules)
local SpawnProtection = require(ServerScriptService.Server.SpawnProtection)
local SpawnRules = require(ServerScriptService.Server.SpawnRules)

local SpawnManager = {}

local mapModel: Instance?
-- Remote RequestSpawn, aussi la voie de la réponse au client (#219, SpawnRules.reply)
local replyRemote: RemoteEvent?
-- Joueurs dont un LoadCharacterAsync est en vol, et heure (os.clock) de leur dernière mort (#171)
local spawning: { [Player]: boolean } = {}
local diedAt: { [Player]: number } = {}
-- Joueurs revenus au menu (#157) : aucune réapparition programmée, aucun personnage en vol gardé, jusqu'à leur demande
local away: { [Player]: boolean } = {}
-- Joueurs revenus du menu pendant une réapparition encore en vol : leur demande est servie à la fin de ce chargement
local rejoin: { [Player]: boolean } = {}
-- État du round, branché par init (hooks.roundState) : une réapparition arrivée pendant la bannière est détruite (#300)
local roundStateFn: (() -> string)? = nil
-- Gravité d'un refus de RequestSpawn au journal ; "result" n'y va pas (Play cliqué pendant la bannière de fin, ou
-- enchaînement automatique de la manche suivante, #300). "early" est moyen : notre client n'envoie RequestSpawn que
-- depuis le menu, où un joueur mort en round ne revient pas, à la fin de la bannière (#300, round alors pas actif),
-- ou en DEAD passé RESPAWN_DELAY + RESPAWN_MARGIN (#245), jamais pendant RESPAWN_DELAY. Cette redemande peut tomber
-- sur une réapparition programmée encore en vol ("spawning", LOW) si le chargement dépasse RESPAWN_MARGIN.
local REFUSAL_SEVERITY: { [string]: CheatLog.Severity } = {
	spawning = CheatLog.Severity.LOW,
	alive = CheatLog.Severity.LOW,
	early = CheatLog.Severity.MEDIUM,
}

-- Cette méthode permet de trouver la map jouée (GameConfig.ACTIVE_MAP dans Workspace.Maps) lorsqu'un joueur demande à
-- apparaître.
local function getMap(): Instance?
	if mapModel and mapModel.Parent then
		return mapModel
	end
	mapModel = MapSelection.waitForActive(10)
	return mapModel
end

-- Tirage des points d'apparition et paramètres du raycast de vue, créés au premier placement
local rng: Random? = nil
local sightParams: RaycastParams? = nil
local sightMap: Instance? = nil

-- Cette méthode permet de tester si un ennemi voit un point d'apparition lorsqu'on choisit où faire apparaître un
-- personnage (#288) : raycast d'yeux à yeux limité aux pièces de la map jouée qui arrêtent le regard (ni murs d'air
-- Clips, ni grillages, SpawnPointRules.blocksSight), listées une fois par map (géométrie fixe pendant la partie).
local function isVisible(map: Instance, from: Vector3, to: Vector3): boolean
	if not sightParams or sightMap ~= map then
		local clips = map:FindFirstChild("Clips")
		local blockers = {}
		for _, d in map:GetDescendants() do
			if
				d:IsA("BasePart")
				and d.CanQuery
				and SpawnPointRules.blocksSight(clips ~= nil and d:IsDescendantOf(clips), d.Transparency)
			then
				table.insert(blockers, d)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = blockers
		sightParams = params
		sightMap = map
	end
	return workspace:Raycast(from, to - from, sightParams) == nil
end

-- Cette méthode permet de lister les yeux des ennemis vivants (tous les autres participants) lorsqu'un personnage
-- apparaît (#288) ; un personnage pas encore placé (sans SpawnedAt, encore à sa position de chargement) est ignoré.
local function enemyEyes(char: Model): { Vector3 }
	local eyes = {}
	for _, participant in Participants.all() do
		local other = Participants.characterOf(participant)
		local placed = other ~= nil
			and other ~= char
			and other.Parent ~= nil
			and other:GetAttribute(BotCombatRules.SPAWNED_AT_ATTRIBUTE) ~= nil
		local humanoid = placed and (other :: Model):FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.Health > 0 and (other :: Model):FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(eyes, root.Position + Vector3.new(0, SpawnPointRules.ROOT_EYE_OFFSET, 0))
		end
	end
	return eyes
end

-- Cette méthode permet de choisir un point au sol (GroundSpawns) loin et hors de vue des ennemis vivants lorsqu'un
-- personnage apparaît (#288, SpawnPointRules) ; nil si la map n'a aucun point.
local function pickGround(char: Model): BasePart?
	local map = getMap()
	local folder = map and map:FindFirstChild("GroundSpawns")
	local parts: { BasePart } = {}
	local eyes: { Vector3 } = {}
	for _, child in if folder then folder:GetChildren() else {} do
		if child:IsA("BasePart") then
			table.insert(parts, child)
			table.insert(eyes, child.Position + Vector3.new(0, SpawnPointRules.POINT_EYE_OFFSET, 0))
		end
	end
	if not rng then
		rng = Random.new()
	end
	local random = rng :: Random
	local index = SpawnPointRules.choose(eyes, enemyEyes(char), function(from, to)
		return isVisible(map :: Instance, from, to)
	end, function(n)
		return random:NextInteger(1, n)
	end)
	return if index then parts[index] else nil
end

-- Cette méthode permet de placer un personnage qui vient d'apparaître (joueur ou bot, #139) : posé sur un point au sol
-- choisi loin des ennemis (#288), protégé SPAWN_PROTECTION secondes (SpawnProtection) ; sans point, (0, 10, 0).
function SpawnManager.place(char: Model)
	local ground = pickGround(char)
	if not ground then
		warn("[SpawnManager] aucun point dans Maps.Map.GroundSpawns")
	end
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	-- Délai de grâce : un bot ne tire pas sur un participant qui vient d'apparaître (#143)
	char:SetAttribute(BotCombatRules.SPAWNED_AT_ATTRIBUTE, os.clock())
	SpawnProtection.protect(char)
	if root then
		local above = Vector3.new(0, SpawnPointRules.ROOT_ABOVE_POINT, 0)
		root.CFrame = CFrame.new((if ground then ground.Position else Vector3.new(0, 5, 0)) + above)
	end
end

-- Cette méthode permet de répondre au client lorsque sa demande d'apparition est jugée ou que son chargement échoue
-- (#219) : le client ne reste jamais sans nouvelles en SPAWNING.
local function reply(player: Player, answer: SpawnRules.Reply)
	if replyRemote and player.Parent then
		replyRemote:FireClient(player, answer)
	end
end

-- Cette méthode permet de faire apparaître un joueur lorsqu'une demande ou une réapparition programmée est acceptée ;
-- un seul LoadCharacterAsync en vol par joueur : rien si un autre est déjà en cours. Renvoie false si ce chargement
-- a échoué (true si un autre, en vol, servira la demande).
function SpawnManager.spawnPlayer(player: Player): boolean
	if spawning[player] then
		return true
	end
	-- Studio seulement (#245) : attribut Workspace DebugSpawnFail = true, chaque chargement échoue (réapparition
	-- programmée et demandes), pour vérifier que le client ne reste pas bloqué
	if RunService:IsStudio() and workspace:GetAttribute("DebugSpawnFail") == true then
		warn("[SpawnManager] DebugSpawnFail : chargement refusé pour " .. player.Name)
		-- Comme un vrai échec : une demande en attente de ce chargement est répondue ici
		if rejoin[player] then
			rejoin[player] = nil
			reply(player, { status = "failed" })
			return true
		end
		return false
	end
	spawning[player] = true
	-- Connexion avant LoadCharacter pour ne pas manquer CharacterAdded
	local conn: RBXScriptConnection
	conn = player.CharacterAdded:Connect(function(char)
		conn:Disconnect()
		-- Réapparition partie avant le retour au menu : le joueur n'a plus de personnage dans le round. Arrivée pendant
		-- la bannière de fin (#300) : sans protection d'apparition à la manche suivante, la demande qui enchaîne en
		-- fait apparaître un neuf
		if not SpawnRules.keepsArrival(away[player] == true, if roundStateFn then roundStateFn() else "idle") then
			char:Destroy()
			return
		end
		CharacterAppearance.apply(char)
		SpawnManager.place(char)
	end)
	-- Rig = StarterCharacter, skin appliqué dans CharacterAdded (#1).
	local ok, err = pcall(player.LoadCharacterAsync, player)
	spawning[player] = nil
	if not ok then
		conn:Disconnect()
		warn("[SpawnManager] LoadCharacterAsync a échoué pour " .. player.Name .. " :", err)
	end
	-- Demande arrivée pendant ce chargement (#157, #219) : le personnage gardé la sert, sinon un nouveau ; un échec est
	-- répondu ici, la demande compte alors comme traitée (true : pas de seconde réponse « failed »)
	if rejoin[player] then
		rejoin[player] = nil
		if not SpawnRules.isAlive(player.Character) and not SpawnManager.spawnPlayer(player) then
			reply(player, { status = "failed" })
		end
		return true
	end
	return ok
end

-- Cette méthode permet de faire réapparaître un joueur lorsque sa réapparition programmée échoit (RoundManager) :
-- rien s'il a déjà un personnage vivant (demande arrivée entre-temps) ou un LoadCharacterAsync en vol.
function SpawnManager.respawn(player: Player)
	if away[player] then
		return
	end
	if SpawnRules.scheduled(spawning[player] == true, SpawnRules.isAlive(player.Character)) then
		SpawnManager.spawnPlayer(player)
	end
end

-- Cette méthode permet de retenir l'heure de la mort d'un joueur lorsque son Humanoid meurt : une demande
-- d'apparition est refusée pendant RESPAWN_DELAY dans un round actif.
function SpawnManager.noteDeath(player: Player)
	-- Joueur déjà parti (forget passé) ou revenu au menu : rien à retenir
	if player.Parent and not away[player] then
		diedAt[player] = os.clock()
	end
end

-- Cette méthode permet de savoir si le chargement d'un personnage est en vol lorsque l'équipement (#280) refuse un
-- changement pendant une apparition.
function SpawnManager.isSpawning(player: Player): boolean
	return spawning[player] == true
end

-- Cette méthode permet d'oublier un joueur lorsqu'il quitte le jeu.
function SpawnManager.forget(player: Player)
	spawning[player] = nil
	diedAt[player] = nil
	away[player] = nil
	rejoin[player] = nil
end

-- Cette méthode permet de sortir du round un joueur revenu au menu (#157, après RoundManager.withdraw) : personnage
-- détruit, plus de réapparition, prochaine demande acceptée sans RESPAWN_DELAY (son score de la manche est perdu).
function SpawnManager.withdraw(player: Player)
	away[player] = true
	rejoin[player] = nil
	local char = player.Character
	if char then
		char:Destroy()
	end
	-- Après la destruction : une mort que Roblox annoncerait en détruisant le personnage n'est pas retenue
	diedAt[player] = nil
end

-- Cette méthode permet de brancher RequestSpawn lorsque le serveur démarre : garde commune, règles de réapparition
-- (SpawnRules.request, refus au journal), réponse au client (#219), puis beforeSpawn (démarrage du round) et apparition.
-- Une demande écartée par la garde commune (débit) reste sans réponse : le client la renvoie après un délai.
function SpawnManager.init(
	requestSpawnRemote: RemoteEvent,
	hooks: { roundState: () -> string, beforeSpawn: (Player) -> () }
)
	replyRemote = requestSpawnRemote
	roundStateFn = hooks.roundState
	requestSpawnRemote.OnServerEvent:Connect(function(player)
		-- Garde commune (#170) : débit
		if not CheatLog.admit(player, requestSpawnRemote.Name) then
			return
		end
		local now = os.clock()
		local request: SpawnRules.Request = {
			spawning = spawning[player] == true,
			hasCharacter = SpawnRules.inPlace(player.Character),
			roundState = hooks.roundState(),
			diedAt = diedAt[player],
			now = now,
			respawnDelay = GameConfig.RESPAWN_DELAY,
		}
		local refusal = SpawnRules.request(request)
		-- Retour du menu pendant une réapparition partie avant le départ : servie à la fin de son chargement (#157)
		if SpawnRules.rejoinsInFlight(refusal, away[player] == true, hooks.roundState()) then
			away[player] = nil
			rejoin[player] = true
			reply(player, SpawnRules.reply(nil, request))
			hooks.beforeSpawn(player)
			return
		end
		-- Avant le journal et le chargement : le client est fixé tout de suite, même si la suite échoue
		local live = refusal == "alive" and SpawnRules.isAlive(player.Character)
		local answer = SpawnRules.reply(refusal, request, { away = away[player] == true, live = live })
		reply(player, answer)
		-- Personnage vivant que le client reprend (il l'avait ignoré au menu) : remis au round comme une apparition,
		-- sans refus au journal
		if live then
			away[player] = nil
			hooks.beforeSpawn(player)
			return
		end
		-- Le client attend le chargement en vol : s'il échoue, la demande est servie à sa fin (nouveau chargement)
		if answer.status == "spawning" then
			rejoin[player] = true
		end
		if refusal then
			local severity = REFUSAL_SEVERITY[refusal]
			if severity then
				local detail = refusal
				if refusal == "early" then
					detail = string.format("early : %.2f s après la mort", now - (diedAt[player] :: number))
				end
				CheatLog.report(Participants.fromPlayer(player), CheatLog.Category.SPAWN, severity, detail)
			end
			return
		end
		away[player] = nil
		hooks.beforeSpawn(player)
		if not SpawnManager.spawnPlayer(player) then
			reply(player, { status = "failed" })
		end
	end)
end

return SpawnManager

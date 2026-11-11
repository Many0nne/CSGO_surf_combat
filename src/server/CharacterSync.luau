-- Position des personnages côté serveur (#75). Le mouvement est fait par le client sur une racine ancrée : rien n'est
-- répliqué par la physique. Le client envoie sa position et son cap (remote non fiable CharacterSync, NET_SYNC_RATE) ;
-- le serveur vérifie qu'elle est possible depuis le dernier point accepté, la pose sur la racine (Validator, hauteur de
-- mort, scripts serveur lisent ainsi la vraie position), puis la relaie horodatée aux autres clients, qui l'interpolent.
-- Une position impossible (seau de distance, #172) est refusée, journalisée (CheatLog) et corrigée : le client est
-- renvoyé à sa dernière position acceptée, et ses paquets envoyés avant d'avoir appliqué la correction sont ignorés.
-- Une position acceptée par le seau est ensuite jugée par les règles du noclip et du vol (#177, MovementGuardRules) :
-- rayons et surfaces de la map ici, décision dans la règle pure ; un joueur en l'air qui se tait au-dessus du vide est
-- déclaré tombé (boucle du vide).
-- Les bots (#139) n'ont pas de client : leur position, calculée par le serveur (BotMotion), passe par relayBot et suit
-- le même relais. Le relais désigne le personnage (Model), pas le Player, pour servir aux deux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local LadderRules = require(ReplicatedStorage.Shared.LadderRules)
local MapRules = require(ReplicatedStorage.Shared.MapRules)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local MovementGuardRules = require(ReplicatedStorage.Shared.MovementGuardRules)
local Participants = require(ServerScriptService.Server.Participants)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)
local SpawnLaunch = require(ReplicatedStorage.Shared.SpawnLaunch)

local CharacterSync = {}

local relayRemote: UnreliableRemoteEvent? = nil
local correctionRemote: RemoteEvent? = nil
local acceptedCallback: ((Model, Vector3) -> ())? = nil

-- Une correction restée sans réponse (s) est renvoyée : filet si le client ne l'a pas appliquée (personnage pas prêt).
local CORRECTION_RESEND = 1
-- Période (s) de la boucle du vide (joueurs silencieux tombés dans le vide).
local VOID_PERIOD = 0.25

-- Mort par chute fournie par KillZone : hauteur de mort de la map jouée, et mise à mort.
export type FallHooks = { height: () -> number?, kill: (Model) -> () }

type Track = {
	char: Model,
	lastPos: Vector3, -- dernière position acceptée, posée sur la racine
	budget: CharacterSyncRules.MoveBudget,
	-- Numéro de la dernière correction pour ce personnage (0 : aucune) : un paquet d'un numéro inférieur est parti
	-- d'une position déjà refusée. Gardé après l'accusé (paquets non fiables, donc parfois en désordre).
	requiredAck: number,
	acked: boolean, -- un paquet portant requiredAck est arrivé
	correctedAt: number,
	refusedAt: number, -- heure du dernier refus (une correction renvoyée ne la change pas)
	guard: MovementGuardRules.Guard, -- noclip, vol et vide (#177)
	voidReportedAt: number, -- dernier signalement du vide (journal seul : un par VOID_SILENCE)
	yaw: number?, -- dernier cap accepté et son heure de réception (os.clock), lus par les stats de visée (#178)
	yawAt: number?,
}

local tracks: { [Player]: Track } = {}
-- Numéro de la dernière correction envoyée à chaque joueur : croissant sur toute la session (même à travers les
-- réapparitions), pour qu'un accusé de réception ancien ne valide jamais une correction plus récente.
local correctionSeqs: { [Player]: number } = {}

-- Historique des positions acceptées par personnage (Model : joueurs et bots, vide à chaque réapparition), pour le
-- rembobinage (#173). Supprimé à la destruction du personnage (mort, départ, bot retiré), clés faibles en filet.
local histories: { [Model]: PositionHistory.History } = setmetatable({}, { __mode = "k" }) :: any

-- Géométrie de la map vue par les règles D2 (#177) : nil tant que la map jouée n'est pas trouvée (règles suspendues).
local geometry: MovementGuardRules.Geometry? = nil
-- Règle du vide : une pièce de la map (sol, ou volume d'échelle ou de boost qui rattrape) dans une boîte ? nil tant que
-- la map jouée n'est pas trouvée.
local floorIn: ((CFrame, Vector3) -> boolean)? = nil

-- Cette méthode permet de préparer la géométrie des règles D2 lorsque la map jouée est trouvée : rayons et requêtes
-- limités à la map et à ses pièces qui collisionnent (parois sans collision, volumes d'échelle et de boost exclus),
-- échelles (support) et boosts qui imposent une vitesse (geysers, lanceurs) relevés une fois, la map étant fixe.
-- Renvoie aussi la recherche de sol de la règle du vide, qui compte en plus les volumes d'échelle et de boost.
local function buildGeometry(map: Instance): (MovementGuardRules.Geometry, (CFrame, Vector3) -> boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	params.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { map }
	overlap.RespectCanCollide = true

	local ladders: { BasePart } = {}
	local ladderFolder = map:FindFirstChild(LadderRules.LADDERS_FOLDER)
	for _, part in if ladderFolder then ladderFolder:GetChildren() else {} do
		if part:IsA("BasePart") then
			table.insert(ladders, part)
		end
	end
	local boosts: { { part: BasePart, vy: number } } = {}
	local boostFolder = map:FindFirstChild(MapRules.BOOSTS_FOLDER)
	for _, part in if boostFolder then boostFolder:GetChildren() else {} do
		local velocity = part:GetAttribute(MapRules.VELOCITY_ATTRIBUTE)
		local kind = part:GetAttribute(MapRules.KIND_ATTRIBUTE)
		if part:IsA("BasePart") and (kind == "Geyser" or kind == "Launcher") and typeof(velocity) == "Vector3" then
			-- Vitesse réellement imposée au client (bornée comme dans BoostSystem)
			local imposed = MapRules.imposedVelocity(velocity)
			table.insert(boosts, { part = part, vy = imposed.Y })
		end
	end
	local volumeRoots: { Instance } = {}
	if ladderFolder then
		table.insert(volumeRoots, ladderFolder)
	end
	if boostFolder then
		table.insert(volumeRoots, boostFolder)
	end
	local volumes = OverlapParams.new()
	volumes.FilterType = Enum.RaycastFilterType.Include
	volumes.FilterDescendantsInstances = volumeRoots

	-- Cette méthode permet de savoir si un joueur silencieux a pu se poser dans une boîte lorsque la règle du vide la
	-- fouille : pièce de la map qui collisionne, ou volume d'échelle ou de boost qui l'aurait rattrapé.
	local function hasFloorIn(cf: CFrame, size: Vector3): boolean
		return #workspace:GetPartBoundsInBox(cf, size, overlap) > 0
			or (#volumeRoots > 0 and #workspace:GetPartBoundsInBox(cf, size, volumes) > 0)
	end

	return {
		-- Cette méthode permet de savoir si un rayon de a vers b touche une paroi de la map lorsque le noclip juge un
		-- segment ou un détour.
		isBlocked = function(a: Vector3, b: Vector3): boolean
			return workspace:Raycast(a, b - a, params) ~= nil
		end,
		-- Cette méthode permet de savoir si un segment est porté lorsque le vol le juge : vitesse imposée par un boost
		-- touché, échelle traversée, ou pièce proche d'un de ses points (pièces candidates : sphère qui couvre le segment).
		support = function(from: Vector3, to: Vector3): (boolean, number)
			local boostVy = 0
			for _, boost in boosts do
				if MovementGuardRules.touchesVolume(from, to, boost.part.CFrame, boost.part.Size) then
					boostVy = math.max(boostVy, boost.vy)
				end
			end
			for _, ladder in ladders do
				if MovementGuardRules.touchesVolume(from, to, ladder.CFrame, ladder.Size) then
					return true, boostVy
				end
			end
			local radius = MovementGuardRules.SUPPORT_REACH + (to - from).Magnitude / 2
			local parts = workspace:GetPartBoundsInRadius((from + to) / 2, radius, overlap)
			return MovementGuardRules.supportedAlong(parts, from, to), boostVy
		end,
	},
		hasFloorIn
end

-- Cette méthode permet d'ajouter une position acceptée et sa pose (cap, accroupi, #213) à l'historique du personnage
-- lorsqu'elle est posée ; l'historique est créé au premier relevé, sauf si le personnage est déjà retiré du monde
-- (Destroying ne se déclencherait plus). Coût relevé sous le repère « srv historique ».
local function recordPosition(char: Model, pos: Vector3, yaw: number, crouching: boolean, stamp: number)
	local startedAt = os.clock()
	local history = histories[char]
	if not history and not char:IsDescendantOf(game) then
		return
	end
	if not history then
		history = PositionHistory.new()
		histories[char] = history
		char.Destroying:Once(function()
			histories[char] = nil
		end)
	end
	PositionHistory.record(history, stamp, pos, yaw, crouching)
	PerfMarkers.record("srv historique", os.clock() - startedAt)
end

-- Cette méthode permet de (re)partir de la position serveur de la racine lorsqu'un paquet arrive pour un personnage
-- neuf (spawn, réapparition) : c'est le point posé par SpawnManager, seule référence sûre.
local function trackFor(player: Player, char: Model, root: BasePart, now: number): Track
	local track = tracks[player]
	if not track or track.char ~= char then
		-- Lancement depuis le soleil (#69, SpawnManager) : sa vitesse verticale ouvre l'enveloppe du vol
		local launch = char:GetAttribute(SpawnLaunch.VELOCITY_ATTRIBUTE)
		track = {
			char = char,
			lastPos = root.Position,
			budget = CharacterSyncRules.newBudget(now),
			requiredAck = 0,
			acked = true,
			correctedAt = -math.huge,
			refusedAt = -math.huge,
			voidReportedAt = -math.huge,
			guard = MovementGuardRules.newGuard(
				now,
				root.Position,
				if typeof(launch) == "Vector3" then launch.Y else nil
			),
		}
		tracks[player] = track
	end
	return track
end

-- Cette méthode permet d'envoyer (ou de renvoyer) au client la correction en attente lorsqu'un paquet est refusé ou
-- que la correction reste sans réponse : personnage, dernière position acceptée et numéro de la correction.
local function fireCorrection(player: Player, track: Track, now: number)
	track.correctedAt = now
	if correctionRemote then
		correctionRemote:FireClient(player, track.char, track.lastPos, track.requiredAck)
	end
end

-- Cette méthode permet de journaliser un déplacement impossible lorsqu'une règle le refuse (catégorie Movement,
-- gravité moyenne : un vrai lag peut en produire un).
local function reportMove(player: Player, detail: string)
	CheatLog.report(Participants.fromPlayer(player), CheatLog.Category.MOVEMENT, CheatLog.Severity.MEDIUM, detail)
end

-- Cette méthode permet de refuser un paquet lorsqu'une règle de déplacement le juge impossible (seau de distance ;
-- réutilisable par les règles suivantes, noclip et vol #177) : violation journalisée, puis le client est renvoyé à sa
-- dernière position acceptée et ses paquets sont ignorés jusqu'à ce qu'il l'ait appliquée.
local function refuse(player: Player, track: Track, detail: string, now: number)
	reportMove(player, detail)
	local seq = (correctionSeqs[player] or 0) + 1
	correctionSeqs[player] = seq
	track.requiredAck = seq
	track.acked = false
	track.refusedAt = now
	-- Le client repart de lastPos vitesse nulle : l'enveloppe du vol aussi (et un client qui n'accuse jamais réception
	-- au-dessus du vide finit déclaré tombé)
	MovementGuardRules.restart(track.guard.flight, now, track.lastPos.Y)
	fireCorrection(player, track, now)
end

-- Cette méthode permet de juger un paquet accepté par le seau avec les règles du noclip et du vol lorsque la map est
-- prête ; renvoie true si le paquet est refusé (mode bloquant), false s'il est accepté (violation au journal seul).
local function judgeGuard(player: Player, track: Track, pos: Vector3, now: number): boolean
	local geo = geometry
	if not geo then
		return false
	end
	local startedAt = os.clock()
	local verdict = MovementGuardRules.judge(track.guard, track.lastPos, pos, now, geo)
	PerfMarkers.record("srv anti-vol", os.clock() - startedAt)
	if not verdict then
		return false
	end
	if verdict.enforce then
		refuse(player, track, verdict.detail, now)
		return true
	end
	reportMove(player, verdict.detail)
	return false
end

-- Cette méthode permet de traiter la position annoncée par un client lorsqu'elle arrive : forme vérifiée, paquet
-- antérieur à la dernière correction ignoré, seau de distance jugé, puis racine déplacée, hauteur de mort testée et
-- position relayée aux autres joueurs. ack = numéro de la dernière correction appliquée par le client ; crouching =
-- accroupi (#213), gardé dans l'historique (non relayé : le rig 3P ne s'accroupit pas).
local function onClientPosition(
	remote: UnreliableRemoteEvent,
	onAccepted: (Model, Vector3) -> (),
	player: Player,
	pos: any,
	yaw: any,
	ack: any,
	crouching: any
)
	if not CharacterSyncRules.isWellFormed(pos, yaw) or type(ack) ~= "number" or type(crouching) ~= "boolean" then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	local track = trackFor(player, char, root, now)
	-- Le client vit, même si ce paquet est ignoré ci-dessous (règle du vide) ; sauf s'il ignore sa correction depuis
	-- VOID_SILENCE : au-dessus du vide, il finit déclaré tombé
	local stale = CharacterSyncRules.awaitsAck(track.requiredAck, ack)
	if not stale or track.acked or now - track.refusedAt < MovementGuardRules.VOID_SILENCE then
		track.guard.heardAt = now
	end
	-- Envoyé avant d'avoir appliqué la correction : ni jugé ni journalisé (le temps continue de remplir le seau)
	if stale then
		if not track.acked and now - track.correctedAt >= CORRECTION_RESEND then
			fireCorrection(player, track, now)
		end
		return
	end
	track.acked = true
	-- Pas de délai minimal entre deux paquets : des paquets groupés passent, chacun consomme le seau (débit borné par
	-- la garde commune, RemoteGuard)
	local silence = now - track.budget.lastAt
	if not CharacterSyncRules.tryMove(track.budget, track.lastPos, pos, now) then
		local distance = (pos - track.lastPos).Magnitude
		local detail = string.format("déplacement de %.1f studs en %.2f s refusé", distance, silence)
		if CharacterSyncRules.ENFORCE_MOVEMENT then
			refuse(player, track, detail, now)
			return
		end
		-- Journal seul : violation comptée, déplacement appliqué quand même, seau vidé
		reportMove(player, detail)
		track.budget.stored = 0
	end
	-- Noclip et vol (#177) : refus et correction en mode bloquant, journal seul sinon
	if judgeGuard(player, track, pos, now) then
		return
	end
	track.lastPos = pos
	track.yaw = yaw
	track.yawAt = now
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

	local stamp = workspace:GetServerTimeNow()
	recordPosition(char, pos, yaw, crouching, stamp)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remote:FireClient(other, char, pos, yaw, stamp)
		end
	end
	onAccepted(char, pos)
end

-- Cette méthode permet de déclarer tombé un joueur silencieux lorsque la boucle du vide le trouve en l'air au-dessus
-- du vide depuis trop longtemps (MovementGuardRules.fellIntoVoid) : journal (gravité faible, une coupure réseau en
-- produit aussi), puis mort, ou en journal seul un signalement au plus par VOID_SILENCE.
local function checkVoid(fall: FallHooks)
	local hasFloorIn = floorIn
	local killHeight = fall.height()
	if not hasFloorIn or not killHeight then
		return
	end
	local now = os.clock()
	for player, track in tracks do
		local hum = track.char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or now - track.voidReportedAt < MovementGuardRules.VOID_SILENCE then
			continue
		end
		-- Cette méthode permet de chercher un sol dans la zone où le joueur a pu atterrir lorsque la règle du vide a
		-- écarté tout le reste (requête la plus coûteuse, appelée en dernier).
		local function hasFloor(): boolean
			local cf, size = MovementGuardRules.voidProbe(track.guard, track.lastPos, now, killHeight)
			return hasFloorIn(cf, size)
		end
		local fell = MovementGuardRules.fellIntoVoid(track.guard, now, killHeight, hasFloor)
		if fell then
			track.voidReportedAt = now
			CheatLog.report(
				Participants.fromPlayer(player),
				CheatLog.Category.MOVEMENT,
				CheatLog.Severity.LOW,
				string.format(
					"vide : en l'air sans position depuis %.1f s, déclaré tombé",
					now - track.guard.heardAt
				)
			)
			if MovementGuardRules.ENFORCE_VOID then
				fall.kill(track.char)
			end
		end
	end
end

-- Cette méthode permet de brancher la réception des positions lorsque le serveur démarre ; onAccepted reçoit chaque
-- position acceptée (hauteur de mort), correction renvoie un client refusé à sa dernière position acceptée, fall donne
-- la hauteur de mort et la mise à mort pour un joueur silencieux tombé dans le vide.
function CharacterSync.init(
	remote: UnreliableRemoteEvent,
	correction: RemoteEvent,
	onAccepted: (Model, Vector3) -> (),
	fall: FallHooks
)
	relayRemote = remote
	correctionRemote = correction
	acceptedCallback = onAccepted
	task.spawn(function()
		local map = MapSelection.waitForActive(30)
		if map then
			geometry, floorIn = buildGeometry(map)
		else
			warn("[CharacterSync] map jouée introuvable : noclip, vol et vide non surveillés")
		end
	end)
	local sinceVoidCheck = 0
	-- Cette méthode permet de passer en revue les joueurs silencieux toutes les VOID_PERIOD secondes lorsque le serveur
	-- avance d'une frame (coût relevé sous le repère « srv vide »).
	RunService.Heartbeat:Connect(function(dt: number)
		sinceVoidCheck += dt
		if sinceVoidCheck < VOID_PERIOD then
			return
		end
		sinceVoidCheck = 0
		local startedAt = os.clock()
		checkVoid(fall)
		PerfMarkers.record("srv vide", os.clock() - startedAt)
	end)
	remote.OnServerEvent:Connect(function(player, pos, yaw, ack, crouching)
		-- Garde commune (#170) : débit et types (Vector3, angle et numéro de correction finis, accroupi booléen)
		if not CheatLog.admit(player, remote.Name, pos, yaw, ack, crouching) then
			return
		end
		onClientPosition(remote, onAccepted, player, pos, yaw, ack, crouching)
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		correctionSeqs[player] = nil
	end)
end

-- Cette méthode permet de publier la position d'un bot lorsque son mouvement serveur atteint la cadence réseau : racine
-- serveur posée (Validator, hauteur de mort), position relayée horodatée à tous les clients, comme celle d'un joueur.
function CharacterSync.relayBot(char: Model, root: BasePart, cf: CFrame)
	root.CFrame = cf
	local remote = relayRemote
	if not remote then
		return
	end
	local pos = cf.Position
	local yaw = CharacterSyncRules.yawOf(cf.LookVector)
	local stamp = workspace:GetServerTimeNow()
	-- Les bots ne s'accroupissent pas (BotMotion)
	recordPosition(char, pos, yaw, false, stamp)
	remote:FireAllClients(char, pos, yaw, stamp)
	if acceptedCallback then
		acceptedCallback(char, pos)
	end
end

-- Cette méthode permet de lire le dernier cap accepté d'un joueur et son heure de réception (os.clock) lorsqu'un tir
-- arrive (flick, statistiques de visée #178) ; nil pour un personnage sans paquet accepté (autre que le sien actuel).
function CharacterSync.lastYaw(player: Player): (number?, number?)
	local track = tracks[player]
	if not track or track.char ~= player.Character then
		return nil, nil
	end
	return track.yaw, track.yawAt
end

-- Cette méthode permet de connaître la position et la pose (cap en rad, accroupi, #213) d'un personnage à l'instant t
-- (horloge serveur, ex. shotTime) lorsque le serveur valide un tir ou un coup (#174, #176) : t est borné à
-- [maintenant - MAX_REWIND, maintenant], interpolé entre deux relevés. nil si le personnage n'a pas encore d'historique.
function CharacterSync.positionAt(char: Model, t: number): (Vector3?, number?, boolean?)
	local history = histories[char]
	if not history then
		return nil, nil, nil
	end
	return PositionHistory.sampleAt(history, t, workspace:GetServerTimeNow())
end

return CharacterSync

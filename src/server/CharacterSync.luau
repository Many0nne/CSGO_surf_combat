-- Position des personnages côté serveur (#75). Le mouvement est fait par le client sur une racine ancrée : rien n'est
-- répliqué par la physique. Le client envoie sa position et son cap (remote non fiable CharacterSync, NET_SYNC_RATE) ;
-- le serveur vérifie qu'elle est possible depuis le dernier point accepté, la pose sur la racine (Validator, hauteur de
-- mort, scripts serveur lisent ainsi la vraie position), puis la relaie horodatée aux autres clients, qui l'interpolent.
-- Une position impossible est ignorée (dernier point valide gardé) avec un warn, sans renvoyer le client en arrière.
-- Les bots (#139) n'ont pas de client : leur position, calculée par le serveur (BotMotion), passe par relayBot et suit
-- le même relais. Le relais désigne le personnage (Model), pas le Player, pour servir aux deux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)

local CharacterSync = {}

local relayRemote: UnreliableRemoteEvent? = nil
local acceptedCallback: ((Model, Vector3) -> ())? = nil

-- Délai minimal entre deux warns de rejet pour un même joueur (s).
local WARN_INTERVAL = 2

type Track = {
	char: Model,
	lastPos: Vector3,
	lastAt: number,
	lastReceivedAt: number,
	lastWarnAt: number,
}

local tracks: { [Player]: Track } = {}

-- Cette méthode permet de (re)partir de la position serveur de la racine lorsqu'un paquet arrive pour un personnage
-- neuf (spawn, réapparition) : c'est le point posé par SpawnManager, seule référence sûre.
local function trackFor(player: Player, char: Model, root: BasePart, now: number): Track
	local track = tracks[player]
	if not track or track.char ~= char then
		track =
			{ char = char, lastPos = root.Position, lastAt = now, lastReceivedAt = -math.huge, lastWarnAt = -math.huge }
		tracks[player] = track
	end
	return track
end

-- Cette méthode permet de signaler un paquet rejeté lorsqu'il est impossible, au plus une fois par WARN_INTERVAL.
local function warnRejected(player: Player, track: Track, pos: Vector3, now: number)
	if now - track.lastWarnAt < WARN_INTERVAL then
		return
	end
	track.lastWarnAt = now
	warn(
		string.format(
			"[CharacterSync] position rejetée pour %s : %.1f studs en %.2f s",
			player.Name,
			(pos - track.lastPos).Magnitude,
			now - track.lastAt
		)
	)
end

-- Cette méthode permet de traiter la position annoncée par un client lorsqu'elle arrive : forme, cadence et
-- plausibilité vérifiées, puis racine déplacée, hauteur de mort testée et position relayée aux autres joueurs.
local function onClientPosition(
	remote: UnreliableRemoteEvent,
	onAccepted: (Model, Vector3) -> (),
	player: Player,
	pos: any,
	yaw: any
)
	if not CharacterSyncRules.isWellFormed(pos, yaw) then
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
	-- Plus de deux fois la cadence prévue : paquet en trop ignoré (flood)
	if now - track.lastReceivedAt < CharacterSyncRules.SEND_INTERVAL * 0.5 then
		return
	end
	track.lastReceivedAt = now
	if not CharacterSyncRules.isPlausibleMove(track.lastPos, pos, now - track.lastAt) then
		warnRejected(player, track, pos, now)
		return
	end
	track.lastPos = pos
	track.lastAt = now
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

	local stamp = workspace:GetServerTimeNow()
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remote:FireClient(other, char, pos, yaw, stamp)
		end
	end
	onAccepted(char, pos)
end

-- Cette méthode permet de brancher la réception des positions lorsque le serveur démarre ; onAccepted reçoit chaque
-- position acceptée (hauteur de mort).
function CharacterSync.init(remote: UnreliableRemoteEvent, onAccepted: (Model, Vector3) -> ())
	relayRemote = remote
	acceptedCallback = onAccepted
	remote.OnServerEvent:Connect(function(player, pos, yaw)
		onClientPosition(remote, onAccepted, player, pos, yaw)
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
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
	remote:FireAllClients(char, pos, CharacterSyncRules.yawOf(cf.LookVector), workspace:GetServerTimeNow())
	if acceptedCallback then
		acceptedCallback(char, pos)
	end
end

return CharacterSync

-- Position des personnages côté serveur (#75). Le mouvement est fait par le client sur une racine ancrée : rien n'est
-- répliqué par la physique. Le client envoie sa position et son cap (remote non fiable CharacterSync, NET_SYNC_RATE) ;
-- le serveur vérifie qu'elle est possible depuis le dernier point accepté, la pose sur la racine (Validator, hauteur de
-- mort, scripts serveur lisent ainsi la vraie position), puis la relaie horodatée aux autres clients, qui l'interpolent.
-- Une position impossible (seau de distance, #172) est refusée, journalisée (CheatLog) et corrigée : le client est
-- renvoyé à sa dernière position acceptée, et ses paquets envoyés avant d'avoir appliqué la correction sont ignorés.
-- Les bots (#139) n'ont pas de client : leur position, calculée par le serveur (BotMotion), passe par relayBot et suit
-- le même relais. Le relais désigne le personnage (Model), pas le Player, pour servir aux deux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local Participants = require(ServerScriptService.Server.Participants)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)

local CharacterSync = {}

local relayRemote: UnreliableRemoteEvent? = nil
local correctionRemote: RemoteEvent? = nil
local acceptedCallback: ((Model, Vector3) -> ())? = nil

-- Une correction restée sans réponse (s) est renvoyée : filet si le client ne l'a pas appliquée (personnage pas prêt).
local CORRECTION_RESEND = 1

type Track = {
	char: Model,
	lastPos: Vector3, -- dernière position acceptée, posée sur la racine
	budget: CharacterSyncRules.MoveBudget,
	-- Numéro de la dernière correction pour ce personnage (0 : aucune) : un paquet d'un numéro inférieur est parti
	-- d'une position déjà refusée. Gardé après l'accusé (paquets non fiables, donc parfois en désordre).
	requiredAck: number,
	acked: boolean, -- un paquet portant requiredAck est arrivé
	correctedAt: number,
}

local tracks: { [Player]: Track } = {}
-- Numéro de la dernière correction envoyée à chaque joueur : croissant sur toute la session (même à travers les
-- réapparitions), pour qu'un accusé de réception ancien ne valide jamais une correction plus récente.
local correctionSeqs: { [Player]: number } = {}

-- Historique des positions acceptées par personnage (Model : joueurs et bots, vide à chaque réapparition), pour le
-- rembobinage (#173). Supprimé à la destruction du personnage (mort, départ, bot retiré), clés faibles en filet.
local histories: { [Model]: PositionHistory.History } = setmetatable({}, { __mode = "k" }) :: any

-- Cette méthode permet d'ajouter une position acceptée à l'historique du personnage lorsqu'elle est posée ; l'historique
-- est créé au premier relevé, sauf si le personnage est déjà retiré du monde (Destroying ne se déclencherait plus).
local function recordPosition(char: Model, pos: Vector3, stamp: number)
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
	PositionHistory.record(history, stamp, pos)
end

-- Cette méthode permet de (re)partir de la position serveur de la racine lorsqu'un paquet arrive pour un personnage
-- neuf (spawn, réapparition) : c'est le point posé par SpawnManager, seule référence sûre.
local function trackFor(player: Player, char: Model, root: BasePart, now: number): Track
	local track = tracks[player]
	if not track or track.char ~= char then
		track = {
			char = char,
			lastPos = root.Position,
			budget = CharacterSyncRules.newBudget(now),
			requiredAck = 0,
			acked = true,
			correctedAt = -math.huge,
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
	fireCorrection(player, track, now)
end

-- Cette méthode permet de traiter la position annoncée par un client lorsqu'elle arrive : forme vérifiée, paquet
-- antérieur à la dernière correction ignoré, seau de distance jugé, puis racine déplacée, hauteur de mort testée et
-- position relayée aux autres joueurs. ack = numéro de la dernière correction appliquée par le client.
local function onClientPosition(
	remote: UnreliableRemoteEvent,
	onAccepted: (Model, Vector3) -> (),
	player: Player,
	pos: any,
	yaw: any,
	ack: any
)
	if not CharacterSyncRules.isWellFormed(pos, yaw) or type(ack) ~= "number" then
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
	-- Envoyé avant d'avoir appliqué la correction : ni jugé ni journalisé (le temps continue de remplir le seau)
	if CharacterSyncRules.awaitsAck(track.requiredAck, ack) then
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
	track.lastPos = pos
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

	local stamp = workspace:GetServerTimeNow()
	recordPosition(char, pos, stamp)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remote:FireClient(other, char, pos, yaw, stamp)
		end
	end
	onAccepted(char, pos)
end

-- Cette méthode permet de brancher la réception des positions lorsque le serveur démarre ; onAccepted reçoit chaque
-- position acceptée (hauteur de mort), correction renvoie un client refusé à sa dernière position acceptée.
function CharacterSync.init(remote: UnreliableRemoteEvent, correction: RemoteEvent, onAccepted: (Model, Vector3) -> ())
	relayRemote = remote
	correctionRemote = correction
	acceptedCallback = onAccepted
	remote.OnServerEvent:Connect(function(player, pos, yaw, ack)
		-- Garde commune (#170) : débit et types (Vector3, angle et numéro de correction finis)
		if not CheatLog.admit(player, remote.Name, pos, yaw, ack) then
			return
		end
		onClientPosition(remote, onAccepted, player, pos, yaw, ack)
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
	local stamp = workspace:GetServerTimeNow()
	recordPosition(char, pos, stamp)
	remote:FireAllClients(char, pos, CharacterSyncRules.yawOf(cf.LookVector), stamp)
	if acceptedCallback then
		acceptedCallback(char, pos)
	end
end

-- Cette méthode permet de connaître la position d'un personnage à l'instant t (horloge serveur, ex. shotTime) lorsque
-- le serveur valide un tir ou un coup (#174, #176) : t est borné à [maintenant - MAX_REWIND, maintenant], interpolé
-- entre deux relevés. nil si le personnage n'a pas encore d'historique.
function CharacterSync.positionAt(char: Model, t: number): Vector3?
	local history = histories[char]
	if not history then
		return nil
	end
	return PositionHistory.sampleAt(history, t, workspace:GetServerTimeNow())
end

return CharacterSync

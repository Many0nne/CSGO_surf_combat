-- Bruits de pas (#146), moitié serveur : chaque position acceptée d'un joueur (CharacterSync, après validation) ou
-- publiée pour un bot (relayBot) passe par observe. Le sol sous le personnage est sondé comme par le mouvement
-- (GroundDetection : une rampe de surf n'est pas un sol), puis FootstepRules dit s'il fait un pas ou atterrit. Chaque
-- bruit est relayé aux autres clients (remote Footstep : personnage, position des pieds, "step" | "land"), pas à son
-- auteur (son client joue ses pas lui-même, sans latence), et passé à onStep (ouïe des bots).
-- Les positions arrivent à NET_SYNC_RATE, parfois groupées : elles sont cumulées sur au moins MIN_SAMPLE avant d'être
-- jugées, sinon deux paquets reçus ensemble donneraient une vitesse absurde.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterDimensions = require(ReplicatedStorage.Shared.movement.CharacterDimensions)
local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local FootstepRules = require(ReplicatedStorage.Shared.FootstepRules)
local GroundDetection = require(ReplicatedStorage.Shared.movement.GroundDetection)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local FootstepService = {}

-- Durée minimale (s) d'un échantillon jugé : un peu moins que l'intervalle d'envoi.
local MIN_SAMPLE = 0.8 * CharacterSyncRules.SEND_INTERVAL

type Track = {
	state: FootstepRules.State,
	ground: GroundDetection.GroundDetection,
	feet: number, -- distance racine → pieds (debout)
	lastPos: Vector3,
	lastAt: number, -- instant du dernier jugement
	startY: number, -- hauteur au dernier jugement
	distance: number, -- distance horizontale cumulée depuis le dernier jugement
	grounded: boolean,
}

local tracks: { [Model]: Track } = {}
local remote: UnreliableRemoteEvent? = nil
local onStep: ((Model, Vector3, FootstepRules.Kind) -> ())? = nil

-- Cette méthode permet de préparer le suivi des pas d'un personnage à sa première position (dimensions mesurées sur son
-- rig, sonde de sol propre) ; nil s'il n'a pas de racine ou n'est plus dans le jeu.
local function trackFor(char: Model, pos: Vector3, now: number): Track?
	local track = tracks[char]
	if track then
		return track
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or not char:IsDescendantOf(game) then
		return nil
	end
	local dims = CharacterDimensions.new(char, root)
	local stand = dims:getStand()
	track = {
		state = FootstepRules.new(),
		ground = GroundDetection.new(char, dims),
		feet = stand.halfHeight - stand.centerOffset,
		lastPos = pos,
		lastAt = now,
		startY = pos.Y,
		distance = 0,
		grounded = true,
	}
	tracks[char] = track
	char.Destroying:Once(function()
		tracks[char] = nil
	end)
	return track
end

-- Cette méthode permet de relayer un pas lorsqu'il vient d'être détecté : à tous les clients sauf celui de son auteur,
-- puis à l'ouïe des bots.
local function emit(char: Model, feetPos: Vector3, kind: FootstepRules.Kind)
	local r = remote
	if r then
		local owner = Players:GetPlayerFromCharacter(char)
		for _, player in Players:GetPlayers() do
			if player ~= owner then
				r:FireClient(player, char, feetPos, kind)
			end
		end
	end
	if onStep then
		onStep(char, feetPos, kind)
	end
end

-- Cette méthode permet de juger la nouvelle position d'un personnage lorsqu'elle est acceptée par le serveur : au sol
-- ou non (sonde du mouvement), distance cumulée, puis pas ou atterrissage relayé.
local function observe(char: Model, pos: Vector3)
	local now = os.clock()
	local track = trackFor(char, pos, now)
	if not track then
		return
	end
	local delta = pos - track.lastPos
	track.distance += Vector3.new(delta.X, 0, delta.Z).Magnitude
	track.lastPos = pos
	local elapsed = now - track.lastAt
	if elapsed < MIN_SAMPLE then
		return
	end
	-- Vitesse verticale de l'échantillon : la sonde ne pose pas au sol un personnage qui monte vite (saut, rampe)
	local vy = (pos.Y - track.startY) / elapsed
	local info = track.ground:getGroundInfo(pos, vy, track.grounded)
	track.grounded = info.onGround
	local kind = FootstepRules.update(track.state, elapsed, info.onGround, track.distance)
	track.lastAt = now
	track.startY = pos.Y
	track.distance = 0
	if kind then
		emit(char, pos - Vector3.new(0, track.feet, 0), kind)
	end
end

-- Cette méthode permet de brancher le relais des pas lorsque le serveur démarre ; listener reçoit chaque pas
-- (personnage, position des pieds, genre) pour l'ouïe des bots.
function FootstepService.init(
	footstepRemote: UnreliableRemoteEvent,
	listener: (Model, Vector3, FootstepRules.Kind) -> ()
)
	remote = footstepRemote
	onStep = listener
end

FootstepService.observe = PerfMarkers.wrap("srv pas", observe) :: (Model, Vector3) -> ()

return FootstepService

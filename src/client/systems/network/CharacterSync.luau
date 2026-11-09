-- Moitié client de la synchro de position (#75, cf. server/CharacterSync) : envoie la position du personnage local à
-- NET_SYNC_RATE, et affiche les autres personnages (joueurs et bots, #139) à la position relayée par le serveur,
-- interpolée avec INTERP_DELAY de retard (les racines sont ancrées : sans cela, ils restent figés à leur apparition).
-- Le relais désigne le personnage (Model) : un bot n'a pas de Player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

-- Avant le mouvement local et la caméra : les autres personnages sont placés avant que la frame ne soit dessinée.
local BIND_NAME = "RemoteCharacters"

local CharacterSync = {}

type Remote = { buffer: { CharacterSyncRules.Snapshot } }

local remote: UnreliableRemoteEvent? = nil
local remotes: { [Model]: Remote } = {}
local sendAccumulator = 0

-- Cette méthode permet de ranger la position d'un autre personnage lorsque le serveur la relaie ; un personnage neuf
-- (réapparition) a son propre tampon et ne glisse donc pas depuis le lieu de sa mort. Un personnage pas encore
-- répliqué arrive à nil : paquet ignoré, le suivant le remplace.
local function onRelayed(char: any, pos: any, yaw: any, stamp: any)
	if typeof(char) ~= "Instance" or not char:IsA("Model") or type(stamp) ~= "number" then
		return
	end
	if not CharacterSyncRules.isWellFormed(pos, yaw) then
		return
	end
	local entry = remotes[char]
	if not entry then
		entry = { buffer = {} }
		remotes[char] = entry
	end
	CharacterSyncRules.push(entry.buffer, { t = stamp, pos = pos, yaw = yaw })
end

-- Cette méthode permet de placer chaque autre personnage à sa position interpolée lorsque le client dessine une
-- frame ; un personnage retiré du jeu (mort, joueur parti, bot retiré) est oublié.
local function placeRemoteCharacters()
	local renderTime = workspace:GetServerTimeNow() - CharacterSyncRules.INTERP_DELAY
	for char, entry in remotes do
		if not char.Parent then
			remotes[char] = nil
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos, yaw = CharacterSyncRules.sample(entry.buffer, renderTime)
		if root and pos and yaw then
			root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		end
	end
end

-- Cette méthode permet de démarrer la réception et l'affichage des autres personnages lorsque le client démarre.
function CharacterSync.init()
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.CHARACTER_SYNC, 15)
		if not found or not found:IsA("UnreliableRemoteEvent") then
			warn("[CharacterSync] remote " .. NetworkProtocol.Names.CHARACTER_SYNC .. " introuvable")
			return
		end
		remote = found
		found.OnClientEvent:Connect(onRelayed)
	end)
	RunService:BindToRenderStep(
		BIND_NAME,
		Enum.RenderPriority.Camera.Value - 2,
		PerfMarkers.wrap("autres joueurs", placeRemoteCharacters)
	)
end

-- Cette méthode permet d'estimer la vitesse d'un autre personnage d'après ses deux dernières positions relayées
-- lorsque son corps devient un ragdoll (#102) ; vecteur nul faute de deux positions.
function CharacterSync.velocityOf(char: Model): Vector3
	local entry = remotes[char]
	local buffer = entry and entry.buffer
	if not buffer or #buffer < 2 then
		return Vector3.zero
	end
	local last, previous = buffer[#buffer], buffer[#buffer - 1]
	local dt = last.t - previous.t
	if dt <= 1e-3 then
		return Vector3.zero
	end
	return (last.pos - previous.pos) / dt
end

-- Cette méthode permet d'envoyer la position et le cap du personnage local au serveur lorsque le mouvement vient
-- d'avancer d'une frame (dt), au plus NET_SYNC_RATE fois par seconde.
function CharacterSync.send(hrp: BasePart, dt: number)
	sendAccumulator += dt
	if not remote or sendAccumulator < CharacterSyncRules.SEND_INTERVAL then
		return
	end
	sendAccumulator = math.min(sendAccumulator - CharacterSyncRules.SEND_INTERVAL, CharacterSyncRules.SEND_INTERVAL)
	remote:FireServer(hrp.Position, CharacterSyncRules.yawOf(hrp.CFrame.LookVector))
end

return CharacterSync

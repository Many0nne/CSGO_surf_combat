-- Moitié client de la synchro de position (#75, cf. server/CharacterSync) : envoie la position du personnage local à
-- NET_SYNC_RATE, et affiche les autres joueurs à la position relayée par le serveur, interpolée avec INTERP_DELAY de
-- retard (les racines sont ancrées : sans cela, ils restent figés à leur point d'apparition).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

-- Avant le mouvement local et la caméra : les autres joueurs sont placés avant que la frame ne soit dessinée.
local BIND_NAME = "RemoteCharacters"

local CharacterSync = {}

type Remote = { char: Model?, buffer: { CharacterSyncRules.Snapshot } }

local remote: UnreliableRemoteEvent? = nil
local remotes: { [Player]: Remote } = {}
local sendAccumulator = 0

-- Cette méthode permet de ranger la position d'un autre joueur lorsque le serveur la relaie ; un personnage neuf
-- (réapparition) repart d'un tampon vide pour ne pas glisser depuis le lieu de sa mort.
local function onRelayed(other: Player, pos: any, yaw: any, stamp: any)
	if typeof(other) ~= "Instance" or not other:IsA("Player") or type(stamp) ~= "number" then
		return
	end
	if not CharacterSyncRules.isWellFormed(pos, yaw) then
		return
	end
	local entry = remotes[other]
	if not entry or entry.char ~= other.Character then
		entry = { char = other.Character, buffer = {} }
		remotes[other] = entry
	end
	CharacterSyncRules.push(entry.buffer, { t = stamp, pos = pos, yaw = yaw })
end

-- Cette méthode permet de placer chaque autre joueur à sa position interpolée lorsque le client dessine une frame.
local function placeRemoteCharacters()
	local renderTime = workspace:GetServerTimeNow() - CharacterSyncRules.INTERP_DELAY
	for other, entry in remotes do
		local char = other.Character
		if not char or char ~= entry.char then
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos, yaw = CharacterSyncRules.sample(entry.buffer, renderTime)
		if root and pos and yaw then
			root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		end
	end
end

-- Cette méthode permet de démarrer la réception et l'affichage des autres joueurs lorsque le client démarre.
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
	Players.PlayerRemoving:Connect(function(other)
		remotes[other] = nil
	end)
	RunService:BindToRenderStep(
		BIND_NAME,
		Enum.RenderPriority.Camera.Value - 2,
		PerfMarkers.wrap("autres joueurs", placeRemoteCharacters)
	)
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

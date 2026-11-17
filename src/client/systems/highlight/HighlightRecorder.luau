-- Caméra du joueur local pour le clip de la partie (#499) : tampon circulaire de HighlightClipRules.CAMERA_SECONDS
-- (format des démos, DemoClipRules : position de la racine, hauteur des yeux, lacet et tangage de FPSCamera, touches,
-- vitesse), écrit à CAMERA_HZ pendant que le personnage local est en vie. Tableaux préalloués, index tournant, aucune
-- allocation par image ; rien n'est envoyé en continu. Le serveur ne demande la fenêtre d'un kill (remote HighlightPov)
-- que lorsque ce kill bat le record de la manche : réponse unique, encodée en série d'entiers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local HighlightClipRules = require(ReplicatedStorage.Shared.HighlightClipRules)
local KeyBindings = require(ReplicatedStorage.Shared.KeyBindings)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local DemoClipRules = require(script.Parent.Parent.Parent.ui.DemoClipRules)

-- Après la caméra FPS (Camera) et le viewmodel (Camera + 1) : la caméra de l'image est posée
local BIND_NAME = "HighlightRecorder"

type Deps = {
	player: Player,
	fpsCamera: any, -- FPSCamera (getCameraYaw, getCameraPitch)
	movement: any, -- MovementController (getVelocity)
}

local HighlightRecorder = {}

local ring = HighlightClipRules.newCameraRing()
local deps: Deps

-- Cette méthode permet de composer le masque des touches de mouvement tenues lorsque l'échantillon est pris, sans table
-- intermédiaire (bits dans l'ordre de DemoClipRules.KEY_ORDER).
local function keysMask(): number
	if UserInputService:GetFocusedTextBox() then
		return 0
	end
	local mask, bit = 0, 1
	for _, action in DemoClipRules.KEY_ORDER do
		for _, name in (KeyBindings.KEYS :: any)[action] do
			if UserInputService:IsKeyDown((Enum.KeyCode :: any)[name]) then
				mask += bit
				break
			end
		end
		bit *= 2
	end
	return mask
end

-- Cette méthode permet d'écrire un échantillon de la caméra lorsqu'il est dû et que le personnage local est en vie ;
-- aucune allocation (valeurs lues, écrites à l'index tournant).
local function step()
	local char = deps.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and camera) then
		return
	end
	local t = workspace:GetServerTimeNow()
	if not HighlightClipRules.cameraDue(ring, t) then
		return
	end
	local pos = root.Position
	local velocity: Vector3 = deps.movement.getVelocity()
	HighlightClipRules.pushCamera(
		ring,
		t,
		pos.X,
		pos.Y,
		pos.Z,
		camera.CFrame.Position.Y - pos.Y,
		deps.fpsCamera.getCameraYaw(),
		deps.fpsCamera.getCameraPitch(),
		keysMask(),
		math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
	)
end

-- Cette méthode permet de renvoyer au serveur la fenêtre [start, stop] du tampon lorsqu'il la demande (kill record) :
-- même numéro de demande, échantillons encodés en série (temps relatifs à `start`).
local function onRequest(remote: RemoteEvent, id: any, start: any, stop: any)
	if type(id) ~= "number" or type(start) ~= "number" or type(stop) ~= "number" then
		return
	end
	local rows = HighlightClipRules.cameraRows(ring, start, stop)
	local text = HighlightClipRules.encodeSeries(rows, HighlightClipRules.CAMERA_SCALES)
	if #text > HighlightClipRules.POV_MAX_BYTES then
		return -- impossible avec CAMERA_CAPACITY (testé) : le serveur reconstruira le POV
	end
	remote:FireServer(id, text)
end

-- Cette méthode permet de démarrer l'enregistrement de la caméra et la réponse aux demandes du serveur lorsque le
-- client démarre.
function HighlightRecorder.init(dependencies: Deps)
	deps = dependencies
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, PerfMarkers.wrap("clip caméra", step))
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.HIGHLIGHT_POV, 15)
		if not found or not found:IsA("RemoteEvent") then
			warn("[HighlightRecorder] remote " .. NetworkProtocol.Names.HIGHLIGHT_POV .. " introuvable")
			return
		end
		found.OnClientEvent:Connect(function(id, start, stop)
			onRequest(found, id, start, stop)
		end)
	end)
end

return HighlightRecorder

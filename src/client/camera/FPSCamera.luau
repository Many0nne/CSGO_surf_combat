local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local GamepadRules = require(ReplicatedStorage.Shared.GamepadRules)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ScopeSensitivity = require(ReplicatedStorage.Shared.ScopeSensitivity)

local cam = workspace.CurrentCamera
local FPSCamera = {}

local yaw = 0
local pitch = 0
local hrpRef: BasePart? = nil
local boundStepName = "FPSCameraUpdate"
local currentCamHeight = CameraConfig.CAM_HEIGHT_STAND
local baseSens = CameraConfig.DEFAULT_SENS
local scopeSensMult = CameraConfig.SCOPE_SENS_MULT
local scopeFov: number? = nil -- FOV du niveau de zoom, nil hors lunette
local currentSens = baseSens
local activeFovTween: Tween? = nil
local scripted = false -- angles posés par le rejeu d'un parcours (#379), souris ignorée
-- Visée à la manette (#276) : position du stick droit, multiplicateur réglable et facteur du zoom de la lunette
local lookStick = Vector2.zero
local gamepadSens = CameraConfig.GAMEPAD_SENS
local zoomFactor = 1
-- Glisser au doigt accumulé depuis la dernière image (px)
local touchDelta = Vector2.zero

UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		lookStick = Vector2.new(input.Position.X, input.Position.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		lookStick = Vector2.zero
	end
end)

local function hideCharacterPart(obj: Instance)
	if obj:IsA("BasePart") then
		(obj :: BasePart).LocalTransparencyModifier = 1
	end
end

function FPSCamera.init(hrp: BasePart, char: Model)
	hrpRef = hrp
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CameraConfig.DEFAULT_FOV
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	for _, obj in char:GetDescendants() do
		hideCharacterPart(obj)
	end
	char.DescendantAdded:Connect(hideCharacterPart)

	RunService:UnbindFromRenderStep(boundStepName)
	RunService:BindToRenderStep(
		boundStepName,
		Enum.RenderPriority.Camera.Value,
		PerfMarkers.wrap("caméra", function(dt: number)
			if not hrpRef or not hrpRef.Parent then
				return
			end

			-- Rotation : toujours a la frequence d'affichage (souris fluide), sauf pendant un parcours rejoué (#379).
			-- Souris et doigt en pixels, stick droit en vitesse (degrés/s), réduite par le zoom de la lunette.
			if not scripted then
				local delta = UserInputService:GetMouseDelta() + touchDelta * CameraConfig.TOUCH_LOOK_MULT
				local rx, ry = GamepadRules.lookRate(lookStick.X, lookStick.Y)
				local stickStep = CameraConfig.GAMEPAD_TURN_RATE * gamepadSens * zoomFactor * dt
				yaw = yaw + delta.X * currentSens + rx * stickStep
				pitch = math.clamp(
					pitch - delta.Y * currentSens + ry * stickStep,
					CameraConfig.PITCH_MIN,
					CameraConfig.PITCH_MAX
				)
			end
			touchDelta = Vector2.zero

			-- Position : celle que le MovementController vient de poser dans cette même frame (il tourne juste avant,
			-- sur le dt du rendu), donc sans interpolation ni retard.
			local headPos = hrpRef.Position + Vector3.new(0, currentCamHeight, 0)
			cam.CFrame = CFrame.new(headPos)
				* CFrame.Angles(0, math.rad(-yaw), 0)
				* CFrame.Angles(math.rad(pitch), 0, 0)
		end)
	)
end

-- Cette méthode permet de couper la caméra FPS (plus de rotation à la souris ni de suivi du personnage) lorsque le
-- joueur quitte la partie par MENU PRINCIPAL, sans attendre la destruction de son personnage (#217).
function FPSCamera.stop()
	RunService:UnbindFromRenderStep(boundStepName)
	hrpRef = nil
end

function FPSCamera.setCamHeight(h: number)
	currentCamHeight = h - 0.4
end

function FPSCamera.getCameraYaw(): number
	return yaw
end

function FPSCamera.getCameraPitch(): number
	return pitch
end

-- Cette méthode permet d'orienter la caméra (yaw/pitch en degrés) lorsqu'un script doit viser sans souris,
-- par exemple le helper de playtest Studio (#30) ; la souris reprend la main à la frame suivante.
function FPSCamera.setAngles(newYaw: number, newPitch: number)
	yaw = newYaw
	pitch = math.clamp(newPitch, CameraConfig.PITCH_MIN, CameraConfig.PITCH_MAX)
end

-- Cette méthode permet d'ignorer la souris (angles posés seulement par setAngles) ou de la rendre lorsque le rejeu d'un
-- parcours démarre ou s'arrête (#379).
function FPSCamera.setScripted(on: boolean)
	scripted = on
end

-- Cette méthode permet de recalculer la sensibilité appliquée lorsque la sensi de base, le multiplicateur lunette
-- ou le niveau de zoom change.
local function refreshSens()
	currentSens = ScopeSensitivity.effective(baseSens, scopeFov, CameraConfig.DEFAULT_FOV, scopeSensMult)
	zoomFactor = ScopeSensitivity.effective(1, scopeFov, CameraConfig.DEFAULT_FOV, scopeSensMult)
end

-- Cette méthode permet de régler la sensibilité de la visée au stick droit (#276) lorsque le réglage change.
function FPSCamera.setGamepadSensitivity(s: number)
	gamepadSens = s
end

-- Cette méthode permet d'ajouter un glisser au doigt (px) à la rotation de la prochaine image lorsque le joueur vise au
-- tactile (#276).
function FPSCamera.addTouchLook(delta: Vector2)
	touchDelta += delta
end

function FPSCamera.setSensitivity(s: number)
	baseSens = s
	refreshSens()
end

function FPSCamera.getSensitivity(): number
	return baseSens
end

function FPSCamera.setScopeMultiplier(m: number)
	scopeSensMult = m
	refreshSens()
end

function FPSCamera.getScopeMultiplier(): number
	return scopeSensMult
end

-- Cette méthode permet d'appliquer la sensibilité de la lunette lorsque le joueur zoome (`fov` = FOV du niveau de zoom)
-- ou dézoome (`scoped` faux) ; changer de niveau de zoom la met à jour.
function FPSCamera.setScoped(scoped: boolean, fov: number?)
	scopeFov = if scoped then (fov or CameraConfig.DEFAULT_FOV) else nil
	refreshSens()
end

function FPSCamera.setFOV(targetFov: number, duration: number?)
	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
	if duration and duration > 0 then
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local t = TweenService:Create(cam, info, { FieldOfView = targetFov })
		activeFovTween = t
		t.Completed:Once(function()
			activeFovTween = nil
		end)
		t:Play()
	else
		cam.FieldOfView = targetFov
	end
end

return FPSCamera

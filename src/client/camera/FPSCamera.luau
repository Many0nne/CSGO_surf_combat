local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local cam = workspace.CurrentCamera
local FPSCamera = {}

local yaw = 0
local pitch = 0
local hrpRef: BasePart? = nil
local boundStepName = "FPSCameraUpdate"
local currentCamHeight = CameraConfig.CAM_HEIGHT_STAND
local baseSens = CameraConfig.DEFAULT_SENS
local scopeSensMult = CameraConfig.SCOPE_SENS_MULT
local isScoped = false
local currentSens = baseSens
local activeFovTween: Tween? = nil

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
		PerfMarkers.wrap("caméra", function()
			if not hrpRef or not hrpRef.Parent then
				return
			end

			-- Rotation : toujours a la frequence d'affichage (souris fluide).
			local delta = UserInputService:GetMouseDelta()
			yaw = yaw + delta.X * currentSens
			pitch = math.clamp(pitch - delta.Y * currentSens, CameraConfig.PITCH_MIN, CameraConfig.PITCH_MAX)

			-- Position : celle que le MovementController vient de poser dans cette même frame (il tourne juste avant,
			-- sur le dt du rendu), donc sans interpolation ni retard.
			local headPos = hrpRef.Position + Vector3.new(0, currentCamHeight, 0)
			cam.CFrame = CFrame.new(headPos)
				* CFrame.Angles(0, math.rad(-yaw), 0)
				* CFrame.Angles(math.rad(pitch), 0, 0)
		end)
	)
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

function FPSCamera.setSensitivity(s: number)
	baseSens = s
	currentSens = isScoped and (baseSens * scopeSensMult) or baseSens
end

function FPSCamera.getSensitivity(): number
	return baseSens
end

function FPSCamera.setScopeMultiplier(m: number)
	scopeSensMult = m
	currentSens = isScoped and (baseSens * scopeSensMult) or baseSens
end

function FPSCamera.getScopeMultiplier(): number
	return scopeSensMult
end

function FPSCamera.setScoped(scoped: boolean)
	isScoped = scoped
	currentSens = isScoped and (baseSens * scopeSensMult) or baseSens
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

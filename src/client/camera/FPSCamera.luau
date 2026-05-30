local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.MovementConfig)

local cam = workspace.CurrentCamera
local FPSCamera = {}

local yaw   = 0
local pitch = 0
local hrpRef: BasePart? = nil
local boundStepName = "FPSCameraUpdate"
local currentCamHeight = Config.CAM_HEIGHT_STAND
local baseSens      = Config.DEFAULT_SENS
local scopeSensMult = Config.AWP_SCOPE_SENS_MULT
local isScoped      = false
local currentSens   = baseSens

local function hideCharacterPart(obj: Instance)
	if obj:IsA("BasePart") then
		(obj :: BasePart).LocalTransparencyModifier = 1
	end
end

function FPSCamera.init(hrp: BasePart, char: Model)
	hrpRef = hrp
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = Config.DEFAULT_FOV
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	for _, obj in char:GetDescendants() do
		hideCharacterPart(obj)
	end
	char.DescendantAdded:Connect(hideCharacterPart)

	RunService:UnbindFromRenderStep(boundStepName)
	RunService:BindToRenderStep(boundStepName, Enum.RenderPriority.Camera.Value, function()
		if not hrpRef then return end
		local delta = UserInputService:GetMouseDelta()
		yaw   = yaw + delta.X * currentSens
		pitch = math.clamp(pitch - delta.Y * currentSens, Config.PITCH_MIN, Config.PITCH_MAX)

		local headPos = hrpRef.Position + Vector3.new(0, currentCamHeight, 0)
		cam.CFrame = CFrame.new(headPos)
			* CFrame.Angles(0, math.rad(-yaw), 0)
			* CFrame.Angles(math.rad(pitch), 0, 0)
	end)
end

function FPSCamera.setCamHeight(h: number)
	currentCamHeight = h
end

function FPSCamera.getCameraYaw(): number
	return yaw
end

function FPSCamera.getCameraPitch(): number
	return pitch
end

function FPSCamera.setSensitivity(s: number)
	baseSens    = s
	currentSens = isScoped and (baseSens * scopeSensMult) or baseSens
end

function FPSCamera.getSensitivity(): number
	return baseSens
end

function FPSCamera.setScopeMultiplier(m: number)
	scopeSensMult = m
	currentSens   = isScoped and (baseSens * scopeSensMult) or baseSens
end

function FPSCamera.getScopeMultiplier(): number
	return scopeSensMult
end

function FPSCamera.setScoped(scoped: boolean)
	isScoped    = scoped
	currentSens = isScoped and (baseSens * scopeSensMult) or baseSens
end

function FPSCamera.setFOV(targetFov: number, duration: number?)
	if duration and duration > 0 then
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(cam, info, { FieldOfView = targetFov }):Play()
	else
		cam.FieldOfView = targetFov
	end
end

return FPSCamera

local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.MovementConfig)

local cam = workspace.CurrentCamera
local FPSCamera = {}

local yaw   = 0
local pitch = 0
local hrpRef: BasePart? = nil
local conn: RBXScriptConnection? = nil

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

	for _, obj in char:GetDescendants() do
		hideCharacterPart(obj)
	end
	char.DescendantAdded:Connect(hideCharacterPart)

	if conn then conn:Disconnect() end
	conn = RunService.RenderStepped:Connect(function()
		if not hrpRef then return end
		local delta = UserInputService:GetMouseDelta()
		yaw   = yaw + delta.X * Config.DEFAULT_SENS
		pitch = math.clamp(pitch - delta.Y * Config.DEFAULT_SENS, Config.PITCH_MIN, Config.PITCH_MAX)

		local headPos = hrpRef.Position + Vector3.new(0, Config.CAM_HEIGHT_STAND, 0)
		cam.CFrame = CFrame.new(headPos)
			* CFrame.Angles(0, math.rad(-yaw), 0)
			* CFrame.Angles(math.rad(pitch), 0, 0)
	end)
end

function FPSCamera.getCameraYaw(): number
	return yaw
end

function FPSCamera.getCameraPitch(): number
	return pitch
end

return FPSCamera

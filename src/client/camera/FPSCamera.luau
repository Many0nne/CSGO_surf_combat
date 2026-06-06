local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)

local cam = workspace.CurrentCamera
local FPSCamera = {}

local yaw   = 0
local pitch = 0
local hrpRef: BasePart? = nil
local boundStepName = "FPSCameraUpdate"
local currentCamHeight = CameraConfig.CAM_HEIGHT_STAND
local baseSens      = CameraConfig.DEFAULT_SENS
local scopeSensMult = CameraConfig.SCOPE_SENS_MULT
local isScoped      = false
local currentSens   = baseSens
local activeFovTween: Tween? = nil

-- Interpolation de position entre deux pas physiques (Heartbeat).
-- Le perso est deplace par CFrame sur Heartbeat (~60 Hz) ; la camera rend a la
-- frequence d'affichage (souvent > 60 Hz). Lire hrp.Position directement au rendu
-- donne une position en escalier => saccades quand on translate ET tourne. On
-- interpole donc entre les deux dernieres positions connues.
local renderPrevPos: Vector3? = nil
local renderCurPos:  Vector3? = nil
local lastStepClock = 0
local lastStepDt    = 0

local function hideCharacterPart(obj: Instance)
	if obj:IsA("BasePart") then
		(obj :: BasePart).LocalTransparencyModifier = 1
	end
end

function FPSCamera.init(hrp: BasePart, char: Model)
	hrpRef = hrp
	renderPrevPos = hrp.Position
	renderCurPos  = hrp.Position
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CameraConfig.DEFAULT_FOV
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	for _, obj in char:GetDescendants() do
		hideCharacterPart(obj)
	end
	char.DescendantAdded:Connect(hideCharacterPart)

	RunService:UnbindFromRenderStep(boundStepName)
	RunService:BindToRenderStep(boundStepName, Enum.RenderPriority.Camera.Value, function()
		if not hrpRef then return end

		-- Rotation : toujours a la frequence d'affichage (souris fluide).
		local delta = UserInputService:GetMouseDelta()
		yaw   = yaw + delta.X * currentSens
		pitch = math.clamp(pitch - delta.Y * currentSens, CameraConfig.PITCH_MIN, CameraConfig.PITCH_MAX)

		-- Position : interpolee entre les deux derniers pas physiques.
		local basePos: Vector3
		if renderPrevPos and renderCurPos and lastStepDt > 0 then
			local alpha = math.clamp((os.clock() - lastStepClock) / lastStepDt, 0, 1)
			basePos = renderPrevPos:Lerp(renderCurPos, alpha)
		else
			basePos = hrpRef.Position
		end

		local headPos = basePos + Vector3.new(0, currentCamHeight, 0)
		cam.CFrame = CFrame.new(headPos)
			* CFrame.Angles(0, math.rad(-yaw), 0)
			* CFrame.Angles(math.rad(pitch), 0, 0)
	end)
end

-- A APPELER depuis le MovementController, sur Heartbeat, JUSTE APRES avoir pose hrp.CFrame :
--   FPSCamera.updateRoot(hrp.Position, dt)
function FPSCamera.updateRoot(pos: Vector3, dt: number)
	renderPrevPos = renderCurPos or pos
	renderCurPos  = pos
	lastStepClock = os.clock()
	lastStepDt    = dt
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
	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
	if duration and duration > 0 then
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local t = TweenService:Create(cam, info, { FieldOfView = targetFov })
		activeFovTween = t
		t.Completed:Once(function() activeFovTween = nil end)
		t:Play()
	else
		cam.FieldOfView = targetFov
	end
end

return FPSCamera
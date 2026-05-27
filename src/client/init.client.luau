local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local GroundDetection    = require(script.systems.GroundDetection)
local StepupSystem       = require(script.systems.StepupSystem)
local WallSlide          = require(script.systems.WallSlide)
local InputModule        = require(script.input.InputModule)
local MovementController = require(script.systems.MovementController)
local Speedometer        = require(script.ui.Speedometer)
local FPSCamera          = require(script.camera.FPSCamera)

local player = Players.LocalPlayer

local character: Model?   = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local stateConn:    RBXScriptConnection?
local testGndConn:  RBXScriptConnection?
local testInpConn:  RBXScriptConnection?

local function setupCharacter(char: Model)
	character = char
	humanoid  = char:WaitForChild("Humanoid") :: Humanoid
	rootPart  = char:WaitForChild("HumanoidRootPart") :: BasePart
	rootPart.Anchored = true

	humanoid.WalkSpeed       = 0
	humanoid.JumpPower       = 0
	humanoid.AutoJumpEnabled = false

	humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
	if stateConn then stateConn:Disconnect() end
	stateConn = humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.PlatformStanding then
			task.defer(function()
				if humanoid then
					humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
				end
			end)
		end
	end)

	task.spawn(function()
		local animate = char:WaitForChild("Animate", 5)
		if animate and animate:IsA("LocalScript") then
			animate.Enabled = false
		end
	end)

	-- Étape 3 — ground detection
	GroundDetection.init(char)

	-- Étape 7 — stepup
	StepupSystem.init(char)

	-- Étape 8 — wallslide
	WallSlide.init(char)

	-- Étape 10 — caméra FPS
	FPSCamera.init(rootPart, char)

	-- Test étape 3 : log changements onGround
	if testGndConn then testGndConn:Disconnect() end
	local lastOnGround = nil
	testGndConn = RunService.Heartbeat:Connect(function()
		if not rootPart then return end
		local info = GroundDetection.getGroundInfo(rootPart)
		if info.onGround ~= lastOnGround then
			lastOnGround = info.onGround
			print(string.format("[Ground] onGround=%s  slope=%.1f°  mat=%s",
				tostring(info.onGround), info.slopeAngle, tostring(info.material)))
		end
	end)

	-- Test étape 4 : log changements wishdir (yaw=0, caméra pas encore implémentée)
	if testInpConn then testInpConn:Disconnect() end
	local lastWish = Vector3.zero
	testInpConn = RunService.Heartbeat:Connect(function()
		local wish = InputModule.getWishDir(FPSCamera.getCameraYaw())
		if (wish - lastWish).Magnitude > 0.001 then
			lastWish = wish
			print(string.format("[Input] wishDir=(%.3f, %.3f, %.3f)  walk=%s  crouch=%s",
				wish.X, wish.Y, wish.Z,
				tostring(InputModule.isWalking()),
				tostring(InputModule.isCrouching())))
		end
	end)

	-- Étapes 5 & 18 : physique + speedometer
	Speedometer.init()
	MovementController.init(char, rootPart, humanoid, Speedometer, FPSCamera)
end

if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

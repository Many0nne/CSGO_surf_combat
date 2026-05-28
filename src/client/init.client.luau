local Players    = game:GetService("Players")

local GroundDetection    = require(script.systems.GroundDetection)
local StepupSystem       = require(script.systems.StepupSystem)
local WallSlide          = require(script.systems.WallSlide)
local CharacterDimensions = require(script.systems.CharacterDimensions)
local MovementController = require(script.systems.MovementController)
local Speedometer        = require(script.ui.Speedometer)
local FPSCamera          = require(script.camera.FPSCamera)

local player = Players.LocalPlayer

local character: Model?   = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local stateConn:    RBXScriptConnection?

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
	CharacterDimensions.init(char, rootPart)
	GroundDetection.init(char)

	-- Étape 7 — stepup
	StepupSystem.init(char)

	-- Étape 8 — wallslide
	WallSlide.init(char)

	-- Étape 10 — caméra FPS
	FPSCamera.init(rootPart, char)

	-- Étapes 5 & 18 : physique + speedometer
	Speedometer.init()
	MovementController.init(char, rootPart, humanoid, Speedometer, FPSCamera)
end

if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

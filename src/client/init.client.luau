local Players    = game:GetService("Players")

local GroundDetection    = require(script.systems.movement.GroundDetection)
local StepupSystem       = require(script.systems.movement.StepupSystem)
local WallSlide          = require(script.systems.movement.WallSlide)
local CharacterDimensions = require(script.systems.movement.CharacterDimensions)
local MovementController = require(script.systems.movement.MovementController)
local ViewmodelSystem    = require(script.systems.weapon.ViewmodelSystem)
local WeaponSystem       = require(script.systems.weapon.WeaponSystem)
local Speedometer        = require(script.ui.Speedometer)
local SettingsMenu       = require(script.ui.SettingsMenu)
local FPSCamera          = require(script.camera.FPSCamera)

local player = Players.LocalPlayer

ViewmodelSystem.init(player)
WeaponSystem.init(player)

local stateConn: RBXScriptConnection?

local function teardownCharacter(_char: Model)
	-- TODO: déconnecter les bindings par-personnage (FPSCamera, MovementController, etc.)
end

local function setupCharacter(char: Model)
	teardownCharacter(char)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	rootPart.Anchored = true

	humanoid.WalkSpeed       = 0
	humanoid.JumpPower       = 0
	humanoid.AutoJumpEnabled = false

	humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
	if stateConn then stateConn:Disconnect() end
	stateConn = humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.PlatformStanding then
			task.defer(function()
				humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
			end)
		end
	end)

	task.spawn(function()
		local animate = char:WaitForChild("Animate", 5)
		if animate and animate:IsA("LocalScript") then
			animate.Enabled = false
		end
	end)

	-- CharacterDimensions doit précéder GroundDetection (lit les dimensions de la capsule)
	CharacterDimensions.init(char, rootPart)
	GroundDetection.init(char)
	StepupSystem.init(char)
	WallSlide.init(char)
	-- FPSCamera doit précéder MovementController et SettingsMenu
	FPSCamera.init(rootPart, char)
	SettingsMenu.init(FPSCamera)
	Speedometer.init()
	MovementController.init(char, rootPart, humanoid, Speedometer, FPSCamera)
end

if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

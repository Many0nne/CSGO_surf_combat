local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local MovementController = require(script.systems.movement.MovementController)
local CharacterSync = require(script.systems.network.CharacterSync)
local ViewmodelSystem = require(script.systems.weapon.ViewmodelSystem)
local WeaponSystem = require(script.systems.weapon.WeaponSystem)
local WeaponThirdPersonView = require(script.systems.weapon.WeaponThirdPersonView)
local FPSCamera = require(script.camera.FPSCamera)
local SettingsMenu = require(script.ui.SettingsMenu)
local LocalSettings = require(script.systems.settings.LocalSettings)
local Speedometer = require(script.ui.Speedometer)
local WeaponBar = require(script.ui.WeaponBar)
local AmmoCounter = require(script.ui.AmmoCounter)
local Crosshair = require(script.ui.Crosshair)
local KeyDisplay = require(script.ui.KeyDisplay)
local Hitmarker = require(script.ui.Hitmarker)
local GameStateController = require(script.systems.game.GameStateController)
local DebugPlaytest = require(script.debug.DebugPlaytest)
local FrameProbe = require(script.debug.FrameProbe)
local PerfOverlay = require(script.debug.PerfOverlay)
local PerfBench = require(script.debug.PerfBench)

local player = Players.LocalPlayer

ViewmodelSystem.init(player)
WeaponSystem.init(player)
WeaponThirdPersonView.init()
-- Autres joueurs affichés à la position relayée par le serveur (#75) ; notre position part de MovementController
CharacterSync.init()

local stateConn: RBXScriptConnection?

local function setupCharacter(char: Model)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart

	rootPart.Anchored = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoJumpEnabled = false
	humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)

	if stateConn then
		stateConn:Disconnect()
	end
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
			-- Ses pistes déjà lancées sont coupées par CharacterAnimator (MovementController).
		end
	end)

	FPSCamera.init(rootPart, char)
	Speedometer.init()
	MovementController.init(char, rootPart, humanoid, Speedometer, FPSCamera)
end

-- Liste des joueurs native désactivée : le classement du jeu (Tab) la remplace et elle masquait le bouton PLAY
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
-- Barre d'outils native désactivée : la barre d'armes du jeu (WeaponBar) la remplace, équipement compris
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
-- Réglages sauvegardés (#100) : demandés au serveur dès le démarrage, appliqués à leur arrivée
LocalSettings.init()
WeaponBar.init()
AmmoCounter.init()
Crosshair.init()
KeyDisplay.init()

-- Réglages créés dès le démarrage : accessibles depuis le menu, avant tout spawn
SettingsMenu.init(FPSCamera)
Hitmarker.init()

-- GameStateController orchestre les transitions d'état, le spawn et tous les UIs.
-- Il appelle setupCharacter au bon moment (après LoadCharacter côté serveur).
GameStateController.init(player, setupCharacter)

-- Helper de playtest debug (#30) : ne fait rien hors Studio (garde RunService:IsStudio() dans init).
DebugPlaytest.init({
	player = player,
	gameState = GameStateController,
	weaponSystem = WeaponSystem,
	viewmodelSystem = ViewmodelSystem,
	fpsCamera = FPSCamera,
})

-- Sonde de saccades : attribut joueur `FrameProbe` = true dans Studio (cf. docs/performance.md).
FrameProbe.init({ player = player, fpsCamera = FPSCamera, movement = MovementController })

-- Overlay de performance (F3), relevés mémoire et banc de rendu (F4) : Studio, ou créateur du jeu publié
-- (cf. docs/performance.md).
PerfOverlay.init(player)
PerfBench.init(player)

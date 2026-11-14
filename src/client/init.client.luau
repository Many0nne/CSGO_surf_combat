local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)

local MovementController = require(script.systems.movement.MovementController)
local CharacterSync = require(script.systems.network.CharacterSync)
local ViewmodelSystem = require(script.systems.weapon.ViewmodelSystem)
local WeaponSystem = require(script.systems.weapon.WeaponSystem)
local WeaponThirdPersonView = require(script.systems.weapon.WeaponThirdPersonView)
local RemoteShotSounds = require(script.systems.weapon.RemoteShotSounds)
local ShotEffects = require(script.systems.weapon.ShotEffects)
local CasingEjection = require(script.systems.weapon.CasingEjection)
local FPSCamera = require(script.camera.FPSCamera)
local SettingsMenu = require(script.ui.SettingsMenu)
local LocalSettings = require(script.systems.settings.LocalSettings)
local SkinPreloader = require(script.systems.inventory.SkinPreloader)
local SoundChannels = require(script.systems.settings.SoundChannels)
local UIKit = require(script.ui.UIKit)
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
-- Secondes d'attente au plus du corps entier d'un personnage avant de le prendre en main (#328)
local RIG_WAIT = 5

ViewmodelSystem.init(player)
WeaponSystem.init(player)
WeaponThirdPersonView.init()
-- Autres joueurs affichés à la position relayée par le serveur (#75) ; notre position part de MovementController
CharacterSync.init()

local stateConn: RBXScriptConnection?

local function setupCharacter(char: Model)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	local rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	-- Corps entier avant MovementController (#328) : CharacterMotor mesure la hauteur racine→pieds sur le rig, et le
	-- personnage arrive souvent sans ses jambes (1,59 stud mesuré au lieu de 4,77 : pieds 3,3 studs sous le sol)
	local missing = CharacterAppearance.waitForParts(char, RIG_WAIT)
	if #missing > 0 then
		warn("[Client] personnage incomplet après " .. RIG_WAIT .. " s, manque : " .. table.concat(missing, ", "))
	end
	-- Parti au menu pendant ces attentes (#217), fin de manche (bannière), mort pendant l'attente du corps (#328), ou
	-- personnage déjà remplacé : ne rien rebrancher (caméra FPS, mouvement). Pas de test de l'état DEAD : sans attente,
	-- setupCharacter tourne avant que GameStateController passe de DEAD (réapparition) à IN_ROUND.
	local state = GameStateController.getState()
	if state == "MENU" or state == "INFOS" or state == "RESULT" or humanoid.Health <= 0 or player.Character ~= char then
		return
	end

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

-- Cette méthode permet de couper tout de suite le pilotage du personnage local (mouvement, caméra FPS) lorsque le
-- joueur quitte la partie par MENU PRINCIPAL (#217) : le serveur ne le détruit qu'un aller-retour plus tard.
local function stopCharacter()
	MovementController.stop()
	FPSCamera.stop()
end

-- Liste des joueurs native désactivée : le classement du jeu (Tab) la remplace et elle masquait le bouton PLAY
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
-- Barre d'outils native désactivée : la barre d'armes du jeu (WeaponBar) la remplace, équipement compris
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
-- Barre de vie native désactivée (#307) : hors DA, elle restait affichée jusqu'au menu ; pas de vie au HUD pour l'instant
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
-- Réglages sauvegardés (#100) : demandés au serveur dès le démarrage, appliqués à leur arrivée
LocalSettings.init()
-- Échelle du HUD (#250) : suit le réglage en direct (changement du joueur, puis réglages sauvegardés à leur arrivée)
LocalSettings.onChanged(function(settings)
	UIKit.setHudScale(PlayerSettings.hudScaleFactor(settings.hudScale))
end)
-- Textures des skins équipés (#333) : chargées dès l'accueil, pas au premier équipement en partie
SkinPreloader.init()
-- Canaux de volume (#249) : groupes général et armes, créés avant le premier son
SoundChannels.init()
WeaponBar.init()
AmmoCounter.init()
Crosshair.init()
KeyDisplay.init()

-- Réglages créés dès le démarrage : accessibles depuis le menu, avant tout spawn
SettingsMenu.init(FPSCamera)
Hitmarker.init()

-- GameStateController orchestre les transitions d'état, le spawn et tous les UIs.
-- Il appelle setupCharacter au bon moment (après LoadCharacter côté serveur).
GameStateController.init(player, setupCharacter, stopCharacter)
-- Tirs des autres joueurs et des bots entendus en 3D (#156), hors écrans du menu
RemoteShotSounds.init(GameStateController.getState)
-- Flamme de bouche et rayon de leurs tirs, sur leur arme 3P (#54), hors écrans du menu
ShotEffects.init(GameStateController.getState)
-- Douilles éjectées à l'ouverture de culasse (#237) : les nôtres héritent de notre vitesse, celles des autres partent
-- de leur arme 3P après le délai d'ouverture
CasingEjection.init(GameStateController.getState, MovementController.getVelocity)

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

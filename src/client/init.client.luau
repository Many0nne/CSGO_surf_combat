local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
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
local FootstepSounds = require(script.systems.audio.FootstepSounds)
local ShotEffects = require(script.systems.weapon.ShotEffects)
local CasingEjection = require(script.systems.weapon.CasingEjection)
local FPSCamera = require(script.camera.FPSCamera)
local SettingsMenu = require(script.ui.SettingsMenu)
local LocalSettings = require(script.systems.settings.LocalSettings)
local SkinPreloader = require(script.systems.inventory.SkinPreloader)
local SoundChannels = require(script.systems.settings.SoundChannels)
local MusicPlayer = require(script.systems.audio.MusicPlayer)
local UIKit = require(script.ui.UIKit)
local HUDRules = require(script.ui.HUDRules)
local Speedometer = require(script.ui.Speedometer)
local WeaponBar = require(script.ui.WeaponBar)
local AmmoCounter = require(script.ui.AmmoCounter)
local Crosshair = require(script.ui.Crosshair)
local KeyDisplay = require(script.ui.KeyDisplay)
local TouchControls = require(script.ui.TouchControls)
local Hitmarker = require(script.ui.Hitmarker)
local GameStateController = require(script.systems.game.GameStateController)
local MenuScene = require(script.systems.game.MenuScene)
local Transition = require(script.ui.Transition)
local LoadingScreen = require(ReplicatedFirst:WaitForChild("LoadingScreen"))
local KillAnnouncer = require(script.systems.game.KillAnnouncer)
local DebugPlaytest = require(script.debug.DebugPlaytest)
local FrameProbe = require(script.debug.FrameProbe)
local ClipRecorder = require(script.debug.ClipRecorder)
local PerfOverlay = require(script.debug.PerfOverlay)
local PerfBench = require(script.debug.PerfBench)
local PerfRecorder = require(script.debug.PerfRecorder)
local PerfReplay = require(script.debug.PerfReplay)
local InputModule = require(script.input.InputModule)
local HighlightRecorder = require(script.systems.highlight.HighlightRecorder)

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
-- HUD masqué jusqu'à son échelle sauvegardée (#282), sans retenir le reste du client : affiché à l'arrivée des réglages
-- (échelle posée d'abord, sans attendre l'abonné ci-dessus), ou passé HUD_SETTINGS_TIMEOUT à l'échelle courante
LocalSettings.onLoaded(function(settings)
	UIKit.setHudScale(PlayerSettings.hudScaleFactor(settings.hudScale))
	UIKit.showHud()
end)
task.delay(HUDRules.HUD_SETTINGS_TIMEOUT, UIKit.showHud)
-- Textures des skins équipés (#333) : chargées dès l'accueil, pas au premier équipement en partie
SkinPreloader.init()
-- Canaux de volume (#249) : groupes général, armes, musique et annonces, créés avant le premier son
SoundChannels.init()
WeaponBar.init()
AmmoCounter.init()
Crosshair.init()
KeyDisplay.init()
-- Commandes tactiles (#276) : seulement sur un appareil tactile
TouchControls.init()

-- Réglages créés dès le démarrage : accessibles depuis le menu, avant tout spawn
SettingsMenu.init(FPSCamera)
Hitmarker.init()

-- GameStateController orchestre les transitions d'état, le spawn et tous les UIs.
-- Il appelle setupCharacter au bon moment (après LoadCharacter côté serveur).
GameStateController.init(player, setupCharacter, stopCharacter)
-- Écran de chargement du lancement (#480, ReplicatedFirst) : levé quand la scène du menu est construite et chargée, ou
-- dès que le joueur a quitté le menu (arrivée sur l'entraînement : la scène du menu n'est jamais finie). Volets de
-- Transition encore fermés (apparition en cours) : ils prennent le relais d'un coup ; sinon l'écran s'ouvre sur le jeu
LoadingScreen.setReadiness(function()
	local state = GameStateController.getState()
	return MenuScene.isReady() or (state ~= "MENU" and state ~= "INFOS")
end, Transition.isClosed)
-- Tirs des autres joueurs et des bots entendus en 3D (#156), hors écrans du menu
RemoteShotSounds.init(GameStateController.getState)
-- Pas des autres joueurs et des bots entendus en 3D (#146), hors écrans du menu
FootstepSounds.init(GameStateController.getState)
-- Flamme de bouche et rayon de leurs tirs, sur leur arme 3P (#54), hors écrans du menu
ShotEffects.init(GameStateController.getState)
-- Musique de fond (#286) : coupée par défaut ; un volume au menu, un en partie, baissée pendant les annonces vocales
MusicPlayer.init(GameStateController.getState, KillAnnouncer.isSpeaking)
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

-- Clip de la partie (#499) : dernières secondes de la caméra gardées en continu (tampon fixe), envoyées seulement à la
-- demande du serveur pour un kill record.
HighlightRecorder.init({ player = player, fpsCamera = FPSCamera, movement = MovementController })

-- Enregistreur des démos de l'écran Apprendre (#285) : attribut joueur `DebugClipRecorder` dans Studio, puis F7 (docs/ui.md).
ClipRecorder.init({ player = player, fpsCamera = FPSCamera, movement = MovementController })

-- Sonde de saccades : attribut joueur `FrameProbe` = true dans Studio (cf. docs/performance.md).
FrameProbe.init({ player = player, fpsCamera = FPSCamera, movement = MovementController })

-- Overlay de performance (F3), relevés mémoire et banc de rendu (F4) : Studio, ou créateur du jeu publié
-- (cf. docs/performance.md).
PerfOverlay.init(player)
PerfBench.init(player)
-- Parcours enregistré puis rejoué pour mesurer en mouvement (#379) : attributs joueur `PerfRecord` (puis F7) et
-- `PerfRun`, mêmes droits que l'overlay (cf. docs/performance.md, « Parcours rejoué »).
PerfRecorder.init({ player = player, fpsCamera = FPSCamera, movement = MovementController, input = InputModule })
PerfReplay.init({
	player = player,
	fpsCamera = FPSCamera,
	movement = MovementController,
	input = InputModule,
	gameState = GameStateController,
})

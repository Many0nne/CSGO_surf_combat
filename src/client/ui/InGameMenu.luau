-- Menu en partie (#157, touche PlayerSettings.MENU_KEY) : REPRENDRE, RÉGLAGES (l'écran SettingsMenu, ouvert par-dessus en
-- présentation « modal ») et MENU PRINCIPAL. La partie ne se met pas en pause (FFA multijoueur) : le menu est une
-- surcouche sur un voile sombre qui retient les clics ; tant qu'il est ouvert, la souris est libre, les touches de jeu
-- sont coupées (InputModule), le crosshair et l'affichage des touches sont masqués. Il route aussi la touche du menu et
-- Échap pour tout le client : saisie de touche des Réglages d'abord, menu en partie, puis Réglages du menu principal.
-- Vues et règles : InGameMenuRules (testées).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local InputModule = require(script.Parent.Parent.input.InputModule)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDState = require(script.Parent.HUDState)
local InGameMenuRules = require(script.Parent.InGameMenuRules)
local MenuPage = require(script.Parent.MenuPage)
local SettingsMenu = require(script.Parent.SettingsMenu)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local Motion = UITheme.Motion

type View = InGameMenuRules.View

local InGameMenu = {}

local MENU_KEY = Enum.KeyCode[PlayerSettings.MENU_KEY]
local TITLE = "MENU"
-- Colonne de choix centrée sous le titre (px à 720 de haut), MENU PRINCIPAL écarté des deux autres
local COLUMN_TOP = MenuPage.ContentTop
local CHOICE_SIZE = 40
local CHOICE_GAP = 18
local LEAVE_GAP = 40
local BACKDROP_TRANSPARENCY = 0.45
local BACKDROP_ORDER = 2 -- sous la page (3, comme SettingsMenu), au-dessus du HUD (0)
-- Studio seulement : la touche P ne passe pas par l'input simulé du MCP en partie, cet attribut joueur ouvre (true) ou
-- ferme (false) le menu à sa place (cf. docs/ui.md « Touche P au MCP »)
local DEBUG_ATTRIBUTE = "DebugInGameMenu"

export type Deps = {
	getState: () -> string, -- état client (GameStateController)
	onLeave: () -> (), -- MENU PRINCIPAL : retrait du round et retour au menu
	onMainMenuKey: () -> (), -- touche du menu au menu principal (Réglages de l'accueil)
}

local deps: Deps?
local page: MenuPage.Page?
local backdropGui: ScreenGui
local backdrop: Frame
local resumeChoice
local view: View = "closed"
-- Souris voulue par le jeu (FPSCamera, mort, réapparition) pendant que le menu la tient libre, rendue à la fermeture
local wantedBehavior = Enum.MouseBehavior.LockCenter
local wantedIcon = false
local mouseConns: { RBXScriptConnection } = {}

-- Cette méthode permet de garder la souris libre tant que le menu est ouvert, même si le jeu la reprend (réapparition :
-- FPSCamera la verrouille) ; la valeur demandée par le jeu est retenue pour la fermeture.
local function holdMouse()
	wantedBehavior = UserInputService.MouseBehavior
	wantedIcon = UserInputService.MouseIconEnabled
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	-- Cette méthode permet de retenir puis annuler un changement de souris lorsque le jeu la reprend menu ouvert.
	local function enforce()
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			wantedBehavior = UserInputService.MouseBehavior
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			wantedIcon = false
			UserInputService.MouseIconEnabled = true
		end
	end
	mouseConns = {
		UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(enforce),
		UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(enforce),
	}
end

-- Cette méthode permet de rendre au jeu la souris qu'il a demandée lorsque le menu se ferme.
local function releaseMouse()
	for _, conn in mouseConns do
		conn:Disconnect()
	end
	mouseConns = {}
	UserInputService.MouseBehavior = wantedBehavior
	UserInputService.MouseIconEnabled = wantedIcon
end

-- Cette méthode permet de poser ou retirer tout ce qui couvre la partie (voile, souris, touches de jeu ; via HUDState,
-- crosshair et affichage des touches masqués) lorsque le menu s'ouvre ou se ferme.
local function applyOverlay(isOpen: boolean)
	InputModule.setSuspended(isOpen)
	HUDState.setMenuOpen(isOpen)
	backdropGui.Enabled = isOpen
	if isOpen then
		holdMouse()
		backdrop.BackgroundTransparency = 1
		UIKit.tween(backdrop, Motion.Enter, { BackgroundTransparency = BACKDROP_TRANSPARENCY })
	else
		releaseMouse()
	end
end

-- Cette méthode permet de passer à une vue (fermé, accueil du menu, Réglages) lorsque le joueur agit ou que l'état du
-- jeu change ; la vue est posée avant de fermer les Réglages, dont le rappel de fermeture la relit.
local function setView(newView: View)
	local built = page
	if not built or newView == view then
		return
	end
	local previous = view
	view = newView
	local isOpen = InGameMenuRules.isOpen(newView)
	if isOpen ~= InGameMenuRules.isOpen(previous) then
		applyOverlay(isOpen)
	end
	if newView == "main" then
		built.show()
		resumeChoice.setSelected(true)
	else
		built.hide()
	end
	if newView == "settings" then
		-- Une ouverture restée en cours (présentation « page ») ignorerait la nouvelle
		SettingsMenu.close()
		SettingsMenu.open("modal", function()
			-- RETOUR des Réglages : retour à l'accueil du menu (rien si le menu s'est fermé entre-temps)
			if view == "settings" then
				setView(InGameMenuRules.onChoice(view, "back"))
			end
		end)
	elseif previous == "settings" then
		SettingsMenu.close()
	end
end

-- Cette méthode permet d'appliquer un choix du menu (REPRENDRE, RÉGLAGES, MENU PRINCIPAL) lorsque le joueur clique.
local function choose(choice: InGameMenuRules.Choice)
	setView(InGameMenuRules.onChoice(view, choice))
	if choice == "leave" and deps then
		deps.onLeave()
	end
end

-- Cette méthode permet de router une entrée lorsque le joueur appuie : saisie de touche des Réglages d'abord, puis Échap
-- (ferme le menu en partie, ou les Réglages du menu principal), puis la touche du menu selon l'état du jeu.
local function onInputBegan(inp: InputObject, gameProcessed: boolean)
	if SettingsMenu.handleCaptureInput(inp) then
		return
	end
	-- Échap ferme, même si Roblox traite aussi la touche (son menu s'ouvre par-dessus)
	if inp.KeyCode == Enum.KeyCode.Escape then
		if InGameMenuRules.isOpen(view) then
			setView("closed")
		else
			SettingsMenu.close()
		end
		return
	end
	if gameProcessed or inp.KeyCode ~= MENU_KEY or not deps then
		return
	end
	local gameState = deps.getState()
	local target = InGameMenuRules.keyTarget(gameState, view)
	if target == "inGame" then
		setView(InGameMenuRules.onMenuKey(view, gameState))
	elseif target == "mainMenu" then
		deps.onMainMenuKey()
	end
end

-- Cette méthode permet de construire la colonne de choix (et le rappel de la touche) lorsque l'écran est construit.
local function buildChoices(built: MenuPage.Page)
	local column = UIKit.frame({
		Name = "Choices",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, COLUMN_TOP),
		Size = UDim2.fromOffset(500, 300),
		Parent = built.block,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CHOICE_GAP),
		Parent = column,
	})
	resumeChoice = built.choice({
		text = "REPRENDRE",
		size = CHOICE_SIZE,
		layoutOrder = 1,
		parent = column,
		action = function()
			choose("resume")
		end,
	})
	built.choice({
		text = "RÉGLAGES",
		size = CHOICE_SIZE,
		layoutOrder = 2,
		parent = column,
		action = function()
			choose("settings")
		end,
	})
	-- Écart avant l'action qui quitte la partie
	UIKit.frame({
		Name = "Gap",
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Size = UDim2.fromOffset(1, LEAVE_GAP - CHOICE_GAP * 2),
		Parent = column,
	})
	built.choice({
		text = "MENU PRINCIPAL",
		size = CHOICE_SIZE,
		layoutOrder = 4,
		parent = column,
		action = function()
			choose("leave")
		end,
	})
	-- Aide en bas au centre, touche en boîte comme sur l'écran d'équipement ; la partie n'est pas en pause : le joueur
	-- reste exposé tant que le menu est ouvert
	local hints = UIKit.hintRow(built.group, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -MenuPage.HintBottom),
	})
	UIKit.keyHint(hints, 1, LocalSettings.keyText(PlayerSettings.MENU_KEY), "REPRENDRE")
	UIKit.keyHint(hints, 2, nil, "LA PARTIE CONTINUE")
end

-- Cette méthode permet de construire le menu et de brancher la touche du menu et Échap lorsque le client démarre.
function InGameMenu.init(newDeps: Deps)
	if page then
		return
	end
	deps = newDeps
	-- Voile à part, sous la page : il reste posé quand les Réglages remplacent l'accueil du menu, sans clignoter
	backdropGui = UIKit.create("ScreenGui", {
		Name = "InGameMenuBackdrop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = BACKDROP_ORDER,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	-- Actif : les clics ne partent pas en tirs dans la partie
	backdrop = UIKit.frame({
		Name = "Backdrop",
		Active = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = BACKDROP_TRANSPARENCY,
		Parent = backdropGui,
	})
	local built = MenuPage.new("InGameMenu", 3, TITLE)
	page = built
	buildChoices(built)

	UserInputService.InputBegan:Connect(onInputBegan)
	if RunService:IsStudio() then
		local player = Players.LocalPlayer
		player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
			local wanted = player:GetAttribute(DEBUG_ATTRIBUTE)
			if wanted == true and view == "closed" then
				setView(InGameMenuRules.onMenuKey(view, newDeps.getState()))
			elseif wanted == false then
				setView("closed")
			end
		end)
	end
	-- Échap ouvre le menu Roblox, qui peut capturer la touche avant nous : tout se ferme aussi à son ouverture
	GuiService.MenuOpened:Connect(function()
		setView("closed")
		SettingsMenu.close()
	end)
end

-- Cette méthode permet d'adapter le menu à l'état du jeu lorsqu'il change (GameStateController) : fermé hors partie,
-- gardé entre la mort et la réapparition.
function InGameMenu.onGameState(gameState: string)
	setView(InGameMenuRules.onGameState(view, gameState))
end

-- Cette méthode permet de savoir si le menu en partie couvre le jeu lorsqu'un module doit ignorer ses entrées (barre
-- d'armes).
function InGameMenu.isOpen(): boolean
	return InGameMenuRules.isOpen(view)
end

return InGameMenu

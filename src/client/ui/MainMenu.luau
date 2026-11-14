-- Menu principal (docs/ui.md) : derrière, le personnage du jeu en pose sur une copie de la map (#253, MenuScene) ; on
-- choisit à la souris système, rien ne se tire. Titre en haut à gauche, onglets ARMES · INFOS · APPRENDRE · JOUER ·
-- RÉGLAGES · FEEDBACK en haut au centre (au-dessus des écrans secondaires, qui s'ouvrent dessous ; l'onglet ouvert est
-- souligné d'ambre, #308), statistiques du joueur en bas à droite (#301, StatsCard). L'onglet ARMES est l'écran
-- d'équipement (#280, disposition de #308, EquipmentScreen) : tout
-- à gauche (titre, arme montrée, onglets des emplacements, grille de cartes), le personnage à droite tient l'arme
-- survolée ou celle de l'emplacement actif.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local EquipmentScreen = require(script.Parent.EquipmentScreen)
local MenuCursor = require(script.Parent.MenuCursor)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local StatsCard = require(script.Parent.StatsCard)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

export type Page = "home" | "infos" | "learn" | "settings" | "feedback"

local MainMenu = {}

local EDGE = MenuPage.Edge -- marge de la maquette (px à 720 de haut)
-- Sous les boutons Roblox du coin haut gauche (plus bas si la fenêtre est petite, MenuPage.followTopbar)
local TITLE_Y = MenuPage.GameTitleY
local TABS_Y = 18
local NOTICE_Y = 72 -- message sous les onglets (apparition impossible, #219)
local NOTICE_TIME = 5 -- s d'affichage de ce message
-- Onglets, de gauche à droite ; ARMES est l'accueil (le personnage et son arme), JOUER l'appel à l'action, APPRENDRE
-- juste avant (#285 : on apprend le geste, puis on joue)
local TABS = {
	{ key = "home", text = "ARMES" },
	{ key = "infos", text = "INFOS" },
	{ key = "learn", text = "APPRENDRE" },
	{ key = "play", text = "JOUER" },
	{ key = "settings", text = "RÉGLAGES" },
	{ key = "feedback", text = "FEEDBACK" },
}
local gui: ScreenGui
local tabsGui: ScreenGui
local content: Frame
local tabs: { [string]: MenuShot.Choice } = {}
local underlines: { [string]: Frame } = {}
local choices: { MenuShot.Choice } = {}
local callbacks: { [string]: (() -> ())? } = {}
local currentPage: Page = "home"
local notice: TextLabel
local noticeShadow: TextLabel
local noticeGeneration = 0

-- Cette méthode permet d'appeler un rappel enregistré lorsqu'un choix du menu est confirmé.
local function fire(name: string)
	local fn = callbacks[name]
	if fn then
		fn()
	end
end

-- Cette méthode permet d'aller sur un onglet lorsque le joueur le touche : l'écran ouvert se ferme d'abord.
local function goTo(page: string)
	if page == currentPage then
		return
	end
	if currentPage ~= "home" then
		fire("home")
	end
	if page ~= "home" then
		fire(page)
	end
end

-- Cette méthode permet de construire le titre du jeu en haut à gauche, visible sur toutes les pages du menu, lorsque
-- celui-ci est initialisé.
local function buildTitle(root: Frame)
	UIKit.shadowedText(root, {
		Name = "Title",
		Text = "SURF FFA",
		FontFace = F.Display,
		TextSize = 34,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE, TITLE_Y),
		Size = UDim2.fromOffset(240, 38),
		ZIndex = 2,
	}, 3)
	UIKit.accentLabel(root, {
		Name = "Subtitle",
		Text = "COMBAT DE SURF",
		Position = UDim2.fromOffset(EDGE + 1, TITLE_Y + 38),
		Size = UDim2.fromOffset(240, 18),
	})
end

-- Cette méthode permet de construire la barre d'onglets lorsque le menu est initialisé : onglets en texte séparés par
-- des filets, l'onglet ouvert en os vif souligné d'ambre (#308), JOUER plus grand, sans soulignement, lance la partie
-- (les volets se ferment aussitôt).
local function buildTabs(root: Frame)
	local bar = UIKit.frame({
		Name = "Tabs",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TABS_Y),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 48),
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 22),
		Parent = bar,
	})
	for i, tab in TABS do
		if i > 1 then
			UIKit.frame({
				Name = "Separator",
				LayoutOrder = 2 * i - 1,
				Size = UDim2.fromOffset(1, 16),
				BackgroundColor3 = C.TextSoft,
				BackgroundTransparency = 0.7,
				Parent = bar,
			})
		end
		local isPlay = tab.key == "play"
		local choice = MenuShot.textChoice({
			text = tab.text,
			font = if isPlay then F.Display else F.DisplayMedium,
			size = if isPlay then 28 else 18,
			color = if isPlay then C.Bone else C.TextSoft,
			selectedColor = C.Bone,
			layoutOrder = 2 * i,
			parent = bar,
			action = function()
				if isPlay then
					fire("play")
				else
					goTo(tab.key)
				end
			end,
			locks = isPlay,
		})
		if not isPlay then
			-- Soulignement ambré de l'onglet ouvert (« là où je suis »), montré par MainMenu.setPage
			underlines[tab.key] = UIKit.frame({
				Name = "Underline",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 6),
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = C.Accent,
				Visible = false,
				ZIndex = 3,
				Parent = choice.button,
			})
		end
		tabs[tab.key] = choice
		table.insert(choices, choice)
	end
	-- Message ponctuel sous les onglets (MainMenu.showNotice), visible sur toutes les pages du menu
	notice, noticeShadow = UIKit.shadowedText(root, {
		Name = "Notice",
		FontFace = F.DisplayMedium,
		TextSize = 16,
		TextColor3 = C.HitRed,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, NOTICE_Y),
		Size = UDim2.fromOffset(640, 20),
		Visible = false,
	}, 2)
end

-- Cette méthode permet de poser le titre du jeu avec les onglets, au-dessus des écrans secondaires (#308 : il reste
-- affiché sur toutes les pages, hors du fond de coin de ces écrans), lorsque le menu est initialisé.
local function buildTitleColumn(root: Frame)
	local titleColumn =
		UIKit.frame({ Name = "TitleColumn", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	buildTitle(titleColumn)
	MenuPage.followTopbar(root, titleColumn)
end

-- Cette méthode permet de construire l'accueil (statistiques, écran d'équipement) lorsque le menu est initialisé.
local function buildContent(root: Frame)
	content = UIKit.frame({ Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	-- Colonne de gauche, décalée d'un bloc sous la barre de Roblox dans les petites fenêtres (#306)
	local column =
		UIKit.frame({ Name = "LeftColumn", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content })
	StatsCard.build(content)
	EquipmentScreen.build(content, column)
	MenuPage.followTopbar(root, column)
end

-- Cette méthode permet de passer les touches et la molette à l'écran d'équipement lorsque le joueur est sur l'accueil.
local function onWeaponInput(input: InputObject, processed: boolean)
	if processed or currentPage ~= "home" then
		return
	end
	EquipmentScreen.onInput(input)
end

-- Cette méthode permet de créer un ScreenGui du menu lorsque celui-ci est initialisé.
local function makeGui(name: string, displayOrder: number): ScreenGui
	return UIKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

-- Cette méthode permet d'initialiser le menu et d'enregistrer les rappels lorsque le client démarre ;
-- onSettings, onHome et onLearn sont optionnels (navigation vers Settings, retour à l'accueil, écran Apprendre).
function MainMenu.init(
	onPlay: () -> (),
	onInfos: () -> (),
	onFeedback: () -> (),
	onSettings: (() -> ())?,
	onHome: (() -> ())?,
	onLearn: (() -> ())?
)
	callbacks = {
		play = onPlay,
		infos = onInfos,
		learn = onLearn,
		feedback = onFeedback,
		settings = onSettings,
		home = onHome,
	}

	gui = makeGui("MainMenu", 1)
	-- Les onglets passent au-dessus des écrans secondaires (DisplayOrder 2 et 3), qui s'ouvrent dessous
	tabsGui = makeGui("MenuTabs", 4)
	buildContent(UIKit.scaledRoot(gui))
	local tabsRoot = UIKit.scaledRoot(tabsGui)
	buildTitleColumn(tabsRoot)
	buildTabs(tabsRoot)
	MainMenu.setPage("home")
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onWeaponInput(input, processed)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onWeaponInput(input, processed)
		end
	end)
end

-- Cette méthode permet de changer la page active (onglet en os, fiche et équipement sur l'accueil seulement) lorsque
-- l'orchestrateur ouvre un écran secondaire ou revient à l'accueil ; l'équipement repart sur SNIPER en partant.
function MainMenu.setPage(page: Page)
	if not gui then
		return
	end
	currentPage = page
	content.Visible = page == "home"
	for key, tab in tabs do
		tab.setSelected(key == page)
	end
	for key, underline in underlines do
		underline.Visible = key == page
	end
	-- Hors de l'onglet ARMES, le personnage repasse au centre, derrière le bloc de l'écran ouvert
	MenuScene.setCentered(page ~= "home")
	if page ~= "home" then
		EquipmentScreen.reset()
	end
end

-- Cette méthode permet d'afficher un message sous les onglets pendant NOTICE_TIME lorsque l'orchestrateur doit
-- expliquer un retour au menu (apparition impossible, #219) ; un nouveau message remplace le précédent.
function MainMenu.showNotice(text: string)
	if not notice then
		return
	end
	noticeGeneration += 1
	local generation = noticeGeneration
	notice.Text = text
	noticeShadow.Text = text
	notice.Visible = true
	noticeShadow.Visible = true
	task.delay(NOTICE_TIME, function()
		if generation == noticeGeneration then
			notice.Visible = false
			noticeShadow.Visible = false
		end
	end)
end

-- Cette méthode permet de lire la page active lorsque l'orchestrateur doit décider où mène une touche.
function MainMenu.getPage(): Page
	return currentPage
end

-- Cette méthode permet d'afficher le menu et de lancer sa scène lorsque le joueur arrive au menu.
function MainMenu.show()
	if not gui then
		return
	end
	if not gui.Enabled then
		MenuShot.reset()
	end
	gui.Enabled = true
	tabsGui.Enabled = true
	MenuCursor.show()
	MainMenu.setPage("home")
	task.spawn(MenuScene.start)
end

-- Cette méthode permet de masquer le menu et sa scène lorsque la partie démarre.
function MainMenu.hide()
	if not gui then
		return
	end
	gui.Enabled = false
	tabsGui.Enabled = false
	MenuCursor.hide()
	for _, choice in choices do
		choice.reset()
	end
	EquipmentScreen.reset()
	-- JOUER garde les clics bloqués (`locks`) jusqu'ici : sans cela, les choix du menu en partie et de ses Réglages
	-- restaient sans effet (#157)
	MenuShot.reset()
	MenuScene.stop()
end

return MainMenu

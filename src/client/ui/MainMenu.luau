-- Menu principal, salle des miroirs (#112, docs/ui.md) : on choisit à la souris système, seule l'arme de la vitrine se
-- tire (hitmarker à son survol, le tir fait pivoter les éclats touchés, #130). Disposition de la maquette
-- (docs/ui/menu-miroirs/reconstituee.jpg) : titre en haut à gauche, onglets ARMES · INFOS · JOUER · RÉGLAGES · FEEDBACK en haut au centre (au-dessus des écrans secondaires,
-- qui s'ouvrent dessous), fiche de l'arme de la vitrine en bas à gauche, sélecteur d'arme en bas à droite.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local Rules = require(script.Parent.Parent.systems.game.MenuSceneRules)
local MenuCursor = require(script.Parent.MenuCursor)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

export type Page = "home" | "infos" | "settings" | "feedback"

local MainMenu = {}

local EDGE = 28 -- marge de la maquette (px à 720 de haut)
local TITLE_Y = 46 -- sous les boutons Roblox du coin haut gauche
local TABS_Y = 18
local PLAY_DELAY = 1.0 -- l'explosion de la vitrine se voit avant les volets
-- Onglets, de gauche à droite ; ARMES est l'accueil (la vitrine), JOUER l'appel à l'action
local TABS = {
	{ key = "home", text = "ARMES" },
	{ key = "infos", text = "INFOS" },
	{ key = "play", text = "JOUER" },
	{ key = "settings", text = "RÉGLAGES" },
	{ key = "feedback", text = "FEEDBACK" },
}
-- Fiche : jeu d'éclats de la vitrine -> clé de WeaponConfig, barres de 10 segments
local CONFIG_KEYS = { AWP = "AWP", M9 = "M9Bayonet" }
local SEGMENTS = 10
local SEGMENT_SIZE = Vector2.new(17, 3)
local SEGMENT_GAP = 4
local STATS = {
	{ key = "damage", label = "DÉGÂTS" },
	{ key = "rate", label = "CADENCE" },
	{ key = "accuracy", label = "PRÉCISION" },
}

local gui: ScreenGui
local tabsGui: ScreenGui
local content: Frame
local card: CanvasGroup
local cardName: TextLabel
local cardNameShadow: TextLabel
local cardCategory: TextLabel
local bars: { [string]: { Frame } } = {}
local tabs: { [string]: MenuShot.Choice } = {}
local choices: { MenuShot.Choice } = {}
local homeChoices: { MenuShot.Choice } = {} -- masqués hors de l'accueil
local callbacks: { [string]: (() -> ())? } = {}
local currentPage: Page = "home"

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

-- Cette méthode permet de construire le titre du jeu en haut à gauche lorsque le menu est initialisé.
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
	UIKit.text({
		Name = "Subtitle",
		Text = "COMBAT DE SURF",
		FontFace = F.DisplayMedium,
		TextSize = 12,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(EDGE + 1, TITLE_Y + 40),
		Size = UDim2.fromOffset(240, 14),
		Parent = root,
	})
end

-- Cette méthode permet de construire la barre d'onglets lorsque le menu est initialisé : JOUER, plus grand et
-- souligné de rouge d'impact, lance la partie après l'explosion de la vitrine.
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
			onFired = if isPlay then MenuScene.burst else nil,
			delay = if isPlay then PLAY_DELAY else nil,
			locks = isPlay,
		})
		if isPlay then
			UIKit.frame({
				Name = "Underline",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 4),
				Size = UDim2.new(1, -2, 0, 3),
				BackgroundColor3 = C.HitRed,
				ZIndex = 3,
				Parent = choice.button,
			})
		end
		tabs[tab.key] = choice
		table.insert(choices, choice)
	end
end

-- Cette méthode permet de construire une barre de stat (libellé ambré, segments) de la fiche lorsque le menu est initialisé.
local function buildBar(parent: Instance, key: string, label: string, y: number)
	UIKit.text({
		Name = key .. "Label",
		Text = label,
		FontFace = F.DisplayMedium,
		TextSize = 13,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(1, y),
		Size = UDim2.fromOffset(80, 14),
		Parent = parent,
	})
	local segments = {}
	for i = 1, SEGMENTS do
		segments[i] = UIKit.frame({
			Name = key .. i,
			Position = UDim2.fromOffset(80 + (i - 1) * (SEGMENT_SIZE.X + SEGMENT_GAP), y + 6),
			Size = UDim2.fromOffset(SEGMENT_SIZE.X, SEGMENT_SIZE.Y),
			BackgroundColor3 = C.Bone,
			Parent = parent,
		})
	end
	bars[key] = segments
end

-- Cette méthode permet de construire la fiche de l'arme (nom, catégorie, barres) en bas à gauche lorsque le menu est
-- initialisé.
local function buildCard(root: Frame)
	card = UIKit.create("CanvasGroup", {
		Name = "WeaponCard",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -112),
		Size = UDim2.fromOffset(360, 152),
		Parent = root,
	})
	cardName, cardNameShadow = UIKit.shadowedText(card, {
		Name = "Name",
		FontFace = F.Display,
		TextSize = 64,
		TextColor3 = C.Bone,
		Size = UDim2.fromOffset(350, 70),
		ZIndex = 2,
	}, 4)
	cardCategory = UIKit.text({
		Name = "Category",
		RichText = true,
		FontFace = F.DisplayMedium,
		TextSize = 14,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(1, 78),
		Size = UDim2.fromOffset(350, 16),
		Parent = card,
	})
	for i, stat in STATS do
		buildBar(card, stat.key, stat.label, 98 + (i - 1) * 18)
	end
end

-- Cette méthode permet de construire le sélecteur d'arme en bas à droite (flèches, rappel molette et touches)
-- lorsque le menu est initialisé ; les flèches remplacent la molette au tactile et à la manette.
local function buildSelector(root: Frame)
	local row = UIKit.frame({
		Name = "Selector",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE + 8, 1, -18),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for _, arrow in { { text = "‹", step = -1, order = 1 }, { text = "›", step = 1, order = 3 } } do
		local choice = MenuShot.textChoice({
			text = arrow.text,
			font = F.Display,
			size = 20,
			color = C.Bone,
			layoutOrder = arrow.order,
			parent = row,
			action = function()
				MenuScene.cycleWeapon(arrow.step)
			end,
		})
		UIKit.padding(choice.button :: any, 2, 8, 4, 8)
		table.insert(choices, choice)
		table.insert(homeChoices, choice)
	end
	UIKit.text({
		Name = "Hint",
		Text = "MOLETTE  ·  1-9",
		FontFace = F.DisplayMedium,
		TextSize = 13,
		TextColor3 = C.Bone,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 16),
		LayoutOrder = 2,
		Parent = row,
	})
end

-- Cette méthode permet de remplir la fiche avec l'arme montrée (stats rapportées à la meilleure arme de la vitrine,
-- dernier segment en rouge d'impact quand la barre est pleine) lorsque la vitrine change d'arme.
local function showWeapon(name: string)
	local weapons = MenuScene.getWeapons()
	local cfg = WeaponConfig.Weapons[CONFIG_KEYS[name] or name]
	if not cfg then
		return
	end
	local maxDamage, maxRate = 0, 0
	for _, other in weapons do
		local otherCfg = WeaponConfig.Weapons[CONFIG_KEYS[other] or other]
		if otherCfg then
			maxDamage = math.max(maxDamage, otherCfg.Damage or 0)
			maxRate = math.max(maxRate, otherCfg.RPM or 0)
		end
	end
	local filled = {
		damage = Rules.statSegments(cfg.Damage or 0, maxDamage, SEGMENTS),
		rate = Rules.statSegments(cfg.RPM or 0, maxRate, SEGMENTS),
		accuracy = Rules.statSegments(cfg.Accuracy or 0, 1, SEGMENTS),
	}
	local title = string.upper(cfg.Name)
	cardName.Text = title
	cardNameShadow.Text = title
	cardCategory.Text = string.format(
		'%s  <font color="#%s">·  %d / %d</font>',
		cfg.Category or "",
		C.Bone:ToHex(),
		table.find(weapons, name) or 1,
		#weapons
	)
	for key, segments in bars do
		local count = filled[key]
		for i, segment in segments do
			local lit = i <= count
			segment.BackgroundColor3 = if lit and count == SEGMENTS and i == SEGMENTS then C.HitRed else C.Bone
			segment.BackgroundTransparency = if lit then 0 else 0.78
		end
	end
	UIKit.reveal(card, 0, 6)
end

-- Cette méthode permet de construire l'accueil (titre, fiche, sélecteur) lorsque le menu est initialisé.
local function buildContent(root: Frame)
	content = UIKit.frame({ Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	buildTitle(content)
	buildCard(content)
	buildSelector(content)
	showWeapon(MenuScene.getWeapon())
	MenuScene.onWeaponChanged(showWeapon)
end

-- Cette méthode permet de tirer sur l'arme de la vitrine lorsque le joueur clique hors des boutons, sur l'accueil
-- seulement ; un clic à côté de l'arme ne tire pas.
local function onInputBegan(input: InputObject, processed: boolean)
	if processed or currentPage ~= "home" or MenuShot.isBusy() then
		return
	end
	local x, y
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		x, y = mouse.X, mouse.Y
	elseif input.UserInputType == Enum.UserInputType.Touch then
		x, y = input.Position.X, input.Position.Y + GuiService:GetGuiInset().Y
	else
		return
	end
	if MenuScene.shoot(x, y) then
		MenuCursor.kick()
	end
end

-- Touches 1 à 9 : rang de l'arme montrée dans la salle des miroirs
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

-- Cette méthode permet de changer l'arme de la vitrine (molette, touches 1-9) lorsque le joueur est sur l'accueil.
local function onWeaponInput(input: InputObject, processed: boolean)
	if processed or currentPage ~= "home" then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		MenuScene.cycleWeapon(if input.Position.Z > 0 then -1 else 1)
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local index = table.find(NUMBER_KEYS, input.KeyCode)
		if index then
			MenuScene.selectWeapon(index)
		end
	end
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
-- onSettings et onHome sont optionnels (navigation vers Settings et retour à l'accueil).
function MainMenu.init(
	onPlay: () -> (),
	onInfos: () -> (),
	onFeedback: () -> (),
	onSettings: (() -> ())?,
	onHome: (() -> ())?
)
	callbacks = { play = onPlay, infos = onInfos, feedback = onFeedback, settings = onSettings, home = onHome }

	gui = makeGui("MainMenu", 1)
	-- Les onglets passent au-dessus des écrans secondaires (DisplayOrder 2 et 3), qui s'ouvrent dessous
	tabsGui = makeGui("MenuTabs", 4)
	buildContent(UIKit.scaledRoot(gui))
	buildTabs(UIKit.scaledRoot(tabsGui))
	MainMenu.setPage("home")
	MenuCursor.init(function(x: number, y: number): boolean
		return currentPage == "home" and not MenuShot.isBusy() and MenuScene.isAimingWeapon(x, y)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onInputBegan(input, processed)
			onWeaponInput(input, processed)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onWeaponInput(input, processed)
		end
	end)
end

-- Cette méthode permet de changer la page active (onglet en os, fiche et sélecteur sur l'accueil seulement) lorsque
-- l'orchestrateur ouvre un écran secondaire ou revient à l'accueil.
function MainMenu.setPage(page: Page)
	if not gui then
		return
	end
	currentPage = page
	content.Visible = page == "home"
	for key, tab in tabs do
		tab.setSelected(key == page)
	end
	if page ~= "home" then
		for _, choice in homeChoices do
			choice.reset()
		end
	end
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

-- Cette méthode permet de masquer le menu, sa scène et le hitmarker lorsque la partie démarre.
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
	MenuScene.stop()
end

return MainMenu

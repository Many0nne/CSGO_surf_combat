-- Menu principal (docs/ui.md) : derrière, le personnage du jeu en pose sur une copie de la map (#253, MenuScene) ; on
-- choisit à la souris système, rien ne se tire. Titre en haut à gauche, onglets ARMES · INFOS · JOUER · RÉGLAGES ·
-- FEEDBACK en haut au centre (au-dessus des écrans secondaires, qui s'ouvrent dessous), fiche de l'arme tenue en bas à
-- gauche. L'onglet ARMES est l'écran d'équipement (#280, EquipmentScreen) : emplacements à gauche, armes et skins
-- possédés de l'emplacement actif à droite, le personnage tient l'arme survolée ou celle de l'emplacement actif.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local Rules = require(script.Parent.Parent.systems.game.MenuSceneRules)
local EquipmentScreen = require(script.Parent.EquipmentScreen)
local MenuCursor = require(script.Parent.MenuCursor)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

export type Page = "home" | "infos" | "settings" | "feedback"

local MainMenu = {}

local EDGE = 28 -- marge de la maquette (px à 720 de haut)
local TITLE_Y = 46 -- sous les boutons Roblox du coin haut gauche (plus bas si la fenêtre est petite, followTopbar)
local TOPBAR_GAP = 8 -- marge entre la barre de Roblox et le titre quand la colonne doit descendre (#306)
local TABS_Y = 18
local NOTICE_Y = 72 -- message sous les onglets (apparition impossible, #219)
local NOTICE_TIME = 5 -- s d'affichage de ce message
-- Onglets, de gauche à droite ; ARMES est l'accueil (le personnage et son arme), JOUER l'appel à l'action
local TABS = {
	{ key = "home", text = "ARMES" },
	{ key = "infos", text = "INFOS" },
	{ key = "play", text = "JOUER" },
	{ key = "settings", text = "RÉGLAGES" },
	{ key = "feedback", text = "FEEDBACK" },
}
-- Fiche : barres de 10 segments
local SEGMENTS = 10
local SEGMENT_SIZE = Vector2.new(17, 3)
local SEGMENT_GAP = 4
local BAR_LABEL_WIDTH = 96 -- colonne des libellés ambrés (16 px) avant les segments
local STATS = {
	{ key = "damage", label = "DÉGÂTS" },
	{ key = "rate", label = "CADENCE" },
	{ key = "accuracy", label = "PRÉCISION" },
}
local gui: ScreenGui
local tabsGui: ScreenGui
local content: Frame
local card: Frame
local cardName: TextLabel
local cardNameShadow: TextLabel
local cardCategory: TextLabel
local cardCategoryShadow: TextLabel
local bars: { [string]: { Frame } } = {}
local tabs: { [string]: MenuShot.Choice } = {}
local choices: { MenuShot.Choice } = {}
local callbacks: { [string]: (() -> ())? } = {}
local currentPage: Page = "home"
local notice: TextLabel
local noticeShadow: TextLabel
local noticeGeneration = 0
local shownWeapon: string? = nil -- arme de la fiche, pour ne rejouer son apparition qu'au changement

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
-- souligné de rouge d'impact, lance la partie (les volets se ferment aussitôt).
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

-- Cette méthode permet de construire une barre de stat (libellé ambré, segments) de la fiche lorsque le menu est initialisé.
local function buildBar(parent: GuiObject, key: string, label: string, y: number)
	UIKit.accentLabel(parent, {
		Name = key .. "Label",
		Text = label,
		Position = UDim2.fromOffset(1, y),
		Size = UDim2.fromOffset(BAR_LABEL_WIDTH, 18),
	})
	local segments = {}
	for i = 1, SEGMENTS do
		segments[i] = UIKit.frame({
			Name = key .. i,
			Position = UDim2.fromOffset(BAR_LABEL_WIDTH + (i - 1) * (SEGMENT_SIZE.X + SEGMENT_GAP), y + 8),
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
	card = UIKit.create("Frame", {
		Name = "WeaponCard",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -100),
		Size = UDim2.fromOffset(380, 168),
		Parent = root,
	})
	cardName, cardNameShadow = UIKit.shadowedText(card, {
		Name = "Name",
		FontFace = F.Display,
		TextSize = 64,
		TextColor3 = C.Bone,
		Size = UDim2.fromOffset(370, 70),
		ZIndex = 2,
	}, 4)
	-- Libellés ambrés à 16 px avec ombre (#280 : à 13 px, l'utilisateur les trouvait illisibles)
	cardCategory, cardCategoryShadow = UIKit.accentLabel(card, {
		Name = "Category",
		Position = UDim2.fromOffset(1, 76),
		Size = UDim2.fromOffset(370, 18),
	})
	for i, stat in STATS do
		buildBar(card, stat.key, stat.label, 102 + (i - 1) * 22)
	end
end

-- Cette méthode permet de remplir la fiche avec l'arme tenue (stats rapportées à la meilleure arme du menu, dernier
-- segment en rouge d'impact quand la barre est pleine) lorsque le personnage change d'arme.
local function showWeapon(name: string)
	local weapons = MenuScene.getWeapons()
	local cfg = WeaponConfig.Weapons[name]
	if not cfg then
		return
	end
	local maxDamage, maxRate = 0, 0
	for _, other in weapons do
		local otherCfg = WeaponConfig.Weapons[other]
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
	-- Plus de rang « n / m » : on ne fait plus défiler les armes possédées (#280)
	cardCategory.Text = cfg.Category or ""
	cardCategoryShadow.Text = cardCategory.Text
	for key, segments in bars do
		local count = filled[key]
		for i, segment in segments do
			local lit = i <= count
			segment.BackgroundColor3 = if lit and count == SEGMENTS and i == SEGMENTS then C.HitRed else C.Bone
			segment.BackgroundTransparency = if lit then 0 else 0.78
		end
	end
	-- Apparition rejouée seulement pour une autre arme : un clic d'équipement ne doit pas faire clignoter la fiche
	if name ~= shownWeapon then
		shownWeapon = name
		UIKit.reveal(card, 0, 6)
	end
end

-- Cette méthode permet de descendre la colonne de gauche (titre, « ÉQUIPEMENT », emplacements) sous la barre de Roblox
-- lorsque l'échelle de l'écran ou la hauteur de cette barre change (#306) : elle reste en px réels, l'interface non.
local function followTopbar(root: Frame, column: Frame)
	local function update()
		local scale = root:GetAttribute("Scale") or 1
		local shift = Rules.topbarShift(GuiService.TopbarInset.Max.Y, scale, TITLE_Y, TOPBAR_GAP)
		column.Position = UDim2.fromOffset(0, shift)
	end
	update()
	root:GetAttributeChangedSignal("Scale"):Connect(update)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(update)
end

-- Cette méthode permet de construire l'accueil (titre, fiche, écran d'équipement) lorsque le menu est initialisé.
local function buildContent(root: Frame)
	content = UIKit.frame({ Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	-- Colonne de gauche, décalée d'un bloc sous la barre de Roblox dans les petites fenêtres
	local column =
		UIKit.frame({ Name = "LeftColumn", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content })
	buildTitle(column)
	buildCard(content)
	EquipmentScreen.build(content, column)
	followTopbar(root, column)
	showWeapon(MenuScene.getWeapon())
	MenuScene.onWeaponChanged(showWeapon)
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

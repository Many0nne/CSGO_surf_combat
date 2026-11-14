-- Écran Infos (MenuPage) : bloc centré sur un voile, titre, sections en onglets en boîte (#308), contenu dessous
-- (texte, ou lignes « touche en boîte → action » pour COMMANDES), RETOUR en bas au centre. L'explication du surf et sa
-- démo sont dans l'écran Apprendre (#285, LearnScreen).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))
local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local InfosRules = require(script.Parent.InfosRules)
local MenuPage = require(script.Parent.MenuPage)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local InfosScreen = {}

-- `lines` : texte fixe ; `keys` : lignes touche → action (COMMANDES), recomposées à chaque affichage depuis
-- KeyBindings et les réglages du joueur (#290).
type Section = {
	title: string,
	lines: { string }?,
	keys: boolean?,
}

-- Contenu sous les onglets (px à 720 de haut)
local CONTENT_WIDTH = MenuPage.BlockWidth
local CONTENT_HEIGHT = MenuPage.ContentBottom - MenuPage.ContentTop
local TEXT_SIZE = 22
local KEY_COLUMN = 170 -- largeur réservée à la touche en boîte

local SECTIONS: { Section } = {
	{
		title = "COMMANDES",
		keys = true,
	},
	{
		title = "CRÉDITS",
		lines = {
			"Physique inspirée du Source SDK (surf de CS:GO).",
			"Headshot 2 by SilverIllusionist -- https://freesound.org/s/470586/ -- License: Attribution 4.0",
		},
	},
	{
		title = "À PROPOS",
		lines = {
			"Ce jeu est un projet passion mené en solo par un développeur web qui apprend la 3D et l'animation en chemin.",
			"Le but n'est pas de cloner CS:GO, mais de reprendre ce qui rend le surf génial et de bâtir quelque chose d'original dessus.",
			"De nouvelles armes, skins et animations sont prévus, tous créés de zéro avec l'originalité en tête.",
			"Merci de jouer alors que le jeu est encore brut de décoffrage.",
			"Envie de donner ton avis ou de filer un coup de main ? Rejoins le Discord : discord.gg/QK66g32mbB",
		},
	},
}

local page: MenuPage.Page
local content: ScrollingFrame
local markTab: (number) -> ()
local selected = 1

-- Cette méthode permet d'afficher une ligne de texte en fondu avec un décalage lorsqu'un onglet se remplit.
local function fadeIn(labels: { TextLabel }, delay: number)
	for _, lbl in labels do
		lbl.TextTransparency = 1
	end
	task.delay(delay, function()
		for _, lbl in labels do
			UIKit.tween(lbl, Motion.Enter, { TextTransparency = 0 })
		end
	end)
end

-- Cette méthode permet de créer une ligne de paragraphe à hauteur automatique lorsque l'onglet affiché est du texte.
local function addParagraph(text: string, order: number): TextLabel
	return UIKit.text({
		Name = "Line" .. order,
		Text = text,
		FontFace = F.DisplayText,
		TextSize = TEXT_SIZE,
		TextColor3 = C.Bone,
		TextWrapped = true,
		LineHeight = 1.2,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, TEXT_SIZE),
		LayoutOrder = order,
		Parent = content,
	})
end

-- Cette méthode permet de créer une ligne « touche en boîte os → action » sur un filet lorsque l'onglet affiché est
-- COMMANDES (#308 : même écriture des touches que l'aide de l'écran d'équipement).
local function addKeyRow(key: string, action: string, order: number): { TextLabel }
	local row = UIKit.frame({
		Name = "Key" .. order,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = content,
	})
	UIKit.frame({
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.88,
		Parent = row,
	})
	local keyLbl = UIKit.tag(row, "KeyTag", 1, C.Bone, C.Ground)
	keyLbl.Text = key
	keyLbl.AnchorPoint = Vector2.new(0, 0.5)
	keyLbl.Position = UDim2.fromScale(0, 0.5)
	local actionLbl = UIKit.text({
		Text = action,
		FontFace = F.DisplayText,
		TextSize = TEXT_SIZE,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(KEY_COLUMN, 0),
		Size = UDim2.new(1, -KEY_COLUMN, 1, 0),
		Parent = row,
	})
	return { keyLbl, actionLbl }
end

-- Cette méthode permet de réunir ce dont les textes à touches dépendent lorsqu'un écran les compose (Infos, Apprendre) :
-- actions de l'affichage des touches (KeyBindings), libellés du clavier du joueur et réglages d'armes.
function InfosScreen.composeContext(): InfosRules.Context
	local settings = LocalSettings.get()
	return {
		entries = HUDRules.keyDisplayEntries("full"),
		keyText = LocalSettings.keyText,
		menuKey = PlayerSettings.MENU_KEY,
		slotKeys = settings.slotKeys,
		defaultSlotKeys = PlayerSettings.DEFAULT_SLOT_KEYS,
		wheel = settings.wheel,
	}
end

-- Cette méthode permet de remplir la zone de contenu avec la section choisie lorsque l'onglet change.
local function renderSection(index: number)
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	content.CanvasPosition = Vector2.zero

	local section = SECTIONS[index]
	if section.keys then
		for i, row in InfosRules.commandRows(InfosScreen.composeContext()) do
			fadeIn(addKeyRow(row.key, row.action, i), i * Motion.Stagger)
		end
	else
		for i, line in section.lines or {} do
			fadeIn({ addParagraph(line, i) }, i * Motion.Stagger)
		end
	end
end

-- Cette méthode permet de marquer l'onglet choisi (boîte ambrée) et d'afficher sa section lorsque le joueur clique dessus.
local function selectTab(index: number)
	selected = index
	markTab(index)
	renderSection(index)
end

-- Cette méthode permet de construire l'écran, ses onglets et sa zone de contenu lorsque le client démarre.
function InfosScreen.init(onClose: () -> ())
	page = MenuPage.new("InfosScreen", 2, "INFOS")
	content = UIKit.create("ScrollingFrame", {
		Name = "Text",
		Position = UDim2.fromOffset(0, MenuPage.ContentTop),
		Size = UDim2.fromOffset(CONTENT_WIDTH, CONTENT_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromScale(0, 0),
		Parent = page.block,
	})
	UIKit.padding(content, 6, 16, 6, 0)
	UIKit.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
		Parent = content,
	})

	local titles = {}
	for i, section in SECTIONS do
		titles[i] = section.title
	end
	markTab = page.tabs(titles, selectTab)
	page.action("RETOUR", onClose).setSelected(true)

	-- Touches d'armes ou molette changées dans Réglages pendant que Infos est ouvert : l'onglet se recompose ; les autres
	-- réglages ne touchent pas l'écran (sinon le défilement reviendrait en haut).
	local shownSlotKeys, shownWheel = table.concat(LocalSettings.get().slotKeys, ","), LocalSettings.get().wheel
	LocalSettings.onChanged(function(settings)
		local slotKeys = table.concat(settings.slotKeys, ",")
		if slotKeys == shownSlotKeys and settings.wheel == shownWheel then
			return
		end
		shownSlotKeys, shownWheel = slotKeys, settings.wheel
		if page.gui.Enabled then
			renderSection(selected)
		end
	end)

	selectTab(1)
end

-- Cette méthode permet d'ouvrir l'écran sur le dernier onglet consulté lorsque le joueur tire sur INFOS.
function InfosScreen.show()
	if not page or page.gui.Enabled then
		return
	end
	page.show()
	selectTab(selected)
end

-- Cette méthode permet de masquer l'écran lorsque le joueur le quitte ou que la partie démarre.
function InfosScreen.hide()
	if page then
		page.hide()
	end
end

return InfosScreen

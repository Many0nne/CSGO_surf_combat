-- Menu principal (direction « Tactical ») : barre de navigation en haut (ACCUEIL, INFOS, SETTINGS, FEEDBACK, PLAY)
-- et page d'accueil. Infos et Settings sont des ScreenGui à part, affichés sous cette barre.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion
local L = UITheme.Layout

export type Page = "home" | "infos" | "settings"

local MainMenu = {}

local NAV_ITEMS: { { page: Page?, label: string } } = {
	{ page = "home", label = "ACCUEIL" },
	{ page = "infos", label = "INFOS" },
	{ page = "settings", label = "SETTINGS" },
	{ page = nil, label = "FEEDBACK" },
}

local gui: ScreenGui
local grade: ColorCorrectionEffect
local header: Frame
local navUnderline: Frame
local navButtons: { [Page]: TextButton } = {}
local homeGroups: { CanvasGroup } = {}
local currentPage: Page = "home"
local callbacks: { [string]: (() -> ())? } = {}

-- Cette méthode permet d'appeler un rappel enregistré lorsqu'un bouton du menu est cliqué.
local function fire(name: string)
	local fn = callbacks[name]
	if fn then
		fn()
	end
end

-- Cette méthode permet de construire le voile dégradé plein écran lorsque le menu se pose sur la scène du lobby.
local function buildShade()
	local shade =
		UIKit.frame({ Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ground, Parent = gui })
	UIKit.create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.55, 0.45),
			NumberSequenceKeypoint.new(1, 0.04),
		}),
		Parent = shade,
	})
end

-- Cette méthode permet de construire le bloc logo (emblème + SURF FFA) lorsque la barre de navigation est créée.
local function buildBrand(parent: Frame)
	local brand = UIKit.frame({
		Name = "Brand",
		Size = UDim2.new(0, 196, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local emblem = UIKit.emblem(brand)
	emblem.AnchorPoint = Vector2.new(0, 0.5)
	emblem.Position = UDim2.new(0, 28, 0.5, 0)
	UIKit.text({
		Text = 'SURF <font color="#F2A900">FFA</font>',
		RichText = true,
		FontFace = F.Display,
		TextSize = T.Title,
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -70, 1, 0),
		Parent = brand,
	})
	UIKit.frame({
		Name = "Divider",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = C.Border,
		Parent = brand,
	})
end

-- Cette méthode permet de créer un onglet de navigation avec son soulignement de survol lorsqu'il est ajouté à la barre.
local function buildNavButton(parent: Frame, index: number, item: { page: Page?, label: string })
	local btn = UIKit.button({
		Name = item.label,
		Text = item.label,
		Size = UDim2.new(0, L.NavItemWidth, 1, 0),
		Position = UDim2.fromOffset((index - 1) * L.NavItemWidth, 0),
		BackgroundTransparency = 1,
		FontFace = F.Display,
		TextSize = T.Nav,
		TextColor3 = C.Muted,
		Parent = parent,
	})
	local hoverLine = UIKit.frame({
		Name = "HoverLine",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = C.Text,
		Parent = btn,
	})
	btn.MouseEnter:Connect(function()
		UIKit.tween(btn, Motion.Hover, { TextColor3 = C.White })
		UIKit.tween(hoverLine, Motion.Hover, { Size = UDim2.fromOffset(L.NavItemWidth - 56, 2) })
	end)
	btn.MouseLeave:Connect(function()
		local active = item.page ~= nil and item.page == currentPage
		UIKit.tween(btn, Motion.Hover, { TextColor3 = active and C.White or C.Muted })
		UIKit.tween(hoverLine, Motion.Hover, { Size = UDim2.fromOffset(0, 2) })
	end)
	btn.MouseButton1Click:Connect(function()
		if item.page == "home" then
			fire("home")
		elseif item.page == "infos" then
			fire("infos")
		elseif item.page == "settings" then
			fire("settings")
		else
			fire("feedback")
		end
	end)
	if item.page then
		navButtons[item.page] = btn
	end
end

-- Cette méthode permet de construire le gros bouton PLAY ambre avec sa flèche lorsque la barre de navigation est créée.
local function buildPlayButton(parent: Frame)
	local play = UIKit.button({
		Name = "Play",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 220, 1, 0),
		BackgroundColor3 = C.Accent,
		Parent = parent,
	})
	local content = UIKit.frame({
		Name = "Content",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(110, 30),
		BackgroundTransparency = 1,
		Parent = play,
	})
	UIKit.text({
		Text = "PLAY",
		FontFace = F.Display,
		TextSize = 26,
		TextColor3 = C.Ground,
		Size = UDim2.fromOffset(70, 30),
		Parent = content,
	})
	local arrow = UIKit.arrowIcon(content, C.Ground)
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.Position = UDim2.new(0, 84, 0.5, 0)

	UIKit.hover(play, play, { BackgroundColor3 = C.Accent }, { BackgroundColor3 = C.AccentHover })
	UIKit.hover(play, arrow, { Position = UDim2.new(0, 84, 0.5, 0) }, { Position = UDim2.new(0, 90, 0.5, 0) })
	play.MouseButton1Down:Connect(function()
		UIKit.tween(play, Motion.Press, { BackgroundColor3 = C.AccentPress })
	end)
	play.MouseButton1Click:Connect(function()
		fire("play")
	end)
end

-- Cette méthode permet de construire la barre de navigation complète lorsque le menu est initialisé.
local function buildHeader(root: Frame)
	header = UIKit.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, L.HeaderHeight),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.06,
		Parent = root,
	})
	UIKit.frame({
		Name = "BottomBorder",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Border,
		Parent = header,
	})
	-- Logo + onglets décalés à droite des boutons Roblox (taille fixe en pixels écran, hors UIScale)
	local bar = UIKit.frame({
		Name = "Bar",
		Size = UDim2.new(0, 208 + L.NavItemWidth * #NAV_ITEMS, 1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	})
	local function placeBar()
		local scale = root:GetAttribute("Scale") or 1
		bar.Position = UDim2.fromOffset(math.ceil(L.TopbarSafeLeft / scale), 0)
	end
	placeBar()
	root:GetAttributeChangedSignal("Scale"):Connect(placeBar)
	buildBrand(bar)

	local nav = UIKit.frame({
		Name = "Nav",
		Position = UDim2.fromOffset(208, 0),
		Size = UDim2.new(0, L.NavItemWidth * #NAV_ITEMS, 1, 0),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	for i, item in NAV_ITEMS do
		buildNavButton(nav, i, item)
	end
	navUnderline = UIKit.frame({
		Name = "ActiveLine",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(L.NavItemWidth, 3),
		BackgroundColor3 = C.Accent,
		ZIndex = 2,
		Parent = nav,
	})
	buildPlayButton(header)
end

-- Cette méthode permet de créer un groupe animable (fondu + glissement) de la page d'accueil lorsqu'elle est construite.
local function homeGroup(root: Frame, props: { [string]: any }): CanvasGroup
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.Parent = root
	local group = UIKit.create("CanvasGroup", props)
	table.insert(homeGroups, group)
	return group
end

-- Cette méthode permet de construire la page d'accueil (titre du mode, raccourcis, version) lorsque le menu est initialisé.
local function buildHome(root: Frame)
	local hero = homeGroup(root, {
		Name = "Hero",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, L.Margin, 1, -72),
		Size = UDim2.fromOffset(620, 270),
	})
	UIKit.text({
		Text = "MODE DE JEU",
		FontFace = F.MonoBold,
		TextSize = 13,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = hero,
	})
	UIKit.text({
		Text = "FREE\nFOR ALL",
		FontFace = F.Display,
		TextSize = T.Hero,
		LineHeight = 0.8,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 180),
		Parent = hero,
	})
	UIKit.text({
		Text = "Rampes, air strafe et bhop façon Source. Chacun pour soi, rounds de 5 minutes.",
		TextSize = 18,
		TextColor3 = C.TextSoft,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 214),
		Size = UDim2.fromOffset(460, 56),
		Parent = hero,
	})

	local card = homeGroup(root, {
		Name = "Shortcuts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -L.Margin, 1, -72),
		Size = UDim2.fromOffset(320, 156),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
	})
	UIKit.stroke(card, C.Border)
	local cardHeader = UIKit.frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		Parent = card,
	})
	UIKit.text({
		Text = "RACCOURCIS",
		FontFace = F.DisplayMedium,
		TextSize = 15,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -36, 1, 0),
		Parent = cardHeader,
	})
	UIKit.frame({
		Name = "Marker",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.Accent,
		Parent = cardHeader,
	})
	UIKit.frame({
		Name = "Divider",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Border,
		Parent = card,
	})
	for i, row in { { "Classement", "TAB" }, { "Réglages", "P" }, { "Bhop", "SPACE" } } do
		local y = 48 + 16 + (i - 1) * 28
		UIKit.text({
			Text = row[1],
			TextSize = 15,
			TextColor3 = C.TextSoft,
			Position = UDim2.fromOffset(18, y),
			Size = UDim2.new(1, -36, 0, 20),
			Parent = card,
		})
		UIKit.text({
			Text = row[2],
			FontFace = F.Mono,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(18, y),
			Size = UDim2.new(1, -36, 0, 20),
			Parent = card,
		})
	end

	local version = homeGroup(root, {
		Name = "Version",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, L.Margin, 1, -24),
		Size = UDim2.fromOffset(80, 16),
	})
	UIKit.text({
		Text = "v0.1",
		FontFace = F.Mono,
		TextSize = T.Caption,
		TextColor3 = C.Muted,
		Size = UDim2.fromScale(1, 1),
		Parent = version,
	})
end

-- Cette méthode permet de rejouer l'entrée de la page d'accueil (fondu décalé de chaque bloc) lorsqu'elle redevient visible.
local function revealHome()
	for i, group in homeGroups do
		group.Visible = true
		UIKit.reveal(group, 0.08 + (i - 1) * 0.06)
	end
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

	gui = UIKit.create("ScreenGui", {
		Name = "MainMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	grade = UIKit.create("ColorCorrectionEffect", {
		Name = "MenuGrade",
		Saturation = -0.35,
		Brightness = -0.08,
		Enabled = false,
		Parent = Lighting,
	})

	buildShade()
	local root = UIKit.scaledRoot(gui)
	buildHome(root)
	buildHeader(root)
end

-- Cette méthode permet de changer la page active (soulignement, couleur des onglets, accueil visible ou non)
-- lorsque l'orchestrateur ouvre Infos, Settings ou revient à l'accueil.
function MainMenu.setPage(page: Page)
	if not gui then
		return
	end
	local previous = currentPage
	currentPage = page
	local index = page == "home" and 0 or page == "infos" and 1 or 2
	UIKit.tween(navUnderline, Motion.Nav, { Position = UDim2.new(0, index * L.NavItemWidth, 1, 0) })
	for name, btn in navButtons do
		UIKit.tween(btn, Motion.Hover, { TextColor3 = name == page and C.White or C.Muted })
	end
	if page == "home" then
		if previous ~= "home" then
			revealHome()
		end
	else
		for _, group in homeGroups do
			group.Visible = false
		end
	end
end

function MainMenu.show()
	if not gui then
		return
	end
	local wasHidden = not gui.Enabled
	gui.Enabled = true
	grade.Enabled = true
	if wasHidden then
		header.Position = UDim2.fromOffset(0, -L.HeaderHeight)
		UIKit.tween(header, Motion.Enter, { Position = UDim2.fromOffset(0, 0) })
		currentPage = "home"
		MainMenu.setPage("home")
		revealHome()
	else
		MainMenu.setPage("home")
	end
end

function MainMenu.hide()
	if gui then
		gui.Enabled = false
	end
	if grade then
		grade.Enabled = false
	end
end

return MainMenu

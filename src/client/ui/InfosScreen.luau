-- Page Infos (direction « Tactical ») : onglets à gauche (HOW TO SURF, CONTROLS, CREDITS, ABOUT),
-- contenu à droite, affichée sous la barre de navigation du menu principal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion
local L = UITheme.Layout

local InfosScreen = {}

type Section = { title: string, lines: { string }?, keys: { { string } }? }

local SECTIONS: { Section } = {
	{
		title = "HOW TO SURF",
		lines = {
			"Approach a ramp and align yourself PARALLEL to its surface.",
			"Hold A or D to press into the ramp — never use W while surfing.",
			"Steer along the ramp's direction with your mouse to gain speed.",
			"Stay on the ramp's sweet spot: not too high, not too low.",
			"Chain ramps smoothly — use air strafes (A/D + mouse) between them.",
			"Never jump onto a ramp — let gravity carry you onto it.",
		},
	},
	{
		title = "CONTROLS",
		keys = {
			{ "W A S D", "Movement" },
			{ "SPACE", "Jump / Bhop (hold for long jumps)" },
			{ "CTRL", "Crouch" },
			{ "LEFT CLICK", "Fire" },
			{ "R", "Reload" },
			{ "F", "Inspect weapon" },
			{ "TAB", "Leaderboard" },
			{ "P", "Settings" },
		},
	},
	{
		title = "CREDITS",
		lines = {
			"Physics inspired by the Source SDK (CS:GO surf).",
		},
	},
	{
		title = "ABOUT",
		lines = {
			"This game is a solo passion project by a web developer learning 3D and animation on the go.",
			"The goal isn't to clone CS:GO — it's to take what makes surf feel great and build something original on top of it.",
			"New weapons, skins, and animations are planned, all made from scratch with originality in mind.",
			"Thanks for playing while it's still rough around the edges.",
			"Want to give feedback or help out? Join the Discord: discord.gg/QK66g32mbB",
		},
	},
}

local gui: ScreenGui
local panel: CanvasGroup
local content: ScrollingFrame
local tabs: { { button: TextButton, bar: Frame } } = {}
local selected = 1
local onCloseCallback: (() -> ())?

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
		TextSize = 18,
		TextColor3 = C.TextSoft,
		TextWrapped = true,
		LineHeight = 1.15,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		Parent = content,
	})
end

-- Cette méthode permet de créer une ligne « touche → action » soulignée lorsque l'onglet affiché est CONTROLS.
local function addKeyRow(key: string, action: string, order: number): { TextLabel }
	local row = UIKit.frame({
		Name = "Key" .. order,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = content,
	})
	UIKit.frame({
		Name = "Underline",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Raised,
		Parent = row,
	})
	local keyLbl = UIKit.text({
		Text = key,
		FontFace = F.MonoBold,
		TextSize = T.Small,
		TextColor3 = C.Accent,
		Size = UDim2.new(0, 150, 1, 0),
		Parent = row,
	})
	local actionLbl = UIKit.text({
		Text = action,
		TextSize = 18,
		Position = UDim2.fromOffset(150, 0),
		Size = UDim2.new(1, -150, 1, 0),
		Parent = row,
	})
	return { keyLbl, actionLbl }
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
	local title = UIKit.text({
		Name = "Title",
		Text = section.title,
		FontFace = F.Display,
		TextSize = T.H1,
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 0,
		Parent = content,
	})
	fadeIn({ title }, 0)

	if section.keys then
		for i, pair in section.keys do
			fadeIn(addKeyRow(pair[1], pair[2], i), i * Motion.Stagger)
		end
	else
		for i, line in section.lines or {} do
			fadeIn({ addParagraph(line, i) }, i * Motion.Stagger)
		end
	end
end

-- Cette méthode permet de mettre en avant l'onglet choisi (fond, texte, barre ambre) lorsque l'utilisateur clique dessus.
local function selectTab(index: number)
	selected = index
	for i, tab in tabs do
		local active = i == index
		UIKit.tween(tab.button, Motion.Hover, {
			BackgroundTransparency = active and 0 or 1,
			TextColor3 = active and C.White or C.Muted,
		})
		tab.bar.Visible = active
	end
	renderSection(index)
end

-- Cette méthode permet de créer la colonne d'onglets lorsque la page est construite.
local function buildTabs(parent: CanvasGroup)
	local column = UIKit.frame({
		Name = "Tabs",
		Size = UDim2.new(0, 260, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.padding(column, 16, 0, 16, 0)
	UIKit.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = column })
	UIKit.frame({
		Name = "Divider",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = C.Border,
		Parent = parent,
	})

	for i, section in SECTIONS do
		local btn = UIKit.button({
			Name = section.title,
			Text = "",
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundColor3 = C.Raised,
			BackgroundTransparency = 1,
			TextColor3 = C.Muted,
			LayoutOrder = i,
			Parent = column,
		})
		-- Le libellé suit la couleur du bouton (TextColor3 animé sur le bouton, recopié ici)
		local label = UIKit.text({
			Text = section.title,
			FontFace = F.DisplayMedium,
			TextSize = T.Body,
			TextColor3 = C.Muted,
			Position = UDim2.fromOffset(21, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Parent = btn,
		})
		btn:GetPropertyChangedSignal("TextColor3"):Connect(function()
			label.TextColor3 = btn.TextColor3
		end)
		UIKit.text({
			Text = string.format("%02d", i),
			FontFace = F.Mono,
			TextSize = T.Caption,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, -18, 1, 0),
			Parent = btn,
		})
		local bar = UIKit.frame({
			Name = "ActiveBar",
			Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = C.Accent,
			Visible = false,
			Parent = btn,
		})
		btn.MouseEnter:Connect(function()
			if selected ~= i then
				UIKit.tween(btn, Motion.Hover, { BackgroundTransparency = 0, TextColor3 = C.White })
			end
		end)
		btn.MouseLeave:Connect(function()
			if selected ~= i then
				UIKit.tween(btn, Motion.Hover, { BackgroundTransparency = 1, TextColor3 = C.Muted })
			end
		end)
		btn.MouseButton1Click:Connect(function()
			selectTab(i)
		end)
		tabs[i] = { button = btn, bar = bar }
	end
end

function InfosScreen.init(onClose: () -> ())
	onCloseCallback = onClose

	gui = UIKit.create("ScreenGui", {
		Name = "InfosScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = UIKit.scaledRoot(gui)

	panel = UIKit.create("CanvasGroup", {
		Name = "Panel",
		Position = UDim2.fromOffset(L.Margin, L.ContentTop),
		Size = UDim2.new(1, -2 * L.Margin, 0, 560),
		BackgroundColor3 = C.Ground,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Parent = root,
	})
	UIKit.stroke(panel, C.Border)
	buildTabs(panel)

	content = UIKit.create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(260, 0),
		Size = UDim2.new(1, -260, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromScale(0, 0),
		Parent = panel,
	})
	UIKit.padding(content, 30, 96, 30, 40)
	UIKit.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
		Parent = content,
	})

	local close = UIKit.closeButton(panel)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -24, 0, 24)
	close.ZIndex = 2
	close.MouseButton1Click:Connect(function()
		if onCloseCallback then
			onCloseCallback()
		end
	end)

	selectTab(1)
end

function InfosScreen.show()
	if not gui or gui.Enabled then
		return
	end
	gui.Enabled = true
	selectTab(selected)
	UIKit.reveal(panel, 0, 14)
end

function InfosScreen.hide()
	if gui then
		gui.Enabled = false
	end
end

return InfosScreen

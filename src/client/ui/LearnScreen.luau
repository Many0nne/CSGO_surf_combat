-- Écran Apprendre (MenuPage, #285) : onglet APPRENDRE du menu principal. Bloc centré sur un voile, titre, démo rejouée
-- dans le moteur (DemoPlayer : touches, souris et vitesse synchronisées), sélecteur s'il y a plusieurs démos, puis le
-- texte d'explication du surf (InfosRules.surfLines), RETOUR en bas au centre. Le lecteur (copie de la map comprise)
-- n'existe que tant que l'écran est affiché.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local DemoPlayer = require(script.Parent.DemoPlayer)
local InfosRules = require(script.Parent.InfosRules)
local InfosScreen = require(script.Parent.InfosScreen)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local LearnScreen = {}

-- Contenu sous le titre (px à 720 de haut) : pas d'onglets, il prend leur place
local CONTENT_TOP = MenuPage.TabsY
local CONTENT_HEIGHT = MenuPage.ContentBottom - CONTENT_TOP
local CHOICE_SIZE = 20
local CHOICE_GAP = 28
local UNDERLINE = 2 -- trait ambré sous la démo choisie (« là où je suis »)

local page: MenuPage.Page
local content: ScrollingFrame
local selectedDemo = 1
local demo: DemoPlayer.Demo? -- lecteur, détruit dès que l'écran se ferme

-- Cette méthode permet d'arrêter la démo et de libérer son lecteur (copie de la map comprise) lorsque le joueur quitte
-- l'écran ou que son contenu est recomposé.
local function stopDemo()
	if demo then
		demo.destroy()
		demo = nil
	end
end

-- Cette méthode permet de poser le sélecteur des démos (s'il y en a plusieurs) puis le lecteur en tête du contenu
-- lorsque l'écran s'affiche ; un choix relance la lecture sur sa démo, soulignée d'ambre.
local function addDemos(ctx: InfosRules.Context)
	local clips = InfosRules.demoClips(ctx)
	local ids = {}
	for i, clip in clips do
		ids[i] = clip.id
	end
	local row = UIKit.frame({
		Name = "DemoChoices",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CHOICE_SIZE + 12),
		Visible = #clips > 1,
		LayoutOrder = 1,
		Parent = content,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CHOICE_GAP),
		Parent = row,
	})
	local holder = UIKit.frame({
		Name = "DemoHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, DemoPlayer.Size.Y),
		LayoutOrder = 2,
		Parent = content,
	})
	local player = DemoPlayer.new(holder, 0, ids)
	player.frame.AnchorPoint = Vector2.new(0.5, 0)
	player.frame.Position = UDim2.fromScale(0.5, 0)
	demo = player

	local choices: { MenuShot.Choice } = {}
	local underlines: { Frame } = {}
	-- Cette méthode permet de marquer la démo choisie et de la lancer lorsque le joueur clique sur son nom.
	local function choose(index: number)
		selectedDemo = index
		for i, choice in choices do
			choice.setSelected(i == index)
			underlines[i].Visible = i == index
		end
		local clip = clips[index]
		player.play(clip.id, clip.title, clip.caption)
	end
	for i, clip in clips do
		choices[i] = MenuShot.textChoice({
			text = clip.title,
			font = F.Display,
			size = CHOICE_SIZE,
			color = C.TextSoft,
			selectedColor = C.Bone,
			layoutOrder = i,
			parent = row,
			action = function()
				choose(i)
			end,
		})
		underlines[i] = UIKit.frame({
			Name = "Underline",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 4),
			Size = UDim2.new(1, 0, 0, UNDERLINE),
			BackgroundColor3 = C.Accent,
			Visible = false,
			Parent = choices[i].button,
		})
	end
	choose(math.clamp(selectedDemo, 1, #clips))
end

-- Cette méthode permet de remplir le contenu (démo puis texte du surf, touches du joueur) lorsque l'écran s'ouvre ou
-- que les touches changent pendant qu'il est ouvert.
local function render()
	stopDemo()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	content.CanvasPosition = Vector2.zero
	local ctx = InfosScreen.composeContext()
	addDemos(ctx)
	-- Après le sélecteur et le lecteur (ordres 1 et 2)
	for i, line in InfosRules.surfLines(ctx) do
		MenuPage.fadeIn({ MenuPage.paragraph(content, line, 2 + i) }, i * Motion.Stagger)
	end
end

-- Cette méthode permet de construire l'écran et sa zone de contenu lorsque le client démarre.
function LearnScreen.init(onClose: () -> ())
	page = MenuPage.new("LearnScreen", 2, "APPRENDRE")
	content = UIKit.create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, CONTENT_TOP),
		Size = UDim2.fromOffset(MenuPage.BlockWidth, CONTENT_HEIGHT),
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
	-- Les textes ne citent que les touches de mouvement et de saut (KeyBindings, non réglables) : composés à l'ouverture
	page.action("RETOUR", onClose).setSelected(true)
end

-- Cette méthode permet d'ouvrir l'écran et de lancer la démo lorsque le joueur touche l'onglet APPRENDRE.
function LearnScreen.show()
	if not page or page.gui.Enabled then
		return
	end
	page.show()
	render()
end

-- Cette méthode permet de masquer l'écran et de libérer la démo lorsque le joueur le quitte ou que la partie démarre.
function LearnScreen.hide()
	stopDemo()
	if page then
		page.hide()
	end
end

return LearnScreen

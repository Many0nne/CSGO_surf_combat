-- Réglages (direction « Ligne de mire », disposition C de #117) : bloc centré sur un voile, catégories à tirer à gauche,
-- lignes de réglages à droite (nom, contrôle, valeur), RÉTABLIR et RETOUR en bas au centre. Deux présentations du même
-- écran : « page » à même la scène du menu, où l'on règle en tirant, et « modal » sur un voile sombre (touche P en
-- partie), sans tir ni hitmarker. Pour ajouter un réglage : une entrée dans `buildCategories`.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local MenuCursor = require(script.Parent.MenuCursor)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

export type Mode = "page" | "modal"

local SettingsMenu = {}

-- Bloc centré (px à 720 de haut) : catégories à gauche, lignes à droite
local BLOCK_WIDTH = 780
local CATS_TOP = MenuPage.ContentTop
local CAT_SIZE = 24
local CAT_STEP = 42
local ROWS_X = 220
local ROWS_TOP = MenuPage.ContentTop - 10
local ROW_WIDTH = BLOCK_WIDTH - ROWS_X
local ROW_HEIGHT = 54
local NAME_WIDTH = 246
local VALUE_WIDTH = 70
local VALUE_SIZE = 26
local VALUE_SHADOW = 3
local PICK_WIDTH = 120
local ACTION_SIZE = 30
local ACTION_GAP = 46
local BACKDROP_TRANSPARENCY = 0.45

type Row = { reset: () -> () }
type Category = { title: string, rows: Frame, list: { Row } }

local page: MenuPage.Page?
local backdrop: Frame
local open = false
local mode: Mode = "modal"
local savedMouseBehavior = Enum.MouseBehavior.LockCenter
local savedMouseIcon = false
local onClosedCallback: (() -> ())?
local pageRequest: (() -> boolean)?
local fpsCamRef: {
	setSensitivity: (number) -> (),
	getSensitivity: () -> number,
	setScopeMultiplier: (number) -> (),
	getScopeMultiplier: () -> number,
}?
local categories: { Category } = {}
local categoryTabs: { MenuShot.Choice } = {}
local categoryBars: { Frame } = {}
local selected = 1

-- Cette méthode permet de savoir si un geste doit tirer lorsqu'il est fait dans l'écran : jamais en partie.
local function shoots(): boolean
	return mode == "page"
end

-- Cette méthode permet de doubler la valeur d'une ligne d'une ombre noire décalée qui suit son texte lorsqu'elle est construite.
local function shadowValue(value: TextBox | TextLabel)
	local shadow = UIKit.text({
		Name = value.Name .. "Shadow",
		Text = value.Text,
		FontFace = value.FontFace,
		TextSize = value.TextSize,
		TextColor3 = C.Black,
		TextTransparency = 0.35,
		TextXAlignment = value.TextXAlignment,
		AnchorPoint = value.AnchorPoint,
		Position = value.Position + UDim2.fromOffset(VALUE_SHADOW, VALUE_SHADOW),
		Size = value.Size,
		ZIndex = value.ZIndex - 1,
		Parent = value.Parent,
	})
	value:GetPropertyChangedSignal("Text"):Connect(function()
		shadow.Text = value.Text
	end)
end

-- Cette méthode permet de créer une ligne vide (nom à gauche, filet en bas) sous les lignes existantes d'une catégorie
-- lorsqu'un réglage y est ajouté ; renvoie la ligne et son nom.
local function makeRow(category: Category, name: string): (Frame, TextLabel)
	local index = #category.list
	local row = UIKit.frame({
		Name = name,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, index * ROW_HEIGHT),
		Size = UDim2.fromOffset(ROW_WIDTH, ROW_HEIGHT),
		Parent = category.rows,
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
	local label = UIKit.text({
		Name = "Name",
		Text = name,
		FontFace = F.DisplayMedium,
		TextSize = 19,
		TextColor3 = C.Bone,
		Size = UDim2.new(0, NAME_WIDTH, 1, 0),
		Parent = row,
	})
	return row, label
end

-- Cette méthode permet d'ajouter un réglage à curseur (trace, poignée en impact, valeur éditable) à une catégorie lorsque
-- l'écran est construit : un tir place la valeur, puis la poignée se glisse sans retirer.
local function addSlider(
	category: Category,
	name: string,
	minVal: number,
	maxVal: number,
	default: number,
	decimals: number,
	onChange: (number) -> ()
)
	local fmt = "%." .. decimals .. "f"
	local currentVal = default
	local row, label = makeRow(category, name)

	local valBox = UIKit.create("TextBox", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(VALUE_WIDTH, 36),
		BackgroundTransparency = 1,
		FontFace = F.Display,
		TextSize = VALUE_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		ClearTextOnFocus = false,
		Text = string.format(fmt, default),
		ZIndex = 2,
		Parent = row,
	})
	shadowValue(valBox)
	local valLine = UIKit.frame({
		Name = "Underline",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 1,
		Parent = valBox,
	})
	valBox.Focused:Connect(function()
		UIKit.tween(valLine, Motion.Hover, { BackgroundTransparency = 0 })
	end)

	-- Trace entre le nom et la valeur : zone cliquable haute contenant le trait, la traînée ambrée et l'impact
	local hit = UIKit.button({
		Name = "Track",
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, NAME_WIDTH + 10, 0.5, 0),
		Size = UDim2.new(1, -(NAME_WIDTH + 10 + VALUE_WIDTH + 16), 0, 34),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local track = UIKit.frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.65,
		Parent = hit,
	})
	local fill = UIKit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = track })
	local handle = UIKit.frame({
		Name = "Impact",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.Black,
		ZIndex = 2,
		Parent = track,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })
	local handleStroke = UIKit.stroke(handle, C.Bone, 2)
	local handleScale = UIKit.create("UIScale", { Parent = handle })
	UIKit.hover(hit, handleScale, { Scale = 1 }, { Scale = 1.25 })
	UIKit.hover(hit, handleStroke, { Color = C.Bone }, { Color = C.HitRed })
	UIKit.hover(hit, label, { TextColor3 = C.Bone }, { TextColor3 = C.HitRed })
	hit.MouseEnter:Connect(function()
		MenuCursor.addHover(1)
	end)
	hit.MouseLeave:Connect(function()
		MenuCursor.addHover(-1)
	end)

	local function applyValue(v: number)
		v = math.clamp(v, minVal, maxVal)
		currentVal = v
		local t = (v - minVal) / (maxVal - minVal)
		fill.Size = UDim2.fromScale(t, 1)
		handle.Position = UDim2.fromScale(t, 0.5)
		valBox.Text = string.format(fmt, v)
		onChange(v)
	end

	valBox.FocusLost:Connect(function()
		UIKit.tween(valLine, Motion.Hover, { BackgroundTransparency = 1 })
		local num = tonumber(valBox.Text)
		if num then
			applyValue(num)
		else
			valBox.Text = string.format(fmt, currentVal)
		end
	end)

	local function valueFromMouse(inputPos: Vector3): number
		local absPos = track.AbsolutePosition
		local absSize = track.AbsoluteSize
		local t = math.clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		return minVal + (maxVal - minVal) * t
	end

	local dragging = false
	hit.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			applyValue(valueFromMouse(inp.Position))
			if shoots() then
				MenuShot.fireAt(hit, inp, false)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
			applyValue(valueFromMouse(inp.Position))
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	applyValue(default)
	table.insert(category.list, {
		reset = function()
			applyValue(default)
		end,
	})
end

-- Cette méthode permet d'ajouter un réglage à choix fermé (« ‹ VALEUR › », flèches à tirer, en boucle) à une catégorie
-- lorsque l'écran est construit ; `options` donne les libellés et valeurs, `initial` l'indice de départ.
local function addPicker(
	category: Category,
	name: string,
	options: { { label: string, value: any } },
	initial: number,
	default: number,
	onChange: (any) -> ()
)
	local current = initial
	local row = makeRow(category, name)
	local picker = UIKit.frame({
		Name = "Picker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		Parent = row,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = picker,
	})
	local holder = UIKit.frame({
		Name = "ValueHolder",
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(PICK_WIDTH, 36),
		Parent = picker,
	})
	local value = UIKit.text({
		Name = "Value",
		FontFace = F.Display,
		TextSize = 20,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
	})
	shadowValue(value)

	local function apply(index: number)
		current = (index - 1) % #options + 1
		value.Text = options[current].label
		onChange(options[current].value)
	end

	assert(page, "SettingsMenu : la page doit exister avant ses lignes")
	for _, arrow in { { text = "‹", step = -1, order = 1 }, { text = "›", step = 1, order = 3 } } do
		local choice = page.choice({
			text = arrow.text,
			size = 22,
			layoutOrder = arrow.order,
			parent = picker,
			shoots = shoots,
			action = function()
				apply(current + arrow.step)
			end,
		})
		UIKit.padding(choice.button :: any, 0, 8, 2, 8)
	end

	apply(initial)
	table.insert(category.list, {
		reset = function()
			apply(default)
		end,
	})
end

-- Cette méthode permet d'afficher les lignes de la catégorie choisie et de marquer son onglet (os vif, barre ambrée)
-- lorsque le joueur tire sur une catégorie ou rouvre l'écran.
local function selectCategory(index: number)
	selected = index
	for i, category in categories do
		local on = i == index
		category.rows.Visible = on
		categoryTabs[i].setSelected(on)
		categoryBars[i].Visible = on
	end
end

-- Cette méthode permet de créer une catégorie (onglet à gauche, conteneur de lignes à droite) lorsque l'écran est construit.
local function addCategory(block: Frame, title: string): Category
	assert(page, "SettingsMenu : la page doit exister avant ses catégories")
	local index = #categories + 1
	local rows = UIKit.frame({
		Name = title,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(ROWS_X, ROWS_TOP),
		Size = UDim2.new(0, ROW_WIDTH, 1, -ROWS_TOP),
		Visible = false,
		Parent = block,
	})
	local category: Category = { title = title, rows = rows, list = {} }
	categories[index] = category
	local tab = page.choice({
		text = title,
		size = CAT_SIZE,
		position = UDim2.fromOffset(0, CATS_TOP + (index - 1) * CAT_STEP),
		parent = block,
		shoots = shoots,
		action = function()
			selectCategory(index)
		end,
	})
	categoryTabs[index] = tab
	categoryBars[index] = UIKit.frame({
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -15, 0.5, 0),
		Size = UDim2.new(0, 3, 0.7, 0),
		BackgroundColor3 = C.Accent,
		Visible = false,
		Parent = tab.button,
	})
	return category
end

-- Cette méthode permet de construire les catégories et leurs réglages lorsque l'écran est initialisé ; une catégorie
-- sans réglage n'est pas créée (TOUCHES viendra avec #100).
local function buildCategories(block: Frame)
	local mouse = addCategory(block, "SOURIS")
	addSlider(mouse, "Sensibilité", 0.1, 5.0, CameraConfig.DEFAULT_SENS, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setSensitivity(v)
		end
	end)
	addSlider(mouse, "Sensibilité à la lunette", 0.1, 1.0, CameraConfig.SCOPE_SENS_MULT, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setScopeMultiplier(v)
		end
	end)

	local graphics = addCategory(block, "GRAPHISMES")
	-- Ombres du soleil sur ce poste seulement (#88) : la passe d'ombres est le plus gros coût GPU de la map ;
	-- par défaut, l'état de la place
	local shadowOptions = { { label = "ACTIVÉES", value = true }, { label = "COUPÉES", value = false } }
	local shadowDefault = if Lighting.GlobalShadows then 1 else 2
	addPicker(graphics, "Ombres", shadowOptions, shadowDefault, shadowDefault, function(v)
		Lighting.GlobalShadows = v
	end)
end

-- Cette méthode permet de remettre aux valeurs par défaut les réglages de la catégorie affichée lorsque le joueur tire
-- sur RÉTABLIR.
local function resetCategory()
	for _, row in categories[selected].list do
		row.reset()
	end
end

-- Cette méthode permet d'ouvrir ou fermer l'écran en sauvegardant puis restaurant l'état de la souris
-- lorsque le joueur appuie sur P, tire sur RÉGLAGES ou ferme l'écran.
local function setOpen(state: boolean)
	if not page or state == open then
		return
	end
	open = state
	if state then
		savedMouseBehavior = UserInputService.MouseBehavior
		savedMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		backdrop.Visible = mode == "modal"
		if mode == "modal" then
			backdrop.BackgroundTransparency = 1
			UIKit.tween(backdrop, Motion.Enter, { BackgroundTransparency = BACKDROP_TRANSPARENCY })
		end
		page.show(mode == "modal")
		selectCategory(selected)
	else
		page.hide()
		UserInputService.MouseBehavior = savedMouseBehavior
		UserInputService.MouseIconEnabled = savedMouseIcon
		if onClosedCallback then
			onClosedCallback()
		end
	end
end

-- Cette méthode permet de poser RÉTABLIR et RETOUR côte à côte en bas au centre lorsque l'écran est construit.
local function buildActions(built: MenuPage.Page)
	local actions = UIKit.frame({
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, MenuPage.ExitY),
		Size = UDim2.fromOffset(BLOCK_WIDTH, 44),
		Parent = built.group,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ACTION_GAP),
		Parent = actions,
	})
	built.choice({
		text = "RÉTABLIR",
		size = ACTION_SIZE,
		layoutOrder = 1,
		parent = actions,
		shoots = shoots,
		action = resetCategory,
	})
	local back = built.choice({
		text = "RETOUR",
		size = ACTION_SIZE,
		layoutOrder = 2,
		parent = actions,
		shoots = shoots,
		action = function()
			setOpen(false)
		end,
	})
	back.setSelected(true)
end

-- Cette méthode permet de construire l'écran et de brancher la touche P et Échap lorsque le client démarre.
function SettingsMenu.init(fpsCam: typeof(fpsCamRef))
	if page then
		return
	end
	fpsCamRef = fpsCam

	local built = MenuPage.new("SettingsMenu", 3, "RÉGLAGES")
	page = built

	-- Le voile retient les clics pour qu'ils ne partent pas en tirs dans la partie
	backdrop = UIKit.frame({
		Name = "Backdrop",
		Active = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = BACKDROP_TRANSPARENCY,
		ZIndex = -1,
		Visible = false,
		Parent = built.gui,
	})

	local block = UIKit.frame({
		Name = "Block",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, BLOCK_WIDTH, 1, 0),
		Parent = built.group,
	})
	buildCategories(block)
	buildActions(built)
	selectCategory(1)

	UserInputService.InputBegan:Connect(function(inp, gameProcessed)
		-- Échap ferme l'écran, même si Roblox traite aussi la touche (menu système)
		if inp.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
			return
		end
		if gameProcessed or inp.KeyCode ~= Enum.KeyCode.P then
			return
		end
		if open then
			setOpen(false)
		elseif not (pageRequest and pageRequest()) then
			mode = "modal"
			setOpen(true)
		end
	end)
	-- Échap ouvre le menu Roblox, qui peut capturer la touche avant nous : on ferme aussi à son ouverture
	GuiService.MenuOpened:Connect(function()
		setOpen(false)
	end)
end

-- Cette méthode permet d'enregistrer une action à exécuter à chaque fermeture de l'écran
-- lorsque le menu doit revenir à l'accueil.
function SettingsMenu.setOnClosed(callback: () -> ())
	onClosedCallback = callback
end

-- Cette méthode permet de laisser le menu traiter la touche P lorsqu'il est affiché ; le rappel renvoie true s'il s'en charge.
function SettingsMenu.setPageRequest(callback: () -> boolean)
	pageRequest = callback
end

-- Cette méthode permet d'ouvrir l'écran dans une présentation donnée lorsque le joueur tire sur RÉGLAGES.
function SettingsMenu.open(newMode: Mode)
	mode = newMode
	setOpen(true)
end

-- Cette méthode permet de fermer l'écran s'il est ouvert lorsque le joueur quitte la page ou lance une partie.
function SettingsMenu.close()
	setOpen(false)
end

-- Cette méthode permet de savoir si l'écran est ouvert lorsqu'un module doit s'y adapter.
function SettingsMenu.isOpen(): boolean
	return open
end

return SettingsMenu

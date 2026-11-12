-- Réglages (direction « Ligne de mire », disposition C de #117) : bloc centré sur un voile, catégories à gauche,
-- lignes de réglages à droite (nom, contrôle, valeur), RÉTABLIR et RETOUR en bas au centre. Deux présentations du même
-- écran : « page » à même la scène du menu principal et « modal » avec son titre, ouverte depuis le menu en partie
-- (InGameMenu, #157, qui pose le voile sombre, libère la souris et route les touches), toutes deux à la souris système
-- (#130). Pour ajouter un réglage : une entrée dans `buildCategories`, et un champ dans PlayerSettings s'il doit être
-- conservé entre les sessions (LocalSettings, #100).
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local LocalInventory = require(script.Parent.Parent.systems.inventory.LocalInventory)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local Crosshair = require(script.Parent.Crosshair)
local HUDRules = require(script.Parent.HUDRules)
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
local KEY_HINT_TIME = 1.5 -- s d'affichage du refus d'une touche (« RÉSERVÉE AU JEU »)
-- Aperçu du viseur (#251), sous les catégories : deux cases, fond clair et fond sombre, viseur à sa vraie taille en px
local PREVIEW_TOP = 230 -- px sous le haut des lignes
local PREVIEW_SIZE = 100 -- 75 px à l'échelle minimale (0,75) : le plus grand viseur (36 px du centre) y tient
local PREVIEW_GAP = 6
local PREVIEW_LIGHT = Color3.fromRGB(222, 214, 200) -- sable clair, comme un ciel ou une rampe éclairée
local PREVIEW_DARK = Color3.fromRGB(28, 30, 34) -- mur ou sol dans l'ombre

-- `sync` reporte sur la ligne les réglages sauvegardés, une fois arrivés du serveur
type Row = { reset: () -> (), sync: (PlayerSettings.Settings) -> () }
type Category = { title: string, rows: Frame, list: { Row }, rowCount: number }
-- Saisie d'une touche en cours : emplacement, choix affiché, rappel qui remet la ligne au repos
type Capture = { slot: number, finish: () -> () }

local page: MenuPage.Page?
local open = false
local mode: Mode = "modal"
local onClosedCallback: (() -> ())?
-- Rappel de fermeture propre à l'ouverture en cours (retour au menu en partie), oublié une fois appelé
local onceClosed: (() -> ())?
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
-- Vrai pendant la construction et le report des réglages chargés : les lignes appliquent leur valeur sans la renvoyer
-- comme un choix du joueur (LocalSettings garderait sinon les valeurs par défaut à la place des réglages sauvegardés)
local syncing = false
local capture: Capture?
-- Cadre mis à l'échelle de l'écran (UIKit.scaledRoot) : l'aperçu du viseur annule son échelle
local scaledRoot: Frame?
local keyHandlers: { [number]: (Enum.KeyCode) -> () } = {}

-- Cette méthode permet d'enregistrer un réglage choisi par le joueur lorsqu'une ligne change de valeur, sauf pendant
-- la construction de l'écran ou le report des réglages chargés.
local function store(field: string, value: any)
	if not syncing then
		LocalSettings.update({ [field] = value })
	end
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
	local index = category.rowCount
	category.rowCount += 1
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
		TextSize = 22,
		TextColor3 = C.Bone,
		Size = UDim2.new(0, NAME_WIDTH, 1, 0),
		Parent = row,
	})
	return row, label
end

-- Cette méthode permet d'ajouter un réglage à curseur (trace, poignée en impact, valeur éditable) à une catégorie lorsque
-- l'écran est construit : un clic place la valeur, puis la poignée se glisse ; `field` est le champ de
-- PlayerSettings où la valeur est conservée ; `snap` garde la valeur à la précision affichée.
local function addSlider(
	category: Category,
	name: string,
	field: string,
	minVal: number,
	maxVal: number,
	default: number,
	decimals: number,
	onChange: (number) -> (),
	snap: boolean?
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
		Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.Bone,
		ZIndex = 2,
		Parent = track,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })
	UIKit.stroke(handle, C.Black, 1.5)
	local handleScale = UIKit.create("UIScale", { Parent = handle })
	UIKit.hover(hit, handleScale, { Scale = 1 }, { Scale = 1.25 })
	UIKit.hover(hit, handle, { BackgroundColor3 = C.Bone }, { BackgroundColor3 = C.HitRed })
	UIKit.hover(hit, label, { TextColor3 = C.Bone }, { TextColor3 = C.HitRed })

	local function applyValue(v: number)
		-- `snap` (viseur) : valeur gardée à la précision affichée ; les sensibilités gardent la leur (valeurs sauvegardées)
		if snap then
			v = math.round(v * 10 ^ decimals) / 10 ^ decimals
		end
		v = math.clamp(v, minVal, maxVal)
		currentVal = v
		local t = (v - minVal) / (maxVal - minVal)
		fill.Size = UDim2.fromScale(t, 1)
		handle.Position = UDim2.fromScale(t, 0.5)
		valBox.Text = string.format(fmt, v)
		onChange(v)
		store(field, v)
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
		sync = function(settings)
			applyValue((settings :: any)[field])
		end,
	})
end

-- Cette méthode permet d'ajouter un réglage à choix fermé (« ‹ VALEUR › », flèches à cliquer, en boucle) à une catégorie
-- lorsque l'écran est construit ; `options` (libellé, valeur, couleur en option), `field` (champ de PlayerSettings),
-- `width` (PICK_WIDTH par défaut) ; `keepOnReset` : RÉTABLIR ne touche pas à cette ligne.
local function addPicker(
	category: Category,
	name: string,
	field: string,
	options: { { label: string, value: any, color: Color3? } },
	initial: number,
	default: number,
	onChange: (any) -> (),
	width: number?,
	keepOnReset: boolean?
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
		Size = UDim2.fromOffset(width or PICK_WIDTH, 36),
		Parent = picker,
	})
	local value = UIKit.text({
		Name = "Value",
		FontFace = F.Display,
		TextSize = 22,
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
		value.TextColor3 = options[current].color or C.Bone
		onChange(options[current].value)
		store(field, options[current].value)
	end

	assert(page, "SettingsMenu : la page doit exister avant ses lignes")
	for _, arrow in { { text = "‹", step = -1, order = 1 }, { text = "›", step = 1, order = 3 } } do
		local choice = page.choice({
			text = arrow.text,
			size = 22,
			layoutOrder = arrow.order,
			parent = picker,
			action = function()
				apply(current + arrow.step)
			end,
		})
		UIKit.padding(choice.button :: any, 0, 8, 2, 8)
	end

	apply(initial)
	table.insert(category.list, {
		reset = function()
			if not keepOnReset then
				apply(default)
			end
		end,
		-- Un champ resté à nil (ombres jamais choisies) garde la valeur affichée
		sync = function(settings)
			for i, option in options do
				if option.value == (settings :: any)[field] then
					apply(i)
				end
			end
		end,
	})
end

-- Cette méthode permet de remplacer le texte d'un choix et de son ombre lorsque la touche affichée change.
local function setChoiceText(choice: MenuShot.Choice, text: string)
	for _, child in choice.button:GetChildren() do
		if child:IsA("TextLabel") then
			child.Text = text
		end
	end
end

-- Cette méthode permet de terminer la saisie de touche en cours (la ligne revient à sa touche) lorsque le joueur a
-- choisi, annule, clique ailleurs ou ferme l'écran.
local function endCapture()
	local active = capture
	capture = nil
	if active then
		active.finish()
	end
end

-- Cette méthode permet de nommer la ligne d'un emplacement de la barre (« Arme 1 · AWP ») lorsqu'elle est créée ou que
-- l'inventaire change.
local function keyRowName(slot: number, weaponLabel: string): string
	return string.format("Arme %d · %s", slot, weaponLabel)
end

-- Cette méthode permet d'ajouter la ligne d'un emplacement de la barre d'armes (nom de l'arme, touche à cliquer) lorsque
-- l'écran est construit : un clic sur la touche attend la suivante, Échap annule, une touche du jeu est refusée.
local function addKeyBinding(category: Category, slot: number, weaponLabel: string): (() -> (), Frame, TextLabel)
	assert(page, "SettingsMenu : la page doit exister avant ses lignes")
	local row, label = makeRow(category, keyRowName(slot, weaponLabel))
	local choice: MenuShot.Choice
	local hint = UIKit.text({
		Name = "Hint",
		Text = "",
		FontFace = F.DisplayMedium,
		TextSize = 17,
		TextColor3 = C.HitRed,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(VALUE_WIDTH + 50), 0.5, 0),
		Size = UDim2.fromOffset(180, 24),
		Parent = row,
	})
	local hintToken = 0

	local function refresh()
		if not (capture and capture.slot == slot) then
			setChoiceText(choice, LocalSettings.keyText(LocalSettings.get().slotKeys[slot]))
		end
	end

	choice = page.choice({
		text = LocalSettings.keyText(LocalSettings.get().slotKeys[slot]),
		size = VALUE_SIZE,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.fromScale(1, 0.5),
		parent = row,
		action = function()
			endCapture()
			capture = {
				slot = slot,
				finish = function()
					hint.Text = ""
					choice.setSelected(false)
					refresh()
				end,
			}
			choice.setSelected(true)
			setChoiceText(choice, "APPUIE…")
		end,
	})

	-- Cette méthode permet de traiter la touche pressée pendant la saisie de cet emplacement : touche acceptée (échange
	-- éventuel avec un autre emplacement), ou refus affiché un instant en gardant la saisie ouverte.
	local function onKey(keyCode: Enum.KeyCode)
		local keys, reason = PlayerSettings.assignKey(LocalSettings.get().slotKeys, slot, keyCode.Name)
		if keys then
			endCapture()
			LocalSettings.update({ slotKeys = keys })
			return
		end
		hintToken += 1
		local token = hintToken
		hint.Text = if reason == "reserved" then "RÉSERVÉE AU JEU" else "TOUCHE NON PROPOSÉE"
		task.delay(KEY_HINT_TIME, function()
			if token == hintToken then
				hint.Text = ""
			end
		end)
	end

	table.insert(category.list, {
		-- Toutes les touches ensemble : remettre un seul emplacement pourrait laisser un doublon après des échanges
		reset = function()
			endCapture()
			LocalSettings.update({ slotKeys = table.clone(PlayerSettings.DEFAULT_SLOT_KEYS) })
		end,
		sync = function() end, -- suivi par LocalSettings.onChanged (refresh)
	})
	keyHandlers[slot] = onKey
	return refresh, row, label
end

-- Cette méthode permet d'afficher les lignes de la catégorie choisie et de marquer son onglet (os vif, barre ambrée)
-- lorsque le joueur clique sur une catégorie ou rouvre l'écran.
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
	local category: Category = { title = title, rows = rows, list = {}, rowCount = 0 }
	categories[index] = category
	local tab = page.choice({
		text = title,
		size = CAT_SIZE,
		position = UDim2.fromOffset(0, CATS_TOP + (index - 1) * CAT_STEP),
		parent = block,
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

-- Cette méthode permet de lister les noms des armes possédées (#267) dans l'ordre des emplacements de la barre lorsque
-- la catégorie TOUCHES est construite ou que l'inventaire change (MAX_ROWS au plus).
local function weaponNames(): { string }
	local ordered = HUDRules.slotOrder(LocalInventory.ownedTools())
	return table.move(ordered, 1, math.min(#ordered, PlayerSettings.MAX_ROWS), 1, {})
end

-- Cette méthode permet de construire la catégorie TOUCHES (molette, puis une touche par arme) lorsque l'écran est
-- initialisé ; les lignes de touches suivent chaque changement (échange entre deux emplacements, chargement, RÉTABLIR).
local function buildKeysCategory(block: Frame)
	local keys = addCategory(block, "TOUCHES")
	-- Une ligne par action, la valeur est le geste : les deux lignes portent le même réglage (`wheel`) vu de chaque
	-- côté, et suivent l'une l'autre (HAUT sur l'une met BAS sur l'autre, AUCUNE coupe la molette)
	local wheelRows = {
		{
			name = "Arme suivante",
			options = {
				{ label = "MOLETTE BAS", value = "previous" },
				{ label = "MOLETTE HAUT", value = "next" },
				{ label = "AUCUNE", value = "off" },
			},
		},
		{
			name = "Arme précédente",
			options = {
				{ label = "MOLETTE HAUT", value = "previous" },
				{ label = "MOLETTE BAS", value = "next" },
				{ label = "AUCUNE", value = "off" },
			},
		},
	}
	local wheelSyncs = {}
	for _, wheelRow in wheelRows do
		local default = 1
		for i, option in wheelRow.options do
			if option.value == PlayerSettings.DEFAULT_WHEEL then
				default = i
			end
		end
		addPicker(keys, wheelRow.name, "wheel", wheelRow.options, default, default, function() end, 150)
		table.insert(wheelSyncs, keys.list[#keys.list].sync)
	end
	LocalSettings.onChanged(function(settings)
		local wasSyncing = syncing
		syncing = true
		for _, sync in wheelSyncs do
			sync(settings)
		end
		syncing = wasSyncing
	end)
	-- Une ligne par emplacement possible (une par arme du catalogue, MAX_ROWS au plus), nommée d'après l'arme possédée à
	-- ce rang et masquée au-delà : l'inventaire peut arriver ou changer après la construction (#267)
	local refreshers = {}
	local slotRows: { { row: Frame, label: TextLabel } } = {}
	for slot = 1, math.min(#InventoryRules.catalogTools(), PlayerSettings.MAX_ROWS) do
		local refresh, row, label = addKeyBinding(keys, slot, "")
		table.insert(refreshers, refresh)
		table.insert(slotRows, { row = row, label = label })
	end
	-- Cette méthode permet de nommer chaque ligne d'après l'arme possédée à son rang lorsque l'inventaire change ; une
	-- saisie de touche ouverte sur une ligne masquée est annulée.
	local function relabel()
		local names = weaponNames()
		for slot, entry in slotRows do
			local name = names[slot]
			entry.row.Visible = name ~= nil
			if not name and capture and capture.slot == slot then
				endCapture()
			end
			entry.label.Text = keyRowName(slot, if name then HUDRules.weaponLabel(name) else "")
		end
	end
	relabel()
	LocalInventory.onChanged(relabel)
	LocalSettings.onChanged(function()
		for _, refresh in refreshers do
			refresh()
		end
	end)
end

-- Cette méthode permet de construire l'aperçu du viseur (une case claire, une case sombre) sous les catégories lorsque la
-- catégorie VISEUR est construite ; le viseur y est à sa taille réelle en px malgré la mise à l'échelle de l'écran.
local function buildCrosshairPreview(category: Category)
	local preview = UIKit.frame({
		Name = "Preview",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-ROWS_X, PREVIEW_TOP),
		Size = UDim2.fromOffset(PREVIEW_SIZE * 2 + PREVIEW_GAP, PREVIEW_SIZE + 26),
		Parent = category.rows,
	})
	UIKit.text({
		Name = "Label",
		Text = "APERÇU",
		FontFace = F.DisplayMedium,
		TextSize = 16,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = preview,
	})
	-- Mise à l'échelle de l'écran (UIKit.scaledRoot, attribut Scale) compensée : le viseur garde ses px comme en jeu
	local root = scaledRoot
	local redraws: { (PlayerSettings.Settings) -> () } = {}
	for i, background in { PREVIEW_LIGHT, PREVIEW_DARK } do
		local pane = UIKit.frame({
			Name = if i == 1 then "Light" else "Dark",
			Position = UDim2.fromOffset((i - 1) * (PREVIEW_SIZE + PREVIEW_GAP), 26),
			Size = UDim2.fromOffset(PREVIEW_SIZE, PREVIEW_SIZE),
			BackgroundColor3 = background,
			ClipsDescendants = true,
			Parent = preview,
		})
		local unscaled = UIKit.frame({
			Name = "Unscaled",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			Parent = pane,
		})
		local scale = UIKit.create("UIScale", { Parent = unscaled })
		-- Cette méthode permet d'annuler l'échelle de l'écran sur le viseur de l'aperçu lorsque la résolution change.
		local function unscale()
			local s = root and root:GetAttribute("Scale")
			scale.Scale = if type(s) == "number" and s > 0 then 1 / s else 1
		end
		unscale()
		if root then
			root:GetAttributeChangedSignal("Scale"):Connect(unscale)
		end
		redraws[i] = Crosshair.mount(unscaled)
	end

	-- Cette méthode permet de redessiner l'aperçu lorsque le style du viseur change (curseur glissé, choix, chargement).
	local function redraw(settings: PlayerSettings.Settings)
		for _, redrawPane in redraws do
			redrawPane(settings)
		end
	end
	redraw(LocalSettings.get())
	LocalSettings.onChanged(redraw)
end

-- Cette méthode permet de construire la catégorie VISEUR (#251 : visée simplifiée, puis style du crosshair et son
-- aperçu) lorsque l'écran est initialisé ; RÉTABLIR y remet le style d'origine sans couper la visée simplifiée.
local function buildCrosshairCategory(block: Frame)
	local crosshair = addCategory(block, "VISEUR")
	local defaults = PlayerSettings.CROSSHAIR
	-- Visée simplifiée (#195) : affiche le crosshair, coupée par défaut ; Crosshair suit LocalSettings
	local aimOptions = { { label = "ACTIVÉE", value = true }, { label = "COUPÉE", value = false } }
	addPicker(crosshair, "Visée simplifiée", "simpleAim", aimOptions, 2, 2, function() end, nil, true)

	local colorOptions = {}
	local colorDefault = 1
	for i, entry in UITheme.CrosshairPalette do
		colorOptions[i] = { label = entry.label, value = entry.id, color = entry.color }
		if entry.id == defaults.color then
			colorDefault = i
		end
	end
	addPicker(crosshair, "Couleur", "crosshairColor", colorOptions, colorDefault, colorDefault, function() end)
	for _, size in
		{
			{ name = "Longueur", field = "crosshairLength", range = defaults.length },
			{ name = "Épaisseur", field = "crosshairThickness", range = defaults.thickness },
			{ name = "Écart central", field = "crosshairGap", range = defaults.gap },
		}
	do
		local range = size.range
		addSlider(crosshair, size.name, size.field, range.min, range.max, range.default, 0, function() end, true)
	end
	local showOptions = { { label = "AFFICHÉ", value = true }, { label = "MASQUÉ", value = false } }
	local dotDefault = if defaults.dot then 1 else 2
	addPicker(crosshair, "Point central", "crosshairDot", showOptions, dotDefault, dotDefault, function() end)
	local outlineDefault = if defaults.outline then 1 else 2
	addPicker(crosshair, "Contour", "crosshairOutline", showOptions, outlineDefault, outlineDefault, function() end)
	local opacity = defaults.opacity
	addSlider(
		crosshair,
		"Opacité",
		"crosshairOpacity",
		opacity.min,
		opacity.max,
		opacity.default,
		2,
		function() end,
		true
	)

	buildCrosshairPreview(crosshair)
end

-- Cette méthode permet de construire les catégories et leurs réglages lorsque l'écran est initialisé ; une catégorie
-- sans réglage n'est pas créée.
local function buildCategories(block: Frame)
	local mouse = addCategory(block, "SOURIS")
	addSlider(
		mouse,
		"Sensibilité",
		"sensitivity",
		CameraConfig.SENS_MIN,
		CameraConfig.SENS_MAX,
		CameraConfig.DEFAULT_SENS,
		2,
		function(v)
			if fpsCamRef then
				fpsCamRef.setSensitivity(v)
			end
		end
	)
	-- Multiplicateur appliqué en plus du ratio du zoom (#115) : 1.00 = même vitesse à l'écran qu'au hip-fire
	local scopeMin, scopeMax = CameraConfig.SCOPE_SENS_MIN, CameraConfig.SCOPE_SENS_MAX
	local scopeDefault = CameraConfig.SCOPE_SENS_MULT
	addSlider(mouse, "Multiplicateur lunette", "scopeMultiplier", scopeMin, scopeMax, scopeDefault, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setScopeMultiplier(v)
		end
	end)

	-- Auto-bhop (#255) : saut automatique tant qu'Espace est maintenu, activé par défaut ; BhopSystem suit LocalSettings
	local bhopOptions = { { label = "ACTIVÉ", value = true }, { label = "COUPÉ", value = false } }
	local movement = addCategory(block, "MOUVEMENT")
	local bhopDefault = if PlayerSettings.DEFAULT_AUTO_BHOP then 1 else 2
	addPicker(movement, "Auto-bhop", "autoBhop", bhopOptions, bhopDefault, bhopDefault, function() end, 150)

	buildKeysCategory(block)

	local graphics = addCategory(block, "GRAPHISMES")
	-- Ombres du soleil sur ce poste seulement (#88) : la passe d'ombres est le plus gros coût GPU de la map ;
	-- par défaut, l'état de la place
	local shadowOptions = { { label = "ACTIVÉES", value = true }, { label = "COUPÉES", value = false } }
	local shadowDefault = if Lighting.GlobalShadows then 1 else 2
	addPicker(graphics, "Ombres", "shadows", shadowOptions, shadowDefault, shadowDefault, function(v)
		Lighting.GlobalShadows = v
	end)
	-- Affichage des touches (#197) : désactivé par défaut ; KeyDisplay suit LocalSettings
	local keyDisplayOptions = {
		{ label = "DÉSACTIVÉ", value = "off" },
		{ label = "SIMPLE", value = "simple" },
		{ label = "COMPLET", value = "full" },
	}
	addPicker(graphics, "Affichage des touches", "keyDisplay", keyDisplayOptions, 1, 1, function() end, 150)

	buildCrosshairCategory(block)
end

-- Cette méthode permet de remettre aux valeurs par défaut les réglages de la catégorie affichée lorsque le joueur clique
-- sur RÉTABLIR.
local function resetCategory()
	for _, row in categories[selected].list do
		row.reset()
	end
end

-- Cette méthode permet d'ouvrir ou fermer l'écran lorsque le joueur clique sur RÉGLAGES, RETOUR, ou que le menu le
-- ferme ; à la fermeture, le rappel de l'ouverture en cours puis celui du menu principal sont prévenus.
local function setOpen(state: boolean)
	if not page or state == open then
		return
	end
	open = state
	if state then
		page.show(mode == "modal")
		selectCategory(selected)
	else
		endCapture()
		page.hide()
		local once = onceClosed
		onceClosed = nil
		if once then
			once()
		end
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
		action = resetCategory,
	})
	local back = built.choice({
		text = "RETOUR",
		size = ACTION_SIZE,
		layoutOrder = 2,
		parent = actions,
		action = function()
			setOpen(false)
		end,
	})
	back.setSelected(true)
end

-- Cette méthode permet de construire l'écran lorsque le client démarre (touches routées par InGameMenu).
function SettingsMenu.init(fpsCam: typeof(fpsCamRef))
	if page then
		return
	end
	fpsCamRef = fpsCam

	local built = MenuPage.new("SettingsMenu", 3, "RÉGLAGES")
	page = built
	scaledRoot = built.group.Parent :: Frame

	local block = UIKit.frame({
		Name = "Block",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, BLOCK_WIDTH, 1, 0),
		Parent = built.group,
	})
	syncing = true
	buildCategories(block)
	syncing = false
	buildActions(built)
	selectCategory(1)
	-- Réglages sauvegardés arrivés du serveur : chaque ligne les affiche et les applique (caméra, ombres)
	LocalSettings.onLoaded(function(settings)
		syncing = true
		for _, category in categories do
			for _, row in category.list do
				row.sync(settings)
			end
		end
		syncing = false
	end)
end

-- Cette méthode permet de donner à la saisie de touche en cours la priorité sur une entrée (InGameMenu l'appelle
-- d'abord) : la touche pressée va à l'emplacement, Échap ou un clic ailleurs annule ; renvoie true si l'entrée est prise.
function SettingsMenu.handleCaptureInput(inp: InputObject): boolean
	local active = capture
	if not active then
		return false
	end
	if inp.KeyCode == Enum.KeyCode.Escape then
		endCapture()
		return true
	elseif inp.UserInputType == Enum.UserInputType.Keyboard then
		keyHandlers[active.slot](inp.KeyCode)
		return true
	elseif inp.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Le clic annule la saisie et garde son effet (autre choix cliqué)
		endCapture()
	end
	return false
end

-- Cette méthode permet d'enregistrer une action à exécuter à chaque fermeture de l'écran
-- lorsque le menu doit revenir à l'accueil.
function SettingsMenu.setOnClosed(callback: () -> ())
	onClosedCallback = callback
end

-- Cette méthode permet d'ouvrir l'écran dans une présentation donnée lorsque le joueur clique sur RÉGLAGES ;
-- `onClosed` est appelé une fois, à la fermeture de cette ouverture (retour au menu en partie).
function SettingsMenu.open(newMode: Mode, onClosed: (() -> ())?)
	if open then
		return
	end
	mode = newMode
	onceClosed = onClosed
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

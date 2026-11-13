-- Écran d'équipement de l'onglet ARMES (#280, disposition revue en #308 d'après une capture de référence, docs/ui.md) :
-- tout tient à gauche, le personnage de l'accueil est à droite et tient l'arme montrée. De haut en bas : grand titre
-- « ÉQUIPEMENT » puis l'emplacement actif et son étiquette, rendu de l'arme montrée, son nom avec « ÉQUIPÉ », onglets
-- des emplacements, grille de cartes (armes possédées, puis skins de l'arme équipée). Survoler une carte la montre,
-- cliquer l'équipe (remote EquipItem, l'écran suit la réponse du serveur). Seuls les items possédés apparaissent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local PlayerSettings = require(Shared:WaitForChild("PlayerSettings"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local LocalInventory = require(script.Parent.Parent.systems.inventory.LocalInventory)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local Rules = require(script.Parent.Parent.systems.game.MenuSceneRules)
local HUDRules = require(script.Parent.HUDRules)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local EquipmentScreen = {}

-- Mise en page (px à 720 de haut)
local EDGE = 28
local TITLE_Y = 108 -- « ÉQUIPEMENT », sous le titre du jeu
local TITLE_SIZE = 52
local TITLE_STEP = 54 -- écart entre les deux lignes du titre
local NAME_Y = 236 -- nom de l'arme montrée et son étiquette
local NAME_SIZE = 26
local CATEGORY_Y = 272
local TABS_Y = 318
local TAB_SIZE = Vector2.new(118, 30)
local TAB_GAP = 6
local GRID_Y = 362
local COLUMNS = 4
local CARD_SIZE = Vector2.new(172, 92)
local CARD_GAP = 12
local CARD_ICON = Vector2.new(136, 40)
local SECTION_HEIGHT = 28 -- libellé « SKINS · ARME » entre les deux rangées
local SECTION_GAP = 20 -- écart entre la rangée des armes et ce libellé
local GRID_WIDTH = COLUMNS * CARD_SIZE.X + (COLUMNS - 1) * CARD_GAP
local PREVIEW_POSITION = Vector2.new(330, 76) -- rendu de l'arme montrée, à droite du titre
local PREVIEW_SIZE = Vector2.new(470, 210)
local SHOW_PREVIEW = true
local SLOT_LABELS = { sniper = "SNIPER", knife = "COUTEAU" }
local SCRIM_SIZE = Vector2.new(1100, 760) -- fond de coin sous la grille et le titre (décor clair possible)
local SCRIM_SHOWN = 0.2

type Hover = { tool: string, skin: string? }
-- Texte à largeur automatique doublé de son ombre, pour une ligne qui enchaîne texte et étiquette
type Flow = { set: (string) -> (), label: TextLabel }
type TabView = { button: TextButton, hovering: boolean }

local tabViews: { TabView } = {}
local grid: Frame
local previewHolder: Frame
local previews: { [string]: ViewportFrame } = {}
local slotTitle: Flow
local slotTag: TextLabel
local weaponName: Flow
local statusTag: TextLabel
local statusStroke: UIStroke
local category: TextLabel
local categoryShadow: TextLabel
local selectedSlot = 1 -- emplacement actif : sa grille est affichée, le personnage tient son arme
local hover: Hover? = nil -- carte survolée : arme (et skin) montrés tant que la souris reste dessus

-- Cette méthode permet de nommer un emplacement (« SNIPER », sinon son id en majuscules) lorsqu'il est affiché.
local function slotLabel(slotName: string): string
	return SLOT_LABELS[slotName] or string.upper(slotName)
end

-- Cette méthode permet de donner le nom affiché d'une arme (nom de WeaponConfig en majuscules, sinon nom du Tool
-- espacé) lorsqu'une carte ou la ligne de nom la nomme.
local function weaponTitle(toolName: string): string
	local cfg = WeaponConfig.Weapons[toolName]
	return if cfg and cfg.Name then string.upper(cfg.Name) else HUDRules.weaponLabel(toolName)
end

-- Cette méthode permet de donner le viewmodel d'une arme (attribut du Tool, sinon son nom) lorsqu'elle est dessinée.
local function viewmodelOf(toolName: string): string
	local folder = ReplicatedStorage:FindFirstChild("Tools")
	local tool = folder and folder:FindFirstChild(toolName)
	local viewmodel = tool and tool:GetAttribute("ViewmodelName")
	return if type(viewmodel) == "string" then viewmodel else toolName
end

-- Cette méthode permet de lire l'arme (fiche du catalogue) et le skin équipés d'un emplacement par son rang lorsque
-- l'écran les affiche.
local function equippedAt(index: number): (InventoryRules.Item?, string?)
	local loadout = LocalInventory.equipped()[InventoryRules.SLOTS[index]]
	if not loadout then
		return nil, nil
	end
	return InventoryRules.item(loadout.weapon), loadout.skin
end

-- Cette méthode permet de poser une ligne horizontale (texte puis étiquettes, alignés en bas) lorsque le titre ou le nom
-- de l'arme est construit.
local function flowRow(parent: GuiObject, name: string, y: number, height: number): Frame
	local row = UIKit.frame({
		Name = name,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, y),
		Size = UDim2.fromOffset(GRID_WIDTH, height),
		Parent = parent,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
		Parent = row,
	})
	return row
end

-- Cette méthode permet de poser dans une ligne un texte à ombre dont la largeur suit le contenu lorsqu'une étiquette
-- doit le suivre de près ; renvoie de quoi changer le texte (ombre comprise).
local function flowText(row: GuiObject, name: string, size: number, shadowOffset: number): Flow
	local box = UIKit.frame({
		Name = name,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = row,
	})
	local props = {
		FontFace = F.Display,
		TextSize = size,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
	}
	local shadowProps = table.clone(props)
	shadowProps.Name = "Shadow"
	shadowProps.TextColor3 = C.Black
	shadowProps.TextTransparency = 0.35
	shadowProps.Position = UDim2.fromOffset(shadowOffset, shadowOffset)
	shadowProps.Parent = box
	local shadow = UIKit.text(shadowProps)
	props.Name = "Text"
	props.TextColor3 = C.Bone
	props.ZIndex = 2
	props.Parent = box
	local label = UIKit.text(props)
	return {
		label = label,
		set = function(text: string)
			label.Text = text
			shadow.Text = text
		end,
	}
end

-- Cette méthode permet de poser une étiquette en boîte (texte court sur fond plein, largeur selon le texte) lorsqu'une
-- ligne précise un état ou une touche.
local function tag(row: GuiObject, name: string, order: number, background: Color3, color: Color3): TextLabel
	local label = UIKit.text({
		Name = name,
		FontFace = F.Display,
		TextSize = 14,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = background,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = order,
		Parent = row,
	})
	UIKit.padding(label, 0, 8, 0, 8)
	return label
end

-- Cette méthode permet de donner l'arme et le skin montrés (carte survolée, sinon équipement de l'emplacement actif) et
-- de dire s'ils sont équipés, lorsque la ligne de nom, le rendu ou le personnage se mettent à jour.
local function shown(): (string?, string?, boolean)
	local weapon, skin = equippedAt(selectedSlot)
	local equippedTool = weapon and weapon.tool
	if hover then
		return hover.tool, hover.skin, hover.tool == equippedTool and hover.skin == skin
	end
	return equippedTool, skin, equippedTool ~= nil
end

-- Cette méthode permet d'afficher le rendu texturé de l'arme montrée (un par viewmodel, gardé une fois construit)
-- lorsque l'arme montrée change.
local function showPreview(toolName: string?)
	if not SHOW_PREVIEW then
		return
	end
	local viewmodel = toolName and viewmodelOf(toolName)
	if viewmodel and not previews[viewmodel] then
		local viewport = UIKit.weaponSilhouette(previewHolder, viewmodel, PREVIEW_SIZE.X / PREVIEW_SIZE.Y, true)
		viewport.Name = "Preview" .. viewmodel
		previews[viewmodel] = viewport
	end
	for name, viewport in previews do
		viewport.Visible = name == viewmodel
	end
end

-- Cette méthode permet de mettre à jour le titre, la ligne de nom (« ÉQUIPÉ » plein en rouge d'impact, sinon « CLIC POUR
-- ÉQUIPER » en contour), le rendu et l'arme du personnage lorsque le survol, l'emplacement ou l'équipement change.
local function paintHeader()
	local slotName = InventoryRules.SLOTS[selectedSlot]
	slotTitle.set(if slotName then slotLabel(slotName) else "")
	slotTag.Text = string.format("EMPLACEMENT %d", selectedSlot)
	local tool, skin, isEquipped = shown()
	weaponName.set(if tool then string.format("%s  /  %s", weaponTitle(tool), Rules.skinLabel(skin)) else "")
	statusTag.Visible = tool ~= nil
	statusTag.Text = if isEquipped then "ÉQUIPÉ" else "CLIC POUR ÉQUIPER"
	statusTag.BackgroundTransparency = if isEquipped then 0 else 1
	statusStroke.Enabled = not isEquipped
	local cfg = tool and WeaponConfig.Weapons[tool]
	local text = if cfg and cfg.Category then string.upper(cfg.Category) else ""
	category.Text = text
	categoryShadow.Text = text
	showPreview(tool)
	if tool then
		MenuScene.holdTool(tool)
	end
end

-- Cette méthode permet de redessiner les onglets des emplacements (actif en boîte ambrée à texte sombre, autres en os,
-- survol en rouge d'impact) lorsque l'emplacement actif ou le survol change.
local function paintTabs()
	for index, view in tabViews do
		local active = selectedSlot == index
		view.button.BackgroundTransparency = if active then 0 else 1
		view.button.TextColor3 = if active then C.Ground elseif view.hovering then C.HitRed else C.Bone
	end
end

-- Cette méthode permet de poser une case vide barrée d'une croix lorsqu'une rangée de la grille compte moins de cartes
-- que de colonnes : elle garde la grille lisible sans montrer d'item non possédé.
local function emptyCard(x: number, y: number)
	local frame = UIKit.frame({
		Name = "Empty",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		Parent = grid,
	})
	UIKit.stroke(frame, C.Bone, 1).Transparency = 0.82
	UIKit.line(frame, 0, 0, CARD_SIZE.X, CARD_SIZE.Y, 1, C.Bone).BackgroundTransparency = 0.88
	UIKit.line(frame, 0, CARD_SIZE.Y, CARD_SIZE.X, 0, 1, C.Bone).BackgroundTransparency = 0.88
end

-- Cette méthode permet de poser une carte de la grille (silhouette, nom, coche et trait rouge d'impact sur l'équipée)
-- lorsque la grille se construit ; survoler la carte montre l'arme (titre, rendu, personnage), cliquer l'équipe.
local function card(x: number, y: number, text: string, item: Hover, equipped: boolean, action: () -> ())
	local button = UIKit.create("TextButton", {
		Name = "Card" .. text,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = if equipped then 0.12 else 0.3,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		Parent = grid,
	})
	local stroke = UIKit.stroke(button, C.Bone, 1)
	local restStroke = if equipped then 0.1 else 0.7
	stroke.Transparency = restStroke
	local icon = UIKit.frame({
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset((CARD_SIZE.X - CARD_ICON.X) / 2, 12),
		Size = UDim2.fromOffset(CARD_ICON.X, CARD_ICON.Y),
		Parent = button,
	})
	-- Skin pas encore rendu (#268) : la silhouette de l'arme, la même pour tous ses skins
	local silhouette = UIKit.weaponSilhouette(icon, viewmodelOf(item.tool), CARD_ICON.X / CARD_ICON.Y)
	local restColor = if equipped then C.Bone else C.TextSoft
	silhouette.ImageColor3 = restColor
	local label = UIKit.shadowedText(button, {
		Name = "Name",
		Text = text,
		FontFace = F.Display,
		TextSize = 16,
		TextColor3 = restColor,
		Position = UDim2.fromOffset(10, CARD_SIZE.Y - 28),
		Size = UDim2.fromOffset(CARD_SIZE.X - 20, 20),
		ZIndex = 2,
	}, 1)
	if equipped then
		UIKit.frame({
			Name = "Equipped",
			BackgroundColor3 = C.HitRed,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			Parent = button,
		})
		local check = UIKit.frame({
			Name = "Check",
			BackgroundColor3 = C.HitRed,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(20, 20),
			Parent = button,
		})
		UIKit.line(check, 5, 10, 9, 14, 2, C.Bone)
		UIKit.line(check, 9, 14, 15, 6, 2, C.Bone)
	end
	button.MouseEnter:Connect(function()
		hover = item
		stroke.Color = C.HitRed
		stroke.Transparency = 0
		UIKit.tween(label, Motion.Hover, { TextColor3 = C.HitRed })
		silhouette.ImageColor3 = C.Bone
		paintHeader()
	end)
	button.MouseLeave:Connect(function()
		stroke.Color = C.Bone
		stroke.Transparency = restStroke
		UIKit.tween(label, Motion.Hover, { TextColor3 = restColor })
		silhouette.ImageColor3 = restColor
		if hover == item then
			hover = nil
			paintHeader()
		end
	end)
	button.Activated:Connect(function()
		if not MenuShot.isBusy() then -- JOUER bloque les choix jusqu'au retour au menu
			action()
		end
	end)
end

-- Cette méthode permet de compléter une rangée par des cases vides jusqu'au nombre de colonnes lorsque la grille se
-- construit.
local function fillRow(count: number, y: number)
	for column = count % COLUMNS, COLUMNS - 1 do
		if count > 0 and column == 0 then
			break -- rangée déjà pleine
		end
		emptyCard(column * (CARD_SIZE.X + CARD_GAP), y)
	end
end

-- Cette méthode permet de reconstruire la grille (armes possédées de l'emplacement actif, puis skins possédés de son
-- arme équipée) lorsque l'emplacement actif ou l'équipement change.
local function rebuildGrid()
	for _, child in grid:GetChildren() do
		child:Destroy()
	end
	hover = nil -- les cartes survolées disparaissent
	local slotName = InventoryRules.SLOTS[selectedSlot]
	if not slotName then
		return
	end
	local owned = LocalInventory.owned()
	local current, currentSkin = equippedAt(selectedSlot)
	local weapons = InventoryRules.weaponsForSlot(owned, slotName)
	local step = CARD_SIZE.X + CARD_GAP
	local y = 0
	for i, weapon in weapons do
		local tool = weapon.tool or ""
		local isEquipped = current ~= nil and current.id == weapon.id
		local line = (i - 1) // COLUMNS
		y = line * (CARD_SIZE.Y + CARD_GAP)
		-- Recliquer l'arme équipée garde son skin ; une autre arme part avec son skin d'origine
		local skin = if isEquipped then currentSkin else nil
		card(((i - 1) % COLUMNS) * step, y, weaponTitle(tool), { tool = tool, skin = skin }, isEquipped, function()
			LocalInventory.equip(slotName, weapon.id, skin)
		end)
	end
	fillRow(#weapons, y)
	if not (current and current.tool) then
		return
	end
	local currentTool: string = current.tool
	local weaponId = current.id
	y += CARD_SIZE.Y + SECTION_GAP
	UIKit.accentLabel(grid, {
		Name = "SkinsTitle",
		Text = "SKINS  ·  " .. weaponTitle(currentTool),
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(GRID_WIDTH, 18),
	})
	y += SECTION_HEIGHT
	-- D'origine d'abord (id nil), puis les skins possédés de l'arme
	local skins: { { id: string? } } = { { id = nil } }
	for _, skin in InventoryRules.skinsFor(owned, weaponId) do
		table.insert(skins, { id = skin.id })
	end
	local rowY = y
	for i, skin in skins do
		local skinId = skin.id
		rowY = y + ((i - 1) // COLUMNS) * (CARD_SIZE.Y + CARD_GAP)
		local item = { tool = currentTool, skin = skinId }
		card(((i - 1) % COLUMNS) * step, rowY, Rules.skinLabel(skinId), item, skinId == currentSkin, function()
			LocalInventory.equip(slotName, weaponId, skinId)
		end)
	end
	fillRow(#skins, rowY)
end

-- Cette méthode permet de rendre un emplacement actif (sa grille, son arme dans les mains du personnage) lorsque le
-- joueur clique son onglet, tape sa touche ou tourne la molette.
local function selectSlot(index: number)
	selectedSlot = index
	rebuildGrid()
	paintTabs()
	paintHeader()
end

-- Cette méthode permet de construire l'onglet d'un emplacement (« 1 · SNIPER ») lorsque l'écran est construit.
local function buildTab(parent: GuiObject, index: number, slotName: string): TabView
	local button = UIKit.create("TextButton", {
		Name = "Tab" .. index,
		Text = string.format("%d  ·  %s", index, slotLabel(slotName)),
		FontFace = F.Display,
		TextSize = 18,
		TextColor3 = C.Bone,
		AutoButtonColor = false,
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(EDGE + (index - 1) * (TAB_SIZE.X + TAB_GAP), TABS_Y),
		Size = UDim2.fromOffset(TAB_SIZE.X, TAB_SIZE.Y),
		Parent = parent,
	})
	local view: TabView = { button = button, hovering = false }
	button.MouseEnter:Connect(function()
		view.hovering = true
		paintTabs()
	end)
	button.MouseLeave:Connect(function()
		view.hovering = false
		paintTabs()
	end)
	button.Activated:Connect(function()
		if not MenuShot.isBusy() then
			selectSlot(index)
		end
	end)
	return view
end

-- Cette méthode permet de construire l'aide en bas à gauche (touche en boîte, action en texte) lorsque l'écran est
-- construit.
local function buildHints(root: Frame)
	local row = UIKit.frame({
		Name = "Hints",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -18),
		Size = UDim2.fromOffset(GRID_WIDTH, 22),
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	local hints = { { "MOLETTE", "EMPLACEMENT" }, { "CLIC", "ÉQUIPER" } }
	for i, hint in hints do
		tag(row, "Key" .. i, 2 * i - 1, C.Bone, C.Ground).Text = hint[1]
		UIKit.text({
			Name = "Action" .. i,
			Text = hint[2] .. "      ",
			FontFace = F.DisplayMedium,
			TextSize = 14,
			TextColor3 = C.TextSoft,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			LayoutOrder = 2 * i,
			Parent = row,
		})
	end
	UIKit.text({
		Name = "Saved",
		Text = "ENREGISTRÉ AUSSITÔT",
		FontFace = F.DisplayMedium,
		TextSize = 14,
		TextColor3 = C.Muted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = 9,
		Parent = row,
	})
end

-- Cette méthode permet de construire l'écran (titre, rendu, nom, onglets et grille dans `column` à gauche, aide en bas
-- à gauche) lorsque l'accueil est construit ; il suit ensuite chaque changement d'inventaire.
function EquipmentScreen.build(root: Frame, column: Frame)
	-- Sous la colonne, créée avant lui : à ZIndex égal il passerait devant et voilerait la grille
	UIKit.cornerScrim(root, "BottomLeft", SCRIM_SIZE, SCRIM_SHOWN).ZIndex = 0
	-- La colonne de gauche descend avec le titre du jeu sous la barre de Roblox (#306)
	UIKit.shadowedText(column, {
		Name = "EquipmentTitle",
		Text = "ÉQUIPEMENT",
		FontFace = F.Display,
		TextSize = TITLE_SIZE,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE, TITLE_Y),
		Size = UDim2.fromOffset(400, TITLE_SIZE + 6),
		ZIndex = 2,
	}, 3)
	local slotRow = flowRow(column, "SlotTitle", TITLE_Y + TITLE_STEP, TITLE_SIZE + 6)
	slotTitle = flowText(slotRow, "Slot", TITLE_SIZE, 3)
	slotTag = tag(slotRow, "SlotTag", 2, C.Accent, C.Ground)
	previewHolder = UIKit.frame({
		Name = "Preview",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PREVIEW_POSITION.X, PREVIEW_POSITION.Y),
		Size = UDim2.fromOffset(PREVIEW_SIZE.X, PREVIEW_SIZE.Y),
		Parent = column,
	})
	local nameRow = flowRow(column, "WeaponName", NAME_Y, NAME_SIZE + 6)
	weaponName = flowText(nameRow, "Weapon", NAME_SIZE, 2)
	statusTag = tag(nameRow, "Status", 2, C.HitRed, C.Bone)
	statusStroke = UIKit.stroke(statusTag, C.Bone, 1)
	statusStroke.Transparency = 0.4
	category, categoryShadow = UIKit.shadowedText(column, {
		Name = "Category",
		FontFace = F.DisplayMedium,
		TextSize = 15,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(EDGE + 1, CATEGORY_Y),
		Size = UDim2.fromOffset(400, 18),
		ZIndex = 2,
	}, 1)
	for index, slotName in InventoryRules.SLOTS do
		tabViews[index] = buildTab(column, index, slotName)
	end
	grid = UIKit.frame({
		Name = "EquipGrid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, GRID_Y),
		Size = UDim2.fromOffset(GRID_WIDTH, 2 * CARD_SIZE.Y + SECTION_HEIGHT + SECTION_GAP),
		Parent = column,
	})
	buildHints(root)
	selectSlot(selectedSlot)
	LocalInventory.onChanged(function()
		selectSlot(selectedSlot)
	end)
end

-- Cette méthode permet de changer d'emplacement actif au clavier (touches des emplacements réglées par le joueur, 1 et 2
-- par défaut) ou à la molette (sens réglé, coupée sur AUCUNE) lorsque le joueur est sur l'accueil.
function EquipmentScreen.onInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local step = PlayerSettings.wheelStep(LocalSettings.get().wheel, input.Position.Z)
		if step then
			selectSlot(Rules.cycleIndex(selectedSlot, step, #InventoryRules.SLOTS))
		end
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local index = PlayerSettings.slotForKey(LocalSettings.get().slotKeys, input.KeyCode.Name)
		if index and InventoryRules.SLOTS[index] then
			selectSlot(index)
		end
	end
end

-- Cette méthode permet de remettre l'écran à l'arrivée (SNIPER actif, aucun survol) lorsque le joueur quitte l'accueil
-- ou revient au menu.
function EquipmentScreen.reset()
	if not grid then
		return
	end
	for _, view in tabViews do
		view.hovering = false
	end
	selectSlot(1)
end

return EquipmentScreen

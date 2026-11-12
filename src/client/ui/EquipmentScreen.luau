-- Écran d'équipement de l'onglet ARMES (#280, propale visuelle du 2026-11-12, docs/ui.md) : à gauche, sous
-- « ÉQUIPEMENT », les deux emplacements (arme et skin équipés, l'actif en os avec la barre ambrée) ; à droite, toujours
-- ouverte sur l'emplacement actif, la liste de ses armes possédées (silhouette, nom, « ÉQUIPÉ ») puis les skins de
-- l'arme équipée en vignettes. Le personnage de l'accueil tient l'arme survolée, sinon celle de l'emplacement actif ; un
-- clic équipe (remote EquipItem, l'écran suit la réponse du serveur). Seuls les items possédés apparaissent.
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

-- Mise en page (px à 720 de haut), d'après la propale
local EDGE = 28
local HEADER_Y = 140 -- titre de la liste à droite
local PAGE_TITLE_Y = 118 -- « ÉQUIPEMENT » à gauche, titre de la page
local PAGE_TITLE_SIZE = 30
local SLOTS_Y = 176
local SLOT_STEP = 100
local SLOT_SIZE = Vector2.new(300, 84)
local SLOT_LABELS = { sniper = "SNIPER", knife = "COUTEAU" }
local PANEL_WIDTH = 380
local ROW_HEIGHT = 46
local ROW_ICON = Vector2.new(110, 28)
local SECTION_GAP = 22
local TILE_SIZE = Vector2.new(120, 88)
local TILE_GAP = 10
local TILE_ICON = Vector2.new(104, 36)
local TITLE_HEIGHT = 28 -- titre de section, avant sa première ligne
local SCRIM_SIZE = Vector2.new(640, 620) -- fond de coin sous la liste (le mur clair du décor rendait le texte illisible)
local SCRIM_SHOWN = 0.3

type SlotView = {
	label: TextLabel,
	name: TextLabel,
	nameShadow: TextLabel,
	skin: TextLabel,
	skinShadow: TextLabel,
	bar: Frame,
	hovering: boolean,
}

local slotViews: { SlotView } = {}
local panel: Frame
local selectedSlot = 1 -- emplacement actif : sa liste est ouverte à droite, le personnage tient son arme
local hoverTool: string? = nil -- arme survolée, tenue par le personnage tant que la souris reste dessus

-- Cette méthode permet de nommer un emplacement (« SNIPER », sinon son id en majuscules) lorsqu'il est affiché.
local function slotLabel(slotName: string): string
	return SLOT_LABELS[slotName] or string.upper(slotName)
end

-- Cette méthode permet de donner le nom affiché d'une arme (nom de WeaponConfig en majuscules, sinon nom du Tool
-- espacé) lorsqu'un emplacement ou la liste la nomme.
local function weaponTitle(toolName: string): string
	local cfg = WeaponConfig.Weapons[toolName]
	return if cfg and cfg.Name then string.upper(cfg.Name) else HUDRules.weaponLabel(toolName)
end

-- Cette méthode permet de donner le viewmodel d'une arme (attribut du Tool, sinon son nom) lorsque sa silhouette est
-- dessinée.
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

-- Cette méthode permet de mettre dans les mains du personnage l'arme survolée, sinon celle de l'emplacement actif,
-- lorsque le survol, l'emplacement actif ou l'équipement change.
local function updateHeld()
	local weapon = equippedAt(selectedSlot)
	local tool = hoverTool or (weapon and weapon.tool)
	if tool then
		MenuScene.holdTool(tool)
	end
end

-- Cette méthode permet de redessiner les emplacements (arme et skin équipés ; actif en os avec la barre ambrée, l'autre
-- grisé ; survol en rouge d'impact) lorsque l'équipement, le survol ou l'emplacement actif change.
local function paintSlots()
	for index, view in slotViews do
		local weapon, skin = equippedAt(index)
		local title = if weapon and weapon.tool then weaponTitle(weapon.tool) else ""
		local skinText = "SKIN · " .. Rules.skinLabel(skin)
		view.name.Text = title
		view.nameShadow.Text = title
		view.skin.Text = skinText
		view.skinShadow.Text = skinText
		local active = selectedSlot == index
		local color = if view.hovering then C.HitRed elseif active then C.Bone else C.BoneMuted
		UIKit.tween(view.name, Motion.Hover, { TextColor3 = color })
		view.label.TextColor3 = if active then C.Accent else C.BoneMuted
		view.bar.Visible = active
	end
end

-- Cette méthode permet de brancher le survol (arme tenue par le personnage) et le clic d'un élément de la liste
-- lorsqu'il est créé ; `paint(hovering)` redessine l'élément.
local function bindItem(button: GuiButton, tool: string, paint: (boolean) -> (), action: () -> ())
	button.MouseEnter:Connect(function()
		hoverTool = tool
		paint(true)
		updateHeld()
	end)
	button.MouseLeave:Connect(function()
		paint(false)
		if hoverTool == tool then
			hoverTool = nil
			updateHeld()
		end
	end)
	button.Activated:Connect(function()
		if not MenuShot.isBusy() then -- JOUER bloque les choix jusqu'au retour au menu
			action()
		end
	end)
end

-- Cette méthode permet de poser la ligne d'une arme (silhouette, nom, « ÉQUIPÉ » en rouge d'impact, filet dessous)
-- lorsque la liste se construit ; survoler la montre dans les mains du personnage, cliquer l'équipe.
local function weaponRow(y: number, toolName: string, equipped: boolean, action: () -> ())
	local row = UIKit.create("TextButton", {
		Name = "Row" .. toolName,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(PANEL_WIDTH, ROW_HEIGHT),
		Parent = panel,
	})
	local icon = UIKit.frame({
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(ROW_ICON.X, ROW_ICON.Y),
		Parent = row,
	})
	local silhouette = UIKit.weaponSilhouette(icon, viewmodelOf(toolName), ROW_ICON.X / ROW_ICON.Y)
	local restColor = if equipped then C.Bone else C.BoneMuted
	silhouette.ImageColor3 = restColor
	local name = UIKit.shadowedText(row, {
		Name = "Name",
		Text = weaponTitle(toolName),
		FontFace = F.Display,
		TextSize = 22,
		TextColor3 = restColor,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, ROW_ICON.X + 14, 0.5, 0),
		Size = UDim2.fromOffset(170, 26),
		ZIndex = 2,
	}, 2)
	if equipped then
		UIKit.shadowedText(row, {
			Name = "Status",
			Text = "ÉQUIPÉ",
			FontFace = F.Display,
			TextSize = 16,
			TextColor3 = C.HitRed,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(80, 20),
			ZIndex = 2,
		}, 2)
	end
	UIKit.frame({
		Name = "Rule",
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.85,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = row,
	})
	bindItem(row, toolName, function(hovering)
		local color = if hovering then C.HitRed else restColor
		UIKit.tween(name, Motion.Hover, { TextColor3 = color })
		silhouette.ImageColor3 = color
	end, action)
end

-- Cette méthode permet de poser la vignette d'un skin (silhouette, nom, trait rouge d'impact sous l'équipé) lorsque la
-- liste se construit ; `action` nil : case vide « AUCUN AUTRE SKIN », ni survol ni clic.
local function skinTile(x: number, y: number, text: string, toolName: string, equipped: boolean, action: (() -> ())?)
	local tile = UIKit.create("TextButton", {
		Name = "Tile" .. text,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = if action then 0.45 else 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y),
		Parent = panel,
	})
	local stroke = UIKit.stroke(tile, C.Bone, 1)
	stroke.Transparency = if equipped then 0.2 elseif action then 0.7 else 0.8
	local label = UIKit.shadowedText(tile, {
		Name = "Name",
		Text = text,
		FontFace = F.Display,
		TextSize = if action then 15 else 13,
		TextColor3 = if action then C.Bone else C.BoneMuted,
		TextXAlignment = if action then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(8, TILE_SIZE.Y - 26),
		Size = UDim2.fromOffset(TILE_SIZE.X - 16, 18),
		ZIndex = 2,
	}, 2)
	if not action then
		return
	end
	local icon = UIKit.frame({
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset((TILE_SIZE.X - TILE_ICON.X) / 2, 12),
		Size = UDim2.fromOffset(TILE_ICON.X, TILE_ICON.Y),
		Parent = tile,
	})
	-- Skin pas encore rendu (#268) : la silhouette de l'arme, la même pour tous ses skins
	UIKit.weaponSilhouette(icon, viewmodelOf(toolName), TILE_ICON.X / TILE_ICON.Y).ImageColor3 = C.Bone
	if equipped then
		UIKit.frame({
			Name = "Equipped",
			BackgroundColor3 = C.HitRed,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			Parent = tile,
		})
	end
	bindItem(tile, toolName, function(hovering)
		UIKit.tween(label, Motion.Hover, { TextColor3 = if hovering then C.HitRed else C.Bone })
	end, action)
end

-- Cette méthode permet de reconstruire la liste de droite (armes possédées de l'emplacement actif, puis skins possédés
-- de son arme équipée) lorsque l'emplacement actif ou l'équipement change.
local function rebuildList()
	for _, child in panel:GetChildren() do
		child:Destroy()
	end
	-- Les éléments survolés disparaissent ; un emplacement survolé à gauche garde son arme en main
	hoverTool = nil
	for index, view in slotViews do
		if view.hovering then
			local weapon = equippedAt(index)
			hoverTool = weapon and weapon.tool
		end
	end
	local slotName = InventoryRules.SLOTS[selectedSlot]
	if not slotName then
		return
	end
	local owned = LocalInventory.owned()
	local current, currentSkin = equippedAt(selectedSlot)
	local weapons = InventoryRules.weaponsForSlot(owned, slotName)
	UIKit.accentLabel(panel, {
		Name = "Title",
		Text = string.format("%s · %d POSSÉDÉ%s", slotLabel(slotName), #weapons, if #weapons > 1 then "S" else ""),
		Size = UDim2.fromOffset(PANEL_WIDTH, 18),
	})
	local y = TITLE_HEIGHT
	for _, weapon in weapons do
		local isEquipped = current ~= nil and current.id == weapon.id
		weaponRow(y, weapon.tool or "", isEquipped, function()
			-- Recliquer l'arme équipée garde son skin ; une autre arme part avec son skin d'origine
			LocalInventory.equip(slotName, weapon.id, if isEquipped then currentSkin else nil)
		end)
		y += ROW_HEIGHT
	end
	if not (current and current.tool) then
		return
	end
	local currentTool: string = current.tool
	local weaponId = current.id
	y += SECTION_GAP
	UIKit.accentLabel(panel, {
		Name = "SkinsTitle",
		Text = "SKINS · " .. weaponTitle(currentTool),
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(PANEL_WIDTH, 18),
	})
	y += TITLE_HEIGHT
	-- D'origine d'abord (id nil), puis les skins possédés de l'arme ; seul, il est suivi d'une case vide
	local skins: { { id: string? } } = { { id = nil } }
	for _, skin in InventoryRules.skinsFor(owned, weaponId) do
		table.insert(skins, { id = skin.id })
	end
	local perRow = math.max(1, math.floor((PANEL_WIDTH + TILE_GAP) / (TILE_SIZE.X + TILE_GAP)))
	for i, skin in skins do
		local skinId = skin.id
		local column, line = (i - 1) % perRow, (i - 1) // perRow
		local x, tileY = column * (TILE_SIZE.X + TILE_GAP), y + line * (TILE_SIZE.Y + TILE_GAP)
		skinTile(x, tileY, Rules.skinLabel(skinId), currentTool, skinId == currentSkin, function()
			LocalInventory.equip(slotName, weaponId, skinId)
		end)
	end
	if #skins == 1 then
		skinTile(TILE_SIZE.X + TILE_GAP, y, "AUCUN AUTRE SKIN", currentTool, false, nil)
	end
end

-- Cette méthode permet de rendre un emplacement actif (sa liste à droite, son arme dans les mains du personnage)
-- lorsque le joueur le clique, tape sa touche ou tourne la molette.
local function selectSlot(index: number)
	selectedSlot = index
	-- Le choix l'emporte sur le survol en cours, sinon il semblerait sans effet
	hoverTool = nil
	rebuildList()
	paintSlots()
	updateHeld()
end

-- Cette méthode permet de construire un emplacement à gauche (« 1 · SNIPER », arme et skin équipés, barre ambrée quand
-- il est actif) lorsque l'écran est construit ; tout le bloc se clique, son survol montre l'arme équipée.
local function buildSlot(root: Frame, index: number, slotName: string): SlotView
	local button = UIKit.create("TextButton", {
		Name = "Slot" .. index,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(EDGE, SLOTS_Y + (index - 1) * SLOT_STEP),
		Size = UDim2.fromOffset(SLOT_SIZE.X, SLOT_SIZE.Y),
		Parent = root,
	})
	local label = UIKit.accentLabel(button, {
		Name = "Label",
		Text = string.format("%d · %s", index, slotLabel(slotName)),
		Size = UDim2.fromOffset(SLOT_SIZE.X, 18),
	})
	local name, nameShadow = UIKit.shadowedText(button, {
		Name = "Weapon",
		FontFace = F.Display,
		TextSize = 32,
		TextColor3 = C.BoneMuted,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.fromOffset(SLOT_SIZE.X, 38),
		ZIndex = 2,
	}, 2)
	local skin, skinShadow = UIKit.shadowedText(button, {
		Name = "Skin",
		FontFace = F.DisplayMedium,
		TextSize = 15,
		TextColor3 = C.BoneMuted,
		Position = UDim2.fromOffset(1, 60),
		Size = UDim2.fromOffset(SLOT_SIZE.X, 18),
		ZIndex = 2,
	}, 2)
	local view: SlotView = {
		label = label,
		name = name,
		nameShadow = nameShadow,
		skin = skin,
		skinShadow = skinShadow,
		bar = UIKit.frame({
			Name = "Bar",
			BackgroundColor3 = C.Accent,
			Position = UDim2.fromOffset(-14, 0),
			Size = UDim2.fromOffset(3, 78),
			Visible = false,
			Parent = button,
		}),
		hovering = false,
	}
	button.MouseEnter:Connect(function()
		view.hovering = true
		local weapon = equippedAt(index)
		hoverTool = weapon and weapon.tool
		paintSlots()
		updateHeld()
	end)
	button.MouseLeave:Connect(function()
		view.hovering = false
		hoverTool = nil
		paintSlots()
		updateHeld()
	end)
	button.Activated:Connect(function()
		if not MenuShot.isBusy() then
			selectSlot(index)
		end
	end)
	return view
end

-- Cette méthode permet de construire l'écran (titre et emplacements à gauche, liste à droite sur son fond de coin, aide
-- en bas à droite) lorsque l'accueil est construit ; il suit ensuite chaque changement d'inventaire ou d'équipement.
function EquipmentScreen.build(root: Frame)
	UIKit.cornerScrim(root, "TopRight", SCRIM_SIZE, SCRIM_SHOWN)
	-- Titre de la page, en grand : il dit qu'on est sur l'écran d'équipement (retour de l'utilisateur)
	UIKit.shadowedText(root, {
		Name = "EquipmentTitle",
		Text = "ÉQUIPEMENT",
		FontFace = F.Display,
		TextSize = PAGE_TITLE_SIZE,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(EDGE, PAGE_TITLE_Y),
		Size = UDim2.fromOffset(SLOT_SIZE.X, PAGE_TITLE_SIZE + 4),
		ZIndex = 2,
	}, 2)
	panel = UIKit.frame({
		Name = "EquipList",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, HEADER_Y),
		Size = UDim2.fromOffset(PANEL_WIDTH, 440),
		Parent = root,
	})
	UIKit.shadowedText(root, {
		Name = "Hint",
		Text = "CLIC POUR ÉQUIPER  ·  ENREGISTRÉ AUSSITÔT",
		FontFace = F.DisplayMedium,
		TextSize = 15,
		TextColor3 = C.TextSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE, 1, -20),
		Size = UDim2.fromOffset(PANEL_WIDTH, 18),
		ZIndex = 2,
	}, 2)
	for index, slotName in InventoryRules.SLOTS do
		slotViews[index] = buildSlot(root, index, slotName)
	end
	rebuildList()
	paintSlots()
	updateHeld()
	LocalInventory.onChanged(function()
		rebuildList()
		paintSlots()
		updateHeld()
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
	if not panel then
		return
	end
	for _, view in slotViews do
		view.hovering = false
	end
	selectSlot(1)
end

return EquipmentScreen

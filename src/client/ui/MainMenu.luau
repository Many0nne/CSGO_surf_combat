-- Menu principal (docs/ui.md) : derrière, le personnage du jeu en pose sur une copie de la map (#253, MenuScene) ; on
-- choisit à la souris système, rien ne se tire. Titre en haut à gauche, onglets ARMES · INFOS · JOUER · RÉGLAGES ·
-- FEEDBACK en haut au centre (au-dessus des écrans secondaires, qui s'ouvrent dessous), fiche de l'arme tenue en bas à
-- gauche. L'onglet ARMES est l'écran d'équipement (#280, disposition A) : les deux emplacements à gauche (arme et skin
-- équipés) ; un clic sur l'un ouvre à droite ses armes possédées, puis les skins de l'arme équipée. Le personnage tient
-- l'arme survolée, sinon celle de l'emplacement choisi (touches 1 et 2, molette) ; un clic équipe (serveur, sauvegardé).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InventoryRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryRules"))
local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig"))
local LocalInventory = require(script.Parent.Parent.systems.inventory.LocalInventory)
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local Rules = require(script.Parent.Parent.systems.game.MenuSceneRules)
local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
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
local STATS = {
	{ key = "damage", label = "DÉGÂTS" },
	{ key = "rate", label = "CADENCE" },
	{ key = "accuracy", label = "PRÉCISION" },
}
-- Écran d'équipement (#280, prototype validé en Studio) : emplacements à gauche, liste à droite (px à 720 de haut)
local SLOTS_Y = 150
local SLOT_STEP = 90
local SLOT_SIZE = Vector2.new(300, 80)
local SLOT_LABELS = { sniper = "SNIPER", knife = "COUTEAU" }
local LIST_Y = 150
local LIST_WIDTH = 260
local LIST_HEADER = 28 -- titre de section et son filet, avant la première ligne
local LIST_STEP = 34
local LIST_GAP = 24 -- entre la section ARME et la section SKIN
local LIST_SCRIM = Vector2.new(520, 560) -- fond de coin sous la liste (le mur clair du décor rendait le texte illisible)
local LIST_SCRIM_SHOWN = 0.35

type SlotView = {
	name: TextLabel,
	nameShadow: TextLabel,
	skin: TextLabel,
	skinShadow: TextLabel,
	bar: Frame,
	hovering: boolean,
}

local gui: ScreenGui
local tabsGui: ScreenGui
local content: Frame
local card: Frame
local cardName: TextLabel
local cardNameShadow: TextLabel
local cardCategory: TextLabel
local bars: { [string]: { Frame } } = {}
local tabs: { [string]: MenuShot.Choice } = {}
local choices: { MenuShot.Choice } = {}
local callbacks: { [string]: (() -> ())? } = {}
local slotViews: { SlotView } = {}
local list: Frame
local listScrim: ImageLabel
local focusedSlot = 1 -- emplacement dont le personnage tient l'arme équipée (hors survol)
local openSlot: number? = nil -- emplacement dont la liste est ouverte à droite
local hoverTool: string? = nil -- arme survolée, tenue par le personnage tant que la souris reste dessus
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
	card = UIKit.create("Frame", {
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

-- Cette méthode permet de lire l'arme (fiche du catalogue) et le skin équipés d'un emplacement par son rang lorsque
-- l'écran d'équipement les affiche.
local function equippedAt(index: number): (InventoryRules.Item?, string?)
	local loadout = LocalInventory.equipped()[InventoryRules.SLOTS[index]]
	if not loadout then
		return nil, nil
	end
	return InventoryRules.item(loadout.weapon), loadout.skin
end

-- Cette méthode permet de mettre dans les mains du personnage l'arme survolée, sinon celle équipée de l'emplacement
-- choisi, lorsque le survol, l'emplacement choisi ou l'équipement change.
local function updateHeld()
	local weapon = equippedAt(focusedSlot)
	local tool = hoverTool or (weapon and weapon.tool)
	if tool then
		MenuScene.holdTool(tool)
	end
end

-- Cette méthode permet de redessiner les emplacements (arme et skin équipés, survol en rouge d'impact, barre ambrée sur
-- l'emplacement ouvert) lorsque l'équipement, le survol ou la liste ouverte change.
local function paintSlots()
	for index, view in slotViews do
		local weapon, skin = equippedAt(index)
		local title = if weapon and weapon.tool then weaponTitle(weapon.tool) else ""
		local skinText = "SKIN · " .. Rules.skinLabel(skin)
		view.name.Text = title
		view.nameShadow.Text = title
		view.skin.Text = skinText
		view.skinShadow.Text = skinText
		local open = openSlot == index
		local color = if view.hovering then C.HitRed elseif open then C.Bone else C.TextSoft
		UIKit.tween(view.name, UITheme.Motion.Hover, { TextColor3 = color })
		view.bar.Visible = open
	end
end

-- Cette méthode permet de poser un titre de section ambré à droite, souligné d'un filet, lorsque la liste se construit.
local function listHeader(text: string, y: number)
	UIKit.text({
		Name = "Header",
		Text = text,
		FontFace = F.DisplayMedium,
		TextSize = 13,
		TextColor3 = C.Accent,
		TextStrokeTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(LIST_WIDTH, 16),
		Parent = list,
	})
	UIKit.frame({
		Name = "Rule",
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0.4,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y + 20),
		Size = UDim2.fromOffset(200, 1),
		Parent = list,
	})
end

-- Cette méthode permet de poser une ligne de la liste (choix en texte à droite, « ÉQUIPÉ » ambré devant celui équipé)
-- lorsque la liste se construit ; survoler montre `tool` dans les mains du personnage, cliquer appelle `action`.
local function listEntry(text: string, y: number, equipped: boolean, tool: string, action: () -> ())
	local choice = MenuShot.textChoice({
		text = text,
		font = if equipped then F.Display else F.DisplayMedium,
		size = 24,
		color = if equipped then C.Bone else C.TextSoft,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, y),
		parent = list,
		action = action,
	})
	if equipped then
		UIKit.text({
			Name = "Equipped",
			Text = "ÉQUIPÉ",
			FontFace = F.DisplayMedium,
			TextSize = 12,
			TextColor3 = C.Accent,
			TextStrokeTransparency = 0.35,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, -14, 0.5, 0),
			Size = UDim2.fromOffset(60, 14),
			Parent = choice.button,
		})
	end
	choice.button.MouseEnter:Connect(function()
		hoverTool = tool
		updateHeld()
	end)
	choice.button.MouseLeave:Connect(function()
		if hoverTool == tool then
			hoverTool = nil
			updateHeld()
		end
	end)
end

-- Cette méthode permet de reconstruire la liste de droite (armes possédées de l'emplacement ouvert, puis skins possédés
-- de son arme équipée) lorsqu'un emplacement s'ouvre ou que l'équipement change ; vide si rien n'est ouvert.
local function rebuildList()
	for _, child in list:GetChildren() do
		child:Destroy()
	end
	-- Les lignes survolées disparaissent ; un emplacement survolé à gauche garde son arme en main
	hoverTool = nil
	for index, view in slotViews do
		if view.hovering then
			local weapon = equippedAt(index)
			hoverTool = weapon and weapon.tool
		end
	end
	local slotName = openSlot and InventoryRules.SLOTS[openSlot]
	list.Visible = slotName ~= nil
	listScrim.Visible = slotName ~= nil
	if not (openSlot and slotName) then
		return
	end
	local slotIndex: number = openSlot
	local owned = LocalInventory.owned()
	local current, currentSkin = equippedAt(slotIndex)
	listHeader(slotLabel(slotName) .. " · ARME", 0)
	local y = LIST_HEADER
	for _, weapon in InventoryRules.weaponsForSlot(owned, slotName) do
		local tool = weapon.tool or ""
		local isEquipped = current ~= nil and current.id == weapon.id
		listEntry(weaponTitle(tool), y, isEquipped, tool, function()
			-- Recliquer l'arme équipée garde son skin ; une autre arme part avec son skin d'origine
			LocalInventory.equip(slotName, weapon.id, if isEquipped then currentSkin else nil)
		end)
		y += LIST_STEP
	end
	if not (current and current.tool) then
		return
	end
	local currentTool: string = current.tool
	local weaponId = current.id
	y += LIST_GAP
	listHeader(weaponTitle(currentTool) .. " · SKIN", y)
	y += LIST_HEADER
	-- D'origine d'abord (id nil), puis les skins possédés de l'arme
	local skins: { { id: string? } } = { { id = nil } }
	for _, skin in InventoryRules.skinsFor(owned, weaponId) do
		table.insert(skins, { id = skin.id })
	end
	for _, skin in skins do
		local skinId = skin.id
		listEntry(Rules.skinLabel(skinId), y, skinId == currentSkin, currentTool, function()
			LocalInventory.equip(slotName, weaponId, skinId)
		end)
		y += LIST_STEP
	end
end

-- Cette méthode permet de choisir l'emplacement montré (personnage) et, si une liste est ouverte, d'y basculer
-- lorsque le joueur tape 1 ou 2 ou tourne la molette.
local function focusSlot(index: number)
	focusedSlot = index
	-- La touche l'emporte sur le survol en cours, sinon elle semblerait sans effet
	hoverTool = nil
	if openSlot and openSlot ~= index then
		openSlot = index
		rebuildList()
	end
	paintSlots()
	updateHeld()
end

-- Cette méthode permet d'ouvrir la liste d'un emplacement, ou de la fermer s'il était déjà ouvert, lorsque le joueur
-- clique dessus.
local function toggleSlot(index: number)
	focusedSlot = index
	openSlot = if openSlot == index then nil else index
	rebuildList()
	paintSlots()
	updateHeld()
end

-- Cette méthode permet de fermer la liste lorsque le joueur quitte l'accueil ou le menu.
local function closeList()
	openSlot = nil
	rebuildList()
	paintSlots()
	updateHeld()
end

-- Cette méthode permet de construire un emplacement à gauche (« 1 · SNIPER », arme et skin équipés, barre ambrée quand
-- sa liste est ouverte) lorsque le menu est initialisé ; tout le bloc se clique, son survol montre l'arme équipée.
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
	UIKit.text({
		Name = "Label",
		Text = string.format("%d · %s", index, slotLabel(slotName)),
		FontFace = F.DisplayMedium,
		TextSize = 13,
		TextColor3 = C.Accent,
		TextStrokeTransparency = 0.35,
		Size = UDim2.fromOffset(SLOT_SIZE.X, 16),
		Parent = button,
	})
	local name, nameShadow = UIKit.shadowedText(button, {
		Name = "Weapon",
		FontFace = F.Display,
		TextSize = 30,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.fromOffset(SLOT_SIZE.X, 36),
		ZIndex = 2,
	}, 2)
	local skin, skinShadow = UIKit.shadowedText(button, {
		Name = "Skin",
		FontFace = F.DisplayMedium,
		TextSize = 14,
		TextColor3 = C.Bone,
		TextTransparency = 0.25,
		Position = UDim2.fromOffset(1, 52),
		Size = UDim2.fromOffset(SLOT_SIZE.X, 18),
		ZIndex = 2,
	}, 2)
	local view: SlotView = {
		name = name,
		nameShadow = nameShadow,
		skin = skin,
		skinShadow = skinShadow,
		bar = UIKit.frame({
			Name = "Bar",
			BackgroundColor3 = C.Accent,
			Position = UDim2.fromOffset(-14, 18),
			Size = UDim2.fromOffset(3, 52),
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
		if not MenuShot.isBusy() then -- JOUER bloque les choix jusqu'au retour au menu
			toggleSlot(index)
		end
	end)
	return view
end

-- Cette méthode permet de construire l'écran d'équipement (emplacements à gauche, liste vide à droite sur son fond de
-- coin) lorsque le menu est initialisé ; il suit ensuite chaque changement d'inventaire ou d'équipement.
local function buildEquipment(root: Frame)
	listScrim = UIKit.cornerScrim(root, "TopRight", LIST_SCRIM, LIST_SCRIM_SHOWN)
	listScrim.Visible = false
	list = UIKit.frame({
		Name = "EquipList",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, LIST_Y),
		Size = UDim2.fromOffset(LIST_WIDTH, 400),
		Visible = false,
		Parent = root,
	})
	for index, slotName in InventoryRules.SLOTS do
		slotViews[index] = buildSlot(root, index, slotName)
	end
	paintSlots()
	LocalInventory.onChanged(function()
		rebuildList()
		paintSlots()
		updateHeld()
	end)
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

-- Cette méthode permet de construire l'accueil (titre, fiche, écran d'équipement) lorsque le menu est initialisé.
local function buildContent(root: Frame)
	content = UIKit.frame({ Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	buildTitle(content)
	buildCard(content)
	buildEquipment(content)
	updateHeld()
	showWeapon(MenuScene.getWeapon())
	MenuScene.onWeaponChanged(showWeapon)
end

-- Cette méthode permet de choisir l'emplacement montré par le personnage (touches des emplacements réglées par le
-- joueur, 1 et 2 par défaut comme en partie ; la molette alterne) lorsque le joueur est sur l'accueil.
local function onWeaponInput(input: InputObject, processed: boolean)
	if processed or currentPage ~= "home" then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Sens réglé par le joueur (Réglages > TOUCHES), comme en partie ; AUCUNE coupe la molette ici aussi
		local step = PlayerSettings.wheelStep(LocalSettings.get().wheel, input.Position.Z)
		if step then
			focusSlot(Rules.cycleIndex(focusedSlot, step, #InventoryRules.SLOTS))
		end
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local index = PlayerSettings.slotForKey(LocalSettings.get().slotKeys, input.KeyCode.Name)
		if index and InventoryRules.SLOTS[index] then
			focusSlot(index)
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
-- l'orchestrateur ouvre un écran secondaire ou revient à l'accueil ; la liste d'équipement se referme en partant.
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
		for _, view in slotViews do
			view.hovering = false
		end
		closeList()
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
	for _, view in slotViews do
		view.hovering = false
	end
	closeList()
	-- JOUER garde les clics bloqués (`locks`) jusqu'ici : sans cela, les choix du menu en partie et de ses Réglages
	-- restaient sans effet (#157)
	MenuShot.reset()
	MenuScene.stop()
end

return MainMenu

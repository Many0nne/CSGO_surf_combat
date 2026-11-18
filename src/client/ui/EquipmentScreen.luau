-- Écran d'équipement de l'onglet ARMES (#280, disposition revue en #308 d'après une capture de référence, docs/ui.md) :
-- tout tient à gauche, le personnage de l'accueil est à droite et tient l'arme montrée. De haut en bas : grand titre
-- « ÉQUIPEMENT » puis l'emplacement actif et son étiquette, rendu de l'arme montrée, son nom avec « ÉQUIPÉ », onglets
-- des emplacements, grille de cartes qui défile à la molette (armes possédées, puis skins de l'arme équipée). Survoler
-- une carte la montre, cliquer l'équipe (remote EquipItem, l'écran suit la réponse du serveur). Seuls les items
-- possédés apparaissent. Onglet TENUE (#521) : tenues de personnage possédées, en portrait ; le personnage de
-- l'accueil porte la tenue survolée ou équipée (MenuScene.previewOutfit), la tenue s'achète au shop. Dernier onglet,
-- EFFET (#566) : effets de tir possédés (caisse d'effets), chaque carte montrant l'AWP dans le skin qui l'inspire ;
-- l'effet survolé ou équipé est montré par la démonstration jouée sur la map (EffectStage, #575), qui prend la caméra.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local Locale = require(Shared:WaitForChild("Locale"))
local PlayerSettings = require(Shared:WaitForChild("PlayerSettings"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local ShotEffectRules = require(Shared:WaitForChild("ShotEffectRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local LocalInventory = require(script.Parent.Parent.systems.inventory.LocalInventory)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local EffectStage = require(script.Parent.Parent.systems.game.EffectStage)
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local Rules = require(script.Parent.Parent.systems.game.MenuSceneRules)
local HUDRules = require(script.Parent.HUDRules)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local EquipmentScreen = {}

-- Mise en page (px à 720 de haut)
local EDGE = MenuPage.Edge
local TITLE_Y = MenuPage.TitleY -- « ÉQUIPEMENT », sous le titre du jeu
local TITLE_SIZE = MenuPage.TitleSize
local TITLE_STEP = 54 -- écart entre les deux lignes du titre
local NAME_Y = 236 -- nom de l'arme montrée et son étiquette
local NAME_SIZE = 26
local CATEGORY_Y = 272
local TABS_Y = 318
local TAB_GAP = 6
local GRID_Y = 362
local GRID_BOTTOM = 54 -- la zone défilante s'arrête au-dessus de l'aide en bas (18 + 24 px) : une rangée et demie de skins
local GRID_PAD = 2 -- retrait des cartes dans la zone défilante : son bord ne coupe pas leur contour au survol
local SCROLL_BAR = 3
local SCROLL_GAP = 7 -- écart entre la grille et sa barre de défilement
local STATS_GAP = 12 -- écart minimal entre la grille et la fiche de statistiques (à côté ou au-dessus)
local COLUMNS = 4
local CARD_SIZE = Vector2.new(172, 92)
local CARD_GAP = 12
local CARD_ICON = Vector2.new(136, 40)
-- Carte d'un skin à rareté : bande de couleur à gauche, libellé en haut, mini-rendu un peu plus bas et plus petit
local RARITY_STRIPE = 4
local RARITY_LABEL_Y = 5
local RARITY_ICON_TOP = 24
local RARITY_ICON = Vector2.new(126, 37) -- même rapport que CARD_ICON, tient entre le libellé et le nom
local SECTION_HEIGHT = 28 -- libellé « SKINS · ARME » entre les deux rangées
local SECTION_GAP = 20 -- écart entre la rangée des armes et ce libellé
local GRID_WIDTH = COLUMNS * CARD_SIZE.X + (COLUMNS - 1) * CARD_GAP
local SCROLL_STEP = CARD_SIZE.Y + CARD_GAP -- une rangée par cran de molette quand la souris n'est pas sur la grille
local PREVIEW_POSITION = Vector2.new(330, 76) -- rendu de l'arme montrée, à droite du titre
local PREVIEW_SIZE = Vector2.new(470, 210)
local SHOW_PREVIEW = true
local SLOT_LABELS = { sniper = "SNIPER", knife = "COUTEAU", outfit = "TENUE", effect = "EFFET" }
local OUTFIT_TAB = #InventoryRules.SLOTS + 1 -- onglet de la tenue de personnage (#521), après ceux des armes
local EFFECT_TAB = #InventoryRules.SLOTS + 2 -- onglet de l'effet de tir (#566), après la tenue
local TAB_COUNT = EFFECT_TAB
local EFFECT_TOOL = "AWP" -- arme tenue et cartes de l'onglet EFFET : la seule arme à distance
local DEMO_POLL = 0.1 -- s entre deux vérifications de la démonstration de l'onglet EFFET (écran affiché ou non)
local SCRIM_SIZE = Vector2.new(1100, 760) -- fond de coin sous la grille et le titre (décor clair possible)
local SCRIM_SHOWN = 0.2

-- Carte survolée : arme et skin, tenue (#521, `outfit` nil : tenue d'origine) dans l'onglet TENUE, ou effet de tir
-- (#566, `kind` "effect", `effect` nil : aucun) dans l'onglet EFFET
type Hover = { tool: string?, skin: string?, outfit: string?, kind: string?, effect: string? }
-- Texte à largeur automatique doublé de son ombre, pour une ligne qui enchaîne texte et étiquette
type Flow = { set: (string, { [string]: any }?) -> (), bind: (() -> string) -> (), label: TextLabel }

local tabChoices: { MenuShot.Choice } = {}
local scroller: ScrollingFrame -- zone défilante de la grille (armes, libellé des skins, skins) ; titres et onglets fixes
local grid: Frame
local previewHolder: Frame
local previews: { [string]: ViewportFrame } = {}
local slotTitle: Flow
local slotTag: TextLabel
local weaponName: Flow
local statusTag: TextLabel
local statusStroke: UIStroke
local rarityTag: TextLabel
local category: TextLabel
local categoryShadow: TextLabel
local selectedSlot = 1 -- emplacement actif : sa grille est affichée, le personnage tient son arme
local hover: Hover? = nil -- carte survolée : arme (et skin) montrés tant que la souris reste dessus
local screenRoot: GuiObject? = nil -- racine de l'écran : la démonstration n'est montrée que s'il est affiché
local demoToken = 0 -- suivi de la démonstration de l'onglet EFFET en cours (#575) ; changer le jeton l'arrête

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
		-- Texte français (+ paramètres) traduit, qui suit la langue
		set = function(fr: string, args: { [string]: any }?)
			Locale.apply(label, fr, args)
			Locale.apply(shadow, fr, args)
		end,
		-- Texte calculé par `produce` (déjà traduit), recalculé au changement de langue
		bind = function(produce: () -> string)
			Locale.bind(label, produce)
			Locale.bind(shadow, produce)
		end,
	}
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

-- Cette méthode permet d'afficher le rendu texturé de l'arme montrée, habillée de son skin (#268 ; un rendu par
-- viewmodel et par skin, gardé une fois construit) lorsque l'arme ou le skin montré change.
local function showPreview(toolName: string?, skinId: string?)
	if not SHOW_PREVIEW then
		return
	end
	local viewmodel = toolName and viewmodelOf(toolName)
	local key = viewmodel and (viewmodel .. "|" .. (skinId or ""))
	if viewmodel and key and not previews[key] then
		local viewport = UIKit.weaponSilhouette(previewHolder, viewmodel, PREVIEW_SIZE.X / PREVIEW_SIZE.Y, true, skinId)
		viewport.Name = "Preview" .. key
		previews[key] = viewport
	end
	for name, viewport in previews do
		viewport.Visible = name == key
	end
end

-- Cette méthode permet de nommer un skin (nom du catalogue, « D'ORIGINE » sans skin) lorsqu'une carte ou la ligne de
-- nom l'affiche.
local function skinTitle(skinId: string?): string
	local item = skinId and InventoryRules.item(skinId)
	return Rules.skinLabel(skinId, item and item.name)
end

-- Cette méthode permet de lire la rareté d'un skin (nil pour le skin d'origine ou un skin hors caisse) lorsqu'une carte
-- ou la ligne de nom la montre.
local function skinRarity(skinId: string?): ShopCatalog.Rarity?
	local item = skinId and InventoryRules.item(skinId)
	return if item then ShopCatalog.rarityOf(item) else nil
end

-- Cette méthode permet de choisir le texte d'une étiquette pleine à la couleur d'une rareté (sombre sur couleur claire,
-- os sur couleur foncée) lorsque la ligne de nom l'affiche.
local function tagTextColor(color: Color3): Color3
	local brightness = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return if brightness > 0.55 then C.Ground else C.Bone
end

-- Cette méthode permet de nommer une tenue (nom du catalogue, « D'ORIGINE » sans tenue) lorsqu'une carte ou la ligne de
-- nom l'affiche.
local function outfitTitle(outfitId: string?): string
	local item = outfitId and InventoryRules.item(outfitId)
	return if item and item.name then item.name else "D'ORIGINE"
end

-- Cette méthode permet de lire la rareté d'une tenue (nil pour la tenue d'origine) lorsqu'une carte ou la ligne de nom
-- la montre.
local function outfitRarity(outfitId: string?): ShopCatalog.Rarity?
	local item = outfitId and InventoryRules.item(outfitId)
	return if item then ShopCatalog.rarityOf(item) else nil
end

-- Cette méthode permet de donner la tenue montrée (carte survolée, sinon tenue équipée) et de dire si elle est équipée,
-- lorsque l'onglet TENUE met à jour sa ligne de nom et le personnage.
local function shownOutfit(): (string?, boolean)
	local equippedOutfit = InventoryRules.outfitOf(LocalInventory.equipped())
	if hover then
		return hover.outfit, hover.outfit == equippedOutfit
	end
	return equippedOutfit, true
end

-- Cette méthode permet de nommer un effet de tir (#566 ; « AUCUN » sans effet) lorsqu'une carte ou la ligne de nom
-- l'affiche.
local function effectTitle(effectId: string?): string
	local item = effectId and InventoryRules.item(effectId)
	return if item and item.name then item.name else "AUCUN"
end

-- Cette méthode permet de lire la rareté d'un effet de tir (#566 ; nil sans effet) lorsqu'une carte ou la ligne de nom
-- la montre.
local function effectRarity(effectId: string?): ShopCatalog.Rarity?
	local item = effectId and InventoryRules.item(effectId)
	return if item then ShopCatalog.rarityOf(item) else nil
end

-- Cette méthode permet de lire le skin d'AWP qui inspire un effet de tir (#566 ; nil : AWP d'origine) lorsque sa carte
-- dessine l'arme.
local function effectSkin(effectId: string?): string?
	local item = effectId and InventoryRules.item(effectId)
	return item and item.inspiredBy
end

-- Cette méthode permet de donner l'effet montré (carte survolée, sinon effet équipé) et de dire s'il est équipé, lorsque
-- l'onglet EFFET met à jour sa ligne de nom ou que la démonstration tire.
local function shownEffect(): (string?, boolean)
	local equippedEffect = InventoryRules.effectOf(LocalInventory.equipped())
	if hover and hover.kind == "effect" then
		return hover.effect, hover.effect == equippedEffect
	end
	return equippedEffect, true
end

-- Cette méthode permet de savoir si l'écran d'équipement est à l'écran (lui et ses parents visibles, interface activée)
-- lorsque la démonstration s'apprête à tirer.
local function isOnScreen(): boolean
	local node: Instance? = screenRoot
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled and node:IsDescendantOf(game)
		end
		node = node.Parent
	end
	return false
end

-- Cette méthode permet de montrer l'effet de l'onglet EFFET par la démonstration sur la map (#575) tant que l'écran est
-- affiché, et de la retirer sinon, lorsque l'effet montré change ou que le suivi vérifie l'écran.
local function syncDemo()
	if selectedSlot == EFFECT_TAB and isOnScreen() then
		EffectStage.play(ShotEffectRules.styleOf((shownEffect())))
	else
		EffectStage.stop()
	end
end

-- Cette méthode permet de suivre la démonstration de l'onglet EFFET lorsqu'il devient actif : vérifiée toutes les
-- DEMO_POLL s (écran quitté, menu fermé : elle se retire), tant que l'onglet reste actif ; tout autre onglet change le
-- jeton et l'arrête.
local function startDemo()
	demoToken += 1
	local token = demoToken
	EffectStage.prepare()
	task.spawn(function()
		while token == demoToken and selectedSlot == EFFECT_TAB do
			syncDemo()
			task.wait(DEMO_POLL)
		end
	end)
end

-- Cette méthode permet de poser la ligne de nom (étiquette de rareté, « ÉQUIPÉ » ou « CLIC POUR ÉQUIPER ») selon ce
-- qui est montré, lorsque l'en-tête d'un onglet d'arme ou de l'onglet TENUE se met à jour.
local function paintStatus(visible: boolean, isEquipped: boolean, rarity: ShopCatalog.Rarity?)
	statusTag.Visible = visible
	Locale.apply(statusTag, if isEquipped then "ÉQUIPÉ" else "CLIC POUR ÉQUIPER")
	statusTag.BackgroundTransparency = if isEquipped then 0 else 1
	statusStroke.Enabled = not isEquipped
	rarityTag.Visible = rarity ~= nil
	if rarity then
		local color = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		Locale.apply(rarityTag, rarity.label)
		rarityTag.BackgroundColor3 = color
		rarityTag.TextColor3 = tagTextColor(color)
	end
end

-- Cette méthode permet de mettre à jour l'en-tête de l'onglet TENUE (#521) : nom et rareté de la tenue montrée, pas de
-- rendu d'arme, et le personnage de l'accueil qui la porte.
local function paintOutfitHeader()
	slotTitle.set(slotLabel(InventoryRules.OUTFIT_SLOT))
	Locale.apply(slotTag, "EMPLACEMENT {n}", { n = OUTFIT_TAB })
	local outfit, isEquipped = shownOutfit()
	weaponName.bind(function()
		return Locale.t(outfitTitle(outfit))
	end)
	paintStatus(true, isEquipped, outfitRarity(outfit))
	Locale.apply(category, "PERSONNAGE")
	Locale.apply(categoryShadow, "PERSONNAGE")
	showPreview(nil, nil)
	MenuScene.previewOutfit(outfit)
end

-- Cette méthode permet de mettre à jour l'en-tête de l'onglet EFFET (#566) : nom et rareté de l'effet montré, skin qui
-- l'inspire, pas de rendu d'arme ; le personnage tient l'AWP dans son skin équipé (la démonstration tire avec).
local function paintEffectHeader()
	slotTitle.set(slotLabel(InventoryRules.EFFECT_SLOT))
	Locale.apply(slotTag, "EMPLACEMENT {n}", { n = EFFECT_TAB })
	local effect, isEquipped = shownEffect()
	weaponName.bind(function()
		return Locale.t(effectTitle(effect))
	end)
	paintStatus(true, isEquipped, effectRarity(effect))
	local skin = effectSkin(effect)
	local skinItem = skin and InventoryRules.item(skin)
	if skinItem and skinItem.name then
		Locale.apply(category, "EFFET DE TIR  ·  INSPIRÉ DE {skin}", { skin = skinItem.name })
		Locale.apply(categoryShadow, "EFFET DE TIR  ·  INSPIRÉ DE {skin}", { skin = skinItem.name })
	else
		Locale.apply(category, "EFFET DE TIR")
		Locale.apply(categoryShadow, "EFFET DE TIR")
	end
	showPreview(nil, nil)
	MenuScene.holdTool(EFFECT_TOOL, InventoryRules.skinOfTool(LocalInventory.equipped(), EFFECT_TOOL))
	syncDemo() -- l'effet survolé passe tout de suite dans la démonstration
end

-- Cette méthode permet de mettre à jour le titre, la ligne de nom (« ÉQUIPÉ » plein en rouge d'impact, sinon « CLIC POUR
-- ÉQUIPER » en contour), le rendu et l'arme du personnage lorsque le survol, l'emplacement ou l'équipement change.
local function paintHeader()
	if selectedSlot == OUTFIT_TAB then
		paintOutfitHeader()
		return
	end
	if selectedSlot == EFFECT_TAB then
		paintEffectHeader()
		return
	end
	local slotName = InventoryRules.SLOTS[selectedSlot]
	slotTitle.set(if slotName then slotLabel(slotName) else "")
	Locale.apply(slotTag, "EMPLACEMENT {n}", { n = selectedSlot })
	local tool, skin, isEquipped = shown()
	if tool then
		weaponName.bind(function()
			return string.format("%s  /  %s", Locale.t(weaponTitle(tool)), Locale.t(skinTitle(skin)))
		end)
	else
		weaponName.set("")
	end
	paintStatus(tool ~= nil, isEquipped, if tool then skinRarity(skin) else nil)
	local cfg = tool and WeaponConfig.Weapons[tool]
	local text = if cfg and cfg.Category then string.upper(cfg.Category) else ""
	Locale.apply(category, text)
	Locale.apply(categoryShadow, text)
	showPreview(tool, skin)
	if tool then
		MenuScene.holdTool(tool, skin)
	end
end

-- Cette méthode permet de marquer l'onglet de l'emplacement actif (boîte ambrée à texte sombre, MenuShot.boxChoice)
-- lorsque l'emplacement actif change.
local function paintTabs()
	for index, tab in tabChoices do
		tab.setSelected(selectedSlot == index)
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
-- `textured` (cartes de skins, #268) : mini-rendu de l'arme habillée de son skin au lieu de la silhouette plate.
-- `portrait` (cartes de tenues, #521) : buste du personnage habillé de la tenue `item.outfit`.
local function card(
	x: number,
	y: number,
	text: string,
	item: Hover,
	equipped: boolean,
	action: () -> (),
	textured: boolean?,
	portrait: boolean?
)
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
	local rarity = if item.kind == "effect"
		then effectRarity(item.effect)
		elseif portrait then outfitRarity(item.outfit)
		elseif textured then skinRarity(item.skin)
		else nil
	local iconSize, iconTop = CARD_ICON, 12
	if rarity then
		local color = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
		UIKit.frame({
			Name = "RarityStripe",
			BackgroundColor3 = color,
			Size = UDim2.new(0, RARITY_STRIPE, 1, 0),
			Parent = button,
		})
		UIKit.shadowedText(button, {
			Name = "Rarity",
			Text = rarity.label,
			FontFace = F.DisplayMedium,
			TextSize = UITheme.TextSize.Min,
			TextColor3 = color,
			Position = UDim2.fromOffset(RARITY_STRIPE + 8, RARITY_LABEL_Y),
			Size = UDim2.fromOffset(CARD_SIZE.X - RARITY_STRIPE - 36, 16),
			ZIndex = 2,
		}, 1)
		iconSize, iconTop = RARITY_ICON, RARITY_ICON_TOP
	end
	local icon = UIKit.frame({
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset((CARD_SIZE.X - iconSize.X) / 2, iconTop),
		Size = UDim2.fromOffset(iconSize.X, iconSize.Y),
		Parent = button,
	})
	-- Carte d'arme : silhouette plate teintée ; carte de skin : l'arme habillée de ce skin, sans teinte ; carte de tenue :
	-- portrait du personnage habillé
	local silhouette = if portrait
		then UIKit.outfitPortrait(icon, item.outfit, iconSize.X / iconSize.Y)
		else UIKit.weaponSilhouette(
			icon,
			viewmodelOf(item.tool or ""),
			iconSize.X / iconSize.Y,
			textured,
			item.skin
		)
	local restColor = if equipped then C.Bone else C.TextSoft
	local plain = textured or portrait
	local iconRest = if plain then C.White else restColor
	local iconHover = if plain then C.White else C.Bone
	silhouette.ImageColor3 = iconRest
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
		silhouette.ImageColor3 = iconHover
		paintHeader()
	end)
	button.MouseLeave:Connect(function()
		stroke.Color = C.Bone
		stroke.Transparency = restStroke
		UIKit.tween(label, Motion.Hover, { TextColor3 = restColor })
		silhouette.ImageColor3 = iconRest
		if hover == item then
			hover = nil
			paintHeader()
		end
	end)
	button.Activated:Connect(function()
		if not MenuShot.isBusy() then -- action exclusive en cours (aucune depuis #523 ; le serveur refuse EquipItem en partie)
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

-- Cette méthode permet de poser les cartes de l'onglet TENUE (#521) : tenue d'origine puis tenues possédées ; renvoie
-- la hauteur occupée.
local function fillOutfits(): number
	local owned = LocalInventory.owned()
	local equippedOutfit = InventoryRules.outfitOf(LocalInventory.equipped())
	local list: { { id: string? } } = { { id = nil } }
	for _, outfit in InventoryRules.outfits() do
		if owned[outfit.id] then
			table.insert(list, { id = outfit.id })
		end
	end
	local step = CARD_SIZE.X + CARD_GAP
	local y = 0
	for i, entry in list do
		local outfitId = entry.id
		y = ((i - 1) // COLUMNS) * (CARD_SIZE.Y + CARD_GAP)
		card(
			((i - 1) % COLUMNS) * step,
			y,
			outfitTitle(outfitId),
			{ outfit = outfitId },
			outfitId == equippedOutfit,
			function()
				LocalInventory.equip(InventoryRules.OUTFIT_SLOT, outfitId or "", nil)
			end,
			nil,
			true
		)
	end
	fillRow(#list, y)
	return y + CARD_SIZE.Y
end

-- Cette méthode permet de poser les cartes de l'onglet EFFET (#566) : « aucun » puis effets possédés, du plus courant au
-- plus rare, chacun sur l'AWP dans le skin qui l'inspire ; renvoie la hauteur occupée.
local function fillEffects(): number
	local owned = LocalInventory.owned()
	local equippedEffect = InventoryRules.effectOf(LocalInventory.equipped())
	local list: { { id: string? } } = { { id = nil } }
	for _, effect in InventoryRules.effects() do
		if owned[effect.id] then
			table.insert(list, { id = effect.id })
		end
	end
	local step = CARD_SIZE.X + CARD_GAP
	local y = 0
	for i, entry in list do
		local effectId = entry.id
		y = ((i - 1) // COLUMNS) * (CARD_SIZE.Y + CARD_GAP)
		card(
			((i - 1) % COLUMNS) * step,
			y,
			effectTitle(effectId),
			{ kind = "effect", effect = effectId, tool = EFFECT_TOOL, skin = effectSkin(effectId) },
			effectId == equippedEffect,
			function()
				LocalInventory.equip(InventoryRules.EFFECT_SLOT, effectId or "", nil)
			end,
			true
		)
	end
	fillRow(#list, y)
	return y + CARD_SIZE.Y
end

-- Cette méthode permet de poser les cartes (armes possédées de l'emplacement actif, puis skins possédés de son arme
-- équipée) lorsque la grille se reconstruit ; renvoie la hauteur occupée, pour la zone défilante.
local function fillGrid(): number
	if selectedSlot == OUTFIT_TAB then
		return fillOutfits()
	end
	if selectedSlot == EFFECT_TAB then
		return fillEffects()
	end
	local slotName = InventoryRules.SLOTS[selectedSlot]
	if not slotName then
		return 0
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
		return y + CARD_SIZE.Y
	end
	local currentTool: string = current.tool
	local weaponId = current.id
	y += CARD_SIZE.Y + SECTION_GAP
	UIKit.accentLabel(grid, {
		Name = "SkinsTitle",
		Text = "SKINS  ·  {weapon}",
		TextArgs = { weapon = weaponTitle(currentTool) },
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
		card(((i - 1) % COLUMNS) * step, rowY, skinTitle(skinId), item, skinId == currentSkin, function()
			LocalInventory.equip(slotName, weaponId, skinId)
		end, true)
	end
	fillRow(#skins, rowY)
	return rowY + CARD_SIZE.Y
end

-- Cette méthode permet de reconstruire la grille et d'ajuster la hauteur défilable lorsque l'emplacement actif ou
-- l'équipement change (la position de défilement est gardée : équiper un skin du bas ne remonte pas la liste).
local function rebuildGrid()
	for _, child in grid:GetChildren() do
		child:Destroy()
	end
	hover = nil -- les cartes survolées disparaissent
	local height = fillGrid()
	grid.Size = UDim2.fromOffset(GRID_WIDTH, height)
	scroller.CanvasSize = UDim2.fromOffset(0, height + 2 * GRID_PAD)
end

-- Cette méthode permet de faire défiler la grille d'une rangée par cran de molette lorsque la souris est ailleurs sur
-- l'accueil ; sur la grille, la zone défilante s'en charge seule.
local function scrollGrid(direction: number)
	local mouse = UserInputService:GetMouseLocation()
	local origin, size = scroller.AbsolutePosition, scroller.AbsoluteSize
	local inside = mouse.X >= origin.X
		and mouse.X <= origin.X + size.X
		and mouse.Y >= origin.Y
		and mouse.Y <= origin.Y + size.Y
	local canvas = scroller.AbsoluteCanvasSize.Y
	local height = scroller.CanvasSize.Y.Offset
	if inside or direction == 0 or canvas <= 0 or height <= 0 then
		return
	end
	-- CanvasPosition est en pixels écran : le pas suit l'échelle de l'accueil (UIScale), mesuré en Studio
	local step = SCROLL_STEP * canvas / height
	local bottom = math.max(0, canvas - scroller.AbsoluteWindowSize.Y)
	scroller.CanvasPosition = Vector2.new(0, math.clamp(scroller.CanvasPosition.Y - direction * step, 0, bottom))
end

-- Cette méthode permet de rendre un emplacement actif (sa grille, son arme dans les mains du personnage) lorsque le
-- joueur clique son onglet ou tape sa touche ; une autre grille repart du haut.
local function selectSlot(index: number)
	local entering = index ~= selectedSlot
	if entering then
		scroller.CanvasPosition = Vector2.zero
	end
	selectedSlot = index
	if index ~= OUTFIT_TAB then
		MenuScene.endOutfitPreview() -- hors de l'onglet TENUE, le personnage porte la tenue équipée
	end
	rebuildGrid()
	paintTabs()
	paintHeader()
	if index ~= EFFECT_TAB then
		demoToken += 1 -- arrête la démonstration de l'onglet EFFET
		EffectStage.stop()
	elseif entering or demoToken == 0 then
		startDemo()
	end
end

-- Cette méthode permet d'arrêter la grille au-dessus de la fiche de statistiques lorsque la fenêtre est trop étroite
-- pour les mettre côte à côte (16:10, 4:3) ; en 16:9 la grille descend jusqu'à l'aide.
local function avoidStats(stats: GuiObject, reserved: number)
	local function update()
		local scale = scroller.AbsoluteSize.X / scroller.Size.X.Offset -- échelle de l'accueil (UIScale)
		local right = scroller.AbsolutePosition.X + scroller.AbsoluteSize.X
		local overlaps = stats.AbsolutePosition.X < right + STATS_GAP * scale
		local bottom = if overlaps then math.max(GRID_BOTTOM, reserved + STATS_GAP) else GRID_BOTTOM
		scroller.Size = UDim2.new(scroller.Size.X, UDim.new(1, -(GRID_Y - GRID_PAD + bottom)))
	end
	stats:GetPropertyChangedSignal("AbsolutePosition"):Connect(update)
	scroller:GetPropertyChangedSignal("AbsolutePosition"):Connect(update)
	update()
end

-- Cette méthode permet de construire l'aide en bas à gauche (touche en boîte, action en texte) lorsque l'écran est
-- construit.
local function buildHints(root: Frame)
	local row = UIKit.hintRow(root, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -18),
	})
	UIKit.keyHint(row, 1, "MOLETTE", "DÉFILER")
	UIKit.keyHint(row, 2, "CLIC", "ÉQUIPER")
	UIKit.keyHint(row, 3, nil, "ENREGISTRÉ AUSSITÔT")
end

-- Cette méthode permet de construire l'écran (titre, rendu, nom, onglets et grille dans `column` à gauche, aide en bas
-- à gauche) lorsque l'accueil est construit ; il suit ensuite chaque changement d'inventaire. La grille évite `stats`
-- (fiche de statistiques, `reserved` px au-dessus du bas) quand elles ne tiennent pas côte à côte.
function EquipmentScreen.build(root: Frame, column: Frame, stats: GuiObject, reserved: number)
	screenRoot = column
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
	slotTag = UIKit.tag(slotRow, "SlotTag", 2, C.Accent, C.Ground)
	previewHolder = UIKit.frame({
		Name = "Preview",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PREVIEW_POSITION.X, PREVIEW_POSITION.Y),
		Size = UDim2.fromOffset(PREVIEW_SIZE.X, PREVIEW_SIZE.Y),
		Parent = column,
	})
	local nameRow = flowRow(column, "WeaponName", NAME_Y, NAME_SIZE + 6)
	weaponName = flowText(nameRow, "Weapon", NAME_SIZE, 2)
	rarityTag = UIKit.tag(nameRow, "Rarity", 2, C.Bone, C.Ground)
	rarityTag.Visible = false
	statusTag = UIKit.tag(nameRow, "Status", 3, C.HitRed, C.Bone)
	statusStroke = UIKit.stroke(statusTag, C.Bone, 1)
	statusStroke.Transparency = 0.4
	category, categoryShadow = UIKit.shadowedText(column, {
		Name = "Category",
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(EDGE + 1, CATEGORY_Y),
		Size = UDim2.fromOffset(400, 18),
		ZIndex = 2,
	}, 1)
	local tabRow = UIKit.frame({
		Name = "SlotTabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, TABS_Y),
		Size = UDim2.fromOffset(GRID_WIDTH, 30),
		Parent = column,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, TAB_GAP),
		Parent = tabRow,
	})
	local tabSlots = table.clone(InventoryRules.SLOTS) :: { string }
	table.insert(tabSlots, InventoryRules.OUTFIT_SLOT) -- TENUE (#521), après les armes
	table.insert(tabSlots, InventoryRules.EFFECT_SLOT) -- EFFET (#566), après la tenue
	for index, slotName in tabSlots do
		tabChoices[index] = MenuShot.boxChoice({
			text = string.format("%d  ·  %s", index, slotLabel(slotName)),
			layoutOrder = index,
			parent = tabRow,
			action = function()
				selectSlot(index)
			end,
		})
	end
	-- Les cartes gardent leur place (EDGE, GRID_Y) : la zone déborde de GRID_PAD autour d'elles, barre à droite
	scroller = UIKit.create("ScrollingFrame", {
		Name = "EquipScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(EDGE - GRID_PAD, GRID_Y - GRID_PAD),
		Size = UDim2.new(0, GRID_WIDTH + 2 * GRID_PAD + SCROLL_GAP + SCROLL_BAR, 1, -(GRID_Y - GRID_PAD + GRID_BOTTOM)),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLL_BAR,
		ScrollBarImageColor3 = C.Accent,
		CanvasSize = UDim2.fromOffset(0, 0),
		Parent = column,
	})
	grid = UIKit.frame({
		Name = "EquipGrid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(GRID_PAD, GRID_PAD),
		Size = UDim2.fromOffset(GRID_WIDTH, 0),
		Parent = scroller,
	})
	avoidStats(stats, reserved)
	buildHints(root)
	selectSlot(selectedSlot)
	LocalInventory.onChanged(function()
		selectSlot(selectedSlot)
	end)
end

-- Cette méthode permet de changer d'emplacement actif au clavier (touches des emplacements réglées par le joueur, 1 et 2
-- par défaut) ou de faire défiler la grille à la molette (sens naturel, hors réglage) lorsque le joueur est sur l'accueil.
function EquipmentScreen.onInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		scrollGrid(math.sign(input.Position.Z))
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local index = PlayerSettings.slotForKey(LocalSettings.get().slotKeys, input.KeyCode.Name)
		if index and InventoryRules.SLOTS[index] then
			selectSlot(index)
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR1 or input.KeyCode == Enum.KeyCode.ButtonL1 then
		-- Manette (#276) : R1 / L1 passent à l'emplacement suivant / précédent, comme la barre d'armes en partie
		local step = if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1
		selectSlot((selectedSlot - 1 + step) % TAB_COUNT + 1)
	end
end

-- Cette méthode permet de remettre l'écran à l'arrivée (SNIPER actif, grille en haut, aucun survol) lorsque le joueur
-- quitte l'accueil ou revient au menu.
function EquipmentScreen.reset()
	if not grid then
		return
	end
	for _, tab in tabChoices do
		tab.reset()
	end
	scroller.CanvasPosition = Vector2.zero
	selectSlot(1)
end

return EquipmentScreen

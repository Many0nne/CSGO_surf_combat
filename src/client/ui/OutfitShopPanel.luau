-- Vue détail d'une tenue au shop (#543, docs/ui.md « Portant des tenues », planche validée le 18/11/2026) : colonne de
-- gauche comme la vue détail des caisses (ShopScreen), la tenue portée par le personnage debout sur le socle
-- (ShopScene.showOutfit). « ‹ SHOP » (retour au portant), nom, « TENUE DE PERSONNAGE » et rareté, deux lignes de
-- description, où l'équiper, prix (jeton, montant, CRÉDITS), ACHETER, tenue voisine (‹ TENUE n / N ›), aide « GLISSER ·
-- LA TOURNER ». ACHETER (remote `BuyOutfit`, OutfitService) : achat direct en crédits, sans tirage ; une tenue possédée
-- montre POSSÉDÉE en rouge d'impact (rouge = à moi), sans clic, et s'équipe dans l'onglet TENUE de l'équipement.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local Locale = require(Shared:WaitForChild("Locale"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WalletRules = require(Shared:WaitForChild("WalletRules"))
local ShopScene = require(script.Parent.Parent.systems.game.ShopScene)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local PurchaseStatus = require(script.Parent.PurchaseStatus)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local OutfitShopPanel = {}

-- Mise en page (px à 720 de haut), alignée sur la vue détail des caisses (ShopScreen)
local EDGE = MenuPage.Edge
local LABEL_Y = MenuPage.TitleY
local LABEL_SIZE = 20
local TITLE_Y = LABEL_Y + 24
local TITLE_SIZE = MenuPage.TitleSize
local SUBTITLE_Y = TITLE_Y + TITLE_SIZE + 10
local DESCRIPTION_Y = SUBTITLE_Y + 38
local DESCRIPTION_SIZE = 20
local DESCRIPTION_HEIGHT = 2 * 26 -- deux lignes
local EQUIP_Y = DESCRIPTION_Y + DESCRIPTION_HEIGHT + 8
local FILET_Y = EQUIP_Y + 30
local PRICE_Y = FILET_Y + 14
local PRICE_SIZE = 44
local PRICE_ICON = 34
local PRICE_ICON_LIFT = 6
local ACTIONS_Y = PRICE_Y + PRICE_SIZE + 26
local COLUMN_WIDTH = 470
local BUY_SIZE = Vector2.new(160, 42)
local STATUS_GAP = 10
local BUY_TEXT = "ACHETER"
local BUYING_TEXT = "ACHAT…"
local OWNED_TEXT = "POSSÉDÉE"
local BOUGHT_TEXT = "ACHETÉE  ·  À ÉQUIPER DANS ÉQUIPEMENT"
local REFUSALS = PurchaseStatus.labels(PurchaseStatus.OUTFIT_REFUSALS)

local panel: Frame
local title: { TextLabel }
local rarityTag: TextLabel
local description: { TextLabel }
local price: { TextLabel }
local position: TextLabel
local buyButton: Frame
local buyStroke: UIStroke
local buyChoice: MenuShot.Choice
local ownedBox: Frame
local status: TextLabel
local navigation: { MenuShot.Choice } = {}
local current = 1
local requesting = false
-- Numéro de la vue affichée, augmenté à chaque changement (tenue, retour, shop fermé) : un message arrivé après un
-- changement n'est plus affiché
local view = 0
local onBack: () -> () = function() end
local onChanged: () -> () = function() end

-- Cette méthode permet de poser un texte à ombre décalée dans la colonne lorsque la vue est construite ; renvoie le texte
-- et son ombre.
local function label(parent: GuiObject, props: { [string]: any }, offset: number): { TextLabel }
	props.ZIndex = 2
	local text, shadow = UIKit.shadowedText(parent, props, offset)
	return { text, shadow }
end

-- Cette méthode permet de changer un texte et son ombre ensemble (français, traduit et suivi au changement de langue)
-- lorsqu'un libellé de la vue change.
local function setText(pair: { TextLabel }, text: string, args: { [string]: any }?)
	for _, item in pair do
		Locale.apply(item, text, args)
	end
end

-- Cette méthode permet de changer le texte d'un choix et de son ombre ensemble lorsqu'un bouton change d'état.
local function setChoiceText(choice: MenuShot.Choice, text: string)
	for _, name in { "Label", "LabelShadow" } do
		local item = choice.button:FindFirstChild(name, true)
		if item and item:IsA("TextLabel") then
			Locale.apply(item, text)
		end
	end
end

-- Cette méthode permet de savoir si le joueur local possède la tenue affichée (attribut informatif `OwnedItems`) lorsque
-- ACHETER se peint.
local function ownsCurrent(): boolean
	local item = ShopScene.outfits()[current]
	if not item then
		return false
	end
	local owned = InventoryRules.decode(Players.LocalPlayer:GetAttribute(InventoryRules.ATTRIBUTE))
	return owned[item.id] == true
end

-- Cette méthode permet de peindre ACHETER (actif, « ACHAT… » pendant l'achat) ou POSSÉDÉE à sa place, et la tenue voisine
-- (figée pendant l'achat) lorsque la vue s'affiche, qu'un achat part ou revient, ou que l'inventaire change.
local function paintActions()
	if not panel then
		return
	end
	local owned = ownsCurrent()
	buyButton.Visible = not owned
	ownedBox.Visible = owned
	buyChoice.setEnabled(not requesting)
	setChoiceText(buyChoice, if requesting then BUYING_TEXT else BUY_TEXT)
	buyStroke.Color = if requesting then C.Muted else C.Bone
	for _, choice in navigation do
		choice.setEnabled(not requesting)
	end
	onChanged()
end

-- Cette méthode permet d'afficher un message sous ACHETER (refus en rouge d'impact, achat réussi en ambre) lorsque le
-- serveur répond.
local showStatus = PurchaseStatus.presenter(function()
	return status
end)

-- Cette méthode permet de remplir la vue pour la tenue courante (nom, rareté, description, prix, place dans la liste)
-- lorsque le joueur en ouvre une ou passe à la voisine.
local function paint()
	local list = ShopScene.outfits()
	local item = list[current]
	if not item then
		return
	end
	setText(title, item.name or item.id)
	local rarity = ShopCatalog.rarity(item.rarity)
	rarityTag.Visible = rarity ~= nil
	if rarity then
		Locale.apply(rarityTag, rarity.label)
		rarityTag.BackgroundColor3 = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
	end
	setText(description, item.description or "")
	setText(price, WalletRules.format(item.price or 0))
	Locale.apply(position, "TENUE  {n} / {total}", { n = current, total = #list })
	status.Visible = false
	paintActions()
end

-- Cette méthode permet de demander l'achat de la tenue courante au serveur lorsque le joueur clique ACHETER ; un achat à
-- la fois, tenue voisine et retour figés jusqu'à la réponse.
local function buy()
	local item = ShopScene.outfits()[current]
	if requesting or not item or ownsCurrent() then
		return
	end
	requesting = true
	local seen = view
	paintActions()
	task.spawn(function()
		local remote = ReplicatedStorage:FindFirstChild(NetworkProtocol.Names.BUY_OUTFIT)
		local ok, result = false, nil
		if remote and remote:IsA("RemoteFunction") then
			ok, result = pcall(function()
				return remote:InvokeServer(item.id)
			end)
		end
		requesting = false
		paintActions()
		-- Vue changée ou shop fermé : une tenue achetée est déjà possédée (l'étiquette du portant et ACHETER le disent)
		if view ~= seen or not panel.Visible then
			return
		end
		if not (ok and type(result) == "table") then
			showStatus(PurchaseStatus.text(REFUSALS, nil))
		elseif result.ok then
			showStatus(BOUGHT_TEXT, true)
		else
			showStatus(PurchaseStatus.text(REFUSALS, result.reason))
		end
	end)
end

-- Cette méthode permet de montrer la tenue `index` du portant (personnage sur le socle, colonne remplie) lorsque le
-- joueur la clique au portant ou passe à la voisine.
function OutfitShopPanel.open(index: number)
	if not ShopScene.outfits()[index] then
		return
	end
	current = index
	view += 1
	panel.Visible = true
	paint()
	ShopScene.showOutfit(index)
end

-- Cette méthode permet de masquer la vue (retour au portant ou à la vitrine, shop fermé) lorsque l'écran change de vue.
function OutfitShopPanel.close()
	view += 1
	if panel then
		panel.Visible = false
		status.Visible = false
	end
end

-- Cette méthode permet de savoir si la vue détail d'une tenue est affichée lorsque l'écran relève sa vue (analytics,
-- bouton des packs).
function OutfitShopPanel.isVisible(): boolean
	return panel ~= nil and panel.Visible
end

-- Cette méthode permet de savoir si un achat de tenue attend la réponse du serveur lorsque l'écran décide d'ouvrir une
-- fenêtre par-dessus (packs de crédits).
function OutfitShopPanel.isBusy(): boolean
	return requesting
end

-- Cette méthode permet de construire la vue détail d'une tenue dans la colonne du shop (`column`) et son aide en bas à
-- droite lorsque l'écran Shop est construit ; `back` ramène au portant, `changed` suit chaque changement d'état.
function OutfitShopPanel.build(column: Frame, back: () -> (), changed: () -> ())
	onBack, onChanged = back, changed
	panel = UIKit.frame({
		Name = "OutfitDetail",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = column,
	})
	local backChoice = MenuShot.textChoice({
		text = "‹  SHOP",
		font = F.DisplayMedium,
		size = LABEL_SIZE,
		color = C.TextSoft,
		position = UDim2.fromOffset(EDGE, LABEL_Y),
		parent = panel,
		action = function()
			onBack()
		end,
	})
	table.insert(navigation, backChoice)
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		backChoice.reset()
	end)
	title = label(panel, {
		Name = "Title",
		FontFace = F.Display,
		TextSize = TITLE_SIZE,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE, TITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, TITLE_SIZE + 6),
	}, 3)
	-- « TENUE DE PERSONNAGE » en ambre, puis la rareté en boîte de sa couleur
	local kind = UIKit.frame({
		Name = "Kind",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE + 1, SUBTITLE_Y - 3),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 24),
		Parent = panel,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = kind,
	})
	-- Texte et ombre dans leur propre cadre : posés directement dans la ligne, la mise en page les rangeait côte à côte
	local kindHolder = UIKit.frame({
		Name = "KindHolder",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		LayoutOrder = 1,
		Parent = kind,
	})
	local kindText, kindShadow = UIKit.accentLabel(kindHolder, {
		Name = "Kind",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
	})
	setText({ kindText, kindShadow }, "TENUE DE PERSONNAGE")
	rarityTag = UIKit.tag(kind, "Rarity", 2, C.Accent, C.Bone)
	rarityTag.Size = UDim2.fromOffset(0, 20)
	rarityTag.TextSize = 16
	description = label(panel, {
		Name = "Description",
		FontFace = F.DisplayText, -- une seule famille dans les menus (#308)
		TextSize = DESCRIPTION_SIZE,
		TextColor3 = C.Bone,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(EDGE, DESCRIPTION_Y),
		Size = UDim2.fromOffset(380, DESCRIPTION_HEIGHT),
	}, 1)
	local equip = label(panel, {
		Name = "Equip",
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(EDGE, EQUIP_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 20),
	}, 1)
	setText(equip, "S'ÉQUIPE DANS ÉQUIPEMENT  ·  TENUE")
	UIKit.frame({
		Name = "Filet",
		Position = UDim2.fromOffset(EDGE, FILET_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 1),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.88,
		Parent = panel,
	})
	local priceRow = UIKit.frame({
		Name = "Price",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, PRICE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, PRICE_SIZE + 4),
		Parent = panel,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
		Parent = priceRow,
	})
	-- Jeton remonté comme celui des caisses : aligné sur le bas de la boîte du texte, il tombait sous les chiffres
	local coin = UIKit.creditIcon(priceRow, PRICE_ICON, 2, { LayoutOrder = 0 })
	coin.Size = UDim2.fromOffset(PRICE_ICON, PRICE_ICON + PRICE_ICON_LIFT)
	UIKit.create("UIPadding", { PaddingBottom = UDim.new(0, PRICE_ICON_LIFT), Parent = coin })
	local amount = UIKit.frame({
		Name = "Amount",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = priceRow,
	})
	price = label(amount, {
		Name = "Value",
		FontFace = F.Display,
		TextSize = PRICE_SIZE,
		TextColor3 = C.Bone,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
	}, 3)
	UIKit.text({
		Name = "Currency",
		Text = ShopCatalog.CURRENCY,
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.TextSoft,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 2,
		Parent = priceRow,
	})
	local actions = UIKit.frame({
		Name = "Actions",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, ACTIONS_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, BUY_SIZE.Y),
		Parent = panel,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 18),
		Parent = actions,
	})
	-- ACHETER : contour os, survol en rouge d'impact, comme celui des caisses
	buyButton = UIKit.frame({
		Name = "Buy",
		Size = UDim2.fromOffset(BUY_SIZE.X, BUY_SIZE.Y),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = actions,
	})
	buyStroke = UIKit.stroke(buyButton, C.Bone, 2)
	buyChoice = MenuShot.textChoice({
		text = BUY_TEXT,
		font = F.Display,
		size = 24,
		color = C.Bone,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		parent = buyButton,
		action = buy,
	})
	-- POSSÉDÉE à la place d'ACHETER : plein en rouge d'impact (rouge = à moi, comme ÉQUIPÉ), sans clic
	ownedBox = UIKit.frame({
		Name = "Owned",
		Size = UDim2.fromOffset(BUY_SIZE.X, BUY_SIZE.Y),
		BackgroundColor3 = C.HitRed,
		LayoutOrder = 1,
		Visible = false,
		Parent = actions,
	})
	local ownedText = UIKit.text({
		Name = "Label",
		FontFace = F.Display,
		TextSize = 24,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = ownedBox,
	})
	Locale.apply(ownedText, OWNED_TEXT)
	-- Tenue voisine : ‹ TENUE n / N ›
	local function arrow(glyph: string, order: number, step: number)
		local choice = MenuShot.textChoice({
			text = glyph,
			font = F.Display,
			size = 22,
			color = C.TextSoft,
			layoutOrder = order,
			parent = actions,
			action = function()
				OutfitShopPanel.open(ShopCatalog.cycle(current, step, #ShopScene.outfits()))
			end,
		})
		table.insert(navigation, choice)
	end
	arrow("‹", 2, -1)
	position = UIKit.text({
		Name = "Position",
		FontFace = F.DisplayMedium,
		TextSize = 18,
		TextColor3 = C.TextSoft,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, BUY_SIZE.Y),
		LayoutOrder = 3,
		Parent = actions,
	})
	arrow("›", 4, 1)
	status = UIKit.tag(panel, "Status", 0, C.HitRed, C.Bone)
	status.Position = UDim2.fromOffset(EDGE, ACTIONS_Y + BUY_SIZE.Y + STATUS_GAP)
	status.ZIndex = 3
	status.Visible = false
	-- Aide en bas à droite (la colonne tient la gauche), comme l'aperçu des skins
	local hints = UIKit.hintRow(column, {
		Name = "OutfitHints",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE, 1, -18),
		Visible = false,
	})
	UIKit.keyHint(hints, 1, "GLISSER", "LA TOURNER")
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		hints.Visible = panel.Visible
	end)
	-- Tenue achetée (ici ou sur un autre serveur) : POSSÉDÉE remplace ACHETER
	Players.LocalPlayer:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(paintActions)
end

return OutfitShopPanel

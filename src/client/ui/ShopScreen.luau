-- Écran Shop (#347, onglet SHOP du menu, docs/ui.md « Shop ») : interface posée sur la salle de présentation
-- (ShopScene), colonne à gauche sur fond de coin comme l'écran d'équipement. Vue d'ensemble : titre « CAISSES », les
-- caisses en vente sont dans la vitrine (nom et prix sur leur étiquette), un clic sur une caisse ouvre la vue détail.
-- Vue détail : « ‹ SHOP » (retour à la vitrine), nom de la caisse, contenu par rareté avec ses chances, prix, ACHETER
-- (inactif tant que l'achat n'existe pas, étiquette BIENTÔT) et passage à la caisse voisine.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local ShopScene = require(script.Parent.Parent.systems.game.ShopScene)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local ShopScreen = {}

-- Mise en page (px à 720 de haut), d'après la planche validée (docs/ui/shop/)
local EDGE = MenuPage.Edge
local LABEL_Y = MenuPage.TitleY -- « SHOP » au-dessus du grand titre
local LABEL_SIZE = 20
local TITLE_Y = LABEL_Y + 24
local TITLE_SIZE = MenuPage.TitleSize
local SUBTITLE_Y = TITLE_Y + TITLE_SIZE + 10
local ROWS_Y = SUBTITLE_Y + 38
local ROW_STEP = 32
local ROW_TEXT = 20
local RARITY_X = 250 -- colonne des raretés et chances
local COLUMN_WIDTH = 440
local BUY_SIZE = Vector2.new(160, 42)
local PRICE_SIZE = 44
-- Fond sombre de la colonne, sur toute la hauteur et effacé vers la droite (planche) : le fond de coin de l'écran
-- d'équipement ne fonçait que le bas, le titre restait sur les caisses éclairées du rack de gauche
local VEIL_WIDTH = 760
local VEIL = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(0.45, 0.45),
	NumberSequenceKeypoint.new(1, 1),
})

local gui: ScreenGui
local overview: Frame
local detail: Frame
local rows: Frame
local filet: Frame
local priceRow: Frame
local actions: Frame
local title: { TextLabel }
local subtitle: { TextLabel }
local countLabel: { TextLabel }
local price: { TextLabel }
local position: TextLabel
local back: MenuShot.Choice
local current = 1
local lines: { Frame } = {} -- lignes du contenu de la caisse ouverte, dans l'ordre de ShopCatalog.contents
local DIMMED = 0.65 -- atténuation des autres lignes quand une arme du tableau est en gros plan (#358)

-- Cette méthode permet de changer un texte et son ombre ensemble lorsqu'un libellé de l'écran change.
local function setText(pair: { TextLabel }, text: string)
	for _, label in pair do
		label.Text = text
	end
end

-- Cette méthode permet de convertir une couleur du catalogue ({ r, g, b }) en Color3 lorsqu'une rareté est affichée.
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Cette méthode permet de poser un texte à ombre décalée dans la colonne lorsque l'écran est construit ; renvoie le
-- texte et son ombre.
local function label(parent: GuiObject, props: { [string]: any }, offset: number): { TextLabel }
	props.ZIndex = 2
	local text, shadow = UIKit.shadowedText(parent, props, offset)
	return { text, shadow }
end

-- Cette méthode permet de mettre en avant la ligne du skin dont l'arme est en gros plan (#358), les autres atténuées,
-- lorsque le gros plan change ; `row` nil rend toutes les lignes (transparence d'origine gardée en attribut).
local function highlightRow(row: number?)
	for i, line in lines do
		local dim = if row and i ~= row then DIMMED else 0
		for _, item in line:GetDescendants() do
			if item:IsA("TextLabel") then
				local base = item:GetAttribute("BaseTransparency")
				if type(base) ~= "number" then
					base = item.TextTransparency
					item:SetAttribute("BaseTransparency", base)
				end
				item.TextTransparency = base + (1 - base) * dim
			elseif item:IsA("Frame") then
				local base = item:GetAttribute("BaseTransparency")
				if type(base) ~= "number" then
					base = item.BackgroundTransparency
					item:SetAttribute("BaseTransparency", base)
				end
				item.BackgroundTransparency = base + (1 - base) * dim
			end
		end
	end
end

-- Cette méthode permet de remplir la vue détail pour la caisse courante (nom, contenu par rareté, prix, place dans la
-- liste) lorsque le joueur ouvre une caisse ou passe à la voisine.
local function paintDetail()
	local crate = ShopCatalog.CRATES[current]
	if not crate then
		return
	end
	setText(title, crate.name)
	setText(subtitle, ShopCatalog.subtitle(crate, InventoryRules.ITEMS))
	for _, child in rows:GetChildren() do
		child:Destroy()
	end
	table.clear(lines)
	local contents = ShopCatalog.contents(crate, InventoryRules.ITEMS)
	for i, row in contents do
		local color = rgb(row.rarity.color)
		local line = UIKit.frame({
			Name = "Row" .. i,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, (i - 1) * ROW_STEP),
			Size = UDim2.fromOffset(COLUMN_WIDTH, ROW_STEP),
			Parent = rows,
		})
		lines[i] = line
		UIKit.frame({
			Name = "Bar",
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.fromOffset(4, ROW_TEXT),
			BackgroundColor3 = color,
			Parent = line,
		})
		label(line, {
			Name = "Skin",
			Text = table.concat(row.weapons, " · ") .. "   " .. row.name,
			FontFace = F.DisplayText,
			TextSize = ROW_TEXT,
			TextColor3 = C.Bone,
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.fromOffset(RARITY_X - 16, ROW_STEP),
		}, 2)
		label(line, {
			Name = "Rarity",
			Text = string.format("%s  %d %%", row.rarity.label, row.rarity.chance),
			FontFace = F.Display,
			TextSize = 18,
			TextColor3 = color,
			Position = UDim2.fromOffset(RARITY_X, 0),
			Size = UDim2.fromOffset(COLUMN_WIDTH - RARITY_X, ROW_STEP),
		}, 1)
	end
	local below = ROWS_Y + #contents * ROW_STEP + 10
	filet.Position = UDim2.fromOffset(EDGE, below)
	priceRow.Position = UDim2.fromOffset(EDGE, below + 14)
	actions.Position = UDim2.fromOffset(EDGE, below + 14 + PRICE_SIZE + 26)
	setText(price, tostring(crate.price))
	position.Text = string.format("CAISSE  %d / %d", current, #ShopCatalog.CRATES)
end

-- Cette méthode permet d'ouvrir la vue détail d'une caisse (glissement de la caméra jusqu'au socle) lorsque le joueur
-- la clique dans la vitrine ou passe à la voisine.
local function openCrate(index: number)
	if not ShopCatalog.CRATES[index] then
		return
	end
	current = index
	overview.Visible = false
	detail.Visible = true
	paintDetail()
	ShopScene.showCrate(index)
end

-- Cette méthode permet de revenir à la vitrine (toutes les caisses) lorsque le joueur clique « ‹ SHOP » ou que l'écran
-- s'ouvre.
local function openOverview()
	overview.Visible = true
	detail.Visible = false
	back.reset()
	ShopScene.showOverview()
end

-- Cette méthode permet de construire la vue d'ensemble (titre, nombre de caisses, aide en bas à gauche) lorsque l'écran
-- est construit.
local function buildOverview(column: Frame, root: Frame)
	overview =
		UIKit.frame({ Name = "Overview", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = column })
	label(overview, {
		Name = "Label",
		Text = "SHOP",
		FontFace = F.DisplayMedium,
		TextSize = LABEL_SIZE,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(EDGE, LABEL_Y),
		Size = UDim2.fromOffset(200, LABEL_SIZE + 4),
	}, 2)
	label(overview, {
		Name = "Title",
		Text = "CAISSES",
		FontFace = F.Display,
		TextSize = TITLE_SIZE,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE, TITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, TITLE_SIZE + 6),
	}, 3)
	local text, shadow = UIKit.accentLabel(overview, {
		Name = "Count",
		Position = UDim2.fromOffset(EDGE + 1, SUBTITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 18),
	})
	countLabel = { text, shadow }
	setText(countLabel, string.format("%d EN VENTE  ·  UNE PAR SÉRIE DE SKINS", #ShopCatalog.CRATES))
	-- L'aide n'est pas dans la colonne (qui descend sous la barre de Roblox) : elle tient le bas de l'écran
	local hints = UIKit.hintRow(root, {
		Name = "OverviewHints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -18),
	})
	UIKit.keyHint(hints, 1, "CLIC", "VOIR LE CONTENU ET ACHETER")
	overview:GetPropertyChangedSignal("Visible"):Connect(function()
		hints.Visible = overview.Visible
	end)
end

-- Cette méthode permet de construire le bouton ACHETER inactif (contour atténué, étiquette BIENTÔT) lorsque la vue
-- détail est construite : l'achat côté serveur n'existe pas encore (#347).
local function buildBuy(parent: Frame)
	local buy = UIKit.frame({
		Name = "Buy",
		Size = UDim2.fromOffset(BUY_SIZE.X, BUY_SIZE.Y),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = parent,
	})
	UIKit.stroke(buy, C.Muted, 2)
	UIKit.text({
		Name = "Label",
		Text = "ACHETER",
		FontFace = F.Display,
		TextSize = 24,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = buy,
	})
	local soon = UIKit.tag(buy, "Soon", 0, C.Muted, C.Ground)
	soon.Text = "BIENTÔT"
	soon.AnchorPoint = Vector2.new(1, 0.5)
	soon.Position = UDim2.new(1, 12, 0, 0)
	soon.ZIndex = 3
end

-- Cette méthode permet de construire la vue détail (retour, nom, contenu, filet, prix, ACHETER, caisse voisine)
-- lorsque l'écran est construit ; son contenu est rempli à chaque caisse ouverte.
local function buildDetail(column: Frame)
	detail = UIKit.frame({
		Name = "Detail",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = column,
	})
	back = MenuShot.textChoice({
		text = "‹  SHOP",
		font = F.DisplayMedium,
		size = LABEL_SIZE,
		color = C.TextSoft,
		position = UDim2.fromOffset(EDGE, LABEL_Y),
		parent = detail,
		action = openOverview,
	})
	title = label(detail, {
		Name = "Title",
		FontFace = F.Display,
		TextSize = TITLE_SIZE,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE, TITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, TITLE_SIZE + 6),
	}, 3)
	local text, shadow = UIKit.accentLabel(detail, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(EDGE + 1, SUBTITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 18),
	})
	subtitle = { text, shadow }
	rows = UIKit.frame({
		Name = "Contents",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, ROWS_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 3 * ROW_STEP),
		Parent = detail,
	})
	filet = UIKit.frame({
		Name = "Filet",
		Size = UDim2.fromOffset(COLUMN_WIDTH, 1),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.88,
		Parent = detail,
	})
	priceRow = UIKit.frame({
		Name = "Price",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN_WIDTH, PRICE_SIZE + 4),
		Parent = detail,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
		Parent = priceRow,
	})
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
	actions = UIKit.frame({
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN_WIDTH, BUY_SIZE.Y),
		Parent = detail,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 18),
		Parent = actions,
	})
	buildBuy(actions)
	-- Caisse voisine : ‹ CAISSE n / N ›
	local function arrow(glyph: string, order: number, step: number)
		MenuShot.textChoice({
			text = glyph,
			font = F.Display,
			size = 22,
			color = C.TextSoft,
			layoutOrder = order,
			parent = actions,
			action = function()
				openCrate(ShopCatalog.cycle(current, step, #ShopCatalog.CRATES))
			end,
		})
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
end

-- Cette méthode permet de construire l'écran (fond de coin, colonne de gauche, deux vues) lorsque le client démarre.
function ShopScreen.init()
	gui = UIKit.create("ScreenGui", {
		Name = "ShopScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2, -- sous les onglets du menu (4)
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = UIKit.scaledRoot(gui)
	local veil = UIKit.frame({
		Name = "Veil",
		BackgroundColor3 = C.Scrim,
		Size = UDim2.new(0, VEIL_WIDTH, 1, 0),
		ZIndex = 0,
		Parent = root,
	})
	UIKit.create("UIGradient", { Transparency = VEIL, Parent = veil })
	local column =
		UIKit.frame({ Name = "Column", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	buildOverview(column, root)
	buildDetail(column)
	MenuPage.followTopbar(root, column)
	ShopScene.onCrateClicked(openCrate)
	ShopScene.onWeaponFocus(highlightRow)
end

-- Cette méthode permet d'ouvrir le shop sur la vitrine (salle, caméra, interface) lorsque le joueur touche l'onglet SHOP.
function ShopScreen.show()
	if not gui or gui.Enabled then
		return
	end
	gui.Enabled = true
	ShopScene.start()
	openOverview()
end

-- Cette méthode permet de fermer le shop (salle retirée, scène de l'accueil reprise) lorsque le joueur change d'onglet
-- ou que la partie démarre.
function ShopScreen.hide()
	if not gui or not gui.Enabled then
		return
	end
	gui.Enabled = false
	ShopScene.stop()
end

return ShopScreen

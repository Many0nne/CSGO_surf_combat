-- Écran Shop (#347, onglet SHOP du menu, docs/ui.md « Shop ») : interface posée sur la salle de présentation
-- (ShopScene), colonne à gauche sur fond de coin comme l'écran d'équipement. Vue d'ensemble : titre « CAISSES », les
-- caisses en vente sont dans la vitrine (nom et prix sur leur étiquette), un clic sur une caisse ouvre la vue détail.
-- Vue détail : « ‹ SHOP » (retour à la vitrine), nom de la caisse, contenu (#424 : un skin par ligne, vignette de
-- l'arme habillée, rareté, chance en pour cent, total exactement 100 %, et remboursement d'un doublon), prix, ACHETER et
-- passage à la caisse voisine. Aperçu d'un skin (#424) : survoler une ligne montre l'arme habillée en grand au-dessus
-- de la caisse (ShopScene.preview), un clic la retient (glisser dans la salle la tourne), un second clic la relâche.
-- ACHETER (#393, remote `BuyCrate`) : le serveur débite, tire et donne le skin (ou rembourse le doublon) en une écriture,
-- puis la scène joue l'ouverture et la colonne laisse place à la révélation (« OBTENU » ou « DOUBLON · +N CRÉDITS »,
-- skin et rareté) jusqu'au clic. Pendant l'achat : « ACHAT… », pas de second clic ; tout le contenu possédé : ACHETER
-- inactif « TOUT OBTENU » ; refus ou échec : message sous le bouton. Pour l'admin et dans Studio, ouverture de test
-- gratuite en plus (#332, remote `OpenCrate`), sous ACHETER.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreditPacks = require(Shared:WaitForChild("CreditPacks"))
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WalletRules = require(Shared:WaitForChild("WalletRules"))
local ShopScene = require(script.Parent.Parent.systems.game.ShopScene)
local LocalWallet = require(script.Parent.Parent.systems.inventory.LocalWallet)
local CreditPackWindow = require(script.Parent.CreditPackWindow)
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
local HEADER_Y = SUBTITLE_Y + 34 -- en-têtes CHANCE et SI DOUBLON au-dessus du contenu (#393)
local HEADER_SIZE = UITheme.TextSize.Min
local ROWS_Y = HEADER_Y + HEADER_SIZE + 6
-- Une ligne par skin (#424) : 8 lignes de 30 px laissent ACHETER et l'ouverture de test au-dessus du bas de l'écran
local ROW_STEP = 30
local ROW_TEXT = 20
local THUMB_X = 12 -- vignette de l'arme habillée, après la barre de rareté
-- Vignette large : une AWP de profil est cinq fois plus longue que haute, à 88 px elle ne faisait que 15 px de haut
local THUMB_SIZE = Vector2.new(128, 30)
local NAME_X = THUMB_X + THUMB_SIZE.X + 10
local RARITY_X = 270 -- colonne des raretés et chances (« EXCEPTIONNEL  2,5 % » tient avant le remboursement)
local COLUMN_WIDTH = 470
local MAX_ROWS = 8 -- place réservée au contenu
local REFUND_ICON = 18 -- jeton devant le remboursement d'un doublon, à droite de la ligne
local REFUND_WIDTH = 70
local BUY_SIZE = Vector2.new(160, 42)
local STATUS_GAP = 10 -- entre ACHETER et le message de refus
local TEST_GAP = 46 -- entre ACHETER et l'ouverture de test (admin, Studio), sous la place du message
local PRICE_SIZE = 44
local PRICE_ICON = 34 -- jeton du crédit devant le prix (#391)
local PRICE_ICON_LIFT = 6
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
-- Aperçu d'un skin (#424) : lignes du contenu et leur skin, ligne survolée, ligne retenue par un clic. Le survol n'agit
-- qu'après HOVER_DELAY : en allant de la liste à ACHETER, la souris traverse des lignes sans les montrer
local lines: { Frame } = {}
local lineSkins: { string } = {}
local hoveredRow: number? = nil
local lockedRow: number? = nil
local hoverToken = 0
local HOVER_DELAY = 0.2
local DIMMED = 0.6 -- atténuation des autres lignes pendant un aperçu
local LOCKED_FILL = 0.9 -- fond os de la ligne retenue (transparence)
-- Achat (#393) et ouverture de test (#332)
local buyButton: Frame
local buyStroke: UIStroke
local buyChoice: MenuShot.Choice
local buyOwned: TextLabel -- étiquette TOUT OBTENU
local testRow: Frame
local openChoice: MenuShot.Choice
local status: TextLabel
local reveal: Frame
local revealHeading: { TextLabel }
local revealTitle: { TextLabel }
local revealRarity: { TextLabel }
local requesting: string? = nil -- remote de la demande en vol (achat ou ouverture de test)
local navigation: { MenuShot.Choice } = {} -- « ‹ SHOP » et flèches de la caisse voisine, figés pendant une demande
-- Numéro de la vue affichée, augmenté à chaque changement (caisse, vitrine, shop fermé) : une réponse arrivée après un
-- changement n'est plus jouée
local view = 0
local statusToken = 0
local DEBUG_ATTRIBUTE = "DebugCrateOpening" -- Studio seulement, voir debugOpening
local BUY_TEXT = "ACHETER"
local BUYING_TEXT = "ACHAT…"
local OPEN_TEXT = "OUVERTURE DE TEST  ·  GRATUITE"
-- Joueur restreint (objets aléatoires payants, #395) : ACHETER inactif avec cette étiquette, refus `region` du serveur
local REGION_TEXT = "INDISPONIBLE DANS TA RÉGION"
-- Packs de crédits (#395) : bouton sous les gains du jour (MainMenu, en haut à droite), fenêtre CreditPackWindow
local PACKS_TEXT = "+ CRÉDITS"
local PACKS_Y = 100 -- sous « GAINS DU JOUR » de la barre du menu (68 à 90)
local PACKS_SIZE = Vector2.new(124, 34)
local shopColumn: Frame
local shopVeil: Frame
local overviewHints: Frame -- aide de la vitrine, hors de la colonne (bas de l'écran)
local packButton: Frame
-- Motifs de refus du serveur (CrateService), affichés sous ACHETER
local REFUSALS = {
	rate = "PATIENTE",
	busy = "ACHAT DÉJÀ EN COURS",
	loading = "INVENTAIRE EN CHARGEMENT",
	forbidden = "RÉSERVÉ",
	unknown = "CAISSE INCONNUE",
	empty = "CAISSE VIDE",
	owned = "TOUT OBTENU",
	region = REGION_TEXT,
	insufficient = "CRÉDITS INSUFFISANTS",
	-- Pas « rien n'est débité » : une écriture passée dont la vérification échoue est aussi `failed` (InventoryStore)
	failed = "ACHAT IMPOSSIBLE  ·  RÉESSAIE PLUS TARD",
}
local paintActions: () -> ()
local paintPackButton: () -> () = function() end

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

-- Cette méthode permet de mettre en avant la ligne du skin montré en aperçu, les autres atténuées, lorsque l'aperçu
-- change ; `row` nil rend toutes les lignes (transparence d'origine gardée en attribut).
local function highlightRow(row: number?)
	for i, line in lines do
		local dim = if row and i ~= row then DIMMED else 0
		for _, item in line:GetDescendants() do
			local property = if item:IsA("TextLabel")
				then "TextTransparency"
				elseif item:IsA("ImageLabel") or item:IsA("ViewportFrame") then "ImageTransparency"
				elseif item:IsA("Frame") then "BackgroundTransparency"
				else nil
			if property then
				local base = item:GetAttribute("BaseTransparency")
				if type(base) ~= "number" then
					base = (item :: any)[property]
					item:SetAttribute("BaseTransparency", base)
				end
				(item :: any)[property] = base + (1 - base) * dim
			end
		end
		line.BackgroundTransparency = if i == lockedRow then LOCKED_FILL else 1
	end
end

-- Cette méthode permet de montrer le skin de la ligne survolée, sinon celui de la ligne retenue (aucun : plan détail),
-- lorsque le survol ou la ligne retenue change.
local function showPreview()
	local row = hoveredRow or lockedRow
	ShopScene.preview(if row then lineSkins[row] else nil)
	highlightRow(row)
end

-- Cette méthode permet de suivre la ligne survolée (nil : aucune) lorsque la souris entre dans une ligne ou en sort ;
-- l'aperçu ne suit qu'après HOVER_DELAY sur la même ligne.
local function setHovered(row: number?)
	hoveredRow = row
	hoverToken += 1
	local token = hoverToken
	task.delay(HOVER_DELAY, function()
		if token == hoverToken then
			showPreview()
		end
	end)
end

-- Cette méthode permet de retenir l'aperçu d'une ligne (ou de le relâcher si elle l'était déjà) lorsque le joueur la
-- clique ; l'aperçu suit tout de suite.
local function toggleLock(row: number)
	lockedRow = if lockedRow == row then nil else row
	hoveredRow = nil
	hoverToken += 1
	showPreview()
end

-- Cette méthode permet de retirer l'aperçu (ni ligne survolée ni retenue) lorsque la caisse, la vue ou l'écran change,
-- ou qu'une ouverture va se jouer.
local function clearPreview()
	hoveredRow, lockedRow = nil, nil
	hoverToken += 1
	ShopScene.preview(nil)
	highlightRow(nil)
end

-- Cette méthode permet de remplir la vue détail pour la caisse courante (nom, un skin par ligne avec sa vignette, prix,
-- place dans la liste) lorsque le joueur ouvre une caisse ou passe à la voisine.
local function paintDetail()
	local crate = ShopCatalog.CRATES[current]
	if not crate then
		return
	end
	clearPreview()
	setText(title, crate.name)
	setText(subtitle, ShopCatalog.subtitle(crate, InventoryRules.ITEMS))
	for _, child in rows:GetChildren() do
		child:Destroy()
	end
	table.clear(lines)
	table.clear(lineSkins)
	local contents = ShopCatalog.contents(crate, InventoryRules.ITEMS)
	local chances = ShopCatalog.chances(contents)
	for i, row in contents do
		local color = rgb(row.rarity.color)
		local line = UIKit.frame({
			Name = "Row" .. i,
			BackgroundColor3 = C.Bone,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, (i - 1) * ROW_STEP),
			Size = UDim2.fromOffset(COLUMN_WIDTH, ROW_STEP),
			Parent = rows,
		})
		lines[i] = line
		lineSkins[i] = row.skin
		-- Zone de survol et de clic de la ligne entière (aperçu du skin)
		local hit = UIKit.button({
			Name = "Hit",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = line,
		})
		hit.MouseEnter:Connect(function()
			setHovered(i)
		end)
		hit.MouseLeave:Connect(function()
			if hoveredRow == i then
				setHovered(nil)
			end
		end)
		hit.Activated:Connect(function()
			toggleLock(i)
		end)
		UIKit.frame({
			Name = "Bar",
			Position = UDim2.fromOffset(0, (ROW_STEP - ROW_TEXT) / 2),
			Size = UDim2.fromOffset(4, ROW_TEXT),
			BackgroundColor3 = color,
			Parent = line,
		})
		-- Vignette : l'arme habillée de ce skin, de profil (rendu des cartes de skin de l'écran ARMES)
		local thumb = UIKit.frame({
			Name = "Thumb",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(THUMB_X, (ROW_STEP - THUMB_SIZE.Y) / 2),
			Size = UDim2.fromOffset(THUMB_SIZE.X, THUMB_SIZE.Y),
			ZIndex = 2,
			Parent = line,
		})
		UIKit.weaponSilhouette(thumb, row.viewmodel, THUMB_SIZE.X / THUMB_SIZE.Y, true, row.skin).ZIndex = 2
		label(line, {
			Name = "Skin",
			Text = row.name,
			FontFace = F.DisplayText,
			TextSize = ROW_TEXT,
			TextColor3 = C.Bone,
			Position = UDim2.fromOffset(NAME_X, 0),
			Size = UDim2.fromOffset(RARITY_X - NAME_X, ROW_STEP),
		}, 2)
		label(line, {
			Name = "Rarity",
			Text = string.format("%s  %s", row.rarity.label, ShopCatalog.chanceLabel(chances[i] or 0)),
			FontFace = F.Display,
			TextSize = 18,
			TextColor3 = color,
			Position = UDim2.fromOffset(RARITY_X, 0),
			Size = UDim2.fromOffset(COLUMN_WIDTH - RARITY_X - REFUND_WIDTH, ROW_STEP),
		}, 1)
		-- Remboursement d'un doublon (#393) : jeton puis montant, calé à droite de la ligne
		local refund = UIKit.frame({
			Name = "Refund",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(COLUMN_WIDTH, 0),
			Size = UDim2.fromOffset(REFUND_WIDTH, ROW_STEP),
			Parent = line,
		})
		UIKit.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
			Parent = refund,
		})
		UIKit.creditIcon(refund, REFUND_ICON, 1, { LayoutOrder = 0 })
		UIKit.text({
			Name = "Amount",
			Text = WalletRules.format(ShopCatalog.refund(crate, row.rarity.id)),
			FontFace = F.Display,
			TextSize = 18,
			TextColor3 = C.TextSoft,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, ROW_STEP),
			LayoutOrder = 1,
			ZIndex = 2,
			Parent = refund,
		})
	end
	local below = ROWS_Y + #contents * ROW_STEP + 10
	filet.Position = UDim2.fromOffset(EDGE, below)
	priceRow.Position = UDim2.fromOffset(EDGE, below + 14)
	local actionsY = below + 14 + PRICE_SIZE + 26
	actions.Position = UDim2.fromOffset(EDGE, actionsY)
	status.Position = UDim2.fromOffset(EDGE, actionsY + BUY_SIZE.Y + STATUS_GAP)
	testRow.Position = UDim2.fromOffset(EDGE, actionsY + BUY_SIZE.Y + TEST_GAP)
	setText(price, ShopCatalog.priceLabel(crate))
	position.Text = string.format("CAISSE  %d / %d", current, #ShopCatalog.CRATES)
	paintActions()
end

-- Cette méthode permet d'ouvrir la vue détail d'une caisse (glissement de la caméra jusqu'au socle) lorsque le joueur
-- la clique dans la vitrine ou passe à la voisine.
local function openCrate(index: number)
	if not ShopCatalog.CRATES[index] then
		return
	end
	current = index
	view += 1
	overview.Visible = false
	detail.Visible = true
	paintDetail()
	ShopScene.showCrate(index)
end

-- Cette méthode permet de revenir à la vitrine (toutes les caisses) lorsque le joueur clique « ‹ SHOP » ou que l'écran
-- s'ouvre.
local function openOverview()
	view += 1
	clearPreview()
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
	setText(countLabel, string.format("%d EN VENTE  ·  UNE PAR ARME ET PAR SÉRIE", #ShopCatalog.CRATES))
	-- L'aide n'est pas dans la colonne (qui descend sous la barre de Roblox) : elle tient le bas de l'écran
	local hints = UIKit.hintRow(root, {
		Name = "OverviewHints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -18),
	})
	UIKit.keyHint(hints, 1, "CLIC", "VOIR LE CONTENU ET ACHETER")
	overviewHints = hints
	overview:GetPropertyChangedSignal("Visible"):Connect(function()
		hints.Visible = overview.Visible and not CreditPackWindow.isOpen()
	end)
end

-- Cette méthode permet de changer le texte d'un choix et de son ombre ensemble lorsqu'un bouton change d'état.
local function setChoiceText(choice: MenuShot.Choice, text: string)
	for _, name in { "Label", "LabelShadow" } do
		local item = choice.button:FindFirstChild(name, true)
		if item and item:IsA("TextLabel") then
			item.Text = text
		end
	end
end

-- Cette méthode permet de savoir si le joueur local peut ouvrir une caisse gratuitement (Studio, ou rôle Admin affiché
-- par le serveur) lorsque la vue détail montre ou non l'ouverture de test ; le serveur revérifie de son côté.
local function canOpen(): boolean
	return RunService:IsStudio() or Players.LocalPlayer:GetAttribute("Role") == "Admin"
end

-- Cette méthode permet de savoir si le joueur local possède déjà tout le contenu de la caisse courante (attribut
-- informatif `OwnedItems`, relu ici pour ne pas dépendre de l'ordre des abonnés) lorsque ACHETER se peint.
local function ownsWholeCrate(): boolean
	local crate = ShopCatalog.CRATES[current]
	if not crate then
		return false
	end
	local owned = InventoryRules.decode(Players.LocalPlayer:GetAttribute(InventoryRules.ATTRIBUTE))
	return ShopCatalog.allOwned(crate, InventoryRules.ITEMS, owned)
end

-- Cette méthode permet de peindre ACHETER (actif, « ACHAT… » pendant un achat, inactif « TOUT OBTENU »), l'ouverture de
-- test et la navigation (figée pendant une demande) lorsque la vue détail s'affiche, qu'une demande part ou revient.
paintActions = function()
	-- Shop fermé : rien à peindre, la vue détail se repeint en s'ouvrant (paintDetail)
	if not (buyButton and gui.Enabled) then
		return
	end
	local complete = ownsWholeCrate()
	-- Restriction pas encore connue : ACHETER reste ouvert, le serveur répond `region` s'il le faut
	local region = LocalWallet.restricted() == true
	local busy = requesting ~= nil
	local buying = requesting == NetworkProtocol.Names.BUY_CRATE
	buyChoice.setEnabled(not (busy or complete or region))
	setChoiceText(buyChoice, if buying then BUYING_TEXT else BUY_TEXT)
	buyStroke.Color = if complete or busy or region then C.Muted else C.Bone
	-- Même étiquette pour les deux états ; celle de la région, plus longue que le bouton, part de son coin gauche
	buyOwned.Text = if region then REGION_TEXT else "TOUT OBTENU"
	buyOwned.AnchorPoint = if region then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
	buyOwned.Position = if region then UDim2.fromOffset(-12, 0) else UDim2.new(1, 12, 0, 0)
	buyOwned.Visible = (complete or region) and not buying
	testRow.Visible = canOpen()
	openChoice.setEnabled(not busy)
	-- Pendant une demande, la caisse affichée reste celle qui est payée : l'ouverture se joue sur son socle
	for _, choice in navigation do
		choice.setEnabled(not busy)
	end
	paintPackButton()
end

-- Cette méthode permet d'afficher un message sous ACHETER pendant 3 s (refus ou échec en rouge d'impact, `ok` en ambre)
-- lorsque le serveur répond sans que l'ouverture puisse se jouer.
local function showStatus(text: string, ok: boolean?)
	statusToken += 1
	local token = statusToken
	status.Text = text
	status.BackgroundColor3 = if ok then C.Accent else C.HitRed
	status.TextColor3 = if ok then C.Ground else C.Bone
	status.Visible = true
	task.delay(3, function()
		if token == statusToken then
			status.Visible = false
		end
	end)
end

-- Cette méthode permet d'écrire la ligne au-dessus du skin révélé lorsque l'ouverture le montre : « OBTENU », ou pour un
-- skin déjà possédé « DOUBLON », suivi des crédits rendus par un achat (« DOUBLON · +200 CRÉDITS », #393).
local function revealHeadline(added: boolean, refund: number): string
	if added then
		return "OBTENU"
	elseif refund > 0 then
		return string.format("DOUBLON  ·  +%s %s", WalletRules.format(refund), ShopCatalog.CURRENCY)
	end
	return "DOUBLON"
end

-- Cette méthode permet d'afficher la révélation (ligne d'en-tête, skin, rareté dans sa couleur) lorsque l'ouverture
-- montre l'arme habillée ; un doublon s'écrit en ambre.
local function showReveal(crate: ShopCatalog.Crate, skinId: string, added: boolean, refund: number)
	setText(revealHeading, revealHeadline(added, refund))
	revealHeading[1].TextColor3 = if added then C.TextSoft else C.Accent
	for _, row in ShopCatalog.contents(crate, InventoryRules.ITEMS) do
		if row.skin == skinId then
			setText(revealTitle, row.weapon .. "  " .. row.name)
			setText(revealRarity, row.rarity.label)
			for _, item in revealRarity do
				if item.Name == "Rarity" then
					item.TextColor3 = rgb(row.rarity.color)
				end
			end
		end
	end
	reveal.Visible = true
end

-- Cette méthode permet de revenir à la vue détail de la caisse lorsque l'ouverture se termine (clic après la
-- révélation).
local function endOpening()
	reveal.Visible = false
	detail.Visible = true
	paintDetail()
end

-- Cette méthode permet de demander la caisse courante au serveur (`remoteName` : achat ou ouverture de test), puis de
-- jouer l'ouverture du skin reçu lorsque le joueur clique ; une demande à la fois, navigation figée jusqu'à la réponse.
local function requestCrate(remoteName: string)
	local crate = ShopCatalog.CRATES[current]
	if requesting or not crate or ShopScene.isOpening() then
		return
	end
	requesting = remoteName
	local seen = view
	-- L'ouverture se joue depuis le plan détail : l'aperçu se retire dès la demande
	clearPreview()
	paintActions()
	task.spawn(function()
		local remote = ReplicatedStorage:FindFirstChild(remoteName)
		local ok, result = false, nil
		if remote and remote:IsA("RemoteFunction") then
			ok, result = pcall(function()
				return remote:InvokeServer(crate.id)
			end)
		end
		requesting = nil
		paintActions()
		if not gui.Enabled or view ~= seen then
			-- Shop fermé ou rouvert pendant la demande : un skin gagné l'est quand même, le solde et l'inventaire suivent ;
			-- ni scène ni message sur une autre vue que celle de la caisse demandée
			return
		end
		if not (ok and type(result) == "table") then
			showStatus("ÉCHEC")
			return
		end
		if not result.ok then
			showStatus(REFUSALS[result.reason] or "ÉCHEC")
			return
		end
		local added = result.added ~= false
		local refund = if type(result.refund) == "number" then result.refund else 0
		detail.Visible = false
		local started = ShopScene.playOpening(result.skinId, result.rarity, function()
			showReveal(crate, result.skinId, added, refund)
		end, endOpening)
		if not started then
			-- Le serveur a déjà donné le skin (ou remboursé) : le dire, même sans la scène
			detail.Visible = true
			showStatus(revealHeadline(added, refund), true)
		end
		paintPackButton()
	end)
end

-- Cette méthode permet de construire ACHETER (contour os, survol en rouge d'impact, étiquette TOUT OBTENU quand tout
-- est possédé) et le message de refus sous les actions lorsque la vue détail est construite.
local function buildBuy(parent: Frame)
	buyButton = UIKit.frame({
		Name = "Buy",
		Size = UDim2.fromOffset(BUY_SIZE.X, BUY_SIZE.Y),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = parent,
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
		action = function()
			requestCrate(NetworkProtocol.Names.BUY_CRATE)
		end,
	})
	-- Même étiquette que BIENTÔT avant l'achat (#347) : os atténué à texte sombre, à cheval sur le coin du bouton
	buyOwned = UIKit.tag(buyButton, "Owned", 0, C.Muted, C.Ground)
	buyOwned.Text = "TOUT OBTENU"
	buyOwned.AnchorPoint = Vector2.new(1, 0.5)
	buyOwned.Position = UDim2.new(1, 12, 0, 0)
	buyOwned.ZIndex = 3
	buyOwned.Visible = false
end

-- Cette méthode permet de construire le message de refus (rouge d'impact, texte os) et l'ouverture de test gratuite
-- (admin et Studio, #332 : texte atténué sous ACHETER) lorsque la vue détail est construite.
local function buildTestAndStatus(parent: Frame)
	status = UIKit.tag(parent, "Status", 0, C.HitRed, C.Bone)
	status.ZIndex = 3
	status.Visible = false
	testRow = UIKit.frame({
		Name = "TestOpen",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN_WIDTH, 24),
		Visible = false,
		Parent = parent,
	})
	openChoice = MenuShot.textChoice({
		text = OPEN_TEXT,
		font = F.DisplayMedium,
		size = UITheme.TextSize.Min,
		color = C.TextSoft,
		parent = testRow,
		action = function()
			requestCrate(NetworkProtocol.Names.OPEN_CRATE)
		end,
	})
end

-- Cette méthode permet de construire la révélation (« OBTENU », arme et skin, rareté, aide CLIC · CONTINUER) lorsque
-- l'écran est construit ; masquée hors ouverture.
local function buildReveal(column: Frame, root: Frame)
	reveal = UIKit.frame({
		Name = "Reveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = column,
	})
	revealHeading = label(reveal, {
		Name = "Label",
		Text = "OBTENU",
		FontFace = F.DisplayMedium,
		TextSize = LABEL_SIZE,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(EDGE, LABEL_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, LABEL_SIZE + 4),
	}, 2)
	revealTitle = label(reveal, {
		Name = "Title",
		FontFace = F.Display,
		TextSize = TITLE_SIZE,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE, TITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, TITLE_SIZE + 6),
	}, 3)
	revealRarity = label(reveal, {
		Name = "Rarity",
		FontFace = F.Display,
		TextSize = 22,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(EDGE + 1, SUBTITLE_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 26),
	}, 2)
	local hints = UIKit.hintRow(root, {
		Name = "RevealHints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, EDGE, 1, -18),
		Visible = false,
	})
	UIKit.keyHint(hints, 1, "CLIC", "CONTINUER")
	reveal:GetPropertyChangedSignal("Visible"):Connect(function()
		hints.Visible = reveal.Visible
	end)
end

-- Cette méthode permet de construire l'aide de l'aperçu des skins (#424) en bas à droite (la colonne tient la gauche),
-- visible avec la vue détail, lorsque l'écran est construit.
local function buildPreviewHints(parent: Frame)
	local hints = UIKit.hintRow(parent, {
		Name = "PreviewHints",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -EDGE, 1, -18),
		Visible = false,
	})
	UIKit.keyHint(hints, 1, "SURVOL", "VOIR UN SKIN")
	UIKit.keyHint(hints, 2, "CLIC", "LE GARDER")
	UIKit.keyHint(hints, 3, "GLISSER", "LE TOURNER")
	detail:GetPropertyChangedSignal("Visible"):Connect(function()
		hints.Visible = detail.Visible
	end)
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
	table.insert(navigation, back)
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
	-- En-têtes du contenu (#393) : chance de chaque rareté (total 100 %) et crédits rendus pour un doublon
	label(detail, {
		Name = "ChanceHeader",
		Text = "CHANCE",
		FontFace = F.DisplayMedium,
		TextSize = HEADER_SIZE,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(EDGE + RARITY_X, HEADER_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH - RARITY_X - REFUND_WIDTH, HEADER_SIZE + 2),
	}, 1)
	label(detail, {
		Name = "RefundHeader",
		Text = "SI DOUBLON",
		FontFace = F.DisplayMedium,
		TextSize = HEADER_SIZE,
		TextColor3 = C.TextSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(EDGE + COLUMN_WIDTH, HEADER_Y),
		Size = UDim2.fromOffset(120, HEADER_SIZE + 2),
	}, 1)
	rows = UIKit.frame({
		Name = "Contents",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE, ROWS_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, MAX_ROWS * ROW_STEP),
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
	-- Jeton du crédit (#391) devant le montant, remonté de PRICE_ICON_LIFT : aligné sur le bas de la boîte du texte, il
	-- tombait sous les chiffres (la boîte compte la place des jambages)
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
	buildTestAndStatus(detail)
	-- Caisse voisine : ‹ CAISSE n / N ›
	local function arrow(glyph: string, order: number, step: number)
		local choice = MenuShot.textChoice({
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
end

-- Cette méthode permet, dans Studio, de piloter le shop par l'attribut DebugCrateOpening du joueur (MCP, docs/ui.md) :
-- « crate:N » montre la caisse N, « skinId|rareté » joue l'ouverture sans passer par le serveur (rien n'est gagné),
-- « skinId|rareté|N » la joue comme un doublon remboursé de N crédits (#393).
local function debugOpening()
	local player = Players.LocalPlayer
	local value = player:GetAttribute(DEBUG_ATTRIBUTE)
	if type(value) ~= "string" then
		return
	end
	player:SetAttribute(DEBUG_ATTRIBUTE, nil)
	if not gui.Enabled or CreditPackWindow.isOpen() then
		warn("[DebugCrateOpening] shop fermé ou fenêtre des packs ouverte : ouvrir l'onglet SHOP, fermer les packs")
		return
	end
	local index = string.match(value, "^crate:(%d+)$")
	if index then
		openCrate(tonumber(index) :: number)
		return
	end
	local skinId, rarityId, refundText = string.match(value, "^([^|]+)|([^|]+)|(%d+)$")
	if not skinId then
		skinId, rarityId = string.match(value, "^([^|]+)|([^|]+)$")
	end
	local refund = if refundText then tonumber(refundText) else nil
	if not (skinId and rarityId) or ShopScene.isOpening() then
		warn("[DebugCrateOpening] valeur ou état invalide : " .. value)
		return
	end
	local crate = ShopCatalog.CRATES[current]
	clearPreview()
	detail.Visible = false
	local started = ShopScene.playOpening(skinId, rarityId, function()
		if crate then
			showReveal(crate, skinId, refund == nil, refund or 0)
		end
	end, endOpening)
	if not started then
		detail.Visible = true
		warn("[DebugCrateOpening] ouverture impossible : " .. value)
	end
	print("[DebugCrateOpening] " .. value .. " : " .. tostring(started))
end

-- Cette méthode permet de montrer « + CRÉDITS » (#395 : joueur connu non restreint, vitrine ou vue détail sans achat en
-- vol, fenêtre fermée, vrais ids ou Studio) lorsque le shop s'affiche, qu'une vue ou que la restriction change.
paintPackButton = function()
	if not packButton then
		return
	end
	packButton.Visible = gui.Enabled
		and requesting == nil
		and (CreditPacks.isReady() or RunService:IsStudio())
		and LocalWallet.restricted() == false
		and not CreditPackWindow.isOpen()
		and (overview.Visible or detail.Visible)
end

-- Cette méthode permet de fermer la fenêtre des packs et de rendre la salle et la colonne du shop lorsque le joueur
-- clique RETOUR, devient restreint ou quitte le shop.
local function closePacks()
	CreditPackWindow.hide()
	ShopScene.setInteractive(true)
	shopColumn.Visible = true
	shopVeil.Visible = true
	overviewHints.Visible = overview.Visible
	paintPackButton()
end

-- Cette méthode permet d'ouvrir la fenêtre des packs (#395) lorsque le joueur clique « + CRÉDITS » : la colonne du shop
-- se masque (elle chevaucherait le bloc centré) et la salle ne réagit plus à la souris ; refusé pendant une demande.
local function openPacks()
	if requesting or ShopScene.isOpening() or CreditPackWindow.isOpen() then
		return
	end
	CreditPackWindow.show()
	if CreditPackWindow.isOpen() then
		shopColumn.Visible = false
		shopVeil.Visible = false
		-- L'aide de la vitrine parle de cliquer les caisses, inertes sous la fenêtre
		overviewHints.Visible = false
		ShopScene.setInteractive(false)
	end
	paintPackButton()
end

-- Cette méthode permet de construire « + CRÉDITS » en haut à droite, sous les gains du jour de la barre du menu (contour
-- os, survol en rouge d'impact comme ACHETER, en plus petit) lorsque l'écran est construit.
local function buildPackButton(root: Frame)
	packButton = UIKit.frame({
		Name = "CreditPacks",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, PACKS_Y),
		Size = UDim2.fromOffset(PACKS_SIZE.X, PACKS_SIZE.Y),
		Visible = false,
		Parent = root,
	})
	UIKit.stroke(packButton, C.Bone, 2)
	MenuShot.textChoice({
		text = PACKS_TEXT,
		font = F.Display,
		size = 18,
		color = C.Bone,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		parent = packButton,
		action = openPacks,
	})
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
	shopVeil = UIKit.frame({
		Name = "Veil",
		BackgroundColor3 = C.Scrim,
		Size = UDim2.new(0, VEIL_WIDTH, 1, 0),
		ZIndex = 0,
		Parent = root,
	})
	UIKit.create("UIGradient", { Transparency = VEIL, Parent = shopVeil })
	shopColumn =
		UIKit.frame({ Name = "Column", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	buildOverview(shopColumn, root)
	buildDetail(shopColumn)
	-- Dans la colonne : masquée avec elle sous la fenêtre des packs
	buildPreviewHints(shopColumn)
	buildReveal(shopColumn, root)
	buildPackButton(root)
	MenuPage.followTopbar(root, shopColumn)
	CreditPackWindow.init(closePacks)
	ShopScene.onCrateClicked(openCrate)
	paintActions()
	Players.LocalPlayer:GetAttributeChangedSignal("Role"):Connect(paintActions)
	-- Skin obtenu (achat, ouverture de test, autre serveur) : TOUT OBTENU peut changer
	Players.LocalPlayer:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(paintActions)
	-- Restriction des objets aléatoires payants (#395) connue ou changée : ACHETER et « + CRÉDITS » suivent
	-- (paintActions repeint aussi le bouton des packs)
	LocalWallet.observeRestricted(function()
		paintActions()
	end)
	if RunService:IsStudio() then
		Players.LocalPlayer:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(debugOpening)
	end
end

-- Cette méthode permet d'ouvrir le shop sur la vitrine (salle, caméra, interface) lorsque le joueur touche l'onglet SHOP.
function ShopScreen.show()
	if not gui or gui.Enabled then
		return
	end
	gui.Enabled = true
	reveal.Visible = false
	ShopScene.start()
	openOverview()
	paintPackButton()
end

-- Cette méthode permet de fermer le shop (salle retirée, scène de l'accueil reprise) lorsque le joueur change d'onglet
-- ou que la partie démarre.
function ShopScreen.hide()
	if not gui or not gui.Enabled then
		return
	end
	gui.Enabled = false
	view += 1
	clearPreview()
	closePacks()
	ShopScene.stop()
end

return ShopScreen

-- Fenêtre des packs de crédits (#395, docs/ui.md « Packs de crédits ») : ouverte par « + CRÉDITS » sous le solde, sur la
-- page SHOP. Écran secondaire du menu (`MenuPage` : bloc centré sur un voile, sans panneau) : titre, trois packs côte à
-- côte (jeton, montant, CRÉDITS, prix en Robux dans un contour os comme ACHETER), une ligne d'explication, RETOUR.
-- Un clic sur un prix demande le prompt d'achat au serveur (remote `BuyCreditPack`), qui l'ouvre ou le refuse
-- (joueur restreint) ; les crédits arrivent ensuite par ProcessReceipt et le solde de la barre du menu suit. Masquée pour
-- un joueur restreint ou dont la restriction n'est pas encore connue (attribut `PaidRandomRestricted`).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreditPacks = require(Shared:WaitForChild("CreditPacks"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local PurchaseGuard = require(Shared:WaitForChild("PurchaseGuard"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WalletRules = require(Shared:WaitForChild("WalletRules"))
local LocalWallet = require(script.Parent.Parent.systems.inventory.LocalWallet)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local PurchaseStatus = require(script.Parent.PurchaseStatus)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local CreditPackWindow = {}

-- Mise en page (px à 720 de haut), dans le bloc centré de 780 px
local PACKS_Y = MenuPage.ContentTop + 24
local PACK_WIDTH = 220
local PACK_ICON = 56
local AMOUNT_SIZE = 52
local PRICE_SIZE = Vector2.new(160, 42)
local NOTE_Y = PACKS_Y + 290
local DIM_TRANSPARENCY = 0.35 -- voile plein écran sous le voile central (salle du shop assombrie)
-- Motifs de refus du serveur (ReceiptService), affichés sous les packs
local REFUSALS = PurchaseStatus.labels({
	unknown = "PACK INCONNU",
	unavailable = "PACKS PAS ENCORE EN VENTE",
	full = "SOLDE AU MAXIMUM",
	loading = "SAUVEGARDE INDISPONIBLE  ·  RÉESSAIE PLUS TARD",
})

local page: MenuPage.Page
local status: TextLabel
-- s après lesquels les prix sont rendus si le serveur n'a jamais confirmé l'ouverture du prompt (secours) ; un prompt
-- connu comme ouvert garde les prix inactifs jusqu'à sa fin (PurchaseGuard), pour qu'aucun second prompt ne s'ouvre dessus
local PROMPT_TIMEOUT = 120
local PROMPT_FINAL_TIMEOUT = 1800 -- s : au-delà, même un prompt connu ouvert rend les prix (fin jamais signalée)
-- Achat en cours, de la demande au serveur à la fin du prompt de Roblox (PromptProductPurchaseFinished) : les prix
-- restent inactifs, fenêtre fermée et rouverte comprise. Numéroté : une fin ou un délai d'un achat passé est ignoré
local guard = PurchaseGuard.new()
-- Crédits du pack attendus après un prompt pas annulé : seule une hausse du solde de ce montant est annoncée
local awaitingCredits: number? = nil
local priceChoices: { MenuShot.Choice } = {}
local lastBalance: number? = nil

-- Cette méthode permet d'activer ou non les prix lorsqu'un achat commence ou se termine.
local function setPricesEnabled(enabled: boolean)
	for _, choice in priceChoices do
		choice.setEnabled(enabled)
	end
end

-- Prix lus sur les Developer Products (`PriceInRobux`), par productId : un appel réussi par produit, jamais répété
local fetchedPrices: { [number]: number } = {}
local fetching: { [number]: boolean } = {}
local priceLabels: { [number]: { TextLabel } } = {}

-- Cette méthode permet de repeindre le prix d'un pack (texte et ombre) lorsque son prix lu arrive.
local function paintPrice(pack: CreditPacks.Pack)
	local text = CreditPacks.priceLabel(pack, fetchedPrices[pack.productId])
	local labels = priceLabels[pack.productId]
	if labels then
		for _, label in labels do
			label.Text = text
		end
	end
end

-- Cette méthode permet de lire le prix d'un pack sur son Developer Product lorsque la fenêtre est construite ;
-- une seule tentative par produit, en différé, sans jamais bloquer ni afficher d'erreur : échec ou attente = config.
local function fetchPrice(pack: CreditPacks.Pack)
	local productId = pack.productId
	if fetchedPrices[productId] or fetching[productId] then
		return
	end
	fetching[productId] = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		fetching[productId] = nil
		local robux = if ok and type(info) == "table" then info.PriceInRobux else nil
		if CreditPacks.displayRobux(pack, robux) == robux then
			fetchedPrices[productId] = robux
			paintPrice(pack)
		end
	end)
end

-- Cette méthode permet de terminer l'achat en cours (prix rendus) lorsque le prompt se ferme, que le serveur refuse ou
-- que le délai de secours passe ; `ended` vient de PurchaseGuard (faux : un autre achat a commencé, ou prompt ouvert).
local function endPurchase(ended: boolean)
	if ended then
		setPricesEnabled(true)
	end
end

-- Cette méthode permet d'afficher un message sous les packs (refus en rouge d'impact, crédits reçus en ambre) lorsque le
-- serveur répond ou que le solde monte.
local showStatus = PurchaseStatus.presenter(function()
	return status
end)

-- Cette méthode permet de demander au serveur le prompt d'achat d'un pack lorsque le joueur clique sur son prix ; une
-- demande à la fois, réponse affichée seulement en cas de refus (le prompt de Roblox suffit sinon).
local function requestPack(pack: CreditPacks.Pack)
	-- Commencé avant l'appel : le serveur ouvre le prompt avant de répondre, sa fin peut arriver avant la réponse
	local id = PurchaseGuard.start(guard, pack.productId)
	if not id then
		return
	end
	awaitingCredits = pack.credits
	setPricesEnabled(false)
	task.delay(PROMPT_TIMEOUT, function()
		endPurchase(PurchaseGuard.timedOut(guard, id))
	end)
	-- Dernier recours : un prompt ouvert dont Roblox n'a jamais signalé la fin ne bloque pas les prix toute la session
	task.delay(PROMPT_FINAL_TIMEOUT, function()
		endPurchase(PurchaseGuard.timedOut(guard, id, true))
	end)
	task.spawn(function()
		local remote = ReplicatedStorage:FindFirstChild(NetworkProtocol.Names.BUY_CREDIT_PACK)
		local ok, result = false, nil
		if remote and remote:IsA("RemoteFunction") then
			ok, result = pcall(function()
				return remote:InvokeServer(pack.id)
			end)
		end
		if ok and type(result) == "table" and result.ok then
			-- prompt ouvert : l'achat se termine avec PromptProductPurchaseFinished (pas avant, même après le délai)
			PurchaseGuard.promptOpened(guard, id)
			return
		end
		if id == guard.current then
			awaitingCredits = nil
		end
		endPurchase(PurchaseGuard.refused(guard, id))
		showStatus(PurchaseStatus.text(REFUSALS, if ok and type(result) == "table" then result.reason else nil))
	end)
end

-- Cette méthode permet de terminer l'achat en cours lorsque le prompt de Roblox se ferme (acheté ou annulé) ; une
-- annulation n'attend plus de crédits.
local function onPromptFinished(userId: number, productId: number, isPurchased: boolean)
	if userId ~= Players.LocalPlayer.UserId or not PurchaseGuard.finished(guard, productId) then
		return
	end
	if not isPurchased then
		awaitingCredits = nil
	end
	endPurchase(true)
end

-- Cette méthode permet de construire un pack (jeton, montant, CRÉDITS, prix en Robux dans un contour os) lorsque la
-- fenêtre est construite.
local function buildPack(parent: Frame, pack: CreditPacks.Pack, order: number)
	local column = UIKit.frame({
		Name = pack.id,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PACK_WIDTH, 260),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = column,
	})
	UIKit.creditIcon(column, PACK_ICON, 3, { LayoutOrder = 1 })
	local amount = UIKit.frame({
		Name = "Amount",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PACK_WIDTH, AMOUNT_SIZE + 6),
		LayoutOrder = 2,
		Parent = column,
	})
	UIKit.shadowedText(amount, {
		Name = "Value",
		Text = WalletRules.format(pack.credits),
		FontFace = F.Display,
		TextSize = AMOUNT_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, 3)
	UIKit.text({
		Name = "Currency",
		Text = WalletRules.CURRENCY,
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.TextSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(PACK_WIDTH, 22),
		LayoutOrder = 3,
		Parent = column,
	})
	-- Écart avant le prix : le contour se détache du montant
	UIKit.frame({
		Name = "Gap",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1, 10),
		LayoutOrder = 4,
		Parent = column,
	})
	local button = UIKit.frame({
		Name = "Price",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PRICE_SIZE.X, PRICE_SIZE.Y),
		LayoutOrder = 5,
		Parent = column,
	})
	UIKit.stroke(button, C.Bone, 2)
	local choice = MenuShot.textChoice({
		text = CreditPacks.priceLabel(pack),
		font = F.Display,
		size = 24,
		color = C.Bone,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		parent = button,
		action = function()
			requestPack(pack)
		end,
	})
	table.insert(priceChoices, choice)
	local labels: { TextLabel } = {}
	priceLabels[pack.productId] = labels
	for _, name in { "Label", "LabelShadow" } do
		local label = choice.button:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			table.insert(labels, label)
		end
	end
	paintPrice(pack)
	fetchPrice(pack)
end

-- Cette méthode permet d'annoncer en ambre les crédits d'un pack lorsque le solde monte de ce montant, fenêtre ouverte,
-- après un prompt pas annulé ; une autre hausse (gain, autre serveur) n'est pas annoncée et n'efface pas l'attente.
local function onBalance(balance: number?)
	local opened = page ~= nil and page.gui.Enabled
	local expected = awaitingCredits
	if opened and expected and balance and lastBalance and balance - lastBalance == expected then
		awaitingCredits = nil
		showStatus("+{amount} CRÉDITS", true, { amount = WalletRules.format(expected) })
	end
	lastBalance = balance
end

-- Cette méthode permet de construire la fenêtre (cachée) lorsque le menu est initialisé ; `onClose` ramène au shop.
function CreditPackWindow.init(onClose: () -> ())
	-- Sous les onglets du menu (4), au-dessus du shop (2) : le solde de la barre reste visible et suit les achats
	page = MenuPage.new("CreditPackWindow", 3, "PACKS DE CRÉDITS")
	-- Sous le voile central : la vitrine du shop garde des étiquettes claires qui ressortaient sur les côtés du voile
	-- et concurrençaient les packs (vu dans Studio) ; toute la salle est assombrie
	UIKit.frame({
		Name = "Dim",
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = DIM_TRANSPARENCY,
		Size = UDim2.fromScale(1, 1),
		ZIndex = -1,
		Parent = (page.group.Parent :: any) :: Instance,
	})
	local row = UIKit.frame({
		Name = "Packs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, PACKS_Y),
		Size = UDim2.new(1, 0, 0, 260),
		Parent = page.block,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 60),
		Parent = row,
	})
	for i, pack in CreditPacks.PACKS do
		buildPack(row, pack, i)
	end
	UIKit.text({
		Name = "Note",
		Text = "PAIEMENT EN ROBUX  ·  LES CRÉDITS ARRIVENT DÈS QUE ROBLOX CONFIRME L'ACHAT",
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, NOTE_Y),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = page.block,
	})
	status = UIKit.tag(page.block, "Status", 0, C.HitRed, C.Bone)
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, NOTE_Y + 36)
	status.ZIndex = 3
	status.Visible = false
	page.action("RETOUR", onClose)
	LocalWallet.observe(onBalance)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onPromptFinished)
	-- Restriction connue après l'ouverture (ou changée en Studio) : la fenêtre se ferme
	LocalWallet.observeRestricted(function(restricted: boolean?)
		if restricted ~= false and page.gui.Enabled then
			onClose()
		end
	end)
end

-- Cette méthode permet d'ouvrir la fenêtre lorsque le joueur clique « + CRÉDITS » ; refusée si le joueur n'est pas
-- connu comme non restreint (le bouton est alors masqué).
function CreditPackWindow.show()
	if not page or page.gui.Enabled or LocalWallet.restricted() ~= false then
		return
	end
	status.Visible = false
	lastBalance = LocalWallet.balance()
	-- Un achat lancé avant la fermeture garde les prix inactifs jusqu'à la fin de son prompt (ou PROMPT_TIMEOUT)
	setPricesEnabled(not guard.active)
	page.show()
end

-- Cette méthode permet de fermer la fenêtre lorsque le joueur clique RETOUR, change d'onglet ou lance la partie.
function CreditPackWindow.hide()
	awaitingCredits = nil
	if page and page.gui.Enabled then
		page.hide()
	end
end

-- Cette méthode permet de savoir si la fenêtre est ouverte lorsque le menu peint le bouton « + CRÉDITS ».
function CreditPackWindow.isOpen(): boolean
	return page ~= nil and page.gui.Enabled
end

return CreditPackWindow

-- Règles pures de la monnaie du jeu, les crédits (#391, #396) : montants valides, solde de départ, format du
-- portefeuille (clé `wallet` de l'enregistrement de l'inventaire, DataStore `PlayerInventory_v1`), relecture tolérante,
-- lots de gains d'une session, débit, attribut lu par le client et affichage. Utilisées par le serveur (InventoryRules,
-- InventoryStore, WalletStore) et le client (LocalWallet), testées (tests/specs/WalletRules.spec.luau).
--
-- Deux compteurs : `earned` (gagnés en jouant, doublons remboursés) et `purchased` (achetés en Robux, #395) ; le solde
-- est leur somme. Un gain ne réécrit pas le solde : la session envoie ses gains par lots numérotés (`Batch`) et la
-- fusion (`applyBatches`, appelée dans l'UpdateAsync de l'inventaire) les ajoute à `earned`. Deux serveurs qui écrivent
-- le même joueur additionnent leurs gains ; un lot renvoyé après une écriture passée mais signalée en échec n'est pas
-- compté deux fois (`writes` : dernier lot appliqué des sessions les plus récentes). Un débit, lui, se décide sur le
-- solde stocké, dans l'écriture même (`debit`, achetés d'abord) : un solde stocké n'est jamais négatif.
-- Champs posés pour la suite, sans logique ici : gains du jour (`day` = jour UTC, `dayEarned`, plafond du jour de
-- #394) et reçus Robux traités (`receipts`, PurchaseId de #395, liste bornée).
local WalletRules = {}

-- Lot de gains envoyé par une session : numéro croissant dans la session, crédits gagnés (positif ou nul)
export type Batch = { seq: number, earned: number }
export type WriteMark = { session: string, seq: number }
export type Wallet = {
	earned: number,
	purchased: number,
	day: number,
	dayEarned: number,
	receipts: { string },
	writes: { WriteMark },
}

-- Nom affiché de la monnaie (ShopCatalog.CURRENCY le reprend)
WalletRules.CURRENCY = "CRÉDITS"
-- Jeton du crédit (UIKit.creditIcon, étiquettes de la vitrine du shop) : jeton en laiton frappé d'un réticule, en
-- couleur (pas teinté). assets/ui/credits/jeton_credit.png (tools/ui/make_credit_icon.py, Decal 103980310535300 ;
-- ci-dessous l'id de l'image contenue dans le Decal)
WalletRules.ICON = "rbxassetid://133766247138455"
-- Solde d'un nouveau joueur (compté dans `earned`)
WalletRules.STARTING_BALANCE = 0
-- Plafond du solde : au-delà, un gain est écrêté (garde-fou contre un montant aberrant, loin de tout gain prévu)
WalletRules.MAX_BALANCE = 999_999_999
-- Sessions dont le dernier lot appliqué est retenu (les plus récentes) : de quoi reconnaître un lot renvoyé
WalletRules.MAX_WRITE_MARKS = 10
-- Reçus Robux retenus (les plus récents, #395) et longueur maximale d'un PurchaseId relu
WalletRules.MAX_RECEIPTS = 100
WalletRules.MAX_RECEIPT_LENGTH = 64

-- Cette méthode permet de savoir si une valeur est un solde valide (entier positif ou nul, fini, sous le plafond)
-- lorsqu'un enregistrement est relu ou un attribut décodé.
function WalletRules.isBalance(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= WalletRules.MAX_BALANCE and value == math.floor(value)
end

-- Cette méthode permet de savoir si un montant à ajouter ou retirer est valide (entier strictement positif, fini, sous
-- le plafond) lorsqu'un système serveur demande un gain ou une dépense.
function WalletRules.isAmount(value: any): boolean
	return WalletRules.isBalance(value) and value > 0
end

-- Cette méthode permet de savoir si un numéro (lot, jour) relu est valide (entier positif ou nul, fini).
local function isCount(value: any): boolean
	return type(value) == "number" and value >= 0 and value == math.floor(value) and value < math.huge
end

-- Cette méthode permet de ramener un solde dans [0, MAX_BALANCE] lorsqu'un écart est appliqué.
function WalletRules.clamp(balance: number): number
	return math.clamp(balance, 0, WalletRules.MAX_BALANCE)
end

-- Cette méthode permet de créer le portefeuille d'un joueur qui n'en a pas encore (nouveau joueur, enregistrement de
-- l'inventaire d'avant #396).
function WalletRules.empty(): Wallet
	return {
		earned = WalletRules.STARTING_BALANCE,
		purchased = 0,
		day = 0,
		dayEarned = 0,
		receipts = {},
		writes = {},
	}
end

-- Cette méthode permet de savoir si un portefeuille relu est réécrivable : absent, ou deux compteurs valides dont la
-- somme tient sous le plafond, champs facultatifs du bon type.
function WalletRules.isWritable(raw: any): boolean
	if raw == nil then
		return true
	end
	if type(raw) ~= "table" then
		return false
	end
	if not (WalletRules.isBalance(raw.earned) and WalletRules.isBalance(raw.purchased)) then
		return false
	end
	if raw.earned + raw.purchased > WalletRules.MAX_BALANCE then
		return false
	end
	return (raw.day == nil or isCount(raw.day))
		and (raw.dayEarned == nil or WalletRules.isBalance(raw.dayEarned))
		and (raw.receipts == nil or type(raw.receipts) == "table")
		and (raw.writes == nil or type(raw.writes) == "table")
end

-- Cette méthode permet de relire les marques de lots appliqués lorsqu'un portefeuille est relu : seules les entrées
-- bien formées, dans l'ordre (la plus récente en dernier).
local function readMarks(raw: any): { WriteMark }
	local marks: { WriteMark } = {}
	if type(raw) == "table" then
		for _, mark in ipairs(raw) do
			if type(mark) == "table" and type(mark.session) == "string" and isCount(mark.seq) then
				table.insert(marks, { session = mark.session, seq = mark.seq })
			end
		end
	end
	return marks
end

-- Cette méthode permet de relire les reçus traités lorsqu'un portefeuille est relu : PurchaseId (chaînes courtes) dans
-- l'ordre, les MAX_RECEIPTS plus récents.
local function readReceipts(raw: any): { string }
	local receipts: { string } = {}
	if type(raw) == "table" then
		for _, id in ipairs(raw) do
			if type(id) == "string" and #id > 0 and #id <= WalletRules.MAX_RECEIPT_LENGTH then
				table.insert(receipts, id)
			end
		end
	end
	while #receipts > WalletRules.MAX_RECEIPTS do
		table.remove(receipts, 1)
	end
	return receipts
end

-- Cette méthode permet de lire un portefeuille (copie assainie) lorsqu'un enregistrement est chargé, fusionné ou vient
-- d'être écrit : absent ou illisible → portefeuille de départ.
function WalletRules.read(raw: any): Wallet
	if raw == nil or not WalletRules.isWritable(raw) then
		return WalletRules.empty()
	end
	return {
		earned = raw.earned,
		purchased = raw.purchased,
		day = if raw.day ~= nil then raw.day else 0,
		dayEarned = if raw.dayEarned ~= nil then raw.dayEarned else 0,
		receipts = readReceipts(raw.receipts),
		writes = readMarks(raw.writes),
	}
end

-- Cette méthode permet de lire le solde d'un portefeuille (gagnés + achetés) lorsqu'il est publié ou vérifié.
function WalletRules.balance(wallet: Wallet): number
	return wallet.earned + wallet.purchased
end

-- Cette méthode permet de lire le numéro du dernier lot appliqué d'une session dans un portefeuille ; 0 si aucun.
function WalletRules.appliedSeq(wallet: Wallet, session: string): number
	for _, mark in wallet.writes do
		if mark.session == session then
			return mark.seq
		end
	end
	return 0
end

-- Cette méthode permet d'ajouter à `earned` (écrêté au plafond) les lots d'une session plus récents que sa marque, puis
-- d'avancer la marque jusqu'à `upTo`, lorsque l'UpdateAsync de l'inventaire fusionne ; pure, renvoie une copie.
function WalletRules.applyBatches(wallet: Wallet, session: string, batches: { Batch }, upTo: number): Wallet
	local result = WalletRules.read(wallet)
	local applied = WalletRules.appliedSeq(result, session)
	local gained = 0
	for _, batch in batches do
		if batch.seq > applied and batch.earned > 0 then
			gained += batch.earned
		end
	end
	local room = WalletRules.MAX_BALANCE - WalletRules.balance(result)
	result.earned += math.clamp(gained, 0, math.max(room, 0))
	if upTo > applied then
		for i, mark in result.writes do
			if mark.session == session then
				table.remove(result.writes, i)
				break
			end
		end
		table.insert(result.writes, { session = session, seq = upTo })
		while #result.writes > WalletRules.MAX_WRITE_MARKS do
			table.remove(result.writes, 1)
		end
	end
	return result
end

-- Cette méthode permet de débiter un portefeuille lorsqu'une transaction paie (achat, debug) : achetés d'abord, puis
-- gagnés ; nil et "insufficient" si le solde ne suffit pas, "invalid" si le montant n'est pas valide. Pure : copie.
function WalletRules.debit(wallet: Wallet, amount: number): (Wallet?, string?)
	if not WalletRules.isAmount(amount) then
		return nil, "invalid"
	end
	if WalletRules.balance(wallet) < amount then
		return nil, "insufficient"
	end
	local result = WalletRules.read(wallet)
	local fromPurchased = math.min(result.purchased, amount)
	result.purchased -= fromPurchased
	result.earned -= amount - fromPurchased
	return result
end

-- Lecture côté client : attribut informatif du Player (nombre entier, gagnés + achetés), posé par le serveur
-- (InventoryStore) une fois l'inventaire lu, puis à chaque changement ; jamais relu par le serveur. Absent : pas
-- (encore) chargé.
WalletRules.ATTRIBUTE = "Credits"

-- Cette méthode permet de relire l'attribut du Player lorsque le menu ou le shop affichent le solde ; nil (non chargé)
-- si l'attribut est absent ou invalide, jamais 0 par défaut.
function WalletRules.decode(value: any): number?
	return if WalletRules.isBalance(value) then value else nil
end

-- Cette méthode permet d'écrire un montant avec une espace tous les trois chiffres (« 12 500 ») lorsqu'un solde ou un
-- prix est affiché ; nil (non chargé) → « — ».
function WalletRules.format(amount: number?): string
	if amount == nil then
		return "—"
	end
	local digits = string.format("%.0f", amount)
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
	return (string.gsub(out, "^ ", ""))
end

return WalletRules

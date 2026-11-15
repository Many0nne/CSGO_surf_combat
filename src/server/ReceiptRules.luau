-- Règles pures des reçus Robux (#395), appliquées par ReceiptService (`MarketplaceService.ProcessReceipt`) : opération
-- de `InventoryStore.transact` qui ajoute les crédits d'un pack **et** inscrit le PurchaseId dans `wallet.receipts` dans
-- la même écriture, et décision rendue à Roblox selon l'issue de la transaction. Testées
-- (tests/specs/ReceiptRules.spec.luau ; écriture : tests/specs/WalletStore.spec.luau « Reçus Robux »).
--
-- Un PurchaseId déjà dans `receipts` (reçu rejoué par Roblox, deux serveurs, écriture passée mais signalée en échec)
-- fait refuser l'opération (`duplicate`) : rien n'est ajouté et le reçu est accordé. `receipts` garde les
-- `WalletRules.MAX_RECEIPTS` plus récents (le plus ancien sort à l'ajout, `WalletRules.read`).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local ReceiptRules = {}

-- Décision rendue à Roblox : `granted` (PurchaseGranted) ou `retry` (NotProcessedYet, reçu rejoué plus tard)
export type Verdict = "granted" | "retry"

-- Cette méthode permet de savoir si un PurchaseId reçu peut être inscrit dans `receipts` (chaîne non vide, assez
-- courte pour être relue) lorsqu'un reçu arrive.
function ReceiptRules.isPurchaseId(id: any): boolean
	return type(id) == "string" and #id > 0 and #id <= WalletRules.MAX_RECEIPT_LENGTH
end

-- Cette méthode permet de construire l'opération pure de `InventoryStore.transact` lorsqu'un reçu de pack est traité :
-- refus `duplicate` si le PurchaseId est déjà inscrit, `full` si le solde dépasserait le plafond ; sinon crédits ajoutés
-- à `purchased` (hors plafond du jour) et PurchaseId inscrit. Résultat : `{ credits }`.
function ReceiptRules.operation(purchaseId: string, credits: number): (record: any) -> (any, any)
	return function(record)
		local wallet = WalletRules.read(record.wallet)
		if table.find(wallet.receipts, purchaseId) then
			return nil, "duplicate"
		end
		if not WalletRules.isAmount(credits) or not ReceiptRules.isPurchaseId(purchaseId) then
			return nil, "invalid"
		end
		if WalletRules.balance(wallet) + credits > WalletRules.MAX_BALANCE then
			return nil, "full"
		end
		wallet.purchased += credits
		table.insert(wallet.receipts, purchaseId)
		record.wallet = wallet
		return record, { credits = credits }
	end
end

-- Cette méthode permet de traduire l'issue de la transaction d'un reçu en décision pour Roblox et en motif journalisé
-- lorsque l'écriture est terminée : accordé seulement si les crédits et le PurchaseId sont écrits (ou l'étaient déjà).
function ReceiptRules.decide(status: string, result: any): (Verdict, string)
	if status == "ok" then
		-- `ok` sans résultat : écriture passée mais signalée en échec, retrouvée par sa marque (crédits et reçu écrits)
		return "granted", if type(result) == "table" then "accordé" else "accordé (écriture rejouée)"
	elseif status == "rejected" then
		if result == "duplicate" then
			return "granted", "déjà traité (reçu rejoué)"
		end
		return "retry", "refusé par l'opération : " .. tostring(result)
	elseif status == "loading" then
		return "retry", "profil pas chargé ou pas sauvegardable"
	end
	return "retry", "écriture en échec"
end

return ReceiptRules

-- Règles pures de l'achat d'une caisse (#393), appliquées par CrateService : opération de la transaction de
-- l'inventaire (`InventoryStore.transact`, contrat dans docs/architecture.md « Crédits ») et réponse au client.
-- Testées (tests/specs/CratePurchaseRules.spec.luau ; écriture : tests/specs/WalletStore.spec.luau).
--
-- Le skin est tiré et le remboursement calculé **avant** la transaction : l'opération est pure (Roblox peut l'appeler
-- plusieurs fois), elle ne fait que lire l'enregistrement stocké. Elle débite le prix (achetés puis gagnés,
-- `WalletRules.debit`), puis ajoute le skin s'il n'est pas dans les items stockés, sinon crédite le remboursement dans
-- `earned`, hors plafond du jour (`dayEarned` n'est pas touché). Solde stocké insuffisant : refus, rien d'écrit.
-- #395 (joueur restreint par `PolicyService`) : seul `earned` pourra payer ; il suffira de remplacer `debit` ci-dessous
-- par un débit de `earned` seul, choisi par un champ de `Purchase`, sans toucher au reste.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local CratePurchaseRules = {}

-- Achat décidé avant la transaction : prix lu dans ShopCatalog, skin tiré, crédits rendus s'il est déjà possédé
export type Purchase = { price: number, skinId: string, refund: number }
-- Résultat de l'opération : le skin était-il déjà dans les items stockés (doublon remboursé)
export type Applied = { duplicate: boolean }
-- Réponse au client : { ok = true, skinId, rarity, added, refund } ou { ok = false, reason }
export type Reply = {
	ok: boolean,
	reason: string?,
	skinId: string?,
	rarity: string?,
	added: boolean?,
	refund: number?,
}

-- Cette méthode permet de débiter le prix d'un achat lorsque l'opération s'applique (point de réglage de #395).
local function debit(wallet: WalletRules.Wallet, purchase: Purchase): (WalletRules.Wallet?, string?)
	return WalletRules.debit(wallet, purchase.price)
end

-- Cette méthode permet de construire l'opération pure d'un achat lorsque CrateService la passe à
-- `InventoryStore.transact` : débit, puis skin ajouté ou remboursement crédité dans `earned` ; refus `insufficient` (ou
-- `invalid`) selon le solde stocké. Résultat : `Applied`.
function CratePurchaseRules.operation(purchase: Purchase): (record: any) -> (any, any)
	return function(record)
		local wallet, why = debit(record.wallet, purchase)
		if not wallet then
			return nil, why
		end
		local duplicate = table.find(record.items, purchase.skinId) ~= nil
		if duplicate then
			-- Remboursement ≤ prix : le solde reste sous celui d'avant l'achat, donc sous le plafond
			wallet.earned += math.clamp(purchase.refund, 0, purchase.price)
		else
			table.insert(record.items, purchase.skinId)
		end
		record.wallet = wallet
		return record, { duplicate = duplicate } :: Applied
	end
end

-- Cette méthode permet de traduire l'issue de la transaction en réponse au client lorsque l'écriture est terminée.
-- `ok` sans résultat (achat déjà écrit par un essai signalé en échec, réponse perdue) : l'achat est passé, le doublon se
-- déduit de ce que la session possédait avant l'achat (`ownedBefore`), seul cas ambigu : le même skin donné par un autre
-- serveur pendant cette écriture, répondu alors comme ajouté (le solde publié reste le bon).
function CratePurchaseRules.reply(
	status: string,
	result: any,
	purchase: Purchase,
	rarityId: string,
	ownedBefore: boolean
): Reply
	if status == "ok" then
		local duplicate = if type(result) == "table" then result.duplicate == true else ownedBefore
		return {
			ok = true,
			skinId = purchase.skinId,
			rarity = rarityId,
			added = not duplicate,
			refund = if duplicate then math.clamp(purchase.refund, 0, purchase.price) else 0,
		}
	elseif status == "rejected" then
		-- Seul un solde stocké trop bas est le fait du joueur ; un autre refus (opération invalide) est un bug serveur
		return { ok = false, reason = if result == "insufficient" then "insufficient" else "failed" }
	elseif status == "loading" then
		return { ok = false, reason = "loading" }
	end
	return { ok = false, reason = "failed" }
end

return CratePurchaseRules

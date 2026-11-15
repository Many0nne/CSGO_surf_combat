-- Règles pures de l'achat d'une caisse (#393), appliquées par CrateService : opération de la transaction de
-- l'inventaire (`InventoryStore.transact`, contrat dans docs/architecture.md « Crédits ») et réponse au client.
-- Testées (tests/specs/CratePurchaseRules.spec.luau ; écriture : tests/specs/WalletStore.spec.luau).
--
-- Le skin est tiré et le remboursement calculé **avant** la transaction : l'opération est pure (Roblox peut l'appeler
-- plusieurs fois), elle ne fait que lire l'enregistrement stocké. Elle débite le prix (achetés puis gagnés,
-- `WalletRules.debit`), puis ajoute le skin s'il n'est pas dans les items stockés, sinon rembourse le doublon dans le
-- compteur d'où le prix est venu (#395) : `purchased` à hauteur de ce qui en a été débité pour cet achat, le reste dans
-- `earned`, hors plafond du jour (`dayEarned` n'est pas touché). Un remboursement ne convertit donc jamais des crédits
-- achetés en crédits gagnés. Solde stocké insuffisant : refus, rien d'écrit. Un joueur restreint (objets aléatoires
-- payants, #395) n'arrive pas jusqu'ici : CrateService le refuse avant (`region`).
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

-- Cette méthode permet de lire les crédits rendus pour un doublon lorsque l'opération ou la réponse en a besoin : bornés
-- au prix, le solde reste ainsi sous celui d'avant l'achat, donc sous le plafond.
local function refundOf(purchase: Purchase): number
	return math.clamp(purchase.refund, 0, purchase.price)
end

-- Cette méthode permet de construire l'opération pure de `InventoryStore.transact` lorsqu'un achat est réglé : débit, puis
-- skin ajouté ou doublon remboursé dans le compteur débité ; refus selon le solde stocké. Résultat : `Applied`.
function CratePurchaseRules.operation(purchase: Purchase): (record: any) -> (any, any)
	return function(record)
		local before = WalletRules.read(record.wallet)
		local wallet, why = WalletRules.debit(before, purchase.price)
		if not wallet then
			return nil, why
		end
		local duplicate = table.find(record.items, purchase.skinId) ~= nil
		if duplicate then
			local refund = refundOf(purchase)
			-- Achetés d'abord, à hauteur de ce que cet achat en a pris : un joueur ne change pas de l'achat en gain
			local backToPurchased = math.min(refund, before.purchased - wallet.purchased)
			wallet.purchased += backToPurchased
			wallet.earned += refund - backToPurchased
		else
			table.insert(record.items, purchase.skinId)
		end
		record.wallet = wallet
		return record, { duplicate = duplicate } :: Applied
	end
end

-- Rejeu (`ok` sans résultat : achat écrit par un essai signalé en échec) : le doublon se déduit de ce que la session
-- possédait avant l'achat (`ownedBefore`) ; seul cas faux, le même skin donné par un autre serveur pendant l'écriture.
-- Cette méthode permet de traduire l'issue de la transaction en réponse au client lorsque l'écriture est terminée.
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
			refund = if duplicate then refundOf(purchase) else 0,
		}
	elseif status == "rejected" then
		-- Seul un solde stocké trop bas est le fait du joueur ; un autre refus (opération invalide) est un bug serveur
		return { ok = false, reason = if result == "insufficient" then "insufficient" else "failed" }
	elseif status == "loading" then
		return { ok = false, reason = "loading" }
	end
	-- `failed` : rien d'appliqué, sauf la limite documentée de `transact` (écriture passée dont la vérification échoue)
	return { ok = false, reason = "failed" }
end

return CratePurchaseRules

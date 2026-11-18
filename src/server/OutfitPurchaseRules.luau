-- Règles pures de l'achat d'une tenue de personnage (#543), appliquées par OutfitService : commande lue dans le catalogue,
-- opération de la transaction de l'inventaire (`InventoryStore.transact`, contrat dans docs/architecture.md « Crédits »)
-- et réponse au client. Testées (tests/specs/OutfitPurchaseRules.spec.luau ; écriture : tests/specs/WalletStore.spec.luau,
-- « Achat de tenue »).
--
-- Achat direct, sans tirage (ce n'est pas un objet aléatoire payant, docs/economie.md) : le client désigne une tenue, le
-- serveur relit son prix dans `InventoryRules.ITEMS` (`price`). Toute tenue du catalogue qui a un prix est en vente,
-- aucune n'est écrite ici. L'opération est pure (Roblox peut l'appeler plusieurs fois) : une tenue déjà dans les items
-- stockés (achetée entre-temps sur un autre serveur) n'est pas débitée, mais l'enregistrement est gardé tel quel (résultat
-- `owned`) : l'écriture réunit alors les items stockés à ceux de la session, qui apprend qu'elle la possède (sans quoi
-- l'onglet TENUE refuserait de l'équiper jusqu'à la session suivante). Solde stocké insuffisant : refus, rien d'écrit.
-- Sinon le prix est débité (achetés puis gagnés, `WalletRules.debit`) et la tenue ajoutée, dans la même écriture.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local WalletRules = require(ReplicatedStorage.Shared.WalletRules)
local TransactOutcome = require(ServerScriptService.Server.TransactOutcome)

local OutfitPurchaseRules = {}

-- Achat décidé avant la transaction : tenue et prix lus dans le catalogue
export type Purchase = { outfitId: string, price: number, rarity: string? }
-- Réponse au client : { ok = true, outfitId, rarity, price }, { ok = true, outfitId, rarity, replayed = true } (rejeu :
-- achetée ou déjà stockée, verdict inconnu, prix non compté) ou { ok = false, reason }
export type Reply = {
	ok: boolean,
	reason: string?,
	replayed: boolean?,
	outfitId: string?,
	rarity: string?,
	price: number?,
}

-- Résultat de l'opération quand la tenue est déjà dans les items stockés (rien de débité)
OutfitPurchaseRules.OWNED = "owned"

-- Cette méthode permet de lire la commande d'une tenue dans le catalogue lorsque le client en demande l'achat : refus
-- `unknown` (id inconnu ou item qui n'est pas une tenue) ou `unavailable` (tenue sans prix valide : pas en vente).
function OutfitPurchaseRules.order(outfitId: any): (Purchase?, string?)
	local item = if type(outfitId) == "string" then InventoryRules.item(outfitId) else nil
	if not item or item.type ~= InventoryRules.Type.OUTFIT then
		return nil, "unknown"
	end
	if not WalletRules.isAmount(item.price) then
		return nil, "unavailable"
	end
	return { outfitId = item.id, price = item.price :: number, rarity = item.rarity }
end

-- Cette méthode permet de construire l'opération pure de `InventoryStore.transact` lorsqu'un achat est réglé : tenue
-- déjà stockée gardée sans débit (résultat `owned`), refus si le solde stocké est trop bas, sinon débit et tenue ajoutée
-- (résultat : l'id ajouté).
function OutfitPurchaseRules.operation(purchase: Purchase): (record: any) -> (any, any)
	return function(record)
		if table.find(record.items, purchase.outfitId) ~= nil then
			return record, OutfitPurchaseRules.OWNED
		end
		local wallet, why = WalletRules.debit(WalletRules.read(record.wallet), purchase.price)
		if not wallet then
			return nil, why
		end
		table.insert(record.items, purchase.outfitId)
		record.wallet = wallet
		return record, purchase.outfitId
	end
end

-- Cette méthode permet de traduire l'issue de la transaction en réponse au client lorsque l'écriture est terminée. Un
-- rejeu (`ok` sans résultat : écrit par un essai signalé en échec, jamais réappliqué) laisse la tenue possédée, mais ne
-- dit pas si elle a été achetée ou trouvée déjà stockée : `replayed`, sans prix (les analytics ne comptent pas de
-- dépense incertaine ; le solde publié, lui, est juste).
function OutfitPurchaseRules.reply(status: string, result: any, purchase: Purchase): Reply
	if status == "ok" and result == OutfitPurchaseRules.OWNED then
		return { ok = false, reason = "owned" }
	elseif status == "ok" and result == nil then
		return { ok = true, outfitId = purchase.outfitId, rarity = purchase.rarity, replayed = true }
	elseif status == "ok" then
		return { ok = true, outfitId = purchase.outfitId, rarity = purchase.rarity, price = purchase.price }
	end
	-- Solde, chargement ou échec : traduits par TransactOutcome (même table que WalletStore.spend et les caisses)
	return { ok = false, reason = TransactOutcome.translate(status, result) }
end

return OutfitPurchaseRules

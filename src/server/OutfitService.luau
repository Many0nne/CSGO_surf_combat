-- Achat des tenues de personnage au portant du shop (#543), décidé par le serveur seul : le client ne désigne qu'une
-- tenue, le serveur relit son prix dans le catalogue (`InventoryRules.ITEMS`) et répond une fois l'écriture connue.
-- La tenue s'équipe ensuite dans l'onglet TENUE de l'écran d'équipement (remote `EquipItem`), pas ici.
--
-- Achat (remote `BuyOutfit`, RemoteFunction, tous les joueurs) : un seul achat en vol par joueur (un double clic est
-- refusé `busy` sans rien faire) ; refus avant toute écriture si la tenue est inconnue ou pas en vente, si le solde ne
-- peut pas changer (`WalletStore.canChange`) ou si la tenue est déjà possédée (admin compris : il les a toutes). Puis
-- une seule `InventoryStore.transact` qui revérifie la possession (déjà stockée : réécrite sans débit, `owned`) et le
-- solde stockés, débite et ajoute la tenue : `OutfitPurchaseRules`. Pas de restriction régionale : achat direct, sans tirage (docs/economie.md).
--
-- Réponses : { ok = true, outfitId, rarity, price } ou { ok = false, reason } avec reason = "rate" (garde commune),
-- "busy" (achat déjà en vol), "unknown" (id inconnu ou pas une tenue), "unavailable" (tenue sans prix), "loading"
-- (inventaire pas chargé ou non sauvegardable), "owned" (déjà possédée, vu par la session ou dans l'enregistrement
-- stocké), "insufficient" (solde stocké insuffisant), "failed" (écriture en échec : rien débité ni donné, sauf la limite
-- documentée de `InventoryStore.transact`).
local ServerScriptService = game:GetService("ServerScriptService")

local CheatLog = require(ServerScriptService.Server.CheatLog)
local InventoryStore = require(ServerScriptService.Server.InventoryStore)
local OutfitPurchaseRules = require(ServerScriptService.Server.OutfitPurchaseRules)
local WalletStore = require(ServerScriptService.Server.WalletStore)

export type Result = OutfitPurchaseRules.Reply

-- Joueurs dont un achat attend son écriture (au plus un chacun) ; retirés à la fin de l'achat, départ compris
local buying: { [Player]: boolean } = {}

local OutfitService = {}

-- Cette méthode permet de refuser un achat avec son motif lorsqu'il ne peut pas aboutir.
local function refuse(reason: string): Result
	return { ok = false, reason = reason }
end

-- Cette méthode permet de régler un achat lorsque son tour est pris (cf. `buy`) : commande lue au catalogue, refus sans
-- écriture, puis transaction.
local function purchase(player: Player, outfitId: string): Result
	local order, why = OutfitPurchaseRules.order(outfitId)
	if not order then
		return refuse(why or "unknown")
	end
	if not WalletStore.canChange(player) then
		return refuse("loading")
	end
	if InventoryStore.owned(player)[order.outfitId] then
		return refuse("owned")
	end
	local status, result = InventoryStore.transact(player, OutfitPurchaseRules.operation(order))
	return OutfitPurchaseRules.reply(status, result, order)
end

-- Cette méthode permet d'acheter une tenue lorsque le client clique ACHETER au portant : un seul achat en vol par joueur,
-- puis `purchase` ; bloquante jusqu'à l'écriture. Le tour est toujours rendu, même sur une erreur.
function OutfitService.buy(player: Player, outfitId: string): Result
	if buying[player] then
		return refuse("busy")
	end
	buying[player] = true
	local ok, result = pcall(purchase, player, outfitId)
	buying[player] = nil
	if not ok then
		warn("[OutfitService] achat en erreur pour", player.Name, ":", result)
		return refuse("failed")
	end
	return result
end

-- Cette méthode permet de brancher le remote d'achat lorsque le serveur démarre : garde commune (débit, type de l'id)
-- puis `OutfitService.buy`. Le thread d'un achat n'est jamais annulé (il porte l'écriture, cf. InventoryStore.transact).
-- `onBought` (analytics) reçoit chaque achat traité, avant la réponse au client.
function OutfitService.init(
	buyRemote: RemoteFunction,
	onBought: ((player: Player, outfitId: string, result: Result) -> ())?
)
	buyRemote.OnServerInvoke = function(player: Player, outfitId: any): Result
		if not CheatLog.admit(player, buyRemote.Name, outfitId) then
			return refuse("rate")
		end
		local result = OutfitService.buy(player, outfitId)
		if onBought then
			onBought(player, outfitId, result)
		end
		return result
	end
end

return OutfitService

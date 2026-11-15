-- Caisses de skins du shop, décidées par le serveur seul : le client ne désigne qu'une caisse, le serveur tire un skin de
-- l'arme de la caisse aux chances affichées (`Random` serveur, `ShopCatalog.draw`) et répond une fois l'issue connue.
--
-- Achat (#393, remote `BuyCrate`, RemoteFunction, tous les joueurs) : un seul achat en vol par joueur (un double clic
-- est refusé `busy` sans rien faire) ; refus avant tout tirage si la caisse est inconnue, si le joueur est restreint
-- (objets aléatoires payants, #395, `PaidRandomPolicy`), si le solde ne peut pas changer (inventaire pas chargé ou pas
-- sauvegardable, `WalletStore.canChange`) ou si tout son contenu est déjà possédé. Puis tirage, remboursement d'un
-- doublon lu dans `ShopCatalog`, et une seule `InventoryStore.transact` qui vérifie le solde stocké, débite et donne le
-- skin (ou rembourse le doublon dans le compteur débité) : `CratePurchaseRules`. La réponse ne part qu'après
-- l'écriture ; une écriture en échec ne débite rien et ne donne rien.
--
-- Ouverture de test (#332, remote `OpenCrate`, admin et Studio seulement) : gratuite, ni débit ni remboursement, un
-- doublon ne donne rien de plus (`added` = false) ; un autre joueur reçoit `forbidden`, sans journal.
--
-- Réponses : { ok = true, skinId, rarity (id de rareté), added, refund? } ou { ok = false, reason } avec reason = "rate"
-- (garde commune), "busy" (achat déjà en vol), "forbidden" (ouverture de test), "unknown" (caisse inconnue), "region"
-- (joueur restreint : objets aléatoires payants, #395), "loading"
-- (inventaire pas chargé ou non sauvegardable : rien de tiré), "owned" (tout le contenu déjà possédé), "empty" (caisse
-- sans skin connu), "insufficient" (solde stocké insuffisant), "failed" (écriture en échec : rien débité ni donné, sauf
-- la limite documentée de `InventoryStore.transact`, écriture passée dont la vérification échoue ; ne jamais rembourser
-- ni rejouer sur ce seul motif).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local CratePurchaseRules = require(ServerScriptService.Server.CratePurchaseRules)
local InventoryStore = require(ServerScriptService.Server.InventoryStore)
local PaidRandomPolicy = require(ServerScriptService.Server.PaidRandomPolicy)
local Roles = require(ServerScriptService.Server.Roles)
local WalletStore = require(ServerScriptService.Server.WalletStore)

export type Result = CratePurchaseRules.Reply

local random = Random.new()
-- Joueurs dont un achat attend son écriture (au plus un chacun) ; retirés à la fin de l'achat, départ compris
local buying: { [Player]: boolean } = {}

local CrateService = {}

-- Cette méthode permet de refuser une ouverture ou un achat avec son motif lorsqu'il ne peut pas aboutir.
local function refuse(reason: string): Result
	return { ok = false, reason = reason }
end

-- Cette méthode permet de tirer un nombre dans [0, 100) lorsqu'une caisse est ouverte ou achetée.
local function roll(): number
	return random:NextNumber(0, 100)
end

-- Cette méthode permet de savoir si un joueur peut ouvrir une caisse gratuitement (test) lorsqu'une demande arrive :
-- admin, ou n'importe qui dans Studio (#332).
function CrateService.canOpen(player: Player): boolean
	return RunService:IsStudio() or Roles.hasRole(player, Roles.ADMIN)
end

-- Cette méthode permet d'ouvrir une caisse gratuitement (test, #332) lorsque l'admin ou Studio la demande : droit,
-- caisse connue, inventaire prêt (avant tout tirage, pour ne pas perdre un skin), tirage serveur puis don du skin.
function CrateService.open(player: Player, crateId: string): Result
	if not CrateService.canOpen(player) then
		return refuse("forbidden")
	end
	local crate = ShopCatalog.crate(crateId)
	if not crate then
		return refuse("unknown")
	end
	if not InventoryStore.canGrant(player) then
		return refuse("loading")
	end
	local row, skinId = ShopCatalog.draw(crate, InventoryRules.ITEMS, roll())
	if not (row and skinId) then
		return refuse("empty")
	end
	local added = InventoryStore.grant(player, skinId)
	return { ok = true, skinId = skinId, rarity = row.rarity.id, added = added }
end

-- Cette méthode permet de régler un achat lorsque son tour est pris (cf. `buy`) : refus avant tirage, tirage, transaction.
local function purchase(player: Player, crateId: string): Result
	local crate = ShopCatalog.crate(crateId)
	if not crate then
		return refuse("unknown")
	end
	-- Chargé et sauvegardable, ou solde de session de Studio sans accès aux API (achat appliqué en mémoire) : c'est ce
	-- que `transact` accepte. `canGrant` refuserait ce dernier cas, sans rien protéger de plus.
	if not WalletStore.canChange(player) then
		return refuse("loading")
	end
	if ShopCatalog.allOwned(crate, InventoryRules.ITEMS, InventoryStore.owned(player)) then
		return refuse("owned")
	end
	-- Objets aléatoires payants (#395) : un joueur restreint (ou dont PolicyService n'a pas répondu) n'achète pas de
	-- caisse. Après les refus sans réseau : cet appel peut attendre PolicyService
	if PaidRandomPolicy.isRestricted(player) then
		return refuse("region")
	end
	local owned = InventoryStore.owned(player)
	local row, skinId = ShopCatalog.draw(crate, InventoryRules.ITEMS, roll())
	if not (row and skinId) then
		return refuse("empty")
	end
	local order: CratePurchaseRules.Purchase = {
		price = crate.price,
		skinId = skinId,
		refund = ShopCatalog.refund(crate, row.rarity.id),
	}
	local ownedBefore = owned[skinId] == true
	local status, result = InventoryStore.transact(player, CratePurchaseRules.operation(order))
	return CratePurchaseRules.reply(status, result, order, row.rarity.id, ownedBefore)
end

-- Cette méthode permet d'acheter et d'ouvrir une caisse lorsque le client clique ACHETER (#393) : un seul achat en vol
-- par joueur, puis `purchase` ; bloquante jusqu'à l'écriture. Le tour est toujours rendu, même sur une erreur.
function CrateService.buy(player: Player, crateId: string): Result
	if buying[player] then
		return refuse("busy")
	end
	buying[player] = true
	local ok, result = pcall(purchase, player, crateId)
	buying[player] = nil
	if not ok then
		warn("[CrateService] achat en erreur pour", player.Name, ":", result)
		return refuse("failed")
	end
	return result
end

-- Cette méthode permet de brancher les remotes d'ouverture de test et d'achat lorsque le serveur démarre : garde commune
-- (débit, type de l'id de caisse) puis `CrateService.open` ou `CrateService.buy`. Le thread d'un achat n'est jamais
-- annulé (il porte l'écriture, cf. InventoryStore.transact).
function CrateService.init(openRemote: RemoteFunction, buyRemote: RemoteFunction)
	openRemote.OnServerInvoke = function(player: Player, crateId: any): Result
		if not CheatLog.admit(player, openRemote.Name, crateId) then
			return refuse("rate")
		end
		return CrateService.open(player, crateId)
	end
	buyRemote.OnServerInvoke = function(player: Player, crateId: any): Result
		if not CheatLog.admit(player, buyRemote.Name, crateId) then
			return refuse("rate")
		end
		return CrateService.buy(player, crateId)
	end
end

return CrateService

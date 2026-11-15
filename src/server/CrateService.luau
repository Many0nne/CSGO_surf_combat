-- Ouverture des caisses de skins (#332), décidée par le serveur seul : le client désigne une caisse (remote
-- `OpenCrate`, RemoteFunction), le serveur tire un skin de l'arme de la caisse aux chances affichées (`Random` serveur,
-- `ShopCatalog.draw`), l'ajoute à l'inventaire (`InventoryStore.grant`) et renvoie le résultat. Un doublon est tiré
-- comme les autres et ne donne rien de plus (`added` = false). Réservé à l'admin (`Roles`) et à Studio tant que l'achat
-- n'existe pas : un autre joueur reçoit `forbidden`, sans journal (le bouton est BIENTÔT chez lui).
-- Réponse : { ok = true, skinId, rarity (id de rareté), added } ou { ok = false, reason } avec reason = "rate" (garde
-- commune), "forbidden", "unknown" (caisse inconnue), "loading" (inventaire pas chargé ou non sauvegardable : rien de tiré),
-- "empty" (caisse sans skin connu).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local InventoryStore = require(ServerScriptService.Server.InventoryStore)
local Roles = require(ServerScriptService.Server.Roles)

export type Result = { ok: boolean, reason: string?, skinId: string?, rarity: string?, added: boolean? }

local random = Random.new()

local CrateService = {}

-- Cette méthode permet de refuser une ouverture avec son motif lorsqu'elle ne peut pas aboutir.
local function refuse(reason: string): Result
	return { ok = false, reason = reason }
end

-- Cette méthode permet de savoir si un joueur peut ouvrir une caisse lorsqu'une demande arrive : admin, ou n'importe
-- qui dans Studio (achat pas encore décidé, #332).
function CrateService.canOpen(player: Player): boolean
	return RunService:IsStudio() or Roles.hasRole(player, Roles.ADMIN)
end

-- Cette méthode permet d'ouvrir une caisse lorsque le client la demande : droit, caisse connue, inventaire prêt (avant
-- tout tirage, pour ne pas perdre un skin), tirage serveur puis don du skin.
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
	local row, skinId = ShopCatalog.draw(crate, InventoryRules.ITEMS, random:NextNumber(0, 100))
	if not (row and skinId) then
		return refuse("empty")
	end
	local added = InventoryStore.grant(player, skinId)
	return { ok = true, skinId = skinId, rarity = row.rarity.id, added = added }
end

-- Cette méthode permet de brancher le remote d'ouverture lorsque le serveur démarre : garde commune (débit, type de
-- l'id de caisse) puis `CrateService.open`.
function CrateService.init(openRemote: RemoteFunction)
	openRemote.OnServerInvoke = function(player: Player, crateId: any): Result
		if not CheatLog.admit(player, openRemote.Name, crateId) then
			return refuse("rate")
		end
		return CrateService.open(player, crateId)
	end
end

return CrateService

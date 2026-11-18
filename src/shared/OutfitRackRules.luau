-- Règles pures du portant des tenues du shop (#543, docs/ui.md « Portant des tenues ») : tenues en vente (toutes les
-- tenues du catalogue qui ont un prix, même règle que OutfitPurchaseRules.order côté serveur), place de chacune sur les
-- barres du portant, cintres vides pour compléter, et sortie du rang de la tenue survolée. Testées
-- (tests/specs/OutfitRackRules.spec.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local OutfitRackRules = {}

-- Cintres par barre au moins : avec moins de tenues, des cintres vides complètent le rang (un portant à moitié vide
-- faisait magasin en rupture, comme la vitrine des caisses sans son stock)
OutfitRackRules.MIN_SLOTS = 6
-- Marge entre le premier cintre et le montant, de chaque côté (studs) : la tenue de trois quarts déborde de son cintre
OutfitRackRules.SIDE_MARGIN = 1.5
-- Tenue de trois quarts dans le rang, de face quand elle en sort (degrés, autour de la verticale, dans le repère du
-- portant) ; avancée vers la pièce quand elle sort (studs)
OutfitRackRules.RANK_YAW = 145
OutfitRackRules.OUT_YAW = 176
OutfitRackRules.OUT_STEP = 1.9

export type Slot = { x: number, outfit: number? }

-- Cette méthode permet de lister les tenues en vente au portant (tenue du catalogue avec un prix valide), dans l'ordre du
-- catalogue (prix puis nom), lorsque le portant se construit ou que la vue détail passe à la voisine.
function OutfitRackRules.forSale(): { InventoryRules.Item }
	local list = {}
	for _, item in InventoryRules.outfits() do
		if WalletRules.isAmount(item.price) then
			table.insert(list, item)
		end
	end
	return list
end

-- Cette méthode permet de placer `count` tenues sur une barre de `width` studs lorsque le portant se construit : au
-- moins MIN_SLOTS cintres répartis à pas égal entre les marges, tenues au milieu du rang dans l'ordre donné, cintres
-- vides de part et d'autre. Chaque place : `x` (centre, repère du portant) et `outfit` (rang de la tenue, nil : vide).
function OutfitRackRules.slots(count: number, width: number): { Slot }
	local n = math.max(OutfitRackRules.MIN_SLOTS, count)
	local inner = width - 2 * OutfitRackRules.SIDE_MARGIN
	local step = if n > 1 then inner / (n - 1) else 0
	local first = (n - count) // 2 -- cintres vides à gauche ; le reste à droite
	local list = {}
	for i = 1, n do
		local rank = i - first
		table.insert(list, {
			x = -inner / 2 + (i - 1) * step,
			outfit = if rank >= 1 and rank <= count then rank else nil,
		})
	end
	return list
end

-- Cette méthode permet de donner l'orientation (degrés) et l'avancée (studs) d'une tenue sur le portant selon sa sortie
-- du rang `out` (0 : dans le rang, 1 : sortie, survolée) lorsqu'une image est rendue.
function OutfitRackRules.pose(out: number): (number, number)
	local t = math.clamp(out, 0, 1)
	local yaw = OutfitRackRules.RANK_YAW + (OutfitRackRules.OUT_YAW - OutfitRackRules.RANK_YAW) * t
	return yaw, OutfitRackRules.OUT_STEP * t
end

return OutfitRackRules

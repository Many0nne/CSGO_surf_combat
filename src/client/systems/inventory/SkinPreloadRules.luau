-- Règles pures du préchargement des skins (#333, #342) : quels skins demander d'après les attributs `OwnedItems` et
-- `EquippedItems` d'un joueur (le local ou un autre), sans toucher au moteur. SkinPreloader en tire les cartes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)

local SkinPreloadRules = {}

export type Request = { viewmodel: string, skin: string }

-- Cette méthode permet de lister les skins équipés d'un joueur (viewmodel et id), au plus un par emplacement
-- (`#InventoryRules.SLOTS`, borne tenue par decodeEquipped), lorsque ses attributs `OwnedItems` / `EquippedItems` arrivent ou changent ; `viewmodelOf` donne le
-- viewmodel d'un Tool. Attribut absent ou illisible : équipement par défaut, donc aucun skin.
function SkinPreloadRules.skinsOf(
	ownedText: any,
	equippedText: any,
	viewmodelOf: (toolName: string) -> string
): { Request }
	local equipped = InventoryRules.decodeEquipped(equippedText, InventoryRules.decode(ownedText))
	local requests: { Request } = {}
	for _, toolName in InventoryRules.equippedTools(equipped) do
		local skin = InventoryRules.skinOfTool(equipped, toolName)
		if skin then
			table.insert(requests, { viewmodel = viewmodelOf(toolName), skin = skin })
		end
	end
	return requests
end

-- Cette méthode permet de ne garder que les cartes jamais demandées lorsqu'une liste d'ids arrive ; marque chacune
-- dans `requested` et renvoie les nouvelles, dans l'ordre, sans doublon.
function SkinPreloadRules.fresh(uris: { string }, requested: { [string]: boolean }): { string }
	local list: { string } = {}
	for _, uri in uris do
		if not requested[uri] then
			requested[uri] = true
			table.insert(list, uri)
		end
	end
	return list
end

return SkinPreloadRules

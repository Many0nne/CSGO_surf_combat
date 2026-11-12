-- Copie client de l'inventaire du joueur (#267) et de son équipement (#280) : lus dans les attributs informatifs
-- `OwnedItems` et `EquippedItems` posés par le serveur (InventoryStore), pour l'accueil du menu (MainMenu, MenuScene) et
-- les Réglages (SettingsMenu). N'ouvre aucun droit : le serveur seul donne les Tools, valide l'équipement et l'usage des
-- armes. Sans attribut (pas encore répliqué) : l'inventaire et l'équipement par défaut.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))

local LocalInventory = {}

local player = Players.LocalPlayer

-- Cette méthode permet de lire les items possédés lorsqu'une liste du menu se construit.
function LocalInventory.owned(): InventoryRules.Owned
	return InventoryRules.decode(player:GetAttribute(InventoryRules.ATTRIBUTE))
end

-- Cette méthode permet de lire les noms des Tools possédés, triés, lorsqu'une liste d'armes se construit.
function LocalInventory.ownedTools(): { string }
	return InventoryRules.ownedTools(LocalInventory.owned())
end

-- Cette méthode permet de savoir si un Tool est possédé lorsqu'une liste d'armes le filtre.
function LocalInventory.ownsTool(toolName: string): boolean
	return InventoryRules.ownsTool(LocalInventory.owned(), toolName)
end

-- Cette méthode permet de lire l'équipement appliqué (arme et skin par emplacement) lorsque l'accueil ou les Réglages
-- l'affichent.
function LocalInventory.equipped(): InventoryRules.Equipped
	return InventoryRules.decodeEquipped(player:GetAttribute(InventoryRules.EQUIPPED_ATTRIBUTE), LocalInventory.owned())
end

-- Cette méthode permet de lister les Tools équipés, dans l'ordre des emplacements, lorsque les lignes de touches des
-- Réglages se nomment.
function LocalInventory.equippedTools(): { string }
	return InventoryRules.equippedTools(LocalInventory.equipped())
end

-- Cette méthode permet de demander au serveur d'équiper une arme et son skin (nil : d'origine) dans un emplacement
-- lorsque le joueur clique à l'accueil ; l'attribut `EquippedItems` change si le serveur accepte.
function LocalInventory.equip(slot: InventoryRules.Slot, weaponId: string, skinId: string?)
	local remote = ReplicatedStorage:FindFirstChild(NetworkProtocol.Names.EQUIP_ITEM)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(slot, weaponId, skinId or "")
	end
end

-- Cette méthode permet d'être prévenu lorsque l'inventaire ou l'équipement change (arrivée des attributs, chargement
-- DataStore, choix du joueur) ; renvoie les deux connexions.
function LocalInventory.onChanged(callback: () -> ()): { RBXScriptConnection }
	return {
		player:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(callback),
		player:GetAttributeChangedSignal(InventoryRules.EQUIPPED_ATTRIBUTE):Connect(callback),
	}
end

return LocalInventory

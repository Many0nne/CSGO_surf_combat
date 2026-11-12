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

local REMOTE_WAIT = 10 -- s d'attente maximale du remote EquipItem (pas encore répliqué juste après l'arrivée)

local player = Players.LocalPlayer
-- Attributs décodés, gardés jusqu'à leur prochain changement : l'accueil les relit à chaque survol
local ownedCache: InventoryRules.Owned? = nil
local equippedCache: InventoryRules.Equipped? = nil
-- Numéro de l'inventaire possédé, augmenté à chaque changement : les listes gardées ailleurs (MenuScene) s'y comparent
local ownedVersion = 0

-- Cette méthode permet d'oublier l'inventaire décodé (et l'équipement, qui en dépend) lorsque `OwnedItems` change.
local function invalidateOwned()
	ownedCache = nil
	equippedCache = nil
	ownedVersion += 1
end
-- Cette méthode permet d'oublier l'équipement décodé lorsque `EquippedItems` change.
local function invalidateEquipped()
	equippedCache = nil
end
player:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(invalidateOwned)
player:GetAttributeChangedSignal(InventoryRules.EQUIPPED_ATTRIBUTE):Connect(invalidateEquipped)

-- Cette méthode permet de lire le numéro de l'inventaire possédé lorsqu'une liste gardée doit savoir si elle est périmée.
function LocalInventory.version(): number
	return ownedVersion
end

-- Cette méthode permet de lire les items possédés lorsqu'une liste du menu se construit.
function LocalInventory.owned(): InventoryRules.Owned
	local owned = ownedCache or InventoryRules.decode(player:GetAttribute(InventoryRules.ATTRIBUTE))
	ownedCache = owned
	return owned
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
	local equipped = equippedCache
		or InventoryRules.decodeEquipped(player:GetAttribute(InventoryRules.EQUIPPED_ATTRIBUTE), LocalInventory.owned())
	equippedCache = equipped
	return equipped
end

-- Cette méthode permet de lister les Tools équipés, dans l'ordre des emplacements, lorsque les lignes de touches des
-- Réglages se nomment.
function LocalInventory.equippedTools(): { string }
	return InventoryRules.equippedTools(LocalInventory.equipped())
end

-- Cette méthode permet de demander au serveur d'équiper une arme et son skin (nil : d'origine) lorsque le joueur clique
-- à l'accueil ; le remote est attendu s'il n'est pas encore répliqué. `EquippedItems` change si le serveur accepte.
function LocalInventory.equip(slot: InventoryRules.Slot, weaponId: string, skinId: string?)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.EQUIP_ITEM, REMOTE_WAIT)
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(slot, weaponId, skinId or "")
		end
	end)
end

-- Cette méthode permet d'être prévenu une fois lorsque l'inventaire ou l'équipement change, les deux attributs posés
-- ensemble par le serveur ne donnant qu'un appel (différé) ; renvoie les deux connexions.
function LocalInventory.onChanged(callback: () -> ()): { RBXScriptConnection }
	local pending = false
	-- Cette méthode permet de programmer un seul appel du rappel lorsque l'un des deux attributs change.
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			callback()
		end)
	end
	return {
		player:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(schedule),
		player:GetAttributeChangedSignal(InventoryRules.EQUIPPED_ATTRIBUTE):Connect(schedule),
	}
end

return LocalInventory

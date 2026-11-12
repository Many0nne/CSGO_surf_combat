-- Copie client de l'inventaire du joueur (#267) : lue dans l'attribut informatif `OwnedItems` posé par le serveur
-- (InventoryStore), pour les listes d'armes du menu (MenuScene) et des Réglages (SettingsMenu). N'ouvre aucun droit : le
-- serveur seul donne les Tools et valide leur usage. Sans attribut (pas encore répliqué) : l'inventaire par défaut.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryRules"))

local LocalInventory = {}

local player = Players.LocalPlayer

-- Cette méthode permet de lire les noms des Tools possédés, dans l'ordre de la barre d'armes, lorsqu'une liste d'armes
-- se construit.
function LocalInventory.ownedTools(): { string }
	return InventoryRules.ownedTools(InventoryRules.decode(player:GetAttribute(InventoryRules.ATTRIBUTE)))
end

-- Cette méthode permet de savoir si un Tool est possédé lorsqu'une liste d'armes le filtre.
function LocalInventory.ownsTool(toolName: string): boolean
	return InventoryRules.ownsTool(InventoryRules.decode(player:GetAttribute(InventoryRules.ATTRIBUTE)), toolName)
end

-- Cette méthode permet d'être prévenu lorsque l'inventaire change (arrivée de l'attribut, chargement DataStore).
function LocalInventory.onChanged(callback: () -> ()): RBXScriptConnection
	return player:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(callback)
end

return LocalInventory

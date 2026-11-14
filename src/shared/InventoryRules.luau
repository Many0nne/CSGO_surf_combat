-- Règles pures de l'inventaire (#267) : catalogue des items, inventaire par défaut, items possédés (défaut + données
-- sauvegardées + tout pour un admin), format sauvegardé et repli si le DataStore est indisponible. Partagé : le serveur
-- décide (InventoryStore), le client n'en lit que l'attribut informatif `OwnedItems` pour ses listes d'armes.
-- Testées (tests/specs/InventoryRules.spec.luau).
--
-- Format d'un item : id stable en minuscules (« weapon.awp », « skin.awp.<nom> » pour #268), indépendant du nom du Tool
-- (renommer un Tool ne change que `tool`), et un type. Un `weapon` désigne son Tool (`tool`) et son emplacement
-- (`slot`) ; un `skin` désigne l'id de son arme (`weapon`). La sauvegarde ne garde que des ids : ajouter un type ou des
-- items n'oblige à aucune migration.
--
-- Équipement (#280) : un joueur équipe une arme par emplacement (SNIPER, COUTEAU) et un skin de cette arme (nil : skin
-- « d'origine »). Seules ces armes vont dans le sac. Le choix est sauvegardé tel quel (`equipped` de PlayerInventory_v1)
-- et résolu à chaque usage contre les items possédés : un item qui n'est plus possédé (rôle retiré) laisse la place à
-- l'équipement par défaut, sans effacer le choix enregistré.
local InventoryRules = {}

export type ItemType = "weapon" | "skin"
export type Slot = "sniper" | "knife"
-- Un skin porte aussi son nom affiché (`name`) et le nom de ses SurfaceAppearance (`appearance` : dossier
-- ReplicatedStorage.Skins.<viewmodel de l'arme>.<appearance>, cf. WeaponSkins)
export type Item = {
	id: string,
	type: ItemType,
	tool: string?,
	slot: Slot?,
	weapon: string?,
	name: string?,
	appearance: string?,
}
-- Items possédés : ensemble d'ids du catalogue
export type Owned = { [string]: boolean }
-- Équipement d'un emplacement : id de l'arme, id du skin (nil : d'origine)
export type Loadout = { weapon: string, skin: string? }
-- Équipement par emplacement ; une version enregistrée peut être partielle, une version résolue est complète
export type Equipped = { [string]: Loadout }

InventoryRules.SCHEMA_VERSION = 1
-- Attribut informatif posé par le serveur sur le Player (ids séparés par des virgules) : il n'ouvre aucun droit, le
-- serveur ne le relit jamais (comme l'attribut `Role`, #266)
InventoryRules.ATTRIBUTE = "OwnedItems"
-- Attribut informatif de l'équipement résolu (#280), même statut : « arme[:skin] » par emplacement, dans l'ordre de SLOTS
InventoryRules.EQUIPPED_ATTRIBUTE = "EquippedItems"
-- Emplacements, dans l'ordre de la barre d'armes et des touches (1 · SNIPER, 2 · COUTEAU)
InventoryRules.SLOTS = { "sniper", "knife" } :: { Slot }
-- Bornes des données relues du DataStore : un id plus long ou au-delà du nombre maximal est ignoré
InventoryRules.MAX_ID_LENGTH = 64
InventoryRules.MAX_STORED = 512
local ID_PATTERN = "^[%l%d_]+[%l%d_%.]*$"

InventoryRules.Type = {
	WEAPON = "weapon" :: ItemType,
	SKIN = "skin" :: ItemType,
}

-- Catalogue : tous les items du jeu. Ajouter une arme = une ligne ici (et son Tool dans assets/rbx/Tools).
InventoryRules.ITEMS = {
	{ id = "weapon.awp", type = "weapon", tool = "AWP", slot = "sniper" },
	{ id = "weapon.kabar", type = "weapon", tool = "KaBar", slot = "knife" },
	{ id = "weapon.m9bayonet", type = "weapon", tool = "M9Bayonet", slot = "knife" },
	-- Skins (#268), par paires AWP + M9 sur un même thème ; obtenus plus tard par les caisses (l'admin les a tous)
	{ id = "skin.awp.couchant", type = "skin", weapon = "weapon.awp", name = "COUCHANT", appearance = "couchant" },
	{ id = "skin.awp.impact", type = "skin", weapon = "weapon.awp", name = "IMPACT", appearance = "impact" },
	{ id = "skin.awp.releve", type = "skin", weapon = "weapon.awp", name = "RELEVÉ", appearance = "releve" },
	{
		id = "skin.m9bayonet.couchant",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "COUCHANT",
		appearance = "couchant",
	},
	{
		id = "skin.m9bayonet.impact",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "IMPACT",
		appearance = "impact",
	},
	{
		id = "skin.m9bayonet.releve",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "RELEVÉ",
		appearance = "releve",
	},
} :: { Item }

-- Inventaire de tout joueur (et des bots), sauvegardé ou non : Ka-Bar et AWP
InventoryRules.DEFAULT_ITEMS = { "weapon.awp", "weapon.kabar" }
-- Équipement par défaut (#280), pris dans l'inventaire par défaut : il est donc toujours possédé
InventoryRules.DEFAULT_EQUIPPED = { sniper = "weapon.awp", knife = "weapon.kabar" } :: { [string]: string }

local byId: { [string]: Item } = {}
-- Id de l'arme dont le Tool porte ce nom : la possession d'un Tool se lit sans parcourir le catalogue (tir, equip)
local weaponIdByTool: { [string]: string } = {}

-- Cette méthode permet d'indexer le catalogue par id et par nom de Tool lorsque le module se charge, ou lorsqu'un test
-- ajoute des items à ITEMS (skins de test, aucun skin n'existant avant #268).
function InventoryRules.reindex()
	table.clear(byId)
	table.clear(weaponIdByTool)
	for _, entry in InventoryRules.ITEMS do
		byId[entry.id] = entry
		if entry.type == "weapon" and entry.tool then
			weaponIdByTool[entry.tool] = entry.id
		end
	end
end
InventoryRules.reindex()
local slotIndex: { [string]: number } = {}
for i, slot in InventoryRules.SLOTS do
	slotIndex[slot] = i
end

-- Cette méthode permet de lire la fiche d'un item du catalogue par son id lorsqu'un système en a besoin ; nil si inconnu.
function InventoryRules.item(id: string): Item?
	return byId[id]
end

-- Cette méthode permet de savoir si une valeur a la forme d'un id d'item (chaîne courte en minuscules, chiffres, `_` et
-- `.`) lorsqu'elle est relue du DataStore ou du catalogue.
function InventoryRules.isValidId(id: any): boolean
	return type(id) == "string" and #id <= InventoryRules.MAX_ID_LENGTH and string.match(id, ID_PATTERN) ~= nil
end

-- Cette méthode permet d'assainir les ids relus du DataStore lorsqu'ils sont chargés ou réécrits : valides, uniques, triés,
-- `limit` au plus (MAX_STORED par défaut) ; un id hors catalogue est gardé pour ne jamais le perdre, sans rien ouvrir.
function InventoryRules.sanitizeStored(raw: any, limit: number?): { string }
	local ids: { string } = {}
	if type(raw) ~= "table" then
		return ids
	end
	local max = limit or InventoryRules.MAX_STORED
	local seen: { [string]: boolean } = {}
	for _, id in ipairs(raw) do
		if #ids >= max then
			break
		end
		if InventoryRules.isValidId(id) and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Cette méthode permet d'assainir l'équipement relu ou réécrit lorsqu'il est chargé ou sauvegardé : par emplacement connu,
-- un id d'arme valide et un skin valide ou absent, sans confronter au catalogue (un choix plus possédé reste enregistré).
function InventoryRules.sanitizeEquipped(raw: any): Equipped
	local equipped: Equipped = {}
	if type(raw) ~= "table" then
		return equipped
	end
	for _, slot in InventoryRules.SLOTS do
		local entry = raw[slot]
		if type(entry) == "table" and InventoryRules.isValidId(entry.weapon) then
			local skin = entry.skin
			equipped[slot] = { weapon = entry.weapon, skin = if InventoryRules.isValidId(skin) then skin else nil }
		end
	end
	return equipped
end

-- Cette méthode permet de savoir si une valeur relue du DataStore est d'un format que cette version sait réécrire :
-- absente (nouveau joueur), ou table de schéma connu (pas plus récent) dont `items` est une liste ou absent et
-- `equipped` (#280) une table ou absent.
local function isWritable(data: any): boolean
	if data == nil then
		return true
	end
	if type(data) ~= "table" then
		return false
	end
	local version = data.schemaVersion
	if version ~= nil and (type(version) ~= "number" or version > InventoryRules.SCHEMA_VERSION) then
		return false
	end
	return (data.items == nil or type(data.items) == "table")
		and (data.equipped == nil or type(data.equipped) == "table")
end

-- Cette méthode permet de décider des ids, du droit d'écrire et de l'équipement relu lorsque le chargement DataStore se
-- termine : échec ou format inconnu/plus récent → sauvegarde coupée ; aucune donnée → écriture permise, équipement vide.
function InventoryRules.loadOutcome(ok: boolean, data: any): ({ string }, boolean, Equipped)
	if not ok then
		return {}, false, {}
	end
	local tableData = if type(data) == "table" then data else nil
	return InventoryRules.sanitizeStored(tableData and tableData.items),
		isWritable(data),
		InventoryRules.sanitizeEquipped(tableData and tableData.equipped)
end

-- Cette méthode permet de construire la valeur écrite dans le DataStore lorsqu'un inventaire est sauvegardé ;
-- l'équipement n'est écrit que s'il y en a un (choisi ou déjà enregistré).
function InventoryRules.payload(
	stored: { string },
	equipped: Equipped?
): { schemaVersion: number, items: { string }, equipped: Equipped? }
	local hasEquipped = equipped ~= nil and next(equipped) ~= nil
	return {
		schemaVersion = InventoryRules.SCHEMA_VERSION,
		items = table.clone(stored),
		equipped = if hasEquipped then table.clone(equipped :: Equipped) else nil,
	}
end

-- Cette méthode permet de calculer la valeur écrite par UpdateAsync lorsqu'un inventaire est sauvegardé : ids réunis sans
-- plafond (un inventaire ne fait que grandir), équipement enregistré remplacé emplacement par emplacement par la session.
function InventoryRules.mergeForSave(
	old: any,
	stored: { string },
	equipped: Equipped?
): { schemaVersion: number, items: { string }, equipped: Equipped? }?
	if not isWritable(old) then
		return nil
	end
	local merged = table.clone(if type(old) == "table" and type(old.items) == "table" then old.items else {})
	table.move(stored, 1, #stored, #merged + 1, merged)
	-- Un emplacement que la session n'a pas choisi garde ce qu'un autre serveur a pu écrire entre-temps ; un emplacement
	-- inconnu de cette version (ajouté plus tard) est recopié tel quel, pas effacé
	local oldEquipped = if type(old) == "table" and type(old.equipped) == "table" then old.equipped else {}
	local keptEquipped: Equipped = {}
	for key, value in oldEquipped do
		if type(key) == "string" and not slotIndex[key] then
			keptEquipped[key] = value
		end
	end
	for slot, loadout in InventoryRules.sanitizeEquipped(oldEquipped) do
		keptEquipped[slot] = loadout
	end
	for slot, loadout in InventoryRules.sanitizeEquipped(equipped) do
		keptEquipped[slot] = loadout
	end
	return InventoryRules.payload(InventoryRules.sanitizeStored(merged, math.huge), keptEquipped)
end

-- Cette méthode permet de calculer les items possédés lorsqu'un système en a besoin : défaut + ids sauvegardés connus +
-- tout le catalogue pour un admin (jamais sauvegardé) ; stored nil : rien de sauvegardé (bot, chargement pas abouti).
function InventoryRules.resolve(stored: { string }?, isAdmin: boolean): Owned
	local owned: Owned = {}
	for _, id in InventoryRules.DEFAULT_ITEMS do
		owned[id] = true
	end
	local saved: { string } = stored or {}
	for _, id in saved do
		if byId[id] then
			owned[id] = true
		end
	end
	if isAdmin then
		for _, entry in InventoryRules.ITEMS do
			owned[entry.id] = true
		end
	end
	return owned
end

-- Cette méthode permet de savoir si un Tool est possédé (arme du catalogue dont le Tool porte ce nom) lorsque le serveur
-- distribue les outils ou valide un equip, un tir ou un coup ; un Tool hors catalogue n'est jamais possédé.
function InventoryRules.ownsTool(owned: Owned, toolName: string): boolean
	local id = weaponIdByTool[toolName]
	return id ~= nil and owned[id] == true
end

-- Cette méthode permet de lister les noms des Tools possédés, triés comme la barre d'armes, lorsque le serveur remplit
-- le sac ou que le client liste ses armes.
function InventoryRules.ownedTools(owned: Owned): { string }
	local names: { string } = {}
	for _, entry in InventoryRules.ITEMS do
		if entry.type == "weapon" and entry.tool and owned[entry.id] then
			table.insert(names, entry.tool)
		end
	end
	table.sort(names)
	return names
end

-- Cette méthode permet de lire le rang d'un emplacement (1 · SNIPER, 2 · COUTEAU) lorsqu'une liste suit leur ordre ;
-- nil pour un emplacement inconnu.
function InventoryRules.slotIndex(slot: any): number?
	return if type(slot) == "string" then slotIndex[slot] else nil
end

-- Cette méthode permet de lire l'emplacement de l'arme dont le Tool porte ce nom lorsque la barre d'armes ou les
-- Réglages rangent les armes ; nil hors catalogue.
function InventoryRules.slotOfTool(toolName: string): Slot?
	local id = weaponIdByTool[toolName]
	local entry = id and byId[id]
	return entry and entry.slot
end

-- Cette méthode permet de lister les armes possédées d'un emplacement, triées par nom de Tool, lorsque l'écran
-- d'équipement ouvre la liste de cet emplacement.
function InventoryRules.weaponsForSlot(owned: Owned, slot: Slot): { Item }
	local list: { Item } = {}
	for _, entry in InventoryRules.ITEMS do
		if entry.type == "weapon" and entry.slot == slot and owned[entry.id] then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return (a.tool or a.id) < (b.tool or b.id)
	end)
	return list
end

-- Cette méthode permet de lister les skins possédés d'une arme, triés par id, lorsque l'écran d'équipement montre ses
-- skins (le skin « d'origine », toujours disponible, n'est pas un item).
function InventoryRules.skinsFor(owned: Owned, weaponId: string): { Item }
	local list: { Item } = {}
	for _, entry in InventoryRules.ITEMS do
		if entry.type == "skin" and entry.weapon == weaponId and owned[entry.id] then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Cette méthode permet de savoir si un équipement d'emplacement est valide pour ces items possédés lorsqu'il est résolu
-- ou demandé : arme possédée de cet emplacement, skin nil ou possédé et de cette arme. Renvoie aussi le motif d'un refus.
local function checkLoadout(owned: Owned, slot: string, weaponId: any, skinId: any): (boolean, string?)
	local weapon = type(weaponId) == "string" and byId[weaponId]
	if not (weapon and weapon.type == "weapon") then
		return false, "unknown"
	end
	if weapon.slot ~= slot then
		return false, "wrong_slot"
	end
	if not owned[weapon.id] then
		return false, "not_owned"
	end
	if skinId == nil then
		return true
	end
	local skin = type(skinId) == "string" and byId[skinId]
	if not (skin and skin.type == "skin" and skin.weapon == weapon.id) then
		return false, "wrong_skin"
	end
	if not owned[skin.id] then
		return false, "not_owned"
	end
	return true
end

-- Cette méthode permet de calculer l'équipement appliqué lorsque le serveur remplit le sac ou que le client l'affiche :
-- par emplacement, le choix enregistré s'il reste valide (skin invalide → d'origine), sinon l'arme par défaut.
function InventoryRules.resolveEquipped(equipped: Equipped?, owned: Owned): Equipped
	local resolved: Equipped = {}
	for _, slot in InventoryRules.SLOTS do
		local chosen = equipped and equipped[slot]
		if chosen and checkLoadout(owned, slot, chosen.weapon, nil) then
			local skinOk = chosen.skin ~= nil and checkLoadout(owned, slot, chosen.weapon, chosen.skin)
			resolved[slot] = { weapon = chosen.weapon, skin = if skinOk then chosen.skin else nil }
		else
			resolved[slot] = { weapon = InventoryRules.DEFAULT_EQUIPPED[slot] }
		end
	end
	return resolved
end

-- Cette méthode permet de valider un choix d'arme ou de skin lorsque le joueur clique à l'accueil : nouvel équipement
-- (copie), ou nil et le motif (`slot`, `unknown`, `wrong_slot`, `not_owned`, `wrong_skin`).
function InventoryRules.equip(
	equipped: Equipped,
	owned: Owned,
	slot: any,
	weaponId: any,
	skinId: any
): (Equipped?, string?)
	if not InventoryRules.slotIndex(slot) then
		return nil, "slot"
	end
	local ok, reason = checkLoadout(owned, slot, weaponId, skinId)
	if not ok then
		return nil, reason
	end
	local nextEquipped = InventoryRules.sanitizeEquipped(equipped)
	nextEquipped[slot] = { weapon = weaponId, skin = skinId }
	return nextEquipped
end

-- Cette méthode permet de lister les Tools d'un équipement résolu, dans l'ordre des emplacements, lorsque le serveur
-- remplit le sac.
function InventoryRules.equippedTools(resolved: Equipped): { string }
	local names: { string } = {}
	for _, slot in InventoryRules.SLOTS do
		local loadout = resolved[slot]
		local weapon = loadout and byId[loadout.weapon]
		if weapon and weapon.tool then
			table.insert(names, weapon.tool)
		end
	end
	return names
end

-- Cette méthode permet de lire le skin équipé de l'arme dont le Tool porte ce nom lorsqu'elle est rendue (1re personne,
-- 3e personne, accueil) ; nil : skin d'origine, ou arme absente de l'équipement résolu.
function InventoryRules.skinOfTool(resolved: Equipped, toolName: string): string?
	local weaponId = weaponIdByTool[toolName]
	if not weaponId then
		return nil
	end
	for _, slot in InventoryRules.SLOTS do
		local loadout = resolved[slot]
		if loadout and loadout.weapon == weaponId then
			return loadout.skin
		end
	end
	return nil
end

-- Cette méthode permet de comparer les Tools d'un joueur (sac et main) à ceux voulus (#280 : armes équipées) lorsque le
-- serveur les synchronise : noms à donner (voulus, absents) et noms à retirer (présents, non voulus).
function InventoryRules.toolChanges(wanted: { string }, present: { string }): ({ string }, { string })
	local has: { [string]: boolean } = {}
	local remove: { string } = {}
	for _, name in present do
		has[name] = true
		if not table.find(wanted, name) and not table.find(remove, name) then
			table.insert(remove, name)
		end
	end
	local give: { string } = {}
	for _, name in wanted do
		if not has[name] then
			table.insert(give, name)
		end
	end
	return give, remove
end

-- Cette méthode permet d'ajouter un item aux ids sauvegardés lorsqu'il est obtenu (boutique, déblocage : hors #267) ;
-- renvoie la nouvelle liste et false si l'id est inconnu du catalogue ou déjà présent.
function InventoryRules.grant(stored: { string }, id: string): ({ string }, boolean)
	if not byId[id] or table.find(stored, id) then
		return stored, false
	end
	local ids = table.clone(stored)
	table.insert(ids, id)
	table.sort(ids)
	return ids, true
end

-- Cette méthode permet d'écrire les items possédés dans l'attribut informatif du Player lorsqu'ils changent (ids triés,
-- séparés par des virgules).
function InventoryRules.encode(owned: Owned): string
	local ids: { string } = {}
	for id, isOwned in owned do
		if isOwned then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

-- Cette méthode permet de relire l'attribut informatif côté client lorsqu'il change : inventaire par défaut (toujours
-- possédé, et seul connu tant que l'attribut n'est pas répliqué) plus les ids connus de l'attribut.
function InventoryRules.decode(text: any): Owned
	local owned = InventoryRules.resolve(nil, false)
	if type(text) ~= "string" then
		return owned
	end
	for id in string.gmatch(text, "[^,]+") do
		if byId[id] then
			owned[id] = true
		end
	end
	return owned
end

-- Cette méthode permet d'écrire l'équipement résolu dans l'attribut informatif du Player lorsqu'il change : « arme » ou
-- « arme:skin » par emplacement, dans l'ordre de SLOTS, séparés par des virgules.
function InventoryRules.encodeEquipped(resolved: Equipped): string
	local parts: { string } = {}
	for _, slot in InventoryRules.SLOTS do
		local loadout = resolved[slot]
		if loadout then
			table.insert(parts, if loadout.skin then loadout.weapon .. ":" .. loadout.skin else loadout.weapon)
		else
			table.insert(parts, "")
		end
	end
	return table.concat(parts, ",")
end

-- Cette méthode permet de relire l'attribut d'équipement côté client lorsqu'il change : choix lus par emplacement puis
-- résolus contre les items possédés (équipement par défaut tant que l'attribut n'est pas répliqué).
function InventoryRules.decodeEquipped(text: any, owned: Owned): Equipped
	local equipped: Equipped = {}
	if type(text) == "string" then
		local index = 0
		for part in string.gmatch(text .. ",", "([^,]*),") do
			index += 1
			local slot = InventoryRules.SLOTS[index]
			if not slot then
				break
			end
			local weapon, skin = string.match(part, "^([^:]+):?(.*)$")
			if weapon then
				equipped[slot] = { weapon = weapon, skin = if skin ~= "" then skin else nil }
			end
		end
	end
	return InventoryRules.resolveEquipped(equipped, owned)
end

return InventoryRules

-- Règles pures de l'inventaire (#267) : catalogue des items, inventaire par défaut, items possédés (défaut + données
-- sauvegardées + tout pour un admin), format sauvegardé et repli si le DataStore est indisponible. Partagé : le serveur
-- décide (InventoryStore), le client n'en lit que l'attribut informatif `OwnedItems` pour ses listes d'armes.
-- Testées (tests/specs/InventoryRules.spec.luau).
--
-- Format d'un item : id stable en minuscules (« weapon.awp », « skin.awp.<nom> » pour #268), indépendant du nom du Tool
-- (renommer un Tool ne change que `tool`), et un type. Un `weapon` désigne son Tool (`tool`) ; un `skin` désignera l'id
-- de son arme (`weapon`). La sauvegarde ne garde que des ids : ajouter un type ou des items n'oblige à aucune migration.
local InventoryRules = {}

export type ItemType = "weapon" | "skin"
export type Item = { id: string, type: ItemType, tool: string?, weapon: string? }
-- Items possédés : ensemble d'ids du catalogue
export type Owned = { [string]: boolean }

InventoryRules.SCHEMA_VERSION = 1
-- Attribut informatif posé par le serveur sur le Player (ids séparés par des virgules) : il n'ouvre aucun droit, le
-- serveur ne le relit jamais (comme l'attribut `Role`, #266)
InventoryRules.ATTRIBUTE = "OwnedItems"
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
	{ id = "weapon.awp", type = "weapon", tool = "AWP" },
	{ id = "weapon.kabar", type = "weapon", tool = "KaBar" },
	{ id = "weapon.m9bayonet", type = "weapon", tool = "M9Bayonet" },
} :: { Item }

-- Inventaire de tout joueur (et des bots), sauvegardé ou non : Ka-Bar et AWP
InventoryRules.DEFAULT_ITEMS = { "weapon.awp", "weapon.kabar" }

local byId: { [string]: Item } = {}
for _, entry in InventoryRules.ITEMS do
	byId[entry.id] = entry
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

-- Cette méthode permet d'assainir les ids sauvegardés lorsqu'ils sont relus du DataStore : chaînes valides seulement,
-- sans doublon, triées, MAX_STORED au plus. Un id absent du catalogue est gardé (item retiré, ou ajouté par une version
-- plus récente du jeu) pour ne jamais le perdre à la sauvegarde suivante ; il n'ouvre rien tant qu'il est inconnu.
function InventoryRules.sanitizeStored(raw: any): { string }
	local ids: { string } = {}
	if type(raw) ~= "table" then
		return ids
	end
	local seen: { [string]: boolean } = {}
	for _, id in ipairs(raw) do
		if #ids >= InventoryRules.MAX_STORED then
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

-- Cette méthode permet de savoir si une valeur relue du DataStore est d'un format que cette version sait réécrire :
-- absente (nouveau joueur), ou table de schéma connu (pas plus récent) dont `items` est une liste ou absent.
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
	return data.items == nil or type(data.items) == "table"
end

-- Cette méthode permet de décider de l'issue du chargement DataStore d'un inventaire lorsqu'il se termine : ids
-- sauvegardés et droit d'écrire. Lecture en échec : inventaire par défaut et sauvegarde coupée, pour ne pas écraser les
-- vraies données ; aucune donnée (nouveau joueur) : rien de sauvegardé, écriture permise ; données d'un format inconnu
-- ou d'une version plus récente du jeu : ids lisibles gardés, sauvegarde coupée.
function InventoryRules.loadOutcome(ok: boolean, data: any): ({ string }, boolean)
	if not ok then
		return {}, false
	end
	return InventoryRules.sanitizeStored(if type(data) == "table" then data.items else nil), isWritable(data)
end

-- Cette méthode permet de construire la valeur écrite dans le DataStore lorsqu'un inventaire est sauvegardé.
function InventoryRules.payload(stored: { string }): { schemaVersion: number, items: { string } }
	return { schemaVersion = InventoryRules.SCHEMA_VERSION, items = table.clone(stored) }
end

-- Cette méthode permet de calculer la valeur écrite par UpdateAsync lorsqu'un inventaire est sauvegardé : ids déjà
-- enregistrés (autre serveur, sauvegarde en retard) réunis avec ceux de la session, un inventaire ne faisant que
-- grandir. nil (écriture annulée) si l'enregistrement est d'un format que cette version ne sait pas réécrire.
function InventoryRules.mergeForSave(old: any, stored: { string }): { schemaVersion: number, items: { string } }?
	if not isWritable(old) then
		return nil
	end
	local merged = InventoryRules.sanitizeStored(if type(old) == "table" then old.items else nil)
	for _, id in stored do
		if InventoryRules.isValidId(id) and not table.find(merged, id) then
			table.insert(merged, id)
		end
	end
	return InventoryRules.payload(InventoryRules.sanitizeStored(merged))
end

-- Cette méthode permet de calculer les items possédés lorsqu'un système serveur en a besoin : inventaire par défaut,
-- plus les items sauvegardés connus du catalogue, plus tout le catalogue pour un admin (jamais sauvegardé : retirer le
-- rôle retire les items). stored nil : rien de sauvegardé (bot, chargement en cours ou en échec).
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
	for _, entry in InventoryRules.ITEMS do
		if entry.type == "weapon" and entry.tool == toolName and owned[entry.id] then
			return true
		end
	end
	return false
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

-- Cette méthode permet de lister tous les Tools d'armes du catalogue, triés, lorsque l'interface prévoit une ligne par
-- arme possible (Réglages).
function InventoryRules.catalogTools(): { string }
	return InventoryRules.ownedTools(InventoryRules.resolve(nil, true))
end

-- Cette méthode permet de comparer les Tools présents chez un joueur (sac et main) à son inventaire lorsque le serveur
-- les synchronise : noms à donner (possédés, absents) et noms à retirer (présents, non possédés).
function InventoryRules.toolChanges(owned: Owned, present: { string }): ({ string }, { string })
	local has: { [string]: boolean } = {}
	local remove: { string } = {}
	for _, name in present do
		has[name] = true
		if not InventoryRules.ownsTool(owned, name) and not table.find(remove, name) then
			table.insert(remove, name)
		end
	end
	local give: { string } = {}
	for _, name in InventoryRules.ownedTools(owned) do
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

-- Cette méthode permet de relire l'attribut informatif côté client lorsqu'il change ; sans attribut (pas encore
-- répliqué), l'inventaire par défaut.
function InventoryRules.decode(text: any): Owned
	if type(text) ~= "string" then
		return InventoryRules.resolve(nil, false)
	end
	local owned: Owned = {}
	for id in string.gmatch(text, "[^,]+") do
		if byId[id] then
			owned[id] = true
		end
	end
	return owned
end

return InventoryRules

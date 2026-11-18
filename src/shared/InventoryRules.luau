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
-- « d'origine »), et une tenue de personnage (#521, emplacement `outfit` hors de SLOTS : rien dans le sac ; nil : tenue
-- d'origine). Seules ces armes vont dans le sac. Le choix est sauvegardé tel quel (`equipped` de PlayerInventory_v1)
-- et résolu à chaque usage contre les items possédés : un item qui n'est plus possédé (rôle retiré) laisse la place à
-- l'équipement par défaut, sans effacer le choix enregistré.
--
-- Portefeuille (#396) : les crédits vivent dans le même enregistrement (clé `wallet`, format de WalletRules), pour
-- qu'une seule UpdateAsync change à la fois le solde et les objets (achat de caisse #393, reçu Robux #395). La fusion
-- (`mergeForSave`) réunit les objets, l'équipement choisi et les lots de gains de la session, puis applique s'il y en a
-- une l'opération d'une transaction (`Operation`), qui peut refuser selon l'état stocké. Contrat dans
-- docs/architecture.md (« Crédits »).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local InventoryRules = {}

export type ItemType = "weapon" | "skin" | "outfit"
export type Slot = "sniper" | "knife"
-- Un skin porte aussi son nom affiché (`name`) et le nom de ses SurfaceAppearance (`appearance` : dossier
-- ReplicatedStorage.Skins.<viewmodel de l'arme>.<appearance>, cf. WeaponSkins), et peut déclarer un effet de tir
-- (`shotEffect`, #520 : "lightning" = éclair à la place du rayon de balle, cf. ShotEffectRules.effectOf). Une tenue
-- (#521) porte son nom affiché, son dossier d'apparence (ReplicatedStorage.Outfits.<appearance>, cf. CharacterAppearance),
-- sa rareté (id de ShopCatalog.RARITIES) et son prix en crédits.
export type Item = {
	id: string,
	type: ItemType,
	tool: string?,
	slot: Slot?,
	weapon: string?,
	name: string?,
	appearance: string?,
	shotEffect: string?,
	rarity: string?,
	price: number?,
}
-- Items possédés : ensemble d'ids du catalogue
export type Owned = { [string]: boolean }
-- Équipement d'un emplacement : id de l'arme, id du skin (nil : d'origine). Emplacement `outfit` (#521) : `weapon` porte
-- l'id de la tenue (OUTFIT_NONE : tenue d'origine choisie), sans skin.
export type Loadout = { weapon: string, skin: string? }
-- Équipement par emplacement ; une version enregistrée peut être partielle, une version résolue est complète
export type Equipped = { [string]: Loadout }
-- Enregistrement de PlayerInventory_v1 (schéma 2, #396 ; le schéma 1 n'avait pas `wallet`)
export type Record = { schemaVersion: number, items: { string }, equipped: Equipped?, wallet: WalletRules.Wallet }
-- Gains d'une session envoyés avec une écriture : lots pas encore confirmés et numéro du dernier lot envoyé (`upTo`,
-- celui d'une transaction compris : il marque l'opération comme appliquée)
export type WalletChange = { session: string, batches: { WalletRules.Batch }, upTo: number }
-- Opération d'une transaction : reçoit une copie de l'enregistrement fusionné (stocké + session), renvoie
-- l'enregistrement voulu, ou nil pour refuser (rien n'est écrit), et un résultat libre rendu à l'appelant. Pure : Roblox
-- peut l'appeler plusieurs fois. Seuls `wallet` (compteurs, jour, reçus) et les ajouts à `items` sont gardés.
export type Operation = (record: Record) -> (Record?, any)
-- Issue d'une fusion : sans opération (`merged`), opération appliquée (`applied`), déjà appliquée par une écriture
-- signalée en échec (`replayed`, rien de réappliqué), refusée par l'opération (`rejected`, rien à écrire) ou format
-- stocké refusé (`refused`, rien à écrire)
export type MergeStatus = "merged" | "applied" | "replayed" | "rejected" | "refused"

-- 2 (#396) : portefeuille `wallet` ; un enregistrement 1 se relit avec le portefeuille de départ et se réécrit en 2
InventoryRules.SCHEMA_VERSION = 2
-- Attribut informatif posé par le serveur sur le Player (ids séparés par des virgules) : il n'ouvre aucun droit, le
-- serveur ne le relit jamais (comme l'attribut `Role`, #266)
InventoryRules.ATTRIBUTE = "OwnedItems"
-- Attribut informatif de l'équipement résolu (#280), même statut : « arme[:skin] » par emplacement, dans l'ordre de SLOTS
InventoryRules.EQUIPPED_ATTRIBUTE = "EquippedItems"
-- Emplacements, dans l'ordre de la barre d'armes et des touches (1 · SNIPER, 2 · COUTEAU)
InventoryRules.SLOTS = { "sniper", "knife" } :: { Slot }
-- Emplacement de la tenue de personnage (#521), à part des armes : il n'entre ni dans le sac ni dans la barre d'armes
InventoryRules.OUTFIT_SLOT = "outfit"
-- Choix enregistré « tenue d'origine » : un id absent du catalogue, pour qu'un retour à l'origine écrase une tenue
-- enregistrée par un autre serveur (un emplacement vide laisserait l'ancien choix en place, cf. mergeForSave)
InventoryRules.OUTFIT_NONE = "outfit.none"
-- Bornes des données relues du DataStore : un id plus long ou au-delà du nombre maximal est ignoré
InventoryRules.MAX_ID_LENGTH = 64
InventoryRules.MAX_STORED = 512
local ID_PATTERN = "^[%l%d_]+[%l%d_%.]*$"

InventoryRules.Type = {
	WEAPON = "weapon" :: ItemType,
	SKIN = "skin" :: ItemType,
	OUTFIT = "outfit" :: ItemType,
}

-- Catalogue : tous les items du jeu. Ajouter une arme = une ligne ici (et son Tool dans assets/rbx/Tools).
InventoryRules.ITEMS = {
	{ id = "weapon.awp", type = "weapon", tool = "AWP", slot = "sniper" },
	{ id = "weapon.kabar", type = "weapon", tool = "KaBar", slot = "knife" },
	{ id = "weapon.m9bayonet", type = "weapon", tool = "M9Bayonet", slot = "knife" },
	-- Skins AWP (#417) : dessinés pour la nouvelle AWP, un script par skin dans assets/awp/skins ; obtenus par les
	-- caisses (l'admin les a tous)
	{
		id = "skin.awp.balise",
		type = "skin",
		weapon = "weapon.awp",
		name = "BALISE",
		appearance = "balise",
	},
	{
		id = "skin.awp.trempe",
		type = "skin",
		weapon = "weapon.awp",
		name = "TREMPE",
		appearance = "trempe",
	},
	{
		id = "skin.awp.ciselure",
		type = "skin",
		weapon = "weapon.awp",
		name = "CISELURE",
		appearance = "ciselure",
	},
	{
		id = "skin.awp.pan",
		type = "skin",
		weapon = "weapon.awp",
		name = "PAN !",
		appearance = "pan",
	},
	{
		id = "skin.awp.orage",
		type = "skin",
		weapon = "weapon.awp",
		name = "ORAGE",
		appearance = "orage",
		shotEffect = "lightning",
	},
	{
		id = "skin.awp.circuit",
		type = "skin",
		weapon = "weapon.awp",
		name = "CIRCUIT",
		appearance = "circuit",
	},
	{
		id = "skin.awp.maquis",
		type = "skin",
		weapon = "weapon.awp",
		name = "MAQUIS",
		appearance = "maquis",
	},
	{
		id = "skin.awp.mue",
		type = "skin",
		weapon = "weapon.awp",
		name = "MUE",
		appearance = "mue",
	},
	-- Série FILM (#433) : hommage au film de science-fiction de 1979, sans reprise directe (assets/awp/skins/remorqueur.py)
	{
		id = "skin.awp.remorqueur",
		type = "skin",
		weapon = "weapon.awp",
		name = "REMORQUEUR",
		appearance = "remorqueur",
	},
	-- Série FILM (#436) : hommage au film de 2016 (vaisseau-pierre, écriture circulaire), logogrammes inventés
	-- (assets/awp/skins/logogramme.py)
	{
		id = "skin.awp.logogramme",
		type = "skin",
		weapon = "weapon.awp",
		name = "LOGOGRAMME",
		appearance = "logogramme",
	},
	-- Communs de la série 1 : motifs réguliers dessinés pour l'AWP (assets/awp/skins/epure.py, tartan.py, banche.py)
	{
		id = "skin.awp.epure",
		type = "skin",
		weapon = "weapon.awp",
		name = "ÉPURE",
		appearance = "epure",
	},
	{
		id = "skin.awp.tartan",
		type = "skin",
		weapon = "weapon.awp",
		name = "TARTAN",
		appearance = "tartan",
	},
	{
		id = "skin.awp.banche",
		type = "skin",
		weapon = "weapon.awp",
		name = "BANCHE",
		appearance = "banche",
	},
	-- Communs de la série 2 (#482), en réserve tant que la caisse n'est pas complète (assets/awp/skins/parquet.py,
	-- cannage.py, tole.py)
	{
		id = "skin.awp.parquet",
		type = "skin",
		weapon = "weapon.awp",
		name = "PARQUET",
		appearance = "parquet",
	},
	{
		id = "skin.awp.cannage",
		type = "skin",
		weapon = "weapon.awp",
		name = "CANNAGE",
		appearance = "cannage",
	},
	{
		id = "skin.awp.tole",
		type = "skin",
		weapon = "weapon.awp",
		name = "TÔLE LARMÉE",
		appearance = "tole",
	},
	-- Rares de la série 2 (#487), en réserve tant que la caisse n'est pas complète (assets/awp/skins/capiton.py,
	-- vitrail.py, laque.py)
	{
		id = "skin.awp.capiton",
		type = "skin",
		weapon = "weapon.awp",
		name = "CAPITON",
		appearance = "capiton",
	},
	{
		id = "skin.awp.vitrail",
		type = "skin",
		weapon = "weapon.awp",
		name = "VITRAIL",
		appearance = "vitrail",
	},
	{
		id = "skin.awp.laque",
		type = "skin",
		weapon = "weapon.awp",
		name = "LAQUE",
		appearance = "laque",
	},
	-- Exceptionnel de la série 2 (#492, refait en #508 : VELOURS devient MARQUETERIE, même id pour qui le possède) :
	-- illustration peinte sur le gabarit de l'AWP (assets/awp/skins/marqueterie.py)
	{
		id = "skin.awp.velours",
		type = "skin",
		weapon = "weapon.awp",
		name = "MARQUETERIE",
		appearance = "marqueterie",
	},
	-- Skins M9 : COUCHANT, RELEVÉ, RECUIT (#268, #337, motifs calculés) ; ÉMAIL, PATROUILLE, ART DÉCO dessinés pour la
	-- M9 (#420, assets/m9/skins/) à la place d'IMPACT, STRATE et SILLAGE
	{
		id = "skin.m9bayonet.couchant",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "COUCHANT",
		appearance = "couchant",
	},
	{
		id = "skin.m9bayonet.releve",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "RELEVÉ",
		appearance = "releve",
	},
	{
		id = "skin.m9bayonet.recuit",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "RECUIT",
		appearance = "recuit",
	},
	{
		id = "skin.m9bayonet.email",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "ÉMAIL",
		appearance = "email",
	},
	{
		id = "skin.m9bayonet.patrouille",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "PATROUILLE",
		appearance = "patrouille",
	},
	{
		id = "skin.m9bayonet.artdeco",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "ART DÉCO",
		appearance = "artdeco",
	},
	-- Série FILM (#433) : biomécanique de Giger, sans reprise directe (assets/m9/skins/hote.py)
	{
		id = "skin.m9bayonet.hote",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "HÔTE",
		appearance = "hote",
	},
	-- Série FILM (#436) : hommage au film de 1991 par son papillon, le sphinx tête-de-mort (assets/m9/skins/sphinx.py)
	{
		id = "skin.m9bayonet.sphinx",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "SPHINX",
		appearance = "sphinx",
	},
	-- Communs de la série 1 (#476) : motifs sobres dessinés pour la M9 (assets/m9/skins/leurre.py, chantier.py, topo.py,
	-- ceramique.py)
	{
		id = "skin.m9bayonet.leurre",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "LEURRE",
		appearance = "leurre",
	},
	{
		id = "skin.m9bayonet.chantier",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "CHANTIER",
		appearance = "chantier",
	},
	{
		id = "skin.m9bayonet.topo",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "TOPO",
		appearance = "topo",
	},
	{
		id = "skin.m9bayonet.ceramique",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "CÉRAMIQUE",
		appearance = "ceramique",
	},
	-- Rare de la série 1 : acier guilloché sous émail, médaillon en rosace (assets/m9/skins/guilloche.py)
	{
		id = "skin.m9bayonet.guilloche",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "GUILLOCHÉ",
		appearance = "guilloche",
	},
	-- Communs et rares de la série 2 (#495), matières d'intérieur, en réserve tant que la caisse n'est pas complète
	-- (assets/m9/skins/piedpoule.py, tomette.py, azulejo.py, nacre.py)
	{
		id = "skin.m9bayonet.piedpoule",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "PIED-DE-POULE",
		appearance = "piedpoule",
	},
	{
		id = "skin.m9bayonet.tomette",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "TOMETTE",
		appearance = "tomette",
	},
	{
		id = "skin.m9bayonet.azulejo",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "AZULEJO",
		appearance = "azulejo",
	},
	{
		id = "skin.m9bayonet.nacre",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "NACRE",
		appearance = "nacre",
	},
	-- Exceptionnels de la série 2 (#505) : illustrations peintes sur le gabarit de la lame (assets/m9/skins/gabarit.py,
	-- chinoiserie.py, tapisserie.py), en réserve tant que la caisse n'a pas son légendaire
	{
		id = "skin.m9bayonet.chinoiserie",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "CHINOISERIE",
		appearance = "chinoiserie",
	},
	{
		id = "skin.m9bayonet.tapisserie",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "TAPISSERIE",
		appearance = "tapisserie",
	},
	-- Légendaire de la série 2 (#515) : cuir doré de Cordoue, paon et grenades peints sur la lame (cordoue.py), manche
	-- gainé de cuir gaufré
	{
		id = "skin.m9bayonet.cordoue",
		type = "skin",
		weapon = "weapon.m9bayonet",
		name = "CUIR DE CORDOUE",
		appearance = "cordoue",
	},
	-- Tenues de personnage (#521) : achetées en crédits (portant du shop), l'admin les a toutes ; cartes et tête dans
	-- assets/rbx/Outfits/<appearance>.rbxm (fabrication : docs/assets.md, « Tenues de personnage »)
	{
		id = "outfit.mercure",
		type = "outfit",
		name = "MERCURE",
		appearance = "mercure",
		rarity = "exceptional",
		price = 2500,
	},
	-- Communes : combinaison de surf noire à panneaux bleu canard (assets/outfits/neoprene) et statue de plâtre lisse
	-- (assets/outfits/platre), cagoule et coque sans visage
	{
		id = "outfit.neoprene",
		type = "outfit",
		name = "NÉOPRÈNE",
		appearance = "neoprene",
		rarity = "common",
		price = 600,
	},
	{
		id = "outfit.platre",
		type = "outfit",
		name = "PLÂTRE",
		appearance = "platre",
		rarity = "common",
		price = 600,
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
	local outfit = raw[InventoryRules.OUTFIT_SLOT]
	if type(outfit) == "table" and InventoryRules.isValidId(outfit.weapon) then
		equipped[InventoryRules.OUTFIT_SLOT] = { weapon = outfit.weapon }
	end
	return equipped
end

-- Cette méthode permet de savoir si une valeur relue du DataStore est d'un format que cette version sait réécrire :
-- absente (nouveau joueur), ou table de schéma connu (pas plus récent) dont `items` est une liste ou absent,
-- `equipped` (#280) une table ou absent et `wallet` (#396) un portefeuille réécrivable ou absent (schéma 1).
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
		and WalletRules.isWritable(data.wallet)
end

-- Cette méthode permet de décider des ids, du droit d'écrire, de l'équipement et du portefeuille relus au chargement :
-- échec ou format inconnu/plus récent → sauvegarde coupée ; rien ou schéma 1 sans `wallet` → portefeuille de départ.
function InventoryRules.loadOutcome(ok: boolean, data: any): ({ string }, boolean, Equipped, WalletRules.Wallet)
	if not ok then
		return {}, false, {}, WalletRules.empty()
	end
	local tableData = if type(data) == "table" then data else nil
	local writable = isWritable(data)
	return InventoryRules.sanitizeStored(tableData and tableData.items),
		writable,
		InventoryRules.sanitizeEquipped(tableData and tableData.equipped),
		if writable then WalletRules.read(tableData and tableData.wallet) else WalletRules.empty()
end

-- Cette méthode permet de construire la valeur écrite dans le DataStore lorsqu'un inventaire est sauvegardé ;
-- l'équipement n'est écrit que s'il y en a un (choisi ou déjà enregistré), le portefeuille toujours (départ s'il manque).
function InventoryRules.payload(stored: { string }, equipped: Equipped?, wallet: WalletRules.Wallet?): Record
	local hasEquipped = equipped ~= nil and next(equipped) ~= nil
	return {
		schemaVersion = InventoryRules.SCHEMA_VERSION,
		items = table.clone(stored),
		equipped = if hasEquipped then table.clone(equipped :: Equipped) else nil,
		wallet = WalletRules.read(wallet),
	}
end

-- Cette méthode permet de copier une valeur en profondeur lorsqu'une opération reçoit l'enregistrement fusionné (elle
-- ne doit pas pouvoir modifier celui de la fusion).
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

-- Cette méthode permet de garder d'un enregistrement rendu par une opération ce qu'elle peut changer : ids ajoutés et
-- portefeuille (marques de lots de la fusion) ; nil si ce portefeuille n'est pas valide (négatif, au-delà du plafond).
local function adoptOperation(merged: Record, proposed: any): Record?
	if type(proposed) ~= "table" or proposed.wallet == nil or not WalletRules.isWritable(proposed.wallet) then
		return nil
	end
	-- Un reçu mal formé serait retiré en silence par `WalletRules.read` : les crédits achetés seraient écrits sans leur
	-- PurchaseId, et le reçu rejoué par Roblox crédité deux fois (#395). Refuser plutôt.
	if type(proposed.wallet.receipts) == "table" then
		for _, id in ipairs(proposed.wallet.receipts) do
			if type(id) ~= "string" or #id == 0 or #id > WalletRules.MAX_RECEIPT_LENGTH then
				return nil
			end
		end
	end
	local ids = table.clone(merged.items)
	if type(proposed.items) == "table" then
		for _, id in InventoryRules.sanitizeStored(proposed.items, math.huge) do
			table.insert(ids, id)
		end
	end
	local wallet = WalletRules.read(proposed.wallet)
	wallet.writes = merged.wallet.writes
	return {
		schemaVersion = InventoryRules.SCHEMA_VERSION,
		items = InventoryRules.sanitizeStored(ids, math.huge),
		equipped = merged.equipped,
		wallet = wallet,
	}
end

-- Cette méthode permet de calculer la valeur écrite par UpdateAsync : ids réunis, équipement de la session, lots de gains
-- pas encore comptés, puis opération `op` (refus possible) ; pure, rend l'enregistrement (nil : rien), l'issue, le résultat.
function InventoryRules.mergeForSave(
	old: any,
	stored: { string },
	equipped: Equipped?,
	wallet: WalletChange?,
	op: Operation?
): (Record?, MergeStatus, any)
	if not isWritable(old) then
		return nil, "refused"
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
	local oldWallet = WalletRules.read(if type(old) == "table" then old.wallet else nil)
	local nextWallet = if wallet
		then WalletRules.applyBatches(oldWallet, wallet.session, wallet.batches, wallet.upTo)
		else oldWallet
	local record = InventoryRules.payload(InventoryRules.sanitizeStored(merged, math.huge), keptEquipped, nextWallet)
	if not op then
		return record, "merged"
	end
	assert(wallet, "une opération demande le numéro de lot de la session (wallet.upTo)")
	-- Opération déjà écrite par un essai signalé en échec (réponse perdue) : sa marque est stockée, ne pas la rejouer
	if WalletRules.appliedSeq(oldWallet, wallet.session) >= wallet.upTo then
		return record, "replayed"
	end
	local proposed, result = op(deepCopy(record))
	if proposed == nil then
		return nil, "rejected", result
	end
	local adopted = adoptOperation(record, proposed)
	if not adopted then
		return nil, "rejected", "invalid"
	end
	return adopted, "applied", result
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
	-- Tenue (#521) : le choix s'il est une tenue possédée, sinon rien (tenue d'origine)
	local outfit = equipped and equipped[InventoryRules.OUTFIT_SLOT]
	local item = outfit and byId[outfit.weapon]
	if item and item.type == "outfit" and owned[item.id] then
		resolved[InventoryRules.OUTFIT_SLOT] = { weapon = item.id }
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
	if slot == InventoryRules.OUTFIT_SLOT then
		return InventoryRules.equipOutfit(equipped, owned, weaponId)
	end
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

-- Cette méthode permet de valider le choix d'une tenue (#521) lorsque le joueur clique dans l'emplacement TENUE :
-- nouvel équipement (copie), ou nil et le motif ; nil, "" ou OUTFIT_NONE remettent la tenue d'origine.
function InventoryRules.equipOutfit(equipped: Equipped, owned: Owned, outfitId: any): (Equipped?, string?)
	local chosen = InventoryRules.OUTFIT_NONE
	if outfitId ~= nil and outfitId ~= "" and outfitId ~= InventoryRules.OUTFIT_NONE then
		local item = type(outfitId) == "string" and byId[outfitId]
		if not (item and item.type == "outfit") then
			return nil, "unknown"
		end
		if not owned[item.id] then
			return nil, "not_owned"
		end
		chosen = item.id
	end
	local nextEquipped = InventoryRules.sanitizeEquipped(equipped)
	nextEquipped[InventoryRules.OUTFIT_SLOT] = { weapon = chosen }
	return nextEquipped
end

-- Cette méthode permet de lire la tenue d'un équipement résolu (#521) lorsqu'un personnage est habillé ; nil : tenue
-- d'origine.
function InventoryRules.outfitOf(resolved: Equipped?): string?
	local outfit = resolved and resolved[InventoryRules.OUTFIT_SLOT]
	return outfit and outfit.weapon
end

-- Cette méthode permet de lister les tenues du catalogue (#521), triées par prix puis par nom, lorsque l'écran
-- d'équipement ou le shop les montre.
function InventoryRules.outfits(): { Item }
	local list: { Item } = {}
	for _, entry in InventoryRules.ITEMS do
		if entry.type == "outfit" then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		if (a.price or 0) ~= (b.price or 0) then
			return (a.price or 0) < (b.price or 0)
		end
		return (a.name or a.id) < (b.name or b.id)
	end)
	return list
end

-- Cette méthode permet de choisir la tenue d'un bot (#521) d'après son nom lorsqu'il apparaît : l'origine ou une tenue
-- du catalogue, à chances égales, toujours la même pour un même nom ; nil : tenue d'origine.
function InventoryRules.outfitForName(name: string): string?
	local outfits = InventoryRules.outfits()
	local hash = 0
	for i = 1, #name do
		hash = (hash * 31 + string.byte(name, i)) % 1000003
	end
	local index = hash % (#outfits + 1)
	return if index == 0 then nil else outfits[index].id
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
-- « arme:skin » par emplacement, dans l'ordre de SLOTS, puis la tenue (#521, absente : d'origine), séparés par des virgules.
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
	local outfit = InventoryRules.outfitOf(resolved)
	if outfit then
		table.insert(parts, outfit) -- tenue (#521), après les emplacements d'armes ; absente : d'origine
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
				if index == #InventoryRules.SLOTS + 1 and part ~= "" then
					equipped[InventoryRules.OUTFIT_SLOT] = { weapon = part }
				end
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

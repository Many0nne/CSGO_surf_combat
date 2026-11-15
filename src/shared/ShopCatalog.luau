-- Catalogue du shop (#347, docs/ui.md « Shop ») : caisses en vente, une par série de skins et par arme (#332), avec
-- leur prix et leur contenu par rareté, tirage d'une ouverture, et rangement des caisses dans la vitrine de la vue
-- d'ensemble. Règles pures, testées (tests/specs/ShopCatalog.spec.luau).
--
-- Provisoire : prix, raretés, chances et remboursements sont des valeurs d'attente (points ouverts de #347, #332 et
-- #393). Les prix sont en crédits, la monnaie du jeu (#391, WalletRules) ; l'achat (#393, CrateService) relit le prix et
-- le remboursement d'un doublon dans ce module côté serveur : ce que le client affiche ne fait jamais foi.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local ShopCatalog = {}

export type Rgb = { number }
-- `refund` : part du prix de la caisse rendue en crédits pour un doublon (#393), en pour cent (entier, 0 à 100)
export type Rarity = { id: string, label: string, chance: number, color: Rgb, refund: number }
-- `weapon` : id de l'arme dont la caisse donne un skin (`id` d'un item `weapon` de InventoryRules.ITEMS) ; `contents` :
-- nom d'apparence des skins (`appearance` de InventoryRules.ITEMS) par id de rareté, le skin étant celui de cette arme
export type Crate = {
	id: string,
	name: string,
	weapon: string,
	stripe: Rgb,
	price: number,
	contents: { [string]: string },
}
-- `luminance` : moyenne de celles des skins de la ligne (1 pour un skin non mesuré)
export type Row = { rarity: Rarity, name: string, weapons: { string }, skins: { string }, luminance: number }
export type Slot = { index: number, row: number, column: number }

ShopCatalog.CURRENCY = WalletRules.CURRENCY

-- Raretés, de la plus courante à la plus rare ; chances en pour cent (total 100). Remboursement d'un doublon (#393) en
-- part du prix, pour qu'une caisse d'un autre prix suive sans nouvelle table : 20 / 40 / 70 % (100, 200, 350 crédits
-- pour une caisse à 500)
ShopCatalog.RARITIES = {
	{ id = "common", label = "COMMUN", chance = 70, color = { 150, 160, 172 }, refund = 20 },
	{ id = "rare", label = "RARE", chance = 25, color = { 70, 120, 230 }, refund = 40 },
	{ id = "exceptional", label = "EXCEPTIONNEL", chance = 5, color = { 170, 70, 220 }, refund = 70 },
} :: { Rarity }

-- Caisses en vente, dans l'ordre de la vitrine : une par arme et par série, une ouverture donne un seul skin de
-- l'arme (#332). Ajouter une série = deux lignes ici (ses skins dans InventoryRules)
ShopCatalog.CRATES = {
	{
		id = "crate.awp.serie1",
		name = "AWP · SÉRIE 1",
		weapon = "weapon.awp",
		stripe = { 226, 58, 40 },
		price = 500,
		contents = { common = "couchant", rare = "impact", exceptional = "releve" },
	},
	{
		id = "crate.m9.serie1",
		name = "M9 · SÉRIE 1",
		weapon = "weapon.m9bayonet",
		stripe = { 226, 58, 40 },
		price = 500,
		contents = { common = "couchant", rare = "impact", exceptional = "releve" },
	},
	{
		id = "crate.awp.serie2",
		name = "AWP · SÉRIE 2",
		weapon = "weapon.awp",
		stripe = { 40, 150, 160 },
		price = 500,
		contents = { common = "recuit", rare = "strate", exceptional = "sillage" },
	},
	{
		id = "crate.m9.serie2",
		name = "M9 · SÉRIE 2",
		weapon = "weapon.m9bayonet",
		stripe = { 40, 150, 160 },
		price = 500,
		contents = { common = "recuit", rare = "strate", exceptional = "sillage" },
	},
} :: { Crate }

-- Vitrine : deux étages de trois caisses ; l'étage à hauteur d'œil (rangée 1, en haut) se remplit d'abord
ShopCatalog.PER_ROW = 3
ShopCatalog.ROWS = 2

-- Nom court d'une arme dans la liste du contenu (« AWP   COUCHANT »)
local WEAPON_LABELS = { ["weapon.awp"] = "AWP", ["weapon.m9bayonet"] = "M9" }

-- Cette méthode permet de trouver une caisse par son id lorsqu'un écran ou un remote la désigne ; nil si inconnue.
function ShopCatalog.crate(id: string): Crate?
	for _, crate in ShopCatalog.CRATES do
		if crate.id == id then
			return crate
		end
	end
	return nil
end

-- Cette méthode permet de lister le contenu d'une caisse par rareté (de la plus courante à la plus rare) lorsque la vue
-- détail l'affiche : nom du skin, arme concernée et id du skin, lus dans le catalogue des items (`items` :
-- InventoryRules.ITEMS), seuls les skins de l'arme de la caisse comptant ; une rareté sans skin connu est omise.
function ShopCatalog.contents(crate: Crate, items: { any }): { Row }
	local rows = {}
	for _, rarity in ShopCatalog.RARITIES do
		local appearance = crate.contents[rarity.id]
		local row: Row = { rarity = rarity, name = "", weapons = {}, skins = {}, luminance = 1 }
		local total = 0
		for _, item in items do
			if item.type == "skin" and appearance and item.appearance == appearance and item.weapon == crate.weapon then
				row.name = item.name or string.upper(appearance)
				table.insert(row.weapons, WEAPON_LABELS[item.weapon] or string.upper(tostring(item.weapon)))
				table.insert(row.skins, item.id)
				total += item.luminance or 1
			end
		end
		if #row.skins > 0 then
			row.luminance = total / #row.skins
			table.insert(rows, row)
		end
	end
	return rows
end

-- Cette méthode permet de tirer le skin d'une ouverture de caisse lorsque le serveur la traite : `roll` (nombre dans
-- [0, 100), hors bornes ramené dedans) est placé sur les chances des raretés de la caisse, les raretés sans skin connu
-- étant exclues et les chances renormalisées. Renvoie la ligne tirée et l'id de son skin ; nil si la caisse est vide.
function ShopCatalog.draw(crate: Crate, items: { any }, roll: number): (Row?, string?)
	local rows = ShopCatalog.contents(crate, items)
	local total = 0
	for _, row in rows do
		total += row.rarity.chance
	end
	if #rows == 0 or total <= 0 then
		return nil, nil
	end
	local clamped = if roll == roll then math.clamp(roll, 0, 100 - 1e-9) else 0
	local target = clamped / 100 * total
	local cumulative = 0
	for _, row in rows do
		cumulative += row.rarity.chance
		if target < cumulative then
			return row, row.skins[1]
		end
	end
	local last = rows[#rows]
	return last, last.skins[1]
end

-- Cette méthode permet de placer les lignes du contenu dans les `count` colonnes du tableau lorsque la vue détail
-- l'habille (#366) : les skins les plus sombres au plus près du milieu (sous la suspension, les métaux sombres ne
-- prennent que la lumière venue de près) ; entre colonnes à même distance du milieu, l'ordre du contenu, de gauche à
-- droite. Renvoie la colonne (1 à `count`) de chaque ligne, par rang dans `rows` ; les lignes en trop n'en ont pas.
function ShopCatalog.columns(rows: { Row }, count: number): { number }
	local middle = (count + 1) / 2
	local order = {}
	for i = 1, #rows do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		if rows[a].luminance ~= rows[b].luminance then
			return rows[a].luminance < rows[b].luminance
		end
		return a < b
	end)
	-- Colonnes par distance au milieu (milieu, puis la paire voisine…), chaque groupe gauche avant droite
	local columns = {}
	local taken = 0
	for distance = 0, middle - 1, 0.5 do
		local group = {}
		for column = 1, count do
			if math.abs(column - middle) == distance then
				table.insert(group, column)
			end
		end
		local chosen = {}
		for k = 1, math.min(#group, #order - taken) do
			table.insert(chosen, order[taken + k])
		end
		taken += #chosen
		table.sort(chosen)
		for k, i in chosen do
			columns[i] = group[k]
		end
	end
	return columns
end

-- Cette méthode permet de composer la ligne sous le nom d'une caisse (« CAISSE · COUCHANT / IMPACT / RELEVÉ ») lorsque
-- la vue détail l'affiche.
function ShopCatalog.subtitle(crate: Crate, items: { any }): string
	local names = {}
	for _, row in ShopCatalog.contents(crate, items) do
		table.insert(names, row.name)
	end
	return "CAISSE  ·  " .. table.concat(names, " / ")
end

-- Cette méthode permet de ranger `count` caisses dans la vitrine lorsque la vue d'ensemble se construit : rangée 1 (en
-- haut) d'abord, au plus PER_ROW par rangée ; `column` est la place dans la rangée, centrée (-1, 0, 1 pour trois
-- caisses, -0,5 et 0,5 pour deux). Au-delà de PER_ROW x ROWS, les caisses ne sont pas rangées.
function ShopCatalog.slots(count: number): { Slot }
	local slots = {}
	local capacity = ShopCatalog.PER_ROW * ShopCatalog.ROWS
	local placed = math.min(count, capacity)
	for row = 1, ShopCatalog.ROWS do
		local first = (row - 1) * ShopCatalog.PER_ROW + 1
		local inRow = math.clamp(placed - first + 1, 0, ShopCatalog.PER_ROW)
		for k = 1, inRow do
			table.insert(slots, { index = first + k - 1, row = row, column = (k - 1) - (inRow - 1) / 2 })
		end
	end
	return slots
end

-- Cette méthode permet de lister les rangées de la vitrine laissées vides par `count` caisses lorsque la vue d'ensemble
-- les garnit de caisses sans marque (stock, pas en vente).
function ShopCatalog.emptyRows(count: number): { number }
	local rows = {}
	for row = 1, ShopCatalog.ROWS do
		if count <= (row - 1) * ShopCatalog.PER_ROW then
			table.insert(rows, row)
		end
	end
	return rows
end

-- Cette méthode permet de passer à la caisse voisine (`step` = 1 ou -1, en boucle) lorsque le joueur clique une flèche
-- de la vue détail.
function ShopCatalog.cycle(index: number, step: number, count: number): number
	if count <= 0 then
		return 1
	end
	return (index - 1 + step) % count + 1
end

-- Cette méthode permet de lire les crédits rendus pour un doublon d'une rareté (part `refund` du prix, arrondie en
-- dessous ; 0 si inconnue) lorsque le serveur règle un achat ou que la vue détail l'affiche (#393).
function ShopCatalog.refund(crate: Crate, rarityId: string): number
	for _, rarity in ShopCatalog.RARITIES do
		if rarity.id == rarityId then
			local share = math.clamp(math.floor(rarity.refund), 0, 100)
			return crate.price * share // 100
		end
	end
	return 0
end

-- Mêmes proportions que `draw` ; arrondi au plus fort reste, à égalité la ligne la plus courante ; vide si total nul.
-- Cette méthode permet de convertir les chances en dixièmes de pour cent de somme exacte 1000 lorsque la vue détail les
-- affiche (#393, règle Roblox des objets aléatoires payants).
function ShopCatalog.chances(rows: { Row }): { number }
	local total = 0
	for _, row in rows do
		total += math.max(row.rarity.chance, 0)
	end
	if total <= 0 then
		return {}
	end
	local tenths, remainders, given = {}, {}, 0
	for i, row in rows do
		local exact = math.max(row.rarity.chance, 0) / total * 1000
		tenths[i] = math.floor(exact)
		remainders[i] = exact - tenths[i]
		given += tenths[i]
	end
	local order = {}
	for i = 1, #rows do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		if remainders[a] ~= remainders[b] then
			return remainders[a] > remainders[b]
		end
		return a < b
	end)
	for k = 1, 1000 - given do
		local i = order[(k - 1) % #order + 1]
		tenths[i] += 1
	end
	return tenths
end

-- Cette méthode permet d'écrire une chance en dixièmes de pour cent (« 70 % », « 2,5 % ») lorsque la vue détail
-- l'affiche.
function ShopCatalog.chanceLabel(tenths: number): string
	if tenths % 10 == 0 then
		return string.format("%d %%", tenths // 10)
	end
	return string.format("%d,%d %%", tenths // 10, tenths % 10)
end

-- Cette méthode permet de savoir si un joueur possède tous les skins d'une caisse (false pour une caisse vide) lorsque
-- la vue détail choisit ACHETER ou TOUT OBTENU et que le serveur reçoit un achat (#393).
function ShopCatalog.allOwned(crate: Crate, items: { any }, owned: { [string]: boolean }): boolean
	local rows = ShopCatalog.contents(crate, items)
	if #rows == 0 then
		return false
	end
	for _, row in rows do
		-- Le skin que `draw` donne pour cette rareté
		if not owned[row.skins[1]] then
			return false
		end
	end
	return true
end

-- Cette méthode permet d'écrire le montant d'un prix (« 500 », « 1 500 ») lorsque la vitrine ou la vue détail
-- l'affiche après le jeton du crédit.
function ShopCatalog.priceLabel(crate: Crate): string
	return WalletRules.format(crate.price)
end

return ShopCatalog

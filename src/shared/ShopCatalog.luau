-- Catalogue du shop (#347, docs/ui.md « Shop ») : caisses en vente, une par série de skins, avec leur prix et leur
-- contenu par rareté, et rangement des caisses dans la vitrine de la vue d'ensemble. Règles pures, testées
-- (tests/specs/ShopCatalog.spec.luau).
--
-- Provisoire : prix, monnaie (CRÉDITS), raretés et chances sont des valeurs d'attente (points ouverts de #347 et
-- #332). L'achat n'existe pas encore : le prix affiché ne fait jamais foi côté serveur.
local ShopCatalog = {}

export type Rgb = { number }
export type Rarity = { id: string, label: string, chance: number, color: Rgb }
-- `contents` : nom d'apparence des skins (`appearance` de InventoryRules.ITEMS) par id de rareté ; une apparence
-- désigne la paire AWP + M9 de la série
export type Crate = { id: string, name: string, stripe: Rgb, price: number, contents: { [string]: string } }
-- `luminance` : moyenne de celles des skins de la ligne (1 pour un skin non mesuré)
export type Row = { rarity: Rarity, name: string, weapons: { string }, skins: { string }, luminance: number }
export type Slot = { index: number, row: number, column: number }

ShopCatalog.CURRENCY = "CRÉDITS"

-- Raretés, de la plus courante à la plus rare ; chances en pour cent (total 100)
ShopCatalog.RARITIES = {
	{ id = "common", label = "COMMUN", chance = 70, color = { 150, 160, 172 } },
	{ id = "rare", label = "RARE", chance = 25, color = { 70, 120, 230 } },
	{ id = "exceptional", label = "EXCEPTIONNEL", chance = 5, color = { 170, 70, 220 } },
} :: { Rarity }

-- Caisses en vente, dans l'ordre de la vitrine. Ajouter une série = une ligne ici (ses skins dans InventoryRules)
ShopCatalog.CRATES = {
	{
		id = "crate.serie1",
		name = "SÉRIE 1",
		stripe = { 226, 58, 40 },
		price = 500,
		contents = { common = "couchant", rare = "impact", exceptional = "releve" },
	},
	{
		id = "crate.serie2",
		name = "SÉRIE 2",
		stripe = { 40, 150, 160 },
		price = 500,
		contents = { common = "recuit", rare = "strate", exceptional = "sillage" },
	},
} :: { Crate }

-- Vitrine : deux étages de trois caisses ; l'étage à hauteur d'œil (rangée 1, en haut) se remplit d'abord
ShopCatalog.PER_ROW = 3
ShopCatalog.ROWS = 2

-- Nom court d'une arme dans la liste du contenu (« AWP · M9 COUCHANT »)
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
-- détail l'affiche : nom du skin, armes concernées et ids des skins, lus dans le catalogue des items (`items` :
-- InventoryRules.ITEMS) ; une rareté sans skin connu est omise.
function ShopCatalog.contents(crate: Crate, items: { any }): { Row }
	local rows = {}
	for _, rarity in ShopCatalog.RARITIES do
		local appearance = crate.contents[rarity.id]
		local row: Row = { rarity = rarity, name = "", weapons = {}, skins = {}, luminance = 1 }
		local total = 0
		for _, item in items do
			if item.type == "skin" and appearance and item.appearance == appearance then
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

-- Cette méthode permet d'écrire un prix (« 500 CRÉDITS ») lorsqu'une étiquette de la vitrine l'affiche.
function ShopCatalog.priceLabel(crate: Crate): string
	return string.format("%d %s", crate.price, ShopCatalog.CURRENCY)
end

return ShopCatalog

-- Catalogue du shop (#347, docs/ui.md « Shop ») : caisses en vente, une par arme (#332, #424), avec leur prix et leur
-- contenu (plusieurs skins par rareté), tirage d'une ouverture, et rangement des caisses dans la vitrine de la vue
-- d'ensemble. Règles pures, testées (tests/specs/ShopCatalog.spec.luau).
--
-- Provisoire : prix, raretés, chances et remboursements sont des valeurs d'attente (points ouverts de #347, #332 et
-- #393). Les prix sont en crédits, la monnaie du jeu (#391, WalletRules) ; l'achat (#393, CrateService) relit le prix et
-- le remboursement d'un doublon dans ce module côté serveur : ce que le client affiche ne fait jamais foi.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local ShopCatalog = {}

export type Rgb = { number }
-- `chance` : part de la rareté en pour cent, partagée à parts égales entre ses skins dans une caisse (#424) ; `refund` :
-- part du prix de la caisse rendue en crédits pour un doublon (#393), en pour cent (entier, 0 à 100)
export type Rarity = { id: string, label: string, chance: number, color: Rgb, refund: number }
-- `weapon` : id de l'arme dont la caisse donne un skin (`id` d'un item `weapon` de InventoryRules.ITEMS) ; `contents` :
-- noms d'apparence des skins (`appearance` de InventoryRules.ITEMS) par id de rareté, le skin étant celui de cette arme
export type Crate = {
	id: string,
	name: string,
	weapon: string,
	stripe: Rgb,
	price: number,
	contents: { [string]: { string } },
}
-- Une ligne du contenu = un skin : sa rareté, son nom affiché, son id d'item, le nom court de son arme (« AWP ») et le
-- viewmodel de son arme (vignette)
export type Row = { rarity: Rarity, name: string, skin: string, weapon: string, viewmodel: string }
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

-- Caisses en vente, dans l'ordre de la vitrine : une par arme et par série, de 6 à 8 skins (#424), une ouverture donne
-- un seul skin de l'arme (#332). Raretés reprises des anciennes caisses par série (TREMPE et MUE, hors caisse, en
-- COMMUN), à revoir. Ajouter une série = une caisse par arme ici (ses skins dans InventoryRules). Une série peut
-- reprendre des skins d'une autre pour atteindre 6 skins (FILM, #433), à la même rareté partout (`rarityOf`)
ShopCatalog.CRATES = {
	{
		id = "crate.awp.serie1",
		name = "AWP · SÉRIE 1",
		weapon = "weapon.awp",
		stripe = { 226, 58, 40 },
		price = 500,
		contents = {
			common = { "balise", "maquis", "trempe", "mue" },
			rare = { "pan", "circuit" },
			exceptional = { "orage", "ciselure" },
		},
	},
	{
		id = "crate.m9.serie1",
		name = "M9 · SÉRIE 1",
		weapon = "weapon.m9bayonet",
		stripe = { 40, 150, 160 },
		price = 500,
		contents = {
			common = { "couchant", "recuit" },
			rare = { "patrouille", "artdeco" },
			exceptional = { "releve", "email" },
		},
	},
	-- Série FILM (#433) : un skin hommage par arme, complétée de skins de la série 1 (même rareté)
	{
		id = "crate.awp.film",
		name = "AWP · FILM",
		weapon = "weapon.awp",
		stripe = { 110, 230, 130 }, -- vert phosphore de l'écran de REMORQUEUR
		price = 500,
		contents = {
			common = { "balise", "maquis", "mue" },
			rare = { "circuit", "pan" },
			exceptional = { "remorqueur" },
		},
	},
	{
		id = "crate.m9.film",
		name = "M9 · FILM",
		weapon = "weapon.m9bayonet",
		stripe = { 200, 182, 140 }, -- os de HÔTE
		price = 500,
		contents = {
			common = { "couchant", "recuit" },
			rare = { "patrouille", "artdeco" },
			exceptional = { "hote", "releve" },
		},
	},
} :: { Crate }

-- Vitrine : deux étages de trois caisses ; l'étage à hauteur d'œil (rangée 1, en haut) se remplit d'abord
ShopCatalog.PER_ROW = 3
ShopCatalog.ROWS = 2

-- Nom court d'une arme sur la révélation (« AWP  ORAGE »)
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

-- Cette méthode permet de lister le contenu d'une caisse, un skin par ligne, par rareté (de la plus courante à la plus
-- rare) puis dans l'ordre du catalogue, lorsque la vue détail l'affiche ou que le serveur tire : lus dans le catalogue
-- des items (`items` : InventoryRules.ITEMS), seuls les skins connus de l'arme de la caisse comptant.
function ShopCatalog.contents(crate: Crate, items: { any }): { Row }
	local viewmodel = ""
	for _, item in items do
		if item.id == crate.weapon then
			viewmodel = item.tool or ""
		end
	end
	local rows = {}
	for _, rarity in ShopCatalog.RARITIES do
		local appearances: { string } = crate.contents[rarity.id] or {}
		for _, appearance in appearances do
			for _, item in items do
				if item.type == "skin" and item.appearance == appearance and item.weapon == crate.weapon then
					table.insert(rows, {
						rarity = rarity,
						name = item.name or string.upper(appearance),
						skin = item.id,
						weapon = WEAPON_LABELS[crate.weapon] or string.upper(crate.weapon),
						viewmodel = viewmodel,
					})
					break
				end
			end
		end
	end
	return rows
end

-- Cette méthode permet de lire la rareté d'un skin (item `skin` de InventoryRules.ITEMS) lorsque l'inventaire la montre :
-- celle de la première caisse de son arme qui le contient ; nil pour un skin qu'aucune caisse ne donne.
function ShopCatalog.rarityOf(skin: { weapon: string?, appearance: string? }): Rarity?
	if not (skin.weapon and skin.appearance) then
		return nil
	end
	for _, crate in ShopCatalog.CRATES do
		if crate.weapon == skin.weapon then
			for _, rarity in ShopCatalog.RARITIES do
				if table.find(crate.contents[rarity.id] or {}, skin.appearance) then
					return rarity
				end
			end
		end
	end
	return nil
end

-- Cette méthode permet de donner le poids de chaque ligne du contenu (chance de sa rareté partagée entre les skins de
-- cette rareté présents, négative ramenée à 0) lorsque le tirage ou l'affichage des chances en a besoin.
local function weights(rows: { Row }): { number }
	local counts: { [string]: number } = {}
	for _, row in rows do
		counts[row.rarity.id] = (counts[row.rarity.id] or 0) + 1
	end
	local result = {}
	for i, row in rows do
		result[i] = math.max(row.rarity.chance, 0) / counts[row.rarity.id]
	end
	return result
end

-- Cette méthode permet de tirer le skin d'une ouverture de caisse lorsque le serveur la traite : `roll` (nombre dans
-- [0, 100), hors bornes ramené dedans) est placé sur les poids des skins (`weights`), les raretés sans skin connu étant
-- exclues et les chances renormalisées. Renvoie la ligne tirée et l'id de son skin ; nil si la caisse est vide.
function ShopCatalog.draw(crate: Crate, items: { any }, roll: number): (Row?, string?)
	local rows = ShopCatalog.contents(crate, items)
	local weight = weights(rows)
	local total = 0
	for _, w in weight do
		total += w
	end
	if #rows == 0 or total <= 0 then
		return nil, nil
	end
	local clamped = if roll == roll then math.clamp(roll, 0, 100 - 1e-9) else 0
	local target = clamped / 100 * total
	local cumulative = 0
	for i, row in rows do
		cumulative += weight[i]
		if target < cumulative then
			return row, row.skin
		end
	end
	local last = rows[#rows]
	return last, last.skin
end

-- Cette méthode permet de composer la ligne sous le nom d'une caisse (« CAISSE · 8 SKINS · UN PAR OUVERTURE ») lorsque
-- la vue détail l'affiche.
function ShopCatalog.subtitle(crate: Crate, items: { any }): string
	return string.format("CAISSE  ·  %d SKINS  ·  UN PAR OUVERTURE", #ShopCatalog.contents(crate, items))
end

-- Cette méthode permet de ranger `count` caisses dans la vitrine lorsque la vue d'ensemble se construit : réparties à
-- parts égales entre les rangées nécessaires, rangée 1 (en haut) servie d'abord (4 caisses : 2 + 2, une série par
-- rangée, #433 ; 5 : 3 + 2) ; `column` est la place dans la rangée, centrée (-1, 0, 1 pour trois caisses, -0,5 et 0,5
-- pour deux). Au-delà de PER_ROW x ROWS, les caisses ne sont pas rangées.
function ShopCatalog.slots(count: number): { Slot }
	local slots = {}
	local placed = math.clamp(count, 0, ShopCatalog.PER_ROW * ShopCatalog.ROWS)
	local rows = math.ceil(placed / ShopCatalog.PER_ROW)
	local first = 1
	for row = 1, rows do
		local inRow = math.ceil((placed - first + 1) / (rows - row + 1))
		for k = 1, inRow do
			table.insert(slots, { index = first + k - 1, row = row, column = (k - 1) - (inRow - 1) / 2 })
		end
		first += inRow
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
-- Cette méthode permet de convertir les chances de chaque skin en dixièmes de pour cent de somme exacte 1000 lorsque la
-- vue détail les affiche (#393, règle Roblox des objets aléatoires payants).
function ShopCatalog.chances(rows: { Row }): { number }
	local weight = weights(rows)
	local total = 0
	for _, w in weight do
		total += w
	end
	if total <= 0 then
		return {}
	end
	local tenths, remainders, given = {}, {}, 0
	for i in rows do
		local exact = weight[i] / total * 1000
		tenths[i] = math.floor(exact + 1e-9)
		remainders[i] = exact - tenths[i]
		given += tenths[i]
	end
	local order = {}
	for i = 1, #rows do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		if math.abs(remainders[a] - remainders[b]) > 1e-9 then
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
		if not owned[row.skin] then
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

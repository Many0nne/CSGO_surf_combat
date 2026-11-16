-- Catalogue du shop (#347, docs/ui.md « Shop ») : caisses en vente, une par arme (#332, #424), avec leur prix et leur
-- contenu (plusieurs skins par rareté), tirage d'une ouverture, et rangement des caisses dans la vitrine de la vue
-- d'ensemble. Règles pures, testées (tests/specs/ShopCatalog.spec.luau).
--
-- Provisoire : prix, chances et remboursements sont des valeurs d'attente (points ouverts de #347, #332 et
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

-- Raretés, de la plus courante à la plus rare (pyramide à la CS:GO, #430) ; chances en pour cent (total 100) : 80 / 16 /
-- 3,2 / 0,8. Remboursement d'un doublon (#393) en part du prix, pour qu'une caisse d'un autre prix suive sans nouvelle
-- table : 20 / 40 / 70 / 100 % (100, 200, 350, 500 crédits pour une caisse à 500)
ShopCatalog.RARITIES = {
	{ id = "common", label = "COMMUN", chance = 80, color = { 150, 160, 172 }, refund = 20 },
	{ id = "rare", label = "RARE", chance = 16, color = { 70, 120, 230 }, refund = 40 },
	{ id = "exceptional", label = "EXCEPTIONNEL", chance = 3.2, color = { 170, 70, 220 }, refund = 70 },
	{ id = "legendary", label = "LÉGENDAIRE", chance = 0.8, color = { 235, 75, 75 }, refund = 100 },
} :: { Rarity }

-- Caisses en vente, dans l'ordre de la vitrine : une par arme et par série, de 6 à 8 skins (#424), une ouverture donne
-- un seul skin de l'arme (#332). Un skin a la même rareté dans toutes les caisses qui le contiennent (#430, `rarityOf`) :
-- AWP, COMMUN maquis, logogramme ; RARE mue, orage, circuit ; EXCEPTIONNEL remorqueur, balise, pan ; LÉGENDAIRE trempe,
-- ciselure. M9, COMMUN artdeco, hote ; RARE patrouille, releve, sphinx ; EXCEPTIONNEL email, recuit ; LÉGENDAIRE
-- couchant. Ajouter une série = une caisse par arme ici (ses skins dans InventoryRules). Une rareté sans skin dans une
-- caisse (LÉGENDAIRE d'AWP · FILM) est écartée du tirage, les autres chances étant renormalisées (`draw`)
ShopCatalog.CRATES = {
	{
		id = "crate.awp.serie1",
		name = "AWP · SÉRIE 1",
		weapon = "weapon.awp",
		stripe = { 226, 58, 40 },
		price = 500,
		contents = {
			common = { "maquis" },
			rare = { "mue", "orage", "circuit" },
			exceptional = { "balise", "pan" },
			legendary = { "trempe", "ciselure" },
		},
	},
	{
		id = "crate.m9.serie1",
		name = "M9 · SÉRIE 1",
		weapon = "weapon.m9bayonet",
		stripe = { 40, 150, 160 },
		price = 500,
		contents = {
			common = { "artdeco" },
			rare = { "patrouille", "releve" },
			exceptional = { "email", "recuit" },
			legendary = { "couchant" },
		},
	},
	-- Série FILM (#433) : des skins hommage par arme, complétés de skins de la série 1 (même rareté partout)
	{
		id = "crate.awp.film",
		name = "AWP · FILM",
		weapon = "weapon.awp",
		stripe = { 110, 230, 130 }, -- vert phosphore de l'écran de REMORQUEUR
		price = 500,
		contents = {
			common = { "logogramme" },
			rare = { "mue", "circuit" },
			exceptional = { "remorqueur", "balise", "pan" },
		},
	},
	{
		id = "crate.m9.film",
		name = "M9 · FILM",
		weapon = "weapon.m9bayonet",
		stripe = { 200, 182, 140 }, -- os de HÔTE
		price = 500,
		contents = {
			common = { "hote", "artdeco" },
			rare = { "patrouille", "sphinx" },
			exceptional = { "recuit" },
			legendary = { "couchant" },
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
		if target + 1e-9 < cumulative then
			return row, row.skin
		end
	end
	-- Repli (reste d'arrondi flottant) : la dernière ligne qui a un poids, jamais une rareté à chance nulle
	for i = #rows, 1, -1 do
		if weight[i] > 0 then
			return rows[i], rows[i].skin
		end
	end
	return nil, nil
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
-- Cette méthode permet de convertir les chances de chaque skin en centièmes de pour cent de somme exacte 10000 lorsque
-- la vue détail les affiche (#393, #430 : 16 / 3 = 5,33 %, règle Roblox des objets aléatoires payants).
function ShopCatalog.chances(rows: { Row }): { number }
	local weight = weights(rows)
	local total = 0
	for _, w in weight do
		total += w
	end
	if total <= 0 then
		return {}
	end
	local hundredths, remainders, given = {}, {}, 0
	for i in rows do
		local exact = weight[i] / total * 10000
		hundredths[i] = math.floor(exact + 1e-9)
		remainders[i] = exact - hundredths[i]
		given += hundredths[i]
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
	for k = 1, 10000 - given do
		local i = order[(k - 1) % #order + 1]
		hundredths[i] += 1
	end
	return hundredths
end

-- Cette méthode permet d'écrire une chance en centièmes de pour cent (« 80 % », « 0,4 % », « 1,07 % ») lorsque la vue
-- détail l'affiche, sans zéro inutile après la virgule.
function ShopCatalog.chanceLabel(hundredths: number): string
	if hundredths % 100 == 0 then
		return string.format("%d %%", hundredths // 100)
	end
	if hundredths % 10 == 0 then
		return string.format("%d,%d %%", hundredths // 100, hundredths % 100 // 10)
	end
	return string.format("%d,%02d %%", hundredths // 100, hundredths % 100)
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

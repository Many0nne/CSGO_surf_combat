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
-- part du prix de la caisse rendue en crédits pour un doublon (#393), en pour cent (entier, 0 à 100) ; `perCrate` :
-- nombre exact de skins de cette rareté dans une caisse en vente (4 / 3 / 2 / 1)
export type Rarity = { id: string, label: string, chance: number, color: Rgb, refund: number, perCrate: number? }
-- `weapon` : id de l'arme dont la caisse donne un skin (`id` d'un item `weapon` de InventoryRules.ITEMS) ; `contents` :
-- noms d'apparence des skins (`appearance` de InventoryRules.ITEMS) par id de rareté, le skin étant celui de cette arme ;
-- `series` (facultatif, #454) : code de série du pochoir (« FO » pour une série `foam` qui donnerait « FM » comme `film`),
-- prioritaire sur le code tiré de l'id, pour lever une collision sans renommer un id déjà en inventaire
export type Crate = {
	id: string,
	name: string,
	weapon: string,
	stripe: Rgb,
	price: number,
	contents: { [string]: { string } },
	series: string?,
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
	{ id = "common", label = "COMMUN", chance = 80, color = { 150, 160, 172 }, refund = 20, perCrate = 4 },
	{ id = "rare", label = "RARE", chance = 16, color = { 70, 120, 230 }, refund = 40, perCrate = 3 },
	{ id = "exceptional", label = "EXCEPTIONNEL", chance = 3.2, color = { 170, 70, 220 }, refund = 70, perCrate = 2 },
	{ id = "legendary", label = "LÉGENDAIRE", chance = 0.8, color = { 235, 75, 75 }, refund = 100, perCrate = 1 },
} :: { Rarity }

-- Caisses en vente, dans l'ordre de la vitrine : une par arme et par série, une ouverture donne un seul skin de l'arme
-- (#332). Composition fixe (choix de l'utilisateur, 17/11/2026) : 4 communs, 3 rares, 2 exceptionnels, 1 légendaire
-- (`perCrate` de RARITIES), et un skin n'est que dans une caisse. Une caisse qu'on ne peut pas remplir n'est pas en vente :
-- ses skins attendent dans RESERVE. Ajouter une série = une caisse par arme ici, ses skins dans InventoryRules
ShopCatalog.CRATES = {
	{
		id = "crate.awp.serie1",
		name = "AWP · SÉRIE 1",
		weapon = "weapon.awp",
		stripe = { 226, 58, 40 },
		price = 500,
		contents = {
			common = { "maquis", "epure", "tartan", "banche" },
			rare = { "mue", "orage", "circuit" },
			exceptional = { "balise", "pan" },
			legendary = { "trempe" },
		},
	},
	{
		id = "crate.m9.serie1",
		name = "M9 · SÉRIE 1",
		weapon = "weapon.m9bayonet",
		stripe = { 40, 150, 160 },
		price = 500,
		contents = {
			common = { "artdeco", "leurre", "chantier", "ceramique" },
			rare = { "patrouille", "releve", "guilloche" },
			exceptional = { "email", "recuit" },
			legendary = { "couchant" },
		},
	},
	-- Série 2 de l'AWP (#493) : skins de la série 2 (#482, #487, #492) et de l'ancienne réserve FILM (LOGOGRAMME,
	-- REMORQUEUR, CISELURE) ; bande ocre laiton, distincte du rouge de la série 1 et du bleu-vert du M9
	{
		id = "crate.awp.serie2",
		name = "AWP · SÉRIE 2",
		weapon = "weapon.awp",
		stripe = { 205, 150, 55 },
		price = 500,
		contents = {
			common = { "logogramme", "parquet", "cannage", "tole" },
			rare = { "capiton", "vitrail", "laque" },
			exceptional = { "remorqueur", "marqueterie" },
			legendary = { "ciselure" },
		},
	},
	-- Série 2 de la M9 (#515) : matières d'intérieur (#495, #505) et la FILM (TOPO, HÔTE, SPHINX), légendaire CUIR DE
	-- CORDOUE ; bande vert jade, distincte du bleu-vert de la série 1, du rouge et de l'ocre de l'AWP. HÔTE est rare et
	-- AZULEJO commun (échange de rareté demandé après la mise en vente)
	{
		id = "crate.m9.serie2",
		name = "M9 · SÉRIE 2",
		weapon = "weapon.m9bayonet",
		stripe = { 70, 160, 90 },
		price = 500,
		contents = {
			common = { "topo", "azulejo", "piedpoule", "tomette" },
			rare = { "sphinx", "hote", "nacre" },
			exceptional = { "chinoiserie", "tapisserie" },
			legendary = { "cordoue" },
		},
	},
} :: { Crate }

-- Réserve : skins finis qu'aucune caisse en vente ne donne encore, par arme puis par rareté. Ils gardent leur rareté
-- (`rarityOf`, pour qui les possède déjà : les caisses FILM, #433, ont été vendues avant d'être retirées), et forment
-- une caisse dès qu'une arme en a assez pour la composition complète. Série FILM (#433, #436) : HÔTE et SPHINX ;
-- CISELURE et TOPO ont cédé leur place dans la série 1 à TREMPE et aux autres communs. Les skins AWP en réserve ont
-- formé la caisse AWP · SÉRIE 2 (#493), ceux de la M9 la caisse M9 · SÉRIE 2 (#515) : la réserve est vide
ShopCatalog.RESERVE = {} :: { [string]: { [string]: { string } } }

-- Vitrine : deux étages de trois caisses ; l'étage à hauteur d'œil (rangée 1, en haut) se remplit d'abord
ShopCatalog.PER_ROW = 3
ShopCatalog.ROWS = 2

-- Nom court d'une arme sur la révélation (« AWP  ORAGE »)
local WEAPON_LABELS = { ["weapon.awp"] = "AWP", ["weapon.m9bayonet"] = "M9" }

-- Cette méthode permet de donner le nom court d'une arme lorsque la révélation ou le pochoir l'affiche : la table
-- WEAPON_LABELS, sinon l'id en majuscules sans le préfixe `weapon.` (« weapon.ak47 » → « AK47 »).
local function weaponLabel(weapon: string): string
	return WEAPON_LABELS[weapon] or string.upper(string.match(weapon, "^weapon%.(.+)$") or weapon)
end

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
						weapon = weaponLabel(crate.weapon),
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
-- celle de la caisse de son arme qui le contient, sinon celle de la réserve ; nil pour un skin ni en caisse ni en réserve.
function ShopCatalog.rarityOf(skin: { weapon: string?, appearance: string? }): Rarity?
	if not (skin.weapon and skin.appearance) then
		return nil
	end
	local sources = {}
	for _, crate in ShopCatalog.CRATES do
		if crate.weapon == skin.weapon then
			table.insert(sources, crate.contents)
		end
	end
	table.insert(sources, ShopCatalog.RESERVE[skin.weapon] or {})
	for _, contents in sources do
		for _, rarity in ShopCatalog.RARITIES do
			if table.find(contents[rarity.id] or {}, skin.appearance) then
				return rarity
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

-- Cette méthode permet de composer la ligne sous le nom d'une caisse lorsque la vue détail l'affiche : renvoie le gabarit
-- français « CAISSE  ·  {n} SKINS  ·  UN PAR OUVERTURE » et ses paramètres, à traduire à l'affichage (Locale).
function ShopCatalog.subtitle(crate: Crate, items: { any }): (string, { [string]: any })
	return "CAISSE  ·  {n} SKINS  ·  UN PAR OUVERTURE", { n = #ShopCatalog.contents(crate, items) }
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

-- Cette méthode permet de composer le pochoir du couvercle d'une caisse (« S1-AWP », « FM-M9 », #434) lorsque le shop la
-- pose : série (`series` de la caisse, sinon tirée de l'id : `serie<n>` → `S<n>`, sinon 1re et dernière lettre), arme ;
-- repli sur l'un des deux, ou "".
function ShopCatalog.stencil(crate: { id: string?, weapon: string?, series: string? }?): string
	local series = crate and crate.id and string.match(crate.id, "^crate%.[^.]+%.(.+)$")
	local code: string? = nil
	local explicit = crate and crate.series
	if explicit and explicit ~= "" then
		code = string.upper(explicit)
	elseif series then
		local letters = string.gsub(string.lower(series), "[^%w]", "")
		local number = string.match(letters, "^serie(%d+)$")
		if number then
			code = "S" .. number
		elseif letters ~= "" then
			code = string.upper(string.sub(letters, 1, 1) .. string.sub(letters, -1))
		end
	end
	local weapon = crate and crate.weapon
	local label: string? = if weapon then weaponLabel(weapon) else nil
	if code and label then
		return code .. "-" .. label
	end
	return code or label or ""
end

return ShopCatalog

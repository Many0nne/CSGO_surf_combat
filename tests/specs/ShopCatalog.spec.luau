-- Catalogue du shop (#347, #424) : caisses, contenu (un skin par ligne) lu dans le catalogue des items, tirage,
-- chances, rangement dans la vitrine.
return function(T, Loader)
	local Shop = Loader.new({}):require("src/shared/ShopCatalog")
	local Inventory = Loader.new({}):require("src/shared/InventoryRules")

	-- Cette méthode permet de lister les noms d'une suite de lignes du contenu lorsqu'un test compare un ordre.
	local function names(rows): string
		local list = {}
		for _, row in rows do
			table.insert(list, row.name)
		end
		return table.concat(list, ",")
	end

	T.describe("ShopCatalog : catalogue", function()
		T.it("les chances des raretés font 100 % (pyramide 80 / 16 / 3,2 / 0,8, #430)", function()
			local total, ids, chances, refunds = 0, {}, {}, {}
			for _, rarity in Shop.RARITIES do
				total += rarity.chance
				table.insert(ids, rarity.id)
				table.insert(chances, rarity.chance)
				table.insert(refunds, rarity.refund)
			end
			T.expectNear(total, 100)
			T.expectEqual(table.concat(ids, ","), "common,rare,exceptional,legendary")
			T.expectEqual(table.concat(chances, ","), "80,16,3.2,0.8")
			T.expectEqual(table.concat(refunds, ","), "20,40,70,100")
			T.expectEqual(Shop.RARITIES[4].label, "LÉGENDAIRE")
		end)

		T.it(
			"caisses dans l'ordre de la vitrine : série 1 (AWP puis M9), puis série 2 (AWP #493, M9 #515)",
			function()
				local ids = {}
				for _, crate in Shop.CRATES do
					table.insert(ids, crate.id)
				end
				T.expectEqual(
					table.concat(ids, ","),
					"crate.awp.serie1,crate.m9.serie1,crate.awp.serie2,crate.m9.serie2"
				)
			end
		)

		T.it("composition 4 / 3 / 2 / 1", function()
			local counts = {}
			for _, rarity in Shop.RARITIES do
				table.insert(counts, rarity.perCrate)
			end
			T.expectEqual(table.concat(counts, ","), "4,3,2,1")
		end)

		T.it("chaque caisse a un id unique, un prix positif et la composition exacte en skins de son arme", function()
			local seen = {}
			for _, crate in Shop.CRATES do
				T.expectEqual(seen[crate.id], nil)
				seen[crate.id] = true
				T.expectEqual(crate.price > 0, true)
				local rows = Shop.contents(crate, Inventory.ITEMS)
				local per = {}
				for _, row in rows do
					per[row.rarity.id] = (per[row.rarity.id] or 0) + 1
					local item = Inventory.item(row.skin)
					T.expectEqual(item ~= nil, true)
					T.expectEqual(item.weapon, crate.weapon)
				end
				for _, rarity in Shop.RARITIES do
					T.expectEqual(per[rarity.id] or 0, rarity.perCrate, crate.id .. " : " .. rarity.id)
				end
				T.expectEqual(#rows, 10, crate.id)
			end
		end)

		-- Un skin n'est que dans une caisse ou dans la réserve : sinon une caisse en vente pourrait se remplir de skins
		-- repris, et rarityOf contredirait la caisse qui l'affiche
		T.it("chaque apparence listée existe et n'est qu'une fois en caisse ou en réserve", function()
			local seen = {}
			local known = {}
			for _, rarity in Shop.RARITIES do
				known[rarity.id] = true
			end
			local function visit(where, weapon, contents)
				local listed = 0
				for rarityId, appearances in contents do
					T.expect(known[rarityId] == true, where .. " : rareté " .. rarityId)
					for _, appearance in appearances do
						local key = weapon .. "/" .. appearance
						T.expectEqual(seen[key], nil, where .. " : " .. key .. " déjà ailleurs")
						seen[key] = where
						listed += 1
					end
				end
				local probe =
					{ id = where, name = "", weapon = weapon, stripe = { 0, 0, 0 }, price = 1, contents = contents }
				T.expectEqual(#Shop.contents(probe, Inventory.ITEMS), listed, where .. " : apparence inconnue")
			end
			for _, crate in Shop.CRATES do
				visit(crate.id, crate.weapon, crate.contents)
			end
			for weapon, contents in Shop.RESERVE do
				visit("réserve " .. weapon, weapon, contents)
			end
		end)

		T.it("tous les skins du jeu sont dans une caisse ou en réserve", function()
			for _, item in Inventory.ITEMS do
				if item.type == "skin" then
					T.expect(Shop.rarityOf(item) ~= nil, item.id .. " ni en caisse ni en réserve")
				end
			end
		end)

		T.it("trouve une caisse par son id", function()
			T.expectEqual(Shop.crate("crate.awp.serie1").name, "AWP · SÉRIE 1")
			T.expectEqual(Shop.crate("crate.m9.serie1").weapon, "weapon.m9bayonet")
			T.expectEqual(Shop.crate("crate.awp.serie2").name, "AWP · SÉRIE 2")
			T.expectEqual(Shop.crate("crate.m9.serie2").name, "M9 · SÉRIE 2")
			T.expectEqual(Shop.crate("crate.inconnue"), nil)
		end)
	end)

	T.describe("ShopCatalog.contents", function()
		T.it("un skin par ligne, par rareté puis dans l'ordre du catalogue, avec le viewmodel de l'arme", function()
			local rows = Shop.contents(Shop.crate("crate.awp.serie1"), Inventory.ITEMS)
			T.expectEqual(names(rows), "MAQUIS,ÉPURE,TARTAN,BANCHE,MUE,ORAGE,CIRCUIT,BALISE,PAN !,TREMPE")
			T.expectEqual(rows[1].rarity.label, "COMMUN")
			T.expectEqual(rows[1].skin, "skin.awp.maquis")
			T.expectEqual(rows[1].viewmodel, "AWP")
			T.expectEqual(rows[1].weapon, "AWP")
			T.expectEqual(rows[4].rarity.label, "COMMUN")
			T.expectEqual(rows[5].rarity.label, "RARE")
			T.expectEqual(rows[8].rarity.label, "EXCEPTIONNEL")
			T.expectEqual(rows[10].rarity.label, "LÉGENDAIRE")
			local knife = Shop.contents(Shop.crate("crate.m9.serie1"), Inventory.ITEMS)
			T.expectEqual(
				names(knife),
				"ART DÉCO,LEURRE,CHANTIER,CÉRAMIQUE,PATROUILLE,RELEVÉ,GUILLOCHÉ,ÉMAIL,RECUIT,COUCHANT"
			)
			T.expectEqual(knife[4].rarity.label, "COMMUN")
			T.expectEqual(knife[5].rarity.label, "RARE")
			T.expectEqual(knife[10].skin, "skin.m9bayonet.couchant")
			T.expectEqual(knife[1].viewmodel, "M9Bayonet")
			local serie2 = Shop.contents(Shop.crate("crate.awp.serie2"), Inventory.ITEMS)
			T.expectEqual(
				names(serie2),
				"LOGOGRAMME,PARQUET,CANNAGE,TÔLE LARMÉE,CAPITON,VITRAIL,LAQUE,REMORQUEUR,MARQUETERIE,CISELURE"
			)
			T.expectEqual(serie2[10].rarity.label, "LÉGENDAIRE")
			T.expectEqual(knife[1].weapon, "M9")
			local knife2 = Shop.contents(Shop.crate("crate.m9.serie2"), Inventory.ITEMS)
			T.expectEqual(
				names(knife2),
				"TOPO,HÔTE,PIED-DE-POULE,TOMETTE,SPHINX,AZULEJO,NACRE,CHINOISERIE,TAPISSERIE,CUIR DE CORDOUE"
			)
			T.expectEqual(knife2[10].skin, "skin.m9bayonet.cordoue")
			T.expectEqual(knife2[10].rarity.label, "LÉGENDAIRE")
		end)

		T.it("omet un skin qui n'existe pas", function()
			local crate = {
				id = "x",
				name = "X",
				weapon = "weapon.awp",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = { "absent", "balise" } },
			}
			T.expectEqual(names(Shop.contents(crate, Inventory.ITEMS)), "BALISE")
		end)

		T.it("nomme une arme hors table comme le pochoir (#455)", function()
			local crate = {
				id = "crate.ak.neon",
				name = "AK · NEON",
				weapon = "weapon.ak47",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = { "neon" } },
			}
			local items = { { id = "skin.ak.neon", type = "skin", appearance = "neon", weapon = "weapon.ak47" } }
			local rows = Shop.contents(crate, items)
			T.expectEqual(rows[1].weapon, "AK47")
			T.expectEqual(Shop.stencil(crate), "NN-" .. rows[1].weapon)
		end)

		T.it("compose la ligne sous le nom", function()
			T.expectEqual(
				Shop.subtitle(Shop.crate("crate.awp.serie1"), Inventory.ITEMS),
				"CAISSE  ·  10 SKINS  ·  UN PAR OUVERTURE"
			)
		end)
	end)

	T.describe("ShopCatalog.draw (#332, #424)", function()
		local crate = Shop.crate("crate.awp.serie1")

		T.it("partage la chance d'une rareté entre ses skins (4 x 20 / 3 x 5,33 / 2 x 1,6 / 0,8)", function()
			local function at(roll)
				local row, skinId = Shop.draw(crate, Inventory.ITEMS, roll)
				return row.rarity.id .. ":" .. skinId
			end
			T.expectEqual(at(0), "common:skin.awp.maquis")
			T.expectEqual(at(19.99), "common:skin.awp.maquis")
			T.expectEqual(at(20), "common:skin.awp.epure")
			T.expectEqual(at(40), "common:skin.awp.tartan")
			T.expectEqual(at(79.99), "common:skin.awp.banche")
			T.expectEqual(at(80), "rare:skin.awp.mue")
			T.expectEqual(at(85.4), "rare:skin.awp.orage")
			T.expectEqual(at(95.99), "rare:skin.awp.circuit")
			T.expectEqual(at(96.1), "exceptional:skin.awp.balise")
			T.expectEqual(at(97.7), "exceptional:skin.awp.pan")
			T.expectEqual(at(99.3), "legendary:skin.awp.trempe")
			T.expectEqual(at(99.999), "legendary:skin.awp.trempe")
		end)

		T.it("ramène un roll hors bornes ou invalide dans [0, 100)", function()
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, -5).rarity.id, "common")
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, 100).rarity.id, "legendary")
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, 1e9).rarity.id, "legendary")
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, 0 / 0).rarity.id, "common")
		end)

		T.it("tire le skin de l'arme de la caisse (M9)", function()
			local _, skinId = Shop.draw(Shop.crate("crate.m9.serie1"), Inventory.ITEMS, 81)
			T.expectEqual(skinId, "skin.m9bayonet.patrouille")
		end)

		T.it("suit les chances affichées (à un centième près) sur un balayage régulier du roll", function()
			for _, c in Shop.CRATES do
				local rows = Shop.contents(c, Inventory.ITEMS)
				local tenths = Shop.chances(rows)
				local counts = {}
				for i = 0, 9999 do
					local _, skinId = Shop.draw(c, Inventory.ITEMS, i / 100)
					counts[skinId] = (counts[skinId] or 0) + 1
				end
				for i, row in rows do
					-- Une chance qui ne tombe pas juste sur un centième (16 / 3 = 5,333 %) est arrondie à 1 centième près
					T.expect(math.abs(counts[row.skin] - tenths[i]) <= 1, row.skin)
				end
			end
		end)

		T.it("exclut une rareté sans skin et renormalise les chances restantes", function()
			-- Rare absente : commun 80 / (80 + 3,2), exceptionnel 3,2 / 83,2 (96,15 %)
			local partial = {
				id = "x",
				name = "X",
				weapon = "weapon.awp",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = { "balise" }, rare = { "absent" }, exceptional = { "orage" } },
			}
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 0).rarity.id, "common")
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 96.1).rarity.id, "common")
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 96.2).rarity.id, "exceptional")
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 99.99).rarity.id, "exceptional")
		end)

		T.it("ne tire rien d'une caisse sans aucun skin connu", function()
			local empty = {
				id = "x",
				name = "X",
				weapon = "weapon.awp",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = { "absent" } },
			}
			local row, skinId = Shop.draw(empty, Inventory.ITEMS, 10)
			T.expectEqual(row, nil)
			T.expectEqual(skinId, nil)
		end)
	end)

	T.describe("ShopCatalog.slots", function()
		T.it("range deux caisses au centre de la rangée du haut", function()
			local slots = Shop.slots(2)
			T.expectEqual(#slots, 2)
			T.expectEqual(slots[1].row, 1)
			T.expectEqual(slots[1].column, -0.5)
			T.expectEqual(slots[2].column, 0.5)
		end)

		T.it("répartit à parts égales entre les rangées, celle du haut servie d'abord (#433)", function()
			local function layout(n)
				local per = {}
				for _, s in Shop.slots(n) do
					per[s.row] = (per[s.row] or 0) + 1
				end
				return table.concat(per, "+")
			end
			T.expectEqual(layout(3), "3")
			T.expectEqual(layout(4), "2+2")
			T.expectEqual(layout(5), "3+2")
			T.expectEqual(layout(6), "3+3")
			local slots = Shop.slots(4) -- série 1 en haut, FILM en bas, chacune centrée
			T.expectEqual(slots[2].row, 1)
			T.expectEqual(slots[2].column, 0.5)
			T.expectEqual(slots[3].row, 2)
			T.expectEqual(slots[3].column, -0.5)
			T.expectEqual(slots[4].index, 4)
		end)

		T.it("ne range pas au-delà de la capacité", function()
			T.expectEqual(#Shop.slots(9), Shop.PER_ROW * Shop.ROWS)
			T.expectEqual(#Shop.slots(0), 0)
		end)

		T.it("liste les rangées vides à garnir", function()
			T.expectEqual(table.concat(Shop.emptyRows(2), ","), "2")
			T.expectEqual(table.concat(Shop.emptyRows(4), ","), "")
			T.expectEqual(table.concat(Shop.emptyRows(0), ","), "1,2")
		end)
	end)

	T.describe("ShopCatalog : navigation et prix", function()
		T.it("passe à la caisse voisine en boucle", function()
			T.expectEqual(Shop.cycle(1, 1, 2), 2)
			T.expectEqual(Shop.cycle(2, 1, 2), 1)
			T.expectEqual(Shop.cycle(1, -1, 2), 2)
			T.expectEqual(Shop.cycle(1, 1, 0), 1)
		end)

		T.it("écrit le prix avec la monnaie", function()
			T.expectEqual(Shop.priceLabel(Shop.crate("crate.awp.serie1")), "500")
		end)
	end)

	-- Cette méthode permet de fabriquer des lignes de contenu de raretés distinctes aux chances données lorsqu'un test
	-- vérifie l'arrondi.
	local function rowsWith(chances: { number })
		local rows = {}
		for i, chance in chances do
			table.insert(rows, {
				rarity = { id = "r" .. i, label = "R" .. i, chance = chance, color = { 0, 0, 0 }, refund = 0 },
				name = "",
				skin = "skin." .. i,
				weapon = "",
				viewmodel = "",
			})
		end
		return rows
	end

	-- Cette méthode permet de sommer une liste de nombres lorsqu'un test vérifie un total.
	local function sum(values: { number }): number
		local total = 0
		for _, value in values do
			total += value
		end
		return total
	end

	T.describe("ShopCatalog : achat (#393)", function()
		T.it("remboursement d'un doublon pour une caisse à 500 : 100, 200, 350, 500", function()
			local crate = Shop.crate("crate.awp.serie1")
			T.expectEqual(crate.price, 500)
			T.expectEqual(Shop.refund(crate, "common"), 100)
			T.expectEqual(Shop.refund(crate, "rare"), 200)
			T.expectEqual(Shop.refund(crate, "exceptional"), 350)
			T.expectEqual(Shop.refund(crate, "legendary"), 500, "100 % : le prix entier")
			T.expectEqual(Shop.refund(crate, "inconnue"), 0)
		end)

		T.it("remboursement proportionnel au prix, entier, jamais plus que le prix", function()
			local crate = table.clone(Shop.crate("crate.awp.serie1"))
			crate.price = 333
			T.expectEqual(Shop.refund(crate, "common"), 66, "333 x 20 % arrondi en dessous")
			T.expectEqual(Shop.refund(crate, "exceptional"), 233)
			for _, rarity in Shop.RARITIES do
				T.expect(rarity.refund >= 0 and rarity.refund <= 100, "part en pour cent : " .. rarity.id)
			end
		end)

		T.it("chances par skin, total exactement 100 % (20 / 5,33 / 1,6 / 0,8)", function()
			local awp = Shop.chances(Shop.contents(Shop.crate("crate.awp.serie1"), Inventory.ITEMS))
			T.expectEqual(table.concat(awp, ","), "2000,2000,2000,2000,534,533,533,160,160,80")
			T.expectEqual(Shop.chanceLabel(awp[1]), "20 %")
			T.expectEqual(Shop.chanceLabel(awp[5]), "5,34 %")
			T.expectEqual(Shop.chanceLabel(awp[8]), "1,6 %")
			T.expectEqual(Shop.chanceLabel(awp[10]), "0,8 %")
			local m9 = Shop.chances(Shop.contents(Shop.crate("crate.m9.serie1"), Inventory.ITEMS))
			T.expectEqual(table.concat(m9, ","), table.concat(awp, ","))
		end)

		T.it("arrondi au plus fort reste : la somme fait toujours 100,0 %", function()
			for _, chances in
				{
					{ 1, 1, 1 },
					{ 2, 1 },
					{ 70, 25 },
					{ 0.3, 0.3, 0.4 },
					{ 1, 2, 3, 4, 5, 6, 7 },
					{ 99.99, 0.005, 0.005 },
					{ 80, 16, 3.2, 0.8 },
				}
			do
				local tenths = Shop.chances(rowsWith(chances))
				T.expectEqual(#tenths, #chances)
				T.expectEqual(sum(tenths), 10000, "somme pour " .. table.concat(chances, "/"))
			end
			-- Tiers : 333,3 x 3 → le reste va à la première ligne (la plus courante)
			T.expectEqual(table.concat(Shop.chances(rowsWith({ 1, 1, 1 })), ","), "3334,3333,3333")
			T.expectEqual(Shop.chanceLabel(3334), "33,34 %")
			T.expectEqual(Shop.chanceLabel(107), "1,07 %")
			T.expectEqual(Shop.chanceLabel(160), "1,6 %")
			T.expectEqual(Shop.chanceLabel(8000), "80 %")
			-- Rareté absente (caisse sans skin rare) : proportions renormalisées comme le tirage
			T.expectEqual(table.concat(Shop.chances(rowsWith({ 70, 5 })), ","), "9333,667")
			T.expectEqual(#Shop.chances({}), 0)
			T.expectEqual(#Shop.chances(rowsWith({ 0, 0 })), 0)
		end)

		T.it("tout obtenu seulement si tous les skins de la caisse sont possédés", function()
			local crate = Shop.crate("crate.awp.serie1")
			local owned = {}
			for _, row in Shop.contents(crate, Inventory.ITEMS) do
				owned[row.skin] = true
			end
			owned["skin.awp.trempe"] = nil
			T.expectEqual(Shop.allOwned(crate, Inventory.ITEMS, owned), false, "un légendaire manquant")
			owned["skin.awp.trempe"] = true
			T.expectEqual(Shop.allOwned(crate, Inventory.ITEMS, owned), true)
			T.expectEqual(Shop.allOwned(Shop.crate("crate.m9.serie1"), Inventory.ITEMS, owned), false, "autre arme")
			local empty = table.clone(crate)
			empty.contents = {}
			T.expectEqual(Shop.allOwned(empty, Inventory.ITEMS, owned), false, "caisse vide : refusée comme vide")
		end)

		T.it("rareté d'un skin lue dans la caisse de son arme, sinon dans la réserve", function()
			local function rarityId(id: string): string?
				local rarity = Shop.rarityOf(Inventory.item(id))
				return rarity and rarity.id
			end
			T.expectEqual(rarityId("skin.awp.maquis"), "common")
			T.expectEqual(rarityId("skin.awp.balise"), "exceptional")
			T.expectEqual(rarityId("skin.awp.trempe"), "legendary")
			T.expectEqual(rarityId("skin.m9bayonet.couchant"), "legendary")
			T.expectEqual(rarityId("skin.awp.circuit"), "rare")
			T.expectEqual(rarityId("skin.m9bayonet.email"), "exceptional")
			T.expectEqual(rarityId("skin.m9bayonet.guilloche"), "rare")
			T.expectEqual(rarityId("skin.awp.ciselure"), "legendary", "série 2")
			T.expectEqual(rarityId("skin.awp.remorqueur"), "exceptional", "série 2")
			T.expectEqual(rarityId("skin.awp.velours"), "exceptional", "série 2")
			T.expectEqual(rarityId("skin.awp.parquet"), "common", "série 2")
			T.expectEqual(rarityId("skin.m9bayonet.sphinx"), "rare", "réserve")
			T.expectEqual(rarityId("skin.m9bayonet.topo"), "common", "réserve")
			T.expectEqual(Shop.rarityOf({ weapon = "weapon.m9bayonet", appearance = "orage" }), nil, "autre arme")
			T.expectEqual(Shop.rarityOf(Inventory.item("weapon.awp")), nil, "une arme n'a pas de rareté")
		end)

		T.it("chaque skin d'une caisse a la rareté de sa ligne", function()
			for _, crate in Shop.CRATES do
				for _, row in Shop.contents(crate, Inventory.ITEMS) do
					local rarity = Shop.rarityOf(Inventory.item(row.skin))
					T.expectEqual(rarity and rarity.id, row.rarity.id, row.skin)
				end
			end
		end)
	end)

	T.describe("ShopCatalog : pochoir du couvercle (#434)", function()
		T.it("série et arme lues dans le catalogue", function()
			T.expectEqual(Shop.stencil(Shop.crate("crate.awp.serie1")), "S1-AWP")
			T.expectEqual(Shop.stencil(Shop.crate("crate.m9.serie1")), "S1-M9")
			T.expectEqual(Shop.stencil(Shop.crate("crate.awp.serie2")), "S2-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.awp.film", weapon = "weapon.awp" }), "FM-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.m9.film", weapon = "weapon.m9bayonet" }), "FM-M9")
		end)

		T.it("chaque caisse du catalogue a un pochoir à elle", function()
			local seen = {}
			for _, crate in Shop.CRATES do
				local text = Shop.stencil(crate)
				T.expect(
					text ~= "" and not seen[text],
					crate.id .. " : pochoir vide ou déjà pris (" .. text .. "), lui donner un champ `series` (#454)"
				)
				seen[text] = true
			end
		end)

		T.it("id de série avec séparateurs : le code garde la série", function()
			T.expectEqual(Shop.stencil({ id = "crate.awp.serie-2", weapon = "weapon.awp" }), "S2-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.awp.dragon_lore", weapon = "weapon.awp" }), "DE-AWP")
		end)

		T.it("nouvelle série ou nouvelle arme : texte dérivé sans table à compléter", function()
			T.expectEqual(Shop.stencil({ id = "crate.awp.serie12", weapon = "weapon.awp" }), "S12-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.ak.neon", weapon = "weapon.ak47" }), "NN-AK47")
		end)

		T.it("code de série explicite prioritaire sur l'id (#454)", function()
			-- `foam` donnerait « FM » comme `film` : le champ lève la collision sans renommer l'id
			T.expectEqual(Shop.stencil({ id = "crate.awp.foam", weapon = "weapon.awp", series = "FO" }), "FO-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.awp.foam", weapon = "weapon.awp" }), "FM-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.awp.serie", weapon = "weapon.awp", series = "s0" }), "S0-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.awp", weapon = "weapon.awp", series = "X1" }), "X1-AWP")
			T.expectEqual(Shop.stencil({ id = "crate.awp.film", weapon = "weapon.awp", series = "" }), "FM-AWP")
			T.expectEqual(Shop.stencil({ series = "FO" }), "FO")
		end)

		T.it("code de série explicite du catalogue : capitales et chiffres, court", function()
			for _, crate in Shop.CRATES do
				if crate.series ~= nil then
					T.expect(
						string.match(crate.series, "^[%u%d]+$") ~= nil and #crate.series <= 4,
						crate.id .. " : series attendu en capitales ou chiffres, 4 au plus (" .. crate.series .. ")"
					)
				end
			end
		end)

		T.it("caisse sans série, sans arme ou inconnue : repli sans erreur", function()
			T.expectEqual(Shop.stencil({ id = "crate.awp", weapon = "weapon.awp" }), "AWP")
			T.expectEqual(Shop.stencil({ id = "autre", weapon = "weapon.m9bayonet" }), "M9")
			T.expectEqual(Shop.stencil({ id = "crate.awp.film" }), "FM")
			T.expectEqual(Shop.stencil({}), "")
			T.expectEqual(Shop.stencil(nil), "")
		end)
	end)
end

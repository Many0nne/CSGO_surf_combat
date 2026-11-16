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

		T.it("caisses dans l'ordre de la vitrine : série 1 puis FILM (#433), AWP puis M9", function()
			local ids = {}
			for _, crate in Shop.CRATES do
				table.insert(ids, crate.id)
			end
			T.expectEqual(table.concat(ids, ","), "crate.awp.serie1,crate.m9.serie1,crate.awp.film,crate.m9.film")
		end)

		T.it("une caisse FILM par arme, de 6 skins, rareté des skins fixée par arme (#433, #430)", function()
			local function contents(id)
				local parts = {}
				for _, rarity in Shop.RARITIES do
					table.insert(parts, rarity.id .. "=" .. table.concat(Shop.crate(id).contents[rarity.id] or {}, ","))
				end
				return table.concat(parts, ";")
			end
			T.expectEqual(
				contents("crate.awp.film"),
				"common=logogramme;rare=mue,circuit;exceptional=remorqueur,balise,pan;legendary="
			)
			T.expectEqual(
				contents("crate.m9.film"),
				"common=hote,artdeco;rare=patrouille,sphinx;exceptional=recuit;legendary=couchant"
			)
			T.expectEqual(#Shop.contents(Shop.crate("crate.awp.film"), Inventory.ITEMS), 6)
			T.expectEqual(#Shop.contents(Shop.crate("crate.m9.film"), Inventory.ITEMS), 6)
		end)

		T.it("chaque caisse a un id unique, un prix positif et de 6 à 8 skins connus de son arme (#424)", function()
			local seen = {}
			for _, crate in Shop.CRATES do
				T.expectEqual(seen[crate.id], nil)
				seen[crate.id] = true
				T.expectEqual(crate.price > 0, true)
				local rows = Shop.contents(crate, Inventory.ITEMS)
				T.expect(#rows >= 6 and #rows <= 8, crate.id .. " : " .. #rows .. " skins")
				for _, rarity in Shop.RARITIES do
					local found = rarity.id == "legendary" and crate.id == "crate.awp.film" -- pas encore de légendaire (#430)
					for _, row in rows do
						found = found or row.rarity.id == rarity.id
					end
					T.expect(found, crate.id .. " sans skin " .. rarity.id)
				end
				for _, row in rows do
					local item = Inventory.item(row.skin)
					T.expectEqual(item ~= nil, true)
					T.expectEqual(item.weapon, crate.weapon)
				end
			end
		end)

		-- Une série peut reprendre les skins d'une autre (#433) : partout à la même rareté, sinon rarityOf (première
		-- caisse) contredirait la caisse qui l'affiche
		T.it(
			"chaque apparence listée existe, une fois par caisse, et a la même rareté dans toutes ses caisses",
			function()
				local rarityByKey = {}
				for _, crate in Shop.CRATES do
					local listed, inCrate = 0, {}
					for rarityId, appearances in crate.contents do
						for _, appearance in appearances do
							local key = crate.weapon .. "/" .. appearance
							T.expectEqual(inCrate[key], nil, crate.id .. " : " .. key .. " en double")
							inCrate[key] = true
							T.expectEqual(rarityByKey[key] or rarityId, rarityId, key)
							rarityByKey[key] = rarityId
							listed += 1
						end
					end
					T.expectEqual(#Shop.contents(crate, Inventory.ITEMS), listed, crate.id .. " : apparence inconnue")
				end
			end
		)

		T.it("tous les skins du jeu sont dans une caisse", function()
			for _, item in Inventory.ITEMS do
				if item.type == "skin" then
					T.expect(Shop.rarityOf(item) ~= nil, item.id .. " hors caisse")
				end
			end
		end)

		T.it("trouve une caisse par son id", function()
			T.expectEqual(Shop.crate("crate.awp.serie1").name, "AWP · SÉRIE 1")
			T.expectEqual(Shop.crate("crate.m9.serie1").weapon, "weapon.m9bayonet")
			T.expectEqual(Shop.crate("crate.inconnue"), nil)
		end)
	end)

	T.describe("ShopCatalog.contents", function()
		T.it("un skin par ligne, par rareté puis dans l'ordre du catalogue, avec le viewmodel de l'arme", function()
			local rows = Shop.contents(Shop.crate("crate.awp.serie1"), Inventory.ITEMS)
			T.expectEqual(names(rows), "MAQUIS,MUE,ORAGE,CIRCUIT,BALISE,PAN !,TREMPE,CISELURE")
			T.expectEqual(rows[1].rarity.label, "COMMUN")
			T.expectEqual(rows[1].skin, "skin.awp.maquis")
			T.expectEqual(rows[1].viewmodel, "AWP")
			T.expectEqual(rows[1].weapon, "AWP")
			T.expectEqual(rows[2].rarity.label, "RARE")
			T.expectEqual(rows[5].rarity.label, "EXCEPTIONNEL")
			T.expectEqual(rows[8].rarity.label, "LÉGENDAIRE")
			local knife = Shop.contents(Shop.crate("crate.m9.serie1"), Inventory.ITEMS)
			T.expectEqual(names(knife), "ART DÉCO,PATROUILLE,RELEVÉ,ÉMAIL,RECUIT,COUCHANT")
			T.expectEqual(knife[6].skin, "skin.m9bayonet.couchant")
			T.expectEqual(knife[1].viewmodel, "M9Bayonet")
			T.expectEqual(knife[1].weapon, "M9")
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

		T.it("compose la ligne sous le nom", function()
			T.expectEqual(
				Shop.subtitle(Shop.crate("crate.awp.serie1"), Inventory.ITEMS),
				"CAISSE  ·  8 SKINS  ·  UN PAR OUVERTURE"
			)
		end)
	end)

	T.describe("ShopCatalog.draw (#332, #424)", function()
		local crate = Shop.crate("crate.awp.serie1")

		T.it("partage la chance d'une rareté entre ses skins (AWP : 80 / 3 x 5,3 / 2 x 1,6 / 2 x 0,4)", function()
			local function at(roll)
				local row, skinId = Shop.draw(crate, Inventory.ITEMS, roll)
				return row.rarity.id .. ":" .. skinId
			end
			T.expectEqual(at(0), "common:skin.awp.maquis")
			T.expectEqual(at(79.99), "common:skin.awp.maquis")
			T.expectEqual(at(80), "rare:skin.awp.mue")
			T.expectEqual(at(85.4), "rare:skin.awp.orage")
			T.expectEqual(at(91), "rare:skin.awp.circuit")
			T.expectEqual(at(96.1), "exceptional:skin.awp.balise")
			T.expectEqual(at(97.7), "exceptional:skin.awp.pan")
			T.expectEqual(at(99.3), "legendary:skin.awp.trempe")
			T.expectEqual(at(99.7), "legendary:skin.awp.ciselure")
			T.expectEqual(at(99.999), "legendary:skin.awp.ciselure")
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

		T.it("AWP · FILM n'a pas de légendaire : jamais tiré, chances renormalisées (#430)", function()
			local film = Shop.crate("crate.awp.film")
			for i = 0, 999 do
				local row = Shop.draw(film, Inventory.ITEMS, i / 10)
				T.expect(row.rarity.id ~= "legendary", "légendaire tiré au roll " .. i / 10)
			end
			T.expectEqual(Shop.draw(film, Inventory.ITEMS, 99.999).rarity.id, "exceptional")
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

		T.it(
			"chances par skin, total exactement 100 % (AWP 80 / 5,34-5,33 / 1,6 / 0,4 ; M9 80 / 8 / 1,6 / 0,8)",
			function()
				local awp = Shop.chances(Shop.contents(Shop.crate("crate.awp.serie1"), Inventory.ITEMS))
				T.expectEqual(table.concat(awp, ","), "8000,534,533,533,160,160,40,40")
				T.expectEqual(Shop.chanceLabel(awp[1]), "80 %")
				T.expectEqual(Shop.chanceLabel(awp[2]), "5,34 %")
				T.expectEqual(Shop.chanceLabel(awp[8]), "0,4 %")
				local m9 = Shop.chances(Shop.contents(Shop.crate("crate.m9.serie1"), Inventory.ITEMS))
				T.expectEqual(table.concat(m9, ","), "8000,800,800,160,160,80")
				T.expectEqual(Shop.chanceLabel(m9[1]), "80 %")
			end
		)

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
			owned["skin.awp.ciselure"] = nil
			T.expectEqual(Shop.allOwned(crate, Inventory.ITEMS, owned), false, "un légendaire manquant")
			owned["skin.awp.ciselure"] = true
			T.expectEqual(Shop.allOwned(crate, Inventory.ITEMS, owned), true)
			T.expectEqual(Shop.allOwned(Shop.crate("crate.m9.serie1"), Inventory.ITEMS, owned), false, "autre arme")
			local empty = table.clone(crate)
			empty.contents = {}
			T.expectEqual(Shop.allOwned(empty, Inventory.ITEMS, owned), false, "caisse vide : refusée comme vide")
		end)

		T.it("rareté d'un skin lue dans la caisse de son arme, nil hors caisse", function()
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
			T.expectEqual(Shop.stencil(Shop.crate("crate.awp.film")), "FM-AWP")
			T.expectEqual(Shop.stencil(Shop.crate("crate.m9.film")), "FM-M9")
		end)

		T.it("chaque caisse du catalogue a un pochoir à elle", function()
			local seen = {}
			for _, crate in Shop.CRATES do
				local text = Shop.stencil(crate)
				T.expect(text ~= "" and not seen[text], crate.id .. " : pochoir vide ou déjà pris (" .. text .. ")")
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

		T.it("caisse sans série, sans arme ou inconnue : repli sans erreur", function()
			T.expectEqual(Shop.stencil({ id = "crate.awp", weapon = "weapon.awp" }), "AWP")
			T.expectEqual(Shop.stencil({ id = "autre", weapon = "weapon.m9bayonet" }), "M9")
			T.expectEqual(Shop.stencil({ id = "crate.awp.film" }), "FM")
			T.expectEqual(Shop.stencil({}), "")
			T.expectEqual(Shop.stencil(nil), "")
		end)
	end)
end

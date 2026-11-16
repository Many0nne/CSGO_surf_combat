-- Catalogue du shop (#347) : caisses, contenu par rareté lu dans le catalogue des items, rangement dans la vitrine.
return function(T, Loader)
	local Shop = Loader.new({}):require("src/shared/ShopCatalog")
	local Inventory = Loader.new({}):require("src/shared/InventoryRules")

	T.describe("ShopCatalog : catalogue", function()
		T.it("les chances des raretés font 100 %", function()
			local total = 0
			for _, rarity in Shop.RARITIES do
				total += rarity.chance
			end
			T.expectEqual(total, 100)
		end)

		T.it(
			"quatre caisses dans l'ordre de la vitrine : AWP série 1, M9 série 1, AWP série 2, M9 série 2",
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

		T.it("chaque caisse a un id unique, un prix positif et un seul skin connu de son arme par rareté", function()
			local seen = {}
			for _, crate in Shop.CRATES do
				T.expectEqual(seen[crate.id], nil)
				seen[crate.id] = true
				T.expectEqual(crate.price > 0, true)
				local rows = Shop.contents(crate, Inventory.ITEMS)
				T.expectEqual(#rows, #Shop.RARITIES)
				for _, row in rows do
					T.expectEqual(#row.skins, 1)
					local item = Inventory.item(row.skins[1])
					T.expectEqual(item ~= nil, true)
					T.expectEqual(item.weapon, crate.weapon)
				end
			end
		end)

		T.it("une apparence ne sort que d'une seule caisse par arme", function()
			local owner = {}
			for _, crate in Shop.CRATES do
				for _, appearance in crate.contents do
					local key = crate.weapon .. "/" .. appearance
					T.expectEqual(owner[key], nil)
					owner[key] = crate.id
				end
			end
		end)

		T.it("trouve une caisse par son id", function()
			T.expectEqual(Shop.crate("crate.awp.serie1").name, "AWP · SÉRIE 1")
			T.expectEqual(Shop.crate("crate.m9.serie2").weapon, "weapon.m9bayonet")
			T.expectEqual(Shop.crate("crate.inconnue"), nil)
		end)
	end)

	T.describe("ShopCatalog.contents", function()
		T.it(
			"liste les raretés de la plus courante à la plus rare, avec le seul skin de l'arme de la caisse",
			function()
				local rows = Shop.contents(Shop.crate("crate.awp.serie1"), Inventory.ITEMS)
				T.expectEqual(rows[1].rarity.label, "COMMUN")
				T.expectEqual(rows[1].name, "BALISE")
				T.expectEqual(table.concat(rows[1].weapons, " · "), "AWP")
				T.expectEqual(table.concat(rows[1].skins, ","), "skin.awp.balise")
				T.expectEqual(rows[3].rarity.label, "EXCEPTIONNEL")
				T.expectEqual(rows[3].name, "ORAGE")
				local knife = Shop.contents(Shop.crate("crate.m9.serie1"), Inventory.ITEMS)
				T.expectEqual(table.concat(knife[1].weapons, " · "), "M9")
				T.expectEqual(table.concat(knife[1].skins, ","), "skin.m9bayonet.couchant")
			end
		)

		T.it("omet une rareté dont le skin n'existe pas", function()
			local crate = {
				id = "x",
				name = "X",
				weapon = "weapon.awp",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = "absent" },
			}
			T.expectEqual(#Shop.contents(crate, Inventory.ITEMS), 0)
		end)

		T.it("compose la ligne sous le nom", function()
			T.expectEqual(
				Shop.subtitle(Shop.crate("crate.awp.serie1"), Inventory.ITEMS),
				"CAISSE  ·  BALISE / PAN ! / ORAGE"
			)
		end)
	end)

	T.describe("ShopCatalog.draw (#332)", function()
		local crate = Shop.crate("crate.awp.serie1")

		T.it("répartit un roll de [0, 100) en 70 / 25 / 5 sur commun, rare, exceptionnel", function()
			local function rarityAt(roll)
				local row, skinId = Shop.draw(crate, Inventory.ITEMS, roll)
				return row.rarity.id .. ":" .. skinId
			end
			T.expectEqual(rarityAt(0), "common:skin.awp.balise")
			T.expectEqual(rarityAt(69.99), "common:skin.awp.balise")
			T.expectEqual(rarityAt(70), "rare:skin.awp.pan")
			T.expectEqual(rarityAt(94.99), "rare:skin.awp.pan")
			T.expectEqual(rarityAt(95), "exceptional:skin.awp.orage")
			T.expectEqual(rarityAt(99.999), "exceptional:skin.awp.orage")
		end)

		T.it("ramène un roll hors bornes ou invalide dans [0, 100)", function()
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, -5).rarity.id, "common")
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, 100).rarity.id, "exceptional")
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, 1e9).rarity.id, "exceptional")
			T.expectEqual(Shop.draw(crate, Inventory.ITEMS, 0 / 0).rarity.id, "common")
		end)

		T.it("tire le skin de l'arme de la caisse (M9)", function()
			local _, skinId = Shop.draw(Shop.crate("crate.m9.serie2"), Inventory.ITEMS, 80)
			T.expectEqual(skinId, "skin.m9bayonet.artdeco")
		end)

		T.it("suit les chances affichées sur un balayage régulier du roll", function()
			local counts = { common = 0, rare = 0, exceptional = 0 }
			for i = 0, 999 do
				local row = Shop.draw(crate, Inventory.ITEMS, i / 10)
				counts[row.rarity.id] += 1
			end
			T.expectEqual(counts.common, 700)
			T.expectEqual(counts.rare, 250)
			T.expectEqual(counts.exceptional, 50)
		end)

		T.it("exclut une rareté sans skin et renormalise les chances restantes", function()
			-- Rare absente : commun 70 / (70 + 5), exceptionnel 5 / 75
			local partial = {
				id = "x",
				name = "X",
				weapon = "weapon.awp",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = "balise", rare = "absent", exceptional = "orage" },
			}
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 0).rarity.id, "common")
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 93.2).rarity.id, "common")
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 93.4).rarity.id, "exceptional")
			T.expectEqual(Shop.draw(partial, Inventory.ITEMS, 99.99).rarity.id, "exceptional")
		end)

		T.it("ne tire rien d'une caisse sans aucun skin connu", function()
			local empty = {
				id = "x",
				name = "X",
				weapon = "weapon.awp",
				stripe = { 0, 0, 0 },
				price = 1,
				contents = { common = "absent" },
			}
			local row, skinId = Shop.draw(empty, Inventory.ITEMS, 10)
			T.expectEqual(row, nil)
			T.expectEqual(skinId, nil)
		end)
	end)

	-- Cette méthode permet de fabriquer des lignes de contenu de luminance donnée lorsqu'un test de placement en a besoin.
	local function rowsOf(values: { number })
		local rows = {}
		for _, value in values do
			table.insert(rows, { rarity = Shop.RARITIES[1], name = "", weapons = {}, skins = {}, luminance = value })
		end
		return rows
	end

	T.describe("ShopCatalog.columns (#366)", function()
		T.it("chaque skin du catalogue a une luminance mesurée", function()
			for _, item in Inventory.ITEMS do
				if item.type == "skin" then
					T.expectEqual(
						type(item.luminance) == "number" and item.luminance >= 0 and item.luminance <= 1,
						true
					)
				end
			end
		end)

		T.it(
			"met le skin le plus sombre au milieu, les autres à gauche puis à droite dans l'ordre du contenu",
			function()
				T.expectEqual(table.concat(Shop.columns(rowsOf({ 0.5, 0.1, 0.3 }), 3), ","), "1,2,3")
				T.expectEqual(table.concat(Shop.columns(rowsOf({ 0.1, 0.5, 0.3 }), 3), ","), "2,1,3")
				T.expectEqual(table.concat(Shop.columns(rowsOf({ 0.5, 0.3, 0.1 }), 3), ","), "1,3,2")
			end
		)

		T.it("à luminance égale, garde l'ordre du contenu", function()
			T.expectEqual(table.concat(Shop.columns(rowsOf({ 0.2, 0.2, 0.2 }), 3), ","), "2,1,3")
		end)

		T.it("deux lignes : la plus sombre au milieu, l'autre à gauche", function()
			T.expectEqual(table.concat(Shop.columns(rowsOf({ 0.4, 0.1 }), 3), ","), "1,2")
		end)

		T.it("nombre pair de colonnes : les deux du milieu d'abord", function()
			T.expectEqual(table.concat(Shop.columns(rowsOf({ 0.1, 0.2, 0.3, 0.4 }), 4), ","), "2,3,1,4")
		end)

		T.it("une ligne au-delà des colonnes n'est pas placée", function()
			local columns = Shop.columns(rowsOf({ 0.4, 0.1, 0.2, 0.3 }), 3)
			T.expectEqual(columns[2], 2)
			T.expectEqual(columns[3], 1)
			T.expectEqual(columns[4], 3)
			T.expectEqual(columns[1], nil)
		end)

		T.it(
			"les caisses en vente mettent leur skin le plus sombre au milieu (Pan ! et Circuit, Couchant et Recuit)",
			function()
				local expected = {
					["crate.awp.serie1"] = "PAN !",
					["crate.m9.serie1"] = "COUCHANT",
					["crate.awp.serie2"] = "CIRCUIT",
					["crate.m9.serie2"] = "RECUIT",
				}
				for id, name in expected do
					local rows = Shop.contents(Shop.crate(id), Inventory.ITEMS)
					local middle
					for i, column in Shop.columns(rows, 3) do
						if column == 2 then
							middle = rows[i].name
						end
					end
					T.expectEqual(middle, name)
				end
			end
		)
	end)

	T.describe("ShopCatalog.slots", function()
		T.it("range les quatre caisses : trois en haut, une centrée en bas", function()
			local slots = Shop.slots(#Shop.CRATES)
			T.expectEqual(#slots, 4)
			T.expectEqual(slots[1].column, -1)
			T.expectEqual(slots[3].column, 1)
			T.expectEqual(slots[4].row, 2)
			T.expectEqual(slots[4].column, 0)
		end)

		T.it("range deux caisses au centre de la rangée du haut", function()
			local slots = Shop.slots(2)
			T.expectEqual(#slots, 2)
			T.expectEqual(slots[1].row, 1)
			T.expectEqual(slots[1].column, -0.5)
			T.expectEqual(slots[2].column, 0.5)
		end)

		T.it("remplit la rangée du haut avant celle du bas", function()
			local slots = Shop.slots(4)
			T.expectEqual(slots[3].row, 1)
			T.expectEqual(slots[3].column, 1)
			T.expectEqual(slots[4].row, 2)
			T.expectEqual(slots[4].column, 0)
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

	-- Cette méthode permet de fabriquer des lignes de contenu aux chances données lorsqu'un test vérifie l'arrondi.
	local function rowsWith(chances: { number })
		local rows = {}
		for i, chance in chances do
			table.insert(rows, {
				rarity = { id = "r" .. i, label = "R" .. i, chance = chance, color = { 0, 0, 0 }, refund = 0 },
				name = "",
				weapons = {},
				skins = { "skin." .. i },
				luminance = 1,
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
		T.it("remboursement d'un doublon pour une caisse à 500 : 100, 200, 350", function()
			local crate = Shop.crate("crate.awp.serie1")
			T.expectEqual(crate.price, 500)
			T.expectEqual(Shop.refund(crate, "common"), 100)
			T.expectEqual(Shop.refund(crate, "rare"), 200)
			T.expectEqual(Shop.refund(crate, "exceptional"), 350)
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

		T.it("chances d'une caisse : 70 %, 25 %, 5 %, total exactement 100 %", function()
			local rows = Shop.contents(Shop.crate("crate.m9.serie2"), Inventory.ITEMS)
			local tenths = Shop.chances(rows)
			T.expectEqual(table.concat(tenths, ","), "700,250,50")
			T.expectEqual(Shop.chanceLabel(tenths[1]), "70 %")
			T.expectEqual(Shop.chanceLabel(tenths[3]), "5 %")
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
				}
			do
				local tenths = Shop.chances(rowsWith(chances))
				T.expectEqual(#tenths, #chances)
				T.expectEqual(sum(tenths), 1000, "somme pour " .. table.concat(chances, "/"))
			end
			-- Tiers : 333,3 x 3 → le reste va à la première ligne (la plus courante)
			T.expectEqual(table.concat(Shop.chances(rowsWith({ 1, 1, 1 })), ","), "334,333,333")
			T.expectEqual(Shop.chanceLabel(334), "33,4 %")
			-- Rareté absente (caisse sans skin rare) : proportions renormalisées comme le tirage
			T.expectEqual(table.concat(Shop.chances(rowsWith({ 70, 5 })), ","), "933,67")
			T.expectEqual(#Shop.chances({}), 0)
			T.expectEqual(#Shop.chances(rowsWith({ 0, 0 })), 0)
		end)

		T.it("tout obtenu seulement si tous les skins de la caisse sont possédés", function()
			local crate = Shop.crate("crate.awp.serie1")
			local owned = { ["skin.awp.balise"] = true, ["skin.awp.pan"] = true }
			T.expectEqual(Shop.allOwned(crate, Inventory.ITEMS, owned), false)
			owned["skin.awp.orage"] = true
			T.expectEqual(Shop.allOwned(crate, Inventory.ITEMS, owned), true)
			T.expectEqual(Shop.allOwned(Shop.crate("crate.m9.serie1"), Inventory.ITEMS, owned), false, "autre arme")
			local empty = table.clone(crate)
			empty.contents = {}
			T.expectEqual(Shop.allOwned(empty, Inventory.ITEMS, owned), false, "caisse vide : refusée comme vide")
		end)
	end)
end

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

		T.it("chaque caisse a un id unique, un prix positif et un skin connu par rareté (AWP et M9)", function()
			local seen = {}
			for _, crate in Shop.CRATES do
				T.expectEqual(seen[crate.id], nil)
				seen[crate.id] = true
				T.expectEqual(crate.price > 0, true)
				local rows = Shop.contents(crate, Inventory.ITEMS)
				T.expectEqual(#rows, #Shop.RARITIES)
				for _, row in rows do
					T.expectEqual(#row.skins, 2)
					for _, id in row.skins do
						T.expectEqual(Inventory.item(id) ~= nil, true)
					end
				end
			end
		end)

		T.it("une apparence ne sort que d'une seule caisse", function()
			local owner = {}
			for _, crate in Shop.CRATES do
				for _, appearance in crate.contents do
					T.expectEqual(owner[appearance], nil)
					owner[appearance] = crate.id
				end
			end
		end)

		T.it("trouve une caisse par son id", function()
			T.expectEqual(Shop.crate("crate.serie1").name, "SÉRIE 1")
			T.expectEqual(Shop.crate("crate.inconnue"), nil)
		end)
	end)

	T.describe("ShopCatalog.contents", function()
		T.it("liste les raretés de la plus courante à la plus rare, armes nommées court", function()
			local rows = Shop.contents(Shop.crate("crate.serie1"), Inventory.ITEMS)
			T.expectEqual(rows[1].rarity.label, "COMMUN")
			T.expectEqual(rows[1].name, "COUCHANT")
			T.expectEqual(table.concat(rows[1].weapons, " · "), "AWP · M9")
			T.expectEqual(rows[3].rarity.label, "EXCEPTIONNEL")
			T.expectEqual(rows[3].name, "RELEVÉ")
		end)

		T.it("omet une rareté dont le skin n'existe pas", function()
			local crate = { id = "x", name = "X", stripe = { 0, 0, 0 }, price = 1, contents = { common = "absent" } }
			T.expectEqual(#Shop.contents(crate, Inventory.ITEMS), 0)
		end)

		T.it("compose la ligne sous le nom", function()
			T.expectEqual(
				Shop.subtitle(Shop.crate("crate.serie1"), Inventory.ITEMS),
				"CAISSE  ·  COUCHANT / IMPACT / RELEVÉ"
			)
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
			T.expectEqual(Shop.priceLabel(Shop.crate("crate.serie1")), "500 CRÉDITS")
		end)
	end)
end

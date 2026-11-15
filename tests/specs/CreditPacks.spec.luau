-- Packs de crédits en Robux (#395) : config cohérente (ids et produits uniques, montants valides, prix croissants) et
-- recherche par id ou par Developer Product.
return function(T, Loader)
	local Packs = Loader.new({}):require("src/shared/CreditPacks")
	local Wallet = Loader.new({}):require("src/shared/WalletRules")

	T.describe("CreditPacks", function()
		T.it("trois packs : 500 à 99 R$, 1 100 à 199 R$, 3 000 à 499 R$", function()
			T.expectEqual(#Packs.PACKS, 3)
			local expected = { { 500, 99 }, { 1100, 199 }, { 3000, 499 } }
			for i, pack in Packs.PACKS do
				T.expectEqual(pack.credits, expected[i][1])
				T.expectEqual(pack.robux, expected[i][2])
			end
		end)

		T.it("ids et produits uniques, montants valides", function()
			local ids, products = {}, {}
			for _, pack in Packs.PACKS do
				T.expect(not ids[pack.id], "id en double : " .. pack.id)
				T.expect(not products[pack.productId], "produit en double : " .. pack.id)
				ids[pack.id] = true
				products[pack.productId] = true
				T.expect(Wallet.isAmount(pack.credits), "crédits invalides : " .. pack.id)
				T.expect(type(pack.productId) == "number" and pack.productId > 0, "produit invalide : " .. pack.id)
				T.expect(#pack.id <= 64, "id trop long pour la garde du remote")
			end
		end)

		T.it("recherche par id et par produit ; inconnu : nil", function()
			local pack = Packs.PACKS[2]
			T.expectEqual(Packs.byId(pack.id), pack)
			T.expectEqual(Packs.byProduct(pack.productId), pack)
			T.expectEqual(Packs.byId("pack.inconnu"), nil)
			T.expectEqual(Packs.byProduct(1), nil)
			T.expectEqual(Packs.byProduct(tostring(pack.productId)), nil, "un id en texte n'est pas un produit")
		end)

		T.it("prêt seulement quand aucun pack ne garde un id provisoire", function()
			local fresh = Loader.new({}):require("src/shared/CreditPacks")
			for i, pack in fresh.PACKS do
				pack.productId = 1_000_000_000 + i
			end
			T.expect(fresh.isReady(), "vrais ids")
			fresh.PACKS[2].productId = 3_950_002
			T.expect(not fresh.isReady(), "un id provisoire restant")
		end)

		T.it("config livrée : vrais Developer Products, packs proposés hors de Studio", function()
			T.expect(Packs.isReady(), "un pack garde un id provisoire")
		end)

		T.it("prix affiché en Robux", function()
			T.expectEqual(Packs.priceLabel(Packs.PACKS[1]), "99 R$")
		end)
	end)
end

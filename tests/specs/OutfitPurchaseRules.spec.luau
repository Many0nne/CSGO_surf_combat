-- Règles pures de l'achat d'une tenue au portant (#543) : commande lue au catalogue (inconnue, pas une tenue, sans prix,
-- toutes les tenues en vente), opération de la transaction (débit et tenue ajoutée, déjà possédée, solde stocké) et
-- réponse au client. L'écriture elle-même (double clic, rejeu, deux serveurs) : tests/specs/WalletStore.spec.luau,
-- « Achat de tenue ».
return function(T, Loader)
	local loader = Loader.new({})
	local Rules = loader:require("src/server/OutfitPurchaseRules")
	local Inventory = loader:require("src/shared/InventoryRules")
	local Wallet = loader:require("src/shared/WalletRules")

	-- Cette méthode permet de construire un enregistrement stocké lorsqu'un test applique l'opération.
	local function record(earned: number, purchased: number, items: { string })
		local w = Wallet.empty()
		w.earned = earned
		w.purchased = purchased
		w.day = 20000
		w.dayEarned = 120
		return { schemaVersion = 2, items = items, wallet = w }
	end

	local ORDER = { outfitId = "outfit.test", price = 2500, rarity = "exceptional" }

	T.describe("OutfitPurchaseRules.order", function()
		T.it("chaque tenue du catalogue avec un prix est en vente, au prix et à la rareté du catalogue", function()
			local count = 0
			for _, item in Inventory.outfits() do
				if item.price then
					local order, why = Rules.order(item.id)
					T.expect(order ~= nil, "en vente : " .. item.id .. " (" .. tostring(why) .. ")")
					T.expectEqual(order.outfitId, item.id)
					T.expectEqual(order.price, item.price)
					T.expectEqual(order.rarity, item.rarity)
					count += 1
				end
			end
			T.expect(count >= 1, "au moins une tenue en vente (MERCURE)")
		end)

		T.it("refuse un id inconnu ou d'un autre type que string : `unknown`", function()
			T.expectEqual(select(2, Rules.order("outfit.inexistante")), "unknown")
			T.expectEqual(select(2, Rules.order(42)), "unknown")
			T.expectEqual(select(2, Rules.order(nil)), "unknown")
			T.expectEqual(select(2, Rules.order(Inventory.OUTFIT_NONE)), "unknown", "tenue d'origine : pas un achat")
		end)

		T.it("refuse un item qui n'est pas une tenue : `unknown`", function()
			T.expectEqual(select(2, Rules.order("weapon.m9bayonet")), "unknown")
			T.expectEqual(select(2, Rules.order("skin.m9bayonet.cordoue")), "unknown")
		end)

		T.it("refuse une tenue sans prix ou au prix invalide : `unavailable`", function()
			table.insert(Inventory.ITEMS, { id = "outfit.sans_prix", type = "outfit", name = "SANS PRIX" })
			table.insert(Inventory.ITEMS, { id = "outfit.gratuite", type = "outfit", name = "GRATUITE", price = 0 })
			table.insert(Inventory.ITEMS, { id = "outfit.fraction", type = "outfit", name = "FRACTION", price = 2.5 })
			Inventory.reindex()
			T.expectEqual(select(2, Rules.order("outfit.sans_prix")), "unavailable")
			T.expectEqual(select(2, Rules.order("outfit.gratuite")), "unavailable")
			T.expectEqual(select(2, Rules.order("outfit.fraction")), "unavailable")
			for _ = 1, 3 do
				table.remove(Inventory.ITEMS)
			end
			Inventory.reindex()
		end)
	end)

	T.describe("OutfitPurchaseRules.operation", function()
		T.it("débite le prix exact (achetés d'abord) et ajoute la tenue, plafond du jour intact", function()
			local rec, added = Rules.operation(ORDER)(record(3000, 1000, { "skin.awp.balise" }))
			T.expect(rec ~= nil)
			T.expectEqual(rec.wallet.purchased, 0, "achetés d'abord")
			T.expectEqual(rec.wallet.earned, 1500)
			T.expectEqual(rec.wallet.earned + rec.wallet.purchased, 4000 - 2500, "solde exact")
			T.expect(table.find(rec.items, "outfit.test") ~= nil, "tenue ajoutée")
			T.expectEqual(#rec.items, 2)
			T.expectEqual(rec.wallet.dayEarned, 120, "hors plafond du jour")
			T.expectEqual(added, "outfit.test")
		end)

		T.it("tenue déjà stockée : enregistrement gardé sans débit, résultat `owned`", function()
			-- Écrit tel quel : l'écriture réunit les items stockés à ceux de la session, qui apprend la tenue
			local rec, why = Rules.operation(ORDER)(record(9000, 0, { "outfit.test" }))
			T.expect(rec ~= nil, "pas de refus : la session doit relire les items")
			T.expectEqual(rec.wallet.earned, 9000, "rien de débité")
			T.expectEqual(#rec.items, 1, "pas de doublon")
			T.expectEqual(why, "owned")
		end)

		T.it("solde stocké insuffisant : refus `insufficient`", function()
			local rec, why = Rules.operation(ORDER)(record(2000, 499, {}))
			T.expectEqual(rec, nil)
			T.expectEqual(why, "insufficient")
		end)

		T.it("solde juste suffisant : passe à 0", function()
			local rec = Rules.operation(ORDER)(record(1250, 1250, {}))
			T.expectEqual(rec.wallet.earned + rec.wallet.purchased, 0)
		end)

		T.it("pure : même résultat à chaque appel sur le même enregistrement", function()
			local op = Rules.operation(ORDER)
			local a = op(record(3000, 0, {}))
			local b = op(record(3000, 0, {}))
			T.expectEqual(a.wallet.earned, b.wallet.earned)
			T.expectEqual(#a.items, #b.items)
		end)
	end)

	T.describe("OutfitPurchaseRules.reply", function()
		T.it("achat écrit : tenue, rareté et prix", function()
			local reply = Rules.reply("ok", "outfit.test", ORDER)
			T.expectEqual(reply.ok, true)
			T.expectEqual(reply.outfitId, "outfit.test")
			T.expectEqual(reply.rarity, "exceptional")
			T.expectEqual(reply.price, 2500)
			T.expectEqual(reply.replayed, nil)
		end)

		T.it("déjà stockée (écrit sans débit) : refus `owned`", function()
			local reply = Rules.reply("ok", "owned", ORDER)
			T.expectEqual(reply.ok, false)
			T.expectEqual(reply.reason, "owned")
		end)

		T.it("rejoué (réponse perdue) : possédée, verdict neutre, aucun prix compté", function()
			local reply = Rules.reply("ok", nil, ORDER)
			T.expectEqual(reply.ok, true)
			T.expectEqual(reply.outfitId, "outfit.test")
			T.expectEqual(reply.replayed, true)
			T.expectEqual(reply.price, nil, "achetée ou déjà stockée : on ne sait pas")
		end)

		T.it("refus et échecs", function()
			T.expectEqual(Rules.reply("rejected", "insufficient", ORDER).reason, "insufficient")
			T.expectEqual(Rules.reply("rejected", "invalid", ORDER).reason, "failed")
			T.expectEqual(Rules.reply("rejected", "error", ORDER).reason, "failed")
			T.expectEqual(Rules.reply("loading", nil, ORDER).reason, "loading")
			local failed = Rules.reply("failed", nil, ORDER)
			T.expectEqual(failed.ok, false)
			T.expectEqual(failed.reason, "failed")
			T.expectEqual(failed.outfitId, nil, "rien de révélé")
		end)
	end)
end

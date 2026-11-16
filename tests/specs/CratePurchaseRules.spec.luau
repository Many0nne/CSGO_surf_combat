-- Règles pures de l'achat d'une caisse (#393) : opération de la transaction (débit, skin ajouté ou doublon remboursé,
-- refus sur le solde stocké, `dayEarned` intact) et réponse au client (rejeu sans résultat, refus, échec).
-- L'écriture elle-même (DataStore, deux serveurs, échecs) : tests/specs/WalletStore.spec.luau, « Achat de caisse ».
return function(T, Loader)
	local Rules = Loader.new({}):require("src/server/CratePurchaseRules")
	local Wallet = Loader.new({}):require("src/shared/WalletRules")

	-- Cette méthode permet de construire un enregistrement stocké lorsqu'un test applique l'opération.
	local function record(earned: number, purchased: number, items: { string })
		local w = Wallet.empty()
		w.earned = earned
		w.purchased = purchased
		w.day = 20000
		w.dayEarned = 120
		return { schemaVersion = 2, items = items, wallet = w }
	end

	local ORDER = { price = 500, skinId = "skin.awp.pan", refund = 200 }

	T.describe("CratePurchaseRules.operation", function()
		T.it("skin neuf : débité (achetés d'abord), skin ajouté, pas de remboursement", function()
			local rec, applied = Rules.operation(ORDER)(record(400, 300, { "skin.awp.balise" }))
			T.expect(rec ~= nil)
			T.expectEqual(rec.wallet.purchased, 0)
			T.expectEqual(rec.wallet.earned, 200)
			T.expect(table.find(rec.items, "skin.awp.pan") ~= nil, "skin ajouté")
			T.expectEqual(applied.duplicate, false)
		end)

		T.it("doublon : débité puis remboursé dans `earned`, items inchangés, plafond du jour intact", function()
			local rec, applied = Rules.operation(ORDER)(record(600, 0, { "skin.awp.pan" }))
			T.expectEqual(rec.wallet.earned, 600 - 500 + 200)
			T.expectEqual(#rec.items, 1)
			T.expectEqual(rec.wallet.dayEarned, 120, "hors plafond du jour")
			T.expectEqual(rec.wallet.day, 20000)
			T.expectEqual(applied.duplicate, true)
		end)

		T.it("doublon payé en crédits achetés : remboursé dans `purchased` (#395)", function()
			local rec = Rules.operation(ORDER)(record(0, 500, { "skin.awp.pan" }))
			T.expectEqual(rec.wallet.purchased, 200)
			T.expectEqual(rec.wallet.earned, 0, "aucun achat converti en gain")
			T.expectEqual(rec.wallet.dayEarned, 120, "hors plafond du jour")
		end)

		T.it(
			"doublon payé en partie en achetés : `purchased` à hauteur du débit, le reste dans `earned`",
			function()
				-- 150 achetés + 350 gagnés débités ; remboursement 200 : 150 rendus aux achetés, 50 aux gagnés
				local rec = Rules.operation(ORDER)(record(400, 150, { "skin.awp.pan" }))
				T.expectEqual(rec.wallet.purchased, 150)
				T.expectEqual(rec.wallet.earned, 50 + 50)
			end
		)

		T.it("doublon payé en achetés au-delà du remboursement : tout rendu aux achetés", function()
			-- 500 achetés débités sur 900 ; remboursement 200 rendu aux achetés, gagnés intacts
			local rec = Rules.operation(ORDER)(record(70, 900, { "skin.awp.pan" }))
			T.expectEqual(rec.wallet.purchased, 600)
			T.expectEqual(rec.wallet.earned, 70)
		end)

		T.it("solde stocké insuffisant : refus `insufficient`, rien de proposé", function()
			local rec, why = Rules.operation(ORDER)(record(300, 199, {}))
			T.expectEqual(rec, nil)
			T.expectEqual(why, "insufficient")
		end)

		T.it("solde juste suffisant : passe à 0", function()
			local rec = Rules.operation(ORDER)(record(250, 250, {}))
			T.expectEqual(rec.wallet.earned + rec.wallet.purchased, 0)
		end)

		T.it("pure : même résultat à chaque appel sur le même enregistrement", function()
			local op = Rules.operation(ORDER)
			local a = op(record(600, 0, {}))
			local b = op(record(600, 0, {}))
			T.expectEqual(a.wallet.earned, b.wallet.earned)
			T.expectEqual(#a.items, #b.items)
		end)

		T.it("remboursement borné au prix", function()
			local rec = Rules.operation({ price = 100, skinId = "s", refund = 900 })(record(100, 0, { "s" }))
			T.expectEqual(rec.wallet.earned, 100)
		end)
	end)

	T.describe("CratePurchaseRules.reply", function()
		T.it("achat écrit : skin, rareté, ajouté ou doublon avec son remboursement", function()
			local new = Rules.reply("ok", { duplicate = false }, ORDER, "rare", false)
			T.expectEqual(new.ok, true)
			T.expectEqual(new.skinId, "skin.awp.pan")
			T.expectEqual(new.rarity, "rare")
			T.expectEqual(new.added, true)
			T.expectEqual(new.refund, 0)
			local dup = Rules.reply("ok", { duplicate = true }, ORDER, "rare", false)
			T.expectEqual(dup.added, false)
			T.expectEqual(dup.refund, 200)
		end)

		T.it(
			"achat rejoué (réponse perdue, pas de résultat) : doublon déduit de ce que la session possédait",
			function()
				local owned = Rules.reply("ok", nil, ORDER, "rare", true)
				T.expectEqual(owned.ok, true)
				T.expectEqual(owned.added, false)
				T.expectEqual(owned.refund, 200)
			end
		)

		T.it("rejeu d'un skin pas possédé avant : jamais « obtenu », verdict neutre (#400)", function()
			-- Un autre serveur a pu donner le skin pendant l'écriture : doublon possible, non vérifiable
			local fresh = Rules.reply("ok", nil, ORDER, "rare", false)
			T.expectEqual(fresh.ok, true)
			T.expectEqual(fresh.skinId, "skin.awp.pan")
			T.expectEqual(fresh.replayed, true)
			T.expectEqual(fresh.added, nil, "ne pas affirmer OBTENU")
			T.expectEqual(fresh.refund, nil)
		end)

		T.it("refus et échecs", function()
			T.expectEqual(Rules.reply("rejected", "insufficient", ORDER, "rare", false).reason, "insufficient")
			T.expectEqual(Rules.reply("rejected", "invalid", ORDER, "rare", false).reason, "failed")
			T.expectEqual(Rules.reply("rejected", "error", ORDER, "rare", false).reason, "failed")
			T.expectEqual(Rules.reply("loading", nil, ORDER, "rare", false).reason, "loading")
			local failed = Rules.reply("failed", nil, ORDER, "rare", false)
			T.expectEqual(failed.ok, false)
			T.expectEqual(failed.reason, "failed")
			T.expectEqual(failed.skinId, nil, "rien de révélé")
		end)
	end)
end

-- Règles pures des reçus Robux (#395) : opération (crédits dans `purchased` et PurchaseId inscrits ensemble, reçu déjà
-- traité, plafond, liste des reçus bornée) et décision rendue à Roblox selon l'issue de la transaction. L'écriture
-- (DataStore, rejeu, deux serveurs, joueur absent) : tests/specs/WalletStore.spec.luau, « Reçus Robux ».
return function(T, Loader)
	local Rules = Loader.new({}):require("src/server/ReceiptRules")
	local Wallet = Loader.new({}):require("src/shared/WalletRules")

	-- Cette méthode permet de construire un enregistrement stocké lorsqu'un test applique l'opération.
	local function record(earned: number, purchased: number, receipts: { string }?)
		local w = Wallet.empty()
		w.earned = earned
		w.purchased = purchased
		w.day = 20000
		w.dayEarned = 120
		w.receipts = receipts or {}
		return { schemaVersion = 2, items = {}, wallet = w }
	end

	T.describe("ReceiptRules.operation", function()
		T.it("crédits dans `purchased` et PurchaseId inscrit dans la même opération", function()
			local rec, result = Rules.operation("achat-1", 500)(record(40, 10))
			T.expectEqual(rec.wallet.purchased, 510)
			T.expectEqual(rec.wallet.earned, 40, "gagnés intacts")
			T.expectEqual(rec.wallet.dayEarned, 120, "hors plafond du jour")
			T.expectEqual(rec.wallet.receipts[#rec.wallet.receipts], "achat-1")
			T.expectEqual(result.credits, 500)
		end)

		T.it("PurchaseId déjà inscrit : refus `duplicate`, rien ajouté", function()
			local rec, why = Rules.operation("achat-1", 500)(record(0, 500, { "achat-0", "achat-1" }))
			T.expectEqual(rec, nil)
			T.expectEqual(why, "duplicate")
		end)

		T.it("pure : même résultat à chaque appel", function()
			local op = Rules.operation("achat-1", 1100)
			local a = op(record(0, 0))
			local b = op(record(0, 0))
			T.expectEqual(a.wallet.purchased, b.wallet.purchased)
			T.expectEqual(#a.wallet.receipts, #b.wallet.receipts)
		end)

		T.it("solde près du plafond : crédits écrêtés, reçu inscrit (jamais laissé en attente)", function()
			local rec, result = Rules.operation("achat-1", 500)(record(Wallet.MAX_BALANCE - 100, 0))
			T.expectEqual(rec.wallet.purchased, 100)
			T.expectEqual(result.credits, 100)
			T.expectEqual(rec.wallet.receipts[1], "achat-1")
			local full = Rules.operation("achat-2", 500)(record(Wallet.MAX_BALANCE, 0))
			T.expectEqual(full.wallet.purchased, 0, "rien à ajouter")
			T.expectEqual(full.wallet.receipts[1], "achat-2")
		end)

		T.it("montant ou PurchaseId invalides : refus `invalid`", function()
			T.expectEqual(select(2, Rules.operation("achat-1", 0)(record(0, 0))), "invalid")
			T.expectEqual(select(2, Rules.operation("", 500)(record(0, 0))), "invalid")
			T.expectEqual(select(2, Rules.operation(string.rep("x", 65), 500)(record(0, 0))), "invalid")
		end)

		T.it("liste des reçus pleine : le plus ancien sort à la relecture, le nouveau reste", function()
			local full = {}
			for i = 1, Wallet.MAX_RECEIPTS do
				table.insert(full, "achat-" .. i)
			end
			local rec = Rules.operation("achat-neuf", 500)(record(0, 0, full))
			local kept = Wallet.read(rec.wallet).receipts
			T.expectEqual(#kept, Wallet.MAX_RECEIPTS)
			T.expectEqual(kept[1], "achat-2")
			T.expectEqual(kept[#kept], "achat-neuf")
		end)
	end)

	T.describe("ReceiptRules.decide", function()
		T.it("écrit : accordé ; écriture rejouée (sans résultat) : accordé", function()
			T.expectEqual((Rules.decide("ok", { credits = 500 })), "granted")
			local verdict, why = Rules.decide("ok", nil)
			T.expectEqual(verdict, "granted")
			T.expect(string.find(why, "rejouée", 1, true) ~= nil)
		end)

		T.it("déjà traité : accordé sans rien ajouter", function()
			T.expectEqual((Rules.decide("rejected", "duplicate")), "granted")
		end)

		T.it("refus, chargement, échec : NotProcessedYet", function()
			T.expectEqual((Rules.decide("rejected", "invalid")), "retry")
			T.expectEqual((Rules.decide("rejected", "error")), "retry")
			T.expectEqual((Rules.decide("loading", nil)), "retry")
			T.expectEqual((Rules.decide("failed", nil)), "retry")
		end)

		T.it("PurchaseId acceptable", function()
			T.expect(Rules.isPurchaseId("a1b2"))
			T.expect(not Rules.isPurchaseId(""))
			T.expect(not Rules.isPurchaseId(42))
			T.expect(not Rules.isPurchaseId(string.rep("x", Wallet.MAX_RECEIPT_LENGTH + 1)))
		end)
	end)
end

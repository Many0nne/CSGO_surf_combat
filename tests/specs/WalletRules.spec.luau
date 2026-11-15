-- WalletRules (#391, #396) : montants valides, portefeuille relu (format de `wallet` dans PlayerInventory_v1), lots de
-- gains fusionnés (lot rejoué, deux sessions, plafond), débit (achetés d'abord, jamais négatif), attribut et affichage.
return function(T, Loader)
	local Wallet = Loader.new({}):require("src/shared/WalletRules")

	-- Cette méthode permet de construire un portefeuille stocké lorsqu'un test part d'un état donné.
	local function wallet(earned: number, purchased: number?)
		local w = Wallet.empty()
		w.earned = earned
		w.purchased = purchased or 0
		return w
	end

	T.describe("WalletRules : montants", function()
		T.it("accepte un solde entier entre 0 et le plafond", function()
			T.expect(Wallet.isBalance(0))
			T.expect(Wallet.isBalance(Wallet.MAX_BALANCE))
			T.expect(not Wallet.isBalance(-1))
			T.expect(not Wallet.isBalance(1.5))
			T.expect(not Wallet.isBalance(Wallet.MAX_BALANCE + 1))
			T.expect(not Wallet.isBalance(math.huge))
			T.expect(not Wallet.isBalance(0 / 0))
			T.expect(not Wallet.isBalance("10"))
		end)

		T.it("refuse un montant nul, négatif, fractionnaire ou infini", function()
			T.expect(Wallet.isAmount(1))
			T.expect(Wallet.isAmount(500))
			T.expect(not Wallet.isAmount(0))
			T.expect(not Wallet.isAmount(-5))
			T.expect(not Wallet.isAmount(2.5))
			T.expect(not Wallet.isAmount(math.huge))
			T.expect(not Wallet.isAmount(nil))
		end)
	end)

	T.describe("WalletRules : format", function()
		T.it("portefeuille absent : départ, réécrivable", function()
			T.expect(Wallet.isWritable(nil))
			local w = Wallet.read(nil)
			T.expectEqual(Wallet.balance(w), Wallet.STARTING_BALANCE)
			T.expectEqual(w.purchased, 0)
			T.expectEqual(w.day, 0)
			T.expectEqual(w.dayEarned, 0)
			T.expectEqual(#w.receipts, 0)
			T.expectEqual(#w.writes, 0)
		end)

		T.it("relit les deux compteurs, le jour (#394), les reçus (#395) et les marques", function()
			local w = Wallet.read({
				earned = 300,
				purchased = 200,
				day = 20400,
				dayEarned = 50,
				receipts = { "achat-1", 12, "achat-2" },
				writes = { { session = "a", seq = 3 }, "x" },
			})
			T.expectEqual(Wallet.balance(w), 500)
			T.expectEqual(w.day, 20400)
			T.expectEqual(w.dayEarned, 50)
			T.expectEqual(table.concat(w.receipts, ","), "achat-1,achat-2")
			T.expectEqual(#w.writes, 1)
			T.expectEqual(Wallet.appliedSeq(w, "a"), 3)
			T.expectEqual(Wallet.appliedSeq(w, "b"), 0)
		end)

		T.it("borne les reçus retenus aux plus récents", function()
			local receipts = {}
			for i = 1, Wallet.MAX_RECEIPTS + 5 do
				table.insert(receipts, "r" .. i)
			end
			local w = Wallet.read({ earned = 0, purchased = 0, receipts = receipts })
			T.expectEqual(#w.receipts, Wallet.MAX_RECEIPTS)
			T.expectEqual(w.receipts[#w.receipts], "r" .. (Wallet.MAX_RECEIPTS + 5))
		end)

		T.it("refuse un portefeuille d'une forme inconnue", function()
			for _, raw in
				{
					"texte",
					{ earned = 10 },
					{ earned = -1, purchased = 0 },
					{ earned = 1.5, purchased = 0 },
					{ earned = Wallet.MAX_BALANCE, purchased = 1 },
					{ earned = 0, purchased = 0, day = -1 },
					{ earned = 0, purchased = 0, receipts = "x" },
					{ earned = 0, purchased = 0, writes = "x" },
				}
			do
				T.expect(not Wallet.isWritable(raw), tostring(raw))
				T.expectEqual(Wallet.balance(Wallet.read(raw)), Wallet.STARTING_BALANCE)
			end
		end)
	end)

	T.describe("WalletRules : lots de gains", function()
		T.it("ajoute les lots à `earned` et avance la marque de la session", function()
			local w =
				Wallet.applyBatches(wallet(100, 40), "a", { { seq = 1, earned = 30 }, { seq = 2, earned = 5 } }, 2)
			T.expectEqual(w.earned, 135)
			T.expectEqual(w.purchased, 40, "achetés intacts")
			T.expectEqual(Wallet.appliedSeq(w, "a"), 2)
		end)

		T.it("un lot rejoué n'est pas recompté", function()
			local first = Wallet.applyBatches(wallet(0), "a", { { seq = 1, earned = 40 } }, 1)
			local again = Wallet.applyBatches(first, "a", { { seq = 1, earned = 40 } }, 1)
			T.expectEqual(again.earned, 40)
			-- Lot 1 renvoyé avec le lot 2 (réponse du premier perdue) : seul le 2 compte
			local both = Wallet.applyBatches(first, "a", { { seq = 1, earned = 40 }, { seq = 2, earned = 10 } }, 2)
			T.expectEqual(both.earned, 50)
		end)

		T.it("deux sessions additionnent leurs gains", function()
			local a = Wallet.applyBatches(wallet(100), "a", { { seq = 1, earned = 60 } }, 1)
			local b = Wallet.applyBatches(a, "b", { { seq = 1, earned = 25 } }, 1)
			T.expectEqual(b.earned, 185)
			T.expectEqual(#b.writes, 2)
		end)

		T.it("écrête au plafond (somme des deux compteurs)", function()
			local w = Wallet.applyBatches(wallet(Wallet.MAX_BALANCE - 10, 5), "a", { { seq = 1, earned = 100 } }, 1)
			T.expectEqual(Wallet.balance(w), Wallet.MAX_BALANCE)
		end)

		T.it("une marque sans lot (transaction) avance aussi, sans rien ajouter", function()
			local w = Wallet.applyBatches(wallet(10), "a", {}, 4)
			T.expectEqual(w.earned, 10)
			T.expectEqual(Wallet.appliedSeq(w, "a"), 4)
		end)

		T.it("ne retient que les dernières sessions, sans modifier l'entrée", function()
			local w = wallet(0)
			for i = 1, Wallet.MAX_WRITE_MARKS + 3 do
				w = Wallet.applyBatches(w, "s" .. i, { { seq = 1, earned = 1 } }, 1)
			end
			T.expectEqual(#w.writes, Wallet.MAX_WRITE_MARKS)
			T.expectEqual(w.writes[#w.writes].session, "s" .. (Wallet.MAX_WRITE_MARKS + 3))
			T.expectEqual(w.earned, Wallet.MAX_WRITE_MARKS + 3)
			local source = wallet(5)
			Wallet.applyBatches(source, "a", { { seq = 1, earned = 1 } }, 1)
			T.expectEqual(source.earned, 5, "pure")
			T.expectEqual(#source.writes, 0, "pure")
		end)
	end)

	T.describe("WalletRules : débit", function()
		T.it("débite les achetés d'abord, puis les gagnés", function()
			local w = Wallet.debit(wallet(100, 30), 50)
			assert(w)
			T.expectEqual(w.purchased, 0)
			T.expectEqual(w.earned, 80)
			local onlyPurchased = Wallet.debit(wallet(100, 30), 20)
			assert(onlyPurchased)
			T.expectEqual(onlyPurchased.purchased, 10)
			T.expectEqual(onlyPurchased.earned, 100)
		end)

		T.it("refuse un solde insuffisant ou un montant invalide, sans rien changer", function()
			local source = wallet(40, 10)
			local w, reason = Wallet.debit(source, 51)
			T.expectEqual(w, nil)
			T.expectEqual(reason, "insufficient")
			local _, invalid = Wallet.debit(source, -5)
			T.expectEqual(invalid, "invalid")
			T.expectEqual(Wallet.balance(source), 50)
			local exact = Wallet.debit(source, 50)
			assert(exact)
			T.expectEqual(Wallet.balance(exact), 0, "jamais négatif")
		end)
	end)

	T.describe("WalletRules : attribut et affichage", function()
		T.it("décode l'attribut : nil s'il est absent ou invalide", function()
			T.expectEqual(Wallet.decode(250), 250)
			T.expectEqual(Wallet.decode(0), 0)
			T.expectEqual(Wallet.decode(nil), nil)
			T.expectEqual(Wallet.decode(-1), nil)
			T.expectEqual(Wallet.decode("250"), nil)
		end)

		T.it("groupe les chiffres par trois", function()
			T.expectEqual(Wallet.format(0), "0")
			T.expectEqual(Wallet.format(500), "500")
			T.expectEqual(Wallet.format(1500), "1 500")
			T.expectEqual(Wallet.format(12500), "12 500")
			T.expectEqual(Wallet.format(999999), "999 999")
			T.expectEqual(Wallet.format(Wallet.MAX_BALANCE), "999 999 999")
			T.expectEqual(Wallet.format(nil), "—")
		end)
	end)
end

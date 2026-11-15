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

	T.describe("WalletRules : plafond du jour dans la fusion (#394)", function()
		local DAY = 20407

		-- Cette méthode permet de construire un lot de gains en jouant d'un jour lorsqu'un test simule une session.
		local function play(seq: number, capped: number, day: number?)
			return { seq = seq, earned = 0, capped = capped, day = day or DAY }
		end

		T.it("compte les gains en jouant du jour et plafonne à 250", function()
			local w = Wallet.applyBatches(wallet(0), "a", { play(1, 40) }, 1)
			T.expectEqual(w.earned, 40)
			T.expectEqual(w.day, DAY)
			T.expectEqual(w.dayEarned, 40)
			w.dayEarned = 240
			local capped = Wallet.applyBatches(w, "a", { play(2, 60) }, 2)
			T.expectEqual(capped.earned, 50, "10 seulement sous le plafond")
			T.expectEqual(capped.dayEarned, 250)
		end)

		T.it("deux serveurs au plafond en même temps ne le dépassent pas", function()
			-- Chacun a vu 200 et crédité 50 de son côté
			local stored = wallet(200)
			stored.day = DAY
			stored.dayEarned = 200
			local a = Wallet.applyBatches(stored, "a", { play(1, 50) }, 1)
			local b = Wallet.applyBatches(a, "b", { play(1, 50) }, 1)
			T.expectEqual(b.dayEarned, 250)
			T.expectEqual(b.earned, 250, "le second serveur n'ajoute rien")
		end)

		T.it("un nouveau jour UTC remet le compteur à zéro", function()
			local stored = wallet(500)
			stored.day = DAY
			stored.dayEarned = 250
			local w = Wallet.applyBatches(stored, "a", { play(1, 60, DAY + 1) }, 1)
			T.expectEqual(w.day, DAY + 1)
			T.expectEqual(w.dayEarned, 60)
			T.expectEqual(w.earned, 560)
		end)

		T.it("lots de part et d'autre de minuit : chacun compté dans son jour", function()
			local stored = wallet(0)
			stored.day = DAY
			stored.dayEarned = 230
			local w = Wallet.applyBatches(stored, "a", { play(1, 40, DAY), play(2, 30, DAY + 1) }, 2)
			T.expectEqual(w.earned, 20 + 30, "20 sous le plafond de la veille, 30 le lendemain")
			T.expectEqual(w.day, DAY + 1)
			T.expectEqual(w.dayEarned, 30)
		end)

		T.it("lot en retard d'un jour déjà dépassé : rien de crédité, jour stocké intact", function()
			local stored = wallet(100)
			stored.day = DAY + 1
			stored.dayEarned = 70
			local w = Wallet.applyBatches(stored, "a", { play(1, 25, DAY) }, 1)
			T.expectEqual(w.earned, 100, "le plafond de la veille ne peut plus être vérifié")
			T.expectEqual(Wallet.appliedSeq(w, "a"), 1, "lot marqué appliqué, pas renvoyé")
			T.expectEqual(w.day, DAY + 1)
			T.expectEqual(w.dayEarned, 70)
		end)

		T.it("crédits hors plafond (lot d'avant #394, remboursement) : jamais plafonnés", function()
			local stored = wallet(0)
			stored.day = DAY
			stored.dayEarned = 250
			local w = Wallet.applyBatches(stored, "a", { { seq = 1, earned = 300 } }, 1)
			T.expectEqual(w.earned, 300)
			T.expectEqual(w.dayEarned, 250)
			local mixed = Wallet.applyBatches(stored, "b", { { seq = 1, earned = 20, capped = 15, day = DAY } }, 1)
			T.expectEqual(mixed.earned, 20, "seule la part plafonnée est retenue au plafond")
		end)

		T.it("un lot rejoué ne recompte pas les gains du jour", function()
			local first = Wallet.applyBatches(wallet(0), "a", { play(1, 40) }, 1)
			local again = Wallet.applyBatches(first, "a", { play(1, 40) }, 1)
			T.expectEqual(again.dayEarned, 40)
			T.expectEqual(again.earned, 40)
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

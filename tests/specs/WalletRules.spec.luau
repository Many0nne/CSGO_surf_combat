-- WalletRules (#391) : montants valides, chargement tolérant, fusion des écarts (lots numérotés, plancher à 0, plafond),
-- attribut du Player et affichage du solde.
return function(T, Loader)
	local Wallet = Loader.new({}):require("src/shared/WalletRules")

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

	T.describe("WalletRules : chargement", function()
		T.it("nouveau joueur : solde de départ, écriture permise", function()
			local balance, canSave = Wallet.loadOutcome(true, nil)
			T.expectEqual(balance, Wallet.STARTING_BALANCE)
			T.expect(canSave)
		end)

		T.it("relit le solde stocké", function()
			local balance, canSave = Wallet.loadOutcome(true, { schemaVersion = 1, credits = 1200 })
			T.expectEqual(balance, 1200)
			T.expect(canSave)
		end)

		T.it("lecture en échec, format inconnu ou plus récent : départ et sauvegarde coupée", function()
			for _, case in
				{
					{ ok = false, data = nil },
					{ ok = true, data = "texte" },
					{ ok = true, data = { schemaVersion = 1 } },
					{ ok = true, data = { schemaVersion = 1, credits = -3 } },
					{ ok = true, data = { schemaVersion = 2, credits = 10 } },
					{ ok = true, data = { schemaVersion = 1, credits = 10, writes = "x" } },
				}
			do
				local balance, canSave = Wallet.loadOutcome(case.ok, case.data)
				T.expectEqual(balance, Wallet.STARTING_BALANCE)
				T.expect(not canSave)
			end
		end)
	end)

	T.describe("WalletRules : fusion", function()
		T.it("ajoute un écart au solde stocké et retient le lot", function()
			local payload, status = Wallet.mergeForSave(
				{ schemaVersion = 1, credits = 100, extra = "gardé" },
				{ session = "a", seq = 1, delta = 50 }
			)
			T.expectEqual(status, "merged")
			T.expectEqual(payload.credits, 150)
			T.expectEqual(payload.extra, "gardé", "champ inconnu recopié")
			T.expectEqual(#payload.writes, 1)
		end)

		T.it("crée l'enregistrement d'un nouveau joueur", function()
			local payload, status = Wallet.mergeForSave(nil, { session = "a", seq = 1, delta = 30 })
			T.expectEqual(status, "merged")
			T.expectEqual(payload.credits, 30)
			T.expectEqual(payload.schemaVersion, Wallet.SCHEMA_VERSION)
		end)

		T.it("ne compte pas deux fois un lot renvoyé", function()
			local first = Wallet.mergeForSave(
				{ schemaVersion = 1, credits = 0 },
				{ session = "a", seq = 1, delta = 40 }
			)
			local again, status = Wallet.mergeForSave(first, { session = "a", seq = 1, delta = 40 })
			T.expectEqual(again, nil)
			T.expectEqual(status, "applied")
			local nextOne = Wallet.mergeForSave(first, { session = "a", seq = 2, delta = 10 })
			T.expectEqual(nextOne.credits, 50)
		end)

		T.it("additionne les écarts de deux sessions", function()
			local a = Wallet.mergeForSave({ schemaVersion = 1, credits = 100 }, { session = "a", seq = 1, delta = -60 })
			local b = Wallet.mergeForSave(a, { session = "b", seq = 1, delta = 25 })
			T.expectEqual(b.credits, 65)
			T.expectEqual(#b.writes, 2)
		end)

		T.it("ne descend jamais sous 0 ni au-dessus du plafond", function()
			local low = Wallet.mergeForSave(
				{ schemaVersion = 1, credits = 30 },
				{ session = "a", seq = 1, delta = -80 }
			)
			T.expectEqual(low.credits, 0)
			local high = Wallet.mergeForSave(
				{ schemaVersion = 1, credits = Wallet.MAX_BALANCE - 1 },
				{ session = "a", seq = 1, delta = 10 }
			)
			T.expectEqual(high.credits, Wallet.MAX_BALANCE)
		end)

		T.it("ne touche pas un format refusé", function()
			local payload, status = Wallet.mergeForSave({ schemaVersion = 9, credits = 5 }, {
				session = "a",
				seq = 1,
				delta = 1,
			})
			T.expectEqual(payload, nil)
			T.expectEqual(status, "refused")
		end)

		T.it("ne retient que les dernières sessions", function()
			local record = { schemaVersion = 1, credits = 0 }
			for i = 1, Wallet.MAX_WRITE_MARKS + 3 do
				record = Wallet.mergeForSave(record, { session = "s" .. i, seq = 1, delta = 1 })
			end
			T.expectEqual(#record.writes, Wallet.MAX_WRITE_MARKS)
			T.expectEqual(record.writes[#record.writes].session, "s" .. (Wallet.MAX_WRITE_MARKS + 3))
			T.expectEqual(record.credits, Wallet.MAX_WRITE_MARKS + 3)
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

-- Suivi de l'achat de pack en cours (#409) : un seul prompt à la fois, délai de secours sans second prompt, fin tardive
-- d'un ancien prompt sans effet sur un achat plus récent.
return function(T, Loader)
	local Guard = Loader.new({}):require("src/shared/PurchaseGuard")

	T.describe("PurchaseGuard", function()
		T.it("un achat à la fois : un second clic est refusé tant que le premier court", function()
			local s = Guard.new()
			T.expectEqual(Guard.start(s, 10), 1)
			T.expectEqual(Guard.start(s, 11), nil)
			T.expect(s.active, "achat en cours")
		end)

		T.it("délai avec prompt ouvert : l'achat reste en cours, pas de second prompt", function()
			local s = Guard.new()
			local id = Guard.start(s, 10) :: number
			Guard.promptOpened(s, id)
			T.expect(not Guard.timedOut(s, id), "le délai ne termine pas un prompt ouvert")
			T.expectEqual(Guard.start(s, 10), nil, "pas de second prompt par-dessus")
			T.expect(Guard.finished(s, 10), "la fin du prompt termine l'achat")
			T.expectEqual(Guard.start(s, 10), 2)
		end)

		T.it("dernier délai : termine même un prompt ouvert dont la fin n'est jamais arrivée", function()
			local s = Guard.new()
			local id = Guard.start(s, 10) :: number
			Guard.promptOpened(s, id)
			T.expect(not Guard.timedOut(s, id))
			T.expect(Guard.timedOut(s, id, true), "dernier recours")
			T.expectEqual(Guard.start(s, 10), 2)
			T.expect(not Guard.timedOut(s, id, true), "ancien dernier délai sans effet sur l'achat suivant")
		end)

		T.it("délai sans réponse du serveur : l'achat se termine (secours)", function()
			local s = Guard.new()
			local id = Guard.start(s, 10) :: number
			T.expect(Guard.timedOut(s, id), "secours")
			T.expectEqual(Guard.start(s, 10), 2)
		end)

		T.it("fin avant le délai : le délai tardif n'a plus d'effet sur l'achat suivant", function()
			local s = Guard.new()
			local first = Guard.start(s, 10) :: number
			Guard.promptOpened(s, first)
			T.expect(Guard.finished(s, 10))
			local second = Guard.start(s, 10) :: number
			T.expect(not Guard.timedOut(s, first), "le délai du premier achat ne termine pas le second")
			T.expect(s.active, "le second court toujours")
			T.expect(Guard.timedOut(s, second), "son propre délai le termine (prompt pas ouvert)")
		end)

		T.it("ok tardif d'un achat passé : ne marque pas le prompt du suivant comme ouvert", function()
			local s = Guard.new()
			local first = Guard.start(s, 10) :: number
			T.expect(Guard.timedOut(s, first))
			local second = Guard.start(s, 10) :: number
			Guard.promptOpened(s, first)
			T.expect(not s.promptOpen, "ancien id ignoré")
			T.expect(Guard.timedOut(s, second))
		end)

		T.it("fin d'un autre produit ou sans achat : ignorée", function()
			local s = Guard.new()
			T.expect(not Guard.finished(s, 10), "aucun achat")
			Guard.start(s, 10)
			T.expect(not Guard.finished(s, 11), "autre produit")
			T.expect(s.active)
		end)

		T.it("refus du serveur : termine l'achat courant, pas un ancien", function()
			local s = Guard.new()
			local first = Guard.start(s, 10) :: number
			T.expect(Guard.refused(s, first))
			local second = Guard.start(s, 10) :: number
			T.expect(not Guard.refused(s, first), "refus tardif d'un ancien achat")
			T.expect(s.active)
			T.expect(Guard.refused(s, second))
		end)
	end)
end

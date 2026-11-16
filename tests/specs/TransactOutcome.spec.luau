-- Traduction de l'issue de `InventoryStore.transact` en motif d'achat (#410) : ok, refus (solde ou autre), chargement, échec.
return function(T, Loader)
	local Outcome = Loader.new({}):require("src/server/TransactOutcome")

	T.describe("TransactOutcome.translate", function()
		T.it("ok : écrit", function()
			T.expectEqual(Outcome.translate("ok", { duplicate = false }), "ok")
			T.expectEqual(Outcome.translate("ok", nil), "ok")
		end)

		T.it("rejected + insufficient : solde insuffisant", function()
			T.expectEqual(Outcome.translate("rejected", "insufficient"), "insufficient")
		end)

		T.it("rejected + autre motif : échec (bug serveur)", function()
			T.expectEqual(Outcome.translate("rejected", "invalid"), "failed")
			T.expectEqual(Outcome.translate("rejected", "error"), "failed")
			T.expectEqual(Outcome.translate("rejected", nil), "failed")
		end)

		T.it("loading : chargement", function()
			T.expectEqual(Outcome.translate("loading", nil), "loading")
		end)

		T.it("failed ou issue inconnue : échec", function()
			T.expectEqual(Outcome.translate("failed", nil), "failed")
			T.expectEqual(Outcome.translate("autre", nil), "failed")
		end)
	end)
end

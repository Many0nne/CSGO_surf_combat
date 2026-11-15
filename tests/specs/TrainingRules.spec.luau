-- Mode entraînement (#345) : serveur reconnu, code d'accès partagé, échecs retentés, décision d'une demande, messages.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/TrainingRules")

	T.describe("TrainingRules.isTrainingServer", function()
		T.it("reconnaît un serveur réservé (identifiant privé, sans propriétaire)", function()
			T.expectEqual(Rules.isTrainingServer("abc", 0, false, nil), true)
		end)

		T.it("écarte un serveur public et un serveur privé payant", function()
			T.expectEqual(Rules.isTrainingServer("", 0, false, nil), false, "public")
			T.expectEqual(Rules.isTrainingServer("abc", 42, false, nil), false, "serveur privé d'un joueur")
		end)

		T.it("suit DebugTraining dans Studio seulement", function()
			T.expectEqual(Rules.isTrainingServer("", 0, true, true), true)
			T.expectEqual(Rules.isTrainingServer("", 0, true, "oui"), false, "pas un booléen")
			T.expectEqual(Rules.isTrainingServer("", 0, false, true), false, "jeu publié")
		end)
	end)

	T.describe("TrainingRules.keepCode", function()
		T.it("garde le code déjà partagé, sinon prend le candidat", function()
			T.expectEqual(Rules.keepCode("ancien", "neuf"), "ancien")
			T.expectEqual(Rules.keepCode(nil, "neuf"), "neuf")
			T.expectEqual(Rules.keepCode("", "neuf"), "neuf")
			T.expectEqual(Rules.keepCode(12, "neuf"), "neuf", "valeur abîmée")
		end)
	end)

	T.describe("TrainingRules.rotateCode", function()
		T.it("remplace le code qui a échoué", function()
			T.expectEqual(Rules.rotateCode("plein", "plein", "neuf"), "neuf")
			T.expectEqual(Rules.rotateCode(nil, "plein", "neuf"), "neuf", "entrée expirée")
		end)

		T.it("garde un code déjà remplacé par un autre serveur", function()
			T.expectEqual(Rules.rotateCode("autre", "plein", "neuf"), "autre")
		end)
	end)

	T.describe("TrainingRules.retriesWithFreshCode", function()
		T.it("retente une fois un serveur plein ou introuvable", function()
			T.expectEqual(Rules.retriesWithFreshCode("GameFull", 1), true)
			T.expectEqual(Rules.retriesWithFreshCode("GameNotFound", 1), true)
			T.expectEqual(Rules.retriesWithFreshCode("GameFull", Rules.MAX_TRIES), false, "dernier essai")
		end)

		T.it("ne retente pas les autres échecs", function()
			for _, name in { "Failure", "Flooded", "Unauthorized", "IsTeleporting", "GameEnded" } do
				T.expectEqual(Rules.retriesWithFreshCode(name, 1), false, name)
			end
		end)
	end)

	T.describe("TrainingRules.readRequest", function()
		T.it("ne lit que join et leave", function()
			T.expectEqual(Rules.readRequest("join"), "join")
			T.expectEqual(Rules.readRequest("leave"), "leave")
			T.expectEqual(Rules.readRequest("autre"), nil)
			T.expectEqual(Rules.readRequest(nil), nil)
		end)
	end)

	T.describe("TrainingRules.decide", function()
		T.it("téléporte vers l'entraînement depuis la partie, et de l'entraînement vers la partie", function()
			T.expectEqual(Rules.decide("join", false, false, false), "teleport")
			T.expectEqual(Rules.decide("leave", true, false, false), "teleport")
		end)

		T.it("refuse une demande sans objet", function()
			T.expectEqual(Rules.decide("join", true, false, false), "unavailable", "déjà à l'entraînement")
			T.expectEqual(Rules.decide("leave", false, false, false), "unavailable", "pas à l'entraînement")
		end)

		T.it("refuse une seconde demande pendant une téléportation", function()
			T.expectEqual(Rules.decide("join", false, false, true), "busy")
		end)

		T.it("prévient que Studio ne téléporte pas", function()
			T.expectEqual(Rules.decide("join", false, true, false), "studio")
			T.expectEqual(Rules.decide("leave", true, true, false), "studio")
		end)
	end)

	T.describe("TrainingRules.notice", function()
		T.it("a un message pour chaque réponse du serveur", function()
			for _, status in { "teleporting", "studio", "failed", "busy", "unavailable" } do
				T.expectEqual(type(Rules.notice(status)), "string", status)
			end
			T.expectEqual(Rules.notice("inconnu"), nil)
			T.expectEqual(Rules.notice(3), nil)
		end)
	end)
end

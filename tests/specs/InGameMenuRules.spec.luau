-- Menu en partie (#157) : vues, touche du menu selon l'état du jeu, choix, fermeture hors partie.
return function(T, Loader)
	local Rules = Loader.new():require("src/client/ui/InGameMenuRules")

	T.describe("InGameMenuRules.available", function()
		T.it("n'ouvre le menu qu'en partie, vivant ou en attente de réapparition", function()
			T.expectEqual(Rules.available("IN_ROUND"), true)
			T.expectEqual(Rules.available("DEAD"), true)
			for _, state in { "MENU", "INFOS", "SPAWNING", "RESULT" } do
				T.expectEqual(Rules.available(state), false, state)
			end
		end)
	end)

	T.describe("InGameMenuRules.keyTarget", function()
		T.it("donne la touche au menu en partie s'il est ouvert ou disponible", function()
			T.expectEqual(Rules.keyTarget("IN_ROUND", "closed"), "inGame")
			T.expectEqual(Rules.keyTarget("DEAD", "closed"), "inGame")
			T.expectEqual(Rules.keyTarget("RESULT", "main"), "inGame", "ouvert : la touche le ferme")
		end)

		T.it("ouvre les Réglages au menu principal, rien ailleurs", function()
			T.expectEqual(Rules.keyTarget("MENU", "closed"), "mainMenu")
			T.expectEqual(Rules.keyTarget("INFOS", "closed"), "none")
			T.expectEqual(Rules.keyTarget("SPAWNING", "closed"), "none")
			T.expectEqual(Rules.keyTarget("RESULT", "closed"), "none")
		end)
	end)

	T.describe("InGameMenuRules.onMenuKey", function()
		T.it("ouvre l'accueil du menu en partie, puis le ferme", function()
			T.expectEqual(Rules.onMenuKey("closed", "IN_ROUND"), "main")
			T.expectEqual(Rules.onMenuKey("main", "IN_ROUND"), "closed")
		end)

		T.it("ferme tout depuis les Réglages", function()
			T.expectEqual(Rules.onMenuKey("settings", "IN_ROUND"), "closed")
		end)

		T.it("reste fermé hors partie", function()
			T.expectEqual(Rules.onMenuKey("closed", "MENU"), "closed")
			T.expectEqual(Rules.onMenuKey("closed", "SPAWNING"), "closed")
		end)
	end)

	T.describe("InGameMenuRules.onChoice", function()
		T.it("REPRENDRE et MENU PRINCIPAL ferment le menu", function()
			T.expectEqual(Rules.onChoice("main", "resume"), "closed")
			T.expectEqual(Rules.onChoice("main", "leave"), "closed")
		end)

		T.it("RÉGLAGES ouvre l'écran Réglages, RETOUR revient à l'accueil du menu", function()
			T.expectEqual(Rules.onChoice("main", "settings"), "settings")
			T.expectEqual(Rules.onChoice("settings", "back"), "main")
		end)

		T.it("ignore un choix qui ne correspond pas à la vue affichée", function()
			T.expectEqual(Rules.onChoice("closed", "settings"), "closed")
			T.expectEqual(Rules.onChoice("main", "back"), "main")
			T.expectEqual(Rules.onChoice("closed", "back"), "closed")
		end)
	end)

	T.describe("InGameMenuRules.onGameState", function()
		T.it("garde le menu ouvert entre la mort et la réapparition", function()
			T.expectEqual(Rules.onGameState("main", "DEAD"), "main")
			T.expectEqual(Rules.onGameState("settings", "IN_ROUND"), "settings")
		end)

		T.it("ferme le menu hors partie (menu, résultat)", function()
			T.expectEqual(Rules.onGameState("main", "MENU"), "closed")
			T.expectEqual(Rules.onGameState("settings", "RESULT"), "closed")
		end)
	end)

	T.describe("InGameMenuRules.isOpen", function()
		T.it("couvre la partie dès que l'accueil ou les Réglages sont affichés", function()
			T.expectEqual(Rules.isOpen("closed"), false)
			T.expectEqual(Rules.isOpen("main"), true)
			T.expectEqual(Rules.isOpen("settings"), true)
		end)
	end)
end

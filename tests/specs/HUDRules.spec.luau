return function(T, Loader)
	local HUDRules = Loader.new():require("src/client/ui/HUDRules")

	T.describe("HUDRules.speedTier", function()
		T.it("place chaque vitesse dans le bon palier, seuils inclus", function()
			T.expectEqual(HUDRules.speedTier(0), 1)
			T.expectEqual(HUDRules.speedTier(29.9), 1)
			T.expectEqual(HUDRules.speedTier(30), 2)
			T.expectEqual(HUDRules.speedTier(69), 2)
			T.expectEqual(HUDRules.speedTier(70), 3)
			T.expectEqual(HUDRules.speedTier(120), 4)
			T.expectEqual(HUDRules.speedTier(180), 5)
			T.expectEqual(HUDRules.speedTier(1000), 5)
		end)
	end)

	T.describe("HUDRules.gameHudVisible", function()
		T.it("n'affiche le HUD de jeu qu'en partie avec un personnage vivant", function()
			T.expectEqual(HUDRules.gameHudVisible("IN_ROUND"), true)
			for _, state in { "MENU", "INFOS", "SPAWNING", "DEAD", "RESULT" } do
				T.expectEqual(HUDRules.gameHudVisible(state), false)
			end
		end)
	end)

	T.describe("HUDRules.acceptsRoundResult", function()
		T.it("n'accepte le résultat de round qu'en partie (vivant ou mort)", function()
			T.expectEqual(HUDRules.acceptsRoundResult("IN_ROUND"), true)
			T.expectEqual(HUDRules.acceptsRoundResult("DEAD"), true)
			for _, state in { "MENU", "INFOS", "SPAWNING", "RESULT" } do
				T.expectEqual(HUDRules.acceptsRoundResult(state), false)
			end
		end)
	end)

	T.describe("HUDRules.speedFill", function()
		T.it("remplit la ligne proportionnellement, pleine au dernier palier, bornée à 0 et 1", function()
			T.expectEqual(HUDRules.speedFill(0), 0)
			T.expectEqual(HUDRules.speedFill(90), 0.5)
			T.expectEqual(HUDRules.speedFill(180), 1)
			T.expectEqual(HUDRules.speedFill(1000), 1)
			T.expectEqual(HUDRules.speedFill(-5), 0)
		end)
	end)

	T.describe("HUDRules.formatTimer", function()
		T.it("formate en m:ss et borne à zéro", function()
			T.expectEqual(HUDRules.formatTimer(300), "5:00")
			T.expectEqual(HUDRules.formatTimer(65), "1:05")
			T.expectEqual(HUDRules.formatTimer(9.7), "0:09")
			T.expectEqual(HUDRules.formatTimer(-3), "0:00")
		end)

		T.it("passe en alerte à 30 s et moins", function()
			T.expectEqual(HUDRules.isLowTime(31), false)
			T.expectEqual(HUDRules.isLowTime(30), true)
		end)
	end)

	T.describe("HUDRules.sortScores / rankOf", function()
		local scores = {
			[1] = { name = "manyonne", kills = 0, deaths = 3 },
			[2] = { name = "Specter", kills = 3, deaths = 2 },
			[3] = { name = "Ramsey", kills = 3, deaths = 1 },
			[4] = { name = "Volkov", kills = 3, deaths = 2 },
		}

		T.it("trie par kills, puis morts, puis nom", function()
			local sorted = HUDRules.sortScores(scores)
			T.expectEqual(sorted[1].name, "Ramsey")
			T.expectEqual(sorted[2].name, "Specter")
			T.expectEqual(sorted[3].name, "Volkov")
			T.expectEqual(sorted[4].name, "manyonne")
		end)

		T.it("retrouve le rang du joueur local, nil s'il est absent", function()
			local sorted = HUDRules.sortScores(scores)
			T.expectEqual(HUDRules.rankOf(sorted, "manyonne"), 4)
			T.expectEqual(HUDRules.rankOf(sorted, "Inconnu"), nil)
		end)
	end)

	T.describe("HUDRules.formatKD / secondsLeft", function()
		T.it("calcule le K/D sans division par zéro", function()
			T.expectEqual(HUDRules.formatKD(3, 2), "1.50")
			T.expectEqual(HUDRules.formatKD(1, 0), "1.00")
			T.expectEqual(HUDRules.formatKD(0, 3), "0.00")
		end)

		T.it("arrondit le compte à rebours à la seconde supérieure", function()
			T.expectEqual(HUDRules.secondsLeft(12.5, 10), 3)
			T.expectEqual(HUDRules.secondsLeft(12, 10), 2)
			T.expectEqual(HUDRules.secondsLeft(10, 12), 0)
		end)
	end)

	T.describe("HUDRules.cycleSlot", function()
		T.it("passe à l'emplacement voisin en bouclant dans les deux sens", function()
			T.expectEqual(HUDRules.cycleSlot(1, 3, 1), 2)
			T.expectEqual(HUDRules.cycleSlot(3, 3, 1), 1)
			T.expectEqual(HUDRules.cycleSlot(1, 3, -1), 3)
			T.expectEqual(HUDRules.cycleSlot(2, 2, -1), 1)
		end)

		T.it("part d'un bout sans arme en main, et ne renvoie rien sans arme", function()
			T.expectEqual(HUDRules.cycleSlot(nil, 3, 1), 1)
			T.expectEqual(HUDRules.cycleSlot(nil, 3, -1), 3)
			T.expectEqual(HUDRules.cycleSlot(nil, 0, 1), nil)
			T.expectEqual(HUDRules.cycleSlot(1, 0, -1), nil)
		end)
	end)

	T.describe("HUDRules.weaponLabel", function()
		T.it("sépare les mots collés et passe en majuscules", function()
			T.expectEqual(HUDRules.weaponLabel("M9Bayonet"), "M9 BAYONET")
			T.expectEqual(HUDRules.weaponLabel("AWP"), "AWP")
			T.expectEqual(HUDRules.weaponLabel("DesertEagle"), "DESERT EAGLE")
		end)
	end)

	T.describe("HUDRules.slotOrder", function()
		T.it("trie par ordre alphabétique sans modifier la liste reçue", function()
			local names = { "M9Bayonet", "AWP" }
			local sorted = HUDRules.slotOrder(names)
			T.expectEqual(sorted[1], "AWP")
			T.expectEqual(sorted[2], "M9Bayonet")
			T.expectEqual(names[1], "M9Bayonet")
		end)
	end)
end

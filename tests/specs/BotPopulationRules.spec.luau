-- Règles de population des bots (#144) : nombre voulu, bot à retirer, commande de debug.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/BotPopulationRules")
	local Config = Loader.new():require("src/shared/BotConfig")

	local function candidate(index: number, alive: boolean, inDuel: boolean, sinceContact: number)
		return { index = index, alive = alive, inDuel = inDuel, sinceContact = sinceContact }
	end

	T.describe("BotPopulationRules.wantedBots", function()
		T.it("comble jusqu'à la population cible, plafonné à MAX_BOTS", function()
			T.expectEqual(Rules.wantedBots(1), math.min(Config.TARGET_POPULATION - 1, Config.MAX_BOTS))
			T.expectEqual(Rules.wantedBots(2), Config.TARGET_POPULATION - 2)
			T.expectEqual(Rules.wantedBots(Config.TARGET_POPULATION), 0)
			T.expectEqual(Rules.wantedBots(Config.TARGET_POPULATION + 3), 0)
		end)

		T.it("un joueur seul a MAX_BOTS adversaires, un de moins à chaque arrivée", function()
			T.expectEqual(Rules.wantedBots(1), Config.MAX_BOTS)
			T.expectEqual(Rules.wantedBots(2), Config.MAX_BOTS - 1)
		end)

		T.it("aucun bot sans joueur ni pendant la pause", function()
			T.expectEqual(Rules.wantedBots(0), 0)
			T.expectEqual(Rules.wantedBots(-1), 0)
			T.expectEqual(Rules.wantedBots(1, true), 0, "pause de DebugPlaytest")
		end)
	end)

	T.describe("BotPopulationRules.pickRemoval", function()
		T.it("retire d'abord un bot hors du jeu", function()
			local list =
				{ candidate(1, true, false, 30), candidate(2, false, false, math.huge), candidate(3, true, false, 90) }
			T.expectEqual(Rules.pickRemoval(list), 2)
		end)

		T.it("sinon retire le vivant le plus loin du combat", function()
			local list = { candidate(1, true, false, 10), candidate(2, true, false, 90), candidate(3, true, false, 40) }
			T.expectEqual(Rules.pickRemoval(list), 2)
		end)

		T.it("ne retire jamais un bot en plein duel", function()
			local list = { candidate(1, true, true, 0), candidate(2, true, false, 5), candidate(3, true, true, 1) }
			T.expectEqual(Rules.pickRemoval(list), 2)
		end)

		T.it("diffère le retrait quand tous les bots sont en duel", function()
			local list = { candidate(1, true, true, 0), candidate(2, true, true, 1) }
			T.expectEqual(Rules.pickRemoval(list), nil)
		end)

		T.it("forcé : préfère un bot hors combat, puis le duel le plus ancien", function()
			local list = { candidate(1, true, true, 1), candidate(2, true, true, 3) }
			T.expectEqual(Rules.pickRemoval(list, true), 1, "égalité de rang : le premier")
			local mixed = { candidate(1, true, true, 3), candidate(2, true, false, 20) }
			T.expectEqual(Rules.pickRemoval(mixed, true), 2)
		end)

		T.it("ne renvoie rien sans bot", function()
			T.expectEqual(Rules.pickRemoval({}), nil)
		end)
	end)

	T.describe("BotPopulationRules.isInDuel", function()
		T.it("combat ou contact récent", function()
			T.expectEqual(Rules.isInDuel("combattre", math.huge), true)
			T.expectEqual(Rules.isInDuel("chercher", Config.POPULATION_DUEL_TIME - 0.1), true)
			T.expectEqual(Rules.isInDuel("chercher", Config.POPULATION_DUEL_TIME + 0.1), false)
			T.expectEqual(Rules.isInDuel("enqueter", math.huge), false)
		end)
	end)

	T.describe("BotPopulationRules.debugCommand", function()
		T.it("un nombre fixe le nombre de bots, borné", function()
			T.expectEqual(Rules.debugCommand(2.7, 0), 2)
			T.expectEqual(Rules.debugCommand(0, 3), 0)
			T.expectEqual(Rules.debugCommand(-1, 3), 0)
			T.expectEqual(Rules.debugCommand(99, 0), Config.MAX_BOTS)
		end)

		T.it("+ et - ajoutent ou retirent un bot, bornés", function()
			T.expectEqual(Rules.debugCommand("+", 2), 3)
			T.expectEqual(Rules.debugCommand("-", 2), 1)
			T.expectEqual(Rules.debugCommand("+", Config.MAX_BOTS), Config.MAX_BOTS)
			T.expectEqual(Rules.debugCommand("-", 0), 0)
		end)

		T.it("le reste revient à la population automatique", function()
			T.expectEqual(Rules.debugCommand(nil, 2), nil)
			T.expectEqual(Rules.debugCommand("auto", 2), nil)
			T.expectEqual(Rules.debugCommand("3", 2), nil)
			T.expectEqual(Rules.debugCommand(0 / 0, 2), nil, "NaN")
			T.expectEqual(Rules.debugCommand(true, 2), nil)
		end)
	end)
end

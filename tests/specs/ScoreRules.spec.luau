-- Ordre des scores et issue d'une manche (#295), partagés par le serveur (vainqueur) et le HUD (classement, écran de fin).
return function(T, Loader)
	local ScoreRules = Loader.new():require("src/shared/ScoreRules")

	-- Cette méthode permet de composer un score lorsqu'un test décrit une manche.
	local function score(id: number, kills: number, deaths: number)
		return { id = id, name = "P" .. id, isBot = id < 0, kills = kills, deaths = deaths }
	end

	-- Cette méthode permet de lister toutes les permutations d'une liste lorsqu'un test vérifie que l'ordre ne compte pas.
	local function permutations(list)
		if #list <= 1 then
			return { table.clone(list) }
		end
		local result = {}
		for i, item in list do
			local rest = table.clone(list)
			table.remove(rest, i)
			for _, perm in permutations(rest) do
				table.insert(perm, 1, item)
				table.insert(result, perm)
			end
		end
		return result
	end

	T.describe("ScoreRules.compare", function()
		T.it("place devant le plus de kills, puis le moins de morts", function()
			T.expect(ScoreRules.compare(score(1, 3, 5), score(2, 2, 0)) < 0, "plus de kills")
			T.expect(ScoreRules.compare(score(1, 2, 1), score(2, 2, 0)) > 0, "plus de morts")
			T.expectEqual(ScoreRules.compare(score(1, 2, 1), score(2, 2, 1)), 0, "égalité parfaite")
		end)
	end)

	T.describe("ScoreRules.outcome", function()
		T.it("désigne le premier par son id, un bot compris", function()
			local outcome, id = ScoreRules.outcome({ score(1, 1, 2), score(-1, 4, 3), score(2, 0, 0) })
			T.expectEqual(outcome, "winner")
			T.expectEqual(id, -1)
		end)

		T.it("départage une égalité de kills aux morts", function()
			local outcome, id = ScoreRules.outcome({ score(1, 2, 3), score(2, 2, 1) })
			T.expectEqual(outcome, "winner")
			T.expectEqual(id, 2)
		end)

		T.it("ne désigne personne à égalité parfaite en tête", function()
			local outcome, id = ScoreRules.outcome({ score(1, 2, 1), score(2, 2, 1), score(3, 1, 0) })
			T.expectEqual(outcome, "tie")
			T.expectEqual(id, nil)
		end)

		T.it("ne désigne personne sans kill, même avec des morts différentes", function()
			T.expectEqual((ScoreRules.outcome({ score(1, 0, 0), score(2, 0, 3) })), "none")
			T.expectEqual((ScoreRules.outcome({})), "none", "aucun participant")
		end)

		T.it("ne dépend jamais de l'ordre de la liste", function()
			local cases = {
				{ list = { score(1, 2, 1), score(2, 2, 1), score(3, 5, 4) }, outcome = "winner", id = 3 },
				{ list = { score(1, 2, 1), score(2, 2, 1), score(3, 1, 0) }, outcome = "tie" },
				{ list = { score(1, 2, 2), score(2, 2, 1), score(-1, 2, 3) }, outcome = "winner", id = 2 },
				{ list = { score(1, 0, 0), score(2, 0, 1), score(-1, 0, 0) }, outcome = "none" },
			}
			for c, case in cases do
				for _, perm in permutations(case.list) do
					local outcome, id = ScoreRules.outcome(perm)
					T.expectEqual(outcome, case.outcome, "cas " .. c)
					T.expectEqual(id, case.id, "cas " .. c)
				end
			end
		end)
	end)
end

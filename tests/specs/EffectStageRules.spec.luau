return function(T, Loader)
	local Rules = Loader.new():require("src/client/systems/game/EffectStageRules")
	local FIRST_SHOT = Rules.FIRST_SHOT
	local THIRD_SHOT = Rules.FIRST_LENGTH + Rules.THIRD_SHOT

	T.describe("EffectStageRules.viewAt", function()
		T.it("commence par le plan du tireur, puis passe au plan de côté", function()
			T.expectEqual(Rules.viewAt(0), "first")
			T.expectEqual(Rules.viewAt(Rules.FIRST_LENGTH - 0.01), "first")
			T.expectEqual(Rules.viewAt(Rules.FIRST_LENGTH), "third")
			T.expectEqual(Rules.viewAt(Rules.LOOP - 0.01), "third")
		end)

		T.it("recommence la boucle", function()
			T.expectEqual(Rules.viewAt(Rules.LOOP), "first")
			T.expectEqual(Rules.viewAt(Rules.LOOP * 3 + Rules.FIRST_LENGTH + 0.1), "third")
		end)
	end)

	T.describe("EffectStageRules.shotBetween", function()
		T.it("tire une fois par plan, dans le plan à l'écran", function()
			T.expectEqual(Rules.shotBetween(0, FIRST_SHOT - 0.01), nil)
			T.expectEqual(Rules.shotBetween(FIRST_SHOT - 0.01, FIRST_SHOT), "first")
			T.expectEqual(Rules.shotBetween(FIRST_SHOT, FIRST_SHOT + 0.5), nil)
			T.expectEqual(Rules.shotBetween(THIRD_SHOT - 0.02, THIRD_SHOT + 0.01), "third")
			T.expectEqual(Rules.viewAt(THIRD_SHOT), "third")
			T.expectEqual(Rules.viewAt(FIRST_SHOT), "first")
		end)

		T.it("retrouve les tirs aux tours suivants de la boucle", function()
			local t = Rules.LOOP * 2 + FIRST_SHOT
			T.expectEqual(Rules.shotBetween(t - 0.016, t + 0.001), "first")
			local u = Rules.LOOP * 5 + THIRD_SHOT
			T.expectEqual(Rules.shotBetween(u - 0.016, u), "third")
		end)

		T.it("ne tire pas sans temps écoulé, et au tout début", function()
			T.expectEqual(Rules.shotBetween(1, 1), nil)
			T.expectEqual(Rules.shotBetween(2, 1), nil)
			T.expectEqual(Rules.shotBetween(0, 0.016), nil)
		end)

		T.it("ne rend que le dernier tir franchi par une image longue", function()
			T.expectEqual(Rules.shotBetween(0, THIRD_SHOT + 0.1), "third")
		end)
	end)
end

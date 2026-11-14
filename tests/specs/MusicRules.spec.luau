return function(T, Loader)
	local MusicRules = Loader.new():require("src/client/systems/audio/MusicRules")
	local LEVEL = MusicRules.LEVEL

	T.describe("MusicRules.targetLevel", function()
		T.it("se tait quand le réglage est coupé, même au menu", function()
			T.expectEqual(MusicRules.targetLevel(false, "MENU", nil), 0)
			T.expectEqual(MusicRules.targetLevel(false, "IN_ROUND", 0), 0)
		end)

		T.it("joue à plein dans les écrans du menu, combat récent ou non", function()
			for _, state in { "MENU", "INFOS" } do
				T.expectEqual(MusicRules.targetLevel(true, state, nil), LEVEL.menu)
				T.expectEqual(MusicRules.targetLevel(true, state, 0), LEVEL.menu)
			end
			T.expectEqual(MusicRules.targetLevel(true, nil, nil), LEVEL.menu) -- avant le premier état
		end)

		T.it("s'atténue en partie, et encore plus pendant un combat", function()
			for _, state in { "SPAWNING", "IN_ROUND", "DEAD", "RESULT" } do
				T.expectEqual(MusicRules.targetLevel(true, state, nil), LEVEL.round)
			end
			T.expectEqual(MusicRules.targetLevel(true, "IN_ROUND", 0), LEVEL.combat)
			T.expectEqual(MusicRules.targetLevel(true, "IN_ROUND", MusicRules.COMBAT_HOLD - 0.01), LEVEL.combat)
			T.expectEqual(MusicRules.targetLevel(true, "IN_ROUND", MusicRules.COMBAT_HOLD), LEVEL.round)
			T.expect(LEVEL.combat < LEVEL.round and LEVEL.round < LEVEL.menu, "menu > partie > combat")
		end)
	end)

	T.describe("MusicRules.step", function()
		T.it("baisse vite et remonte lentement, sans dépasser la cible", function()
			T.expectNear(MusicRules.step(1, 0, MusicRules.FADE_DOWN / 2), 0.5)
			T.expectNear(MusicRules.step(0, 1, MusicRules.FADE_UP / 2), 0.5)
			T.expectEqual(MusicRules.step(1, 0.35, 10), 0.35)
			T.expectEqual(MusicRules.step(0.12, 0.35, 10), 0.35)
			T.expectEqual(MusicRules.step(0.35, 0.35, 0.016), 0.35)
		end)
	end)

	T.describe("MusicRules.isNearShot", function()
		T.it("compte un tir dans le rayon, ignore un tir lointain ou une origine invalide", function()
			local here = Vector3.new(0, 0, 0)
			T.expectEqual(MusicRules.isNearShot(here, Vector3.new(MusicRules.COMBAT_RADIUS - 1, 0, 0)), true)
			T.expectEqual(MusicRules.isNearShot(here, Vector3.new(MusicRules.COMBAT_RADIUS + 1, 0, 0)), false)
			T.expectEqual(MusicRules.isNearShot(here, "loin"), false)
			T.expectEqual(MusicRules.isNearShot(nil, here), false)
		end)
	end)
end

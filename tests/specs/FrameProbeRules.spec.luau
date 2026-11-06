return function(T, Loader)
	local Rules = Loader.new():require("src/shared/FrameProbeRules")

	local DT = 1 / 60

	-- Cette méthode permet de construire une frame saine à 60 FPS et 16 studs/s lorsqu'un test n'en change qu'une partie.
	local function sample(over)
		local s = { dt = DT, simDt = DT, steps = 1, disp = 16 * DT, simSpeed = 16, yawRate = 90 }
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	T.describe("FrameProbeRules.median / percentile / summarize", function()
		T.it("médiane impaire, paire et vide", function()
			T.expectEqual(Rules.median({ 3, 1, 2 }), 2)
			T.expectEqual(Rules.median({ 4, 1, 3, 2 }), 2.5)
			T.expectEqual(Rules.median({}), 0)
		end)

		T.it("résumé : FPS médian, p99 et max", function()
			local dts = table.create(99, DT)
			table.insert(dts, 0.1)
			local s = Rules.summarize(dts)
			T.expectNear(s.fps, 60, 1e-6)
			T.expectNear(s.p99Ms, DT * 1000, 1e-6)
			T.expectNear(s.maxMs, 100, 1e-6)
		end)
	end)

	T.describe("FrameProbeRules.isIsolatedOutlier", function()
		T.it("pic isolé détecté, accélération progressive ignorée", function()
			T.expect(Rules.isIsolatedOutlier(16, 30, 16, 2))
			T.expect(Rules.isIsolatedOutlier(16, 5, 16, 2))
			T.expect(not Rules.isIsolatedOutlier(14, 16, 18, 2))
		end)

		T.it("ignoré sous le seuil de référence", function()
			T.expect(not Rules.isIsolatedOutlier(0.5, 1.5, 0.5, 2))
		end)
	end)

	T.describe("FrameProbeRules.classify", function()
		T.it("frame saine : aucune anomalie", function()
			local kinds = Rules.classify(sample(), sample(), sample(), DT)
			T.expectEqual(#kinds, 0)
		end)

		T.it("frame lente : HITCH", function()
			local kinds = Rules.classify(sample(), sample({ dt = 0.05, simDt = 0.05, disp = 0.8 }), sample(), DT)
			T.expectEqual(kinds[1], "HITCH")
		end)

		T.it("téléportation : TELEPORT seul", function()
			local kinds = Rules.classify(sample(), sample({ disp = 50 }), sample(), DT)
			T.expectEqual(#kinds, 1)
			T.expectEqual(kinds[1], "TELEPORT")
		end)

		T.it("pas physique doublé : STUTTER pas_physique_double", function()
			local kinds, source =
				Rules.classify(sample(), sample({ steps = 2, simDt = 2 * DT, disp = 32 * DT }), sample(), DT)
			T.expectEqual(kinds[1], "STUTTER")
			T.expectEqual(source, "pas_physique_double")
		end)

		T.it("pas physique manquant : STUTTER pas_physique_manquant", function()
			local _, source = Rules.classify(sample(), sample({ steps = 0, simDt = 0, disp = 0 }), sample(), DT)
			T.expectEqual(source, "pas_physique_manquant")
		end)

		T.it("vitesse simulée irrégulière : STUTTER simulation", function()
			local _, source = Rules.classify(sample(), sample({ simSpeed = 32, disp = 32 * DT }), sample(), DT)
			T.expectEqual(source, "simulation")
		end)

		T.it("déplacement sans rapport avec la vitesse simulée : position_hors_simulation", function()
			local _, source = Rules.classify(sample(), sample({ disp = 40 * DT }), sample(), DT)
			T.expectEqual(source, "position_hors_simulation")
		end)

		T.it("pas simulé plus long que la frame rendue : timing_rendu_vs_simulation", function()
			local cur = sample({ dt = DT * 0.8, simDt = DT * 1.2, disp = 16 * DT * 1.2 })
			local _, source = Rules.classify(sample(), cur, sample(), DT)
			T.expectEqual(source, "timing_rendu_vs_simulation")
		end)

		T.it("rotation irrégulière : ROTATION", function()
			local kinds = Rules.classify(sample(), sample({ yawRate = 300 }), sample(), DT)
			T.expectEqual(kinds[1], "ROTATION")
		end)
	end)
end

return function(T, Loader)
	local Rules = Loader.new():require("src/client/systems/game/MenuSceneRules")

	-- Cette méthode permet de comparer deux nombres à une tolérance près lorsqu'un calcul trigonométrique arrondit.
	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-6)
	end

	T.describe("MenuSceneRules.damp", function()
		T.it("se rapproche de la cible sans la dépasser", function()
			T.expectEqual(Rules.damp(0, 10, 0.1, 5), 5)
			T.expectEqual(Rules.damp(0, 10, 1, 5), 10)
		end)
	end)

	T.describe("MenuSceneRules.aimAngles", function()
		T.it("regarde droit devant quand le curseur est centré, sans recul", function()
			local a = Rules.aimAngles(0, 0, 0)
			T.expectEqual(a.camYaw, -0)
			T.expectEqual(a.camPitch, -0)
		end)

		T.it("tourne vers le curseur et relève la vue pendant le recul", function()
			T.expectEqual(Rules.aimAngles(1, 0, 0).camYaw < 0, true)
			T.expectEqual(Rules.aimAngles(0, 0, 1).camPitch > 0, true)
		end)
	end)

	T.describe("MenuSceneRules.decayKick", function()
		T.it("revient à zéro et ne passe pas en négatif", function()
			T.expectEqual(Rules.decayKick(0, 1), 0)
			T.expectEqual(Rules.decayKick(1, Rules.KICK_TIME * 2), 0)
			T.expectEqual(Rules.decayKick(1, 0) == 1, true)
		end)
	end)

	T.describe("MenuSceneRules.fitFov", function()
		T.it("garde le FOV au format de référence et sur un écran plus large", function()
			T.expectEqual(Rules.fitFov(35.12, 16 / 9, 16 / 9), 35.12)
			T.expectEqual(Rules.fitFov(35.12, 16 / 9, 21 / 9), 35.12)
		end)

		T.it("ouvre le FOV en 4:3 pour garder la largeur du 16:9 (45,75° comme le rendu Blender)", function()
			T.expectEqual(near(Rules.fitFov(35.12, 16 / 9, 4 / 3), 45.75, 0.02), true)
		end)
	end)

	T.describe("MenuSceneRules.scatterProgress", function()
		T.it("va de 0 à 1 et reste à 1 après la dispersion", function()
			T.expectEqual(Rules.scatterProgress(0), 0)
			T.expectEqual(Rules.scatterProgress(Rules.SCATTER_TIME), 1)
			T.expectEqual(Rules.scatterProgress(Rules.SCATTER_TIME * 3), 1)
		end)

		T.it("ralentit en fin de course", function()
			T.expectEqual(Rules.scatterProgress(Rules.SCATTER_TIME / 2) > 0.5, true)
		end)
	end)

	T.describe("MenuSceneRules.settle", function()
		T.it("tourne lentement depuis la position dispersée tant que l'éclat attend", function()
			local a, tilt = Rules.settle(2, 0.1, -1)
			T.expectEqual(near(a, 2 - Rules.DRIFT_SPEED), true)
			T.expectEqual(tilt, 0.1)
		end)

		T.it("part de la position dispersée à la libération, sans saut", function()
			local a, tilt = Rules.settle(2, 0.1, 0)
			T.expectEqual(a, 2)
			T.expectEqual(tilt, 0.1)
			local a2 = Rules.settle(2, 0.1, 1e-4)
			T.expectEqual(near(a2, 2, 1e-3), true)
		end)

		T.it("dépasse la position de repos (oscillation) puis s'y pose", function()
			-- demi-période du pivot : l'éclat est passé de l'autre côté
			local a = Rules.settle(1, 0, 1 / (2 * Rules.SWING_HZ))
			T.expectEqual(a < 0, true)
			local posed = Rules.settle(math.rad(280), math.rad(8), Rules.SETTLE_TIME)
			T.expectEqual(math.abs(posed) < 0.005, true)
		end)
	end)

	T.describe("MenuSceneRules.hitVelocity", function()
		T.it("est pleine au point d'impact, décroît puis s'annule au-delà du rayon", function()
			local full = Rules.hitVelocity(0)
			T.expectEqual(full > 0, true)
			T.expectEqual(Rules.hitVelocity(Rules.HIT_RADIUS / 2) < full, true)
			T.expectEqual(Rules.hitVelocity(Rules.HIT_RADIUS), 0)
			T.expectEqual(Rules.hitVelocity(Rules.HIT_RADIUS * 3), 0)
		end)
	end)

	T.describe("MenuSceneRules.springStep", function()
		-- Cette méthode permet de suivre le ressort image par image lorsqu'un test simule la réaction d'un éclat.
		local function run(velocity, duration, dt)
			local offset, peak = 0, 0
			local elapsed = 0
			while elapsed < duration do
				offset, velocity = Rules.springStep(offset, velocity, dt)
				peak = math.max(peak, math.abs(offset))
				elapsed += dt
			end
			return offset, peak
		end

		T.it("part dans le sens de l'élan, sans saut", function()
			local offset = Rules.springStep(0, 1, 1 / 60)
			T.expectEqual(offset > 0 and offset < 0.02, true)
		end)

		T.it("pivote d'environ la moitié de HIT_ANGLE puis revient au repos", function()
			local final, peak = run(Rules.hitVelocity(0), Rules.HIT_TIME, 1 / 60)
			T.expectEqual(near(peak, Rules.HIT_ANGLE / 2, 0.15), true)
			T.expectEqual(math.abs(final) < 0.02, true)
		end)

		T.it("reste stable sur des images longues", function()
			local final = run(Rules.hitVelocity(0), Rules.HIT_TIME, 0.25)
			T.expectEqual(math.abs(final) < 0.02, true)
		end)
	end)

	T.describe("MenuSceneRules.statSegments", function()
		T.it("remplit toute la barre pour l'arme la plus forte", function()
			T.expectEqual(Rules.statSegments(115, 115, 10), 10)
		end)

		T.it("arrondit au segment et garde au moins un segment pour une valeur positive", function()
			T.expectEqual(Rules.statSegments(50, 115, 10), 4)
			T.expectEqual(Rules.statSegments(1, 1000, 10), 1)
		end)

		T.it("laisse la barre vide sans valeur ni maximum", function()
			T.expectEqual(Rules.statSegments(0, 115, 10), 0)
			T.expectEqual(Rules.statSegments(5, 0, 10), 0)
		end)
	end)
end

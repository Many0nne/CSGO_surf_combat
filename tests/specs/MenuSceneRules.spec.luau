return function(T, Loader)
	local Rules = Loader.new():require("src/client/systems/game/MenuSceneRules")

	-- Cette méthode permet de comparer deux nombres à une tolérance près lorsqu'un calcul trigonométrique arrondit.
	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-6)
	end

	-- Cette méthode permet d'écrire un vecteur sans Vector3 (absent sous Lune) lorsqu'on appelle une règle géométrique.
	local function vec(x, y, z)
		return { X = x, Y = y, Z = z }
	end

	T.describe("MenuSceneRules.damp", function()
		T.it("se rapproche de la cible sans la dépasser", function()
			T.expectEqual(Rules.damp(0, 10, 0.1, 5), 5)
			T.expectEqual(Rules.damp(0, 10, 1, 5), 10)
		end)
	end)

	T.describe("MenuSceneRules.aimAngles", function()
		T.it("regarde droit devant quand le curseur est centré", function()
			local a = Rules.aimAngles(0, 0)
			T.expectEqual(a.camYaw, -0)
			T.expectEqual(a.camPitch, -0)
		end)

		T.it("tourne légèrement vers le curseur", function()
			T.expectEqual(Rules.aimAngles(1, 0).camYaw < 0, true)
			T.expectEqual(Rules.aimAngles(0, 1).camPitch < 0, true)
			T.expectEqual(math.abs(Rules.aimAngles(1, 1).camYaw) <= 2, true)
		end)
	end)

	T.describe("MenuSceneRules.fitFov", function()
		T.it("garde le FOV au format de référence et sur un écran plus large", function()
			T.expectEqual(Rules.fitFov(35.12, 16 / 9, 16 / 9), 35.12)
			T.expectEqual(Rules.fitFov(35.12, 16 / 9, 21 / 9), 35.12)
		end)

		T.it("ouvre le FOV en 4:3 pour garder la largeur du 16:9", function()
			T.expectEqual(near(Rules.fitFov(35.12, 16 / 9, 4 / 3), 45.75, 0.02), true)
		end)
	end)

	T.describe("MenuSceneRules.inView", function()
		local eye, forward = vec(0, 0, 0), vec(1, 0, 0)
		local tanHalf, maxDistance, nearRadius = 1, 500, 30

		T.it("garde une pièce devant la caméra, dans le cône", function()
			T.expectEqual(Rules.inView(vec(100, 0, 50), 1, eye, forward, tanHalf, maxDistance, nearRadius), true)
		end)

		T.it("écarte une pièce derrière la caméra, hors du voisinage", function()
			T.expectEqual(Rules.inView(vec(-100, 0, 0), 1, eye, forward, tanHalf, maxDistance, nearRadius), false)
		end)

		T.it("garde une pièce derrière la caméra mais toute proche (ombres, bords)", function()
			T.expectEqual(Rules.inView(vec(-20, 0, 0), 1, eye, forward, tanHalf, maxDistance, nearRadius), true)
		end)

		T.it("écarte une pièce hors du cône ou trop loin", function()
			T.expectEqual(Rules.inView(vec(100, 0, 150), 1, eye, forward, tanHalf, maxDistance, nearRadius), false)
			T.expectEqual(Rules.inView(vec(800, 0, 0), 1, eye, forward, tanHalf, maxDistance, nearRadius), false)
		end)

		T.it("garde une grande pièce dont le centre sort du cône mais qui y entre", function()
			T.expectEqual(Rules.inView(vec(100, 0, 150), 60, eye, forward, tanHalf, maxDistance, nearRadius), true)
		end)
	end)

	T.describe("MenuSceneRules.cycleIndex", function()
		T.it("passe à l'arme suivante et revient au début après la dernière", function()
			T.expectEqual(Rules.cycleIndex(1, 1, 3), 2)
			T.expectEqual(Rules.cycleIndex(3, 1, 3), 1)
		end)

		T.it("revient à la dernière avant la première", function()
			T.expectEqual(Rules.cycleIndex(1, -1, 3), 3)
		end)

		T.it("reste sur 1 sans arme", function()
			T.expectEqual(Rules.cycleIndex(1, 1, 0), 1)
		end)
	end)

	T.describe("MenuSceneRules.skinLabel (#280)", function()
		T.it("nomme le skin d'origine et un skin du catalogue", function()
			T.expectEqual(Rules.skinLabel(nil), "D'ORIGINE")
			T.expectEqual(Rules.skinLabel("skin.awp.dragon_lore"), "DRAGON LORE")
		end)
	end)

	T.describe("MenuSceneRules.breathAngle", function()
		T.it("part du repos et reste faible", function()
			T.expectEqual(Rules.breathAngle(0), 0)
			T.expectEqual(near(Rules.breathAngle(Rules.BREATH_PERIOD / 4), Rules.BREATH_ANGLE), true)
			T.expectEqual(math.abs(Rules.breathAngle(1.3)) <= Rules.BREATH_ANGLE, true)
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

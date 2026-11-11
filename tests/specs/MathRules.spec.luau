return function(T, Loader)
	local M = Loader.new():require("src/shared/MathRules")

	local NAN = 0 / 0
	local INF = math.huge

	-- Les Vector3 sont en simple précision : les angles issus d'un acos ne sont justes qu'à ~1e-4° près.
	local function near(a: number, b: number): boolean
		return math.abs(a - b) < 1e-3
	end

	T.describe("MathRules.isFinite", function()
		T.it("accepte un nombre ordinaire, zéro et les négatifs", function()
			T.expectEqual(M.isFinite(0), true)
			T.expectEqual(M.isFinite(-3.5), true)
			T.expectEqual(M.isFinite(1e300), true)
		end)

		T.it("refuse NaN et ±inf", function()
			T.expectEqual(M.isFinite(NAN), false, "NaN")
			T.expectEqual(M.isFinite(INF), false, "+inf")
			T.expectEqual(M.isFinite(-INF), false, "-inf")
		end)

		T.it("refuse ce qui n'est pas un nombre", function()
			T.expectEqual(M.isFinite(nil), false)
			T.expectEqual(M.isFinite("1"), false)
			T.expectEqual(M.isFinite(true), false)
			T.expectEqual(M.isFinite({}), false)
		end)
	end)

	T.describe("MathRules.isFiniteVector3", function()
		T.it("accepte un Vector3 fini", function()
			T.expectEqual(M.isFiniteVector3(Vector3.new(1, -2, 3)), true)
			T.expectEqual(M.isFiniteVector3(Vector3.zero), true)
		end)

		T.it("refuse un Vector3 avec une composante NaN ou infinie", function()
			T.expectEqual(M.isFiniteVector3(Vector3.new(NAN, 0, 0)), false, "NaN en X")
			T.expectEqual(M.isFiniteVector3(Vector3.new(0, INF, 0)), false, "inf en Y")
			T.expectEqual(M.isFiniteVector3(Vector3.new(0, 0, -INF)), false, "-inf en Z")
		end)

		T.it("refuse ce qui n'est pas un Vector3", function()
			T.expectEqual(M.isFiniteVector3(nil), false)
			T.expectEqual(M.isFiniteVector3(1), false)
			T.expectEqual(M.isFiniteVector3({ X = 0, Y = 0, Z = 0 }), false)
		end)
	end)

	T.describe("MathRules.isBounded et isBoundedVector3", function()
		T.it("accepte jusqu'à la borne incluse, dans les deux sens", function()
			T.expectEqual(M.isBounded(100, 100), true)
			T.expectEqual(M.isBounded(-100, 100), true)
			T.expectEqual(M.isBounded(100.001, 100), false)
		end)

		T.it("refuse NaN, ±inf et les autres types", function()
			T.expectEqual(M.isBounded(NAN, 100), false)
			T.expectEqual(M.isBounded(INF, 100), false)
			T.expectEqual(M.isBounded(-INF, 100), false)
			T.expectEqual(M.isBounded("5", 100), false)
		end)

		T.it("juge chaque composante d'un Vector3", function()
			T.expectEqual(M.isBoundedVector3(Vector3.new(100, -100, 0), 100), true)
			T.expectEqual(M.isBoundedVector3(Vector3.new(0, 0, 101), 100), false, "Z hors borne")
			T.expectEqual(M.isBoundedVector3(Vector3.new(NAN, 0, 0), 100), false, "NaN")
			T.expectEqual(M.isBoundedVector3(Vector3.new(INF, 0, 0), 100), false, "inf")
			T.expectEqual(M.isBoundedVector3(nil, 100), false)
		end)
	end)

	T.describe("MathRules.wrapAngle et angleDelta (radians)", function()
		T.it("ramène un angle dans [-π, π[", function()
			T.expect(near(M.wrapAngle(0), 0))
			T.expect(near(M.wrapAngle(3 * math.pi / 2), -math.pi / 2), "270° vaut -90°")
			T.expect(near(M.wrapAngle(-3 * math.pi / 2), math.pi / 2), "-270° vaut 90°")
			T.expect(near(M.wrapAngle(5 * math.pi), -math.pi), "900° vaut -180°")
		end)

		T.it("prend le plus court côté, par ±π", function()
			T.expect(near(M.angleDelta(math.pi - 0.1, -math.pi + 0.1), 0.2), "de 170° à -170° : +20°")
			T.expect(near(M.angleDelta(-math.pi + 0.1, math.pi - 0.1), -0.2), "de -170° à 170° : -20°")
			T.expect(near(M.angleDelta(0.5, 0.5), 0), "aucune rotation")
		end)

		T.it("un demi-tour vaut -π (borne basse incluse)", function()
			T.expect(near(M.angleDelta(0, math.pi), -math.pi))
			T.expect(near(M.angleDelta(math.pi, 0), -math.pi))
		end)
	end)

	T.describe("MathRules.wrapAngleDeg et angleDeltaDeg (degrés)", function()
		T.it("ramène un angle dans [-180, 180[", function()
			T.expect(near(M.wrapAngleDeg(270), -90))
			T.expect(near(M.wrapAngleDeg(-270), 90))
			T.expect(near(M.wrapAngleDeg(180), -180))
			T.expect(near(M.wrapAngleDeg(540), -180))
		end)

		T.it("prend le plus court côté, par 0°/360°", function()
			T.expect(near(M.angleDeltaDeg(350, 10), 20), "de 350° à 10° : +20°")
			T.expect(near(M.angleDeltaDeg(10, 350), -20), "de 10° à 350° : -20°")
			T.expect(near(M.angleDeltaDeg(90, 90), 0))
			T.expect(near(M.angleDeltaDeg(0, 180), -180), "demi-tour")
		end)
	end)

	T.describe("MathRules.headingDeg", function()
		T.it("suit la convention de la caméra FPS : 0 vers -Z, positif vers +X", function()
			T.expect(near(M.headingDeg(0, -1), 0), "-Z")
			T.expect(near(M.headingDeg(1, 0), 90), "+X")
			T.expect(near(M.headingDeg(-1, 0), -90), "-X")
			T.expect(near(math.abs(M.headingDeg(0, 1)), 180), "+Z")
		end)
	end)

	T.describe("MathRules.horizontalLength", function()
		T.it("ignore la hauteur", function()
			T.expect(near(M.horizontalLength(Vector3.new(3, 100, 4)), 5))
			T.expect(near(M.horizontalLength(Vector3.new(0, 7, 0)), 0), "vecteur vertical")
		end)
	end)

	T.describe("MathRules.horizontalAngle", function()
		local MIN = 1e-3

		T.it("mesure l'écart de 0 à 180°, hauteur ignorée", function()
			local forward = Vector3.new(0, 0, -1)
			T.expect(near(M.horizontalAngle(forward, Vector3.new(0, 50, -3), MIN) :: number, 0), "même cap")
			T.expect(near(M.horizontalAngle(forward, Vector3.new(2, -9, -2), MIN) :: number, 45), "45°")
			T.expect(near(M.horizontalAngle(forward, Vector3.new(1, 0, 0), MIN) :: number, 90), "90°")
			T.expect(near(M.horizontalAngle(forward, Vector3.new(0, 0, 5), MIN) :: number, 180), "dos")
		end)

		T.it("ne dépend pas du sens des arguments ni du côté (valeur absolue)", function()
			local a, b = Vector3.new(1, 0, 0), Vector3.new(0, 0, -1)
			T.expect(near(M.horizontalAngle(a, b, MIN) :: number, M.horizontalAngle(b, a, MIN) :: number))
			T.expect(near(M.horizontalAngle(Vector3.new(-1, 0, 0), b, MIN) :: number, 90))
		end)

		T.it("ne déborde pas du domaine d'acos pour des vecteurs presque colinéaires", function()
			local d = Vector3.new(0.3, 0, -0.7)
			local angle = M.horizontalAngle(d, d * 3, MIN)
			T.expect(angle ~= nil and angle == angle and angle < 1e-3, "écart : " .. tostring(angle))
		end)

		T.it("renvoie nil pour un vecteur vertical ou nul, de l'un ou l'autre côté", function()
			local forward = Vector3.new(0, 0, -1)
			T.expectEqual(M.horizontalAngle(forward, Vector3.new(0, 10, 0), MIN), nil, "cible verticale")
			T.expectEqual(M.horizontalAngle(Vector3.new(0, 1, 0), forward, MIN), nil, "regard vertical")
			T.expectEqual(M.horizontalAngle(Vector3.zero, forward, MIN), nil, "vecteur nul")
		end)

		T.it("le seuil minLength décide de ce qui est défini", function()
			local forward = Vector3.new(0, 0, -1)
			local tiny = Vector3.new(0.05, 0, 0)
			T.expectEqual(M.horizontalAngle(forward, tiny, 0.1), nil, "sous le seuil")
			T.expect(near(M.horizontalAngle(forward, tiny, 0.01) :: number, 90), "au-dessus du seuil")
		end)
	end)
end

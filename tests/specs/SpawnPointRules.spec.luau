-- Apparition (#288) : choix du point loin et hors de vue des ennemis vivants.
return function(T, Loader)
	local Rules = Loader.new():require("src/server/SpawnPointRules")
	local GameConfig = Loader.new():require("src/shared/GameConfig")
	local RADIUS = GameConfig.SPAWN_SAFE_RADIUS

	-- Cette méthode permet de simuler un raycast de vue qui ne voit jamais rien lorsqu'un test ne juge que la distance.
	local function blind()
		return false
	end

	-- Cette méthode permet de simuler un tirage qui renvoie toujours le premier candidat lorsqu'un test vérifie la liste.
	local function first()
		return 1
	end

	-- Groupes de Dizzy (ouest, est), à ~500 studs l'un de l'autre
	local WEST = Vector3.new(1780, 10, -110)
	local EAST = Vector3.new(2210, 10, -400)

	T.describe("SpawnPointRules.choose", function()
		T.it("sans ennemi : tirage uniforme sur tous les points, tous sûrs", function()
			local seen = {}
			for n = 1, 3 do
				local index, safe = Rules.choose({ WEST, EAST, WEST }, {}, blind, function(count)
					T.expectEqual(count, 3, "tous les points candidats")
					return n
				end)
				T.expectEqual(safe, true)
				seen[index :: number] = true
			end
			T.expectEqual(seen[1] and seen[2] and seen[3], true, "chaque point peut sortir")
		end)

		T.it("écarte un point trop proche d'un ennemi", function()
			local enemy = WEST + Vector3.new(RADIUS - 1, 0, 0)
			local index, safe = Rules.choose({ WEST, EAST }, { enemy }, blind, first)
			T.expectEqual(index, 2)
			T.expectEqual(safe, true)
		end)

		T.it("garde un point juste au-delà du rayon", function()
			local enemy = WEST + Vector3.new(RADIUS + 1, 0, 0)
			T.expectEqual(Rules.isSafe(WEST, { enemy }, blind), true)
		end)

		T.it("écarte un point en vue d'un ennemi, même loin", function()
			local enemy = EAST + Vector3.new(0, 0, 400)
			-- L'ennemi voit le groupe ouest seulement ; l'appel reçoit ses yeux puis ceux du point
			local function sees(from, to)
				T.expectEqual(from, enemy)
				return to == WEST
			end
			local index, safe = Rules.choose({ WEST, EAST }, { enemy }, sees, first)
			T.expectEqual(index, 2)
			T.expectEqual(safe, true)
		end)

		T.it("un point doit être sûr pour chaque ennemi", function()
			local nearWest = WEST + Vector3.new(5, 0, 0)
			local nearEast = EAST + Vector3.new(5, 0, 0)
			local _, safe = Rules.choose({ WEST, EAST }, { nearWest, nearEast }, blind, first)
			T.expectEqual(safe, false)
		end)

		T.it("sans point sûr : retombe sur le point le plus loin de son ennemi le plus proche", function()
			local always = function()
				return true
			end
			local far = WEST + Vector3.new(80, 0, 0)
			local enemies = { WEST, EAST }
			local index, safe = Rules.choose(
				{ WEST + Vector3.new(10, 0, 0), far, EAST },
				enemies,
				always,
				function(count)
					T.expectEqual(count, 1, "un seul point le plus éloigné")
					return 1
				end
			)
			T.expectEqual(index, 2)
			T.expectEqual(safe, false)
		end)

		T.it("repli : à distance égale, le point que voient le moins d'ennemis, puis tirage", function()
			local enemy = Vector3.new(0, 0, 0)
			local points = { Vector3.new(50, 0, 0), Vector3.new(-50, 0, 0), Vector3.new(0, 0, 50) }
			local function sees(_, to)
				return to == points[1]
			end
			T.expectEqual(table.concat(Rules.farthest(points, { enemy }, sees), ","), "2,3")
			local index = Rules.choose(points, { enemy }, sees, function(count)
				T.expectEqual(count, 2)
				return 2
			end)
			T.expectEqual(index, 3)
		end)

		T.it("tire parmi les seuls points sûrs, uniformément", function()
			local enemy = WEST
			local points = { WEST, EAST, WEST + Vector3.new(10, 0, 0), EAST + Vector3.new(10, 0, 0) }
			local index = Rules.choose(points, { enemy }, blind, function(count)
				T.expectEqual(count, 2, "deux points sûrs (est)")
				return 2
			end)
			T.expectEqual(index, 4)
		end)

		T.it("sans point : nil", function()
			local index, safe = Rules.choose({}, {}, blind, first)
			T.expectEqual(index, nil)
			T.expectEqual(safe, false)
		end)
	end)

	T.describe("SpawnPointRules.blocksSight", function()
		T.it("ni les murs d'air ni les pièces transparentes n'arrêtent le regard, un mur si", function()
			T.expectEqual(Rules.blocksSight(true, 0), false, "mur d'air (Clips)")
			T.expectEqual(Rules.blocksSight(false, 0.55), false, "grillage")
			T.expectEqual(Rules.blocksSight(false, 1), false, "pièce invisible")
			T.expectEqual(Rules.blocksSight(false, 0), true, "mur")
			T.expectEqual(Rules.blocksSight(false, 0.2), true, "vitre teintée")
		end)
	end)
end

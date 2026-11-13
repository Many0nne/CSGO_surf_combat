-- Apparition (#288) : choix du point loin et hors de vue des ennemis vivants, retrait de la protection au premier tir.
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

		T.it("retombe sur le hasard parmi tous les points si aucun ne convient", function()
			local always = function()
				return true
			end
			local index, safe = Rules.choose({ WEST, EAST }, { WEST }, always, function(count)
				T.expectEqual(count, 2, "repli : tous les points")
				return 2
			end)
			T.expectEqual(index, 2)
			T.expectEqual(safe, false)
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

	T.describe("SpawnProtection.drop", function()
		local Protection = Loader.new():require("src/server/SpawnProtection")

		-- Cette méthode permet de construire un faux personnage avec des enfants nommés lorsqu'un test vérifie le retrait.
		local function fakeCharacter(names: { string })
			local char = { children = {} }
			for _, name in names do
				local child = { Name = name }
				function child.Destroy(self)
					local list = char.children
					table.remove(list, table.find(list, self) :: number)
				end
				table.insert(char.children, child)
			end
			function char.GetChildren(self)
				return table.clone(self.children)
			end
			return char
		end

		T.it("retire la protection au premier tir, puis plus rien", function()
			local char = fakeCharacter({ Protection.NAME, "Humanoid" })
			T.expectEqual(Protection.drop(char :: any), true)
			T.expectEqual(#char.children, 1)
			T.expectEqual(char.children[1].Name, "Humanoid")
			T.expectEqual(Protection.drop(char :: any), false, "second tir : plus de protection")
		end)

		T.it("ne retire pas un autre ForceField", function()
			local char = fakeCharacter({ "ForceField" })
			T.expectEqual(Protection.drop(char :: any), false)
			T.expectEqual(#char.children, 1)
		end)

		T.it("sans personnage : rien", function()
			T.expectEqual(Protection.drop(nil), false)
		end)
	end)
end

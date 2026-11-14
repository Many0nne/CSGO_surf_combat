-- Hauteur des points d'apparition (#328) : sous chaque point de GroundSpawns, écart entre les pieds du rig posé par
-- SpawnManager et le premier sol vu par les rayons du mouvement (CanQuery), dans [0, MAX_FALL] ; un point au-dessus
-- du vide ou dans un volume est fautif.
return function(T, Loader)
	local SpawnCheck = Loader.new():require("tools/map/SpawnCheck")
	local SpawnPointRules = Loader.new():require("src/server/SpawnPointRules")

	-- Cette méthode permet de poser une pièce ancrée dans un dossier lorsqu'un test construit une petite map.
	local function part(parent, name, position, size, query)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = CFrame.new(position)
		p.CanQuery = query ~= false
		p.Parent = parent
		return p
	end

	-- Cette méthode permet de construire une map avec un sol plat (dessus à Y = 0) et un dossier GroundSpawns vide
	-- lorsqu'un test y pose ses points.
	local function flatMap()
		local map = Instance.new("Model")
		map.Name = "Test"
		local geometry = Instance.new("Folder")
		geometry.Name = "Geometry"
		geometry.Parent = map
		part(geometry, "floor", Vector3.new(0, -1, 0), Vector3.new(100, 2, 100))
		local spawns = Instance.new("Folder")
		spawns.Name = "GroundSpawns"
		spawns.Parent = map
		return map, spawns
	end

	-- Cette méthode permet de poser un point d'apparition (2 × 1 × 2, sans requête) dont les pieds du rig posé par
	-- SpawnManager seraient à la hauteur `feet` lorsqu'un test le mesure.
	local function point(spawns, name, x, feet, z)
		local centerY = feet + SpawnCheck.ROOT_TO_FEET - SpawnCheck.ROOT_ABOVE_POINT
		return part(spawns, name, Vector3.new(x, centerY, z), Vector3.new(2, 1, 2), false)
	end

	T.describe("SpawnCheck", function()
		T.it("part de la racine telle que SpawnManager la pose", function()
			T.expectEqual(SpawnCheck.ROOT_ABOVE_POINT, SpawnPointRules.ROOT_ABOVE_POINT)
		end)

		T.it("mesure l'écart signé entre les pieds et le sol, points triés par nom", function()
			local map, spawns = flatMap()
			point(spawns, "B", 10, 0.76, 0)
			point(spawns, "A", 0, -0.4, 0)
			local m = SpawnCheck.measure(map)
			T.expectEqual(#m, 2)
			T.expectEqual(m[1].name, "A")
			T.expectNear(m[1].gap, -0.4, 1e-4, "A")
			T.expectNear(m[2].gap, 0.76, 1e-4, "B")
			T.expectNear(m[2].floorY, 0, 1e-4, "B : sol")
		end)

		T.it("ignore les pièces sans requête (habillage) et lit une marche plus haute sous le point", function()
			local map, spawns = flatMap()
			part(map, "decor", Vector3.new(0, 1, 0), Vector3.new(4, 2, 4), false)
			part(map, "step", Vector3.new(20, 0.5, 0), Vector3.new(4, 1, 4))
			point(spawns, "A", 0, 0.5, 0)
			point(spawns, "B", 20, 0.5, 0)
			local m = SpawnCheck.measure(map)
			T.expectNear(m[1].gap, 0.5, 1e-4, "A : l'habillage sans requête n'est pas un sol")
			T.expectNear(m[2].gap, -0.5, 1e-4, "B : marche de 1 stud sous des pieds à 0,5")
		end)

		T.it("ne trouve aucun sol au-dessus du vide", function()
			local map, spawns = flatMap()
			point(spawns, "A", 500, 0.5, 0)
			T.expectEqual(SpawnCheck.measure(map)[1].gap, nil)
		end)

		T.it("accepte des pieds au-dessus du sol dans la limite de chute", function()
			local map, spawns = flatMap()
			point(spawns, "A", 0, 0.01, 0)
			point(spawns, "B", 10, SpawnCheck.MAX_FALL - 0.01, 0)
			local lines, errors, low, high = SpawnCheck.check(map)
			T.expectEqual(#lines, 2)
			T.expectEqual(#errors, 0)
			T.expectNear(low, 0.01, 1e-4, "écart le plus bas")
			T.expectNear(high, SpawnCheck.MAX_FALL - 0.01, 1e-4, "écart le plus haut")
		end)

		T.it("signale des pieds sous le sol, trop hauts, au-dessus du vide ou un point dans un mur", function()
			local map, spawns = flatMap()
			point(spawns, "Low", 0, -0.1, 0)
			point(spawns, "High", 10, SpawnCheck.MAX_FALL + 0.1, 0)
			point(spawns, "Void", 500, 0.5, 0)
			part(map, "wall", Vector3.new(30, 5, 0), Vector3.new(4, 10, 4))
			point(spawns, "Wall", 30, 0.5, 0)
			local _, errors = SpawnCheck.check(map)
			T.expectEqual(#errors, 4)
			T.expect(string.find(errors[1], "High", 1, true) ~= nil, "erreurs dans l'ordre des noms : " .. errors[1])
		end)
	end)
end

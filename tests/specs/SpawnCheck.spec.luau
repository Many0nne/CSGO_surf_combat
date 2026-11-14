-- Hauteur des points d'apparition (#328) : sous chaque point de GroundSpawns, écart entre sa face basse et le premier
-- sol vu par les rayons du mouvement (CanQuery), borné par SpawnCheck.TOL ; un point dans le vide ou dans un volume est
-- fautif.
return function(T, Loader)
	local SpawnCheck = Loader.new():require("tools/map/SpawnCheck")

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

	-- Cette méthode permet de poser un point d'apparition du générateur (2 × 1 × 2, sans requête) dont la face basse est
	-- à `bottom` lorsqu'un test le mesure.
	local function point(spawns, name, x, bottom, z)
		return part(spawns, name, Vector3.new(x, bottom + 0.5, z), Vector3.new(2, 1, 2), false)
	end

	T.describe("SpawnCheck.measure", function()
		T.it("mesure l'écart signé entre la face basse du point et le sol", function()
			local map, spawns = flatMap()
			point(spawns, "B", 10, 0.03, 0)
			point(spawns, "A", 0, -0.4, 0)
			local m = SpawnCheck.measure(map)
			T.expectEqual(#m, 2)
			T.expectEqual(m[1].name, "A")
			T.expectNear(m[1].gap, -0.4, 1e-4, "A")
			T.expectNear(m[2].gap, 0.03, 1e-4, "B")
			T.expectNear(m[2].floorY, 0, 1e-4, "B : sol")
		end)

		T.it("ignore les pièces sans requête (habillage) et lit une marche plus haute sous le point", function()
			local map, spawns = flatMap()
			part(map, "decor", Vector3.new(0, 1, 0), Vector3.new(4, 2, 4), false)
			part(map, "step", Vector3.new(20, 0.5, 0), Vector3.new(4, 1, 4))
			point(spawns, "A", 0, 0, 0)
			point(spawns, "B", 20, 0, 0)
			local m = SpawnCheck.measure(map)
			T.expectNear(m[1].gap, 0, 1e-4, "A : l'habillage sans requête n'est pas un sol")
			T.expectNear(m[2].gap, -1, 1e-4, "B : marche de 1 stud au-dessus de la face basse")
		end)

		T.it("ne trouve aucun sol au-dessus du vide", function()
			local map, spawns = flatMap()
			point(spawns, "A", 500, 0, 0)
			local m = SpawnCheck.measure(map)
			T.expectEqual(m[1].gap, nil)
		end)
	end)

	T.describe("SpawnCheck.check", function()
		T.it("accepte des points au niveau du sol, à la tolérance près", function()
			local map, spawns = flatMap()
			point(spawns, "A", 0, 0.03, 0)
			point(spawns, "B", 10, -SpawnCheck.TOL + 0.01, 0)
			local lines, errors, worst = SpawnCheck.check(map)
			T.expectEqual(#lines, 2)
			T.expectEqual(#errors, 0)
			T.expectNear(worst, SpawnCheck.TOL - 0.01, 1e-4, "plus grand écart = celui de B")
		end)

		T.it("signale un point enfoncé, un point trop haut, un point dans le vide et un point dans un mur", function()
			local map, spawns = flatMap()
			point(spawns, "Low", 0, -1, 0)
			point(spawns, "High", 10, 1, 0)
			point(spawns, "Void", 500, 0, 0)
			part(map, "wall", Vector3.new(30, 5, 0), Vector3.new(4, 10, 4))
			point(spawns, "Wall", 30, 0, 0)
			local _, errors, worst = SpawnCheck.check(map)
			T.expectEqual(#errors, 4)
			T.expectEqual(worst, math.huge)
			T.expect(string.find(errors[1], "High", 1, true) ~= nil, "erreurs dans l'ordre des noms : " .. errors[1])
		end)
	end)
end

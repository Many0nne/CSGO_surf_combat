-- Vues entre zones d'apparition (#329) : deux points de zones différentes ne doivent pas se voir d'yeux à yeux ; murs
-- d'air (Clips) et pièces transparentes (grillages) laissent passer le regard, comme dans SpawnManager.
return function(T, Loader)
	local SpawnSight = Loader.new():require("tools/map/SpawnSight")
	local SpawnPointRules = Loader.new():require("src/server/SpawnPointRules")

	-- Cette méthode permet de poser une pièce ancrée dans un dossier lorsqu'un test construit une petite map.
	local function part(parent, name, position, size)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = CFrame.new(position)
		p.Parent = parent
		return p
	end

	-- Cette méthode permet de construire une map vide avec ses dossiers Geometry, Geometry.Clips et GroundSpawns
	-- lorsqu'un test y pose ses points et ses murs.
	local function emptyMap()
		local map = Instance.new("Model")
		map.Name = "Test"
		local geometry = Instance.new("Folder")
		geometry.Name = "Geometry"
		geometry.Parent = map
		local clips = Instance.new("Folder")
		clips.Name = "Clips"
		clips.Parent = geometry
		local spawns = Instance.new("Folder")
		spawns.Name = "GroundSpawns"
		spawns.Parent = map
		return map, geometry, clips, spawns
	end

	-- Cette méthode permet de poser un point d'apparition (2 × 1 × 2, sans requête) avec son équipe et sa zone
	-- lorsqu'un test vérifie les vues.
	local function point(spawns, name, x, team, zone)
		local p = part(spawns, name, Vector3.new(x, 0.5, 0), Vector3.new(2, 1, 2))
		p.CanQuery = false
		p:SetAttribute("Team", team)
		if zone then
			p:SetAttribute("Zone", zone)
		end
		return p
	end

	T.describe("SpawnSight", function()
		T.it("teste la vue des yeux comme SpawnPointRules", function()
			T.expectEqual(SpawnSight.POINT_EYE, SpawnPointRules.POINT_EYE_OFFSET)
			T.expectEqual(SpawnSight.SEE_THROUGH, SpawnPointRules.SEE_THROUGH_TRANSPARENCY)
		end)

		T.it("signale deux zones qui se voient, pas deux points d'une même zone", function()
			local map, _, _, spawns = emptyMap()
			point(spawns, "A1", 0, "FFA", "Nord")
			point(spawns, "A2", 4, "FFA", "Nord")
			point(spawns, "B1", 60, "FFA", "Sud")
			local tested, visible, rows = SpawnSight.check(map)
			T.expectEqual(tested, 2)
			T.expectEqual(#visible, 2)
			T.expectEqual(#rows, 1)
			T.expectEqual(rows[1].za, "Nord")
			T.expectEqual(rows[1].zb, "Sud")
		end)

		T.it("prend l'équipe comme zone sans attribut Zone", function()
			local map, _, _, spawns = emptyMap()
			point(spawns, "T01", 0, "T")
			point(spawns, "CT01", 60, "CT")
			local tested, visible = SpawnSight.check(map)
			T.expectEqual(tested, 1)
			T.expectEqual(#visible, 1)
		end)

		T.it("un mur arrête le regard, pas un mur d'air ni un grillage", function()
			local map, geometry, clips, spawns = emptyMap()
			point(spawns, "A", 0, "FFA", "Nord")
			point(spawns, "B", 60, "FFA", "Sud")
			local clip = part(clips, "Clip", Vector3.new(20, 5, 0), Vector3.new(1, 20, 20))
			clip.Transparency = 1
			local fence = part(geometry, "fence", Vector3.new(25, 5, 0), Vector3.new(1, 20, 20))
			fence.Transparency = 0.55
			T.expectEqual(#select(2, SpawnSight.check(map)), 1)
			part(geometry, "wall", Vector3.new(30, 5, 0), Vector3.new(1, 20, 20))
			T.expectEqual(#select(2, SpawnSight.check(map)), 0)
		end)

		T.it(
			"une pièce qui contient les yeux d'un point ne cache rien, dans les deux sens (comme workspace:Raycast)",
			function()
				local map, geometry, _, spawns = emptyMap()
				point(spawns, "A", 0, "FFA", "Nord")
				point(spawns, "B", 60, "FFA", "Sud")
				-- poutre autour des yeux de A (6,5 studs au-dessus du centre du point)
				part(geometry, "beam", Vector3.new(0, 7, 0), Vector3.new(3, 2, 3))
				T.expectEqual(#select(2, SpawnSight.check(map)), 1)
			end
		)

		T.it("un cylindre n'arrête pas le regard (sa boîte cacherait plus qu'en jeu)", function()
			local map, geometry, _, spawns = emptyMap()
			point(spawns, "A", 0, "FFA", "Nord")
			point(spawns, "B", 60, "FFA", "Sud")
			local pipe = part(geometry, "pipe", Vector3.new(30, 5, 0), Vector3.new(20, 20, 20))
			pipe.Shape = require("@lune/roblox").Enum.PartType.Cylinder
			T.expectEqual(#select(2, SpawnSight.check(map)), 1)
		end)

		T.it("un mur sous la ligne des yeux ne la coupe pas", function()
			local map, geometry, _, spawns = emptyMap()
			point(spawns, "A", 0, "FFA", "Nord")
			point(spawns, "B", 60, "FFA", "Sud")
			part(geometry, "low", Vector3.new(30, 2, 0), Vector3.new(1, 4, 20))
			T.expectEqual(#select(2, SpawnSight.check(map)), 1)
		end)
	end)
end

-- Travail long étalé sur plusieurs frames (#605) : parcours dans l'ordre de GetDescendants, copie de map identique à
-- Clone (ordre, noms, attributs), découpage par budget.
return function(T, Loader)
	local waits = 0
	local fakeTask = {
		wait = function()
			waits += 1
		end,
	}
	local SlicedWork = Loader.new({}, { task = fakeTask }):require("src/shared/SlicedWork")

	-- Cette méthode permet de créer une instance rangée sous `parent` lorsqu'un test construit une map.
	local function make(className: string, name: string, parent: any): any
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
		return inst
	end

	-- Cette méthode permet de construire une petite map à plusieurs niveaux lorsqu'un test la parcourt ou la copie :
	-- dossiers imbriqués, modèle de décor, pièce avec un enfant, attributs sur la map et sur une pièce.
	local function fakeMap(): any
		local map = make("Model", "Radoub", nil)
		map:SetAttribute("KillHeight", -40)
		local geometry = make("Folder", "Geometry", map)
		local floors = make("Folder", "Floors", geometry)
		make("Part", "floor1", floors)
		local floor2 = make("Part", "floor2", floors)
		make("Decal", "stain", floor2)
		local ramps = make("Folder", "Ramps", geometry)
		local ramp = make("WedgePart", "ramp", ramps)
		ramp:SetAttribute("Group", "ramp")
		local crate = make("Model", "Crate", geometry)
		make("Part", "lid", crate)
		make("Part", "box", crate)
		make("Folder", "GroundSpawns", map)
		make("Part", "spawn", map.GroundSpawns)
		return map
	end

	-- Cette méthode permet d'écrire le chemin de chaque descendant d'une liste lorsqu'on compare deux parcours.
	local function paths(list: { any }, root: any): { string }
		local out = {}
		for _, inst in list do
			local names = {}
			local node = inst
			while node and node ~= root do
				table.insert(names, 1, node.Name .. ":" .. node.ClassName)
				node = node.Parent
			end
			table.insert(out, table.concat(names, "/"))
		end
		return out
	end

	T.describe("SlicedWork.eachDescendant", function()
		-- Ordre de GetDescendants dans Roblox (en profondeur, parent avant ses enfants ; contrôlé dans Studio sur Dizzy, #605).
		-- Lune rend un autre ordre (en largeur) : l'ordre attendu est écrit ici.
		T.it("visite les descendants en profondeur, parent avant ses enfants, dans l'ordre des enfants", function()
			local map = fakeMap()
			local visited = {}
			SlicedWork.eachDescendant(map, function(inst)
				table.insert(visited, inst.Name)
			end)
			T.expectEqual(
				table.concat(visited, " "),
				"Geometry Floors floor1 floor2 stain Ramps ramp Crate lid box GroundSpawns spawn"
			)
		end)

		T.it("appelle step après chaque visite", function()
			local map = fakeMap()
			local steps = 0
			SlicedWork.eachDescendant(map, function() end, function()
				steps += 1
			end)
			T.expectEqual(steps, #map:GetDescendants())
		end)
	end)

	T.describe("SlicedWork.cloneInto", function()
		T.it("copie la map comme Clone : même arbre, même ordre, mêmes attributs", function()
			local map = fakeMap()
			local world = make("Folder", "World", nil)
			local copy = SlicedWork.cloneInto(map, world)
			T.expectEqual(copy.Parent, world)
			T.expectEqual(copy.Name, "Radoub")
			T.expectEqual(copy.ClassName, "Model")
			T.expectEqual(copy:GetAttribute("KillHeight"), -40)
			local reference = map:Clone()
			T.expectEqual(
				table.concat(paths(copy:GetDescendants(), copy), " "),
				table.concat(paths(reference:GetDescendants(), reference), " ")
			)
			local ramp = copy.Geometry.Ramps.ramp
			T.expectEqual(ramp:GetAttribute("Group"), "ramp")
			T.expect(ramp ~= map.Geometry.Ramps.ramp, "copie distincte de l'original")
		end)

		T.it("laisse l'original intact et ignore ce qui n'est pas Archivable", function()
			local map = fakeMap()
			local hidden = make("Part", "hidden", map.Geometry)
			hidden.Archivable = false
			local before = #map:GetDescendants()
			local copy = SlicedWork.cloneInto(map, make("Folder", "World", nil))
			T.expectEqual(#map:GetDescendants(), before)
			T.expectEqual(copy.Geometry:FindFirstChild("hidden"), nil)
		end)

		T.it("appelle step à chaque enfant copié", function()
			local map = fakeMap()
			local steps = 0
			SlicedWork.cloneInto(map, make("Folder", "World", nil), function()
				steps += 1
			end)
			-- Geometry, Floors, floor1, floor2, Ramps, ramp, Crate, lid, box, GroundSpawns, spawn
			T.expectEqual(steps, 11)
		end)
	end)

	T.describe("SlicedWork.destroy", function()
		T.it("détruit la copie et tout son contenu", function()
			local world = make("Folder", "World", nil)
			local copy = SlicedWork.cloneInto(fakeMap(), world)
			local steps = 0
			SlicedWork.destroy(copy, function()
				steps += 1
			end)
			T.expectEqual(#world:GetChildren(), 0)
			T.expect(steps > 0, "destruction découpée")
		end)
	end)

	T.describe("SlicedWork.slicer", function()
		T.it("cède la main une fois la tranche écoulée, jamais avant", function()
			waits = 0
			local always = SlicedWork.slicer("test", -1)
			always.step()
			always.step()
			always.finish()
			T.expectEqual(waits, 2)
			waits = 0
			local never = SlicedWork.slicer("test", 1e9)
			for _ = 1, 100 do
				never.step()
			end
			never.finish()
			T.expectEqual(waits, 0)
		end)
	end)
end

-- Dossiers de map et règle des balles (#292) : murs d'air cherchés dans Geometry.Clips, murs d'air et grillages
-- `passbullets` écartés des rayons de tir et de vue, liste d'inclusion « tout sauf », dossiers attendus par la CI.
return function(T, Loader)
	local MapGeometry = Loader.new():require("src/shared/MapGeometry")
	local LadderRules = Loader.new():require("src/shared/LadderRules")
	local BotConfig = Loader.new():require("src/shared/BotConfig")

	-- Cette méthode permet de créer une instance rangée sous `parent` lorsqu'un test construit une map.
	local function make(className: string, name: string, parent: any): any
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
		return inst
	end

	-- Cette méthode permet de construire une map comme celle du générateur lorsqu'un test en a besoin : Geometry (sols,
	-- murs d'air, rampes, décor avec un grillage `passbullets`, un poteau `chainlink` et une caisse), spawns et échelles.
	local function fakeMap(): any
		local map = make("Model", "Dizzy", nil)
		local geometry = make("Folder", "Geometry", map)
		local floors = make("Folder", "Floors", geometry)
		make("Part", "floor", floors)
		local clips = make("Folder", "Clips", geometry)
		make("Part", "Clip", clips)
		make("Folder", "Ramps", geometry)
		local decor = make("Folder", "Decor", geometry)
		local fence = make("Part", "block", decor)
		fence:SetAttribute("Group", "passbullets_chainlink")
		local post = make("Part", "block", decor)
		post:SetAttribute("Group", "chainlink")
		local crate = make("Part", "block", decor)
		crate:SetAttribute("Group", "metal")
		make("Folder", "GroundSpawns", map)
		make("Folder", "Ladders", map)
		return map, { clips = clips, fence = fence, post = post, crate = crate, floors = floors, decor = decor }
	end

	-- Cette méthode permet de savoir si une liste contient une instance lorsqu'un test vérifie un filtre.
	local function has(list: { any }, inst: any): boolean
		return table.find(list, inst) ~= nil
	end

	T.describe("MapGeometry.clips", function()
		T.it("trouve les murs d'air dans Geometry.Clips", function()
			local map, parts = fakeMap()
			T.expectEqual(MapGeometry.clips(map), parts.clips)
		end)

		T.it("ne lit pas un dossier Clips à la racine de la map (ancien chemin des bots)", function()
			local map = make("Model", "Map", nil)
			make("Folder", "Clips", map)
			T.expectEqual(MapGeometry.clips(map), nil)
		end)
	end)

	T.describe("MapGeometry.bulletTransparent", function()
		T.it("liste les murs d'air et les seuls grillages passbullets", function()
			local map, parts = fakeMap()
			local list = MapGeometry.bulletTransparent(map)
			T.expectEqual(#list, 2)
			T.expect(has(list, parts.clips), "murs d'air")
			T.expect(has(list, parts.fence), "grillage passbullets")
			T.expect(not has(list, parts.post), "poteau chainlink gardé")
			T.expect(not has(list, parts.crate), "caisse gardée")
		end)

		T.it("ne liste pas deux fois une pièce passbullets rangée dans les murs d'air", function()
			local map, parts = fakeMap()
			make("Part", "Clip", parts.clips):SetAttribute("Group", "passbullets_chainlink")
			T.expectEqual(#MapGeometry.bulletTransparent(map), 2)
		end)

		T.it("calcule la liste une fois par map, figée (partagée par tous les rayons)", function()
			local map = fakeMap()
			T.expectEqual(MapGeometry.bulletTransparent(map), MapGeometry.bulletTransparent(map))
			T.expect(table.isfrozen(MapGeometry.bulletTransparent(map)), "liste modifiable")
		end)

		T.it("rend une liste vide pour une map sans Geometry", function()
			T.expectEqual(#MapGeometry.bulletTransparent(make("Model", "Vide", nil)), 0)
		end)
	end)

	T.describe("MapGeometry.seeThrough", function()
		T.it("traverse les murs d'air (à toute profondeur) et les grillages passbullets, pas le reste", function()
			local map, parts = fakeMap()
			local skip = MapGeometry.seeThrough(map)
			T.expect(skip(parts.clips:FindFirstChild("Clip")), "mur d'air")
			T.expect(skip(parts.fence), "grillage passbullets")
			T.expect(not skip(parts.post), "poteau chainlink")
			T.expect(not skip(parts.crate), "caisse")
			T.expect(not skip(parts.floors:FindFirstChild("floor")), "sol")
		end)
	end)

	T.describe("MapGeometry.castThrough", function()
		-- Cette méthode permet de simuler un raycast sur l'axe X lorsqu'un test place des obstacles : chaque obstacle
		-- { x, inst } est touché si le rayon (origine, longueur) le rencontre en avançant ; appels notés dans `calls`.
		local function fakeCast(obstacles, calls)
			return function(from: Vector3, delta: Vector3)
				table.insert(calls, from.X)
				local best
				for _, o in obstacles do
					if o.x >= from.X and o.x <= from.X + delta.X and (not best or o.x < best.x) then
						best = o
					end
				end
				return best and { Instance = best.inst, Position = Vector3.new(best.x, 0, 0) }
			end
		end
		local CLIP, WALL = { name = "clip" }, { name = "wall" }
		-- Cette méthode permet de reconnaître les pièces traversées lorsqu'un test lance un rayon.
		local function skip(inst)
			return inst == CLIP
		end

		T.it("passe derrière un mur d'air et s'arrête sur le mur suivant", function()
			local calls = {}
			local hit = MapGeometry.castThrough(
				fakeCast({ { x = 3, inst = CLIP }, { x = 7, inst = WALL } }, calls),
				Vector3.zero,
				Vector3.new(10, 0, 0),
				skip
			)
			T.expectEqual(hit and hit.Instance, WALL)
			T.expectEqual(#calls, 2)
			T.expectNear(calls[2], 3 + MapGeometry.PASS_STEP, 1e-4)
		end)

		T.it("rend nil quand seuls des murs d'air sont sur le chemin", function()
			local calls = {}
			local cast = fakeCast({ { x = 2, inst = CLIP }, { x = 5, inst = CLIP } }, calls)
			T.expectEqual(MapGeometry.castThrough(cast, Vector3.zero, Vector3.new(10, 0, 0), skip), nil)
			T.expectEqual(#calls, 3)
		end)

		T.it("rend le premier obstacle solide sans relancer", function()
			local calls = {}
			local cast = fakeCast({ { x = 4, inst = WALL }, { x = 6, inst = CLIP } }, calls)
			local hit = MapGeometry.castThrough(cast, Vector3.zero, Vector3.new(10, 0, 0), skip)
			T.expectEqual(hit and hit.Instance, WALL)
			T.expectEqual(#calls, 1)
		end)

		T.it("ne dépasse pas la longueur du rayon après un mur d'air au bout", function()
			local calls = {}
			local cast = fakeCast({ { x = 10, inst = CLIP } }, calls)
			T.expectEqual(MapGeometry.castThrough(cast, Vector3.zero, Vector3.new(10, 0, 0), skip), nil)
			T.expectEqual(#calls, 1)
		end)
	end)

	T.describe("MapGeometry.missingFolders", function()
		T.it("ne signale rien pour une map complète", function()
			T.expectEqual(#MapGeometry.missingFolders(fakeMap()), 0)
		end)

		T.it("signale un dossier renommé par son chemin", function()
			local map, parts = fakeMap()
			parts.clips.Name = "PlayerClips"
			map:FindFirstChild("Ladders"):Destroy()
			local missing = MapGeometry.missingFolders(map)
			T.expectEqual(#missing, 2)
			T.expect(has(missing, "Geometry.Clips"), "Geometry.Clips")
			T.expect(has(missing, "Ladders"), "Ladders")
		end)

		T.it("reprend les noms de dossiers des autres modules", function()
			T.expectEqual(MapGeometry.LADDERS, LadderRules.LADDERS_FOLDER)
			T.expectEqual(MapGeometry.RAMPS, BotConfig.RAMPS_FOLDER)
		end)
	end)
end

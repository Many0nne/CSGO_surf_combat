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

		T.it("calcule la liste une fois par map", function()
			local map = fakeMap()
			T.expectEqual(MapGeometry.bulletTransparent(map), MapGeometry.bulletTransparent(map))
		end)

		T.it("rend une liste vide pour une map sans Geometry", function()
			T.expectEqual(#MapGeometry.bulletTransparent(make("Model", "Vide", nil)), 0)
		end)
	end)

	T.describe("MapGeometry.includeAllBut", function()
		T.it("garde tout sauf les murs d'air et les grillages, en détaillant seulement leurs ancêtres", function()
			local map, parts = fakeMap()
			local include = MapGeometry.includeAllBut(map, MapGeometry.bulletTransparent(map))
			local geometry = map:FindFirstChild("Geometry")
			T.expect(has(include, parts.floors), "sols gardés entiers")
			T.expect(has(include, geometry:FindFirstChild("Ramps")), "rampes gardées")
			T.expect(has(include, parts.post) and has(include, parts.crate), "décor solide gardé pièce par pièce")
			T.expect(has(include, map:FindFirstChild("GroundSpawns")), "autres dossiers de la map gardés")
			T.expect(not has(include, parts.clips), "murs d'air écartés")
			T.expect(not has(include, parts.fence), "grillage écarté")
			T.expect(not has(include, geometry) and not has(include, parts.decor), "ancêtres détaillés, pas inclus")
			T.expectEqual(#include, 6)
		end)

		T.it("garde entière une pièce solide qui contient un élément écarté", function()
			local map, parts = fakeMap()
			local fenceInPost = make("Part", "block", parts.post)
			local include = MapGeometry.includeAllBut(map, { fenceInPost })
			T.expect(has(include, parts.decor) == false, "décor détaillé")
			T.expect(has(include, parts.post), "poteau gardé")
		end)

		T.it("garde la map entière depuis Workspace.Maps quand rien n'est écarté", function()
			local maps = make("Folder", "Maps", nil)
			local map = make("Model", "Dizzy", maps)
			local include = MapGeometry.includeAllBut(maps, {})
			T.expectEqual(#include, 1)
			T.expectEqual(include[1], map)
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

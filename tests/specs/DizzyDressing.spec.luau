return function(T, Loader)
	local DizzyDressing = Loader.new():require("tools/map/DizzyDressing")

	-- Cette méthode permet d'ajouter une pièce ancrée dans un dossier de la géométrie lorsqu'un test monte une map.
	local function part(folder, pos, size, group)
		local p = Instance.new("Part")
		p.CFrame = CFrame.new(pos)
		p.Size = size
		p.CanCollide = true
		p.CanQuery = true
		if group then
			p:SetAttribute("Group", group)
		end
		p.Parent = folder
		return p
	end

	-- Cette méthode permet de construire une petite map (Geometry avec Decor, Walls, Ramps) et ses pièces repères.
	local function map()
		local m = Instance.new("Model")
		local g = Instance.new("Folder")
		g.Name = "Geometry"
		g.Parent = m
		local f = {}
		for _, name in { "Decor", "Walls", "Ramps" } do
			f[name] = Instance.new("Folder")
			f[name].Name = name
			f[name].Parent = g
		end
		Instance.new("Folder").Parent = f.Walls -- un enfant qui n'est pas une pièce ne doit rien casser
		return m,
			{
				near = part(f.Walls, Vector3.new(3, 0, 0), Vector3.new(1, 1, 1)),
				slope = part(f.Ramps, Vector3.new(0, 0, -4), Vector3.new(1, 1, 1)),
				outside = part(f.Walls, Vector3.new(6, 0, 6), Vector3.new(1, 1, 1)),
				big = part(f.Walls, Vector3.new(1, 0, 0), Vector3.new(20, 10, 1)),
				plate = part(f.Decor, Vector3.new(0, 0, 0), Vector3.new(4, 0.3, 4), "metal"),
				other = part(f.Decor, Vector3.new(0.5, 0, 0), Vector3.new(1, 1, 1), "rock"),
			}
	end

	-- Cette méthode permet de lancer redress avec une liste de rhabillages de test, puis de remettre la vraie liste.
	local function redress(m, list)
		local saved = DizzyDressing.REDRESS
		DizzyDressing.REDRESS = list
		local dressing = Instance.new("Folder")
		local ok, result = pcall(DizzyDressing.redress, m, dressing)
		DizzyDressing.REDRESS = saved
		return ok, result, dressing
	end

	T.describe("DizzyDressing.redress (hide)", function()
		T.it("masque les petites pièces d'une zone ronde dans les dossiers visés, collision gardée", function()
			local m, p = map()
			local ok, n, dressing = redress(m, {
				{
					kind = "hide",
					folders = { "Walls", "Ramps" },
					maxVolume = 100,
					why = "bobine",
					zone = { center = { 0, 0, 0 }, radius = 5, size = { 20, 4, 20 } },
				},
			})
			T.expect(ok, tostring(n))
			T.expectEqual(n, 2)
			T.expectEqual(p.near.Transparency, 1)
			T.expectEqual(p.slope.Transparency, 1)
			T.expect(p.near.CanCollide and p.near.CanQuery, "la collision doit rester")
			T.expectEqual(p.near:GetAttribute("Redress"), "bobine")
			-- hors du rayon (dans la boîte), trop grosse, ou dans un dossier non visé : intactes
			T.expectEqual(p.outside.Transparency, 0)
			T.expectEqual(p.big.Transparency, 0)
			T.expectEqual(p.plate.Transparency, 0)
			T.expectEqual(#dressing:GetChildren(), 0)
		end)

		T.it("vise Decor par défaut et filtre par groupe source", function()
			local m, p = map()
			local ok, n = redress(m, {
				{ kind = "hide", group = "metal", why = "joues", zone = { center = { 0, 0, 0 }, size = { 3, 3, 3 } } },
			})
			T.expect(ok, tostring(n))
			T.expectEqual(n, 1)
			T.expectEqual(p.plate.Transparency, 1)
			T.expectEqual(p.other.Transparency, 0)
			T.expectEqual(p.near.Transparency, 0)
		end)

		T.it("arrête la génération si une zone ne contient rien", function()
			local m = map()
			local ok = redress(m, {
				{ kind = "hide", group = "metal", why = "vide", zone = { center = { 100, 0, 0 }, size = { 1, 1, 1 } } },
			})
			T.expect(not ok, "une zone vide doit lever une erreur")
		end)
	end)
end

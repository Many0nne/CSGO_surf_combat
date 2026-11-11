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

	-- Cette méthode permet de vérifier qu'aucune pièce d'un habillage ne bloque les raycasts du mouvement ni les joueurs.
	local function ghostsOnly(dressing)
		local n = 0
		for _, d in dressing:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
				if d.CanCollide or d.CanQuery then
					return false, d.Name
				end
			end
		end
		return n > 0, "aucune pièce"
	end

	T.describe("DizzyDressing.redress (lot #187)", function()
		T.it(
			"rhabille une clôture : grillage en texture des deux côtés, panneau invisible, collision d'origine gardée",
			function()
				local m = map()
				local panel = part(
					m:FindFirstChild("Geometry"):FindFirstChild("Decor"),
					Vector3.new(0, 20, 0),
					Vector3.new(0.5, 22.8, 65),
					"passbullets_chainlink"
				)
				panel.Transparency = 0.55
				local ok, n, dressing = redress(m, {
					{
						kind = "fence",
						group = "passbullets_chainlink",
						why = "clôture",
						zone = { center = { 0, 20, 0 }, size = { 2, 2, 2 } },
					},
				})
				T.expect(ok, tostring(n))
				T.expectEqual(n, 1)
				T.expectEqual(panel.Transparency, 1)
				T.expect(panel.CanCollide and panel.CanQuery, "la clôture relevée garde sa collision")
				local faces = {}
				for _, t in dressing:GetDescendants() do
					if t:IsA("Texture") then
						T.expectEqual(t.Texture, DizzyDressing.CHAINLINK)
						T.expectEqual(t.Parent.Transparency, 1)
						faces[t.Face.Name] = true
					end
				end
				T.expect(faces.Front and faces.Back, "grillage visible des deux côtés")
				T.expect(DizzyDressing.CHAINLINK ~= "rbxassetid://0", "id de l'image du grillage à renseigner")
				local ghosts, why = ghostsOnly(dressing)
				T.expect(ghosts, tostring(why))
			end
		)

		T.it("rhabille fûts et parpaings sans pièce qui accroche le mouvement", function()
			local m = map()
			part(
				m:FindFirstChild("Geometry"):FindFirstChild("Decor"),
				Vector3.new(0, 10, 0),
				Vector3.new(7.1, 8, 7.1),
				"rock"
			)
			part(
				m:FindFirstChild("Geometry"):FindFirstChild("Decor"),
				Vector3.new(0, 30, 0),
				Vector3.new(2.5, 5.6, 1.8),
				"rock"
			)
			local ok, n, dressing = redress(m, {
				{
					kind = "barrel",
					group = "rock",
					minVolume = 300,
					why = "fût",
					zone = { center = { 0, 10, 0 }, size = { 2, 2, 2 } },
				},
				{
					kind = "hollowblock",
					group = "rock",
					maxVolume = 40,
					why = "parpaing",
					zone = { center = { 0, 30, 0 }, size = { 2, 2, 2 } },
				},
			})
			T.expect(ok, tostring(n))
			T.expectEqual(n, 2)
			local ghosts, why = ghostsOnly(dressing)
			T.expect(ghosts, tostring(why))
			-- parpaing debout : cloisons dans l'axe le plus long (vertical ici), aucune pièce hors de la boîte relevée
			for _, d in dressing:GetDescendants() do
				if d:IsA("BasePart") and d.Parent.Name == "CinderBlock" then
					T.expect(math.abs(d.CFrame.Position.Y - 30) <= 2.81, "cloison hors de la boîte")
				end
			end
		end)
	end)

	T.describe("DizzyDressing.minus (pans de bardage percés, #189)", function()
		T.it("couvre exactement le pan moins les ouvertures, sans recouvrement", function()
			local pan = { x0 = -10, x1 = 10, y0 = 0, y1 = 8 }
			local holes = {
				{ x0 = -6, x1 = -2, y0 = 3, y1 = 6 }, -- baie au milieu
				{ x0 = 5, x1 = 12, y0 = 7, y1 = 9 }, -- encoche en haut à droite, qui déborde du pan
			}
			local rects = DizzyDressing.minus(pan, holes)
			local area = 0
			for i, r in rects do
				area += (r.x1 - r.x0) * (r.y1 - r.y0)
				for _, h in holes do
					local inside = r.x0 < h.x1 and r.x1 > h.x0 and r.y0 < h.y1 and r.y1 > h.y0
					T.expect(not inside, "un morceau couvre une ouverture")
				end
				for j = i + 1, #rects do
					local o = rects[j]
					T.expect(not (r.x0 < o.x1 and r.x1 > o.x0 and r.y0 < o.y1 and r.y1 > o.y0), "morceaux superposés")
				end
			end
			T.expect(math.abs(area - (160 - 12 - 5)) < 1e-6, "aire " .. area)
		end)

		T.it("rend le pan entier sans ouverture", function()
			local rects = DizzyDressing.minus({ x0 = 0, x1 = 4, y0 = 0, y1 = 2 }, {})
			T.expectEqual(#rects, 1)
		end)
	end)

	T.describe("DizzyDressing.paintBands (#189)", function()
		-- Cette méthode permet de lancer paintBands avec une liste de bandes de test, puis de remettre la vraie liste.
		local function paint(m, list)
			local saved = DizzyDressing.BANDS
			DizzyDressing.BANDS = list
			local ok, result = pcall(DizzyDressing.paintBands, m, Vector3.new(0, 0, 0))
			DizzyDressing.BANDS = saved
			return ok, result
		end

		T.it("découpe les murs traversés en trois, bande au milieu, même emprise, côté CT compris", function()
			local m = map()
			local walls = m:FindFirstChild("Geometry"):FindFirstChild("Walls")
			for _, c in walls:GetChildren() do
				c:Destroy()
			end
			part(walls, Vector3.new(0, 5, 0), Vector3.new(10, 10, 1)) -- traversé par la bande
			part(walls, Vector3.new(0, 20, 0), Vector3.new(10, 4, 1)) -- au-dessus de la bande
			-- symétrique par le demi-tour autour de (0, CENTER_Z)
			part(walls, Vector3.new(0, 5, 2 * DizzyDressing.CENTER_Z), Vector3.new(10, 10, 1))
			local ok, n = paint(m, { { why = "test", x = { -1, 1 }, z = { -1, 1 }, y = { 3, 5 } } })
			T.expect(ok, tostring(n))
			T.expectEqual(n, 2)
			local band, bottom, top, height = 0, math.huge, -math.huge, 0
			for _, p in walls:GetChildren() do
				local y = p.CFrame.Position.Y
				if p.CFrame.Position.Z == 0 and y < 15 then
					bottom = math.min(bottom, y - p.Size.Y / 2)
					top = math.max(top, y + p.Size.Y / 2)
					height += p.Size.Y
					if p:GetAttribute("Band") then
						band += 1
						T.expectEqual(p.Color, DizzyDressing.FACADE_BLUE)
						T.expect(math.abs(y - 4) < 1e-6 and math.abs(p.Size.Y - 2) < 1e-6, "bande mal placée")
						T.expect(p.CanCollide and p.CanQuery, "la bande garde la collision du mur")
					end
				end
			end
			T.expectEqual(band, 1)
			T.expect(math.abs(bottom) < 1e-6 and math.abs(top - 10) < 1e-6 and math.abs(height - 10) < 1e-6, "emprise")
			T.expectEqual(#walls:GetChildren(), 7) -- 3 + 3 morceaux, le mur du dessus intact
		end)

		T.it("arrête la génération si une emprise ne coupe aucun mur", function()
			local m = map()
			local ok = paint(m, { { why = "vide", unique = true, x = { 50, 60 }, z = { 50, 60 }, y = { 0, 1 } } })
			T.expect(not ok, "une emprise vide doit lever une erreur")
		end)
	end)
end

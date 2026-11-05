return function(T, Loader)
	local DizzyPatches = Loader.new():require("tools/map/DizzyPatches")

	-- Cette méthode permet de construire une petite géométrie de map (dossiers Walls et Clips) pour les retouches.
	local function geometry()
		local g = Instance.new("Folder")
		for _, spec in
			{ { "Walls", Vector3.new(0, 0, 0) }, { "Walls", Vector3.new(50, 0, 0) }, { "Clips", Vector3.new(0, 0, 0) } }
		do
			local folder = g:FindFirstChild(spec[1]) or Instance.new("Folder")
			folder.Name = spec[1]
			folder.Parent = g
			local p = Instance.new("Part")
			p.CFrame = CFrame.new(spec[2])
			p.Parent = folder
		end
		return g
	end

	local styled = {}
	-- Cette méthode permet de simuler l'habillage du générateur lorsqu'une retouche ajoute ou rhabille une pièce.
	local function style(part, look)
		part.Name = look
		table.insert(styled, look)
	end

	local zone = { center = { 0, 0, 0 }, size = { 4, 4, 4 } }

	T.describe("DizzyPatches.validate", function()
		T.it("accepte une liste vide et des retouches complètes", function()
			T.expectEqual(#DizzyPatches.validate({}), 0)
			T.expectEqual(#DizzyPatches.validate({
				{ op = "remove", why = "a", zone = zone, folder = "Clips" },
				{ op = "add", why = "b", position = { 1, 2, 3 }, size = { 1, 1, 1 }, look = "wall" },
				{ op = "restyle", why = "c", zone = zone, look = "decor:metal" },
			}), 0)
		end)

		T.it("refuse une retouche sans raison, une op inconnue ou un dossier inconnu", function()
			T.expectEqual(#DizzyPatches.validate({ { op = "remove", zone = zone } }), 1)
			T.expectEqual(#DizzyPatches.validate({ { op = "move", why = "x" } }), 1)
			T.expectEqual(#DizzyPatches.validate({ { op = "remove", why = "x", zone = zone, folder = "Murs" } }), 1)
		end)

		T.it("refuse un ajout mal formé", function()
			T.expectEqual(#DizzyPatches.validate({
				{ op = "add", why = "x", position = { 1, 2 }, size = { 1, 1, 1 }, look = "wall" },
			}), 1)
			T.expectEqual(
				#DizzyPatches.validate({ { op = "add", why = "x", position = { 1, 2, 3 }, size = { 1, 1, 1 } } }),
				1
			)
			T.expectEqual(#DizzyPatches.validate({
				{ op = "add", why = "x", position = { 1, 2, 3 }, size = { 1, 1, 1 }, look = "wall", kind = "Ball" },
			}), 1)
		end)
	end)

	T.describe("DizzyPatches.inZone", function()
		T.it("garde les points dans la boîte, bords compris", function()
			T.expectEqual(DizzyPatches.inZone(Vector3.new(2, -2, 0), zone), true)
			T.expectEqual(DizzyPatches.inZone(Vector3.new(2.1, 0, 0), zone), false)
		end)
	end)

	T.describe("DizzyPatches.apply", function()
		T.it("retire seulement les pièces de la zone et du dossier demandé", function()
			local g = geometry()
			local counts =
				DizzyPatches.apply(g, { { op = "remove", why = "mur d'air", zone = zone, folder = "Clips" } }, style)
			T.expectEqual(counts[1], 1)
			T.expectEqual(#g.Clips:GetChildren(), 0)
			T.expectEqual(#g.Walls:GetChildren(), 2)
		end)

		T.it("ajoute une pièce habillée, rangée selon son habillage et marquée", function()
			local g = geometry()
			DizzyPatches.apply(g, {
				{
					op = "add",
					why = "fente",
					position = { 5, 6, 7 },
					size = { 2, 8, 2 },
					look = "wall",
					kind = "WedgePart",
				},
			}, style)
			local added = g.Walls:FindFirstChild("wall")
			T.expectEqual(added ~= nil, true)
			T.expectEqual(added.ClassName, "WedgePart")
			T.expectEqual(added.CFrame.Position, Vector3.new(5, 6, 7))
			T.expectEqual(added:GetAttribute("Patch"), "fente")
		end)

		T.it("range un ajout de décor dans Decor, créé au besoin", function()
			local g = geometry()
			DizzyPatches.apply(
				g,
				{ { op = "add", why = "caisse", position = { 0, 4, 0 }, size = { 8, 8, 8 }, look = "decor:metal" } },
				style
			)
			T.expectEqual(#g.Decor:GetChildren(), 1)
		end)

		T.it("rhabille les pièces de la zone", function()
			local g = geometry()
			table.clear(styled)
			local counts =
				DizzyPatches.apply(g, { { op = "restyle", why = "teinte", zone = zone, look = "ceiling" } }, style)
			T.expectEqual(counts[1], 2)
			T.expectEqual(#styled, 2)
		end)

		T.it("limite une retouche au groupe source demandé", function()
			local g = geometry()
			local decor = Instance.new("Folder")
			decor.Name = "Decor"
			decor.Parent = g
			for _, group in { "metal", "stucco" } do
				local p = Instance.new("Part")
				p.CFrame = CFrame.new(0, 0, 0)
				p:SetAttribute("Group", group)
				p.Parent = decor
			end
			local counts = DizzyPatches.apply(
				g,
				{ { op = "remove", why = "structure", zone = zone, folder = "Decor", group = "metal" } },
				style
			)
			T.expectEqual(counts[1], 1)
			T.expectEqual(decor:GetChildren()[1]:GetAttribute("Group"), "stucco")
			T.expectEqual(#DizzyPatches.validate({ { op = "remove", why = "x", zone = zone, group = 3 } }), 1)
		end)

		T.it("lève une erreur sur une zone vide ou une liste invalide", function()
			local g = geometry()
			local far = { center = { 500, 0, 0 }, size = { 1, 1, 1 } }
			T.expectEqual(pcall(DizzyPatches.apply, g, { { op = "remove", why = "rien", zone = far } }, style), false)
			T.expectEqual(pcall(DizzyPatches.apply, g, { { op = "remove", zone = zone } }, style), false)
		end)
	end)
end

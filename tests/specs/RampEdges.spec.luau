return function(T, Loader)
	local loader = Loader.new()
	local RampEdges = loader:require("tools/map/RampEdges")
	local RampCheck = loader:require("tools/map/RampCheck")

	-- rampe d'essai : pente à 60°, normale (0, 0,5, -0,866), longueur le long de X
	local ROT = CFrame.Angles(math.rad(-60), 0, 0)
	local RAISE = 0.3 -- bande de rive plus haute que la dalle principale, comme sur ar_dizzy

	-- Cette méthode permet de poser une pièce ancrée dans un dossier lorsqu'un test construit une scène.
	local function part(parent, class, cf, size, name)
		local p = Instance.new(class)
		p.Anchored = true
		p.CFrame = cf
		p.Size = size
		p.Name = name
		p.Parent = parent
		return p
	end

	-- Scène : dalle principale, rive relevée, tranche de mur et coin au bout, dalle horizontale qui perce le bas de la
	-- pente et déborde en longueur, mur d'air d'un seul tenant, bloc au loin. `poke` : dépassement des murs du bout.
	-- Cette méthode permet de construire la map d'essai lorsqu'un test a besoin d'une rampe complète.
	local function scene(poke)
		poke = poke or 0.03
		local map = Instance.new("Model")
		local geometry = Instance.new("Folder")
		geometry.Name = "Geometry"
		geometry.Parent = map
		local folders = {}
		for _, name in { "Ramps", "Walls", "Ceilings", "Decor", "Clips" } do
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = geometry
			folders[name] = f
		end
		part(folders.Ramps, "Part", ROT, Vector3.new(100, 2, 80), "main")
		part(
			folders.Ramps,
			"Part",
			CFrame.new(53, 0, 0) * ROT * CFrame.new(0, RAISE, 0),
			Vector3.new(6, 2, 80),
			"strip"
		)
		-- tranche de mur au bout (posée sur sa face, sans retrait), au-dessus de la rive
		part(
			folders.Walls,
			"Part",
			CFrame.new(55.5, 0, 0) * ROT * CFrame.new(0, 1 + RAISE + poke - 1.5, 0),
			Vector3.new(1, 3, 80),
			"endwall"
		)
		part(
			folders.Walls,
			"WedgePart",
			CFrame.new(-49.5, 0, 0) * ROT * CFrame.new(0, 1 + RAISE + poke - 1.5, 10),
			Vector3.new(1, 3, 40),
			"endwedge"
		)
		-- bas de la pente (bord -Z local de la dalle) : dalle horizontale épaisse qui perce la surface, plus longue que
		-- la rampe
		local foot = (ROT * CFrame.new(0, 1, -40)).Position
		part(
			folders.Ramps.Parent.Ceilings,
			"Part",
			CFrame.new(foot.X, foot.Y - 0.2, foot.Z - 1),
			Vector3.new(130, 1.2, 6),
			"ceiling"
		)
		-- mur d'air (invisible) d'un seul tenant sur toute la longueur, dessus au niveau de la rive : gardé tel quel
		local clip = part(
			folders.Clips,
			"Part",
			CFrame.new(3, 0, 0) * ROT * CFrame.new(0, 1 + RAISE - 0.3, 0),
			Vector3.new(106, 0.6, 80),
			"clip"
		)
		clip.Transparency = 1
		-- bloc loin au-dessus de la rampe, le long de sa normale : pas un rebord
		local far = (ROT * CFrame.new(0, 30, 0)).Position
		part(folders.Decor, "Part", CFrame.new(far), Vector3.new(4, 4, 4), "far")
		return map, folders
	end

	-- Cette méthode permet de savoir si un point est dans une pièce (boîte RampCheck.box, coin compris), à eps près.
	local function inside(b, p, eps)
		local d = { p.X - b.px, p.Y - b.py, p.Z - b.pz }
		local x = d[1] * b.xx + d[2] * b.xy + d[3] * b.xz
		local y = d[1] * b.yx + d[2] * b.yy + d[3] * b.yz
		local z = d[1] * b.zx + d[2] * b.zy + d[3] * b.zz
		if math.abs(x) > b.sx / 2 + eps or math.abs(y) > b.sy / 2 + eps or math.abs(z) > b.sz / 2 + eps then
			return false
		end
		return not b.wedge or y * b.sz - z * b.sy <= eps * (b.sy + b.sz)
	end

	-- Cette méthode permet de vérifier qu'une pièce rognée est exactement l'originale moins la zone au-dessus de la
	-- surface : points tirés dans l'originale, loin des bords de la découpe (incertains à l'arrondi près).
	local function expectExactCut(name, orig, pieces, ramp, surface)
		local cut = surface - RampEdges.SKIN
		-- repère direct (X × Y = Z) : Roblox ne sait pas poser un repère retourné
		for _, b in pieces do
			local cx = b.xy * b.yz - b.xz * b.yy
			local cy = b.xz * b.yx - b.xx * b.yz
			local cz = b.xx * b.yy - b.xy * b.yx
			T.expect(cx * b.zx + cy * b.zy + cz * b.zz > 0.999, name .. " : repère retourné")
		end
		local cf = CFrame.fromMatrix(
			Vector3.new(orig.px, orig.py, orig.pz),
			Vector3.new(orig.xx, orig.xy, orig.xz),
			Vector3.new(orig.yx, orig.yy, orig.yz),
			Vector3.new(orig.zx, orig.zy, orig.zz)
		)
		local checked, removed = 0, 0
		for i = 0, 10 do
			for j = 0, 10 do
				for k = 0, 10 do
					local p = cf
						* Vector3.new(
							(i / 10 - 0.5) * orig.sx * 0.98,
							(j / 10 - 0.5) * orig.sy * 0.98,
							(k / 10 - 0.5) * orig.sz * 0.98
						)
					local q = { p.X, p.Y, p.Z }
					local u, v, h = RampCheck.dot(q, ramp.u), RampCheck.dot(q, ramp.v), RampCheck.dot(q, ramp.n)
					local near = math.abs(h - cut) < 0.01
						or math.abs(v - ramp.v0) < 0.01
						or math.abs(v - ramp.v1) < 0.01
						or math.abs(u - ramp.u0) < 0.01
						or math.abs(u - ramp.u1) < 0.01
					if inside(orig, p, -1e-3) and not near then
						local gone = h > cut and v > ramp.v0 and v < ramp.v1 and u > ramp.u0 and u < ramp.u1
						local found = false
						for _, b in pieces do
							if inside(b, p, 1e-3) then
								found = true
							end
						end
						T.expect(
							found ~= gone,
							string.format("point (%.2f, %.2f, %.2f) : gardé=%s", p.X, p.Y, p.Z, tostring(found))
						)
						checked += 1
						if gone then
							removed += 1
						end
					end
				end
			end
		end
		T.expect(
			checked > 50 and removed > 0,
			string.format("%s : échantillonnage trop pauvre (%d, %d)", name, checked, removed)
		)
	end

	T.describe("RampEdges.clip", function()
		T.it("coupe un carré par un demi-plan et garde l'aire attendue", function()
			local square = { { 0, 0 }, { 2, 0 }, { 2, 2 }, { 0, 2 } }
			T.expectNear(RampEdges.area(square), 4)
			T.expectNear(RampEdges.area(RampEdges.clip(square, 0, 1, 0.5)), 1)
			T.expectNear(RampEdges.area(RampEdges.clip(square, 1, 1, 2)), 2)
			T.expectEqual(#RampEdges.clip(square, 0, 1, -1), 0)
		end)
	end)

	T.describe("RampEdges.wedges", function()
		T.it("un triangle de section devient des coins qui le couvrent exactement", function()
			local ramp = { u = { 1, 0, 0 }, v = { 0, 0, 1 }, n = { 0, 1, 0 } }
			local tri = { { 0, 0 }, { 4, 0 }, { 1, 3 } }
			local ws = RampEdges.wedges(tri, ramp, 0, 2)
			T.expectEqual(#ws, 2)
			local area = 0
			for _, w in ws do
				area += w.size.Y * w.size.Z / 2
				T.expectNear(w.size.X, 2)
			end
			T.expectNear(area, 6)
		end)
	end)

	T.describe("RampEdges.apply", function()
		T.it(
			"peau au niveau de la rive sur toute l'emprise, rien ne dépasse, mur d'air et bloc lointain intacts",
			function()
				local map, folders = scene()
				local main = folders.Ramps:FindFirstChild("main")
				local topBefore = select(2, RampCheck.topFace(RampCheck.box(main)))
				local report = RampEdges.apply(map.Geometry)
				T.expectEqual(#report, 1)
				T.expectNear(report[1].surface, RAISE, 1e-4)
				-- dalle principale, rive, tranche, coin, plafond
				T.expectEqual(report[1].trimmed, 5)
				local skins = {}
				for _, p in folders.Ramps:GetChildren() do
					if p:GetAttribute(RampEdges.ATTRIBUTE) == "peau d'acier continue de la rampe" then
						table.insert(skins, p)
					end
				end
				T.expectEqual(#skins, 1)
				T.expectNear(select(2, RampCheck.topFace(RampCheck.box(skins[1]))) - topBefore, RAISE, 1e-4)
				T.expectNear(skins[1].Size.X, 106, 1e-3)
				T.expectNear(skins[1].Size.Y, RampEdges.SKIN, 1e-4)
				local clips = folders.Clips:GetChildren()
				T.expectEqual(#clips, 1)
				T.expect(
					clips[1]:GetAttribute(RampEdges.ATTRIBUTE) == nil,
					"le mur d'air d'un seul tenant ne doit pas être rogné"
				)
				T.expect(folders.Decor:FindFirstChild("far") ~= nil, "le bloc au loin ne doit pas être touché")
				local _, worst = RampCheck.check(map)
				T.expect(worst <= RampCheck.TOL, "dépassement restant " .. worst)
			end
		)

		T.it("un poteau qui traverse la rampe arrête la génération au lieu d'être rogné", function()
			local map, folders = scene()
			part(
				folders.Decor,
				"Part",
				CFrame.new(10, 0, 0) * ROT * CFrame.new(0, 1, 0),
				Vector3.new(2, 6, 2),
				"pillar"
			)
			local ok, err = pcall(RampEdges.apply, map.Geometry)
			T.expect(not ok and string.find(tostring(err), "traverse") ~= nil, tostring(err))
		end)

		T.it("la découpe est exacte (dalles d'acier, boîte débordant en longueur, tranche de mur, coin)", function()
			local map, folders = scene(0.8)
			local surf = {}
			for _, p in folders.Ramps:GetChildren() do
				table.insert(surf, RampCheck.box(p))
			end
			local ramp = RampCheck.ramps(surf)[1]
			local surface = ramp.top + RAISE
			local before = {}
			for _, name in { "main", "strip", "endwall", "endwedge", "ceiling" } do
				local p = map:FindFirstChild(name, true)
				before[name] = RampCheck.box(p)
			end
			RampEdges.apply(map.Geometry)
			for name, orig in before do
				T.expect(map:FindFirstChild(name, true) ~= nil, name .. " : aucun morceau")
				local pieces = {}
				for _, p in map:GetDescendants() do
					local tag = p:GetAttribute(RampEdges.ATTRIBUTE)
					if p:IsA("BasePart") and p.Name == name and tag ~= "peau d'acier continue de la rampe" then
						T.expect(p:GetAttribute(RampEdges.ATTRIBUTE) ~= nil, name .. " : morceau sans marque")
						table.insert(pieces, RampCheck.box(p))
					end
				end
				expectExactCut(name, orig, pieces, ramp, surface)
			end
		end)
	end)

	T.describe("RampCheck", function()
		T.it("mesure la rive relevée avant correction, rien après", function()
			local map = scene()
			local lines, worst = RampCheck.check(map)
			T.expect(worst > RAISE - 0.05, "rebord non vu : " .. table.concat(lines, " | "))
			RampEdges.apply(map.Geometry)
			local _, after = RampCheck.check(map)
			T.expect(after <= RampCheck.TOL)
		end)

		T.it("signale un creux et un trou", function()
			local main = RampCheck.box(part(nil, "Part", ROT, Vector3.new(100, 2, 80), "main"))
			local strip = RampCheck.box(part(nil, "Part", CFrame.new(53, 0, 0) * ROT, Vector3.new(6, 2, 80), "strip"))
			local ramp = RampCheck.ramps({ main, strip })[1]
			-- trou : la rive n'est pas posée
			local holed = RampCheck.measure(ramp, { main })
			T.expect(#holed.holes > 0, "trou non vu")
			-- creux : la rive est 0,3 plus bas
			local low = RampCheck.box(
				part(nil, "Part", CFrame.new(53, 0, 0) * ROT * CFrame.new(0, -0.3, 0), Vector3.new(6, 2, 80), "low")
			)
			local dipped = RampCheck.measure(ramp, { main, low })
			T.expectNear(dipped.below, 0.3, 0.02)
			T.expectEqual(#dipped.holes, 0)
		end)

		T.it("une rampe de deux grandes dalles n'est comptée qu'une fois", function()
			local a = RampCheck.box(part(nil, "Part", ROT, Vector3.new(100, 2, 80), "a"))
			local b = RampCheck.box(part(nil, "Part", CFrame.new(100, 0, 0) * ROT, Vector3.new(100, 2, 80), "b"))
			local ramps = RampCheck.ramps({ a, b })
			T.expectEqual(#ramps, 1)
			T.expectNear(ramps[1].u1 - ramps[1].u0, 200, 1e-3)
		end)

		T.it("une petite dalle de surf n'est pas une rampe", function()
			local surf = { RampCheck.box(part(nil, "Part", ROT, Vector3.new(10, 2, 10), "chip")) }
			T.expectEqual(#RampCheck.ramps(surf), 0)
		end)
	end)
end

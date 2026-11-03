return function(T, Loader)
	local loader = Loader.new()
	local DuneField = loader:require("src/shared/DuneField")
	local MovementConfig = loader:require("src/shared/MovementConfig")

	-- anneau de l'Arène (tools/map/build_arena.luau) : demi-largeur, demi-longueur, largeur au sol de la rampe
	local RING = Vector3.new(120, 170, 55 / math.tan(math.rad(55)))
	local FLATS = { { 0, -30, 6 }, { -45, 100, 10 } }
	local STEP = 3

	-- Cette méthode permet de parcourir le sol de l'île sur une grille lorsqu'on vérifie une propriété partout.
	local function eachCell(fn: (number, number, number) -> ())
		for x = -RING.X, RING.X, STEP do
			for z = -(RING.Y + RING.X), RING.Y + RING.X, STEP do
				local h = DuneField.height(x, z, RING, FLATS)
				if h then
					fn(x, z, h)
				end
			end
		end
	end

	T.describe("DuneField.height", function()
		T.it("n'existe que dans l'anneau", function()
			T.expect(DuneField.height(0, 0, RING, FLATS) ~= nil, "centre de la place")
			T.expectEqual(DuneField.height(RING.X + 5, 0, RING, FLATS), nil)
			T.expectEqual(DuneField.height(0, RING.Y + RING.X + 5, RING, FLATS), nil)
		end)

		T.it("est déterministe", function()
			T.expectEqual(DuneField.height(37.5, -81.25, RING, FLATS), DuneField.height(37.5, -81.25, RING, FLATS))
		end)

		T.it("garde plates les zones demandées (points d'apparition, dalles)", function()
			T.expectNear(DuneField.height(0, -30, RING, FLATS) :: number, DuneField.FLOOR, 1e-6)
			T.expectNear(DuneField.height(-45, 100, RING, FLATS) :: number, DuneField.FLOOR, 1e-6)
		end)

		T.it("s'efface au pied des rampes pour ne jamais dépasser de leur surface", function()
			for z = -RING.Y, RING.Y, 10 do
				local toe = DuneField.height(RING.X - RING.Z, z, RING, FLATS) :: number
				T.expectNear(toe, DuneField.FLOOR, 1e-6, "pied de rampe en z = " .. z)
			end
		end)

		T.it("reste marchable partout (pente sous le seuil de surf)", function()
			local maxSlope = math.acos(MovementConfig.SURF_NORMAL_Y)
			local worst, at = 0, ""
			eachCell(function(x, z, h)
				local hx = DuneField.height(x + 0.5, z, RING, FLATS)
				local hz = DuneField.height(x, z + 0.5, RING, FLATS)
				if hx and hz then
					local slope = math.atan(math.sqrt(((hx - h) / 0.5) ^ 2 + ((hz - h) / 0.5) ^ 2))
					if slope > worst then
						worst, at = slope, string.format("(%d, %d)", x, z)
					end
				end
			end)
			T.expect(
				worst < maxSlope - math.rad(3),
				string.format("pente max %.1f° en %s, seuil %.1f°", math.deg(worst), at, math.deg(maxSlope))
			)
		end)

		T.it("alterne champs de dunes et couloirs plats", function()
			local cells, dunes, highest = 0, 0, 0
			eachCell(function(_, _, h)
				cells += 1
				if h > DuneField.FLOOR + 2 then
					dunes += 1
				end
				highest = math.max(highest, h)
			end)
			local share = dunes / cells
			T.expect(highest > 8, "aucune grande dune (max " .. highest .. ")")
			T.expect(highest <= DuneField.MAX_HEIGHT, "plus haut que MAX_HEIGHT")
			T.expect(share > 0.15 and share < 0.55, string.format("part du sol en dunes : %.0f %%", share * 100))
		end)
	end)
end

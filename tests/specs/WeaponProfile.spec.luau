return function(T, Loader)
	local WeaponProfile = Loader.new():require("src/shared/WeaponProfile")

	-- Cette méthode permet de comparer deux vecteurs à une tolérance près lorsqu'un repère vient d'une rotation.
	local function same(a: Vector3, b: Vector3): boolean
		return (a - b).Magnitude < 1e-4
	end

	-- Cette méthode permet de savoir de quel côté de l'image tombe la pointe (+1 droite, -1 gauche) et quelle face est
	-- vue, lorsqu'on pose une arme comme la vignette (caméra sur le +Z du profil) et comme l'aperçu du shop (profil
	-- ramené sur `at`, caméra devant `at`, sur son +Z).
	local function views(box: CFrame, size: Vector3, reference)
		local profile, extents = WeaponProfile.frame(box, size, reference)
		local tip = profile * Vector3.new(extents.X / 2, 0, 0)
		local camera = profile * CFrame.new(0, 0, 10)
		local thumb = camera:PointToObjectSpace(tip).X
		local at = CFrame.new(5, 2, -3) * CFrame.Angles(0, 0.4, 0)
		local placed = at * profile:Inverse()
		local stage = CFrame.lookAt(at * Vector3.new(0, 0, 12), at.Position, at.UpVector)
		local reveal = stage:PointToObjectSpace(placed * tip).X
		local faceThumb = profile.ZVector
		local faceReveal = placed:Inverse():VectorToWorldSpace(at.ZVector)
		return math.sign(thumb), math.sign(reveal), faceThumb, faceReveal
	end

	-- Boîtes de test : longueur le long de X (ordre direct des axes de la boîte), puis le long de Z (ordre circulaire),
	-- les deux cas où l'ancien aperçu tournait l'arme de 180° par rapport à la vignette
	local tilted = CFrame.new(1, 2, 3) * CFrame.Angles(0.3, -1.1, 0.7)
	local boxes = {
		{ name = "AWP (longueur en X)", size = Vector3.new(9.2, 1.8, 0.6) },
		{ name = "M9 (longueur en Z)", size = Vector3.new(0.93, 0.37, 3.72) },
		{ name = "longueur en Y", size = Vector3.new(0.4, 5, 1.2) },
	}

	T.describe("WeaponProfile.frame sans référence", function()
		for _, case in boxes do
			T.it("vignette et aperçu montrent la même face, pointe du même côté : " .. case.name, function()
				local thumb, reveal, faceThumb, faceReveal = views(tilted, case.size, nil)
				T.expectEqual(thumb, 1)
				T.expectEqual(reveal, 1)
				T.expectEqual(same(faceThumb, faceReveal), true)
			end)
		end

		T.it(
			"garde la pose des vignettes d'avant #429 (longueur à l'horizontale, haut = axe moyen, regard = plus mince)",
			function()
				local size = Vector3.new(0.93, 0.37, 3.72)
				local profile, extents = WeaponProfile.frame(tilted, size, nil)
				T.expectEqual(same(profile.Position, tilted.Position), true)
				T.expectEqual(same(profile.YVector, tilted.RightVector), true)
				T.expectEqual(same(profile.ZVector, tilted.UpVector), true)
				-- ancienne caméra : lookAt(centre + mince * d, centre, moyen), droite de l'image = moyen × mince
				T.expectEqual(same(profile.XVector, tilted.RightVector:Cross(tilted.UpVector)), true)
				T.expectEqual(same(extents, Vector3.new(3.72, 0.93, 0.37)), true)
			end
		)
	end)

	T.describe("WeaponProfile.frame avec référence", function()
		T.it("pose la pointe en X, le haut en Y, la face en Z, avec l'étendue le long de chacun", function()
			local reference = { part = "Handle", tip = Vector3.new(0, 0, -1), up = Vector3.new(1, 0, 0) }
			local profile, extents = WeaponProfile.frame(tilted, Vector3.new(0.93, 0.37, 3.72), reference)
			T.expectEqual(same(profile.XVector, -tilted.ZVector), true)
			T.expectEqual(same(profile.YVector, tilted.XVector), true)
			T.expectEqual(same(profile.ZVector, -tilted.YVector), true)
			T.expectEqual(same(extents, Vector3.new(3.72, 0.93, 0.37)), true)
		end)

		for name, reference in WeaponProfile.REFERENCES do
			T.it(
				"référence de " .. name .. " : axes unitaires et perpendiculaires, pointe à droite partout",
				function()
					T.expectEqual(math.abs(reference.tip.Magnitude - 1) < 1e-6, true)
					T.expectEqual(math.abs(reference.up.Magnitude - 1) < 1e-6, true)
					T.expectEqual(math.abs(reference.tip:Dot(reference.up)) < 1e-6, true)
					local thumb, reveal, faceThumb, faceReveal = views(tilted, Vector3.new(2, 3, 4), reference)
					T.expectEqual(thumb, 1)
					T.expectEqual(reveal, 1)
					T.expectEqual(same(faceThumb, faceReveal), true)
				end
			)
		end
	end)
end

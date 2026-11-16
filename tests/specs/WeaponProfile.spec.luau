return function(T, Loader)
	local WeaponProfile = Loader.new():require("src/shared/WeaponProfile")

	-- Cette méthode permet de comparer deux vecteurs à une tolérance près lorsqu'un repère vient d'une rotation.
	local function same(a: Vector3, b: Vector3): boolean
		return (a - b).Magnitude < 1e-4
	end

	-- Cette méthode permet de vérifier qu'un repère est direct (X × Y = Z) lorsqu'un rendu le prend tel quel (#429 : repère
	-- indirect pour la vignette, direct pour l'aperçu).
	local function direct(profile: CFrame): boolean
		return same(profile.XVector:Cross(profile.YVector), profile.ZVector)
	end

	-- Boîtes de test : longueur le long de X (ordre direct des axes de la boîte), puis le long de Z (ordre circulaire),
	-- les deux cas où l'ancien aperçu tournait l'arme de 180° par rapport à la vignette
	local tilted = CFrame.new(1, 2, 3) * CFrame.Angles(0.3, -1.1, 0.7)
	local boxes = {
		{ name = "AWP (longueur en X)", size = Vector3.new(9.2, 1.8, 0.6), long = "XVector", thin = "ZVector" },
		{ name = "M9 (longueur en Z)", size = Vector3.new(0.93, 0.37, 3.72), long = "ZVector", thin = "YVector" },
		{ name = "longueur en Y", size = Vector3.new(0.4, 5, 1.2), long = "YVector", thin = "XVector" },
	}

	T.describe("WeaponProfile.frame sans référence", function()
		for _, case in boxes do
			T.it("repère direct, longueur en X, regard le long de l'axe le plus mince : " .. case.name, function()
				local profile = WeaponProfile.frame(tilted, case.size, nil)
				T.expectEqual(direct(profile), true)
				T.expectEqual(math.abs(profile.XVector:Dot(tilted[case.long])) > 0.9999, true)
				T.expectEqual(math.abs(profile.ZVector:Dot(tilted[case.thin])) > 0.9999, true)
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
				"référence de "
					.. name
					.. " : axes de la pièce (±1 sur un seul axe), perpendiculaires, repère direct",
				function()
					-- l'étendue se lit composante par composante dans la taille de la boîte : un axe en biais la fausserait
					for _, v in { reference.tip, reference.up } do
						T.expectEqual(math.abs(v.X) + math.abs(v.Y) + math.abs(v.Z), 1)
						T.expectEqual(math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)), 1)
					end
					T.expectEqual(reference.tip:Dot(reference.up), 0)
					T.expectEqual(direct((WeaponProfile.frame(tilted, Vector3.new(2, 3, 4), reference))), true)
				end
			)
		end

		T.it("toute arme vendue au shop a sa référence, par le viewmodel des lignes du contenu", function()
			local loader = Loader.new({})
			local ShopCatalog = loader:require("src/shared/ShopCatalog")
			local InventoryRules = loader:require("src/shared/InventoryRules")
			for _, crate in ShopCatalog.CRATES do
				for _, row in ShopCatalog.contents(crate, InventoryRules.ITEMS) do
					T.expectEqual(WeaponProfile.REFERENCES[row.viewmodel] ~= nil, true)
				end
			end
		end)

		-- Mesuré dans Studio (#429) : boîte d'une arme reconstruite = axes de sa première pièce (Handle du M9, Barrel de
		-- l'AWP) ; pointe du M9 vers +Z de Handle, vue sur sa face +Y, dos +X ; bouche de l'AWP vers +X de Barrel
		T.it(
			"M9 : pointe (+Z de Handle) à droite, même face (+Y) et même haut (+X) que ses vignettes d'avant",
			function()
				local size = Vector3.new(0.93, 0.37, 3.72)
				local old = WeaponProfile.frame(tilted, size, nil)
				local profile = WeaponProfile.frame(tilted, size, WeaponProfile.REFERENCES.M9Bayonet)
				T.expectEqual(same(profile.XVector, tilted.ZVector), true)
				T.expectEqual(same(profile.ZVector, tilted.YVector), true)
				T.expectEqual(same(profile.XVector, old.XVector) and same(profile.ZVector, old.ZVector), true)
			end
		)

		T.it("AWP : bouche (+X de Barrel) à droite, lunette en haut, face +Z (celle de l'aperçu d'avant)", function()
			local profile, extents =
				WeaponProfile.frame(tilted, Vector3.new(9.15, 1.83, 0.61), WeaponProfile.REFERENCES.AWP)
			T.expectEqual(same(profile.XVector, tilted.XVector), true)
			T.expectEqual(same(profile.YVector, tilted.YVector), true)
			T.expectEqual(same(profile.ZVector, tilted.ZVector), true)
			T.expectEqual(same(extents, Vector3.new(9.15, 1.83, 0.61)), true)
		end)

		-- #444 : pièces du Ka-Bar aux mêmes axes, lame le long de -Z de Handle (relevé dans la place), dos de lame en +Y
		-- (build_knife.py : dos +Z Blender, Roblox = (x, z, -y) Blender, tools/export_mesh_fbx.py) ; boîte 0,32 × 0,75 × 3,73
		T.it(
			"Ka-Bar : pointe (-Z de Handle) à droite, dos (+Y) en haut, même pose que ses vignettes d'avant",
			function()
				local size = Vector3.new(0.32, 0.75, 3.73)
				local old, oldExtents = WeaponProfile.frame(tilted, size, nil)
				local profile, extents = WeaponProfile.frame(tilted, size, WeaponProfile.REFERENCES.KaBar)
				T.expectEqual(same(profile.XVector, -tilted.ZVector), true)
				T.expectEqual(same(profile.YVector, tilted.YVector), true)
				T.expectEqual(same(profile.XVector, old.XVector) and same(profile.ZVector, old.ZVector), true)
				T.expectEqual(same(extents, oldExtents), true)
			end
		)
	end)
end

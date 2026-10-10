return function(T, Loader)
	local loader = Loader.new()
	local WeaponThirdPerson = loader:require("src/shared/WeaponThirdPerson")
	local WeaponConfig = loader:require("src/shared/WeaponConfig")

	-- Cette méthode permet de comparer deux vecteurs composante par composante lorsqu'un test vérifie une orientation.
	local function expectVec(actual, expected, message)
		T.expectNear(actual.X, expected.X, 1e-4, message .. " (X)")
		T.expectNear(actual.Y, expected.Y, 1e-4, message .. " (Y)")
		T.expectNear(actual.Z, expected.Z, 1e-4, message .. " (Z)")
	end

	-- Cette méthode permet de vérifier qu'un CFrame est l'identité lorsqu'une action est terminée ou absente.
	local function expectIdentity(cf, message)
		expectVec(cf.Position, Vector3.new(0, 0, 0), message .. " position")
		expectVec(cf.RightVector, Vector3.new(1, 0, 0), message .. " right")
		expectVec(cf.UpVector, Vector3.new(0, 1, 0), message .. " up")
	end

	T.describe("WeaponThirdPerson.getSettings", function()
		T.it("lit le grip de WeaponConfig et complète les valeurs par défaut", function()
			local awp = WeaponThirdPerson.getSettings("AWP")
			T.expectEqual(awp.Pose, "Rifle")
			T.expectEqual(awp.Scale, WeaponConfig.Weapons.AWP.ThirdPerson.Scale)
			T.expectEqual(awp.IsMelee, false)
			T.expectEqual(WeaponThirdPerson.getSettings("Butterfly").Pose, "Melee")
			T.expectEqual(WeaponThirdPerson.getSettings("Butterfly").IsMelee, true)
			local unknown = WeaponThirdPerson.getSettings("Inconnue")
			T.expectEqual(unknown.Pose, "Rifle")
			T.expect(unknown.Grip ~= nil, "grip par défaut")
		end)

		T.it("chaque pose référencée par une arme existe", function()
			for name, cfg in WeaponConfig.Weapons do
				local pose = cfg.ThirdPerson and cfg.ThirdPerson.Pose
				T.expect(pose == nil or WeaponThirdPerson.POSES[pose] ~= nil, "pose de " .. name)
			end
		end)
	end)

	T.describe("WeaponThirdPerson.handleCFrame", function()
		T.it("bras levé à l'horizontale : canon vers l'avant, dessus de l'arme vers le haut", function()
			-- Main d'un bras pivoté de +90° autour de X (pose Rifle sans le léger rentrant).
			local hand = CFrame.new(1, 4, 0) * CFrame.Angles(math.rad(90), 0, 0)
			local grip = WeaponThirdPerson.getSettings("AWP").Grip
			local handle = WeaponThirdPerson.handleCFrame(hand, grip)
			expectVec(handle.RightVector, Vector3.new(0, 0, -1), "canon (X poignée)")
			expectVec(handle.UpVector, Vector3.new(0, 1, 0), "dessus (Y poignée)")
			-- La poignée est 0.2 devant la main (repère main -Y = avant).
			expectVec(handle.Position, Vector3.new(1, 4, -0.2), "position")
		end)

		T.it("applique le décalage d'action dans le repère de la poignée", function()
			local grip = CFrame.new(0, -0.2, 0)
			local handle = WeaponThirdPerson.handleCFrame(CFrame.identity, grip, CFrame.new(-0.25, 0, 0))
			expectVec(handle.Position, Vector3.new(-0.25, -0.2, 0), "recul le long du canon")
		end)
	end)

	T.describe("WeaponThirdPerson.actionOffset", function()
		local rifle = WeaponThirdPerson.getSettings("AWP")
		local knife = WeaponThirdPerson.getSettings("Butterfly")

		T.it("identité sans action, avant le début ou une fois l'action finie", function()
			expectIdentity(WeaponThirdPerson.actionOffset(nil, 0, rifle), "sans action")
			expectIdentity(WeaponThirdPerson.actionOffset("Shoot", -0.1, rifle), "avant le début")
			expectIdentity(WeaponThirdPerson.actionOffset("Shoot", 1, rifle), "tir fini")
			expectIdentity(WeaponThirdPerson.actionOffset("Reload", rifle.ReloadTime + 0.01, rifle), "recharge finie")
			expectIdentity(WeaponThirdPerson.actionOffset("Equip", rifle.EquipTime, rifle), "switch fini")
			expectIdentity(WeaponThirdPerson.actionOffset("Inconnue", 0.1, rifle), "action inconnue")
		end)

		T.it("tir : recul vers l'arrière et canon relevé au départ", function()
			local cf = WeaponThirdPerson.actionOffset("Shoot", 0, rifle)
			T.expect(cf.Position.X < 0, "recul le long de -X")
			T.expect(cf.RightVector.Y > 0, "canon relevé")
		end)

		T.it("estoc melee : l'arme avance au milieu de l'action", function()
			local cf = WeaponThirdPerson.actionOffset("Shoot", 0.15, knife)
			T.expect(cf.Position.X > 0.5, "avance le long du canon")
		end)

		T.it("recharge : arme abaissée à mi-parcours", function()
			local cf = WeaponThirdPerson.actionOffset("Reload", rifle.ReloadTime / 2, rifle)
			T.expect(cf.RightVector.Y < -0.3, "canon vers le bas")
		end)

		T.it("switch : arme basse au début, remonte progressivement", function()
			local start = WeaponThirdPerson.actionOffset("Equip", 0, rifle)
			local mid = WeaponThirdPerson.actionOffset("Equip", rifle.EquipTime / 2, rifle)
			T.expect(start.RightVector.Y < mid.RightVector.Y, "remonte")
			T.expect(start.RightVector.Y < -0.5, "basse au début")
		end)
	end)

	T.describe("WeaponThirdPerson.isVisibleTo", function()
		T.it("caché uniquement pour son propre personnage en 1re personne", function()
			T.expectEqual(WeaponThirdPerson.isVisibleTo(true, true), false)
			T.expectEqual(WeaponThirdPerson.isVisibleTo(true, false), true)
			T.expectEqual(WeaponThirdPerson.isVisibleTo(false, true), true)
			T.expectEqual(WeaponThirdPerson.isVisibleTo(false, false), true)
		end)
	end)
end

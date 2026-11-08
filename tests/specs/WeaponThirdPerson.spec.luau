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
			T.expectEqual(WeaponThirdPerson.getSettings("M9Bayonet").Pose, "Melee")
			T.expectEqual(WeaponThirdPerson.getSettings("M9Bayonet").IsMelee, true)
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
			-- Main d'un bras pivoté de +90° autour de X, grip canon = -Y de la main.
			local hand = CFrame.new(1, 4, 0) * CFrame.Angles(math.rad(90), 0, 0)
			local grip = CFrame.fromMatrix(Vector3.new(0, -0.2, 0), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1))
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
		local knife = WeaponThirdPerson.getSettings("M9Bayonet")

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

		T.it("estoc melee : l'arme avance le long de la lame au milieu de l'action", function()
			local cf = WeaponThirdPerson.actionOffset("Shoot", 0.15, knife)
			T.expect(cf.Position.Z > 0.5, "avance vers la pointe (+Z de la poignée)")
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

	T.describe("WeaponThirdPerson.POSES (#107)", function()
		-- Cette méthode permet de composer la chaîne taille, épaule, coude, poignet d'un côté lorsqu'un test vérifie
		-- où pointe l'arme : les C0/C1 du rig R15 n'ont pas de rotation, seuls les Transform orientent la main.
		local function handRotation(pose, side, air)
			local cf = CFrame.identity
			for _, joint in { "Waist", side .. "Shoulder", side .. "Elbow", side .. "Wrist" } do
				local target, weight = WeaponThirdPerson.holdTarget(pose, joint, air)
				if target and weight > 0 then
					cf = cf * target
				end
			end
			return cf.Rotation
		end

		T.it("chaque articulation tenue est pilotable et sa rotation est orthonormée", function()
			local allowed = {}
			for _, name in WeaponThirdPerson.HOLD_JOINTS do
				allowed[name] = true
			end
			for poseName, pose in WeaponThirdPerson.POSES do
				for _, group in { pose.Joints or {}, pose.AirJoints or {} } do
					for joint, cf in group do
						T.expect(allowed[joint], poseName .. "." .. joint .. " hors de HOLD_JOINTS")
						T.expectNear(cf.RightVector.Magnitude, 1, 1e-3, poseName .. "." .. joint .. " X")
						T.expectNear(cf.UpVector.Magnitude, 1, 1e-3, poseName .. "." .. joint .. " Y")
						T.expectNear(cf.RightVector:Dot(cf.UpVector), 0, 1e-3, poseName .. "." .. joint .. " X.Y")
					end
				end
			end
		end)

		T.it("fusil F1 : canon horizontal vers l'avant, taille tournée vers la droite", function()
			local barrel = (handRotation("Rifle", "Right", 0) * WeaponThirdPerson.getSettings("AWP").Grip).RightVector
			T.expect(barrel.Z < -0.99, "canon vers l'avant (-Z)")
			T.expectNear(barrel.Y, 0, 0.02, "canon horizontal")
			local top = (handRotation("Rifle", "Right", 0) * WeaponThirdPerson.getSettings("AWP").Grip).UpVector
			T.expect(top.Y > 0.99, "dessus de l'arme vers le haut")
			local waist = WeaponThirdPerson.holdTarget("Rifle", "Waist", 0)
			T.expect(waist and waist.LookVector.X > 0.5, "buste tourné vers la droite")
			local neck = WeaponThirdPerson.holdTarget("Rifle", "Neck", 0)
			T.expect(waist and neck and (waist * neck).LookVector.Z < -0.999, "tête face au regard")
		end)

		T.it("arme sans réglage 3P : tenue fusil et canon vers l'avant", function()
			local unknown = WeaponThirdPerson.getSettings("Inconnue")
			T.expectEqual(unknown.Pose, "Rifle")
			local barrel = (handRotation("Rifle", "Right", 0) * unknown.Grip).RightVector
			T.expect(barrel.Z < -0.99, "canon vers l'avant (-Z)")
		end)

		T.it("couteau C1 : lame vers l'avant, pointe relevée, tranchant vers le bas", function()
			local knife = handRotation("Melee", "Right", 0) * WeaponThirdPerson.getSettings("M9Bayonet").Grip
			T.expect(knife.ZVector.Z < -0.8, "pointe vers l'avant (-Z)")
			T.expect(knife.ZVector.Y > 0, "pointe relevée")
			T.expect(knife.RightVector.Y < -0.9, "tranchant vers le bas")
			T.expectEqual(WeaponThirdPerson.getSettings("M9Bayonet").Scale, 1)
		end)

		T.it("couteau : bras gauche libre au sol, tenu en l'air, fondu entre les deux", function()
			local _, ground = WeaponThirdPerson.holdTarget("Melee", "LeftShoulder", 0)
			local _, half = WeaponThirdPerson.holdTarget("Melee", "LeftShoulder", 0.5)
			local _, air = WeaponThirdPerson.holdTarget("Melee", "LeftShoulder", 1)
			T.expectEqual(ground, 0)
			T.expectNear(half, 0.5)
			T.expectEqual(air, 1)
			local _, right = WeaponThirdPerson.holdTarget("Melee", "RightShoulder", 0)
			T.expectEqual(right, 1)
			local _, waist = WeaponThirdPerson.holdTarget("Melee", "Waist", 1)
			T.expectEqual(waist, 0)
		end)

		T.it("tenue inconnue ou absente : aucune articulation pilotée", function()
			local cf, weight = WeaponThirdPerson.holdTarget("Inconnue", "RightShoulder", 1)
			T.expectEqual(cf, nil)
			T.expectEqual(weight, 0)
			T.expectEqual((WeaponThirdPerson.holdTarget(nil, "Waist", 1)), nil)
		end)
	end)

	T.describe("WeaponThirdPerson.approach", function()
		T.it("monte et descend à vitesse constante sans dépasser la cible", function()
			local fade = WeaponThirdPerson.HOLD_FADE_TIME
			T.expectNear(WeaponThirdPerson.approach(0, 1, fade / 2), 0.5)
			T.expectEqual(WeaponThirdPerson.approach(0.9, 1, fade), 1)
			T.expectNear(WeaponThirdPerson.approach(1, 0, fade / 4), 0.75)
			T.expectEqual(WeaponThirdPerson.approach(0.1, 0, fade), 0)
		end)
	end)

	T.describe("WeaponThirdPerson.stepLayers", function()
		local fade = WeaponThirdPerson.HOLD_FADE_TIME

		T.it("une nouvelle tenue entre à 0 puis monte jusqu'à 1", function()
			local layers = {}
			T.expect(WeaponThirdPerson.stepLayers(layers, "Rifle", fade / 2), "couche ajoutée")
			T.expectEqual(#layers, 1)
			T.expectNear(layers[1].weight, 0.5)
			T.expect(not WeaponThirdPerson.stepLayers(layers, "Rifle", fade), "pas de nouvelle couche")
			T.expectEqual(layers[1].weight, 1)
		end)

		T.it("changement d'arme : l'ancienne tenue descend pendant que la nouvelle monte, puis disparaît", function()
			local layers = { { pose = "Rifle", weight = 1 } }
			WeaponThirdPerson.stepLayers(layers, "Melee", fade / 2)
			T.expectEqual(#layers, 2)
			T.expectNear(layers[1].weight, 0.5, 1e-6, "fusil")
			T.expectNear(layers[2].weight, 0.5, 1e-6, "couteau")
			WeaponThirdPerson.stepLayers(layers, "Melee", fade / 2)
			T.expectEqual(#layers, 1)
			T.expectEqual(layers[1].pose, "Melee")
		end)

		T.it("arme rangée : la tenue descend puis la liste se vide", function()
			local layers = { { pose = "Melee", weight = 1 } }
			WeaponThirdPerson.stepLayers(layers, nil, fade / 2)
			T.expectNear(layers[1].weight, 0.5)
			WeaponThirdPerson.stepLayers(layers, nil, fade)
			T.expectEqual(#layers, 0)
		end)
	end)

	T.describe("WeaponThirdPerson.blendHold", function()
		local anim = CFrame.new(0, 0, 5)

		T.it("une seule couche à mi-fondu : à mi-chemin entre l'animation et la tenue", function()
			local target = WeaponThirdPerson.holdTarget("Rifle", "Waist", 0)
			local result = WeaponThirdPerson.blendHold(anim, { { pose = "Rifle", weight = 0.5 } }, "Waist", 0)
			T.expect(result ~= nil, "articulation tenue")
			expectVec((result :: CFrame).Position, Vector3.new(0, 0, 2.5), "position")
			local expected = anim:Lerp(target :: CFrame, 0.5)
			expectVec((result :: CFrame).LookVector, expected.LookVector, "rotation")
		end)

		T.it("deux tenues à 0,5 : mélange des deux, sans retour de l'animation", function()
			local layers = { { pose = "Rifle", weight = 0.5 }, { pose = "Melee", weight = 0.5 } }
			local result = WeaponThirdPerson.blendHold(anim, layers, "RightShoulder", 0) :: CFrame
			T.expect(result ~= nil, "articulation tenue")
			expectVec(result.Position, Vector3.new(0, 0, 0), "plus rien de l'animation")
			local rifle = WeaponThirdPerson.holdTarget("Rifle", "RightShoulder", 0) :: CFrame
			local knife = WeaponThirdPerson.holdTarget("Melee", "RightShoulder", 0) :: CFrame
			expectVec(result.LookVector, rifle:Lerp(knife, 0.5).LookVector, "rotation moyenne")
		end)

		T.it("articulation qu'aucune tenue ne tient : nil (l'animation reste)", function()
			T.expectEqual(WeaponThirdPerson.blendHold(anim, { { pose = "Melee", weight = 1 } }, "Waist", 1), nil)
			T.expectEqual(WeaponThirdPerson.blendHold(anim, { { pose = "Melee", weight = 1 } }, "LeftShoulder", 0), nil)
		end)
	end)

	T.describe("WeaponThirdPerson.isVisibleTo", function()
		T.it("caché pour son propre personnage, visible pour les autres joueurs", function()
			T.expectEqual(WeaponThirdPerson.isVisibleTo(true), false)
			T.expectEqual(WeaponThirdPerson.isVisibleTo(false), true)
		end)
	end)
end

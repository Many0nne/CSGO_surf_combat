return function(T, Loader)
	local Rules = Loader.new():require("src/shared/DebugPlaytestRules")

	T.describe("DebugPlaytestRules.viewmodelInView", function()
		T.it("accepte un viewmodel proche et devant la caméra", function()
			local ok, distance, z = Rules.viewmodelInView({ { X = -1, Y = -1, Z = -2 }, { X = 1, Y = -1, Z = -2 } })
			T.expectEqual(ok, true)
			T.expectEqual(distance, math.sqrt(5))
			T.expectEqual(z, -2)
		end)

		T.it("refuse un viewmodel resté loin de la caméra (#41)", function()
			T.expectEqual((Rules.viewmodelInView({ { X = 0, Y = -1000000, Z = -2 } })), false)
		end)

		T.it("refuse un viewmodel derrière la caméra", function()
			T.expectEqual((Rules.viewmodelInView({ { X = 0, Y = 0, Z = 2 } })), false)
		end)

		T.it("refuse un viewmodel sans pièce visible", function()
			T.expectEqual((Rules.viewmodelInView({})), false)
		end)
	end)

	T.describe("DebugPlaytestRules.viewmodelDefects", function()
		T.it("ne signale rien sur un modèle sain", function()
			T.expectEqual(#Rules.viewmodelDefects(true, { "LeftArm", "RightArm", "Handle" }, {}), 0)
		end)

		T.it("signale PrimaryPart absent, doublons et joints cassés (#41)", function()
			local defects = Rules.viewmodelDefects(
				false,
				{ "LeftArm", "Handle", "LeftArm", "LeftArm" },
				{ "LeftShoulder" }
			)
			T.expectEqual(#defects, 3)
			T.expectEqual(defects[1], "PrimaryPart absent")
			T.expectEqual(defects[2], "en double : LeftArm")
			T.expectEqual(defects[3], "joints cassés : LeftShoulder")
		end)
	end)

	T.describe("DebugPlaytestRules.resolveToolName", function()
		local tools = { "M9Bayonet", "AWP" }

		T.it("accepte un nom exact, puis insensible à la casse", function()
			T.expectEqual(Rules.resolveToolName(tools, "AWP"), "AWP")
			T.expectEqual(Rules.resolveToolName(tools, "m9bayonet"), "M9Bayonet")
		end)

		T.it("résout un numéro de slot dans l'ordre alphabétique", function()
			T.expectEqual(Rules.resolveToolName(tools, 1), "AWP")
			T.expectEqual(Rules.resolveToolName(tools, 2), "M9Bayonet")
			T.expectEqual(Rules.resolveToolName(tools, 3), nil)
		end)

		T.it("refuse un sélecteur vide, inconnu ou d'un autre type", function()
			T.expectEqual(Rules.resolveToolName(tools, ""), nil)
			T.expectEqual(Rules.resolveToolName(tools, "Deagle"), nil)
			T.expectEqual(Rules.resolveToolName(tools, true), nil)
		end)

		T.it("ne modifie pas la liste reçue", function()
			local list = { "B", "A" }
			Rules.resolveToolName(list, 1)
			T.expectEqual(list[1], "B")
		end)
	end)

	T.describe("DebugPlaytestRules.markersFor", function()
		T.it("dérive les marqueurs « X Sound » des sons déclarés", function()
			local cfg = { AnimationSounds = { Shoot = { "Shoot", "Bolt" } } }
			local markers = Rules.markersFor(cfg, "Shoot")
			T.expectEqual(#markers, 2)
			T.expectEqual(markers[1], "Shoot Sound")
			T.expectEqual(markers[2], "Bolt Sound")
		end)

		T.it("ajoute le marqueur dynamique de mêlée sur le tir uniquement", function()
			local cfg = { IsMelee = true, AnimationSounds = { Equip = { "Equip" }, Shoot = {} } }
			local shoot = Rules.markersFor(cfg, "Shoot")
			T.expectEqual(#shoot, 1)
			T.expectEqual(shoot[1], "Stab Sound")
			T.expectEqual(#Rules.markersFor(cfg, "Equip"), 1)
		end)

		T.it("renvoie une liste vide sans config", function()
			T.expectEqual(#Rules.markersFor(nil, "Shoot"), 0)
		end)

		T.it("ajoute le marqueur de coup sur chaque slash alterné d'une arme de mêlée", function()
			local cfg = { IsMelee = true, ShootAnimations = { "Shoot", "Shoot2" }, AnimationSounds = {} }
			T.expectEqual(Rules.markersFor(cfg, "Shoot2")[1], "Stab Sound")
			T.expectEqual(#Rules.markersFor(cfg, "Inspect"), 0)
		end)

		T.it("ajoute le marqueur de coup sur l'attaque secondaire sans modifier la config", function()
			local cfg = {
				IsMelee = true,
				ShootAnimations = { "Shoot" },
				SecondaryAttack = { Animation = "Stab" },
				AnimationSounds = {},
			}
			T.expectEqual(Rules.markersFor(cfg, "Stab")[1], "Stab Sound")
			T.expectEqual(#cfg.ShootAnimations, 1)
		end)
	end)

	T.describe("DebugPlaytestRules.expectedDamage", function()
		T.it("renvoie les dégâts de base, nil sans config", function()
			T.expectEqual(Rules.expectedDamage({ Damage = 115 }), 115)
			T.expectEqual(Rules.expectedDamage(nil), nil)
			T.expectEqual(Rules.expectedDamage({}), nil)
		end)
	end)

	T.describe("DebugPlaytestRules.yawPitchToward", function()
		-- Cette méthode permet de reconstruire la direction de visée de FPSCamera lorsque le test vérifie l'inverse.
		local function lookVector(yaw: number, pitch: number): Vector3
			return (CFrame.Angles(0, math.rad(-yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector
		end

		T.it("retrouve la direction visée par la caméra", function()
			local from = Vector3.new(1, 2, 3)
			for _, target in { Vector3.new(7, 1, -4), Vector3.new(-5, 2, 3), Vector3.new(1, -3, 9) } do
				local yaw, pitch = Rules.yawPitchToward(from, target, -89, 89)
				local look = lookVector(yaw, pitch)
				T.expectNear(look:Dot((target - from).Unit), 1, 1e-4)
			end
		end)

		T.it("vise -Z avec un yaw nul et borne le pitch", function()
			local yaw, pitch = Rules.yawPitchToward(Vector3.zero, Vector3.new(0, 0, -10), -89, 89)
			T.expectNear(yaw, 0)
			T.expectNear(pitch, 0)
			local _, steep = Rules.yawPitchToward(Vector3.zero, Vector3.new(0, 10, 0), -45, 45)
			T.expectNear(steep, 45)
		end)
	end)

	T.describe("DebugPlaytestRules report", function()
		T.it("préfixe chaque étape et résume un run réussi", function()
			local report = Rules.newReport()
			T.expectEqual(report:add("SPAWN", true, "ok"), "[DebugPlaytest] PASS SPAWN : ok")
			report:add("EQUIP", true)
			local line, ok = report:summary()
			T.expectEqual(line, "[DebugPlaytest] RESULT PASS 2/2")
			T.expectEqual(ok, true)
		end)

		T.it("liste les étapes en échec", function()
			local report = Rules.newReport()
			report:add("SPAWN", true)
			T.expectEqual(report:add("DAMAGE", false, "reçus 0"), "[DebugPlaytest] FAIL DAMAGE : reçus 0")
			report:add("SOUND", false)
			local line, ok = report:summary()
			T.expectEqual(line, "[DebugPlaytest] RESULT FAIL 1/3 (DAMAGE, SOUND)")
			T.expectEqual(ok, false)
		end)

		T.it("considère un run vide comme un échec", function()
			local _, ok = Rules.newReport():summary()
			T.expectEqual(ok, false)
		end)
	end)
end

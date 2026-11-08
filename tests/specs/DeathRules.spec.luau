return function(T, Loader)
	local DeathRules = Loader.new():require("src/client/systems/game/DeathRules")

	T.describe("DeathRules.ragdollVelocity", function()
		T.it("garde la vitesse du joueur sans direction de tir (chute)", function()
			local v = DeathRules.ragdollVelocity(Vector3.new(80, -10, 0), nil, nil, false)
			T.expectEqual(v, Vector3.new(80, -10, 0))
		end)

		T.it("pousse à l'horizontale dans le sens du tir, avec un peu de hauteur", function()
			local v = DeathRules.ragdollVelocity(Vector3.zero, Vector3.new(0, -1, 1).Unit, "M9Bayonet", false)
			local push = DeathRules.PUSH_BY_WEAPON.M9Bayonet
			T.expectNear(v.X, 0)
			T.expectNear(v.Z, push)
			T.expectNear(v.Y, push * DeathRules.PUSH_LIFT)
		end)

		T.it("pousse plus fort à l'AWP qu'au couteau, et encore plus à la tête", function()
			local dir = Vector3.new(1, 0, 0)
			local knife = DeathRules.ragdollVelocity(Vector3.zero, dir, "M9Bayonet", false).X
			local awp = DeathRules.ragdollVelocity(Vector3.zero, dir, "AWP", false).X
			local awpHead = DeathRules.ragdollVelocity(Vector3.zero, dir, "AWP", true).X
			T.expect(awp > knife, "AWP > couteau")
			T.expectNear(awpHead, awp * DeathRules.HEADSHOT_PUSH)
		end)

		T.it("prend la poussée par défaut pour une arme inconnue", function()
			local v = DeathRules.ragdollVelocity(Vector3.zero, Vector3.new(1, 0, 0), "Inconnue", false)
			T.expectNear(v.X, DeathRules.DEFAULT_PUSH)
		end)
	end)

	T.describe("DeathRules.turnAlpha", function()
		T.it("ne bouge pas sans temps écoulé et tend vers 1", function()
			T.expectEqual(DeathRules.turnAlpha(0), 0)
			T.expect(DeathRules.turnAlpha(10) > 0.99)
		end)

		T.it("ne dépend pas du découpage en frames", function()
			local one = DeathRules.turnAlpha(0.1)
			local half = DeathRules.turnAlpha(0.05)
			T.expectNear(1 - (1 - half) * (1 - half), one)
		end)
	end)

	T.describe("DeathRules.cameraOffset", function()
		T.it("recule à l'opposé du regard horizontal et monte", function()
			local offset = DeathRules.cameraOffset(Vector3.new(1, -0.5, 0).Unit)
			T.expectNear(offset.X, -DeathRules.CAMERA_BACK)
			T.expectNear(offset.Y, DeathRules.CAMERA_UP)
			T.expectNear(offset.Z, 0)
		end)

		T.it("garde un recul défini quand le regard est vertical", function()
			local offset = DeathRules.cameraOffset(Vector3.new(0, -1, 0))
			T.expectNear(Vector3.new(offset.X, 0, offset.Z).Magnitude, DeathRules.CAMERA_BACK)
		end)
	end)

	T.describe("DeathRules.formatDistance / ragdollFade", function()
		T.it("affiche la distance en mètres arrondis", function()
			T.expectEqual(DeathRules.formatDistance(0), "0 m")
			T.expectEqual(DeathRules.formatDistance(100), "28 m")
		end)

		T.it("garde le corps visible puis l'efface en RAGDOLL_FADE", function()
			T.expectEqual(DeathRules.ragdollFade(0), 0)
			T.expectEqual(DeathRules.ragdollFade(DeathRules.RAGDOLL_LIFETIME), 0)
			T.expectNear(DeathRules.ragdollFade(DeathRules.RAGDOLL_LIFETIME + DeathRules.RAGDOLL_FADE / 2), 0.5)
			T.expectEqual(DeathRules.ragdollFade(100), 1)
		end)
	end)
end

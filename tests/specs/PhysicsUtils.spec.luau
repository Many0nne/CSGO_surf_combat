return function(T, Loader)
	local PhysicsUtils = Loader.new():require("src/shared/PhysicsUtils")
	local DT = 1 / 60

	T.describe("PhysicsUtils", function()
		T.it("safeNormalize renvoie zéro pour un vecteur nul", function()
			T.expectEqual(PhysicsUtils.safeNormalize(Vector3.zero), Vector3.zero)
		end)

		T.it("safeNormalize renvoie un vecteur unitaire", function()
			T.expectNear(PhysicsUtils.safeNormalize(Vector3.new(3, 4, 0)).Magnitude, 1)
		end)

		T.it("getXZ / setXZ séparent et conservent Y", function()
			local v = Vector3.new(1, 2, 3)
			T.expectEqual(PhysicsUtils.getXZ(v), Vector3.new(1, 0, 3))
			T.expectEqual(PhysicsUtils.setXZ(v, Vector3.new(7, 99, 9)), Vector3.new(7, 2, 9))
		end)

		T.it(
			"clampHorizontal plafonne la vitesse horizontale sans toucher à la verticale ni à la direction",
			function()
				local v = PhysicsUtils.clampHorizontal(Vector3.new(600, -130, 800), 420)
				T.expectNear(Vector3.new(v.X, 0, v.Z).Magnitude, 420, 1e-4)
				T.expectNear(v.X / v.Z, 600 / 800, 1e-4)
				T.expectEqual(v.Y, -130)
			end
		)

		T.it("clampHorizontal réduit tout le vecteur en surf : il reste dans le plan de la rampe", function()
			local normal = Vector3.new(0.8, 0.6, 0)
			local along = Vector3.new(-0.6, 0.8, 0) * 300 + Vector3.new(0, 0, 500)
			local v = PhysicsUtils.clampHorizontal(along, 420, true)
			T.expectNear(Vector3.new(v.X, 0, v.Z).Magnitude, 420, 1e-4)
			T.expectNear(v:Dot(normal), 0, 1e-4)
		end)

		T.it(
			"clampHorizontal rend la vitesse telle quelle sous le plafond (bhop, air strafe, surf inchangés)",
			function()
				for _, v in
					{ Vector3.zero, Vector3.new(90, 38, 0), Vector3.new(-250, -400, 300), Vector3.new(0, 0, 420) }
				do
					T.expectEqual(PhysicsUtils.clampHorizontal(v, 420), v)
				end
			end
		)

		T.it("projectOnPlane donne un vecteur orthogonal à la normale", function()
			local normal = Vector3.new(1, 1, 0).Unit
			local projected = PhysicsUtils.projectOnPlane(Vector3.new(5, -2, 3), normal)
			T.expectNear(projected:Dot(normal), 0, 1e-5)
		end)

		T.it("angleDeg est robuste aux vecteurs nuls et exact à 90°", function()
			T.expectEqual(PhysicsUtils.angleDeg(Vector3.zero, Vector3.xAxis), 0)
			T.expectNear(PhysicsUtils.angleDeg(Vector3.xAxis, Vector3.zAxis), 90, 1e-4)
		end)

		T.it("applyFriction ne renverse jamais la direction", function()
			local v = PhysicsUtils.applyFriction(Vector3.new(10, 0, 0), 8, 2, 10)
			T.expectEqual(v, Vector3.zero)
		end)

		T.it("applyFriction sous STOP_SPEED retire une quantité constante", function()
			local v = PhysicsUtils.applyFriction(Vector3.new(1, 0, 0), 8, 2, DT)
			T.expectNear(v.X, 1 - 2 * 8 * DT, 1e-5)
		end)

		T.it("accelerate n'ajoute rien quand la vitesse dans wishdir dépasse wishspeed", function()
			local v = Vector3.new(40, 0, 0)
			T.expectEqual(PhysicsUtils.accelerate(v, Vector3.xAxis, 30, 12, DT), v)
		end)

		T.it("accelerate ne dépasse pas wishspeed dans la direction voulue", function()
			local v = PhysicsUtils.accelerate(Vector3.new(29, 0, 0), Vector3.xAxis, 30, 12, DT)
			T.expectNear(v.X, 30, 1e-5)
		end)

		-- Issue #7 : à la jonction rampe montante -> sol, les pieds finissent ~1.7 cm sous le rebord.
		T.it("airStepOffset enjambe un rebord de quelques mm (jonction rampe -> sol)", function()
			T.expectNear(PhysicsUtils.airStepOffset(0.017, 1.2, 0.05) :: number, 0.067, 1e-6)
		end)

		T.it("airStepOffset décolle d'au moins clearance quand le rebord est déjà sous les pieds", function()
			T.expectNear(PhysicsUtils.airStepOffset(-0.2, 1.2, 0.05) :: number, 0.05, 1e-6)
		end)

		T.it("airStepOffset refuse un rebord plus haut que la marche max", function()
			T.expectEqual(PhysicsUtils.airStepOffset(1.5, 1.2, 0.05), nil)
		end)
	end)
end

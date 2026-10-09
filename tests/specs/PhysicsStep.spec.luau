return function(T, Loader)
	local loader = Loader.new()
	local Config = loader:require("src/shared/MovementConfig")
	local Ground = loader:require("src/client/systems/movement/PhysicsStepGround")
	local Air = loader:require("src/client/systems/movement/PhysicsStepAir")
	local DT = 1 / 60

	T.describe("PhysicsStepGround", function()
		T.it("atteint RUN_SPEED depuis l'arrêt sans le dépasser (régression #4)", function()
			local v = Vector3.zero
			local maxSpeed = 0
			for _ = 1, 120 do
				v = Ground.step(v, Vector3.xAxis, Config.RUN_SPEED, DT)
				maxSpeed = math.max(maxSpeed, v.Magnitude)
			end
			T.expectNear(v.Magnitude, Config.RUN_SPEED, 1e-3, "vitesse stabilisée")
			T.expect(maxSpeed <= Config.RUN_SPEED + 1e-6, "dépassement de RUN_SPEED : " .. maxSpeed)
		end)

		T.it("atteint 90% de RUN_SPEED en moins de 0.5 s", function()
			local v = Vector3.zero
			for _ = 1, 30 do
				v = Ground.step(v, Vector3.xAxis, Config.RUN_SPEED, DT)
			end
			T.expect(v.Magnitude >= 0.9 * Config.RUN_SPEED, "trop lent : " .. v.Magnitude)
		end)

		T.it("s'arrête complètement sans input", function()
			local v = Vector3.new(Config.RUN_SPEED, 0, 0)
			for _ = 1, 120 do
				v = Ground.step(v, Vector3.zero, 0, DT)
			end
			T.expectEqual(v, Vector3.zero)
		end)

		T.it("GROUND_ACCEL reste supérieur à FRICTION", function()
			T.expect(Config.GROUND_ACCEL > Config.FRICTION)
		end)
	end)

	T.describe("PhysicsStepAir", function()
		T.it("ne modifie pas la vitesse sans input", function()
			local v = Vector3.new(30, -5, 0)
			T.expectEqual(Air.step(v, Vector3.zero, Config.RUN_SPEED, 1, DT), v)
		end)

		T.it("n'accélère pas dans la direction déjà rapide", function()
			local v = Vector3.new(30, 0, 0)
			T.expectEqual(Air.step(v, Vector3.xAxis, Config.RUN_SPEED, 1, DT), v)
		end)

		T.it("plafonne la vitesse dans wishdir à AIR_SPEED_CAP", function()
			local v = Vector3.zero
			for _ = 1, 120 do
				v = Air.step(v, Vector3.xAxis, Config.RUN_SPEED, 1, DT)
			end
			T.expectNear(v.X, Config.AIR_SPEED_CAP, 1e-5)
		end)

		T.it("un strafe perpendiculaire fait gagner de la vitesse", function()
			local v = Vector3.new(30, 0, 0)
			local after = Air.step(v, Vector3.zAxis, Config.RUN_SPEED, 1, DT)
			T.expect(after.Magnitude > v.Magnitude, "pas de gain en strafe")
			T.expect(after:Dot(Vector3.zAxis) <= Config.AIR_SPEED_CAP + 1e-6, "cap dépassé")
		end)

		T.it("surfaceFriction = 0 annule l'accélération", function()
			local v = Vector3.new(30, 0, 0)
			T.expectEqual(Air.step(v, Vector3.zAxis, Config.RUN_SPEED, 0, DT), v)
		end)
	end)
end

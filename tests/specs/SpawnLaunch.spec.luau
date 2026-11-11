return function(T, Loader)
	local SpawnLaunch = Loader.new():require("src/shared/SpawnLaunch")

	-- Cette méthode permet de reconstruire la direction visée par FPSCamera lorsqu'on vérifie la convention d'angles.
	local function cameraLook(yaw: number, pitch: number): Vector3
		return (CFrame.Angles(0, math.rad(-yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector
	end

	T.describe("SpawnLaunch.cameraAngles", function()
		T.it("regarde dans la direction du lancement (horizontale)", function()
			for _, dir in { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-0.6, 0, 0.8) } do
				local look = cameraLook(SpawnLaunch.cameraAngles(dir))
				T.expectNear(look.X, dir.X, 1e-4)
				T.expectNear(look.Z, dir.Z, 1e-4)
			end
		end)

		T.it("suit une descente modérée et borne l'inclinaison", function()
			local _, pitch = SpawnLaunch.cameraAngles(Vector3.new(0, -0.2, -1))
			T.expectNear(pitch, math.deg(math.asin(-0.2 / Vector3.new(0, -0.2, -1).Magnitude)), 1e-4)
			local _, steep = SpawnLaunch.cameraAngles(Vector3.new(0, -1, -0.1))
			T.expectEqual(steep, -30)
			local _, up = SpawnLaunch.cameraAngles(Vector3.new(0, 1, -0.1))
			T.expectEqual(up, 10)
		end)
	end)

	T.describe("SpawnLaunch.velocity", function()
		T.it("donne la vitesse demandée dans la direction du point de lancement", function()
			local v = SpawnLaunch.velocity(Vector3.new(0, 0, -2), 120)
			T.expectNear(v.Magnitude, 120, 1e-4)
			T.expectNear(v.Z, -120, 1e-4)
		end)

		T.it("borne un lancement trop rapide à la limite du serveur (#212)", function()
			local Config = Loader.new():require("src/shared/MovementConfig")
			local v = SpawnLaunch.velocity(Vector3.new(0, -0.3, -1), 1000)
			T.expectNear(v.Magnitude, Config.MAX_SPEED_SERVER, 1e-4)
			T.expectNear(v.Y / v.Z, 0.3, 1e-4)
			-- Une vitesse négative (erreur de signe dans la map) ne lance pas à l'envers à pleine vitesse
			T.expectEqual(SpawnLaunch.velocity(Vector3.new(0, 0, -1), -1000).Magnitude, 0)
			T.expectEqual(SpawnLaunch.velocity(Vector3.new(0, 0, -1), 0 / 0), Vector3.zero)
		end)
	end)
end

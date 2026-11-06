return function(T, Loader)
	local Rules = Loader.new():require("src/shared/CharacterSyncRules")
	local MovementConfig = Loader.new():require("src/shared/MovementConfig")

	T.describe("CharacterSyncRules.isWellFormed", function()
		T.it("accepte un Vector3 et un angle finis", function()
			T.expectEqual(Rules.isWellFormed(Vector3.new(1, 2, 3), 0.5), true)
		end)

		T.it("rejette une valeur forgée, infinie ou NaN", function()
			T.expectEqual(Rules.isWellFormed({ X = 1, Y = 2, Z = 3 }, 0), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(0 / 0, 0, 0), 0), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(math.huge, 0, 0), 0), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(0, 0, 0), "0"), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(0, 0, 0), 0 / 0), false)
		end)
	end)

	T.describe("CharacterSyncRules.isPlausibleMove", function()
		local origin = Vector3.zero
		local maxSpeed = MovementConfig.MAX_SPEED_SERVER

		T.it("accepte un déplacement à la vitesse maximale", function()
			T.expectEqual(Rules.isPlausibleMove(origin, Vector3.new(maxSpeed * 0.5, 0, 0), 0.5), true)
		end)

		T.it("rejette une téléportation", function()
			T.expectEqual(Rules.isPlausibleMove(origin, Vector3.new(maxSpeed * 2, 0, 0), 0.5), false)
		end)

		T.it("tolère des paquets arrivés groupés (durée au moins d'un intervalle d'envoi)", function()
			local stepDist = maxSpeed * Rules.SEND_INTERVAL
			T.expectEqual(Rules.isPlausibleMove(origin, Vector3.new(stepDist, 0, 0), 0), true)
		end)

		T.it("accepte à nouveau après un rejet, la durée depuis le dernier point accepté ayant grandi", function()
			local far = Vector3.new(100, 0, 0)
			T.expectEqual(Rules.isPlausibleMove(origin, far, 0.1), false)
			T.expectEqual(Rules.isPlausibleMove(origin, far, 0.4), true)
		end)
	end)

	T.describe("CharacterSyncRules.yawOf", function()
		T.it("retrouve l'angle d'une rotation autour de Y", function()
			for _, angle in { 0, 0.7, -2.5, math.pi / 2 } do
				T.expectNear(Rules.yawOf(CFrame.Angles(0, angle, 0).LookVector), angle, 1e-5)
			end
		end)
	end)

	T.describe("CharacterSyncRules.push", function()
		T.it("ignore un paquet en retard et borne la taille du tampon", function()
			local buffer = {}
			Rules.push(buffer, { t = 1, pos = Vector3.zero, yaw = 0 })
			Rules.push(buffer, { t = 0.5, pos = Vector3.one, yaw = 0 })
			T.expectEqual(#buffer, 1)
			for i = 2, Rules.BUFFER_SIZE + 5 do
				Rules.push(buffer, { t = i, pos = Vector3.zero, yaw = 0 })
			end
			T.expectEqual(#buffer, Rules.BUFFER_SIZE)
			T.expectEqual(buffer[#buffer].t, Rules.BUFFER_SIZE + 5)
		end)
	end)

	T.describe("CharacterSyncRules.sample", function()
		local buffer = {
			{ t = 1, pos = Vector3.new(0, 0, 0), yaw = 0 },
			{ t = 2, pos = Vector3.new(10, 0, 0), yaw = 1 },
		}

		T.it("interpole entre les deux paquets qui encadrent l'instant", function()
			local pos, yaw = Rules.sample(buffer, 1.25)
			T.expectNear(pos.X, 2.5, 1e-5)
			T.expectNear(yaw, 0.25, 1e-5)
		end)

		T.it("reste sur les extrémités sans extrapoler", function()
			T.expectNear(Rules.sample(buffer, 0).X, 0, 1e-5)
			T.expectNear(Rules.sample(buffer, 5).X, 10, 1e-5)
		end)

		T.it("tourne par le plus court chemin au passage de ±π", function()
			local wrap = {
				{ t = 0, pos = Vector3.zero, yaw = math.pi - 0.1 },
				{ t = 1, pos = Vector3.zero, yaw = -math.pi + 0.1 },
			}
			local _, yaw = Rules.sample(wrap, 0.5)
			T.expectNear(math.abs(yaw), math.pi, 1e-5)
		end)

		T.it("ne renvoie rien sans paquet", function()
			T.expectEqual(Rules.sample({}, 1), nil)
		end)
	end)
end

return function(T, Loader)
	local MapRules = Loader.new():require("src/shared/MapRules")

	T.describe("MapRules.contains", function()
		local cf = CFrame.new(10, 5, 0) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(4, 10, 20)

		T.it("suit l'orientation de la boîte", function()
			-- tournée de 90° : sa longueur (Z local, 20) est sur l'axe X du monde
			T.expectEqual(MapRules.contains(cf, size, Vector3.new(19, 5, 0), 0), true)
			T.expectEqual(MapRules.contains(cf, size, Vector3.new(10, 5, 5), 0), false)
		end)

		T.it("élargit la boîte de la marge", function()
			T.expectEqual(MapRules.contains(cf, size, Vector3.new(10, 5, 2.5), 0), false)
			T.expectEqual(MapRules.contains(cf, size, Vector3.new(10, 5, 2.5), 1), true)
		end)
	end)

	T.describe("MapRules.velocityAfter", function()
		local fwd = Vector3.new(0, 0, -1)

		T.it("impose la vitesse d'un geyser ou d'un lanceur", function()
			local set = Vector3.new(-40, 100, 50)
			T.expectEqual(MapRules.velocityAfter("Geyser", Vector3.new(5, 0, 0), set, nil, fwd, 300), set)
			T.expectEqual(MapRules.velocityAfter("Launcher", Vector3.zero, set, nil, fwd, 300), set)
		end)

		T.it("ajoute la vitesse d'un portique dans le sens du mouvement, sans toucher à la verticale", function()
			local v = MapRules.velocityAfter("Portal", Vector3.new(60, -20, 80), nil, 40, fwd, 300)
			T.expectNear(Vector3.new(v.X, 0, v.Z).Magnitude, 140, 1e-4)
			T.expectNear(v.X / v.Z, 60 / 80, 1e-4)
			T.expectNear(v.Y, -20, 1e-4)
		end)

		T.it("plafonne le portique sans jamais ralentir", function()
			local capped = MapRules.velocityAfter("Portal", Vector3.new(0, 0, 280), nil, 40, fwd, 300)
			T.expectNear(capped.Z, 300, 1e-4)
			local over = MapRules.velocityAfter("Portal", Vector3.new(0, 0, 320), nil, 40, fwd, 300)
			T.expectNear(over.Z, 320, 1e-4)
		end)

		T.it("pousse dans le sens du portique quand le joueur est presque arrêté", function()
			local v = MapRules.velocityAfter("Portal", Vector3.new(0.2, 0, 0), nil, 40, fwd, 300)
			-- vitesse résiduelle (0,2) + boost (40), dans l'axe du portique
			T.expectNear(v.Z, -40.2, 1e-3)
			T.expectNear(v.X, 0, 1e-4)
		end)

		T.it("ignore un boost mal configuré", function()
			T.expectEqual(MapRules.velocityAfter("Portal", Vector3.zero, nil, nil, fwd, 300), nil)
			T.expectEqual(MapRules.velocityAfter("Inconnu", Vector3.zero, Vector3.one, 10, fwd, 300), nil)
		end)
	end)

	T.describe("MapRules.isBelowKillHeight", function()
		T.it("tue sous la hauteur de la map, et jamais sans hauteur déclarée", function()
			T.expectEqual(MapRules.isBelowKillHeight(-61, -60), true)
			T.expectEqual(MapRules.isBelowKillHeight(-59, -60), false)
			T.expectEqual(MapRules.isBelowKillHeight(-1000, nil), false)
		end)
	end)

	T.describe("MapRules.ballisticVelocity", function()
		T.it("atteint la cible au temps demandé", function()
			local from, to, t, g = Vector3.new(0, 0, 0), Vector3.new(-60, 36, 70), 1.3, -110
			local v = MapRules.ballisticVelocity(from, to, t, g)
			local reached = from + v * t + Vector3.new(0, 0.5 * g * t * t, 0)
			T.expectNear((reached - to).Magnitude, 0, 1e-3)
		end)
	end)
end

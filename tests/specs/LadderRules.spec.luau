return function(T, Loader)
	local LadderRules = Loader.new():require("src/shared/LadderRules")
	local PhysicsUtils = Loader.new():require("src/shared/PhysicsUtils")

	-- échelle sur un mur dont la face regarde +Z : le joueur est côté +Z et avance vers -Z pour monter
	local normal = Vector3.new(0, 0, 1)
	local SPEED = 20

	-- Cette méthode permet de construire la direction visée (lacet face au mur, tangage en degrés) lorsqu'on simule
	-- la touche « avancer » sur l'échelle.
	local function forward(pitchDeg: number): Vector3
		local p = math.rad(pitchDeg)
		return Vector3.new(0, math.sin(p), -math.cos(p))
	end

	T.describe("LadderRules.climbVelocity", function()
		T.it("monte en avançant face à l'échelle, sans s'enfoncer au-delà du mur", function()
			local v = LadderRules.climbVelocity(forward(0), normal, SPEED, false)
			T.expectNear(v.Y, SPEED, 1e-4)
			T.expectEqual(v.X, 0)
			T.expect(v.Z < 0, "poussée vers le mur pour passer le rebord en haut")
		end)

		T.it("descend en avançant le regard baissé, ou en reculant", function()
			T.expect(LadderRules.climbVelocity(forward(-70), normal, SPEED, false).Y < 0, "regard baissé")
			T.expectNear(LadderRules.climbVelocity(-forward(0), normal, SPEED, false).Y, -SPEED, 1e-4)
		end)

		T.it("borne la vitesse le long de l'échelle en regardant en diagonale", function()
			local v = LadderRules.climbVelocity(forward(45), normal, SPEED, false)
			T.expectNear(Vector3.new(v.X, v.Y, 0).Magnitude, SPEED, 1e-4)
		end)

		T.it("se déplace de côté le long de l'échelle", function()
			local v = LadderRules.climbVelocity(Vector3.new(1, 0, 0), normal, SPEED, false)
			T.expectNear(v.X, SPEED, 1e-4)
			T.expectNear(v.Y, 0, 1e-4)
		end)

		T.it("reste immobile sans touche (pas de gravité sur l'échelle)", function()
			T.expectEqual(LadderRules.climbVelocity(Vector3.zero, normal, SPEED, false), Vector3.zero)
		end)

		T.it("s'écarte du mur en reculant au pied de l'échelle", function()
			local v = LadderRules.climbVelocity(-forward(0), normal, SPEED, true)
			T.expect(v.Z > 0, "part du mur")
		end)
	end)

	T.describe("LadderRules.jumpOffVelocity", function()
		T.it("pousse le long de la normale, à l'horizontale", function()
			T.expectEqual(LadderRules.jumpOffVelocity(Vector3.new(0, 0.2, 1), 30), Vector3.new(0, 0, 30))
		end)
	end)

	T.describe("PhysicsUtils.isSideContact", function()
		T.it("écarte l'arête d'un muret plus haute que la hauteur de marche", function()
			-- muret de 3,6 studs (bord de Dizzy derrière les extracteurs) : arête accrochée par la sonde de sol
			T.expectEqual(PhysicsUtils.isSideContact(45.65, 42.09, 1.2), true)
		end)

		T.it("garde le sol et les marches qu'on peut enjamber", function()
			T.expectEqual(PhysicsUtils.isSideContact(42.09, 42.09, 1.2), false)
			T.expectEqual(PhysicsUtils.isSideContact(43.2, 42.09, 1.2), false)
		end)
	end)
end

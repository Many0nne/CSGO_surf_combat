-- Douille éjectée à l'ouverture de culasse (#237) : départ, arc, rotation, durée de vie, pool, vitesse héritée.
return function(T, Loader)
	local CasingRules = Loader.new():require("src/shared/CasingRules")

	local MID = { 0.5, 0.5, 0.5, 0.5 } -- tirages au centre des fourchettes : valeurs de base
	-- EjectPort d'un viewmodel qui regarde vers -Z du monde : +X droite, +Y haut, +Z arrière (repère identité)
	local PORT = CFrame.new(10, 20, 30)

	-- Cette méthode permet de comparer deux vecteurs lorsqu'un test vérifie une position ou une vitesse calculée.
	local function near(a: Vector3, b: Vector3, eps: number?): boolean
		return (a - b).Magnitude < (eps or 1e-4)
	end

	T.describe("CasingRules.launch (#237)", function()
		T.it("part de la fenêtre d'éjection, vers la droite et le haut, sans partir vers l'avant", function()
			local flight = CasingRules.launch(PORT, 1, Vector3.zero, MID)
			T.expect(near(flight.start.Position, PORT.Position), tostring(flight.start.Position))
			local v = CasingRules.EJECT_VELOCITY
			T.expect(near(flight.velocity, Vector3.new(v[1], v[2], v[3])), tostring(flight.velocity))
			T.expect(flight.velocity.X > 0 and flight.velocity.Y > 0 and flight.velocity.Z >= 0)
		end)

		T.it("couche la douille le long de l'arme : l'axe du cylindre (X) suit l'axe Z de l'EjectPort", function()
			local flight = CasingRules.launch(PORT, 1, Vector3.zero, MID)
			local axis = flight.start.RightVector
			T.expect(math.abs(axis:Dot(Vector3.new(0, 0, 1))) > 0.999, tostring(axis))
		end)

		T.it(
			"suit l'orientation de l'arme : arme tournée de 90°, la douille sort toujours sur son côté droit",
			function()
				local turned = PORT * CFrame.Angles(0, math.pi / 2, 0) -- droite de l'arme = -Z du monde
				local flight = CasingRules.launch(turned, 1, Vector3.zero, MID)
				T.expect(flight.velocity.Z < -1 and flight.velocity.Y > 0, tostring(flight.velocity))
			end
		)

		T.it(
			"arme 3P : vitesse, gravité réduites par l'échelle ; la vitesse du tireur s'ajoute telle quelle",
			function()
				local run = Vector3.new(0, 0, -200)
				local small = CasingRules.launch(PORT, 0.5, run, MID)
				local full = CasingRules.launch(PORT, 1, Vector3.zero, MID)
				T.expect(near(small.velocity, full.velocity * 0.5 + run), tostring(small.velocity))
				T.expectEqual(small.gravity, CasingRules.GRAVITY * 0.5)
			end
		)

		T.it("les tirages font varier vitesse et rotation dans ± SPREAD", function()
			local low = CasingRules.launch(PORT, 1, Vector3.zero, { 0, 0, 0, 0 })
			local high = CasingRules.launch(PORT, 1, Vector3.zero, { 1, 1, 1, 1 })
			local s = CasingRules.SPREAD
			T.expect(math.abs(low.velocity.X - CasingRules.EJECT_VELOCITY[1] * (1 - s)) < 1e-4)
			T.expect(math.abs(high.velocity.X - CasingRules.EJECT_VELOCITY[1] * (1 + s)) < 1e-4)
			T.expect(high.spin.Magnitude > low.spin.Magnitude)
		end)
	end)

	T.describe("CasingRules.cframeAt (#237)", function()
		local flight = CasingRules.launch(PORT, 1, Vector3.zero, MID)

		T.it("au départ, la douille est dans la fenêtre d'éjection", function()
			T.expect(near(CasingRules.cframeAt(flight, 0).Position, PORT.Position))
		end)

		T.it("suit un arc : monte, puis retombe sous la fenêtre avant la fin de sa vie", function()
			local apex = flight.velocity.Y / flight.gravity
			T.expect(apex > 0 and apex < CasingRules.LIFETIME, tostring(apex))
			local top = CasingRules.cframeAt(flight, apex).Position
			local last = CasingRules.cframeAt(flight, CasingRules.LIFETIME).Position
			T.expect(top.Y > PORT.Position.Y)
			T.expect(last.Y < PORT.Position.Y - 1, tostring(last.Y))
			T.expect(last.X > PORT.Position.X + 5, "partie à droite : " .. tostring(last.X))
		end)

		T.it("tourne sur elle-même à vitesse constante", function()
			local a = CasingRules.cframeAt(flight, 0.05)
			local b = CasingRules.cframeAt(flight, 0.10)
			local start = flight.start
			local angle1 = math.acos(math.clamp(a.RightVector:Dot(start.RightVector), -1, 1))
			local angle2 = math.acos(math.clamp(b.RightVector:Dot(start.RightVector), -1, 1))
			T.expect(angle1 > 0.3 and angle2 > angle1, string.format("%.3f %.3f", angle1, angle2))
		end)

		T.it("sans rotation, l'orientation de départ est gardée", function()
			local still = { start = flight.start, velocity = Vector3.zero, spin = Vector3.zero, gravity = 0 }
			local cf = CasingRules.cframeAt(still, 0.5)
			T.expect(near(cf.RightVector, flight.start.RightVector) and near(cf.Position, flight.start.Position))
		end)
	end)

	T.describe("CasingRules.isExpired et délai 3P (#237)", function()
		T.it("vit LIFETIME secondes", function()
			T.expectEqual(CasingRules.isExpired(0), false)
			T.expectEqual(CasingRules.isExpired(CasingRules.LIFETIME - 0.01), false)
			T.expectEqual(CasingRules.isExpired(CasingRules.LIFETIME), true)
		end)

		T.it(
			"la douille d'un tir relayé part pendant le cycle de tir, et sa vie finit avant le tir suivant",
			function()
				local WeaponConfig = Loader.new():require("src/shared/WeaponConfig")
				local awp = WeaponConfig.Weapons.AWP
				local delay = awp.CasingEjectDelay
				T.expect(type(delay) == "number" and delay > 0 and delay < awp.FireDelay, tostring(delay))
				T.expect(CasingRules.LIFETIME < awp.FireDelay, "une douille en vol par tireur")
			end
		)
	end)

	T.describe("CasingRules.pickSlot (#237)", function()
		T.it("prend un emplacement libre d'abord", function()
			T.expectEqual(CasingRules.pickSlot({}, 4, false), 1)
			T.expectEqual(CasingRules.pickSlot({ [1] = 5, [2] = 6 }, 4, false), 3)
			T.expectEqual(CasingRules.pickSlot({ [1] = 5, [3] = 6 }, 4, true), 2)
		end)

		T.it("pool plein : la douille locale réutilise la plus ancienne, celle d'un autre n'a rien", function()
			T.expectEqual(CasingRules.pickSlot({ 9, 4, 7 }, 3, true), 2)
			T.expectEqual(CasingRules.pickSlot({ 9, 4, 7 }, 3, false), nil)
		end)
	end)

	T.describe("CasingRules.inheritedVelocity et isNearCamera (#237)", function()
		T.it("vitesse moyenne de l'arme pendant le délai", function()
			local v = CasingRules.inheritedVelocity(Vector3.zero, Vector3.new(0, 0, -82), 0.82)
			T.expect(near(v, Vector3.new(0, 0, -100)), tostring(v))
		end)

		T.it("un surfeur à la vitesse maximale garde sa vitesse (pas pris pour un saut)", function()
			local MovementConfig = Loader.new():require("src/shared/MovementConfig")
			local speed = MovementConfig.MAX_SPEED_SERVER
			local v = CasingRules.inheritedVelocity(Vector3.zero, Vector3.new(speed * 0.82, 0, 0), 0.82)
			T.expect(near(v, Vector3.new(speed, 0, 0), 1e-3), tostring(v))
		end)

		T.it("un saut (réapparition) ou une durée nulle ne donne aucune vitesse", function()
			T.expectEqual(CasingRules.inheritedVelocity(Vector3.zero, Vector3.new(1000, 0, 0), 0.82), Vector3.zero)
			T.expectEqual(CasingRules.inheritedVelocity(Vector3.zero, Vector3.new(1, 0, 0), 0), Vector3.zero)
		end)

		T.it("pas de douille pour un tireur loin de notre caméra", function()
			local far = CasingRules.MAX_REMOTE_DISTANCE
			T.expectEqual(CasingRules.isNearCamera(Vector3.new(far - 1, 0, 0), Vector3.zero), true)
			T.expectEqual(CasingRules.isNearCamera(Vector3.new(far + 1, 0, 0), Vector3.zero), false)
		end)
	end)
end

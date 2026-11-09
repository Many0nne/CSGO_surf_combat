-- Règles des bots (#139, #140) : cap et regard, gêne, nom, nombre demandé en Studio.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/BotRules")
	local Config = Loader.new():require("src/shared/BotConfig")

	local function near(a: number, b: number, msg: string?)
		T.expectEqual(math.abs(a - b) < 1e-6, true, (msg or "") .. " : " .. tostring(a) .. " ≠ " .. tostring(b))
	end

	T.describe("BotRules", function()
		T.it("suit la convention de cap de la caméra FPS", function()
			local north = Rules.headingDir(0)
			near(north.X, 0, "cap 0")
			near(north.Z, -1, "cap 0 vers -Z")
			local east = Rules.headingDir(90)
			near(east.X, 1, "cap 90 vers +X")
			local look = Rules.headingRotation(90).LookVector
			near(look.X, east.X, "la racine regarde où il marche")
			near(look.Z, east.Z, "la racine regarde où il marche")
		end)

		T.it("donne le cap d'une direction, nil pour une direction nulle", function()
			near(Rules.yawOf(Vector3.new(0, 0, -1)) :: number, 0, "vers -Z")
			near(Rules.yawOf(Vector3.new(1, 5, 0)) :: number, 90, "vers +X, hauteur ignorée")
			T.expectEqual(Rules.yawOf(Vector3.new(0, 3, 0)), nil)
		end)

		T.it("tourne le regard à vitesse bornée, par le plus court côté", function()
			near(Rules.turnToward(10, 350, 100, 1), 350, "20° en arrière : atteint")
			near(Rules.turnToward(350, 10, 100, 0.1), 0, "passe par 0 : 10° par tick")
			near(Rules.turnToward(0, 170, 90, 1), 90, "borné à rate × dt")
		end)

		T.it("compte le temps gêné seulement au sol et lent", function()
			local wish = 20
			local slow = wish * Config.STUCK_SPEED_RATIO * 0.5
			T.expectEqual(Rules.stuckTime(0.1, true, slow, wish, 0.1) > 0.19, true, "au sol et lent : cumule")
			T.expectEqual(Rules.stuckTime(0.3, true, wish, wish, 0.1), 0, "à pleine vitesse : remis à 0")
			T.expectEqual(Rules.stuckTime(0.3, false, 0, wish, 0.1), 0, "en l'air : jamais gêné")
			T.expectEqual(Rules.stuckTime(0.3, true, 0, 0, 0.1), 0, "sans envie d'avancer : jamais gêné")
		end)

		T.it("donne le premier nom libre, puis un nom numéroté", function()
			T.expectEqual(Rules.pickName({}), Config.NAMES[1])
			T.expectEqual(Rules.pickName({ [Config.NAMES[1]] = true }), Config.NAMES[2])
			local all = {}
			for _, name in Config.NAMES do
				all[name] = true
			end
			local extra = Rules.pickName(all)
			T.expectEqual(all[extra], nil, "pas un nom déjà pris")
			all[extra] = true
			T.expectEqual(Rules.pickName(all) ~= extra, true, "deux noms numérotés différents")
		end)

		T.it("borne le nombre de bots demandé", function()
			T.expectEqual(Rules.requestedCount(nil), 0)
			T.expectEqual(Rules.requestedCount("3"), 0)
			T.expectEqual(Rules.requestedCount(0 / 0), 0, "NaN")
			T.expectEqual(Rules.requestedCount(2.7), 2)
			T.expectEqual(Rules.requestedCount(-1), 0)
			T.expectEqual(Rules.requestedCount(99), Config.MAX_BOTS)
		end)
	end)

	T.describe("BotRules bunny hop (#151)", function()
		local Movement = Loader.new():require("src/shared/MovementConfig")
		local Air = Loader.new():require("src/shared/movement/PhysicsStepAir")
		local dt = 1 / 64
		local run = Movement.RUN_SPEED

		-- Cette méthode permet de simuler un saut entier d'un bot qui strafe vers un cap lorsqu'un test mesure le gain
		-- de vitesse et la tenue du cap (gravité ignorée, seule la vitesse horizontale compte).
		local function simulate(v0: Vector3, desired: Vector3, target: number, noise: number, ticks: number?)
			local v = v0
			local worst = 0
			for _ = 1, ticks or math.floor(Rules.airTime() / dt) do
				local wish, w = Rules.airStrafe(v, desired, target, run, dt, noise)
				v = Air.step(v, wish, w, 1, dt)
				worst = math.max(worst, math.abs(Rules.signedAngle(v, desired)))
			end
			return v, worst
		end

		T.it("tourne une direction et mesure l'angle signé dans le même sens", function()
			local d = Rules.rotateXZ(Vector3.new(1, 0, 0), 30)
			near(Rules.signedAngle(Vector3.new(1, 0, 0), d), 30, "rotation +30°")
			near(Rules.signedAngle(d, Vector3.new(1, 0, 0)), -30, "retour −30°")
			near(d.Magnitude, 1, "longueur gardée")
		end)

		T.it("strafe à 90° quand l'accélération par tick dépasse la limite", function()
			near(Rules.optimalStrafeAngle(run, run, dt), 90, "a·t > L : perpendiculaire")
			near(Rules.optimalStrafeAngle(80, 2, dt), 90, "même à petite envie : a·t reste au-dessus de L")
		end)

		T.it("tourne sans gagner de vitesse à la vitesse visée", function()
			local v = Vector3.new(45, 0, 0)
			local angle = Rules.steadyTurnAngle(45, run)
			T.expectEqual(angle > 90, true, "au-delà de 90°")
			local after = Air.step(v, Rules.rotateXZ(Vector3.new(1, 0, 0), angle), run, 1, dt)
			near(after.Magnitude, 45, "vitesse inchangée")
			T.expectEqual(after.Z > 0.5, true, "le cap a tourné")
		end)

		T.it("gagne de la vitesse en tenant son cap pendant un saut", function()
			local desired = Vector3.new(0, 0, -1)
			local v, worst = simulate(desired * run, desired, math.huge, 0)
			T.expectEqual(v.Magnitude > run * 1.4, true, "vitesse gagnée : " .. v.Magnitude)
			T.expectEqual(worst < 15, true, "cap tenu à 15° près : " .. worst)
			-- Six sauts enchaînés (environ 1 600 de |v|² gagnés par saut) : la vitesse approche 100
			local fast = simulate(desired * run, desired, math.huge, 0, 6 * math.floor(Rules.airTime() / dt))
			T.expectEqual(fast.Magnitude > 90, true, "6 sauts : " .. fast.Magnitude)
		end)

		T.it("tient la vitesse visée et corrige le cap sans accélérer", function()
			local target = 45
			local desired = Vector3.new(0, 0, -1)
			local v = simulate(desired * run, desired, target, 0)
			T.expectEqual(
				v.Magnitude < target + 3,
				true,
				"pas plus que la vitesse visée (+ un tick) : " .. v.Magnitude
			)
			-- Lancé à 30° du cap, à la vitesse visée : revient vers le cap sans accélérer
			local after = simulate(Rules.rotateXZ(desired, 30) * target, desired, target, 0)
			near(after.Magnitude, target, "vitesse gardée")
			T.expectEqual(
				math.abs(Rules.signedAngle(after, desired)) <= Config.BHOP_ALIGN_TOL + 1,
				true,
				"cap rattrapé"
			)
		end)

		T.it("freine en l'air jusqu'à la vitesse visée, sans la dépasser", function()
			local desired = Vector3.new(1, 0, 0)
			local wish, w = Rules.airStrafe(desired * 100, desired, 60, run, dt, 0)
			near(wish.X, -1, "vise à l'opposé de la vitesse")
			local after = Air.step(desired * 100, wish, w, 1, dt)
			near(after.Magnitude, 60, "perd juste l'excès en un tick")
			local v = simulate(desired * 100, desired, 60, 0, 10)
			T.expectEqual(
				math.abs(v.Magnitude - 60) <= Config.BHOP_SPEED_TOL + 0.5,
				true,
				"reste à 60 : " .. v.Magnitude
			)
		end)

		T.it("gagne encore de la vitesse avec un strafe imparfait", function()
			local desired = Vector3.new(1, 0, 0)
			for _, noise in { -Config.BHOP_STRAFE_NOISE, Config.BHOP_STRAFE_NOISE } do
				local v = simulate(desired * run, desired, math.huge, noise)
				T.expectEqual(v.Magnitude > run * 1.3, true, "gain malgré le bruit " .. noise .. " : " .. v.Magnitude)
			end
			local none = simulate(desired * run, desired, math.huge, 1)
			T.expectEqual(none.Magnitude < run + 1, true, "au bord de la fenêtre : plus de gain")
		end)

		T.it("donne une vitesse qui tient réellement le rayon du virage", function()
			local radius = 20
			local speed = Rules.turnSpeed(radius, dt) / Config.BHOP_TURN_SAFETY
			-- Virage sans gain à cette vitesse : rayon mesuré = vitesse / vitesse de rotation
			local v = Vector3.new(speed, 0, 0)
			local ticks = 20
			for _ = 1, ticks do
				v = Air.step(v, Rules.rotateXZ(v.Unit, Rules.steadyTurnAngle(speed, run)), run, 1, dt)
			end
			local turned = math.rad(math.abs(Rules.signedAngle(Vector3.new(1, 0, 0), v)))
			local measured = speed * ticks * dt / turned
			T.expectEqual(math.abs(measured - radius) / radius < 0.1, true, "rayon " .. measured)
			T.expectEqual(Rules.turnSpeed(math.huge, dt), math.huge, "ligne droite : pas de limite")
			T.expectEqual(Rules.turnSpeed(10, dt) < Rules.turnSpeed(40, dt), true, "virage serré : plus lent")
		end)

		T.it("ressaute seulement si le saut suivant tient avant la fin de la marche", function()
			local hop = run * Rules.airTime()
			T.expectEqual(Rules.keepBhopping(hop + Config.BHOP_LAND_MARGIN + 1, run), true)
			T.expectEqual(Rules.keepBhopping(hop, run), false, "pas de marge")
			T.expectEqual(
				Rules.keepBhopping(hop + Config.BHOP_LAND_MARGIN + 1, run * 1.5),
				false,
				"plus vite : plus loin"
			)
		end)

		T.it("vise une vitesse bornée par le plafond, les virages et la marche restante", function()
			local T0 = Rules.airTime()
			T.expectEqual(Rules.bhopTargetSpeed(10000, math.huge, run, T0), Config.BHOP_MAX_SPEED, "plafond")
			T.expectEqual(Rules.bhopTargetSpeed(10000, 55, run, T0), 55, "virage devant")
			local fit = Rules.bhopTargetSpeed(80, math.huge, run, T0)
			T.expectEqual(fit < 60 and fit >= run, true, "fin de marche proche : ralentit (" .. fit .. ")")
			T.expectEqual(Rules.bhopTargetSpeed(80, math.huge, run, 0) > fit, true, "près d'atterrir : plus de marge")
			T.expectEqual(Rules.bhopTargetSpeed(5, 10, run, T0), run, "jamais sous la course")
			near(Rules.timeToLand(Movement.JUMP_VELOCITY), T0, "au décollage : un saut entier")
			T.expectEqual(Rules.timeToLand(-Movement.JUMP_VELOCITY - 5), 0, "sous la hauteur du décollage")
		end)
	end)
end

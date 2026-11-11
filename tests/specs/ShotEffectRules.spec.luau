-- Effets visuels du tir (#54) : fondu du rayon, fin et départ du rayon, effets des tirs relayés.
return function(T, Loader)
	local ShotEffectRules = Loader.new():require("src/shared/ShotEffectRules")

	local ORIGIN = Vector3.new(0, 10, 0)
	local FORWARD = Vector3.new(0, 0, -1)

	T.describe("ShotEffectRules.tracerTransparency (#54)", function()
		T.it("opaque au tir, effacé à la fin de sa vie, de plus en plus vite", function()
			local life = ShotEffectRules.TRACER_LIFETIME
			T.expectEqual(ShotEffectRules.tracerTransparency(0), 0)
			T.expectEqual(ShotEffectRules.tracerTransparency(life), 1)
			T.expectEqual(ShotEffectRules.tracerTransparency(life * 3), 1)
			local half = ShotEffectRules.tracerTransparency(life / 2)
			T.expect(half > 0 and half < 0.5, tostring(half))
		end)

		T.it("reste dans [0, 1], même pour un temps négatif", function()
			T.expectEqual(ShotEffectRules.tracerTransparency(-1), 0)
		end)

		T.it("paliers du fondu : opaque au tir, dernier palier à la fin ou rayon masqué", function()
			local steps = ShotEffectRules.FADE_STEPS
			T.expectEqual(ShotEffectRules.fadeStep(0, false), 0)
			T.expectEqual(ShotEffectRules.fadeStep(ShotEffectRules.TRACER_LIFETIME, false), steps)
			T.expectEqual(ShotEffectRules.fadeStep(0, true), steps)
			local mid = ShotEffectRules.fadeStep(ShotEffectRules.TRACER_LIFETIME / 2, false)
			T.expect(mid > 0 and mid < steps and mid == math.floor(mid), tostring(mid))
		end)
	end)

	T.describe("ShotEffectRules.isTooClose (#54)", function()
		local start, finish = Vector3.new(0, 10, -3), Vector3.new(0, 10, -200)

		T.it("masque un rayon que la caméra traverse (surf vers l'avant après le tir)", function()
			T.expectEqual(ShotEffectRules.isTooClose(start, finish, Vector3.new(0, 10.2, -40)), true)
		end)

		T.it("garde un rayon qui part devant la caméra ou passe à côté", function()
			T.expectEqual(ShotEffectRules.isTooClose(start, finish, Vector3.new(0.6, 10.5, 0)), false)
			T.expectEqual(ShotEffectRules.isTooClose(start, finish, Vector3.new(5, 10, -40)), false)
		end)
	end)

	T.describe("ShotEffectRules.endpoint (#54)", function()
		T.it("finit au point touché", function()
			local hit = Vector3.new(3, 4, -50)
			T.expectEqual(ShotEffectRules.endpoint(ORIGIN, FORWARD, hit, 2048), hit)
		end)

		T.it("dans le vide, finit à la portée maximale dans la direction du tir", function()
			T.expectEqual(ShotEffectRules.endpoint(ORIGIN, FORWARD, nil, 2048), ORIGIN + FORWARD * 2048)
			T.expectEqual(ShotEffectRules.endpoint(ORIGIN, FORWARD * 5, nil, 100), ORIGIN + FORWARD * 100)
		end)
	end)

	T.describe("ShotEffectRules.tracerStart (#54)", function()
		local muzzle = ORIGIN + Vector3.new(0.6, -0.5, -3)

		T.it("part de la bouche du canon, pas de l'œil", function()
			T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, muzzle, ORIGIN + FORWARD * 200), muzzle)
		end)

		T.it("part de l'origine du tir quand l'arme n'a pas de bouche de canon", function()
			T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, nil, ORIGIN + FORWARD * 200), ORIGIN)
		end)

		T.it("pas de rayon quand la bouche du canon est au-delà de l'impact (collé à un mur)", function()
			T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, muzzle, ORIGIN + FORWARD * 2), nil)
		end)

		T.it("pas de rayon plus court que TRACER_MIN_LENGTH", function()
			local min = ShotEffectRules.TRACER_MIN_LENGTH
			T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, nil, ORIGIN + FORWARD * (min / 2)), nil)
			local justAfterMuzzle = muzzle + FORWARD * (min / 2)
			T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, justAfterMuzzle, justAfterMuzzle + FORWARD * 0.1), nil)
		end)
	end)

	T.describe("ShotEffectRules.tracerStart : canon dessiné loin du tir (#54)", function()
		T.it(
			"part de l'origine quand le canon dessiné est sans rapport avec le tir (personnage pas à jour)",
			function()
				local lagging = ORIGIN + Vector3.new(ShotEffectRules.MUZZLE_MAX_OFFSET + 5, 0, 0)
				T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, lagging, ORIGIN + FORWARD * 200), ORIGIN)
			end
		)

		T.it("garde le canon en retard d'un surfeur rapide (moins de MUZZLE_MAX_OFFSET)", function()
			local near = ORIGIN + Vector3.new(ShotEffectRules.MUZZLE_MAX_OFFSET - 1, 0, 0)
			T.expectEqual(ShotEffectRules.tracerStart(ORIGIN, near, ORIGIN + FORWARD * 200), near)
		end)
	end)

	T.describe("ShotEffectRules.clipNearCamera (#54)", function()
		local start = Vector3.new(0, 10, -100)
		local radius = ShotEffectRules.NEAR_CAMERA

		T.it("ne touche pas un rayon qui passe loin de la caméra", function()
			local endpoint = Vector3.new(0, 10, 100)
			local a, b = ShotEffectRules.clipNearCamera(start, endpoint, Vector3.new(50, 10, 0))
			T.expectEqual(a, start)
			T.expectEqual(b, endpoint)
		end)

		T.it("arrête à NEAR_CAMERA de la caméra un tir qui nous touche", function()
			local camera = Vector3.new(0, 10, 0)
			local a, b = ShotEffectRules.clipNearCamera(start, camera + Vector3.new(0, -0.5, 0), camera)
			T.expectEqual(a, start)
			T.expect(b ~= nil, "rayon supprimé")
			T.expect(math.abs((b - camera).Magnitude - radius) < 0.01, tostring(b))
			T.expect(b.Z < camera.Z, "le rayon dépasse la caméra")
		end)

		T.it("arrête avant la caméra un tir qui la traverse (fin derrière nous)", function()
			local camera = Vector3.new(0, 10, 0)
			local _, b = ShotEffectRules.clipNearCamera(start, Vector3.new(0, 10, 100), camera)
			T.expectEqual(b, Vector3.new(0, 10, -radius))
		end)

		T.it("tir qui finit à côté de nous : coupé à l'entrée de la sphère, pas au bout du segment", function()
			local camera = Vector3.new(2, 10, 0)
			local _, b = ShotEffectRules.clipNearCamera(start, Vector3.new(0, 10, 0), camera)
			-- droite x = 0 à 2 studs de la caméra : entrée à z = -sqrt(r² - 4)
			T.expect(b ~= nil and math.abs(b.Z + math.sqrt(radius * radius - 4)) < 0.01, tostring(b))
		end)

		T.it("tireur collé à nous qui tire au loin : le rayon part de la sortie de la sphère", function()
			local camera = Vector3.new(0, 10, 0)
			local muzzle = Vector3.new(1, 10, -0.5)
			local a, b = ShotEffectRules.clipNearCamera(muzzle, Vector3.new(1, 10, -200), camera)
			T.expect(a ~= nil and (a - camera).Magnitude > radius - 0.01, tostring(a))
			T.expectEqual(b, Vector3.new(1, 10, -200))
		end)

		T.it("pas de rayon quand il tient tout entier près de la caméra", function()
			local camera = Vector3.new(0, 10, 0)
			local a, b = ShotEffectRules.clipNearCamera(Vector3.new(0, 10, -1), Vector3.new(0, 10, 1), camera)
			T.expectEqual(a, nil)
			T.expectEqual(b, nil)
		end)
	end)

	T.describe("ShotEffectRules.shouldShow / hasRoom (#54)", function()
		local shooter, me = {}, {}

		T.it("montre le tir d'un autre en partie, mort ou en fin de round", function()
			for _, state in { "SPAWNING", "IN_ROUND", "DEAD", "RESULT" } do
				T.expectEqual(ShotEffectRules.shouldShow(shooter, me, state), true, state)
			end
		end)

		T.it("rien dans les écrans du menu ni sans état", function()
			T.expectEqual(ShotEffectRules.shouldShow(shooter, me, "MENU"), false)
			T.expectEqual(ShotEffectRules.shouldShow(shooter, me, nil), false)
		end)

		T.it("rien pour son propre tir (déjà montré sur le viewmodel) ni sans tireur", function()
			T.expectEqual(ShotEffectRules.shouldShow(me, me, "IN_ROUND"), false)
			T.expectEqual(ShotEffectRules.shouldShow(nil, me, "IN_ROUND"), false)
		end)

		T.it("plus de rayon au-delà de MAX_ACTIVE en cours", function()
			T.expectEqual(ShotEffectRules.hasRoom(0), true)
			T.expectEqual(ShotEffectRules.hasRoom(ShotEffectRules.MAX_ACTIVE - 1), true)
			T.expectEqual(ShotEffectRules.hasRoom(ShotEffectRules.MAX_ACTIVE), false)
		end)
	end)
end

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

		T.it("reste dans [0, 1], même pour un temps négatif ou une durée nulle", function()
			T.expectEqual(ShotEffectRules.tracerTransparency(-1), 0)
			T.expectEqual(ShotEffectRules.tracerTransparency(0.05, 0), 1)
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

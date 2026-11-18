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

	T.describe("TREMPE (#566)", function()
		T.it("s'efface plus lentement que le rayon ordinaire, sur sa propre durée de vie", function()
			local life = ShotEffectRules.tracerLifetime("temper")
			T.expectEqual(life, ShotEffectRules.TEMPER_LIFETIME)
			T.expect(life > ShotEffectRules.TRACER_LIFETIME, "plus long que le rayon ordinaire")
			T.expectEqual(ShotEffectRules.tracerLifetime(nil), ShotEffectRules.TRACER_LIFETIME)
			T.expectEqual(ShotEffectRules.tracerLifetime("pan"), ShotEffectRules.TRACER_LIFETIME)
			T.expectEqual(ShotEffectRules.fadeStep(life, false, life), ShotEffectRules.FADE_STEPS)
			T.expect(
				ShotEffectRules.fadeStep(ShotEffectRules.TRACER_LIFETIME, false, life) < ShotEffectRules.FADE_STEPS
			)
		end)

		T.it("écailles réparties entre les tronçons, le reste près de la bouche", function()
			local sections = #ShotEffectRules.TEMPER_FLAKE_SECTIONS
			local counts = ShotEffectRules.temperFlakeSplit(sections * 4 + 1)
			T.expectEqual(#counts, sections)
			T.expectEqual(counts[1], 5)
			T.expectEqual(counts[sections], 4)
			local total = 0
			for _, n in ShotEffectRules.temperFlakeSplit(20) do
				total += n
			end
			T.expectEqual(total, 20)
		end)

		T.it("écailles proportionnelles à la longueur du rayon, bornées", function()
			T.expectEqual(ShotEffectRules.temperFlakeCount(0), ShotEffectRules.TEMPER_FLAKES_MIN)
			T.expectEqual(ShotEffectRules.temperFlakeCount(10000), ShotEffectRules.TEMPER_FLAKES_MAX)
			local mid = ShotEffectRules.temperFlakeCount(60)
			T.expect(
				mid > ShotEffectRules.TEMPER_FLAKES_MIN and mid < ShotEffectRules.TEMPER_FLAKES_MAX,
				"entre les bornes"
			)
		end)

		T.it("de la paille à la bouche au bleu vers l'impact, dans les limites d'une ColorSequence", function()
			local points = ShotEffectRules.temperKeypoints(0, 0.37)
			T.expectEqual(#points, ShotEffectRules.TEMPER_KEYPOINTS)
			T.expect(#points <= 20, "20 points au plus")
			T.expectEqual(points[1][1], 0)
			T.expectEqual(points[#points][1], 1)
			for i, point in points do
				for c = 2, 4 do
					T.expect(point[c] >= 0 and point[c] <= 255, "couleur bornée au point " .. i)
				end
				if i > 1 then
					T.expect(point[1] > points[i - 1][1], "positions croissantes")
				end
			end
			local first, last = points[1], points[#points]
			T.expect(first[2] > first[4], "paille (rouge > bleu) à la bouche")
			T.expect(last[4] > last[2], "bleu dominant vers l'impact")
		end)

		T.it("les franges défilent : deux instants donnent deux dégradés", function()
			local a = ShotEffectRules.temperKeypoints(0, 0.5)
			local b = ShotEffectRules.temperKeypoints(0.1, 0.5)
			local differs = false
			for i = 1, #a do
				differs = differs or math.abs(a[i][2] - b[i][2]) > 1
			end
			T.expect(differs, "les couleurs bougent")
		end)
	end)

	T.describe("PAN ! (#566)", function()
		T.it("le rayon part du bord de l'explosion, sauf si l'impact est trop proche", function()
			local finish = ORIGIN + FORWARD * 100
			local center = ORIGIN + FORWARD * 2
			local start = ShotEffectRules.panTracerStart(ORIGIN, finish, center, 3)
			T.expectNear((start - ORIGIN).Magnitude, 2 + 3 * ShotEffectRules.PAN_TRACER_GAP)
			local close = ORIGIN + FORWARD * 3
			T.expectEqual(ShotEffectRules.panTracerStart(ORIGIN, close, center, 3), ORIGIN)
		end)

		T.it("jaillit, dépasse, se pose puis s'efface sur sa durée de vie", function()
			local scale0 = ShotEffectRules.panFrame(0)
			T.expectEqual(scale0, 0)
			local peak = ShotEffectRules.panFrame(ShotEffectRules.PAN_POP)
			T.expectNear(peak, ShotEffectRules.PAN_OVERSHOOT)
			local settled, visible = ShotEffectRules.panFrame(ShotEffectRules.PAN_POP + ShotEffectRules.PAN_SETTLE)
			T.expectNear(settled, 1)
			T.expectEqual(visible, 0)
			local _, gone = ShotEffectRules.panFrame(ShotEffectRules.PAN_LIFETIME)
			T.expectEqual(gone, 1)
			T.expectEqual(ShotEffectRules.panTurn(0), ShotEffectRules.PAN_TURN)
			T.expectEqual(ShotEffectRules.panTurn(ShotEffectRules.PAN_POP + ShotEffectRules.PAN_SETTLE), 0)
			local mid = ShotEffectRules.panTurn(ShotEffectRules.PAN_POP)
			T.expect(mid > 0 and mid < ShotEffectRules.PAN_TURN, "pivote vers la caméra pendant le pop")
			local _, fading = ShotEffectRules.panFrame(ShotEffectRules.PAN_LIFETIME * 0.8)
			T.expect(fading > 0 and fading < 1, "s'efface sur la fin")
		end)

		T.it("se place devant le canon vers l'impact, plus petit et plus près chez le tireur", function()
			local finish = ORIGIN + FORWARD * 100
			local pos, width = ShotEffectRules.panPlacement(ORIGIN, finish, false)
			T.expectNear((pos - ORIGIN).Magnitude, ShotEffectRules.PAN_AHEAD)
			T.expect((pos - ORIGIN):Dot(FORWARD) > 0, "devant le canon")
			T.expectEqual(width, ShotEffectRules.PAN_WIDTH)
			local localPos, localWidth = ShotEffectRules.panPlacement(ORIGIN, finish, true)
			T.expect(localWidth < width, "plus petit chez le tireur")
			T.expect((localPos - ORIGIN).Magnitude <= (pos - ORIGIN).Magnitude, "plus près chez le tireur")
			local demo = ShotEffectRules.panPlacement(ORIGIN, finish, false, ShotEffectRules.PAN_AHEAD_DEMO)
			T.expectNear((demo - ORIGIN).Magnitude, ShotEffectRules.PAN_AHEAD_DEMO)
			local near = ShotEffectRules.panPlacement(ORIGIN, ORIGIN + FORWARD * 1, false)
			T.expectNear((near - ORIGIN).Magnitude, 0.5, 1e-6)
		end)
	end)

	T.describe("BALISE (#567)", function()
		T.it("le ruban se déroule de la bouche à l'impact, reste tendu, puis se rétracte vers l'impact", function()
			local tail, head = ShotEffectRules.baliseSpan(0)
			T.expectEqual(tail, 0)
			T.expectEqual(head, 0)
			tail, head = ShotEffectRules.baliseSpan(ShotEffectRules.BALISE_UNROLL / 2)
			T.expectEqual(tail, 0)
			T.expectNear(head, 0.5)
			tail, head = ShotEffectRules.baliseSpan(ShotEffectRules.BALISE_RETRACT_FROM)
			T.expectEqual(tail, 0)
			T.expectEqual(head, 1)
			local mid = (ShotEffectRules.BALISE_RETRACT_FROM + ShotEffectRules.BALISE_LIFETIME) / 2
			tail = ShotEffectRules.baliseSpan(mid)
			T.expect(tail > 0 and tail < 0.5, "rétraction lente puis rapide : " .. tail)
			tail, head = ShotEffectRules.baliseSpan(ShotEffectRules.BALISE_LIFETIME)
			T.expectEqual(tail, 1)
			T.expectEqual(head, 1)
		end)

		T.it("vit BALISE_LIFETIME, style activé et porté par l'item BALISE", function()
			T.expectEqual(ShotEffectRules.tracerLifetime("balise"), ShotEffectRules.BALISE_LIFETIME)
			T.expectEqual(ShotEffectRules.styleOf("effect.balise"), "balise")
			T.expect(ShotEffectRules.isEnabled("balise"), "BALISE désactivé")
		end)

		T.it("la marque d'impact suit la distance de la caméra, bornée", function()
			local bounds = ShotEffectRules.BALISE_MARK_SIZE
			T.expectEqual(ShotEffectRules.baliseMarkSize(0), bounds[1])
			T.expectEqual(ShotEffectRules.baliseMarkSize(1e6), bounds[2])
			local d = (bounds[1] + bounds[2]) / 2 / ShotEffectRules.BALISE_MARK_ANGLE
			T.expectNear(ShotEffectRules.baliseMarkSize(d), d * ShotEffectRules.BALISE_MARK_ANGLE)
		end)
	end)

	T.describe("CIRCUIT (#567)", function()
		-- Tirage fixe : alterne le bas et le haut de chaque intervalle
		local function seq()
			local n = 0
			return function(min, max)
				n += 1
				return if n % 2 == 0 then max else min
			end
		end

		T.it("la piste part de la bouche, finit sur l'impact, et n'a que des paliers et des coudes à 45°", function()
			for _, length in { 8, 20, 60, 300, 2000 } do
				local path = ShotEffectRules.circuitPath(length, seq())
				T.expectEqual(path[1][1], 0)
				T.expectEqual(path[1][2], 0)
				T.expectEqual(path[#path][1], length)
				T.expectEqual(path[#path][2], 0)
				T.expect(#path - 1 <= ShotEffectRules.CIRCUIT_MAX_SEGMENTS, "trop de segments : " .. #path - 1)
				for i = 2, #path do
					local da, dl = path[i][1] - path[i - 1][1], math.abs(path[i][2] - path[i - 1][2])
					T.expect(da > 0, "la piste recule à " .. i .. " (" .. length .. " studs)")
					T.expect(dl < 1e-9 or math.abs(da - dl) < 1e-9, "coude qui n'est pas à 45° à " .. i)
					T.expect(math.abs(path[i][2]) <= ShotEffectRules.CIRCUIT_JOG + 1e-9, "palier hors des bornes")
				end
				local lastRun = path[#path][1] - path[#path - 1][1]
				if #path > 2 then
					T.expect(lastRun >= ShotEffectRules.CIRCUIT_LAST_RUN - 1e-9, "arrivée trop courte : " .. lastRun)
				end
			end
		end)

		T.it("un tir court a une piste droite", function()
			local path = ShotEffectRules.circuitPath(ShotEffectRules.CIRCUIT_MIN_LENGTH - 1, seq())
			T.expectEqual(#path, 2)
		end)

		T.it("un point de la piste suit ses coudes, borné aux deux bouts", function()
			local path = { { 0, 0 }, { 2, 0 }, { 3, 1 }, { 6, 1 } }
			T.expectNear(ShotEffectRules.circuitLength(path), 2 + math.sqrt(2) + 3)
			local a, l = ShotEffectRules.circuitPointAt(path, 1)
			T.expectNear(a, 1)
			T.expectNear(l, 0)
			a, l = ShotEffectRules.circuitPointAt(path, 2 + math.sqrt(2) / 2)
			T.expectNear(a, 2.5)
			T.expectNear(l, 0.5)
			a, l = ShotEffectRules.circuitPointAt(path, 99)
			T.expectEqual(a, 6)
			T.expectEqual(l, 1)
			a = ShotEffectRules.circuitPointAt(path, -3)
			T.expectEqual(a, 0)
		end)

		T.it("se construit, envoie l'impulsion puis s'éteint de la bouche vers l'impact", function()
			local built, pulse = ShotEffectRules.circuitProgress(0)
			T.expectEqual(built, 0)
			T.expectEqual(pulse, nil)
			built, pulse = ShotEffectRules.circuitProgress(ShotEffectRules.CIRCUIT_BUILD)
			T.expectEqual(built, 1)
			T.expect(pulse ~= nil and pulse > 0, "impulsion en route à la fin de la construction")
			local after = ShotEffectRules.CIRCUIT_PULSE_FROM + ShotEffectRules.CIRCUIT_PULSE_TIME + 0.01
			T.expectEqual(select(2, ShotEffectRules.circuitProgress(after)), nil)
			local t = ShotEffectRules.CIRCUIT_FADE_FROM + ShotEffectRules.CIRCUIT_FADE_TIME / 2
			T.expect(ShotEffectRules.circuitFade(t, 0) > ShotEffectRules.circuitFade(t, 1), "bouche éteinte d'abord")
			T.expectEqual(ShotEffectRules.circuitFade(0, 0), 0)
			T.expectNear(ShotEffectRules.circuitFade(ShotEffectRules.CIRCUIT_LIFETIME, 1), 1)
		end)

		T.it("style activé, porté par l'item CIRCUIT ; cube d'impact selon la distance", function()
			T.expectEqual(ShotEffectRules.styleOf("effect.circuit"), "circuit")
			local bounds = ShotEffectRules.CIRCUIT_CUBE_SIZE
			T.expectEqual(ShotEffectRules.circuitCubeSize(0), bounds[1])
			T.expectEqual(ShotEffectRules.circuitCubeSize(1e6), bounds[2])
		end)

		T.it("le cube jaillit, dépasse, se pose puis s'efface sur sa vie", function()
			local life = ShotEffectRules.CIRCUIT_CUBE_LIFE_IMPACT
			T.expectEqual(ShotEffectRules.circuitCubeFrame(0, life), 0)
			T.expectNear(
				ShotEffectRules.circuitCubeFrame(ShotEffectRules.CIRCUIT_CUBE_POP, life),
				ShotEffectRules.CIRCUIT_CUBE_OVERSHOOT
			)
			local settled, clear = ShotEffectRules.circuitCubeFrame(
				ShotEffectRules.CIRCUIT_CUBE_POP + ShotEffectRules.CIRCUIT_CUBE_SETTLE,
				life
			)
			T.expectEqual(settled, 1)
			T.expectEqual(clear, 0)
			T.expectEqual(select(2, ShotEffectRules.circuitCubeFrame(life, life)), 1)
		end)

		T.it("le réseau d'impact part du bord du cube, dans des directions différentes, coudes de 45°", function()
			for _, draw in
				{
					seq(),
					function(min, max)
						return (min + max) / 2
					end,
				}
			do
				local net = ShotEffectRules.circuitBranches(draw)
				local counts = ShotEffectRules.CIRCUIT_BRANCHES
				T.expect(#net >= counts[1] and #net <= counts[2], "nombre de pistes : " .. #net)
				local seen = {}
				for _, branch in net do
					local first = branch[1]
					T.expect(math.max(math.abs(first[1]), math.abs(first[2])) >= 0.5 - 1e-9, "départ dans le cube")
					local dir = math.round(math.deg(math.atan2(branch[2][2] - first[2], branch[2][1] - first[1])))
					T.expect(not seen[dir], "deux pistes dans la même direction")
					seen[dir] = true
					T.expect(#branch - 2 <= ShotEffectRules.CIRCUIT_BRANCH_TURNS[2], "trop de coudes")
					for i = 3, #branch do
						local a1 = math.atan2(branch[i - 1][2] - branch[i - 2][2], branch[i - 1][1] - branch[i - 2][1])
						local a2 = math.atan2(branch[i][2] - branch[i - 1][2], branch[i][1] - branch[i - 1][1])
						local turn = math.abs(math.deg(a2 - a1)) % 360
						turn = math.min(turn, 360 - turn)
						T.expectNear(turn, 45, 1e-6)
					end
				end
			end
		end)
	end)
end

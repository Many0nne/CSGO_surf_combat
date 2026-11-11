return function(T, Loader)
	local Rules = Loader.new():require("src/shared/MovementGuardRules")
	local Config = Loader.new():require("src/shared/MovementConfig")

	local V = Vector3.new
	local INTERVAL = 1 / Config.NET_SYNC_RATE
	local STAND = 2.5 -- hauteur du centre d'un personnage debout au-dessus du sol

	-- Cette méthode permet de décrire une boîte alignée sur les axes lorsqu'un test pose une pièce de la map.
	local function box(min: Vector3, max: Vector3)
		return { CFrame = CFrame.new((min + max) / 2), Size = max - min }
	end

	-- Cette méthode permet de savoir si un segment traverse une boîte orientée lorsque la géométrie simulée remplace le
	-- raycast serveur : méthode des tranches dans le repère de la boîte ; comme un raycast Roblox, un départ à
	-- l'intérieur de la boîte ne la touche pas.
	local function segmentHits(a: Vector3, b: Vector3, part): boolean
		local la = part.CFrame:PointToObjectSpace(a)
		local lb = part.CFrame:PointToObjectSpace(b)
		local half = part.Size / 2
		local d = lb - la
		local tmin, tmax = 0, 1
		local inside = true
		for _, axis in { "X", "Y", "Z" } do
			local o, dir, h = (la :: any)[axis], (d :: any)[axis], (half :: any)[axis]
			if math.abs(o) > h then
				inside = false
			end
			if math.abs(dir) < 1e-9 then
				if math.abs(o) > h then
					return false
				end
			else
				local t1, t2 = (-h - o) / dir, (h - o) / dir
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
				if tmin > tmax then
					return false
				end
			end
		end
		return not inside
	end

	-- Cette méthode permet de construire la géométrie vue par les règles lorsqu'un test simule une map : parois
	-- (rayons et supports), volumes d'échelle et boosts (vitesse verticale imposée).
	local function geometryOf(parts, ladders, boosts)
		return {
			isBlocked = function(a: Vector3, b: Vector3): boolean
				for _, part in parts do
					if segmentHits(a, b, part) then
						return true
					end
				end
				return false
			end,
			support = function(from: Vector3, to: Vector3): (boolean, number)
				local launchVy = 0
				for _, boost in boosts or {} do
					if Rules.touchesVolume(from, to, boost.CFrame, boost.Size) then
						launchVy = math.max(launchVy, boost.vy)
					end
				end
				for _, ladder in ladders or {} do
					if Rules.touchesVolume(from, to, ladder.CFrame, ladder.Size) then
						return true, launchVy
					end
				end
				return Rules.supportedAlong(parts, from, to), launchVy
			end,
		}
	end

	-- Cette méthode permet de produire une gigue pseudo-aléatoire reproductible (0..1) lorsqu'un test décale
	-- l'arrivée des paquets.
	local seed = 4242
	local function noise(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end

	-- Cette méthode permet d'échantillonner une trajectoire comme le client (un paquet par SEND_INTERVAL) lorsqu'un
	-- test simule un joueur : heure d'arrivée = envoi + latence + gigue (paquets rangés par arrivée).
	-- fps : cadence d'images du client, qui envoie comme CharacterSync.send (temps accumulé, reste reporté).
	local function packets(path: (number) -> Vector3, duration: number, jitter: number?, fps: number?)
		local list = {}
		local sendTimes = {}
		if fps then
			local accumulator, clock = 0, 0
			while clock < duration do
				clock += 1 / fps
				accumulator += 1 / fps
				if accumulator >= INTERVAL then
					accumulator = math.min(accumulator - INTERVAL, INTERVAL / 2)
					table.insert(sendTimes, clock)
				end
			end
		else
			for i = 1, math.floor(duration / INTERVAL) do
				table.insert(sendTimes, i * INTERVAL)
			end
		end
		for _, sentAt in sendTimes do
			table.insert(list, { t = sentAt + 0.05 + (jitter or 0) * noise(), pos = path(sentAt) })
		end
		table.sort(list, function(a, b)
			return a.t < b.t
		end)
		return list
	end

	-- Cette méthode permet de rejouer des paquets devant les règles comme CharacterSync lorsqu'un test simule une
	-- partie : une violation en mode bloquant garde lastPos (paquet refusé), sinon la position est appliquée.
	local function replay(list, geometry, start: Vector3, launchVy: number?)
		local guard = Rules.newGuard(0, start, launchVy)
		local lastPos = start
		local verdicts = {}
		for _, packet in list do
			local verdict = Rules.judge(guard, lastPos, packet.pos, packet.t, geometry)
			if verdict then
				verdict.t = packet.t
				table.insert(verdicts, verdict)
			end
			if verdict and verdict.enforce then
				Rules.restart(guard.flight, packet.t, lastPos.Y) -- comme CharacterSync.refuse
			else
				lastPos = packet.pos
			end
		end
		return verdicts, guard
	end

	-- Cette méthode permet de résumer les violations lorsqu'un test échoue (règle, heure, détail).
	local function describe(verdicts): string
		local lines = {}
		for _, v in verdicts do
			table.insert(lines, string.format("%s à %.2f s (%s)", v.rule, v.t, v.detail))
		end
		return table.concat(lines, " ; ")
	end

	-- Cette méthode permet de simuler la chute libre du client (pas fixe de 64 Hz, demi-pas de gravité avant et après
	-- le déplacement, chute plafonnée) lorsqu'un test a besoin d'une trajectoire honnête indépendante des règles.
	local function freeFall(y0: number, vy0: number, t: number): number
		local dt = 1 / 64
		local y, vy = y0, vy0
		local steps = math.floor(t / dt)
		for _ = 1, steps do
			vy += Config.GRAVITY * 0.5 * dt
			y += vy * dt
			vy += Config.GRAVITY * 0.5 * dt
			vy = math.max(vy, -Config.MAX_FALL_SPEED)
		end
		return y + vy * (t - steps * dt)
	end

	local FLOOR = box(V(-2000, -10, -2000), V(2000, 0, 2000))
	local HOP = 2 * Config.JUMP_VELOCITY / -Config.GRAVITY -- durée d'un saut (s)

	-- Cette méthode permet de calculer la hauteur du centre pendant un saut lancé depuis le sol lorsqu'un test enchaîne
	-- des sauts : arc exact de JUMP_VELOCITY sous GRAVITY.
	local function hop(tau: number): number
		return STAND + Config.JUMP_VELOCITY * tau + 0.5 * Config.GRAVITY * tau * tau
	end

	T.describe("MovementGuardRules.crossesWall (noclip)", function()
		T.it("signale une marche à travers un mur fin", function()
			local wall = box(V(-0.5, 0, -10), V(0.5, 10, 10))
			local geometry = geometryOf({ wall })
			local crossed = 0
			for i = 0, 7 do
				local from, to = V(-5 + 1.5 * i, 3, 0), V(-5 + 1.5 * (i + 1), 3, 0)
				if Rules.crossesWall(from, to, geometry.isBlocked) then
					crossed += 1
				end
			end
			T.expectEqual(crossed, 1)
		end)

		T.it("signale une chute à travers un sol", function()
			local slab = box(V(-50, -1, -50), V(50, 0, 50))
			T.expect(Rules.crossesWall(V(0, STAND, 0), V(0, -3, 0), geometryOf({ slab }).isBlocked))
		end)

		T.it(
			"laisse passer un virage serré à 100 studs/s autour d'un coin de mur (la corde coupe l'angle)",
			function()
				local block = box(V(-20, 0, -20), V(0, 10, 0))
				local isBlocked = geometryOf({ block }).isBlocked
				-- Centre à 1 stud des faces : le long de z = 1, quart de cercle autour de l'arête, puis le long de x = 1
				local function at(s: number): Vector3
					if s < 0 then
						return V(s, 3, 1)
					elseif s <= math.pi / 2 then
						return V(math.sin(s), 3, math.cos(s))
					end
					return V(1, 3, -(s - math.pi / 2))
				end
				local cut = false
				for i = 0, 20 do
					local s0 = -10 + i * 0.7
					local from, to = at(s0), at(s0 + 5)
					cut = cut or isBlocked(from, to)
					T.expect(not Rules.crossesWall(from, to, isBlocked), "virage pris pour un noclip")
				end
				T.expect(cut, "le scénario doit couper l'angle au moins une fois")
			end
		)

		T.it("laisse passer un surf à 300 studs/s par-dessus l'arête d'une rampe", function()
			-- Rampe en toit : arête en (0, 0), faces à 45°, centre du surfeur à 2 studs des faces
			local roof = {
				CFrame = CFrame.new(0, -10 * math.sqrt(2), 0) * CFrame.Angles(0, 0, math.pi / 4),
				Size = V(20, 20, 40),
			}
			local isBlocked = geometryOf({ roof }).isBlocked
			local s2 = math.sqrt(2)
			local function at(s: number): Vector3
				if s < 0 then
					return V(-2 / s2, 2 / s2, 0) + V(1 / s2, 1 / s2, 0) * s
				elseif s <= math.pi then
					local angle = 3 * math.pi / 4 - s / 2
					return V(2 * math.cos(angle), 2 * math.sin(angle), 0)
				end
				return V(2 / s2, 2 / s2, 0) + V(1 / s2, -1 / s2, 0) * (s - math.pi)
			end
			local cut = false
			for i = 0, 15 do
				local s0 = -14 + i
				local from, to = at(s0), at(s0 + 15)
				cut = cut or isBlocked(from, to)
				T.expect(not Rules.crossesWall(from, to, isBlocked), "arête de rampe prise pour un noclip")
			end
			T.expect(cut, "le scénario doit couper l'arête au moins une fois")
		end)

		T.it("ne teste pas un segment libre ni un segment nul", function()
			local calls = 0
			local function isBlocked(): boolean
				calls += 1
				return false
			end
			T.expect(not Rules.crossesWall(V(0, 0, 0), V(10, 0, 0), isBlocked))
			T.expectEqual(calls, 1)
			T.expect(not Rules.crossesWall(V(0, 0, 0), V(0, 0, 0), isBlocked))
			T.expectEqual(calls, 1)
		end)
	end)

	T.describe("MovementGuardRules.supports", function()
		T.it("un sol porte un joueur debout ou qui vient de rebondir, pas un joueur haut", function()
			T.expect(Rules.supports(FLOOR, V(0, STAND, 0)))
			T.expect(Rules.supports(FLOOR, V(0, STAND + 3.5, 0)))
			T.expect(not Rules.supports(FLOOR, V(0, 10, 0)))
		end)

		T.it("une rampe de surf porte, un mur vertical non, un plafond non", function()
			local ramp = { CFrame = CFrame.Angles(0, 0, math.rad(60)), Size = V(100, 10, 40) }
			local normal = ramp.CFrame.UpVector
			T.expect(Rules.supports(ramp, ramp.CFrame.Position + normal * 7))
			local wall = box(V(0, 0, -10), V(2, 100, 10))
			T.expect(not Rules.supports(wall, V(-1.5, 50, 0)))
			local ceiling = box(V(-10, 10, -10), V(10, 12, 10))
			T.expect(not Rules.supports(ceiling, V(0, 8, 0)))
		end)
	end)

	T.describe("MovementGuardRules.judge (vol, journal seul)", function()
		T.it("un saut normal n'est pas signalé", function()
			local function path(t: number): Vector3
				local y = if t > 0.5 and t < 0.5 + HOP then hop(t - 0.5) else STAND
				return V(30 * t, y, 0)
			end
			local verdicts = replay(packets(path, 3), geometryOf({ FLOOR }), path(0))
			T.expectEqual(#verdicts, 0, describe(verdicts))
		end)

		T.it("10 s de bhop à 90 studs/s avec 80 ms de gigue ne sont pas signalés", function()
			local function path(t: number): Vector3
				return V(90 * t, hop(t % HOP), 0)
			end
			local verdicts = replay(packets(path, 10, 0.08), geometryOf({ FLOOR }), V(0, STAND, 0))
			T.expectEqual(#verdicts, 0, describe(verdicts))
		end)

		T.it("une chute de 300 studs (vitesse de chute plafonnée) avec gigue n'est pas signalée", function()
			local tower = box(V(-30, 0, -10), V(0, 300, 10))
			local function path(t: number): Vector3
				local x = -15 + 30 * t
				if x <= 0 then
					return V(x, 300 + STAND, 0)
				end
				return V(x, math.max(STAND, freeFall(300 + STAND, 0, t - 0.5)), 0)
			end
			local verdicts = replay(packets(path, 5, 0.08), geometryOf({ FLOOR, tower }), path(0))
			T.expectEqual(#verdicts, 0, describe(verdicts))
		end)

		T.it(
			"bhop et chute de 300 studs sans signalement à 15, 30, 45 et 144 FPS, gigue de 80 ms, 10 graines",
			function()
				local tower = box(V(-30, 0, -10), V(0, 300, 10))
				local geometry = geometryOf({ FLOOR, tower })
				local function fall(t: number): Vector3
					local x = -15 + 30 * t
					return V(x, if x <= 0 then 300 + STAND else math.max(STAND, freeFall(300 + STAND, 0, t - 0.5)), 0)
				end
				local function bhop(t: number): Vector3
					return V(90 * t, hop(t % HOP), 0)
				end
				for _, fps in { 15, 30, 45, 144 } do
					for run = 1, 10 do
						seed = run * 7919
						for _, path in { fall, bhop } do
							local verdicts = replay(packets(path, 6, 0.08, fps), geometry, path(0))
							T.expectEqual(
								#verdicts,
								0,
								string.format("%d FPS, graine %d : %s", fps, run, describe(verdicts))
							)
						end
					end
				end
			end
		)

		T.it(
			"un surf sur une rampe à 60° puis une sortie à 130 studs/s vers le haut ne sont pas signalés",
			function()
				local up = V(-math.sin(math.rad(60)), math.cos(math.rad(60)), 0) -- normale de la face
				local along = V(math.cos(math.rad(60)), math.sin(math.rad(60)), 0) -- pente, vers le haut
				local ramp = { CFrame = CFrame.new(-up * 5) * CFrame.Angles(0, 0, math.rad(60)), Size = V(100, 10, 40) }
				local speed = 150
				local leaveAt = 95 / speed
				local function path(t: number): Vector3
					if t <= leaveAt then
						return up * 2 + along * (-45 + speed * t)
					end
					local exit = up * 2 + along * 50
					local s = t - leaveAt
					local v = along * speed
					return V(exit.X + v.X * s, freeFall(exit.Y, v.Y, s), 0)
				end
				local verdicts = replay(packets(path, 4, 0.05), geometryOf({ ramp }), path(0))
				T.expectEqual(#verdicts, 0, describe(verdicts))
			end
		)

		local wall = box(V(0, 0, -10), V(2, 60, 10))
		local ladder = box(V(-2.5, 0, -2.5), V(0, 65.6, 2.5))
		-- Cette méthode permet de suivre un joueur qui grimpe l'échelle à LADDER_CLIMB_SPEED puis passe sur le toit.
		local function climb(t: number): Vector3
			local top = 60 + STAND
			local y = STAND + Config.LADDER_CLIMB_SPEED * t
			if y < top then
				return V(-1.5, y, 0)
			end
			return V(math.min(-1.5 + 10 * (t - (top - STAND) / Config.LADDER_CLIMB_SPEED), 1), top, 0)
		end

		T.it("une échelle grimpée jusqu'au toit n'est pas signalée", function()
			local verdicts = replay(packets(climb, 4), geometryOf({ FLOOR, wall }, { ladder }), climb(0))
			T.expectEqual(#verdicts, 0, describe(verdicts))
		end)

		T.it("la même montée le long d'un mur sans échelle est signalée", function()
			local verdicts = replay(packets(climb, 4), geometryOf({ FLOOR, wall }), climb(0))
			T.expect(#verdicts > 0)
			T.expectEqual(verdicts[1].rule, "flight")
			T.expectEqual(verdicts[1].enforce, false)
		end)

		local geyser = box(V(-2, 0, -2), V(2, 4, 2))
		local GEYSER_VY = 150
		-- Cette méthode permet de suivre un joueur qui marche dans un geyser puis retombe sous la gravité.
		local function boosted(t: number): Vector3
			local enterAt = 7 / 20 -- de x = -10 à x = -3 (bord du volume élargi du rayon)
			if t <= enterAt then
				return V(-10 + 20 * t, STAND, 0)
			end
			local s = t - enterAt
			return V(-3 + 20 * s, math.max(STAND, freeFall(STAND, GEYSER_VY, s)), 0)
		end

		T.it("un geyser qui projette à 150 studs/s n'est pas signalé", function()
			geyser.vy = GEYSER_VY
			local verdicts = replay(packets(boosted, 5, 0.05), geometryOf({ FLOOR }, {}, { geyser }), boosted(0))
			T.expectEqual(#verdicts, 0, describe(verdicts))
		end)

		T.it("un geyser dépassé à pied ne donne plus d'élan au saut suivant", function()
			geyser.vy = GEYSER_VY
			local geometry = geometryOf({ FLOOR }, {}, { geyser })
			-- Traverse le geyser en marchant (sans être projeté, recharge), s'éloigne, puis « saute » à 60 studs et plane
			local function path(t: number): Vector3
				local x = -10 + 20 * t
				if t < 2 then
					return V(x, STAND, 0)
				end
				return V(x, STAND + math.min(60, 120 * (t - 2)), 0)
			end
			local verdicts = replay(packets(path, 5), geometry, path(0))
			T.expect(#verdicts > 0, "le vol après le geyser doit être signalé")
		end)

		T.it(
			"un tricheur qui plane en alternant un paquet haut et un paquet bas (±25 ou ±15 studs) est signalé",
			function()
				for _, amplitude in { 25, 15 } do
					local i = 0
					local function path(t: number): Vector3
						i += 1
						local high = if t < 1 then STAND + 40 * t else STAND + 40
						return V(10 * t, if i % 2 == 0 then high else high - amplitude, 0)
					end
					local verdicts = replay(packets(path, 5), geometryOf({ FLOOR }), V(0, STAND, 0))
					T.expect(#verdicts > 0, "l'alternance de " .. amplitude .. " studs ne doit pas masquer le vol")
				end
			end
		)

		T.it("un lancement depuis le soleil n'est pas signalé, même au premier paquet tardif", function()
			local launch = V(100, 80, 0)
			local origin = V(0, 500, 0)
			local function path(t: number): Vector3
				return V(origin.X + launch.X * t, math.max(STAND, freeFall(origin.Y, launch.Y, t)), 0)
			end
			local list = packets(path, 6, 0.05)
			-- Les 0,3 premières secondes de paquets sont perdues
			while list[1].t < 0.35 do
				table.remove(list, 1)
			end
			local verdicts = replay(list, geometryOf({ FLOOR }), origin, launch.Y)
			T.expectEqual(#verdicts, 0, describe(verdicts))
		end)

		T.it("un joueur qui plane au-dessus de la map est signalé en moins de 1,5 s, puis régulièrement", function()
			local function path(t: number): Vector3
				return V(10 * t, if t < 1 then STAND + 40 * t else STAND + 40, 0)
			end
			local verdicts = replay(packets(path, 5), geometryOf({ FLOOR }), V(0, STAND, 0))
			T.expect(#verdicts >= 3, describe(verdicts))
			T.expectEqual(verdicts[1].rule, "flight")
			T.expect(verdicts[1].t < 1 + 1.5, describe(verdicts))
			T.expect(#verdicts < 20, "pas un signalement par paquet : " .. #verdicts)
		end)

		T.it("une descente lente (parachute) depuis un toit est signalée", function()
			local roof = box(V(-30, 0, -10), V(0, 100, 10))
			local function path(t: number): Vector3
				local x = -15 + 30 * t
				return V(x, if x <= 0 then 100 + STAND else 100 + STAND - 5 * (t - 0.5), 0)
			end
			local verdicts = replay(packets(path, 5), geometryOf({ FLOOR, roof }), path(0))
			T.expect(#verdicts > 0)
		end)
	end)

	T.describe("MovementGuardRules.judge (modes bloquants)", function()
		T.it(
			"un paquet qui traverse un mur en volant est refusé si le vol est bloquant et le noclip en journal seul",
			function()
				Rules.ENFORCE_FLIGHT = true
				local ok, err = pcall(function()
					local wall = box(V(19.5, 0, -10), V(20.5, 100, 10))
					local geometry = geometryOf({ FLOOR, wall })
					-- Plane à 40 studs depuis 1,5 s (enveloppe partie de là à l'arrêt), puis un paquet de plus et la traversée
					local guard = Rules.newGuard(0, V(18, 42.5, 0))
					guard.fresh = false
					Rules.restart(guard.flight, 0, 42.5)
					Rules.judge(guard, V(18, 42.5, 0), V(19, 42.5, 0), 1.45, geometry)
					local last = Rules.judge(guard, V(19, 42.5, 0), V(21, 42.5, 0), 1.5, geometry)
					T.expect(last ~= nil, "le paquet qui traverse doit être signalé")
					T.expectEqual(last.rule, "flight")
					T.expectEqual(last.enforce, true)
				end)
				Rules.ENFORCE_FLIGHT = false
				assert(ok, err)
			end
		)

		T.it(
			"noclip : journal seul signale une fois et applique ; bloquant refuse chaque paquet de l'autre côté",
			function()
				local wall = box(V(-0.5, 0, -10), V(0.5, 10, 10))
				local geometry = geometryOf({ FLOOR, wall })
				local function path(t: number): Vector3
					return V(-5 + 30 * t, STAND, 0)
				end
				local logged = replay(packets(path, 1), geometry, path(0))
				T.expectEqual(#logged, 1, describe(logged))
				T.expectEqual(logged[1].rule, "noclip")
				T.expectEqual(logged[1].enforce, false)

				Rules.ENFORCE_NOCLIP = true
				local ok, err = pcall(function()
					local refused = replay(packets(path, 1), geometry, path(0))
					T.expect(#refused > 1, describe(refused))
					for _, v in refused do
						T.expectEqual(v.rule, "noclip")
						T.expectEqual(v.enforce, true)
					end
				end)
				Rules.ENFORCE_NOCLIP = false
				assert(ok, err)
			end
		)

		T.it(
			"vol : un tricheur qui se fige en plein bhop est refusé une fois, la chute après correction ne l'est pas",
			function()
				Rules.ENFORCE_FLIGHT = true
				local ok, err = pcall(function()
					local geometry = geometryOf({ FLOOR })
					local guard = Rules.newGuard(0, V(0, STAND, 0))
					local lastPos = V(0, STAND, 0)
					local verdicts = {}
					local correctedAt: number? = nil
					local correctedFrom = Vector3.zero
					local hoverAt: Vector3? = nil
					for i = 1, 100 do
						local sentAt = i * INTERVAL
						local arrival = sentAt + 0.05
						local pos
						if correctedAt then
							-- Le client applique la correction 0,15 s après son envoi (aller-retour), puis tombe vitesse nulle
							local appliedAt = correctedAt + 0.15
							if sentAt < appliedAt then
								continue -- paquet parti avant la correction : ignoré par CharacterSync (awaitsAck)
							end
							pos =
								V(correctedFrom.X, math.max(STAND, freeFall(correctedFrom.Y, 0, sentAt - appliedAt)), 0)
						elseif i >= 40 then
							-- Le tricheur monte de 30 studs et plane jusqu'à sa correction
							hoverAt = hoverAt or lastPos + V(0, 30, 0)
							pos = hoverAt :: Vector3
						else
							pos = V(90 * sentAt, hop(sentAt % HOP), 0)
						end
						local verdict = Rules.judge(guard, lastPos, pos, arrival, geometry)
						if verdict then
							verdict.t = arrival
							table.insert(verdicts, verdict)
							T.expectEqual(verdict.enforce, true)
							Rules.restart(guard.flight, arrival, lastPos.Y) -- comme CharacterSync.refuse
							correctedAt, correctedFrom = arrival, lastPos
						else
							lastPos = pos
						end
					end
					T.expectEqual(#verdicts, 1, describe(verdicts))
				end)
				Rules.ENFORCE_FLIGHT = false
				assert(ok, err)
			end
		)
	end)

	T.describe("MovementGuardRules.fellIntoVoid", function()
		-- Cette méthode permet de suivre un joueur qui saute du bord de l'île (y = 50) puis se tait à t = 0,5 s.
		local function silentFaller()
			local guard = Rules.newGuard(0, V(0, 50, 0))
			Rules.observe(guard.flight, 0.05, 50, true)
			for i = 2, 10 do
				local t = i * INTERVAL
				Rules.observe(guard.flight, t, freeFall(50, 0, t - 0.05), false)
			end
			guard.heardAt = 0.5
			return guard
		end
		local noFloor = function(): boolean
			return false
		end

		T.it("déclare tombé un joueur en chute silencieux depuis VOID_SILENCE, au-dessus du vide", function()
			local guard = silentFaller()
			T.expect(Rules.fellIntoVoid(guard, 0.5 + Rules.VOID_SILENCE + 0.5, 0, noFloor))
		end)

		T.it("ne déclare rien avant VOID_SILENCE, au-dessus d'un sol, ou sans hauteur de mort", function()
			local guard = silentFaller()
			T.expect(not Rules.fellIntoVoid(guard, 0.5 + Rules.VOID_SILENCE - 0.1, 0, noFloor))
			T.expect(not Rules.fellIntoVoid(guard, 10, 0, function()
				return true
			end))
			T.expect(not Rules.fellIntoVoid(guard, 10, nil, noFloor))
		end)

		T.it(
			"ne déclare rien tant que la plus haute position possible reste au-dessus de la hauteur de mort",
			function()
				local guard = silentFaller()
				T.expect(not Rules.fellIntoVoid(guard, 0.5 + Rules.VOID_SILENCE, -500, noFloor))
			end
		)

		T.it("ne déclare rien pour un joueur porté (debout) qui se tait", function()
			local guard = Rules.newGuard(0, V(0, 50, 0))
			Rules.observe(guard.flight, 0.05, 50, true)
			T.expect(not Rules.fellIntoVoid(guard, 60, 0, noFloor))
		end)

		T.it("déclare tombé un client corrigé au-dessus du vide qui n'accuse jamais réception", function()
			local guard = Rules.newGuard(0, V(0, 50, 0))
			Rules.restart(guard.flight, 1, 50)
			guard.heardAt = 1
			T.expect(not Rules.fellIntoVoid(guard, 2, 0, noFloor))
			T.expect(Rules.fellIntoVoid(guard, 1 + Rules.VOID_SILENCE + 1, 0, noFloor))
		end)

		T.it("ne déclare rien tant que le client envoie, même des paquets ignorés (attente d'accusé)", function()
			local guard = silentFaller()
			guard.heardAt = 3
			T.expect(not Rules.fellIntoVoid(guard, 4, 0, noFloor))
		end)

		T.it("cherche le sol aussi là où le joueur a pu atterrir en avançant (saut par-dessus un trou)", function()
			-- Saut vers une plateforme 30 studs devant, à 30 studs/s, puis coupure réseau
			local guard = Rules.newGuard(0, V(0, 50, 0))
			local lastPos = V(0, 50, 0)
			for i = 1, 10 do
				local t = i * INTERVAL
				local pos = V(30 * t, if i == 1 then 50 else freeFall(50, Config.JUMP_VELOCITY, t - INTERVAL), 0)
				Rules.judge(guard, lastPos, pos, t, geometryOf({}))
				lastPos = pos
			end
			local platform = box(V(25, 0, -5), V(60, 48, 5))
			local now = 0.5 + Rules.VOID_SILENCE + 0.5
			local cf, size = Rules.voidProbe(guard, lastPos, now, 0)
			local lo, hi = cf.Position - size / 2, cf.Position + size / 2
			local pLo, pHi = platform.CFrame.Position - platform.Size / 2, platform.CFrame.Position + platform.Size / 2
			local overlaps = lo.X <= pHi.X
				and hi.X >= pLo.X
				and lo.Y <= pHi.Y
				and hi.Y >= pLo.Y
				and lo.Z <= pHi.Z
				and hi.Z >= pLo.Z
			T.expect(overlaps, "la plateforme d'en face doit être dans la zone")
			T.expect(cf.Position.Y - size.Y / 2 <= 0, "la zone descend jusqu'à la hauteur de mort")
			T.expect(cf.Position.Y + size.Y / 2 >= lastPos.Y, "la zone couvre la dernière position")
		end)
	end)
end

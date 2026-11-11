-- Statistiques de visée (#178) : accumulation, flick, z-score contre la population, planchers, bots exclus,
-- nettoyage au départ, aucun veto sur un tir.
return function(T, Loader)
	local AimStats = Loader.new():require("src/server/AimStats")
	local CharacterSyncRules = Loader.new():require("src/shared/CharacterSyncRules")

	local FORWARD = Vector3.new(0, 0, -1)
	local FORWARD_YAW = CharacterSyncRules.yawOf(FORWARD)

	-- Cette méthode permet de créer un faux participant (joueur ou bot) lorsqu'un test tire avec lui.
	local function participant(id: number, isBot: boolean?): any
		return { id = id, name = "J" .. id, isBot = isBot == true }
	end

	-- Cette méthode permet de simuler `shots` tirs dont `hits` touchent (`heads` à la tête) lorsqu'un test construit un
	-- joueur ; cap reçu juste avant chaque tir, déjà aligné (pas de flick).
	local function play(state, p, shots: number, hits: number, heads: number, startAt: number?)
		local t = startAt or 0
		for i = 1, shots do
			t += 2
			AimStats.noteShot(state, p, t, FORWARD_YAW, t - 0.05)
			if i <= hits then
				AimStats.noteHit(state, p, i <= heads, t + 0.05, FORWARD)
			end
		end
	end

	-- Cette méthode permet de peupler un serveur de `n` joueurs honnêtes (ids 1..n, 32 à 45 % de tête, 40 % de
	-- touches) lorsqu'un test a besoin d'une population.
	local function population(state, n: number)
		for id = 1, n do
			play(state, participant(id), 100, 40, 12 + id)
		end
	end

	T.describe("AimStats : accumulation", function()
		T.it("compte tirs, touches rattachées, têtes", function()
			local state = AimStats.new()
			play(state, participant(1), 10, 4, 1)
			local s = state.players[1]
			T.expectEqual(s.shots, 10)
			T.expectEqual(s.hits, 4)
			T.expectEqual(s.hitShots, 4)
			T.expectEqual(s.headshots, 1)
			T.expectNear(AimStats.rate(s, "hitRate"), 0.4)
			T.expectNear(AimStats.rate(s, "headshotRate"), 0.25)
		end)

		T.it("une seule touche rattachée par tir, et pas après HIT_LINK_WINDOW", function()
			local state = AimStats.new()
			local p = participant(1)
			AimStats.noteShot(state, p, 10)
			AimStats.noteHit(state, p, false, 10.1)
			AimStats.noteHit(state, p, false, 10.2)
			AimStats.noteShot(state, p, 20)
			AimStats.noteHit(state, p, true, 20 + AimStats.HIT_LINK_WINDOW + 0.1)
			local s = state.players[1]
			T.expectEqual(s.hits, 3, "toutes les touches comptent pour la tête")
			T.expectEqual(s.hitShots, 1)
			T.expectEqual(s.headshots, 1)
		end)

		T.it("flick : rotation rapide entre le cap figé au tir et la direction validée de la touche", function()
			local state = AimStats.new()
			local p = participant(1)
			local right = Vector3.new(1, 0, 0) -- 90° de cap
			AimStats.noteShot(state, p, 10, FORWARD_YAW, 9.95)
			AimStats.noteHit(state, p, true, 10.02, right)
			local s = state.players[1]
			T.expectEqual(s.measured, 1)
			T.expectEqual(s.flickHits, 1)
			T.expectNear(s.peakSpeed, 90 / 0.05, 1)
			-- Cap trop ancien à l'arrivée du tir : pas de mesure
			AimStats.noteShot(state, p, 20, FORWARD_YAW + math.pi / 2, 20 - AimStats.FLICK_MAX_AGE - 0.01)
			AimStats.noteHit(state, p, true, 20.02, FORWARD)
			T.expectEqual(s.measured, 1)
			-- Petite correction : mesurée, pas un flick
			AimStats.noteShot(state, p, 30, FORWARD_YAW + math.rad(5), 29.95)
			AimStats.noteHit(state, p, true, 30.02, FORWARD)
			T.expectEqual(s.measured, 2)
			T.expectEqual(s.flickHits, 1)
			-- Touche sans tir récent : comptée, ni au but ni mesurée
			AimStats.noteHit(state, p, false, 40, right)
			T.expectEqual(s.measured, 2)
			T.expectEqual(s.hits, 4)
			T.expectEqual(s.hitShots, 3)
		end)

		T.it("air strafe (200 °/s) : pas un flick", function()
			local state = AimStats.new()
			local p = participant(1)
			-- Cap reçu 50 ms avant le tir, la caméra a tourné de 10° depuis
			AimStats.noteShot(state, p, 10, FORWARD_YAW + math.rad(10), 9.95)
			AimStats.noteHit(state, p, false, 10.02, FORWARD)
			T.expectEqual(state.players[1].measured, 1)
			T.expectEqual(state.players[1].flickHits, 0)
		end)

		T.it("arrêt du serveur : plus rien compté après le gel", function()
			local state = AimStats.new()
			play(state, participant(1), 3, 1, 0)
			AimStats.close(state, { 1 })
			AimStats.freeze(state)
			play(state, participant(1), 3, 1, 0)
			T.expectEqual(AimStats.count(state), 0)
		end)

		T.it("écart de cap pris par le plus court (passage de -180° à 180°)", function()
			local d = AimStats.yawDelta(math.pi - 0.01, Vector3.new(0, 0, 1))
			T.expect(d ~= nil and d < 2, "écart : " .. tostring(d))
			T.expectEqual(AimStats.yawDelta(0, Vector3.new(0, 1, 0)), nil, "tir vertical : non mesuré")
		end)

		T.it("bots exclus : ni comptés, ni dans la population", function()
			local state = AimStats.new()
			play(state, participant(-1, true), 100, 100, 100)
			T.expectEqual(AimStats.count(state), 0)
			T.expectEqual(#AimStats.periodic(state), 0)
		end)
	end)

	T.describe("AimStats : jugement contre la population", function()
		T.it("joueur normal non signalé", function()
			local state = AimStats.new()
			population(state, 6)
			play(state, participant(99), 100, 42, 16)
			local v = AimStats.judge(state, 99)
			T.expect(v.judged, "jugé")
			T.expectEqual(#v.flagged, 0)
			for id = 1, 6 do
				T.expectEqual(#AimStats.judge(state, id).flagged, 0, "honnête " .. id)
			end
		end)

		T.it("joueur à 90 % de tête sur 40 touches signalé", function()
			local state = AimStats.new()
			population(state, 6)
			play(state, participant(99), 100, 40, 36)
			local v = AimStats.judge(state, 99)
			T.expect(table.find(v.flagged, "headshotRate") ~= nil, "tête signalée")
			T.expect(v.z.headshotRate >= AimStats.Z_THRESHOLD, "z : " .. tostring(v.z.headshotRate))
			local line = AimStats.describe(state.players[99], v)
			T.expect(string.find(line, "SIGNALÉ", 1, true) == 1, line)
		end)

		T.it("petite population non signalée (serveur de 2 joueurs)", function()
			local state = AimStats.new()
			population(state, 1)
			play(state, participant(99), 100, 40, 36)
			local v = AimStats.judge(state, 99)
			T.expectEqual(v.judged, false)
			T.expectEqual(#v.flagged, 0)
			T.expect(string.find(AimStats.describe(state.players[99], v), "population", 1, true) ~= nil)
		end)

		T.it("moins de MIN_HITS touches : non jugé", function()
			local state = AimStats.new()
			population(state, 6)
			play(state, participant(99), 40, AimStats.MIN_HITS - 1, AimStats.MIN_HITS - 1)
			T.expectEqual(AimStats.judge(state, 99).judged, false)
		end)

		T.it("plancher absolu : très au-dessus d'une population faible mais sous le plancher, non signalé", function()
			local state = AimStats.new()
			for id = 1, 6 do
				play(state, participant(id), 100, 40, 2 + id % 2)
			end
			-- 50 % de tête : z énorme contre ~6 %, mais sous FLOOR.headshotRate
			play(state, participant(99), 100, 40, 20)
			local v = AimStats.judge(state, 99)
			T.expect(v.z.headshotRate > AimStats.Z_THRESHOLD)
			T.expectEqual(table.find(v.flagged, "headshotRate"), nil)
		end)
	end)

	T.describe("AimStats : sortie et nettoyage", function()
		T.it("résumé périodique : seulement les joueurs qui ont tiré depuis le précédent", function()
			local state = AimStats.new()
			play(state, participant(1), 3, 1, 0)
			play(state, participant(2), 3, 1, 0)
			T.expectEqual(#AimStats.periodic(state), 2)
			T.expectEqual(#AimStats.periodic(state), 0, "rien de neuf")
			play(state, participant(2), 1, 0, 0, 100)
			local entries = AimStats.periodic(state)
			T.expectEqual(#entries, 1)
			T.expectEqual(entries[1].id, 2)
		end)

		T.it("départ : résumé final puis statistiques oubliées (aucune fuite)", function()
			local state = AimStats.new()
			population(state, 6)
			play(state, participant(99), 100, 40, 36)
			local entry = AimStats.close(state, { 99 })[1]
			T.expect(entry ~= nil and #entry.verdict.flagged > 0 and entry.report, "signalé au départ")
			T.expectEqual(state.players[99], nil)
			T.expectEqual(AimStats.count(state), 6)
			for id = 1, 6 do
				AimStats.close(state, { id })
			end
			T.expectEqual(AimStats.count(state), 0)
			T.expectEqual(#AimStats.close(state, { 42 }), 0, "inconnu : rien")
		end)

		T.it("arrêt du serveur : tous les joueurs restants jugés contre la même population", function()
			local state = AimStats.new()
			population(state, 6)
			play(state, participant(99), 100, 40, 36)
			-- Le tricheur clos en dernier : avec des départs un par un, la population serait déjà sous MIN_POPULATION
			local entries = AimStats.close(state, { 1, 2, 3, 4, 5, 6, 99 })
			T.expectEqual(#entries, 7)
			T.expect(entries[7].verdict.judged and entries[7].report, "tricheur jugé et signalé")
			T.expectEqual(AimStats.count(state), 0)
		end)

		T.it("relevé final au journal s'il a été signalé plus tôt, même redevenu normal", function()
			local state = AimStats.new()
			population(state, 6)
			local p = participant(99)
			play(state, p, 100, 40, 36)
			T.expect(AimStats.periodic(state)[7].report, "signalé au résumé périodique")
			-- Il retombe dans la moyenne : plus signalé, mais son relevé final va quand même au journal
			play(state, p, 400, 200, 40, 1000)
			local entry = AimStats.close(state, { 99 })[1]
			T.expectEqual(#entry.verdict.flagged, 0)
			T.expect(entry.report, "dernier relevé journalisé")
			-- Un joueur jamais signalé : console seulement
			T.expectEqual(AimStats.close(state, { 1 })[1].report, false)
		end)

		T.it("détail compact : tient dans les 160 octets de CheatLog avec trois signalements", function()
			local stats = {
				shots = 12500,
				hits = 9000,
				headshots = 8500,
				hitShots = 8000,
				measured = 11000,
				flickHits = 7000,
				peakSpeed = 24000,
			}
			local verdict = {
				judged = true,
				z = { headshotRate = 12.3, hitRate = 10.1, flickRate = 11.7 },
				flagged = { "headshotRate", "hitRate", "flickRate" },
			}
			local line = AimStats.describe(stats :: any, verdict :: any)
			T.expect(#line <= 160, #line .. " octets : " .. line)
		end)

		T.it("aucune sanction ni tir refusé : noteShot et noteHit ne renvoient rien", function()
			local state = AimStats.new()
			population(state, 6)
			local cheater = participant(99)
			play(state, cheater, 100, 40, 36)
			T.expectEqual(select("#", AimStats.noteShot(state, cheater, 1000, FORWARD_YAW, 999.95)), 0)
			T.expectEqual(select("#", AimStats.noteHit(state, cheater, true, 1000.05, FORWARD)), 0)
			T.expectEqual(state.players[99].shots, 101, "le tir du joueur signalé est compté comme les autres")
		end)
	end)
end

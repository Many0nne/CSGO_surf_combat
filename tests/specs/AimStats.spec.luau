-- Statistiques de visée (#178) : accumulation, rattachement des touches par shotTime (#216), flick, z-score contre la
-- population, planchers, bots exclus, nettoyage au départ, aucun veto sur un tir.
return function(T, Loader)
	local AimStats = Loader.new():require("src/server/AimStats")
	local ShotLinkRules = Loader.new():require("src/server/ShotLinkRules")
	local CharacterSyncRules = Loader.new():require("src/shared/CharacterSyncRules")

	local FORWARD = Vector3.new(0, 0, -1)
	local FORWARD_YAW = CharacterSyncRules.yawOf(FORWARD)

	-- Cette méthode permet de créer un faux participant (joueur ou bot) lorsqu'un test tire avec lui.
	local function participant(id: number, isBot: boolean?): any
		return { id = id, name = "J" .. id, isBot = isBot == true }
	end

	-- Cette méthode permet de simuler `shots` tirs dont `hits` touchent (`heads` à la tête) lorsqu'un test construit un
	-- joueur ; cap reçu juste avant chaque tir, déjà aligné (pas de flick), touche rattachée à son tir (#216).
	local function play(state, p, shots: number, hits: number, heads: number, startAt: number?)
		local t = startAt or 0
		for i = 1, shots do
			t += 2
			AimStats.noteShot(state, p, t, FORWARD_YAW, t - 0.05, 500 + t)
			if i <= hits then
				AimStats.noteHit(state, p, i <= heads, t + 0.05, FORWARD, 500 + t)
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

		T.it("touche rattachée à son tir par shotTime (pas au dernier tir), une seule par tir (#216)", function()
			local state = AimStats.new()
			local p = participant(1)
			AimStats.noteShot(state, p, 10, nil, nil, 100)
			AimStats.noteShot(state, p, 10.2, nil, nil, 100.2)
			AimStats.noteHit(state, p, false, 10.3, nil, 100)
			AimStats.noteHit(state, p, false, 10.35, nil, 100)
			AimStats.noteHit(state, p, true, 10.4, nil, 100.2)
			local s = state.players[1]
			T.expectEqual(s.hits, 3, "toutes les touches comptent pour la tête")
			T.expectEqual(s.hitShots, 3, "2 tirs rattachés une fois + l'orpheline comptée comme un tir (#246)")
			T.expectEqual(s.orphanHits, 1, "seconde touche du premier tir : orpheline")
			T.expectEqual(s.headshots, 1)
		end)

		T.it("touche orpheline : comptée à part et comme un tir qui touche (#216, #246)", function()
			local state = AimStats.new()
			local p = participant(1)
			-- Tricheur qui tait ses tirs : touches sans ShotFired, orphelines
			for i = 1, 10 do
				AimStats.noteHit(state, p, true, i * 2, FORWARD)
			end
			-- Tir trop ancien (au-delà de ShotLinkRules.MAX_AGE) : la touche n'y est plus rattachée
			AimStats.noteShot(state, p, 30, nil, nil, 200)
			AimStats.noteHit(state, p, false, 30 + ShotLinkRules.MAX_AGE + 0.1, FORWARD, 200)
			local s = state.players[1]
			T.expectEqual(s.hits, 11)
			T.expectEqual(s.orphanHits, 11)
			T.expectEqual(s.shots, 12, "11 orphelines + le tir annoncé")
			T.expectEqual(s.hitShots, 11, "chaque orpheline compte comme un tir qui touche")
			T.expect(string.find(AimStats.describe(s, AimStats.judge(state, 1)), "orph 11", 1, true) ~= nil)
		end)

		T.it("client sans ShotFired : reste dans le taux de touches et lève une violation (#246)", function()
			local state = AimStats.new()
			local p = participant(1)
			local alerts = 0
			for i = 1, 40 do
				AimStats.noteHit(state, p, false, i, FORWARD)
				if AimStats.orphanAlert(state, p) then
					alerts += 1
				end
			end
			local s = state.players[1]
			T.expectEqual(s.shots, 40)
			T.expectNear(AimStats.rate(s, "hitRate"), 1)
			-- Jugé dès ORPHAN_MIN_TOUCHES touches, puis une violation par palier de 5 (20, 25, 30, 35, 40)
			T.expectEqual(alerts, 5, "une violation par palier, pas une par touche")
			T.expectEqual(AimStats.orphanAlert(state, participant(2)), nil, "joueur inconnu : rien")
		end)

		T.it("taux d'orphelines jugé seulement à partir de ORPHAN_MIN_TOUCHES touches (#246)", function()
			local state = AimStats.new()
			local p = participant(1)
			for i = 1, AimStats.ORPHAN_MIN_TOUCHES - 1 do
				AimStats.noteHit(state, p, false, i, FORWARD)
				T.expectEqual(AimStats.orphanAlert(state, p), nil, "touche " .. i)
			end
			AimStats.noteHit(state, p, false, 100, FORWARD)
			T.expect(AimStats.orphanAlert(state, p) ~= nil, "alerte à la touche " .. AimStats.ORPHAN_MIN_TOUCHES)
		end)

		T.it("taux franchi tard : une seule violation, pas de rattrapage touche par touche (#246)", function()
			local state = AimStats.new()
			local p = participant(1)
			play(state, p, 300, 300, 0)
			local alerts = 0
			for i = 1, 200 do
				AimStats.noteHit(state, p, false, 5000 + i, FORWARD)
				if AimStats.orphanAlert(state, p) then
					alerts += 1
				end
			end
			-- Taux > 25 % dès la 101e orpheline (101/401), puis un palier de 5 : 101, 105, 110 … 200 = 21 alertes ; sans
			-- le saut de palier, une alerte par touche au-delà de 101 (100 alertes)
			T.expectEqual(alerts, 21)
		end)

		T.it("client honnête (tirs et touches) ou quelques orphelines : aucune violation (#246)", function()
			local state = AimStats.new()
			local p = participant(1)
			local alerts = 0
			for i = 1, 100 do
				local t = i * 2
				AimStats.noteShot(state, p, t, FORWARD_YAW, t - 0.05, 500 + t)
				AimStats.noteHit(state, p, false, t + 0.05, FORWARD, 500 + t)
				-- 3 touches dont le ShotFired a été écarté par le relais : sous le seuil
				if i % 33 == 0 then
					AimStats.noteHit(state, p, false, t + 0.1, FORWARD)
				end
				if AimStats.orphanAlert(state, p) then
					alerts += 1
				end
			end
			T.expectEqual(state.players[1].orphanHits, 3)
			T.expectEqual(alerts, 0)
			-- Un bot n'est jamais jugé
			AimStats.noteHit(state, participant(-1, true), false, 1, FORWARD)
			T.expectEqual(AimStats.orphanAlert(state, participant(-1, true)), nil)
		end)

		T.it("flick mesuré sur le cap figé au tir rattaché, pas au dernier tir (#216)", function()
			local state = AimStats.new()
			local p = participant(1)
			-- Deux tirs en attente : le premier, cap à 90° de la touche (flick) ; le second, cap aligné
			AimStats.noteShot(state, p, 10, FORWARD_YAW + math.pi / 2, 9.95, 100)
			AimStats.noteShot(state, p, 10.1, FORWARD_YAW, 10.05, 100.1)
			AimStats.noteHit(state, p, true, 10.15, FORWARD, 100)
			T.expectEqual(state.players[1].flickHits, 1)
		end)

		T.it("flick : rotation rapide entre le cap figé au tir et la direction validée de la touche", function()
			local state = AimStats.new()
			local p = participant(1)
			local right = Vector3.new(1, 0, 0) -- 90° de cap
			AimStats.noteShot(state, p, 10, FORWARD_YAW, 9.95, 10)
			AimStats.noteHit(state, p, true, 10.02, right, 10)
			local s = state.players[1]
			T.expectEqual(s.measured, 1)
			T.expectEqual(s.flickHits, 1)
			T.expectNear(s.peakSpeed, 90 / 0.05, 1)
			-- Cap trop ancien à l'arrivée du tir : pas de mesure
			AimStats.noteShot(state, p, 20, FORWARD_YAW + math.pi / 2, 20 - AimStats.FLICK_MAX_AGE - 0.01, 20)
			AimStats.noteHit(state, p, true, 20.02, FORWARD, 20)
			T.expectEqual(s.measured, 1)
			-- Petite correction : mesurée, pas un flick
			AimStats.noteShot(state, p, 30, FORWARD_YAW + math.rad(5), 29.95, 30)
			AimStats.noteHit(state, p, true, 30.02, FORWARD, 30)
			T.expectEqual(s.measured, 2)
			T.expectEqual(s.flickHits, 1)
			-- Touche sans tir rattaché : comptée, ni au but ni mesurée
			AimStats.noteHit(state, p, false, 40, right)
			T.expectEqual(s.measured, 2)
			T.expectEqual(s.hits, 4)
			T.expectEqual(s.hitShots, 4, "3 rattachés + l'orpheline (#246)")
			T.expectEqual(s.orphanHits, 1)
		end)

		T.it("air strafe (200 °/s) : pas un flick", function()
			local state = AimStats.new()
			local p = participant(1)
			-- Cap reçu 50 ms avant le tir, la caméra a tourné de 10° depuis
			AimStats.noteShot(state, p, 10, FORWARD_YAW + math.rad(10), 9.95, 10)
			AimStats.noteHit(state, p, false, 10.02, FORWARD, 10)
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
				orphanHits = 9000,
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
			-- Le noteHit sans tir rattaché est une orpheline, comptée comme un tir (#246)
			T.expectEqual(state.players[99].shots, 102, "le tir du joueur signalé est compté comme les autres")
		end)
	end)
end

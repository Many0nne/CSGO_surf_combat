return function(T, Loader)
	local Rules = Loader.new():require("src/shared/PerfRouteRules")

	-- Cette méthode permet de construire un tick lorsqu'un test n'en fixe que quelques champs.
	local function tick(keys, yaw, pitch, over)
		local t = { keys = keys, yaw = yaw, pitch = pitch, fire = 0, tool = "AWP" }
		for k, v in over or {} do
			t[k] = v
		end
		return t
	end

	-- Cette méthode permet de construire une piste de test : un point de contrôle, une course droite, un virage, un tir,
	-- un changement d'arme, puis un second point de contrôle.
	local function sample()
		local ticks = {
			tick(1, 90000, -2000, { check = Rules.check(10, 5.5, -3, 0, 0, 0) }),
		}
		for _ = 1, 5 do
			table.insert(ticks, tick(1, 90000, -2000))
		end
		for i = 1, 4 do
			table.insert(ticks, tick(1 + 8 + 16, 90000 + i * 1234, -2000 - i, nil))
		end
		table.insert(ticks, tick(1 + 128, 94936, -2004, { fire = 2 }))
		table.insert(ticks, tick(0, 94936, -2004, { tool = "Desert Eagle" }))
		table.insert(ticks, tick(0, 94936, -2004, { tool = "", check = Rules.check(12, 5.5, -3, 3.25, -1, 0) }))
		return { version = Rules.VERSION, map = "Dizzy", ticks = ticks }
	end

	T.describe("PerfRouteRules.encode / decode", function()
		T.it("aller-retour exact : touches, angles, tirs, armes, points de contrôle", function()
			local route = sample()
			local decoded, why = Rules.decode(Rules.encode(route))
			T.expect(decoded ~= nil, why)
			T.expectEqual(decoded.map, "Dizzy")
			T.expectEqual(#decoded.ticks, #route.ticks)
			for i, t in route.ticks do
				local d = decoded.ticks[i]
				T.expectEqual(d.keys, t.keys)
				T.expectEqual(d.yaw, t.yaw)
				T.expectEqual(d.pitch, t.pitch)
				T.expectEqual(d.fire, t.fire)
				T.expectEqual(d.tool, t.tool)
				T.expectEqual(d.check ~= nil, t.check ~= nil)
				if t.check then
					for k, v in t.check do
						T.expectEqual(d.check[k], v)
					end
				end
			end
		end)

		T.it("ticks identiques compressés en répétitions", function()
			local text = Rules.encode(sample())
			-- Le tick du point de contrôle et les 5 suivants s'écrivent pareil : une ligne puis x5
			T.expect(string.find(text, "\n1 0 0\nx5\n", 1, true) ~= nil, text)
			-- Le virage garde des écarts identiques : une ligne puis x3
			T.expect(string.find(text, "\n25 1234 -1\nx3\n", 1, true) ~= nil, text)
		end)

		T.it("nom d'arme avec espace, arme rangée", function()
			local text = Rules.encode(sample())
			T.expect(string.find(text, "\nE Desert~Eagle\n", 1, true) ~= nil, text)
			T.expect(string.find(text, " %-\n") ~= nil, text)
		end)

		T.it("fins de ligne Windows acceptées", function()
			local text = string.gsub(Rules.encode(sample()), "\n", "\r\n")
			T.expect(Rules.decode(text) ~= nil)
		end)

		T.it("textes refusés avec leur raison", function()
			T.expect(select(2, Rules.decode("")) == "en-tête ROUTE absent")
			T.expect(string.find(select(2, Rules.decode("ROUTE 9 Dizzy 0")), "version") ~= nil)
			T.expect(string.find(select(2, Rules.decode("ROUTE 1 Dizzy 1\n1 0 0")), "point de contrôle") ~= nil)
			T.expect(
				string.find(select(2, Rules.decode("ROUTE 1 Dizzy 3\nC 0 0 0 0 0 0 0 0 -\n1 0 0")), "annoncés") ~= nil
			)
			T.expect(
				string.find(select(2, Rules.decode("ROUTE 1 Dizzy 1\nC 0 0 0 0 0 0 0 -\n1 0 0")), "illisible") ~= nil
			)
			T.expect(string.find(select(2, Rules.decode("ROUTE 1 Dizzy 1\nx2")), "répétition") ~= nil)
		end)
	end)

	T.describe("PerfRouteRules.keysFrom / split", function()
		T.it("touches tenues et appuis dans un masque, relus à l'identique", function()
			local mask = Rules.keysFrom({ forward = true, right = true, jump = true }, { jump = true, reload = true })
			T.expectEqual(mask, 1 + 8 + 16 + 128 + 256)
			local held, presses = Rules.split(mask)
			T.expect(held.forward and held.right and held.jump)
			T.expect(not held.left and not held.back and not held.crouch and not held.walk)
			T.expect(presses.jump and presses.reload and not presses.inspect)
		end)
	end)

	T.describe("PerfRouteRules.trim / nextCheck", function()
		T.it("le début recule au point de contrôle précédent", function()
			local route = sample()
			local cut = Rules.trim(route, 3 / 64, 1)
			T.expectEqual(#cut.ticks, #route.ticks)
			T.expect(cut.ticks[1].check ~= nil)
		end)

		T.it("prochain point de contrôle pour reprendre après une réapparition", function()
			local route = sample()
			T.expectEqual(Rules.nextCheck(route, 1), 1)
			T.expectEqual(Rules.nextCheck(route, 2), #route.ticks)
			T.expectEqual(Rules.nextCheck(route, #route.ticks + 1), nil)
		end)
	end)

	T.describe("PerfRouteRules.drift", function()
		T.it("distance en studs entre la position et le point de contrôle", function()
			local c = Rules.check(10, 5.5, -3, 0, 0, 0)
			T.expectNear(Rules.drift(c, 13, 9.5, -3), 5, 1e-9)
			T.expectNear(Rules.drift(c, 10, 5.5, -3), 0, 1e-9)
		end)
	end)

	T.describe("PerfRouteRules.toLogLines / fromLog", function()
		T.it("découpée en morceaux sans blanc, recollée depuis un journal bruité", function()
			local text = Rules.encode(sample())
			local saved = Rules.LOG_CHUNK
			Rules.LOG_CHUNK = 20
			local lines = Rules.toLogLines("dizzy", 1000, text)
			Rules.LOG_CHUNK = saved
			T.expect(#lines > 2)
			for _, line in lines do
				T.expect(string.find(string.match(line, "%] (.*)$"), "%s") == nil, line)
			end
			-- Préfixe d'un journal Roblox, autre prise incomplète plus récente, autre piste
			local log = "2026-11-15T10:00:00.000Z,1.0,abc,6 [FLog::Output] "
				.. table.concat(lines, "\n2026-11-15T10:00:00.000Z,1.0,abc,6 [FLog::Output] ")
				.. "\n[PerfRoute dizzy 2000 1/3] 1,0,0\n[PerfRoute autre 3000 1/1] x"
			T.expectEqual(Rules.fromLog(log, "dizzy"), text)
			T.expectEqual(select(2, Rules.fromLog("rien", "dizzy")), "aucune prise de dizzy")
			T.expectEqual(
				select(2, Rules.fromLog("[PerfRoute dizzy 2000 1/3] 1,0,0", "dizzy")),
				"aucune prise complète de dizzy"
			)
		end)
	end)

	T.describe("PerfRouteRules.runLine", function()
		T.it("bilan du rejeu sur une ligne", function()
			local line = Rules.runLine({
				name = "Dizzy",
				status = "fini",
				ticks = 640,
				total = 640,
				fps = 59.6,
				p99Ms = 21.04,
				maxMs = 48.2,
				hitches = 0,
				checks = 10,
				driftMean = 0.12,
				driftMax = 0.5,
				recalages = 0,
				respawns = 1,
				memStartMb = 1500,
				memEndMb = 1510,
			})
			T.expect(string.find(line, "^%[Perf%] RUN Dizzy fini 10/10s | FPS 60 p99 21.0ms max 48.2ms") ~= nil, line)
			T.expect(string.find(line, "1 réapparitions | mém 1500 %-> 1510 Mo$") ~= nil, line)
		end)
	end)
end

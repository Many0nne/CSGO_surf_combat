return function(T, Loader)
	local Rules = Loader.new():require("src/shared/PerfRules")
	local Markers = Loader.new():require("src/shared/PerfMarkers")

	-- Cette méthode permet de construire un relevé mémoire lorsqu'un test n'en fixe que quelques champs.
	local function snap(index, totalMb, tags, over)
		local s =
			{ index = index, reason = "spawn", totalMb = totalMb, instanceCount = 1000, luaKb = 2048, tags = tags }
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	T.describe("PerfRules.canUse", function()
		T.it("Studio : toujours", function()
			T.expect(Rules.canUse(true, 1, 2, false))
		end)

		T.it("publié, jeu d'un utilisateur : seulement le créateur", function()
			T.expect(Rules.canUse(false, 42, 42, true))
			T.expect(not Rules.canUse(false, 7, 42, true))
			T.expect(not Rules.canUse(false, 0, 0, true))
		end)

		T.it("publié, jeu de groupe : personne (Studio seulement)", function()
			T.expect(not Rules.canUse(false, 99, 99, false))
		end)
	end)

	T.describe("PerfRules.memoryDiff", function()
		T.it("hausses d'abord, petites variations ignorées, nouvelle catégorie comptée", function()
			local diffs = Rules.memoryDiff(
				{ LuaHeap = 50, Instances = 70, Gui = 20, Sounds = 5 },
				{ LuaHeap = 58, Instances = 70.2, Gui = 18, Sounds = 5, Animation = 3 }
			)
			T.expectEqual(#diffs, 3)
			T.expectEqual(diffs[1].tag, "LuaHeap")
			T.expectNear(diffs[1].delta, 8, 1e-9)
			T.expectEqual(diffs[2].tag, "Animation")
			T.expectEqual(diffs[3].tag, "Gui")
			T.expectNear(diffs[3].delta, -2, 1e-9)
		end)

		T.it("au plus MEMORY_DIFF_MAX catégories", function()
			local prev, cur = {}, {}
			for i = 1, 10 do
				prev["T" .. i] = 0
				cur["T" .. i] = i
			end
			local diffs = Rules.memoryDiff(prev, cur)
			T.expectEqual(#diffs, Rules.MEMORY_DIFF_MAX)
			T.expectEqual(diffs[1].tag, "T10")
		end)
	end)

	T.describe("PerfRules.formatSnapshot", function()
		T.it("premier relevé : sans écart", function()
			local line = Rules.formatSnapshot("CLIENT", snap(1, 500, {}, { reason = "démarrage" }), nil, nil)
			T.expectEqual(line, "MEM CLIENT #1 démarrage : total 500 Mo | Instances 1000 | Lua 2.0 Mo")
		end)

		T.it("relevé suivant : écarts depuis le précédent et le premier, catégories qui bougent", function()
			local first = snap(1, 500, { LuaHeap = 50 })
			local prev = snap(2, 510, { LuaHeap = 52 })
			local cur = snap(3, 525, { LuaHeap = 60 }, { instanceCount = 1150, luaKb = 3072 })
			local line = Rules.formatSnapshot("SERVEUR", cur, prev, first)
			T.expectEqual(
				line,
				"MEM SERVEUR #3 spawn : total 525 Mo (+15.0 depuis #2, +25.0 depuis #1) | Instances 1150 (+150)"
					.. " | Lua 3.0 Mo (+1.0) | écarts Mo : LuaHeap +8.0"
			)
		end)

		T.it("deuxième relevé : le premier n'est pas cité deux fois", function()
			local first = snap(1, 500, {})
			local line = Rules.formatSnapshot("CLIENT", snap(2, 499, {}), first, first)
			T.expect(string.find(line, "(-1.0 depuis #1)", 1, true) ~= nil)
		end)
	end)

	T.describe("PerfRules.markerReport", function()
		T.it("moyenne par frame, du plus cher au moins cher", function()
			local lines = Rules.markerReport({
				["caméra"] = { time = 0.006, calls = 60, max = 0.0002 },
				mouvement = { time = 0.030, calls = 120, max = 0.002 },
			}, 60)
			T.expectEqual(lines[1].label, "mouvement")
			T.expectNear(lines[1].msPerFrame, 0.5, 1e-9)
			T.expectNear(lines[1].callsPerFrame, 2, 1e-9)
			T.expectNear(lines[1].maxMs, 2, 1e-9)
			T.expectEqual(lines[2].label, "caméra")
		end)

		T.it("aucune frame : rien", function()
			T.expectEqual(#Rules.markerReport({ a = { time = 1, calls = 1, max = 1 } }, 0), 0)
		end)
	end)

	T.describe("PerfRules.frameStats", function()
		T.it("médiane, p99 et max en ms, FPS déduit de la médiane", function()
			local dts = {}
			for _ = 1, 99 do
				table.insert(dts, 0.016)
			end
			table.insert(dts, 0.05)
			local s = Rules.frameStats(dts)
			T.expectEqual(s.frames, 100)
			T.expectNear(s.medianMs, 16, 1e-9)
			T.expectNear(s.maxMs, 50, 1e-9)
			T.expectNear(s.fps, 62.5, 1e-9)
		end)

		T.it("aucune frame : zéros", function()
			local s = Rules.frameStats({})
			T.expectEqual(s.frames, 0)
			T.expectEqual(s.fps, 0)
		end)
	end)

	T.describe("PerfMarkers", function()
		T.it("transmet les arguments, ne compte que si timing est actif, collect remet à zéro", function()
			local seen = {}
			local fn = Markers.wrap("test", function(a, b)
				table.insert(seen, a + b)
			end)
			Markers.collect()
			Markers.timing = false
			fn(1, 2)
			T.expectEqual(Markers.collect().test.calls, 0)
			Markers.timing = true
			fn(3, 4)
			fn(5, 6)
			local totals = Markers.collect()
			Markers.timing = false
			T.expectEqual(totals.test.calls, 2)
			T.expect(totals.test.time >= 0 and totals.test.max <= totals.test.time)
			T.expectEqual(Markers.collect().test.calls, 0)
			T.expectEqual(table.concat(seen, ","), "3,7,11")
		end)

		T.it("deux callbacks du même nom partagent le compteur (connexion en double visible)", function()
			local a = Markers.wrap("double", function() end)
			local b = Markers.wrap("double", function() end)
			Markers.collect()
			Markers.timing = true
			a()
			b()
			local totals = Markers.collect()
			Markers.timing = false
			T.expectEqual(totals.double.calls, 2)
		end)
	end)
	T.describe("PerfRules.benchSummary / benchPhaseValid / formatBenchLine", function()
		T.it("moyenne GPU et CPU, centiles des frames", function()
			local s = Rules.benchSummary({ 10, 20, 30 }, { 4, 6, 8 }, { 16, 17, 50 })
			T.expectNear(s.gpuMeanMs, 20, 1e-9)
			T.expectEqual(s.gpuP95Ms, 30)
			T.expectNear(s.cpuMeanMs, 6, 1e-9)
			T.expectEqual(s.frameMedianMs, 17)
			T.expectEqual(s.frameP99Ms, 50)
			T.expectEqual(s.frames, 3)
		end)

		T.it("phase vide : zéros, invalide", function()
			local s = Rules.benchSummary({}, {}, {})
			T.expectEqual(s.gpuMeanMs, 0)
			T.expectEqual(Rules.benchPhaseValid(s, false), false)
		end)

		T.it("invalide si la fenêtre a perdu le focus ou si le GPU vaut 0", function()
			local ok = Rules.benchSummary({ 12 }, { 5 }, { 16 })
			T.expectEqual(Rules.benchPhaseValid(ok, false), true)
			T.expectEqual(Rules.benchPhaseValid(ok, true), false)
			T.expectEqual(Rules.benchPhaseValid(Rules.benchSummary({ 0 }, { 5 }, { 66 }), false), false)
		end)

		T.it("ligne : écart à la référence, mention INVALIDE", function()
			local s = Rules.benchSummary({ 9 }, { 5 }, { 16 })
			T.expect(string.find(Rules.formatBenchLine("sans ombres", s, true, 15), "(-6.0)", 1, true) ~= nil)
			T.expect(string.find(Rules.formatBenchLine("référence", s, true, nil), "(", 1, true) == nil)
			T.expect(string.find(Rules.formatBenchLine("x", s, false, 15), "INVALIDE", 1, true) ~= nil)
		end)
	end)

	T.describe("PerfRules.roundDuration", function()
		T.it("sans attribut ou attribut invalide : durée par défaut", function()
			T.expectEqual(Rules.roundDuration(300, nil), 300)
			T.expectEqual(Rules.roundDuration(300, "60"), 300)
			T.expectEqual(Rules.roundDuration(300, 0 / 0), 300)
			T.expectEqual(Rules.roundDuration(300, Rules.MIN_ROUND_DURATION - 1), 300)
		end)

		T.it("attribut valide : remplace la durée par défaut", function()
			T.expectEqual(Rules.roundDuration(300, 60), 60)
			T.expectEqual(Rules.roundDuration(300, Rules.MIN_ROUND_DURATION), Rules.MIN_ROUND_DURATION)
		end)
	end)
end

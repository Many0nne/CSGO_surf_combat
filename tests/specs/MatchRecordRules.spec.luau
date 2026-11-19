-- Règles pures de l'enregistreur de partie (#582) : transport dans la console, morceaux, fusion, lecture.
return function(T, Loader)
	local loader = Loader.new()
	local R = loader:require("src/shared/MatchRecordRules")
	local H = loader:require("src/shared/HighlightClipRules")

	-- Cette méthode permet de fabriquer un morceau décodé (participant qui avance sur X à 10 studs/s, relevés à 20 Hz)
	-- lorsqu'un test a besoin d'un morceau valide.
	local function chunkOf(seq: number, t0: number, t1: number, extra: { [string]: any }?)
		local rows = {}
		local t = 0
		while t <= (t1 - t0) + 1e-9 do
			table.insert(rows, { t, 10 * (t0 + t), 0, 0, 0 })
			t += 1 / R.ACTOR_HZ
		end
		local chunk = {
			v = R.VERSION,
			rec = "1234",
			seq = seq,
			t0 = t0,
			t1 = t1,
			actors = { { id = 7, name = "Joueur", bot = false, track = H.encodeSeries(rows, R.ACTOR_SCALES) } },
			events = {},
		}
		for key, value in extra or {} do
			chunk[key] = value
		end
		return chunk
	end

	T.describe("MatchRecordRules transport", function()
		T.it("échappe espaces, retours et pour-cent, et les relit", function()
			local text = 'a b\nc\t%d "Desert Eagle"'
			local flat = R.escape(text)
			T.expect(string.find(flat, "%s") == nil)
			T.expectEqual(R.unescape(flat), text)
		end)

		T.it("découpe un morceau en lignes et le recolle depuis un journal", function()
			local text = string.rep('{"k":"shot","note":"un tir lointain"},', 60)
			local lines = R.toLogLines("99", 3, text)
			T.expect(#lines > 1)
			-- Lignes mêlées au reste du journal, une ligne en double (journal relu)
			local log = "bruit\n"
				.. table.concat(lines, "\n2026-11-19 [FLog::Output] ")
				.. "\n"
				.. lines[1]
				.. "\nautre ligne"
			local found = R.fromLog(log)
			T.expect(found["99"] ~= nil)
			T.expectEqual(found["99"][3], text)
		end)

		T.it("ignore un morceau incomplet", function()
			local lines = R.toLogLines("5", 1, string.rep("x", R.LOG_CHUNK * 2 + 10))
			local found = R.fromLog(lines[1] .. "\n" .. lines[3])
			T.expect(found["5"] == nil)
		end)
	end)

	T.describe("MatchRecordRules morceaux", function()
		T.it("refuse une autre version ou un morceau sans champs", function()
			T.expect(R.readChunk({ v = 99 }) == nil)
			T.expect(R.readChunk({ v = R.VERSION, rec = "1" }) == nil)
			T.expect(R.readChunk("texte") == nil)
		end)

		T.it("retire les évènements inconnus ou abîmés", function()
			local chunk = R.readChunk(chunkOf(1, 0, 5, {
				events = {
					{ t = 1, k = "shot", id = 7 },
					{ t = 1, k = "inconnu", id = 7 },
					{ t = "x", k = "shot", id = 7 },
					"pas une table",
				},
			}))
			T.expect(chunk ~= nil)
			T.expectEqual(#chunk.events, 1)
		end)

		T.it("range et relit une direction arrondie", function()
			local event = { t = 0, k = "shot", id = 1 }
			R.setDirection(event, Vector3.new(0, 0, -2))
			T.expectEqual(event.dz, -1)
			local dir = R.directionOf(event)
			T.expectNear(dir.Z, -1, 1e-9)
			T.expect(R.directionOf({ t = 0, k = "shot", id = 1 }) == nil)
		end)
	end)

	T.describe("MatchRecordRules fusion", function()
		-- Cette méthode permet de fusionner une liste de morceaux bruts lorsqu'un test a besoin d'une partie.
		local function matchOf(chunks)
			local match = R.newMatch()
			for _, raw in chunks do
				local chunk = R.readChunk(raw)
				T.expect(chunk ~= nil)
				R.addChunk(match, chunk)
			end
			return R.finish(match)
		end

		T.it("met les morceaux bout à bout sur l'horloge de la partie", function()
			local match = matchOf({
				chunkOf(1, 100, 105, { meta = { me = 7, map = "Dizzy" } }),
				chunkOf(2, 105, 110, { events = { { t = 0.5, k = "death", id = 7 } } }),
			})
			T.expectEqual(match.me, 7)
			T.expectEqual(match.meta.map, "Dizzy")
			T.expectNear(match.duration, 10, 1e-9)
			T.expectNear(match.events[1].t, 5.5, 1e-9)
			-- Relevé partagé à la jonction (t = 5) non doublé
			local times = match.actors[7].track.t
			for i = 2, #times do
				T.expect(times[i] > times[i - 1])
			end
			local out = {}
			local present = R.sample(match.actors[7].track, 7.33, out)
			T.expect(present)
			T.expectNear(out[1], 1073.3, 0.05)
		end)

		T.it("liste les morceaux manquants", function()
			local match = matchOf({ chunkOf(1, 0, 5), chunkOf(3, 10, 15) })
			T.expectEqual(#match.missing, 1)
			T.expectEqual(match.missing[1], 2)
		end)

		T.it("refuse un morceau d'un autre enregistrement", function()
			local match = R.newMatch()
			R.addChunk(match, R.readChunk(chunkOf(1, 0, 5)))
			local other = chunkOf(2, 5, 10)
			other.rec = "autre"
			T.expect(not R.addChunk(match, R.readChunk(other)))
		end)

		T.it("trie les évènements en gardant l'ordre à instant égal", function()
			local match = matchOf({
				chunkOf(1, 0, 5, {
					events = {
						{ t = 2, k = "kill", id = 1, victim = 2 },
						{ t = 1, k = "shot", id = 1 },
						{ t = 2, k = "death", id = 2 },
					},
				}),
			})
			T.expectEqual(match.events[1].k, "shot")
			T.expectEqual(match.events[2].k, "kill")
			T.expectEqual(match.events[3].k, "death")
			T.expectEqual(R.killOf(match, 2, 2.1).id, 1)
			T.expect(R.killOf(match, 2, 3) == nil)
		end)
	end)

	T.describe("MatchRecordRules lecture", function()
		local track = { t = { 0, 0.05, 0.1, 1.0, 1.05 }, cols = { { 0, 1, 2, 10, 11 }, { 3.1, -3.1, 0, 0, 0 } } }

		T.it("interpole entre deux relevés et suit l'indice d'une image à l'autre", function()
			local out = {}
			local present, index = R.sample(track, 0.075, out)
			T.expect(present)
			T.expectNear(out[1], 1.5, 1e-9)
			local _, nextIndex = R.sample(track, 0.09, out, index)
			T.expectEqual(nextIndex, index)
		end)

		T.it("interpole un cap par le plus court chemin", function()
			local out = {}
			R.sample(track, 0.025, out, nil, 2)
			T.expect(math.abs(out[2]) > 3)
		end)

		T.it("absent dans un trou et au-delà des bords", function()
			local out = {}
			T.expect(not (R.sample(track, 0.6, out)))
			T.expect((R.sample(track, 0.3, out)))
			T.expect(not (R.sample(track, 1.5, out)))
			T.expect(not (R.sample(track, -1, out)))
		end)

		T.it("garde les colonnes de drapeaux sans interpolation", function()
			local flags = { t = { 0, 1 }, cols = { { 0, 1 } } }
			local out = {}
			R.sample(flags, 0.2, out, nil, nil, { [1] = true })
			T.expectEqual(out[1], 0)
		end)

		T.it("trouve l'état en place à un instant", function()
			local list =
				{ { t = 1, k = "equip", id = 1, tool = "AWP" }, { t = 3, k = "equip", id = 1, tool = "Knife" } }
			T.expect(R.lastBefore(list, 0.5) == nil)
			T.expectEqual(R.lastBefore(list, 2).tool, "AWP")
			T.expectEqual(R.lastBefore(list, 3).tool, "Knife")
		end)
	end)

	T.describe("MatchRecordRules HUD et sons du rejeu (#586)", function()
		T.it("garde les nouveaux évènements à la lecture d'un morceau", function()
			local chunk = R.readChunk(chunkOf(1, 0, 5, {
				events = {
					{ t = 0.1, k = "fx", id = 7, s = "pan" },
					{ t = 0.2, k = "hit", id = 7, kl = true, hs = true },
					{ t = 0.3, k = "ammo", id = 7, m = 4, r = 30 },
					{ t = 0.4, k = "step", id = 7, ld = true },
					{ t = 0.5, k = "round", id = 0, s = "active", l = 120 },
					{ t = 0.6, k = "scores", id = 0, sc = {} },
				},
			}))
			T.expect(chunk ~= nil)
			T.expectEqual(#(chunk :: any).events, 6)
		end)

		T.it("range le classement trié avec une clé qui suit les kills et les morts", function()
			local list, key = R.encodeScores({
				[-2] = { id = -2, name = "Lucie", isBot = true, kills = 3, deaths = 1 },
				[7] = { id = 7, name = "Joueur", kills = 5, deaths = 0 },
			})
			T.expectEqual(#list, 2)
			T.expectEqual(list[1].i, -2)
			T.expectEqual(list[1].b, true)
			T.expectEqual(list[2].b, nil)
			T.expectEqual(key, "-2:3:1,7:5:0")
			local _, other = R.encodeScores({ [7] = { id = 7, name = "Joueur", kills = 6, deaths = 0 } })
			T.expect(other ~= key)
		end)

		T.it("relit le classement au format du HUD, joueur rejoué renommé", function()
			local list = R.encodeScores({
				[-2] = { id = -2, name = "Lucie", isBot = true, kills = 3, deaths = 1 },
				[7] = { id = 7, name = "Joueur", kills = 5, deaths = 0 },
			})
			local scores = R.decodeScores(list, { [7] = "Studio" })
			T.expectEqual(scores[7].name, "Studio")
			T.expectEqual(scores[7].kills, 5)
			T.expectEqual(scores[7].isBot, false)
			T.expectEqual(scores[-2].name, "Lucie")
			T.expectEqual(scores[-2].isBot, true)
			T.expect(next(R.decodeScores("abîmé")) == nil)
			T.expect(next(R.decodeScores({ { i = "x", n = 3 } })) == nil, "ligne abîmée écartée")
		end)

		T.it("range une réserve infinie en JSON et la relit", function()
			T.expectEqual(R.encodeAmmo(math.huge), -1)
			T.expectEqual(R.decodeAmmo(-1), math.huge)
			T.expectEqual(R.encodeAmmo(4), 4)
			T.expectEqual(R.decodeAmmo(4), 4)
			T.expect(R.encodeAmmo(nil) == nil)
			T.expect(R.encodeAmmo(0 / 0) == nil)
			T.expect(R.decodeAmmo({ v = "inf" }) == nil)
		end)

		T.it("décompte le timer d'une manche active et le fige sinon", function()
			local active = { t = 10, k = "round", id = 0, s = "active", l = 120.4 }
			T.expectEqual(R.timeLeftAt(active, 10), 121)
			T.expectEqual(R.timeLeftAt(active, 15.5), 115)
			T.expectEqual(R.timeLeftAt(active, 500), 0)
			local result = { t = 10, k = "round", id = 0, s = "result", l = 0 }
			T.expectEqual(R.timeLeftAt(result, 20), 0)
			local idle = { t = 10, k = "round", id = 0, s = "idle", l = 90 }
			T.expectEqual(R.timeLeftAt(idle, 30), 90)
			T.expect(R.timeLeftAt(nil, 3) == nil)
		end)

		T.it("compte la série de kills depuis la dernière mort ou fin de manche", function()
			local match = R.newMatch()
			match.events = {
				{ t = 1, k = "kill", id = 7, victim = -1 },
				{ t = 2, k = "kill", id = 7, victim = -2 },
				{ t = 3, k = "kill", id = -3, victim = 7 },
				{ t = 3, k = "death", id = 7 },
				{ t = 4, k = "kill", id = 7, victim = -1 },
				{ t = 5, k = "kill", id = -1, victim = -2 },
				{ t = 6, k = "round", id = 0, s = "result", l = 0 },
				{ t = 7, k = "round", id = 0, s = "active", l = 120 },
				{ t = 8, k = "kill", id = 7, victim = -4 },
			}
			T.expectEqual(R.streakAt(match, 7, 0.5), 0)
			T.expectEqual(R.streakAt(match, 7, 2), 2)
			T.expectEqual(R.streakAt(match, 7, 3), 0, "mort")
			T.expectEqual(R.streakAt(match, 7, 5), 1, "kill d'un autre ignoré")
			T.expectEqual(R.streakAt(match, 7, 6.5), 0, "fin de manche")
			T.expectEqual(R.streakAt(match, 7, 9), 1)
		end)

		T.it("mesure la vitesse horizontale d'une piste, 0 hors de la piste", function()
			-- 30 Hz, 12 studs/s sur X, 5 studs/s sur Y (non comptés)
			local track = { t = {}, cols = { {}, {}, {} } }
			for i = 0, 30 do
				table.insert(track.t, i / 30)
				table.insert(track.cols[1], 12 * i / 30)
				table.insert(track.cols[2], 5 * i / 30)
				table.insert(track.cols[3], 0)
			end
			local a, b = {}, {}
			T.expectNear(R.speedAt(track, 0.5, 0.1, a, b), 12, 1e-6)
			T.expectEqual(R.speedAt(track, 3, 0.1, a, b), 0)
		end)
	end)
end

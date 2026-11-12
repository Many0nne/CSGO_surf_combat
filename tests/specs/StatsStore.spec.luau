-- StatsStore (#296) avec un DataStore, des joueurs et une horloge simulés : nombre d'écritures (aucune au menu), kill
-- avant la fin du chargement, deux serveurs sur le même joueur, échec signalé, arrêt du serveur en parallèle.
return function(T, Loader)
	-- Cette méthode permet de simuler `task` et `os.clock` par coroutines lorsqu'un test fait avancer le temps lui-même :
	-- `task.wait` endort la coroutine courante jusqu'à ce que `advance` atteigne son réveil.
	local function makeScheduler()
		local sched = { now = 0, sleepers = {} }
		-- Cette méthode permet de reprendre une coroutine lorsqu'elle démarre ou se réveille, en remontant ses erreurs.
		local function resume(co, ...)
			local ok, err = coroutine.resume(co, ...)
			if not ok then
				error(debug.traceback(co, tostring(err)), 0)
			end
		end
		sched.task = {
			spawn = function(fn, ...)
				resume(coroutine.create(fn), ...)
			end,
			wait = function(seconds: number?)
				table.insert(sched.sleepers, { co = coroutine.running(), at = sched.now + (seconds or 0) })
				coroutine.yield()
			end,
		}
		sched.os = {
			clock = function()
				return sched.now
			end,
		}
		-- Cette méthode permet d'avancer l'horloge de `seconds` lorsqu'un test laisse passer le temps, en réveillant les
		-- coroutines dans l'ordre de leurs échéances.
		function sched.advance(seconds: number)
			local target = sched.now + seconds
			while true do
				local index, best = nil, nil
				for i, sleeper in sched.sleepers do
					if sleeper.at <= target and (best == nil or sleeper.at < best.at) then
						index, best = i, sleeper
					end
				end
				if not best then
					break
				end
				table.remove(sched.sleepers, index)
				sched.now = best.at
				resume(best.co)
			end
			sched.now = target
		end
		return sched
	end

	-- Cette méthode permet de copier une valeur en profondeur lorsque le faux DataStore la stocke ou la rend.
	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for k, v in value do
			copy[k] = deepCopy(v)
		end
		return copy
	end

	-- Cette méthode permet de simuler un DataStore partagé par plusieurs serveurs lorsqu'un test compte les écritures ;
	-- `latency` endort chaque requête, `failures` fait échouer les N prochaines, `commitThenFail` fait échouer les N
	-- prochaines écritures après les avoir faites (réponse perdue) ; `readLatency` et `readFailures` ne visent que les lectures.
	local function makeDataStore(sched)
		local ds = {
			data = {},
			writes = 0,
			reads = 0,
			latency = 0,
			failures = 0,
			commitThenFail = 0,
			readLatency = 0,
			readFailures = 0,
		}
		-- Cette méthode permet d'attendre la latence simulée et d'échouer si une panne est programmée.
		local function request()
			if ds.latency > 0 then
				sched.task.wait(ds.latency)
			end
			if ds.failures > 0 then
				ds.failures -= 1
				error("DataStore indisponible (simulé)")
			end
		end
		-- Cette méthode permet de lire un enregistrement (copie) lorsque StatsStore charge un joueur, latence et pannes
		-- simulées comprises.
		function ds.GetAsync(_, key: string)
			if ds.readLatency > 0 then
				sched.task.wait(ds.readLatency)
			end
			if ds.readFailures > 0 then
				ds.readFailures -= 1
				error("lecture impossible (simulé)")
			end
			request()
			ds.reads += 1
			return deepCopy(ds.data[key])
		end
		-- Cette méthode permet d'appliquer une fusion à un enregistrement lorsque StatsStore écrit ; nil annule l'écriture
		-- (non comptée), comme Roblox.
		function ds.UpdateAsync(_, key: string, transform)
			request()
			local nextValue = transform(deepCopy(ds.data[key]))
			if nextValue == nil then
				return nil
			end
			ds.writes += 1
			ds.data[key] = deepCopy(nextValue)
			if ds.commitThenFail > 0 then
				ds.commitThenFail -= 1
				error("réponse perdue (simulé)")
			end
			return deepCopy(nextValue)
		end
		return ds
	end

	-- Ids de session uniques sur tous les serveurs simulés, comme HttpService:GenerateGUID
	local guids = 0

	-- Cette méthode permet de monter un serveur (un StatsStore isolé) sur un DataStore et une horloge partagés lorsqu'un
	-- test démarre ; renvoie le module, les avertissements émis et de quoi faire partir un joueur ou arrêter le serveur.
	local function makeServer(sched, ds)
		local players = {}
		local removing, closing = nil, nil
		local warnings = {}
		local services = {
			HttpService = {
				GenerateGUID = function()
					guids += 1
					return "session-" .. guids
				end,
			},
			DataStoreService = {
				GetDataStore = function()
					return ds
				end,
			},
			Players = {
				GetPlayers = function()
					return players
				end,
				PlayerRemoving = {
					Connect = function(_, fn)
						removing = fn
					end,
				},
			},
		}
		local loader = Loader.new(services, {
			task = sched.task,
			os = sched.os,
			warn = function(...)
				table.insert(warnings, table.concat({ ... }, " "))
			end,
		})
		loader.globals.game = {
			GetService = function(_, name)
				return loader.game:GetService(name)
			end,
			BindToClose = function(_, fn)
				closing = fn
			end,
		}
		local server = { warnings = warnings, StatsStore = loader:require("src/server/StatsStore") }
		server.StatsStore.init()
		-- Cette méthode permet de faire arriver un joueur lorsqu'un test en a besoin (chargement lancé comme init.server).
		function server.join(userId: number)
			local player = { UserId = userId, Name = "Joueur" .. userId }
			table.insert(players, player)
			sched.task.spawn(server.StatsStore.load, player)
			return player
		end
		-- Cette méthode permet de faire partir un joueur lorsqu'un test simule sa déconnexion.
		function server.leave(player)
			table.remove(players, table.find(players, player))
			sched.task.spawn(removing, player)
		end
		-- Cette méthode permet de lancer l'arrêt du serveur lorsqu'un test simule BindToClose ; renvoie un drapeau de fin.
		function server.close()
			local state = { done = false }
			sched.task.spawn(function()
				closing()
				state.done = true
			end)
			return state
		end
		return server
	end

	-- Cette méthode permet de lire les compteurs stockés d'un joueur dans le faux DataStore lorsqu'un test les vérifie.
	local function storedStats(ds, userId: number)
		local record = ds.data[tostring(userId)]
		return record and record.stats
	end

	local INTERVAL = Loader.new({}):require("src/shared/GameConfig").AUTO_SAVE_INTERVAL

	T.describe("StatsStore : écritures", function()
		T.it("aucune écriture en 10 minutes pour des joueurs restés au menu", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			server.join(1)
			server.join(2)
			sched.advance(600)
			T.expectEqual(ds.writes, 0, "écritures DataStore sur 10 min au menu (2 joueurs)")
		end)

		T.it("écrit une fois les écarts d'une manche, puis plus rien", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			server.StatsStore.recordRoundEnd(alice, true)
			sched.advance(600)
			T.expectEqual(ds.writes, 1)
			local stats = storedStats(ds, 1)
			T.expectEqual(stats.kills, 1)
			T.expectEqual(stats.roundsPlayed, 1)
			T.expectEqual(stats.roundsWon, 1)
			T.expectEqual(server.StatsStore.getStats(alice).roundsWon, 1, "stocké relu après écriture")
		end)

		T.it("garde un kill enregistré avant la fin du chargement et l'ajoute au profil stocké", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 1, stats = { kills = 10, deaths = 2, roundsPlayed = 3, roundsWon = 1 } }
			ds.latency = 5
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			T.expectEqual(server.StatsStore.getStats(alice).kills, 1, "écart visible pendant le chargement")
			sched.advance(5)
			T.expectEqual(server.StatsStore.getStats(alice).kills, 11, "stocké + écart après chargement")
			sched.advance(INTERVAL)
			T.expectEqual(storedStats(ds, 1).kills, 11)
			T.expectEqual(storedStats(ds, 1).deaths, 2)
		end)

		T.it("deux serveurs sur le même joueur additionnent leurs écarts (pas d'écrasement)", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 1, stats = { kills = 5, deaths = 0, roundsPlayed = 0, roundsWon = 0 } }
			local old = makeServer(sched, ds)
			local fresh = makeServer(sched, ds)
			local onOld = old.join(1)
			local onFresh = fresh.join(1)
			old.StatsStore.recordKill(onOld)
			fresh.StatsStore.recordKill(onFresh)
			fresh.StatsStore.recordKill(onFresh)
			-- La session récente écrit d'abord, l'ancienne (en retard) ensuite : rien n'est perdu
			fresh.leave(onFresh)
			old.leave(onOld)
			T.expectEqual(storedStats(ds, 1).kills, 8)
		end)

		T.it("signale un échec d'écriture et garde les écarts pour la suivante", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordDeath(alice)
			ds.failures = 3 -- les trois essais d'une écriture
			sched.advance(INTERVAL + 10)
			T.expectEqual(ds.writes, 0)
			T.expect(#server.warnings == 1 and string.find(server.warnings[1], "sauvegarde impossible", 1, true) ~= nil)
			server.StatsStore.recordDeath(alice)
			sched.advance(INTERVAL)
			T.expectEqual(ds.writes, 1, "le lot en échec repart tel quel")
			T.expectEqual(storedStats(ds, 1).deaths, 1)
			T.expectEqual(server.StatsStore.getStats(alice).deaths, 2, "écart suivant visible, pas encore écrit")
			sched.advance(INTERVAL)
			T.expectEqual(ds.writes, 2, "puis l'écart arrivé depuis")
			T.expectEqual(storedStats(ds, 1).deaths, 2)
		end)

		T.it("une écriture passée mais signalée en échec n'est pas comptée deux fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			ds.commitThenFail = 1
			sched.advance(INTERVAL + 10)
			T.expectEqual(storedStats(ds, 1).kills, 1)
			server.StatsStore.recordKill(alice)
			sched.advance(INTERVAL)
			T.expectEqual(storedStats(ds, 1).kills, 2)
			T.expectEqual(server.StatsStore.getStats(alice).kills, 2)
		end)

		T.it("lecture en échec (services d'API coupés) : aucune écriture, arrêt sans attente", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(10)
			server.StatsStore.recordKill(alice)
			sched.advance(INTERVAL)
			local state = server.close()
			sched.advance(0.5)
			T.expect(state.done, "arrêt terminé tout de suite")
			T.expectEqual(ds.writes, 0)
			T.expect(string.find(server.warnings[1], "chargement impossible", 1, true) ~= nil)
		end)

		T.it(
			"format plus récent écrit entre-temps par un autre serveur : écriture annulée, sauvegarde coupée",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.StatsStore.recordKill(alice)
				ds.data["1"] = { schemaVersion = 99, stats = { kills = 40 } }
				sched.advance(INTERVAL)
				T.expectEqual(ds.writes, 0)
				T.expectEqual(ds.data["1"].stats.kills, 40)
				T.expect(string.find(server.warnings[1], "format enregistré inconnu", 1, true) ~= nil, "signalé")
				server.StatsStore.recordKill(alice)
				sched.advance(INTERVAL)
				T.expectEqual(ds.writes, 0, "plus aucune tentative")
			end
		)

		T.it("ne touche pas un enregistrement d'un format plus récent", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 99, stats = { kills = 40 } }
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			server.leave(alice)
			sched.advance(INTERVAL * 2)
			T.expectEqual(ds.writes, 0)
			T.expectEqual(ds.data["1"].schemaVersion, 99, "pas réétiqueté")
			T.expectEqual(ds.data["1"].stats.kills, 40)
		end)
	end)

	T.describe("StatsStore : départ et arrêt du serveur", function()
		T.it("départ pendant une écriture qui échoue : les écarts repartent plus tard", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			ds.latency = 1
			ds.failures = 3
			sched.advance(INTERVAL) -- écriture lancée, en vol
			server.StatsStore.recordDeath(alice)
			server.leave(alice)
			sched.advance(10) -- les trois essais échouent
			T.expectEqual(ds.writes, 0)
			sched.advance(INTERVAL)
			T.expectEqual(ds.writes, 2, "lot en échec puis écarts arrivés pendant l'écriture")
			T.expectEqual(storedStats(ds, 1).kills, 1)
			T.expectEqual(storedStats(ds, 1).deaths, 1)
		end)

		T.it("départ pendant une écriture réussie : les écarts arrivés entre-temps partent aussitôt", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			ds.latency = 1
			sched.advance(INTERVAL)
			server.StatsStore.recordDeath(alice)
			server.leave(alice)
			sched.advance(3)
			T.expectEqual(storedStats(ds, 1).deaths, 1)
		end)

		T.it("départ puis arrêt : une seule écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			server.leave(alice)
			local state = server.close()
			sched.advance(1)
			T.expect(state.done, "arrêt terminé")
			T.expectEqual(ds.writes, 1)
		end)

		T.it("arrêt avec le DataStore en panne : abandon avant la fin du budget de BindToClose", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			ds.failures = math.huge
			local state = server.close()
			sched.advance(25)
			T.expect(state.done, "arrêt terminé dans les 25 s")
			T.expect(string.find(server.warnings[#server.warnings], "abandonnée", 1, true) ~= nil, "abandon signalé")
		end)

		T.it("chargement en échec après une écriture réussie : la sauvegarde reste permise", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.readLatency = INTERVAL + 10 -- l'auto-sauvegarde écrit avant la fin de la lecture
			ds.readFailures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			sched.advance(INTERVAL)
			T.expectEqual(storedStats(ds, 1).kills, 1, "écrit pendant la lecture")
			sched.advance(3 * (INTERVAL + 10) + 6) -- les trois lectures échouent
			server.StatsStore.recordKill(alice)
			sched.advance(INTERVAL)
			T.expectEqual(storedStats(ds, 1).kills, 2, "toujours sauvegardé")
			T.expectEqual(#server.warnings, 0)
		end)

		T.it("arrêt : écrit les joueurs en parallèle", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local players = {}
			for id = 1, 4 do
				players[id] = server.join(id)
				server.StatsStore.recordKill(players[id])
			end
			ds.latency = 3
			local state = server.close()
			sched.advance(3.5)
			T.expectEqual(ds.writes, 4, "quatre écritures en 3,5 s (3 s chacune)")
			T.expect(state.done, "arrêt terminé sans attendre les écritures l'une après l'autre")
		end)

		T.it("arrêt pendant une écriture : les écarts arrivés entre-temps repartent", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.StatsStore.recordKill(alice)
			ds.latency = 2
			sched.advance(INTERVAL) -- écriture lancée, en vol
			server.StatsStore.recordKill(alice)
			local state = server.close()
			sched.advance(10)
			T.expect(state.done, "arrêt terminé")
			T.expectEqual(storedStats(ds, 1).kills, 2)
		end)
	end)
end

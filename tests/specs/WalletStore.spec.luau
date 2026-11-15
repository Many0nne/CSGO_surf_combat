-- WalletStore (#391) avec un DataStore, des joueurs et une horloge simulés : gain et dépense refusés avant le
-- chargement ou après une lecture en échec, solde insuffisant, écriture peu après un changement, deux serveurs, lot
-- renvoyé, départ et arrêt du serveur, solde de session de Studio (DebugCredits).
return function(T, Loader)
	-- Cette méthode permet de simuler `task` et `os.clock` par coroutines lorsqu'un test fait avancer le temps lui-même.
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
	-- prochaines écritures après les avoir faites (réponse perdue).
	local function makeDataStore(sched)
		local ds = { data = {}, writes = 0, latency = 0, failures = 0, commitThenFail = 0 }
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
		-- Cette méthode permet de lire un enregistrement (copie) lorsque WalletStore charge un joueur.
		function ds.GetAsync(_, key: string)
			request()
			return deepCopy(ds.data[key])
		end
		-- Cette méthode permet d'appliquer une fusion à un enregistrement lorsque WalletStore écrit ; nil annule
		-- l'écriture (non comptée), comme Roblox.
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

	local guids = 0

	-- Cette méthode permet de monter un serveur (un WalletStore isolé) sur un DataStore et une horloge partagés lorsqu'un
	-- test démarre ; renvoie le module, les avertissements émis et de quoi faire partir un joueur ou arrêter le serveur.
	local function makeServer(sched, ds)
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
			print = function() end,
		})
		loader.globals.game = {
			GetService = function(_, name)
				return loader.game:GetService(name)
			end,
			BindToClose = function(_, fn)
				closing = fn
			end,
		}
		local server = { warnings = warnings, Wallet = loader:require("src/server/WalletStore") }
		server.Wallet.init()
		-- Cette méthode permet de faire arriver un joueur lorsqu'un test en a besoin (chargement lancé comme init.server).
		function server.join(userId: number)
			local player = { UserId = userId, Name = "Joueur" .. userId, attributes = {} }
			-- Cette méthode permet de simuler Player:SetAttribute lorsque WalletStore publie le solde.
			function player.SetAttribute(self, name: string, value: any)
				self.attributes[name] = value
			end
			-- Cette méthode permet de simuler Player:GetAttribute lorsque WalletStore lit DebugCredits.
			function player.GetAttribute(self, name: string)
				return self.attributes[name]
			end
			sched.task.spawn(server.Wallet.load, player)
			return player
		end
		-- Cette méthode permet de faire partir un joueur lorsqu'un test simule sa déconnexion.
		function server.leave(player)
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

	-- Cette méthode permet de lire le solde stocké d'un joueur dans le faux DataStore lorsqu'un test le vérifie.
	local function storedCredits(ds, userId: number): number?
		local record = ds.data[tostring(userId)]
		return record and record.credits
	end

	local INTERVAL = Loader.new({}):require("src/shared/GameConfig").AUTO_SAVE_INTERVAL

	T.describe("WalletStore : solde", function()
		T.it("nouveau joueur : 0 publié dans l'attribut, aucune écriture au menu", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(server.Wallet.balance(alice), 0)
			T.expectEqual(alice.attributes.Credits, 0)
			sched.advance(600)
			T.expectEqual(ds.writes, 0)
		end)

		T.it("refuse gain et dépense avant la fin du chargement", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 1, credits = 300 }
			ds.latency = 5
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(server.Wallet.balance(alice), nil, "pas encore chargé")
			T.expectEqual(alice.attributes.Credits, nil, "pas d'attribut avant le chargement")
			T.expect(not server.Wallet.canChange(alice))
			T.expect(not server.Wallet.add(alice, 10))
			T.expect(not server.Wallet.spend(alice, 10))
			sched.advance(5)
			T.expectEqual(server.Wallet.balance(alice), 300)
			T.expect(server.Wallet.add(alice, 10))
			T.expectEqual(server.Wallet.balance(alice), 310)
		end)

		T.it("dépense : refus si le solde ne suffit pas, rien de débité", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 1, credits = 400 }
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expect(not server.Wallet.spend(alice, 500))
			T.expectEqual(server.Wallet.balance(alice), 400)
			T.expect(server.Wallet.spend(alice, 400))
			T.expectEqual(server.Wallet.balance(alice), 0)
			T.expectEqual(alice.attributes.Credits, 0)
		end)

		T.it("refuse un montant invalide", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			for _, amount in { 0, -10, 2.5, math.huge, 0 / 0 } do
				T.expect(not server.Wallet.add(alice, amount), "gain " .. tostring(amount))
				T.expect(not server.Wallet.spend(alice, amount), "dépense " .. tostring(amount))
			end
			T.expectEqual(server.Wallet.balance(alice), 0)
		end)

		T.it("écrête un gain au plafond", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local max = Loader.new({}):require("src/shared/WalletRules").MAX_BALANCE
			T.expect(server.Wallet.add(alice, max))
			T.expect(server.Wallet.add(alice, 5))
			T.expectEqual(server.Wallet.balance(alice), max)
		end)

		T.it("lecture en échec : solde indisponible, aucun changement ni écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(10)
			T.expectEqual(server.Wallet.balance(alice), nil)
			T.expect(not server.Wallet.add(alice, 50))
			sched.advance(INTERVAL)
			T.expectEqual(ds.writes, 0)
			T.expect(string.find(server.warnings[1], "chargement impossible", 1, true) ~= nil)
		end)
	end)

	T.describe("WalletStore : écritures", function()
		T.it("écrit une fois peu après des changements rapprochés", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 200)
			sched.advance(1)
			server.Wallet.spend(alice, 50)
			T.expectEqual(ds.writes, 0, "pas d'écriture immédiate")
			sched.advance(10)
			T.expectEqual(ds.writes, 1, "une seule écriture pour les deux changements")
			T.expectEqual(storedCredits(ds, 1), 150)
			sched.advance(600)
			T.expectEqual(ds.writes, 1, "plus rien ensuite")
		end)

		T.it("deux serveurs sur le même joueur additionnent leurs écarts", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 1, credits = 1000 }
			local old = makeServer(sched, ds)
			local fresh = makeServer(sched, ds)
			local onOld = old.join(1)
			local onFresh = fresh.join(1)
			old.Wallet.spend(onOld, 300)
			fresh.Wallet.add(onFresh, 50)
			fresh.leave(onFresh)
			old.leave(onOld)
			T.expectEqual(storedCredits(ds, 1), 750)
		end)

		T.it("garde l'écart après un échec et le renvoie tel quel", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 80)
			ds.failures = 3
			sched.advance(20)
			T.expectEqual(ds.writes, 0)
			T.expect(string.find(server.warnings[1], "sauvegarde impossible", 1, true) ~= nil)
			T.expectEqual(server.Wallet.balance(alice), 80, "solde gardé en mémoire")
			sched.advance(INTERVAL)
			T.expectEqual(storedCredits(ds, 1), 80)
		end)

		T.it("une écriture passée mais signalée en échec n'est pas comptée deux fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 100)
			ds.commitThenFail = 1
			sched.advance(20)
			T.expectEqual(storedCredits(ds, 1), 100)
			server.Wallet.add(alice, 1)
			sched.advance(20)
			T.expectEqual(storedCredits(ds, 1), 101)
			T.expectEqual(server.Wallet.balance(alice), 101)
		end)

		T.it("écrit au départ du joueur et à l'arrêt du serveur", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local bob = server.join(2)
			server.Wallet.add(alice, 30)
			server.Wallet.add(bob, 70)
			server.leave(alice)
			T.expectEqual(storedCredits(ds, 1), 30, "écrit au départ, sans attendre")
			local state = server.close()
			sched.advance(1)
			T.expect(state.done)
			T.expectEqual(storedCredits(ds, 2), 70, "écrit à l'arrêt")
		end)
	end)

	T.describe("WalletStore : DebugCredits (Studio)", function()
		T.it("ajoute puis retire, sans descendre sous 0", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			alice.attributes.DebugCredits = 1500
			server.Wallet.applyDebug(alice)
			T.expectEqual(server.Wallet.balance(alice), 1500)
			T.expectEqual(alice.attributes.DebugCredits, nil, "attribut remis à nil")
			alice.attributes.DebugCredits = -2000
			server.Wallet.applyDebug(alice)
			T.expectEqual(server.Wallet.balance(alice), 0)
		end)

		T.it("sans accès aux API : solde de session, jamais écrit", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(10)
			alice.attributes.DebugCredits = 500
			server.Wallet.applyDebug(alice)
			T.expectEqual(server.Wallet.balance(alice), 500)
			T.expectEqual(alice.attributes.Credits, 500)
			server.leave(alice)
			sched.advance(INTERVAL)
			T.expectEqual(ds.writes, 0)
		end)
	end)
end

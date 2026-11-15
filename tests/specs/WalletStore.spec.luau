-- WalletStore (#391) sur l'enregistrement de l'inventaire (#396, InventoryStore) avec un DataStore, des joueurs et une
-- horloge simulés : solde publié, gains et dépenses refusés avant le chargement, gains écrits par lots (deux serveurs,
-- lot renvoyé), débit immédiat vérifié sur le solde stocké (ordre, refus, échec d'écriture), transactions d'un même
-- joueur l'une après l'autre, enregistrement v1 sans `wallet`, départ et arrêt, solde de session de Studio.
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
				resume(if type(fn) == "thread" then fn else coroutine.create(fn), ...)
			end,
			wait = function(seconds: number?)
				table.insert(sched.sleepers, { co = coroutine.running(), at = sched.now + (seconds or 0) })
				coroutine.yield()
			end,
			delay = function(seconds: number, fn, ...)
				local args = table.pack(...)
				local co = coroutine.create(function()
					fn(table.unpack(args, 1, args.n))
				end)
				table.insert(sched.sleepers, { co = co, at = sched.now + seconds })
			end,
		}
		sched.os = setmetatable({
			clock = function()
				return sched.now
			end,
		}, { __index = os })
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
		-- Cette méthode permet de lire un enregistrement (copie) lorsque InventoryStore charge un joueur.
		function ds.GetAsync(_, key: string)
			request()
			return deepCopy(ds.data[key])
		end
		-- Cette méthode permet d'appliquer une fusion à un enregistrement lorsque InventoryStore écrit ; nil annule
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

	-- Cette méthode permet de simuler un signal Roblox (plusieurs abonnés) lorsqu'un module s'y connecte au chargement.
	local function makeSignal()
		local signal = { handlers = {} }
		function signal.Connect(_, fn)
			table.insert(signal.handlers, fn)
			return { Disconnect = function() end }
		end
		return signal
	end

	local guids = 0

	-- Cette méthode permet de monter un serveur (InventoryStore et WalletStore isolés) sur un DataStore et une horloge
	-- partagés lorsqu'un test démarre ; renvoie la façade, l'inventaire, les avertissements et de quoi faire arriver ou
	-- partir un joueur et arrêter le serveur.
	local function makeServer(sched, ds)
		local closing = nil
		local warnings = {}
		local removing = makeSignal()
		local opened = {}
		local services = {
			HttpService = {
				GenerateGUID = function()
					guids += 1
					return "session-" .. guids
				end,
			},
			DataStoreService = {
				GetDataStore = function(_, name: string)
					table.insert(opened, name)
					return ds
				end,
			},
			Players = { PlayerRemoving = removing, PlayerAdded = makeSignal() },
			RunService = {
				IsStudio = function()
					return false
				end,
			},
			StarterPack = {
				GetChildren = function()
					return {}
				end,
			},
		}
		local loader = Loader.new(services, {
			task = sched.task,
			os = sched.os,
			warn = function(...)
				local parts = {}
				for _, v in { ... } do
					table.insert(parts, tostring(v))
				end
				table.insert(warnings, table.concat(parts, " "))
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
			CreatorType = "Group",
			CreatorId = 0,
		}
		local server = {
			warnings = warnings,
			opened = opened,
			Inventory = loader:require("src/server/InventoryStore"),
			Wallet = loader:require("src/server/WalletStore"),
		}
		server.Inventory.init({ Name = "EquipItem", OnServerEvent = makeSignal() }, function()
			return false
		end)
		-- Cette méthode permet de faire arriver un joueur lorsqu'un test en a besoin (inscription puis chargement lancé
		-- comme init.server).
		function server.join(userId: number)
			local player = {
				UserId = userId,
				Name = "Joueur" .. userId,
				Parent = true,
				Character = nil,
				attributes = {},
				ChildAdded = makeSignal(),
			}
			-- Cette méthode permet de simuler Player:SetAttribute lorsque les stores publient un attribut.
			function player.SetAttribute(self, name: string, value: any)
				self.attributes[name] = value
			end
			-- Cette méthode permet de simuler Player:GetAttribute lorsque WalletStore lit DebugCredits.
			function player.GetAttribute(self, name: string)
				return self.attributes[name]
			end
			server.Inventory.setup(player)
			sched.task.spawn(server.Inventory.load, player)
			return player
		end
		-- Cette méthode permet de lancer une dépense dans sa propre coroutine (elle attend l'écriture) lorsqu'un test la
		-- demande ; renvoie un état rempli à la fin (`done`, `status`).
		function server.spend(player, amount: number)
			local state = { done = false, status = nil }
			sched.task.spawn(function()
				state.status = server.Wallet.spend(player, amount)
				state.done = true
			end)
			return state
		end
		-- Cette méthode permet de lancer une transaction dans sa propre coroutine lorsqu'un test en simule une (#393) ;
		-- renvoie un état rempli à la fin (`done`, `status`, `result`).
		function server.transact(player, op)
			local state = { done = false, status = nil, result = nil }
			sched.task.spawn(function()
				state.status, state.result = server.Inventory.transact(player, op)
				state.done = true
			end)
			return state
		end
		-- Cette méthode permet de faire partir un joueur lorsqu'un test simule sa déconnexion.
		function server.leave(player)
			player.Parent = nil
			for _, handler in removing.handlers do
				sched.task.spawn(handler, player)
			end
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

	local Wallet = Loader.new({}):require("src/shared/WalletRules")

	-- Cette méthode permet de poser un enregistrement de schéma 2 dans le faux DataStore lorsqu'un test part d'un solde.
	local function seed(ds, userId: number, earned: number, purchased: number?, items: { string }?)
		local w = Wallet.empty()
		w.earned = earned
		w.purchased = purchased or 0
		ds.data[tostring(userId)] = { schemaVersion = 2, items = items or {}, wallet = w }
	end

	-- Cette méthode permet de lire le portefeuille stocké d'un joueur dans le faux DataStore lorsqu'un test le vérifie.
	local function storedWallet(ds, userId: number)
		local record = ds.data[tostring(userId)]
		return record and record.wallet
	end

	-- Cette méthode permet de lire le solde stocké (gagnés + achetés) d'un joueur lorsqu'un test le vérifie.
	local function storedBalance(ds, userId: number): number?
		local w = storedWallet(ds, userId)
		return w and (w.earned + w.purchased)
	end

	-- Cette méthode permet de trouver un avertissement contenant un texte lorsqu'un test vérifie un signalement.
	local function hasWarning(server, text: string): boolean
		for _, line in server.warnings do
			if string.find(line, text, 1, true) then
				return true
			end
		end
		return false
	end

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
			seed(ds, 1, 300)
			ds.latency = 5
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(server.Wallet.balance(alice), nil, "pas encore chargé")
			T.expectEqual(alice.attributes.Credits, nil, "pas d'attribut avant le chargement")
			T.expect(not server.Wallet.canChange(alice))
			T.expect(not server.Wallet.add(alice, 10))
			local early = server.spend(alice, 10)
			T.expect(early.done)
			T.expectEqual(early.status, "loading")
			sched.advance(5)
			T.expectEqual(server.Wallet.balance(alice), 300)
			T.expectEqual(alice.attributes.Credits, 300)
			T.expect(server.Wallet.add(alice, 10))
			T.expectEqual(server.Wallet.balance(alice), 310)
		end)

		T.it("attribut = gagnés + achetés", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 120, 80)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(alice.attributes.Credits, 200)
		end)

		T.it("refuse un montant invalide", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			for _, amount in { 0, -10, 2.5, math.huge, 0 / 0 } do
				T.expect(not server.Wallet.add(alice, amount), "gain " .. tostring(amount))
				T.expectEqual(server.spend(alice, amount).status, "invalid", "dépense " .. tostring(amount))
			end
			T.expectEqual(server.Wallet.balance(alice), 0)
			T.expectEqual(ds.writes, 0)
		end)

		T.it("écrête un gain au plafond", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expect(server.Wallet.add(alice, Wallet.MAX_BALANCE))
			T.expect(server.Wallet.add(alice, 5))
			T.expectEqual(server.Wallet.balance(alice), Wallet.MAX_BALANCE)
			sched.advance(10)
			T.expectEqual(storedBalance(ds, 1), Wallet.MAX_BALANCE)
		end)

		T.it("lecture en échec : solde indisponible, aucun changement ni écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(10)
			T.expectEqual(server.Wallet.balance(alice), nil)
			T.expectEqual(alice.attributes.Credits, nil)
			T.expect(not server.Wallet.add(alice, 50))
			T.expectEqual(server.spend(alice, 5).status, "loading")
			sched.advance(600)
			T.expectEqual(ds.writes, 0)
			T.expect(hasWarning(server, "chargement impossible"))
		end)

		T.it("schéma plus récent : sauvegarde coupée, solde indisponible, enregistrement intact", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 99, items = {}, wallet = { future = true } }
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(server.Wallet.balance(alice), nil)
			T.expectEqual(server.spend(alice, 5).status, "loading")
			server.leave(alice)
			sched.advance(600)
			T.expectEqual(ds.writes, 0)
			T.expectEqual(ds.data["1"].schemaVersion, 99)
		end)
	end)

	T.describe("WalletStore : enregistrement de l'inventaire", function()
		T.it(
			"enregistrement v1 sans `wallet` : solde de départ, skins et équipement gardés à l'écriture",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				ds.data["1"] = {
					schemaVersion = 1,
					items = { "skin.awp.couchant", "weapon.m9bayonet" },
					equipped = { knife = { weapon = "weapon.m9bayonet" } },
				}
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				T.expectEqual(server.Wallet.balance(alice), Wallet.STARTING_BALANCE)
				T.expect(server.Wallet.add(alice, 25))
				sched.advance(10)
				local record = ds.data["1"]
				T.expectEqual(record.schemaVersion, 2)
				T.expectEqual(table.concat(record.items, ","), "skin.awp.couchant,weapon.m9bayonet")
				T.expectEqual(record.equipped.knife.weapon, "weapon.m9bayonet")
				T.expectEqual(record.wallet.earned, 25)
			end
		)

		T.it("seul PlayerInventory_v1 est ouvert (PlayerWallet_v1 abandonné)", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 10)
			sched.advance(10)
			server.spend(alice, 5)
			T.expect(#server.opened > 0)
			for _, name in server.opened do
				T.expectEqual(name, "PlayerInventory_v1")
			end
		end)
	end)

	T.describe("WalletStore : gains", function()
		T.it("écrit une fois peu après des gains rapprochés", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 200)
			sched.advance(1)
			server.Wallet.add(alice, 50)
			T.expectEqual(server.Wallet.balance(alice), 250)
			sched.advance(10)
			T.expectEqual(ds.writes, 1, "une seule écriture pour les deux gains")
			T.expectEqual(storedWallet(ds, 1).earned, 250)
			sched.advance(600)
			T.expectEqual(ds.writes, 1, "plus rien ensuite")
		end)

		T.it("deux serveurs sur le même joueur additionnent leurs gains", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 1000)
			local old = makeServer(sched, ds)
			local fresh = makeServer(sched, ds)
			local onOld = old.join(1)
			local onFresh = fresh.join(1)
			old.Wallet.add(onOld, 300)
			fresh.Wallet.add(onFresh, 50)
			fresh.leave(onFresh)
			old.leave(onOld)
			T.expectEqual(storedBalance(ds, 1), 1350)
		end)

		T.it("garde les gains après un échec et les renvoie", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 80)
			ds.failures = 3
			sched.advance(20)
			T.expectEqual(ds.writes, 0)
			T.expect(hasWarning(server, "sauvegarde impossible"))
			T.expectEqual(server.Wallet.balance(alice), 80, "solde gardé en mémoire")
			sched.advance(120)
			T.expectEqual(storedBalance(ds, 1), 80)
		end)

		T.it("un lot écrit mais signalé en échec n'est pas compté deux fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 100)
			ds.commitThenFail = 1
			sched.advance(20)
			T.expectEqual(storedBalance(ds, 1), 100)
			server.Wallet.add(alice, 1)
			sched.advance(20)
			T.expectEqual(storedBalance(ds, 1), 101)
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
			T.expectEqual(storedBalance(ds, 1), 30, "écrit au départ, sans attendre")
			local state = server.close()
			sched.advance(1)
			T.expect(state.done)
			T.expectEqual(storedBalance(ds, 2), 70, "écrit à l'arrêt")
		end)
	end)

	T.describe("WalletStore : dépenses", function()
		T.it("débit écrit tout de suite, achetés d'abord puis gagnés, rendu après l'écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 400, 100)
			ds.latency = 1
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(1)
			local spend = server.spend(alice, 150)
			T.expect(not spend.done, "attend l'écriture")
			sched.advance(1)
			T.expect(spend.done)
			T.expectEqual(spend.status, "ok")
			T.expectEqual(ds.writes, 1)
			T.expectEqual(storedWallet(ds, 1).purchased, 0)
			T.expectEqual(storedWallet(ds, 1).earned, 350)
			T.expectEqual(server.Wallet.balance(alice), 350)
			T.expectEqual(alice.attributes.Credits, 350)
		end)

		T.it("refus si le solde stocké ne suffit pas, même si la copie locale suffisait", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 400)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			-- Un autre serveur a dépensé entre-temps : le stocké n'a plus que 100
			seed(ds, 1, 100)
			local writes = ds.writes
			local spend = server.spend(alice, 300)
			T.expectEqual(spend.status, "insufficient")
			T.expectEqual(ds.writes, writes, "rien d'écrit")
			T.expectEqual(storedBalance(ds, 1), 100)
			T.expectEqual(server.Wallet.balance(alice), 100, "copie locale recalée sur le stocké")
			T.expectEqual(alice.attributes.Credits, 100)
		end)

		T.it("compte les gains de la session pas encore écrits", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 50)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 30)
			local spend = server.spend(alice, 70)
			T.expectEqual(spend.status, "ok")
			T.expectEqual(storedBalance(ds, 1), 10)
			sched.advance(600)
			T.expectEqual(storedBalance(ds, 1), 10, "gain pas recompté ensuite")
			T.expectEqual(server.Wallet.balance(alice), 10)
		end)

		T.it("écriture en échec : `failed`, rien débité, gains gardés", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 200)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.Wallet.add(alice, 10)
			ds.failures = 4 -- trois essais d'écriture, puis la lecture de vérification
			local spend = server.spend(alice, 50)
			sched.advance(10)
			T.expect(spend.done)
			T.expectEqual(spend.status, "failed")
			T.expectEqual(storedBalance(ds, 1), 200)
			T.expectEqual(server.Wallet.balance(alice), 210)
			sched.advance(120)
			T.expectEqual(storedBalance(ds, 1), 210, "gain écrit plus tard, dépense non rejouée")
		end)

		T.it("écriture passée mais signalée en échec : `ok`, débitée une seule fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 200)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.commitThenFail = 1
			local spend = server.spend(alice, 50)
			sched.advance(10)
			T.expectEqual(spend.status, "ok")
			T.expectEqual(storedBalance(ds, 1), 150)
			T.expectEqual(server.Wallet.balance(alice), 150)
		end)

		T.it("deux dépenses du même joueur passent l'une après l'autre : jamais sous 0", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 100)
			ds.latency = 1
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(1)
			local first = server.spend(alice, 60)
			local second = server.spend(alice, 60)
			sched.advance(5)
			T.expectEqual(first.status, "ok")
			T.expectEqual(second.status, "insufficient")
			T.expectEqual(storedBalance(ds, 1), 40)
		end)

		T.it("deux serveurs qui dépensent le même solde : un seul débit passe", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 100)
			local a = makeServer(sched, ds)
			local b = makeServer(sched, ds)
			local onA = a.join(1)
			local onB = b.join(1)
			T.expectEqual(a.spend(onA, 80).status, "ok")
			T.expectEqual(b.spend(onB, 80).status, "insufficient")
			T.expectEqual(storedBalance(ds, 1), 20)
		end)
	end)

	T.describe("InventoryStore.transact (#396)", function()
		T.it("débit et objet dans la même écriture, inventaire publié", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 500)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local state = server.transact(alice, function(record)
				local w = Wallet.debit(record.wallet, 300)
				if not w then
					return nil, "insufficient"
				end
				record.wallet = w
				table.insert(record.items, "skin.awp.couchant")
				return record, "skin.awp.couchant"
			end)
			T.expectEqual(state.status, "ok")
			T.expectEqual(state.result, "skin.awp.couchant")
			T.expectEqual(ds.writes, 1)
			T.expectEqual(storedBalance(ds, 1), 200)
			T.expectEqual(ds.data["1"].items[1], "skin.awp.couchant")
			T.expect(server.Inventory.owned(alice)["skin.awp.couchant"], "possédé tout de suite")
			T.expect(string.find(alice.attributes.OwnedItems, "skin.awp.couchant", 1, true) ~= nil)
		end)

		T.it("transaction refusée : rien ne change (stocké, solde, inventaire)", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 50, 0, { "weapon.m9bayonet" })
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local before = deepCopy(ds.data["1"])
			local state = server.transact(alice, function(record)
				local w, reason = Wallet.debit(record.wallet, 300)
				if not w then
					return nil, reason
				end
				record.wallet = w
				table.insert(record.items, "skin.awp.couchant")
				return record, nil
			end)
			T.expectEqual(state.status, "rejected")
			T.expectEqual(state.result, "insufficient")
			T.expectEqual(ds.writes, 0)
			T.expectEqual(storedBalance(ds, 1), before.wallet.earned)
			T.expectEqual(#ds.data["1"].items, 1)
			T.expectEqual(server.Wallet.balance(alice), 50)
			T.expect(not server.Inventory.owned(alice)["skin.awp.couchant"])
			sched.advance(600)
			T.expectEqual(ds.writes, 0, "rien à écrire ensuite")
		end)

		T.it("attend l'écriture en cours du joueur (sauvegarde des gains) avant de partir", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 0)
			ds.latency = 2
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(2)
			server.Wallet.add(alice, 40)
			sched.advance(6) -- la sauvegarde des gains part (2 s de latence)
			local spend = server.spend(alice, 40)
			T.expect(not spend.done)
			sched.advance(10)
			T.expectEqual(spend.status, "ok")
			T.expectEqual(storedBalance(ds, 1), 0)
			T.expectEqual(ds.writes, 2)
		end)
	end)

	T.describe("InventoryStore.transact : changements pendant l'écriture (#396)", function()
		-- Cette méthode permet de construire l'opération d'un achat refusé faute de solde lorsqu'un test simule un refus.
		local function tooExpensive(record)
			local w, reason = Wallet.debit(record.wallet, 10_000)
			if not w then
				return nil, reason
			end
			record.wallet = w
			return record, nil
		end

		T.it("un item obtenu pendant une transaction refusée est quand même écrit ensuite", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 10)
			ds.latency = 1
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(1)
			local state = server.transact(alice, tooExpensive)
			T.expect(server.Inventory.grant(alice, "weapon.m9bayonet"), "don accepté pendant l'écriture")
			server.Wallet.add(alice, 5)
			sched.advance(2)
			T.expectEqual(state.status, "rejected")
			sched.advance(30)
			T.expect(table.find(ds.data["1"].items, "weapon.m9bayonet") ~= nil, "item écrit")
			T.expectEqual(storedBalance(ds, 1), 15, "gain écrit")
		end)

		T.it("transaction réussie : items de la session réunis à ceux écrits, objet acheté possédé", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 500)
			ds.latency = 1
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(1)
			local state = server.transact(alice, function(record)
				local w = Wallet.debit(record.wallet, 100)
				if not w then
					return nil, "insufficient"
				end
				record.wallet = w
				table.insert(record.items, "skin.awp.couchant")
				return record, nil
			end)
			T.expect(server.Inventory.grant(alice, "weapon.m9bayonet"), "don accepté pendant l'écriture")
			sched.advance(2)
			T.expectEqual(state.status, "ok")
			local owned = server.Inventory.owned(alice)
			T.expect(owned["weapon.m9bayonet"], "item donné pendant l'écriture gardé")
			T.expect(owned["skin.awp.couchant"], "objet acheté possédé")
			sched.advance(30)
			T.expect(table.find(ds.data["1"].items, "weapon.m9bayonet") ~= nil)
			T.expect(table.find(ds.data["1"].items, "skin.awp.couchant") ~= nil)
		end)

		T.it("une opération en erreur est un refus immédiat, pas une panne du DataStore", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 100)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local state = server.transact(alice, function(_record)
				error("bug simulé")
			end)
			T.expect(state.done, "sans attente de nouvel essai")
			T.expectEqual(state.status, "rejected")
			T.expectEqual(state.result, "error")
			T.expectEqual(ds.writes, 0)
			T.expect(hasWarning(server, "bug simulé"))
			T.expect(not hasWarning(server, "sauvegarde impossible"))
		end)

		T.it("spend : un refus autre que le solde (portefeuille invalide) rend `failed`", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 100)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local state = server.transact(alice, function(record)
				record.wallet.earned = -1
				return record, nil
			end)
			T.expectEqual(state.status, "rejected")
			T.expectEqual(state.result, "invalid")
			T.expectEqual(storedBalance(ds, 1), 100)
		end)

		T.it("Studio sans accès aux API : une transaction s'applique au solde de session, sans écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(10)
			alice.attributes.DebugCredits = 300
			server.Wallet.applyDebug(alice)
			local state = server.transact(alice, function(record)
				local w = Wallet.debit(record.wallet, 120)
				if not w then
					return nil, "insufficient"
				end
				record.wallet = w
				table.insert(record.items, "skin.awp.couchant")
				return record, "achat"
			end)
			T.expectEqual(state.status, "ok")
			T.expectEqual(state.result, "achat")
			T.expectEqual(server.Wallet.balance(alice), 180)
			T.expect(server.Inventory.owned(alice)["skin.awp.couchant"])
			T.expectEqual(server.spend(alice, 500).status, "insufficient")
			T.expectEqual(ds.writes, 0)
		end)
		T.it("une erreur après l'écriture rend quand même le tour : les écritures suivantes passent", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 500)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local setAttribute = alice.SetAttribute
			local thrown = false
			-- Cette méthode permet de faire échouer une seule publication de l'inventaire lorsqu'un test simule un bug.
			function alice.SetAttribute(self, name: string, value: any)
				if name == "OwnedItems" and not thrown then
					thrown = true
					error("publication en panne (simulé)")
				end
				setAttribute(self, name, value)
			end
			local state = server.transact(alice, function(record)
				table.insert(record.items, "skin.awp.couchant")
				return record, nil
			end)
			T.expect(state.done)
			T.expect(thrown)
			T.expect(hasWarning(server, "écriture en erreur"))
			local spend = server.spend(alice, 100)
			sched.advance(10)
			T.expect(spend.done, "pas de blocage")
			T.expectEqual(spend.status, "ok")
			T.expectEqual(storedBalance(ds, 1), 400)
		end)

		T.it("DebugCredits sur un enregistrement d'un format refusé : pas de solde de session", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 99, items = {} }
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			alice.attributes.DebugCredits = 500
			server.Wallet.applyDebug(alice)
			T.expectEqual(server.Wallet.balance(alice), nil)
			T.expectEqual(alice.attributes.Credits, nil)
		end)
		T.it("format refusé en cours de session : solde retiré de l'affichage, gains perdus signalés", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 100)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(alice.attributes.Credits, 100)
			-- Un serveur plus récent réécrit l'enregistrement dans un schéma inconnu
			ds.data["1"] = { schemaVersion = 99, items = {} }
			server.Wallet.add(alice, 25)
			sched.advance(10)
			T.expectEqual(alice.attributes.Credits, nil)
			T.expectEqual(server.Wallet.balance(alice), nil)
			T.expect(hasWarning(server, "gains perdus : 25"))
			T.expectEqual(ds.data["1"].schemaVersion, 99, "enregistrement intact")
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
			sched.advance(10)
			T.expectEqual(storedBalance(ds, 1), 1500)
			alice.attributes.DebugCredits = -2000
			sched.task.spawn(server.Wallet.applyDebug, alice)
			T.expectEqual(server.Wallet.balance(alice), 0)
			T.expectEqual(storedBalance(ds, 1), 0)
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
			alice.attributes.DebugCredits = -200
			server.Wallet.applyDebug(alice)
			T.expectEqual(server.Wallet.balance(alice), 300)
			server.leave(alice)
			sched.advance(600)
			T.expectEqual(ds.writes, 0)
		end)
	end)
end

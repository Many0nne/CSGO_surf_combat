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
		local ds = { data = {}, writes = 0, latency = 0, failures = 0, commitThenFail = 0, requests = {} }
		-- Cette méthode permet d'attendre la latence simulée et d'échouer si une panne est programmée (heure de départ
		-- de chaque requête notée dans `requests`).
		local function request()
			table.insert(ds.requests, sched.now)
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
	-- partir un joueur et arrêter le serveur. `options.studio` : serveur de Studio (ouverture de test des caisses).
	local function makeServer(sched, ds, options: { studio: boolean? }?)
		local studio = options ~= nil and options.studio == true
		local closing = nil
		local warnings = {}
		local logs = {}
		local removing = makeSignal()
		local opened = {}
		-- Tirage des caisses (#393) : valeur dans [0, 100) rendue par le faux `Random` de CrateService
		local rolls = { value = 0 }
		-- Joueurs présents sur ce serveur (Players:GetPlayerByUserId, reçus Robux de #395)
		local present = {}
		-- Réponse du faux PolicyService (#395) : `restricted` par UserId, `fail` fait échouer l'appel ; `calls` compte
		local policy = { restricted = {}, fail = false, calls = 0, latency = 0 }
		local services = {
			PolicyService = {
				GetPolicyInfoForPlayerAsync = function(_, player)
					policy.calls += 1
					if policy.latency > 0 then
						sched.task.wait(policy.latency)
					end
					if policy.fail then
						error("PolicyService indisponible (simulé)")
					end
					return { ArePaidRandomItemsRestricted = policy.restricted[player.UserId] == true }
				end,
			},
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
			Players = {
				PlayerRemoving = removing,
				PlayerAdded = makeSignal(),
				GetPlayerByUserId = function(_, userId: number)
					return present[userId]
				end,
			},
			RunService = {
				IsStudio = function()
					return studio
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
			print = function(...)
				local parts = {}
				for _, v in { ... } do
					table.insert(parts, tostring(v))
				end
				table.insert(logs, table.concat(parts, " "))
			end,
			Random = {
				new = function()
					return {
						NextNumber = function()
							return rolls.value
						end,
					}
				end,
			},
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
			logs = logs,
			opened = opened,
			rolls = rolls,
			policy = policy,
			Inventory = loader:require("src/server/InventoryStore"),
			Wallet = loader:require("src/server/WalletStore"),
			-- Chargé ici, hors coroutine : la lecture d'un module par Lune cède la main à son propre ordonnanceur, qu'une
			-- coroutine reprise par l'horloge simulée n'attend pas
			Crates = loader:require("src/server/CrateService"),
			Receipts = loader:require("src/server/ReceiptService"),
			Policy = loader:require("src/server/PaidRandomPolicy"),
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
			-- Cette méthode permet de simuler le signal d'un attribut lorsque InventoryStore suit DebugInventory (Studio).
			function player.GetAttributeChangedSignal(_self, _name: string)
				return makeSignal()
			end
			present[userId] = player
			server.Inventory.setup(player)
			sched.task.spawn(server.Inventory.load, player)
			return player
		end
		-- Cette méthode permet de faire traiter un reçu Robux (#395) dans sa propre coroutine (il attend le chargement et
		-- l'écriture) lorsqu'un test le demande ; renvoie un état rempli à la fin (`done`, `verdict`, `why`).
		function server.receipt(userId: number, productId: number, purchaseId: string)
			local state = { done = false, verdict = nil, why = nil }
			sched.task.spawn(function()
				state.verdict, state.why, state.extra = server.Receipts.handle({
					PlayerId = userId,
					ProductId = productId,
					PurchaseId = purchaseId,
				})
				state.done = true
			end)
			return state
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
				state.at = sched.now
			end)
			return state
		end
		-- Cette méthode permet de lancer un achat de caisse (#393, CrateService chargé sur ce serveur) dans sa propre
		-- coroutine lorsqu'un test le demande ; renvoie un état rempli à la fin (`done`, `reply`).
		function server.buy(player, crateId: string, roll: number?)
			rolls.value = roll or 0
			local state = { done = false, reply = nil }
			sched.task.spawn(function()
				state.reply = server.Crates.buy(player, crateId)
				state.done = true
			end)
			return state
		end
		-- Cette méthode permet d'ouvrir une caisse gratuitement (test, #332) lorsqu'un test compare avec l'achat.
		function server.open(player, crateId: string, roll: number?)
			rolls.value = roll or 0
			return server.Crates.open(player, crateId)
		end
		-- Cette méthode permet de faire partir un joueur lorsqu'un test simule sa déconnexion.
		function server.leave(player)
			player.Parent = nil
			present[player.UserId] = nil
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
				state.at = sched.now
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
					items = { "skin.awp.balise", "weapon.m9bayonet" },
					equipped = { knife = { weapon = "weapon.m9bayonet" } },
				}
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				T.expectEqual(server.Wallet.balance(alice), Wallet.STARTING_BALANCE)
				T.expect(server.Wallet.add(alice, 25))
				sched.advance(10)
				local record = ds.data["1"]
				T.expectEqual(record.schemaVersion, 2)
				T.expectEqual(table.concat(record.items, ","), "skin.awp.balise,weapon.m9bayonet")
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

		T.it(
			"six écritures en échec d'affilée : retenté toutes les 120 s (FAILED_SAVE_INTERVAL), gains écrits à la reprise (#408)",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.Wallet.add(alice, 60)
				ds.failures = 18 -- six écritures de trois essais
				-- Échecs à 12, 78, 144, 210 et 276 s (un nouvel essai 60 s après chacun), puis un essai toutes les 120 s
				sched.advance(300)
				-- Un gain pendant la panne n'avance pas le nouvel essai (prévu à 396 s)
				server.Wallet.add(alice, 20)
				sched.advance(90)
				T.expectEqual(ds.failures, 3, "après 5 échecs : pas de nouvel essai avant 120 s")
				sched.advance(120)
				T.expectEqual(ds.failures, 0, "sixième écriture tentée malgré les 5 échecs")
				T.expectEqual(ds.writes, 0)
				T.expectEqual(server.Wallet.balance(alice), 80, "gains gardés en mémoire")
				sched.advance(130)
				T.expectEqual(storedBalance(ds, 1), 80, "gains écrits à la reprise")
				T.expectEqual(ds.writes, 1)
			end
		)

		T.it(
			"gain arrivé pendant une écriture qui échoue : le nouvel essai attend quand même 60 s (#408)",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.Wallet.add(alice, 10)
				ds.failures = 3
				ds.latency = 1
				local started = #ds.requests
				-- Écriture à 6 s : essais à 6, 9 et 14 s, échec à 15 s ; gain à 8 s, pendant l'écriture
				sched.advance(8)
				server.Wallet.add(alice, 5)
				sched.advance(62)
				T.expectEqual(#ds.requests - started, 3, "pas de nouvel essai 6 s après l'échec")
				sched.advance(20)
				T.expectEqual(storedBalance(ds, 1), 15, "écrit 60 s après l'échec")
			end
		)

		T.it(
			"objet donné pendant une panne : écrit avec le prochain essai, sans en lancer un de plus (#408)",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.Wallet.add(alice, 10)
				ds.failures = 3
				-- Écriture à 6 s, échec à 12 s, nouvel essai prévu à 72 s
				sched.advance(20)
				local started = #ds.requests
				T.expect(server.Inventory.grant(alice, "weapon.m9bayonet"), "don accepté")
				sched.advance(40)
				T.expectEqual(#ds.requests, started, "pas d'essai lancé par le don")
				sched.advance(20)
				local record = ds.data["1"]
				T.expect(
					record ~= nil and table.find(record.items, "weapon.m9bayonet") ~= nil,
					"objet écrit au nouvel essai"
				)
				T.expectEqual(storedBalance(ds, 1), 10)
			end
		)

		T.it(
			"joueur parti, DataStore en panne : abandonné après MAX_SAVE_FAILURES échecs depuis son départ (#408)",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.Wallet.add(alice, 40)
				ds.failures = math.huge
				server.leave(alice)
				sched.advance(1000)
				T.expect(hasWarning(server, "sauvegarde abandonnée pour"), "abandon signalé")
				local count = #ds.requests
				sched.advance(1000)
				T.expectEqual(#ds.requests, count, "plus aucun essai après l'abandon")
			end
		)

		T.it(
			"lot renvoyé après les écritures de MAX_WRITE_MARKS - 1 autres sessions : compté une fois (#408)",
			function()
				T.expect(Wallet.MAX_WRITE_MARKS >= 20 and Wallet.MAX_WRITE_MARKS <= 50, "borne entre 20 et 50")
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.Wallet.add(alice, 100)
				ds.commitThenFail = 1
				-- Écrit à 6 s mais signalé en échec ; nouvel essai à 8 s
				sched.advance(7)
				local stored = storedWallet(ds, 1)
				T.expectEqual(stored.earned, 100)
				-- Entre-temps, d'autres sessions (autres serveurs) écrivent la même clé
				for i = 1, Wallet.MAX_WRITE_MARKS - 1 do
					table.insert(stored.writes, { session = "autre" .. i, seq = 1 })
					stored.earned += 1
				end
				sched.advance(20)
				T.expectEqual(storedBalance(ds, 1), 100 + Wallet.MAX_WRITE_MARKS - 1, "lot renvoyé pas recompté")
				T.expectEqual(#storedWallet(ds, 1).writes, Wallet.MAX_WRITE_MARKS)
				T.expectEqual(server.Wallet.balance(alice), 100 + Wallet.MAX_WRITE_MARKS - 1)
			end
		)

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

		T.it(
			"arrêt avec le DataStore en panne : essais espacés, fini avant 30 s, transaction répondue (#408)",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				local bob = server.join(2)
				server.Wallet.add(alice, 50)
				server.Wallet.add(bob, 20)
				ds.failures = math.huge
				ds.latency = 3 -- un essai lancé juste avant closeDeadline finit après : attendu dans la marge
				local started = #ds.requests
				local state = server.close()
				-- Achat ou reçu Robux qui attend son tour derrière la sauvegarde d'arrêt d'alice
				local pending = server.transact(alice, function(record)
					return record, "fait"
				end)
				sched.advance(120)
				T.expect(state.done, "arrêt terminé")
				T.expect(state.at < 30, "arrêt fini en " .. tostring(state.at) .. " s")
				T.expect(pending.done, "transaction répondue")
				T.expectEqual(pending.status, "failed")
				T.expect(pending.at < 30, "transaction répondue en " .. tostring(pending.at) .. " s")
				-- Aucun essai ne part après closeDeadline (25 s), et ils sont espacés : 6 s entre deux écritures en échec
				-- d'un même profil, soit 10 requêtes pour 2 joueurs et la transaction (bob retenté à 21 s, pas à 15 s)
				local count = #ds.requests - started
				for i = started + 1, #ds.requests do
					T.expect(ds.requests[i] < 25, "essai lancé à " .. ds.requests[i] .. " s")
				end
				T.expectEqual(count, 10, "requêtes à l'arrêt")
				T.expect(hasWarning(server, "arrêt du serveur"), "abandon signalé")
			end
		)
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
				table.insert(record.items, "skin.awp.balise")
				return record, "skin.awp.balise"
			end)
			T.expectEqual(state.status, "ok")
			T.expectEqual(state.result, "skin.awp.balise")
			T.expectEqual(ds.writes, 1)
			T.expectEqual(storedBalance(ds, 1), 200)
			T.expectEqual(ds.data["1"].items[1], "skin.awp.balise")
			T.expect(server.Inventory.owned(alice)["skin.awp.balise"], "possédé tout de suite")
			T.expect(string.find(alice.attributes.OwnedItems, "skin.awp.balise", 1, true) ~= nil)
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
				table.insert(record.items, "skin.awp.balise")
				return record, nil
			end)
			T.expectEqual(state.status, "rejected")
			T.expectEqual(state.result, "insufficient")
			T.expectEqual(ds.writes, 0)
			T.expectEqual(storedBalance(ds, 1), before.wallet.earned)
			T.expectEqual(#ds.data["1"].items, 1)
			T.expectEqual(server.Wallet.balance(alice), 50)
			T.expect(not server.Inventory.owned(alice)["skin.awp.balise"])
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
				table.insert(record.items, "skin.awp.balise")
				return record, nil
			end)
			T.expect(server.Inventory.grant(alice, "weapon.m9bayonet"), "don accepté pendant l'écriture")
			sched.advance(2)
			T.expectEqual(state.status, "ok")
			local owned = server.Inventory.owned(alice)
			T.expect(owned["weapon.m9bayonet"], "item donné pendant l'écriture gardé")
			T.expect(owned["skin.awp.balise"], "objet acheté possédé")
			sched.advance(30)
			T.expect(table.find(ds.data["1"].items, "weapon.m9bayonet") ~= nil)
			T.expect(table.find(ds.data["1"].items, "skin.awp.balise") ~= nil)
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
				table.insert(record.items, "skin.awp.balise")
				return record, "achat"
			end)
			T.expectEqual(state.status, "ok")
			T.expectEqual(state.result, "achat")
			T.expectEqual(server.Wallet.balance(alice), 180)
			T.expect(server.Inventory.owned(alice)["skin.awp.balise"])
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
				table.insert(record.items, "skin.awp.balise")
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

	-- Tirages de la caisse AWP série 1 (chances 70 / 25 / 5) : COUCHANT < 70, IMPACT < 95, RELEVÉ au-delà
	local AWP1 = "crate.awp.serie1"
	local ROLL_IMPACT = 80

	-- Cette méthode permet de savoir si un skin est dans les items stockés d'un joueur lorsqu'un test vérifie un achat.
	local function storedHas(ds, userId: number, id: string): boolean
		local record = ds.data[tostring(userId)]
		return record ~= nil and table.find(record.items, id) ~= nil
	end

	T.describe("Achat de caisse (#393, CrateService.buy)", function()
		T.it("achat : débité et skin donné en une écriture, réponse après l'écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 400, 200)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.latency = 1
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expect(not buy.done, "attend l'écriture")
			sched.advance(1)
			T.expect(buy.done)
			T.expectEqual(buy.reply.ok, true)
			T.expectEqual(buy.reply.skinId, "skin.awp.pan")
			T.expectEqual(buy.reply.rarity, "rare")
			T.expectEqual(buy.reply.added, true)
			T.expectEqual(buy.reply.refund, 0)
			T.expectEqual(ds.writes, 1, "une seule écriture")
			T.expectEqual(storedWallet(ds, 1).purchased, 0, "achetés d'abord")
			T.expectEqual(storedWallet(ds, 1).earned, 100)
			T.expect(storedHas(ds, 1, "skin.awp.pan"), "skin écrit avec le débit")
			T.expectEqual(server.Inventory.owned(alice)["skin.awp.pan"], true, "possédé tout de suite")
			T.expectEqual(alice.attributes.Credits, 100)
		end)

		T.it("doublon : remboursé dans `earned` hors plafond du jour, aucun item ajouté", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600, 0, { "skin.awp.pan" })
			ds.data["1"].wallet.day = 20000
			ds.data["1"].wallet.dayEarned = 120
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.ok, true)
			T.expectEqual(buy.reply.added, false)
			T.expectEqual(buy.reply.refund, 200)
			T.expectEqual(storedWallet(ds, 1).earned, 600 - 500 + 200)
			T.expectEqual(storedWallet(ds, 1).dayEarned, 120, "plafond du jour pas touché")
			T.expectEqual(#ds.data["1"].items, 1)
			T.expectEqual(alice.attributes.Credits, 300)
		end)

		T.it("solde stocké insuffisant : refus, rien d'écrit, rien donné", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 499)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.ok, false)
			T.expectEqual(buy.reply.reason, "insufficient")
			T.expectEqual(ds.writes, 0)
			T.expectEqual(storedBalance(ds, 1), 499)
			T.expectEqual(server.Inventory.owned(alice)["skin.awp.pan"], nil)
		end)

		T.it("solde local suffisant mais dépensé sur un autre serveur : refus sur le stocké", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			seed(ds, 1, 100)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.reason, "insufficient")
			T.expectEqual(alice.attributes.Credits, 100, "copie locale recalée")
		end)

		T.it("deux serveurs achètent en même temps avec 600 : un seul passe, solde jamais négatif", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600)
			local serverA = makeServer(sched, ds)
			local serverB = makeServer(sched, ds)
			local onA = serverA.join(1)
			local onB = serverB.join(1)
			ds.latency = 1
			local buyA = serverA.buy(onA, AWP1, 10)
			local buyB = serverB.buy(onB, "crate.awp.serie2", 10)
			sched.advance(5)
			T.expect(buyA.done and buyB.done)
			local passed = (if buyA.reply.ok then 1 else 0) + (if buyB.reply.ok then 1 else 0)
			T.expectEqual(passed, 1)
			local refused = if buyA.reply.ok then buyB.reply else buyA.reply
			T.expectEqual(refused.reason, "insufficient")
			T.expectEqual(storedBalance(ds, 1), 100)
			T.expectEqual(#ds.data["1"].items, 1, "un seul skin")
		end)

		T.it("écriture en échec : `failed`, rien débité, rien donné", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.failures = 4 -- trois essais d'écriture, puis la lecture de vérification
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			sched.advance(10)
			T.expect(buy.done)
			T.expectEqual(buy.reply.ok, false)
			T.expectEqual(buy.reply.reason, "failed")
			T.expectEqual(buy.reply.skinId, nil, "rien de révélé")
			T.expectEqual(storedBalance(ds, 1), 600)
			T.expect(not storedHas(ds, 1, "skin.awp.pan"))
			T.expectEqual(server.Inventory.owned(alice)["skin.awp.pan"], nil)
			T.expectEqual(alice.attributes.Credits, 600)
		end)

		T.it("écrit mais réponse perdue (rejeu) : débité une fois, réponse juste, skin neuf", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.commitThenFail = 1
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			sched.advance(10)
			T.expect(buy.done)
			T.expectEqual(buy.reply.ok, true)
			T.expectEqual(buy.reply.added, true)
			T.expectEqual(buy.reply.refund, 0)
			-- Le nouvel essai trouve la marque de l'achat : il réécrit la fusion sans réappliquer l'opération
			T.expectEqual(storedBalance(ds, 1), 100, "débité une seule fois")
			T.expectEqual(#ds.data["1"].items, 1)
			T.expectEqual(server.Inventory.owned(alice)["skin.awp.pan"], true)
		end)

		T.it("rejeu d'un doublon : remboursé une fois, réponse « doublon »", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600, 0, { "skin.awp.pan" })
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.commitThenFail = 1
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			sched.advance(10)
			T.expectEqual(buy.reply.ok, true)
			T.expectEqual(buy.reply.added, false)
			T.expectEqual(buy.reply.refund, 200)
			T.expectEqual(storedBalance(ds, 1), 300)
		end)

		T.it("double clic : le second achat est refusé `busy` sans rien faire", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 2000)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.latency = 1
			local first = server.buy(alice, AWP1, ROLL_IMPACT)
			local second = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expect(second.done, "refusé tout de suite")
			T.expectEqual(second.reply.reason, "busy")
			sched.advance(2)
			T.expectEqual(first.reply.ok, true)
			T.expectEqual(storedBalance(ds, 1), 1500, "un seul débit")
			-- Le tour est rendu : un achat suivant passe
			local third = server.buy(alice, AWP1, 10)
			sched.advance(2)
			T.expectEqual(third.reply.ok, true)
			T.expectEqual(storedBalance(ds, 1), 1000)
		end)

		T.it("tout le contenu déjà possédé : refus `owned` avant tout tirage, rien d'écrit", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600, 0, { "skin.awp.balise", "skin.awp.pan", "skin.awp.orage" })
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.reason, "owned")
			T.expectEqual(ds.writes, 0)
			T.expectEqual(storedBalance(ds, 1), 600)
			T.expectEqual(server.buy(alice, "crate.m9.serie1", 10).reply.ok, true, "l'autre arme reste en vente")
		end)

		T.it("inventaire pas chargé, caisse inconnue : refus sans écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600)
			ds.latency = 5
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local early = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(early.reply.reason, "loading")
			sched.advance(5)
			local unknown = server.buy(alice, "crate.inconnue", ROLL_IMPACT)
			T.expectEqual(unknown.reply.reason, "unknown")
			T.expectEqual(ds.writes, 0)
		end)

		T.it("format stocké refusé (schéma plus récent) : refus `loading`", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.data["1"] = { schemaVersion = 99, items = {}, wallet = { earned = 600, purchased = 0 } }
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.reason, "loading")
			T.expectEqual(ds.data["1"].schemaVersion, 99, "rien de réécrit")
		end)

		T.it("ouverture de test (Studio) : gratuite, ni débit ni remboursement, distincte de l'achat", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 600, 0, { "skin.awp.pan" })
			local server = makeServer(sched, ds, { studio = true })
			local alice = server.join(1)
			local opened = server.open(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(opened.ok, true)
			T.expectEqual(opened.added, false, "doublon : rien de plus")
			T.expectEqual(opened.refund, nil, "pas de remboursement")
			sched.advance(600)
			T.expectEqual(storedBalance(ds, 1), 600, "pas de débit")
		end)

		T.it("ouverture de test refusée hors Studio pour un joueur ordinaire", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(server.open(alice, AWP1, ROLL_IMPACT).reason, "forbidden")
		end)

		T.it("Studio sans accès aux API : achat appliqué au solde de session, jamais écrit", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3 -- lecture du chargement en échec (trois essais)
			local server = makeServer(sched, ds, { studio = true })
			local alice = server.join(1)
			sched.advance(10)
			alice.attributes.DebugCredits = 700
			server.Wallet.applyDebug(alice)
			T.expectEqual(alice.attributes.Credits, 700)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.ok, true)
			T.expectEqual(alice.attributes.Credits, 200)
			T.expectEqual(server.Inventory.owned(alice)["skin.awp.pan"], true)
			T.expectEqual(ds.writes, 0, "jamais écrit")
		end)
	end)

	T.describe("WalletStore : gains en jouant et plafond du jour (#394)", function()
		local DAY = 20407

		-- Cette méthode permet de fixer l'heure UTC (os.time) vue par le serveur lorsqu'un test simule un jour donné.
		local function at(sched, day: number, seconds: number?)
			sched.os.time = function()
				return day * 86400 + (seconds or 3600)
			end
		end

		T.it("plafonne au jour vu par la session, publie les gains du jour et les écrit", function()
			local sched = makeScheduler()
			at(sched, DAY)
			local ds = makeDataStore(sched)
			seed(ds, 1, 100)
			ds.data["1"].wallet.day = DAY
			ds.data["1"].wallet.dayEarned = 230
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(alice.attributes.DailyCredits, DAY .. ":230")
			T.expectEqual(server.Wallet.addPlayGain(alice, 15, DAY), 15)
			T.expectEqual(server.Wallet.addPlayGain(alice, 15, DAY), 5, "plafond du jour")
			T.expectEqual(server.Wallet.addPlayGain(alice, 15, DAY), 0)
			T.expectEqual(alice.attributes.DailyCredits, DAY .. ":250")
			T.expectEqual(alice.attributes.Credits, 120)
			sched.advance(10)
			local stored = storedWallet(ds, 1)
			T.expectEqual(stored.earned, 120)
			T.expectEqual(stored.dayEarned, 250)
			T.expectEqual(stored.day, DAY)
		end)

		T.it("pas chargé ou sauvegarde coupée : nil, rien de crédité", function()
			local sched = makeScheduler()
			at(sched, DAY)
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			sched.advance(10)
			T.expectEqual(server.Wallet.addPlayGain(alice, 15, DAY), nil)
			T.expectEqual(alice.attributes.DailyCredits, nil)
			server.leave(alice)
			sched.advance(600)
			T.expectEqual(ds.writes, 0)
		end)

		T.it("minuit UTC entre deux gains : deux lots, chacun compté dans son jour", function()
			local sched = makeScheduler()
			at(sched, DAY, 86398)
			local ds = makeDataStore(sched)
			seed(ds, 1, 0)
			ds.data["1"].wallet.day = DAY
			ds.data["1"].wallet.dayEarned = 240
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			T.expectEqual(server.Wallet.addPlayGain(alice, 15, DAY), 10)
			at(sched, DAY + 1, 2)
			T.expectEqual(server.Wallet.addPlayGain(alice, 15, DAY + 1), 15, "nouveau jour : compteur à zéro")
			T.expectEqual(alice.attributes.DailyCredits, (DAY + 1) .. ":15")
			sched.advance(10)
			local stored = storedWallet(ds, 1)
			T.expectEqual(stored.earned, 25)
			T.expectEqual(stored.day, DAY + 1)
			T.expectEqual(stored.dayEarned, 15)
		end)

		T.it("deux serveurs en même temps : le plafond du jour stocké n'est pas dépassé", function()
			local sched = makeScheduler()
			at(sched, DAY)
			local ds = makeDataStore(sched)
			seed(ds, 1, 0)
			ds.data["1"].wallet.day = DAY
			ds.data["1"].wallet.dayEarned = 200
			local one = makeServer(sched, ds)
			local two = makeServer(sched, ds)
			local onOne = one.join(1)
			local onTwo = two.join(1)
			T.expectEqual(one.Wallet.addPlayGain(onOne, 40, DAY), 40)
			T.expectEqual(two.Wallet.addPlayGain(onTwo, 40, DAY), 40, "chacun ne voit que ses gains")
			sched.advance(10)
			local stored = storedWallet(ds, 1)
			T.expectEqual(stored.dayEarned, 250)
			T.expectEqual(stored.earned, 50, "40 + 10 seulement")
			-- Chaque serveur recale sa copie sur le stocké après son écriture
			one.Wallet.add(onOne, 1)
			sched.advance(10)
			T.expectEqual(onOne.attributes.DailyCredits, DAY .. ":250")
		end)
	end)

	local Packs = Loader.new({}):require("src/shared/CreditPacks")
	local PACK = Packs.PACKS[1] -- 500 crédits

	-- Cette méthode permet de savoir si un PurchaseId est inscrit dans le portefeuille stocké lorsqu'un test le vérifie.
	local function storedReceipt(ds, userId: number, purchaseId: string): boolean
		local w = storedWallet(ds, userId)
		return w ~= nil and table.find(w.receipts, purchaseId) ~= nil
	end

	T.describe("Reçus Robux (#395, ReceiptService.handle)", function()
		T.it("accordé : crédits dans `purchased` et PurchaseId inscrits dans la même écriture", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 40)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			ds.latency = 1
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			T.expect(not receipt.done, "attend l'écriture")
			sched.advance(1)
			T.expectEqual(receipt.verdict, "granted")
			T.expectEqual(ds.writes, 1, "une seule écriture")
			T.expectEqual(storedWallet(ds, 1).purchased, 500)
			T.expectEqual(storedWallet(ds, 1).earned, 40)
			T.expect(storedReceipt(ds, 1, "achat-1"), "PurchaseId écrit avec les crédits")
			T.expectEqual(alice.attributes.Credits, 540)
		end)

		T.it("même reçu rejoué : accordé sans rien ajouter ni écrire", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			server.join(1)
			T.expectEqual(server.receipt(1, PACK.productId, "achat-1").verdict, "granted")
			local again = server.receipt(1, PACK.productId, "achat-1")
			T.expectEqual(again.verdict, "granted")
			T.expect(string.find(again.why, "déjà traité", 1, true) ~= nil)
			T.expectEqual(storedWallet(ds, 1).purchased, 500, "crédité une seule fois")
			T.expectEqual(ds.writes, 1)
		end)

		T.it("écriture passée mais signalée en échec : accordé, crédité une seule fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			server.join(1)
			ds.commitThenFail = 1
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(10)
			T.expectEqual(receipt.verdict, "granted")
			T.expectEqual(storedWallet(ds, 1).purchased, 500)
			T.expectEqual(#storedWallet(ds, 1).receipts, 1)
		end)

		T.it("écriture en échec : NotProcessedYet, rien ajouté ; rejoué plus tard : accordé une fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 0)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			-- Trois transactions de trois essais, plus la lecture de vérification de chacune
			ds.failures = 12
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(40)
			T.expect(receipt.done)
			T.expectEqual(receipt.verdict, "retry")
			T.expectEqual(storedWallet(ds, 1).purchased, 0)
			T.expect(not storedReceipt(ds, 1, "achat-1"))
			T.expectEqual(alice.attributes.Credits, 0)
			-- Roblox rejoue le reçu (nouvel achat, reconnexion)
			local replay = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(10)
			T.expectEqual(replay.verdict, "granted")
			T.expectEqual(storedWallet(ds, 1).purchased, 500)
		end)

		T.it("une écriture en échec puis réussie au tour suivant : accordé, crédité une fois", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			server.join(1)
			ds.failures = 4 -- la première transaction échoue (trois essais et la vérification)
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(30)
			T.expectEqual(receipt.verdict, "granted")
			T.expectEqual(storedWallet(ds, 1).purchased, 500)
		end)

		T.it("joueur absent du serveur : NotProcessedYet, rien écrit", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local receipt = server.receipt(2, PACK.productId, "achat-1")
			T.expectEqual(receipt.verdict, "retry")
			T.expect(string.find(receipt.why, "absent", 1, true) ~= nil)
			T.expectEqual(ds.writes, 0)
		end)

		T.it("joueur parti pendant le chargement : NotProcessedYet", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.latency = 5
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(1)
			server.leave(alice)
			sched.advance(20)
			T.expectEqual(receipt.verdict, "retry")
			T.expect(not storedReceipt(ds, 1, "achat-1"))
		end)

		T.it("produit inconnu ou PurchaseId invalide : NotProcessedYet, rien écrit", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			server.join(1)
			local unknown = server.receipt(1, 1, "achat-1")
			T.expectEqual(unknown.verdict, "retry")
			T.expect(string.find(unknown.why, "produit inconnu", 1, true) ~= nil)
			T.expectEqual(server.receipt(1, PACK.productId, "").verdict, "retry")
			T.expectEqual(ds.writes, 0)
		end)

		T.it("reçu à la connexion : attend la fin du chargement, puis accordé", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.latency = 3
			local server = makeServer(sched, ds)
			server.join(1)
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(2)
			T.expect(not receipt.done, "chargement pas fini")
			sched.advance(10)
			T.expectEqual(receipt.verdict, "granted")
			T.expectEqual(storedWallet(ds, 1).purchased, 500)
		end)

		T.it("chargement en échec (sauvegarde coupée) : NotProcessedYet, rien écrit", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			ds.failures = 3
			local server = makeServer(sched, ds)
			server.join(1)
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			sched.advance(40)
			T.expectEqual(receipt.verdict, "retry")
			T.expectEqual(ds.writes, 0)
		end)

		T.it(
			"deux serveurs traitent le même reçu en même temps : crédité une seule fois, accordé des deux côtés",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local serverA = makeServer(sched, ds)
				local serverB = makeServer(sched, ds)
				serverA.join(1)
				serverB.join(1)
				ds.latency = 1
				local onA = serverA.receipt(1, PACK.productId, "achat-1")
				local onB = serverB.receipt(1, PACK.productId, "achat-1")
				sched.advance(5)
				T.expectEqual(onA.verdict, "granted")
				T.expectEqual(onB.verdict, "granted")
				T.expectEqual(storedWallet(ds, 1).purchased, 500)
				T.expectEqual(#storedWallet(ds, 1).receipts, 1)
			end
		)

		T.it("deux reçus différents sur deux serveurs : les deux crédités", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local serverA = makeServer(sched, ds)
			local serverB = makeServer(sched, ds)
			serverA.join(1)
			serverB.join(1)
			ds.latency = 1
			serverA.receipt(1, PACK.productId, "achat-1")
			serverB.receipt(1, Packs.PACKS[3].productId, "achat-2")
			sched.advance(5)
			T.expectEqual(storedWallet(ds, 1).purchased, 3500)
		end)

		T.it(
			"joueur restreint : prompt refusé, reçu arrivé quand même accordé et signalé, caisse refusée",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				seed(ds, 1, 600)
				local server = makeServer(sched, ds)
				server.policy.restricted[1] = true
				local alice = server.join(1)
				local reply, pack = server.Receipts.promptFor(alice, PACK.id)
				T.expectEqual(reply.reason, "region")
				T.expectEqual(pack, nil, "pas de prompt")
				T.expectEqual(alice.attributes.PaidRandomRestricted, true, "attribut publié")
				local receipt = server.receipt(1, PACK.productId, "achat-store")
				T.expectEqual(receipt.verdict, "granted", "Robux jamais remboursés : crédits accordés")
				T.expect(string.find(receipt.extra, "restreint", 1, true) ~= nil, "signalé dans le journal")
				local writes = ds.writes
				local buy = server.buy(alice, AWP1, ROLL_IMPACT)
				T.expectEqual(buy.reply.ok, false)
				T.expectEqual(buy.reply.reason, "region")
				T.expectEqual(ds.writes, writes, "rien d'écrit")
				T.expectEqual(storedBalance(ds, 1), 1100, "ni débit ni skin")
			end
		)

		T.it("joueur non restreint (Studio) : prompt accepté pour un pack connu, refusé pour un inconnu", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds, { studio = true })
			local alice = server.join(1)
			local reply, pack = server.Receipts.promptFor(alice, PACK.id)
			T.expectEqual(reply.ok, true)
			T.expectEqual(pack and pack.productId, PACK.productId)
			T.expectEqual(alice.attributes.PaidRandomRestricted, false)
			T.expectEqual(server.Receipts.promptFor(alice, "pack.inconnu").reason, "unknown")
		end)

		T.it("hors Studio avec des ids provisoires : prompt refusé `unavailable`", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local reply, pack = server.Receipts.promptFor(alice, PACK.id)
			T.expectEqual(reply.reason, if Packs.isReady() then nil else "unavailable")
			T.expectEqual(pack ~= nil, Packs.isReady())
		end)

		T.it(
			"chargement en échec (sauvegarde coupée) : prompt refusé `loading`, pas de pack payé pour rien",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				ds.failures = 3
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				sched.advance(40)
				local reply, pack = server.Receipts.promptFor(alice, PACK.id)
				T.expectEqual(reply.reason, "loading")
				T.expectEqual(pack, nil)
			end
		)

		T.it("solde près du plafond : prompt refusé `full` (le reçu resterait en attente)", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, Wallet.MAX_BALANCE - 100)
			local server = makeServer(sched, ds, { studio = true })
			local alice = server.join(1)
			T.expectEqual(server.Receipts.promptFor(alice, PACK.id).reason, "full")
		end)

		T.it("PolicyService en échec à l'arrivée : redemandé d'office, sans nouvel appel du client", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.policy.fail = true
			server.Receipts.promptFor(alice, PACK.id)
			T.expectEqual(alice.attributes.PaidRandomRestricted, true)
			server.policy.fail = false
			sched.advance(31)
			T.expectEqual(alice.attributes.PaidRandomRestricted, false, "attribut rendu sans action du joueur")
			sched.advance(100)
			T.expectEqual(server.policy.calls, 2, "plus redemandé une fois lu")
		end)

		T.it("PolicyService en échec : restreint, réponse gardée 30 s puis redemandée", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 1000)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.policy.fail = true
			T.expectEqual(server.buy(alice, AWP1, ROLL_IMPACT).reply.reason, "region")
			T.expect(hasWarning(server, "PolicyService"), "échec signalé")
			server.policy.fail = false
			T.expectEqual(server.buy(alice, AWP1, ROLL_IMPACT).reply.reason, "region", "pas redemandé tout de suite")
			T.expectEqual(server.policy.calls, 1)
			sched.advance(31)
			T.expectEqual(server.buy(alice, AWP1, ROLL_IMPACT).reply.ok, true)
			-- Réponse lue : gardée pour la session, plus redemandée
			sched.advance(100)
			server.buy(alice, AWP1, 10)
			T.expectEqual(server.policy.calls, 2)
		end)

		T.it("demandes simultanées à PolicyService : un seul appel, la même réponse pour tous", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			server.policy.latency = 1
			local answers = {}
			for i = 1, 3 do
				sched.task.spawn(function()
					answers[i] = server.Policy.isRestricted(alice)
				end)
			end
			T.expectEqual(#answers, 0, "tous attendent la réponse")
			sched.advance(1)
			T.expectEqual(server.policy.calls, 1)
			T.expectEqual(answers[1], false)
			T.expectEqual(answers[2], false)
			T.expectEqual(answers[3], false)
		end)

		T.it(
			"PolicyService en échec : le reçu n'est pas noté « restreint », un seul avertissement par série",
			function()
				local sched = makeScheduler()
				local ds = makeDataStore(sched)
				local server = makeServer(sched, ds)
				local alice = server.join(1)
				server.policy.fail = true
				server.Receipts.promptFor(alice, PACK.id)
				sched.advance(95) -- trois nouveaux essais en échec
				local receipt = server.receipt(1, PACK.productId, "achat-1")
				T.expectEqual(receipt.verdict, "granted")
				T.expect(string.find(receipt.extra, "restreint", 1, true) == nil, "échec ≠ restreint par Roblox")
				local count = 0
				for _, line in server.warnings do
					if string.find(line, "PolicyService", 1, true) then
						count += 1
					end
				end
				T.expectEqual(count, 1)
				T.expect(server.policy.calls >= 4, "redemandé toutes les 30 s")
			end
		)

		T.it("reçu d'un joueur dont la restriction n'est pas connue : n'attend pas PolicyService", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			local server = makeServer(sched, ds)
			server.join(1)
			server.policy.latency = 10
			local receipt = server.receipt(1, PACK.productId, "achat-1")
			T.expect(receipt.done, "accordé sans attendre")
			T.expectEqual(receipt.verdict, "granted")
			T.expectEqual(server.policy.calls, 0)
		end)

		T.it("doublon d'une caisse payée en crédits achetés : remboursé dans `purchased`", function()
			local sched = makeScheduler()
			local ds = makeDataStore(sched)
			seed(ds, 1, 0, 600, { "skin.awp.pan" })
			local server = makeServer(sched, ds)
			local alice = server.join(1)
			local buy = server.buy(alice, AWP1, ROLL_IMPACT)
			T.expectEqual(buy.reply.refund, 200)
			T.expectEqual(storedWallet(ds, 1).purchased, 300)
			T.expectEqual(storedWallet(ds, 1).earned, 0)
		end)
	end)
end

-- Analytics (#527) avec un AnalyticsService simulé (appels enregistrés) et une horloge simulée : funnels d'onboarding
-- (nouveau joueur seulement, étapes en attente jusqu'à l'ancienneté connue), de session, du shop et des packs Robux,
-- économie des crédits, départ et blocages (temps par écran, série de morts, zone de la map), rien sans service
-- (Studio), règles pures (classes, zones, endroit).
return function(T, Loader)
	local Rules = Loader.new({}):require("src/shared/AnalyticsRules")
	local S = Rules.Screen

	-- Cette méthode permet de simuler AnalyticsService lorsqu'un test démarre : chaque appel est enregistré avec sa
	-- méthode et ses arguments (le Player en premier).
	local function fakeService()
		local service = { calls = {} }
		for _, method in { "LogOnboardingFunnelStepEvent", "LogFunnelStepEvent", "LogEconomyEvent", "LogCustomEvent" } do
			service[method] = function(self, ...)
				table.insert(self.calls, { method = method, args = table.pack(...) })
			end
		end
		return service
	end

	-- Cette méthode permet de monter le module sur le faux service lorsqu'un test démarre ; `opts.training`,
	-- `opts.noService` (Studio : rien n'est envoyé, seulement écrit).
	local function setup(opts: { training: boolean?, noService: boolean? }?)
		local options = opts or {}
		local Analytics = Loader.new({}):require("src/server/analytics/Analytics")
		local env = { clock = 0, guids = 0, logs = {}, service = fakeService() }
		Analytics.init({
			service = if options.noService then nil else env.service,
			flow = { source = "Source", sink = "Sink" },
			log = function(line: string)
				table.insert(env.logs, line)
			end,
			clock = function()
				return env.clock
			end,
			guid = function()
				env.guids += 1
				return "id" .. env.guids
			end,
			training = options.training == true,
		})
		env.Analytics = Analytics
		return env
	end

	-- Cette méthode permet de lister les appels d'une méthode du faux service lorsqu'un test les vérifie.
	local function callsOf(env, method: string)
		local found = {}
		for _, call in env.service.calls do
			if call.method == method then
				table.insert(found, call.args)
			end
		end
		return found
	end

	-- Cette méthode permet de lister les numéros d'étape d'un funnel envoyés lorsqu'un test vérifie un parcours.
	local function stepsOf(env, funnel: string?)
		local steps = {}
		if funnel == nil then
			for _, args in callsOf(env, "LogOnboardingFunnelStepEvent") do
				table.insert(steps, args[2])
			end
			return steps
		end
		for _, args in callsOf(env, "LogFunnelStepEvent") do
			if args[2] == funnel then
				table.insert(steps, args[4])
			end
		end
		return steps
	end

	-- Cette méthode permet de lister les événements personnalisés d'un nom lorsqu'un test les vérifie.
	local function eventsOf(env, name: string)
		local found = {}
		for _, args in callsOf(env, "LogCustomEvent") do
			if args[2] == name then
				table.insert(found, { value = args[3], fields = args[4] or {} })
			end
		end
		return found
	end

	-- Cette méthode permet de comparer une liste de nombres lorsqu'un test vérifie un ordre d'étapes.
	local function expectList(actual: { any }, expected: { any }, message: string)
		T.expectEqual(table.concat(actual, ","), table.concat(expected, ","), message)
	end

	T.describe("Analytics : funnel de session", function()
		T.it("suit une visite de l'arrivée au départ, chaque étape une fois", function()
			local env = setup()
			local A = env.Analytics
			local alice = { Name = "Alice" }
			A.playerAdded(alice)
			A.screen(alice, S.LOADING)
			A.screen(alice, S.HOME)
			A.screen(alice, S.SHOP)
			A.screen(alice, S.HOME)
			A.screen(alice, S.PLAYING)
			A.spawned(alice)
			A.spawned(alice)
			for _ = 1, 3 do
				A.roundEnd(alice)
				A.spawned(alice)
			end
			A.leftRound(alice)
			A.screen(alice, S.HOME)
			A.playerRemoving(alice)
			expectList(stepsOf(env, Rules.SESSION_FUNNEL), { 1, 2, 3, 4, 5, 6, 7 }, "étapes de la session")
			local ids = {}
			for _, args in callsOf(env, "LogFunnelStepEvent") do
				if args[2] == Rules.SESSION_FUNNEL then
					ids[args[3]] = true
				end
			end
			T.expectEqual(ids.id1, true, "un seul funnelSessionId pour la visite")
		end)

		T.it("ouvre une nouvelle visite à chaque arrivée", function()
			local env = setup()
			local bob = { Name = "Bob" }
			env.Analytics.playerAdded(bob)
			env.Analytics.playerRemoving(bob)
			env.Analytics.playerAdded(bob)
			local ids = {}
			for _, args in callsOf(env, "LogFunnelStepEvent") do
				if args[4] == Rules.Session.ARRIVAL.step then
					table.insert(ids, args[3])
				end
			end
			T.expectEqual(#ids, 2)
			T.expect(ids[1] ~= ids[2], "deux visites, deux identifiants")
		end)
	end)

	T.describe("Analytics : funnel d'onboarding", function()
		T.it("garde les étapes en attente puis les envoie dans l'ordre pour un nouveau joueur", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "Nouveau" }
			A.playerAdded(p)
			A.screen(p, S.LOADING)
			A.screen(p, S.HOME)
			expectList(stepsOf(env), {}, "rien avant l'ancienneté connue")
			A.setNewcomer(p, true)
			expectList(stepsOf(env), { 1, 2 }, "chargement et menu envoyés")
			A.screen(p, S.PLAYING)
			A.spawned(p)
			A.shot(p)
			A.shot(p)
			A.damage(p)
			A.death(nil, p, "joueur", "A1")
			A.death(p, nil, "chute", "B2")
			A.roundEnd(p)
			A.screen(p, S.PLAYING)
			A.spawned(p)
			expectList(stepsOf(env), { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, "parcours complet, chaque étape une fois")
			T.expectEqual(callsOf(env, "LogOnboardingFunnelStepEvent")[3][3], "Clic sur JOUER", "nom de l'étape")
		end)

		T.it("n'envoie rien pour un habitué ni pour une ancienneté inconnue", function()
			-- Enveloppé : une liste ne peut pas porter nil
			for _, case in { { isNew = false }, { isNew = nil } } do
				local isNew = case.isNew
				local env = setup()
				local A = env.Analytics
				local p = { Name = "Habitue" }
				A.playerAdded(p)
				A.screen(p, S.HOME)
				A.setNewcomer(p, isNew)
				A.screen(p, S.PLAYING)
				A.spawned(p)
				expectList(stepsOf(env), {}, "aucune étape d'onboarding (" .. tostring(isNew) .. ")")
				A.playerRemoving(p)
				local label = eventsOf(env, Rules.Event.DEPARTURE)[1].fields[Rules.Field.THREE]
				T.expectEqual(label, if isNew == nil then "inconnu" else "habitue", "ancienneté au départ")
			end
		end)

		T.it("ne compte pas l'enchaînement des manches comme un clic sur JOUER", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.setNewcomer(p, true)
			A.screen(p, S.LOADING)
			A.screen(p, S.PLAYING)
			expectList(stepsOf(env), { 1 }, "arrivée directe en partie (entraînement) : pas de clic")
		end)

		T.it("n'envoie rien sur un serveur d'entraînement", function()
			local env = setup({ training = true })
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.setNewcomer(p, true)
			A.screen(p, S.HOME)
			A.screen(p, S.PLAYING)
			A.spawned(p)
			A.death(p, nil, "chute", "A1")
			expectList(stepsOf(env), {}, "pas d'onboarding")
			T.expectEqual(#eventsOf(env, Rules.Event.DEATH), 0, "pas de mort comptée")
			T.expect(#stepsOf(env, Rules.SESSION_FUNNEL) > 0, "la session reste suivie")
		end)
	end)

	T.describe("Analytics : shop et packs Robux", function()
		T.it("suit une visite du shop jusqu'au skin équipé, avec les crédits dépensés et remboursés", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "Acheteur" }
			A.playerAdded(p)
			A.screen(p, S.HOME)
			A.screen(p, S.SHOP)
			A.screen(p, S.SHOP_DETAIL)
			A.screen(p, S.CRATE_OPENING)
			local result = { ok = true, skinId = "skin.awp.x", rarity = "rare", added = false, refund = 100 }
			A.crateBought(p, "crate.awp.serie1", result, 500, 1600)
			A.screen(p, S.SHOP_DETAIL)
			A.screen(p, S.HOME)
			A.equipped(p, "skin.autre")
			A.equipped(p, "skin.awp.x")
			A.equipped(p, "skin.awp.x")
			expectList(stepsOf(env, Rules.SHOP_FUNNEL), { 1, 2, 3, 4, 5 }, "étapes du shop")
			local shopIds = {}
			for _, args in callsOf(env, "LogFunnelStepEvent") do
				if args[2] == Rules.SHOP_FUNNEL then
					shopIds[args[3]] = true
				end
			end
			local count = 0
			for _ in shopIds do
				count += 1
			end
			T.expectEqual(count, 1, "une seule visite (ouverture et retour au détail compris)")
			local eco = callsOf(env, "LogEconomyEvent")
			T.expectEqual(#eco, 2, "dépense puis remboursement")
			T.expectEqual(eco[1][2], "Sink")
			T.expectEqual(eco[1][3], Rules.CURRENCY)
			T.expectEqual(eco[1][4], 500, "prix")
			T.expectEqual(eco[1][5], 1500, "solde après la dépense, avant le remboursement")
			T.expectEqual(eco[1][6], Rules.Transaction.SHOP)
			T.expectEqual(eco[1][7], "crate.awp.serie1")
			T.expectEqual(eco[2][2], "Source")
			T.expectEqual(eco[2][4], 100, "remboursement du doublon")
			T.expectEqual(eco[2][5], 1600, "solde final")
		end)

		T.it("compte la demande refusée à ACHETER sans ouverture ni crédits", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "Pauvre" }
			A.playerAdded(p)
			A.screen(p, S.SHOP)
			A.screen(p, S.SHOP_DETAIL)
			A.crateBought(p, "crate.awp.serie1", { ok = false, reason = "insufficient" }, 500, 20)
			expectList(stepsOf(env, Rules.SHOP_FUNNEL), { 1, 2, 3 }, "pas de caisse ouverte")
			T.expectEqual(#callsOf(env, "LogEconomyEvent"), 0, "rien dépensé")
		end)

		T.it("ouvre une nouvelle visite en revenant au shop depuis un autre onglet", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.screen(p, S.SHOP)
			A.screen(p, S.HOME)
			A.screen(p, S.SHOP)
			expectList(stepsOf(env, Rules.SHOP_FUNNEL), { 1, 1 }, "deux visites")
		end)

		T.it("suit les packs Robux et compte les crédits achetés", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.screen(p, S.SHOP)
			A.screen(p, S.CREDIT_PACKS)
			A.packPrompted(p, "pack.500")
			A.packCredited(p, "pack.500", 500, 700)
			expectList(stepsOf(env, Rules.PACK_FUNNEL), { 1, 2, 3 }, "étapes des packs")
			local eco = callsOf(env, "LogEconomyEvent")
			T.expectEqual(#eco, 1)
			T.expectEqual(eco[1][2], "Source")
			T.expectEqual(eco[1][4], 500)
			T.expectEqual(eco[1][5], 700)
			T.expectEqual(eco[1][6], Rules.Transaction.IAP)
			T.expectEqual(eco[1][7], "pack.500")
		end)

		T.it("compte les gains en jouant, jamais un gain nul", function()
			local env = setup()
			local p = { Name = "P" }
			env.Analytics.playerAdded(p)
			env.Analytics.playGain(p, 5, 105)
			env.Analytics.playGain(p, 0, 105)
			local eco = callsOf(env, "LogEconomyEvent")
			T.expectEqual(#eco, 1)
			T.expectEqual(eco[1][6], Rules.Transaction.GAMEPLAY)
			T.expectEqual(eco[1][7], Rules.PLAY_GAIN_SKU)
		end)
	end)

	T.describe("Analytics : départs et blocages", function()
		T.it("donne au départ l'endroit, la durée, les manches jouées et l'ancienneté", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.setNewcomer(p, true)
			A.screen(p, S.HOME)
			A.screen(p, S.PLAYING)
			A.spawned(p)
			A.roundEnd(p)
			A.spawned(p)
			A.death(p, nil, "chute", "C3")
			env.clock = 312.4
			A.playerRemoving(p)
			local departure = eventsOf(env, Rules.Event.DEPARTURE)
			T.expectEqual(#departure, 1)
			T.expectEqual(departure[1].value, 312, "durée de la session (s)")
			T.expectEqual(departure[1].fields[Rules.Field.ONE], "partie_mort")
			T.expectEqual(departure[1].fields[Rules.Field.TWO], "1")
			T.expectEqual(departure[1].fields[Rules.Field.THREE], "nouveau")
		end)

		T.it("donne l'écran du menu ouvert au départ", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.screen(p, S.SHOP_DETAIL)
			A.playerRemoving(p)
			T.expectEqual(eventsOf(env, Rules.Event.DEPARTURE)[1].fields[Rules.Field.ONE], S.SHOP_DETAIL)
		end)

		T.it("envoie le temps passé sur un écran quitté, au-delà du minimum", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			A.screen(p, S.HOME)
			env.clock = 1
			A.screen(p, S.SHOP)
			env.clock = 31
			A.screen(p, S.HOME)
			local times = eventsOf(env, Rules.Event.SCREEN_TIME)
			T.expectEqual(#times, 1, "passage d'une seconde ignoré")
			T.expectEqual(times[1].value, 30)
			T.expectEqual(times[1].fields[Rules.Field.ONE], S.SHOP)
		end)

		T.it("mesure le temps du menu avant le premier clic sur JOUER, une fois", function()
			local env = setup()
			local A = env.Analytics
			local p = { Name = "P" }
			A.playerAdded(p)
			env.clock = 4
			A.screen(p, S.HOME)
			env.clock = 49
			A.screen(p, S.PLAYING)
			A.leftRound(p)
			A.screen(p, S.HOME)
			A.screen(p, S.PLAYING)
			local waits = eventsOf(env, Rules.Event.MENU_BEFORE_PLAY)
			T.expectEqual(#waits, 1)
			T.expectEqual(waits[1].value, 45)
			T.expectEqual(waits[1].fields[Rules.Field.ONE], "inconnu", "ancienneté pas encore connue")
		end)

		T.it("signale les séries de morts sans kill aux paliers et les remet à zéro sur un kill", function()
			local env = setup()
			local A = env.Analytics
			local victim, other = { Name = "V" }, { Name = "O" }
			A.playerAdded(victim)
			A.playerAdded(other)
			for _ = 1, 5 do
				A.death(victim, other, "joueur", "A1")
			end
			A.death(other, victim, "joueur", "A1")
			for _ = 1, 3 do
				A.death(victim, nil, "chute", "D4")
			end
			local values = {}
			for _, e in eventsOf(env, Rules.Event.DEATH_STREAK) do
				table.insert(values, e.value)
			end
			expectList(values, { 3, 5, 3 }, "paliers 3 et 5, puis 3 après le kill")
			local deaths = eventsOf(env, Rules.Event.DEATH)
			T.expectEqual(#deaths, 9, "une mort par victime joueur")
			T.expectEqual(deaths[9].fields[Rules.Field.ONE], "D4")
			T.expectEqual(deaths[9].fields[Rules.Field.TWO], "chute")
		end)
	end)

	T.describe("Analytics : Studio et robustesse", function()
		T.it("n'envoie rien sans service, mais écrit chaque envoi", function()
			local env = setup({ noService = true })
			local p = { Name = "P" }
			env.Analytics.playerAdded(p)
			env.Analytics.screen(p, S.HOME)
			T.expectEqual(#env.service.calls, 0)
			T.expect(#env.logs >= 2, "envois écrits en console")
			T.expect(string.find(env.logs[1], "Session", 1, true) ~= nil, env.logs[1])
		end)

		T.it("ignore un joueur inconnu et un écran hors liste", function()
			local env = setup()
			local p = { Name = "P" }
			env.Analytics.screen(p, S.HOME)
			env.Analytics.spawned(p)
			env.Analytics.playerAdded(p)
			env.Analytics.screen(p, "hack")
			T.expectEqual(#env.service.calls, 1, "seulement l'arrivée")
		end)

		T.it("ne laisse pas une erreur du service remonter dans le jeu", function()
			local env = setup()
			env.service.LogFunnelStepEvent = function()
				error("limite atteinte")
			end
			local p = { Name = "P" }
			local ok = pcall(env.Analytics.playerAdded, p)
			T.expect(ok, "playerAdded ne lève pas")
		end)
	end)

	T.describe("AnalyticsRules", function()
		T.it("range les manches jouées en classes bornées", function()
			local got = {}
			for _, n in { 0, 1, 2, 3, 4, 9, 10, 250 } do
				table.insert(got, Rules.roundsBucket(n))
			end
			expectList(got, { "0", "1", "2-3", "2-3", "4-9", "4-9", "10+", "10+" }, "classes")
		end)

		T.it("range une position dans la grille 4 × 4 de la map, bords compris", function()
			local bounds = { minX = 0, minZ = 0, maxX = 400, maxZ = 400 }
			T.expectEqual(Rules.zone(10, 10, bounds), "A1")
			T.expectEqual(Rules.zone(399, 399, bounds), "D4")
			T.expectEqual(Rules.zone(150, 250, bounds), "B3")
			T.expectEqual(Rules.zone(-500, 9000, bounds), "A4", "hors de la boîte : ramené au bord")
			T.expectEqual(Rules.zone(400, 0, bounds), "D1", "bord max")
			T.expectEqual(Rules.zone(10, 10, nil), "?")
		end)

		T.it("décrit l'endroit d'un joueur et la cause d'une mort", function()
			T.expectEqual(Rules.location(nil, "arrivee"), "inconnu")
			T.expectEqual(Rules.location(S.PLAYING, "vivant"), "partie_vivant")
			T.expectEqual(Rules.location(S.SHOP, "vivant"), S.SHOP)
			T.expectEqual(Rules.deathCause(false, false), "chute")
			T.expectEqual(Rules.deathCause(true, true), "bot")
			T.expectEqual(Rules.deathCause(true, false), "joueur")
		end)

		T.it("traduit les pages du menu et reconnaît les écrans du menu et du shop", function()
			T.expectEqual(Rules.menuScreen("shop"), S.SHOP)
			T.expectEqual(Rules.menuScreen("lobby"), S.LOBBY, "lobby de JOUER (#523)")
			T.expect(Rules.isMenu(S.LOBBY), "le lobby est un écran du menu")
			T.expectEqual(Rules.menuScreen("inconnue"), S.HOME)
			T.expect(Rules.isMenu(S.CREDIT_PACKS), "packs : écran du menu")
			T.expect(not Rules.isMenu(S.PLAYING), "partie : pas le menu")
			T.expect(not Rules.isMenu(S.LOADING), "chargement : pas le menu")
			T.expect(Rules.isShop(S.CRATE_OPENING), "ouverture : shop")
			T.expect(not Rules.isShop(S.HOME), "accueil : pas le shop")
			for _, screen in Rules.SCREENS do
				T.expect(#screen <= 40, "écran court : " .. screen)
			end
		end)
	end)
end

-- CreditGains (#394) avec un portefeuille et des horloges simulés : kills crédités tout de suite (joueur +5, bot +1),
-- manche jouée (kill, ou 120 s en vie avec une activité réelle : distance ou action acceptée, #401) et victoire en fin
-- de manche, plafond de manche puis du jour, rien en
-- entraînement, hors manche active ou si le solde ne peut pas changer, attribut RoundCredits du bandeau.
return function(T, Loader)
	local DAY = 20407

	-- Cette méthode permet de simuler un Player (nom, attributs) lorsqu'un test en a besoin.
	local function makePlayer(name: string)
		local player = { Name = name, attributes = {} }
		-- Cette méthode permet de simuler Player:SetAttribute lorsque CreditGains publie les gains de la manche.
		function player.SetAttribute(self, key: string, value: any)
			self.attributes[key] = value
		end
		return player
	end

	-- Cette méthode permet de monter CreditGains sur un faux portefeuille (plafond du jour simulé comme InventoryStore)
	-- lorsqu'un test démarre ; `opts.training`, `opts.blocked` (joueurs dont le solde ne peut pas changer).
	local function setup(opts: { training: boolean?, blocked: { any }? }?)
		local options = opts or {}
		local Economy = Loader.new({}):require("src/shared/EconomyRules")
		local Gains = Loader.new({}):require("src/server/CreditGains")
		local env = { active = true, clock = 0, now = DAY * 86400 + 3600, daily = {}, credited = {} }
		-- Cette méthode permet de savoir si le solde d'un joueur peut changer dans ce test.
		local function ready(player)
			return not (options.blocked and table.find(options.blocked, player))
		end
		Gains.init({
			training = options.training == true,
			roundActive = function()
				return env.active
			end,
			credit = function(player, amount, day)
				if not ready(player) then
					return nil
				end
				local key = player.Name .. ":" .. day
				local gain = Economy.capDay(amount, env.daily[key] or 0)
				env.daily[key] = (env.daily[key] or 0) + gain
				if gain > 0 then
					env.credited[player.Name] = (env.credited[player.Name] or 0) + gain
				end
				return gain
			end,
			now = function()
				return env.now
			end,
			clock = function()
				return env.clock
			end,
		})
		env.Gains = Gains
		env.Economy = Economy
		return env
	end

	-- Cette méthode permet de construire une position (seuls X, Y, Z sont lus) lorsqu'un test simule un déplacement.
	local function pos(x: number, z: number, y: number?)
		return { X = x, Y = y or 0, Z = z }
	end

	-- Cette méthode permet de simuler un joueur qui parcourt `distance` studs en ligne droite (pas de 10 studs, comme
	-- des positions acceptées par CharacterSync) lorsqu'un test a besoin d'une activité réelle.
	local function walk(env, player, character, distance: number)
		local x = 0
		while x < distance do
			local step = math.min(10, distance - x)
			env.Gains.onMove(player, character, pos(x, 0), pos(x + step, 0))
			x += step
		end
	end

	local nextId = 0
	-- Cette méthode permet de construire un participant (joueur ou bot) lorsqu'un test simule un kill ou une fin de manche.
	local function participant(player: any?)
		nextId += 1
		return { id = if player then nextId else -nextId, isBot = player == nil, player = player }
	end

	T.describe("CreditGains : kills", function()
		T.it("kill sur un joueur +5, sur un bot +1, crédités tout de suite", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onKill(a, participant(makePlayer("bob")))
			env.Gains.onKill(a, participant(nil))
			T.expectEqual(env.credited.alice, 6)
		end)

		T.it("bot tueur, pas de tueur ou suicide : rien", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onKill(participant(nil), a)
			env.Gains.onKill(nil, a)
			env.Gains.onKill(a, a)
			T.expectEqual(env.credited.alice, nil)
		end)

		T.it("hors manche active ou en entraînement : rien", function()
			local env = setup()
			local alice = makePlayer("alice")
			env.active = false
			env.Gains.onKill(participant(alice), participant(makePlayer("bob")))
			T.expectEqual(env.credited.alice, nil, "hors manche")
			local training = setup({ training = true })
			training.Gains.onKill(participant(alice), participant(makePlayer("bob")))
			T.expectEqual(training.credited.alice, nil, "entraînement")
		end)

		T.it("plafond de manche : 12 kills sur joueurs = 60, fin de manche sans rien de plus", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			for _ = 1, 14 do
				env.Gains.onKill(a, participant(makePlayer("x")))
			end
			T.expectEqual(env.credited.alice, 60)
			env.Gains.onRoundEnd({ a }, a)
			T.expectEqual(env.credited.alice, 60)
			T.expectEqual(alice.attributes.RoundCredits, 60)
		end)
	end)

	T.describe("CreditGains : fin de manche", function()
		T.it("manche jouée par un kill sur bot + victoire : 1 + 15 + 25", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onSpawn(alice)
			env.Gains.onKill(a, participant(nil))
			env.Gains.onRoundEnd({ a }, a)
			T.expectEqual(env.credited.alice, 41)
			T.expectEqual(alice.attributes.RoundCredits, 41)
		end)

		T.it("sans kill : 120 s en vie cumulées sur plusieurs vies font une manche jouée", function()
			local env = setup()
			local alice, bob = makePlayer("alice"), makePlayer("bob")
			local a, b = participant(alice), participant(bob)
			env.Gains.onSpawn(alice)
			env.Gains.onSpawn(bob)
			walk(env, alice, nil, env.Economy.PLAYED_MIN_DISTANCE)
			walk(env, bob, nil, env.Economy.PLAYED_MIN_DISTANCE)
			env.clock = 70
			env.Gains.onDespawn(alice) -- mort à 70 s
			env.Gains.onDespawn(bob)
			env.clock = 75
			env.Gains.onSpawn(alice) -- réapparition
			env.clock = 125
			env.Gains.onRoundEnd({ a, b }, nil)
			T.expectEqual(env.credited.alice, 15, "70 + 50 s en vie")
			T.expectEqual(env.credited.bob, nil, "70 s seulement : AFK écarté")
			T.expectEqual(bob.attributes.RoundCredits, 0, "manche sans gain : 0 (le bandeau n'affiche rien)")
		end)

		T.it("un corps détruit en retard n'arrête pas la vie suivante", function()
			local env = setup()
			local alice = makePlayer("alice")
			local first, second = {}, {}
			env.Gains.onSpawn(alice, first)
			env.clock = 10
			env.Gains.onSpawn(alice, second) -- réapparition, le premier corps est encore là
			env.clock = 20
			env.Gains.onDespawn(alice, first) -- corps détruit après coup : ignoré
			env.Gains.onAction(alice)
			env.clock = 125
			env.Gains.onRoundEnd({ participant(alice) }, nil)
			T.expectEqual(env.credited.alice, 15, "10 + 115 s en vie")
		end)

		T.it("le temps passé hors manche active ne compte pas", function()
			local env = setup()
			local alice = makePlayer("alice")
			env.active = false
			env.Gains.onSpawn(alice)
			env.clock = 200
			env.active = true
			env.Gains.onRoundEnd({ participant(alice) }, nil)
			T.expectEqual(env.credited.alice, nil)
		end)

		T.it("une apparition hors manche active (bannière de fin) garde les gains affichés", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onKill(a, participant(makePlayer("bob")))
			env.Gains.onRoundEnd({ a }, nil)
			T.expectEqual(alice.attributes.RoundCredits, 20)
			env.active = false
			env.Gains.onSpawn(alice)
			T.expectEqual(alice.attributes.RoundCredits, 20)
			env.active = true
			env.Gains.onSpawn(alice)
			T.expectEqual(alice.attributes.RoundCredits, nil, "effacé à l'apparition de la manche suivante")
		end)

		T.it("les manches repartent de zéro (kills et plafond de manche)", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onKill(a, participant(makePlayer("bob")))
			env.Gains.onRoundEnd({ a }, nil)
			env.Gains.onRoundEnd({ a }, nil)
			T.expectEqual(env.credited.alice, 20, "seconde manche sans kill ni temps en vie : rien")
		end)

		T.it("plafond du jour atteint : crédit réduit puis nul, attribut à 0", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.daily["alice:" .. DAY] = 240
			env.Gains.onKill(a, participant(makePlayer("bob")))
			env.Gains.onRoundEnd({ a }, a)
			T.expectEqual(env.credited.alice, 10)
			T.expectEqual(alice.attributes.RoundCredits, 10)
			T.expectEqual(env.daily["alice:" .. DAY], 250)
			local banner = env.Economy.roundBanner(alice.attributes.RoundCredits, env.daily["alice:" .. DAY])
			assert(banner)
			T.expect(banner.capReached)
		end)

		T.it("solde qui ne peut pas changer (sauvegarde coupée) : rien, pas d'attribut", function()
			local alice = makePlayer("alice")
			local env = setup({ blocked = { alice } })
			local a = participant(alice)
			env.Gains.onKill(a, participant(makePlayer("bob")))
			env.Gains.onRoundEnd({ a }, a)
			T.expectEqual(env.credited.alice, nil)
			T.expectEqual(alice.attributes.RoundCredits, nil)
		end)

		T.it("entraînement : pas de gain de fin de manche", function()
			local env = setup({ training = true })
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onSpawn(alice)
			env.clock = 300
			env.Gains.onRoundEnd({ a }, a)
			T.expectEqual(env.credited.alice, nil)
			T.expectEqual(alice.attributes.RoundCredits, nil)
		end)

		T.it("bots ignorés en fin de manche", function()
			local env = setup()
			local bot = participant(nil)
			env.Gains.onRoundEnd({ bot }, bot)
			T.expectEqual(next(env.credited), nil)
		end)
	end)

	T.describe("CreditGains : activité réelle (#401)", function()
		T.it("AFK sans kill, 300 s en vie, immobile ou qui tourne sur place : pas crédité", function()
			local env = setup()
			local alice = makePlayer("alice")
			local char = {}
			env.Gains.onSpawn(alice, char)
			-- Tourne sur place : positions acceptées identiques (seul le cap change)
			for _ = 1, 100 do
				env.Gains.onMove(alice, char, pos(5, 5), pos(5, 5))
			end
			-- Saute sur place : la hauteur ne compte pas
			env.Gains.onMove(alice, char, pos(5, 5), pos(5, 5, 8))
			env.clock = 300
			env.Gains.onRoundEnd({ participant(alice) }, nil)
			T.expectEqual(env.credited.alice, nil)
			T.expectEqual(alice.attributes.RoundCredits, 0)
		end)

		T.it("actif sans kill : distance parcourue ou tir accepté, crédité", function()
			local env = setup()
			local alice, bob = makePlayer("alice"), makePlayer("bob")
			local a, b = participant(alice), participant(bob)
			env.Gains.onSpawn(alice)
			env.Gains.onSpawn(bob)
			walk(env, alice, nil, env.Economy.PLAYED_MIN_DISTANCE)
			env.Gains.onAction(bob)
			env.clock = 130
			env.Gains.onRoundEnd({ a, b }, nil)
			T.expectEqual(env.credited.alice, 15, "distance")
			T.expectEqual(env.credited.bob, 15, "tir accepté")
		end)

		T.it("avec un kill : crédité comme avant, sans activité ni temps en vie", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onSpawn(alice)
			env.Gains.onKill(a, participant(nil))
			env.clock = 10
			env.Gains.onRoundEnd({ a }, nil)
			T.expectEqual(env.credited.alice, 16, "1 (bot) + 15")
		end)

		T.it("distance juste sous le seuil : pas crédité", function()
			local env = setup()
			local alice = makePlayer("alice")
			env.Gains.onSpawn(alice)
			walk(env, alice, nil, env.Economy.PLAYED_MIN_DISTANCE - 1)
			env.clock = 300
			env.Gains.onRoundEnd({ participant(alice) }, nil)
			T.expectEqual(env.credited.alice, nil)
		end)

		T.it("hors vie ou hors manche active : activité ignorée", function()
			local env = setup()
			local alice = makePlayer("alice")
			local first, second = {}, {}
			-- Avant toute apparition (menu) : rien
			walk(env, alice, nil, 5000)
			env.Gains.onAction(alice)
			env.Gains.onSpawn(alice, first)
			env.clock = 60
			env.Gains.onDespawn(alice, first)
			-- Mort : plus en vie, rien n'est compté
			walk(env, alice, first, 5000)
			env.Gains.onAction(alice)
			env.Gains.onSpawn(alice, second)
			-- Paquet tardif de l'ancien personnage : ignoré
			walk(env, alice, first, 5000)
			env.clock = 130
			-- Bannière de fin : manche plus active
			env.active = false
			walk(env, alice, second, 5000)
			env.Gains.onAction(alice)
			env.active = true
			env.Gains.onRoundEnd({ participant(alice) }, nil)
			T.expectEqual(env.credited.alice, nil, "130 s en vie, aucune activité comptée")
		end)

		T.it("premier paquet sans position précédente : ignoré", function()
			local env = setup()
			local alice = makePlayer("alice")
			env.Gains.onSpawn(alice)
			env.Gains.onMove(alice, nil, nil, pos(9999, 9999))
			env.clock = 300
			env.Gains.onRoundEnd({ participant(alice) }, nil)
			T.expectEqual(env.credited.alice, nil)
		end)

		T.it("l'activité repart de zéro à chaque manche", function()
			local env = setup()
			local alice = makePlayer("alice")
			local a = participant(alice)
			env.Gains.onSpawn(alice)
			env.Gains.onAction(alice)
			env.clock = 130
			env.Gains.onRoundEnd({ a }, nil)
			T.expectEqual(env.credited.alice, 15)
			env.Gains.onSpawn(alice)
			env.clock = 300
			env.Gains.onRoundEnd({ a }, nil)
			T.expectEqual(env.credited.alice, 15, "seconde manche AFK : rien de plus")
		end)
	end)
end

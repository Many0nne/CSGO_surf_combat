-- Réapparition (#171) : délai depuis la mort, personnage vivant, un seul LoadCharacterAsync en vol, refus au journal.
return function(T, Loader)
	local DELAY = 2.5

	-- Cette méthode permet de construire une demande d'apparition par défaut (rien ne bloque) lorsqu'un test n'en
	-- change qu'un champ.
	local function request(overrides)
		local r = {
			spawning = false,
			hasCharacter = false,
			roundState = "active",
			diedAt = nil,
			now = 100,
			respawnDelay = DELAY,
		}
		for k, v in overrides do
			r[k] = v
		end
		return r
	end

	-- Cette méthode permet de construire un faux personnage (en place ou non, PV) lorsqu'un test vérifie isAlive.
	local function fakeCharacter(inGame: boolean, health: number?)
		local character = {
			Parent = if inGame then {} else nil,
			FindFirstChildOfClass = function()
				return if health then { Health = health } else nil
			end,
		}
		function character.Destroy(self)
			self.Parent = nil
		end
		return character
	end

	T.describe("SpawnRules.request", function()
		local SpawnRules = Loader.new():require("src/server/SpawnRules")

		T.it("accepte le premier spawn depuis le menu (round idle ou actif, jamais mort)", function()
			T.expectEqual(SpawnRules.request(request({ roundState = "idle" })), nil)
			T.expectEqual(SpawnRules.request(request({})), nil)
		end)

		T.it("refuse moins de RESPAWN_DELAY après la mort pendant un round actif", function()
			T.expectEqual(SpawnRules.request(request({ diedAt = 99.7 })), "early", "0,3 s : corps déjà détruit")
			T.expectEqual(SpawnRules.request(request({ diedAt = 100 - DELAY + 0.01 })), "early")
			T.expectEqual(SpawnRules.request(request({ diedAt = 100 - DELAY })), nil, "délai écoulé")
			T.expectEqual(
				SpawnRules.request(request({ diedAt = 99.9, hasCharacter = true })),
				"early",
				"corps encore en place : demande précoce, pas « alive »"
			)
		end)

		T.it("ne tient pas compte d'une mort hors round actif (round suivant après la bannière)", function()
			T.expectEqual(SpawnRules.request(request({ roundState = "idle", diedAt = 99.9 })), nil)
		end)

		T.it("un spawn en vol prime sur la demande précoce", function()
			T.expectEqual(SpawnRules.request(request({ spawning = true, diedAt = 99.9 })), "spawning")
		end)

		T.it("refuse un personnage en place, un spawn en vol et la bannière de fin", function()
			T.expectEqual(SpawnRules.request(request({ hasCharacter = true })), "alive")
			T.expectEqual(SpawnRules.request(request({ spawning = true })), "spawning")
			T.expectEqual(SpawnRules.request(request({ roundState = "result" })), "result")
		end)
	end)

	T.describe("SpawnRules.rejoinsInFlight (#157)", function()
		local SpawnRules = Loader.new():require("src/server/SpawnRules")

		T.it("sert une demande refusée « spawning » d'un joueur revenu du menu, hors bannière de fin", function()
			T.expectEqual(SpawnRules.rejoinsInFlight("spawning", true, "active"), true)
			T.expectEqual(SpawnRules.rejoinsInFlight("spawning", true, "idle"), true)
			T.expectEqual(SpawnRules.rejoinsInFlight("spawning", true, "result"), false, "bannière de fin")
			T.expectEqual(SpawnRules.rejoinsInFlight("spawning", false, "active"), false, "joueur resté en partie")
			T.expectEqual(SpawnRules.rejoinsInFlight("early", true, "active"), false)
			T.expectEqual(SpawnRules.rejoinsInFlight(nil, true, "active"), false)
		end)
	end)

	T.describe("SpawnRules.scheduled et isAlive", function()
		local SpawnRules = Loader.new():require("src/server/SpawnRules")

		T.it("ne fait pas réapparaître par-dessus un personnage vivant ni un spawn en vol", function()
			T.expectEqual(SpawnRules.scheduled(false, false), true)
			T.expectEqual(SpawnRules.scheduled(false, true), false)
			T.expectEqual(SpawnRules.scheduled(true, false), false)
		end)

		T.it("compte en place un personnage dans le jeu, vivant ou non", function()
			T.expectEqual(SpawnRules.inPlace(nil), false)
			T.expectEqual(SpawnRules.inPlace(fakeCharacter(true, 0)), true, "corps pas encore détruit")
			T.expectEqual(SpawnRules.inPlace(fakeCharacter(false, 100)), false)
		end)

		T.it("ne compte vivant qu'un personnage en place avec des PV", function()
			T.expectEqual(SpawnRules.isAlive(nil), false)
			T.expectEqual(SpawnRules.isAlive(fakeCharacter(true, 100)), true)
			T.expectEqual(SpawnRules.isAlive(fakeCharacter(true, 0)), false, "corps en attente de destruction")
			T.expectEqual(SpawnRules.isAlive(fakeCharacter(false, 100)), false, "personnage retiré")
			T.expectEqual(SpawnRules.isAlive(fakeCharacter(true, nil)), false, "sans Humanoid")
		end)
	end)

	-- Cette méthode permet de monter SpawnManager avec horloge, remote et services simulés lorsqu'un test passe par le
	-- handler de RequestSpawn ; state est l'état du round renvoyé au handler.
	local function setup()
		local env = { clock = 0, warns = {}, state = "active", started = 0 }
		local loader = Loader.new({
			Players = { PlayerRemoving = { Connect = function() end } },
			RunService = {
				IsStudio = function()
					return true
				end,
			},
			HttpService = {},
			Debris = {},
		}, {
			os = {
				clock = function()
					return env.clock
				end,
				date = os.date,
				time = os.time,
			},
			warn = function(...)
				table.insert(env.warns, table.concat({ ... }, " "))
			end,
			task = { spawn = function() end },
		})
		env.SpawnManager = loader:require("src/server/SpawnManager")
		env.CheatLog = loader:require("src/server/CheatLog")
		local remote = { Name = "RequestSpawn" }
		remote.OnServerEvent = {
			Connect = function(_, fn)
				env.handler = fn
			end,
		}
		env.SpawnManager.init(remote :: any, {
			roundState = function()
				return env.state
			end,
			beforeSpawn = function()
				env.started += 1
			end,
		})
		return env
	end

	-- Cette méthode permet de créer un faux joueur qui compte ses LoadCharacterAsync lorsqu'un test les vérifie ;
	-- duringLoad simule ce qui arrive pendant que l'appel attend (autre demande, réapparition programmée).
	local function fakePlayer(userId: number)
		local player = { UserId = userId, Name = "P" .. userId, Parent = {}, Character = nil, loads = 0 }
		player.CharacterAdded = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
		function player.LoadCharacterAsync(self)
			self.loads += 1
			if self.duringLoad then
				local fn = self.duringLoad
				self.duringLoad = nil
				fn()
			end
			self.Character = fakeCharacter(true, 100)
		end
		return player
	end

	T.describe("SpawnManager : RequestSpawn et réapparition programmée", function()
		T.it("refuse une demande 0,3 s après la mort et la journalise (Spawn, moyenne)", function()
			local env = setup()
			local p = fakePlayer(1)
			env.SpawnManager.noteDeath(p :: any)
			env.clock = 0.3
			env.handler(p)
			T.expectEqual(p.loads, 0)
			local summary = env.CheatLog.summary(1)
			T.expectEqual(summary.counts.Spawn.medium, 1)
			env.clock = 2.6
			env.handler(p)
			T.expectEqual(p.loads, 1, "accepté après RESPAWN_DELAY")
		end)

		T.it("premier spawn depuis le menu : démarre le round et charge le personnage", function()
			local env = setup()
			env.state = "idle"
			local p = fakePlayer(1)
			env.handler(p)
			T.expectEqual(env.started, 1)
			T.expectEqual(p.loads, 1)
			T.expectEqual(env.CheatLog.summary(1), nil, "aucune violation")
		end)

		T.it("demande d'un joueur déjà en jeu : refusée et journalisée faible (alive)", function()
			local env = setup()
			local p = fakePlayer(1)
			p.Character = fakeCharacter(true, 100)
			env.handler(p)
			T.expectEqual(p.loads, 0)
			T.expectEqual(env.CheatLog.summary(1).counts.Spawn.low, 1)
		end)

		T.it("mort en fin de round, bannière, puis Play au round suivant : accepté", function()
			local env = setup()
			local p = fakePlayer(1)
			env.SpawnManager.noteDeath(p :: any)
			env.state = "result"
			env.clock = 1
			env.handler(p)
			T.expectEqual(p.loads, 0, "bannière : refusé")
			env.state = "idle"
			env.clock = 6.5
			env.handler(p)
			T.expectEqual(env.started, 1)
			T.expectEqual(p.loads, 1)
			T.expectEqual(env.CheatLog.summary(1), nil, "aucune violation pour un client honnête")
		end)

		T.it("oublie un joueur parti (forget) : plus de délai ni de spawn en vol retenus", function()
			local env = setup()
			local p = fakePlayer(1)
			env.SpawnManager.noteDeath(p :: any)
			env.SpawnManager.forget(p :: any)
			env.clock = 0.5
			env.handler(p)
			T.expectEqual(p.loads, 1)
		end)

		T.it("Play pendant la bannière de fin : refusé sans violation", function()
			local env = setup()
			env.state = "result"
			local p = fakePlayer(1)
			env.handler(p)
			T.expectEqual(p.loads, 0)
			T.expectEqual(env.CheatLog.summary(1), nil)
		end)

		T.it("un seul LoadCharacterAsync en vol (demande et réapparition programmée pendant l'attente)", function()
			local env = setup()
			local p = fakePlayer(1)
			p.duringLoad = function()
				env.clock = 0.5
				env.handler(p)
				env.SpawnManager.respawn(p :: any)
			end
			env.handler(p)
			T.expectEqual(p.loads, 1)
		end)

		T.it("la réapparition programmée ne remplace pas un personnage vivant", function()
			local env = setup()
			local p = fakePlayer(1)
			p.Character = fakeCharacter(true, 100)
			env.SpawnManager.respawn(p :: any)
			T.expectEqual(p.loads, 0)
			p.Character = fakeCharacter(false, 0)
			env.SpawnManager.respawn(p :: any)
			T.expectEqual(p.loads, 1, "corps détruit : réapparition")
		end)

		T.it("libère le spawn en vol quand LoadCharacterAsync échoue", function()
			local env = setup()
			local p = fakePlayer(1)
			function p.LoadCharacterAsync(self)
				self.loads += 1
				error("échec simulé")
			end
			env.handler(p)
			env.clock = 2
			env.handler(p)
			T.expectEqual(p.loads, 2)
		end)
	end)

	T.describe("SpawnManager : retour au menu en partie (#157)", function()
		T.it("détruit le personnage et annule la réapparition programmée", function()
			local env = setup()
			local p = fakePlayer(1)
			local char = fakeCharacter(true, 100)
			p.Character = char
			env.SpawnManager.withdraw(p :: any)
			T.expectEqual(char.Parent, nil, "personnage détruit")
			env.SpawnManager.respawn(p :: any)
			T.expectEqual(p.loads, 0, "pas de réapparition")
		end)

		T.it("accepte JOUER juste après une mort suivie d'un retour au menu, sans journal", function()
			local env = setup()
			local p = fakePlayer(1)
			env.SpawnManager.noteDeath(p :: any)
			env.SpawnManager.withdraw(p :: any)
			env.SpawnManager.noteDeath(p :: any) -- une mort annoncée après le retrait n'est pas retenue
			env.clock = 0.3
			env.handler(p)
			T.expectEqual(p.loads, 1)
			T.expectEqual(env.CheatLog.summary(1), nil, "rien au journal")
		end)

		T.it(
			"sert JOUER arrivé pendant la réapparition en vol, sans second chargement si le personnage est gardé",
			function()
				local env = setup()
				local p = fakePlayer(1)
				p.duringLoad = function()
					env.SpawnManager.withdraw(p :: any)
					env.handler(p)
				end
				env.SpawnManager.respawn(p :: any)
				T.expectEqual(p.loads, 1)
				T.expectEqual(env.started, 1, "remis au round (beforeSpawn)")
				T.expectEqual(env.CheatLog.summary(1), nil, "pas de refus journalisé")
				env.SpawnManager.respawn(p :: any)
				T.expectEqual(p.loads, 1, "personnage vivant : rien de plus")
			end
		)

		T.it("recharge si le personnage en vol a été détruit, refuse pendant la bannière de fin", function()
			local env = setup()
			local p = fakePlayer(1)
			p.duringLoad = function()
				env.SpawnManager.withdraw(p :: any)
				env.handler(p)
			end
			-- Le personnage en vol est arrivé pendant le retrait : détruit
			function p.LoadCharacterAsync(self)
				self.loads += 1
				if self.duringLoad then
					local fn = self.duringLoad
					self.duringLoad = nil
					fn()
					self.Character = fakeCharacter(false, 0)
				else
					self.Character = fakeCharacter(true, 100)
				end
			end
			env.SpawnManager.respawn(p :: any)
			T.expectEqual(p.loads, 2, "nouveau chargement pour la demande")

			local env2 = setup()
			env2.state = "result"
			local q = fakePlayer(2)
			q.duringLoad = function()
				env2.SpawnManager.withdraw(q :: any)
				env2.handler(q)
			end
			env2.SpawnManager.respawn(q :: any)
			T.expectEqual(env2.started, 0, "bannière de fin : pas de retour au round")
		end)
	end)
end

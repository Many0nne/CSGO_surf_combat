-- Cycle d'un round avec un joueur et un faux bot (#137) : score, annonce de mort (kill feed), réapparition, gagnant.
return function(T, Loader)
	-- Cette méthode permet de construire un personnage minimal (racine positionnée) lorsqu'un participant en a besoin.
	local function makeCharacter(position: Vector3)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = position
		root.Parent = model
		return model
	end

	-- Cette méthode permet de simuler un RemoteEvent lorsqu'un test lit ce que le serveur envoie à tous les clients.
	local function fakeRemote()
		local remote = { sent = {} }
		function remote.FireAllClients(_, data)
			table.insert(remote.sent, data)
		end
		function remote.last()
			return remote.sent[#remote.sent]
		end
		return remote
	end

	-- Cette méthode permet de monter un RoundManager avec services, remotes, `task` et horloge simulés lorsqu'un test
	-- démarre ; les délais ne partent qu'à flush, tick fait avancer le timer du round et wait l'horloge (os.clock).
	local function setup()
		local players, owners = {}, {}
		local now = 0
		local heartbeat = nil
		local pending = {}
		local services = {
			Players = {
				GetPlayers = function()
					return players
				end,
				GetPlayerFromCharacter = function(_, character)
					return owners[character]
				end,
			},
			RunService = {
				IsServer = function()
					return true
				end,
				Heartbeat = {
					Connect = function(_, fn)
						heartbeat = fn
						return {
							Disconnect = function()
								heartbeat = nil
							end,
						}
					end,
				},
			},
			Stats = {},
		}
		-- Durées des délais programmés, dans l'ordre (fin de manche : RESULT_DURATION, #300)
		local delays = {}
		local fakeTask = {
			delay = function(seconds, fn, ...)
				table.insert(delays, seconds)
				table.insert(pending, table.pack(fn, ...))
			end,
			spawn = function(fn, ...)
				fn(...)
			end,
		}
		local fakeOs = {
			clock = function()
				return now
			end,
		}
		local loader = Loader.new(services, { task = fakeTask, os = fakeOs })
		local RoundManager = loader:require("src/server/RoundManager")
		local Participants = loader:require("src/server/Participants")
		local remotes = {
			roundState = fakeRemote(),
			scoreUpdate = fakeRemote(),
			roundResult = fakeRemote(),
			playerDied = fakeRemote(),
		}
		-- Fins de manche signalées aux stats persistantes (#296) : participants en jeu et vainqueur
		local roundEnds = {}
		RoundManager.init({
			roundState = remotes.roundState,
			scoreUpdate = remotes.scoreUpdate,
			roundResult = remotes.roundResult,
			playerDied = remotes.playerDied,
			onRoundEnd = function(participants, winner)
				table.insert(roundEnds, { participants = participants, winner = winner })
			end,
		} :: any)

		local env = {
			RoundManager = RoundManager,
			Participants = Participants,
			remotes = remotes,
			roundEnds = roundEnds,
			delays = delays,
			GameConfig = loader:require("src/shared/GameConfig"),
		}
		-- Cette méthode permet d'inscrire un joueur au classement lorsqu'un test en a besoin ; sans position, il est resté
		-- au menu (pas de personnage).
		function env.addPlayer(userId: number, name: string, position: Vector3?)
			local player = { UserId = userId, Name = name, Character = position and makeCharacter(position) }
			if player.Character then
				owners[player.Character] = player
			end
			table.insert(players, player)
			local participant = Participants.fromPlayer(player :: any)
			RoundManager.addParticipant(participant)
			return participant
		end
		function env.addBot(name: string, position: Vector3)
			local bot = Participants.addBot(name)
			Participants.setCharacter(bot, makeCharacter(position))
			RoundManager.addParticipant(bot)
			return bot
		end
		function env.flush()
			local due = pending
			pending = {}
			for _, call in due do
				call[1](table.unpack(call, 2, call.n))
			end
		end
		-- Cette méthode permet d'avancer l'horloge simulée (os.clock) lorsqu'un test fait vieillir le dernier coup reçu.
		function env.wait(seconds: number)
			now += seconds
		end
		function env.tick(dt: number)
			if heartbeat then
				heartbeat(dt)
			end
		end
		return env
	end

	T.describe("RoundManager : participants joueur et bot", function()
		T.it("compte le kill d'un bot sur un joueur et l'annonce avec son nom", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.new(10, 0, 0))
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)

			env.RoundManager.recordDamage(bot, alice, "AWP", true)
			local killer = env.RoundManager.onCharacterDied(alice, function() end)

			T.expectEqual(killer, bot, "tueur crédité")
			local scores = env.remotes.scoreUpdate.last()
			T.expectEqual(scores[bot.id].kills, 1)
			T.expectEqual(scores[bot.id].isBot, true)
			T.expectEqual(scores[alice.id].deaths, 1)
			T.expectEqual(scores[alice.id].isBot, false)

			local death = env.remotes.playerDied.last()
			T.expectEqual(death.victimId, 1)
			T.expectEqual(death.victimName, "Alice")
			T.expectEqual(death.victimIsBot, false)
			T.expectEqual(death.killerId, bot.id)
			T.expectEqual(death.killerName, "Marcel")
			T.expectEqual(death.killerIsBot, true)
			T.expectEqual(death.weapon, "AWP")
			T.expectEqual(death.headshot, true)
			T.expectEqual(death.direction, Vector3.new(1, 0, 0), "du tueur vers la victime")
		end)

		T.it("compte le kill d'un joueur sur un bot et fait réapparaître le bot", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)

			env.RoundManager.recordDamage(alice, bot, "M9Bayonet", false)
			local respawned = 0
			env.RoundManager.onCharacterDied(bot, function()
				respawned += 1
			end)
			local death = env.remotes.playerDied.last()
			T.expectEqual(death.victimId, bot.id)
			T.expectEqual(death.victimName, "Marcel")
			T.expectEqual(death.victimIsBot, true)
			T.expectEqual(death.killerName, "Alice")
			T.expectEqual(death.killerIsBot, false)
			T.expectEqual(env.remotes.scoreUpdate.last()[alice.id].kills, 1)

			env.flush()
			T.expectEqual(respawned, 1, "réapparition après RESPAWN_DELAY")
		end)

		T.it("ne fait pas réapparaître un bot retiré entre-temps", function()
			local env = setup()
			env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			local respawned = false
			env.RoundManager.onCharacterDied(bot, function()
				respawned = true
			end)
			env.RoundManager.removeParticipant(bot)
			env.Participants.remove(bot)
			env.flush()
			T.expectEqual(respawned, false)
			T.expectEqual(env.remotes.scoreUpdate.last()[bot.id], nil, "retiré du classement")
		end)

		T.it("annonce une chute sans tueur", function()
			local env = setup()
			local bot = env.addBot("Marcel", Vector3.zero)
			env.addPlayer(1, "Alice", Vector3.zero)
			env.RoundManager.startRound(60)
			T.expectEqual(env.RoundManager.onCharacterDied(bot, function() end), nil)
			local death = env.remotes.playerDied.last()
			T.expectEqual(death.killerId, nil)
			T.expectEqual(death.killerName, nil)
			T.expectEqual(death.killerIsBot, false)
		end)

		T.it("n'attribue pas le kill d'un tueur parti", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)
			env.RoundManager.removeParticipant(bot)
			env.Participants.remove(bot)
			T.expectEqual(env.RoundManager.onCharacterDied(alice, function() end), nil)
			T.expectEqual(env.remotes.playerDied.last().killerName, nil)
		end)

		T.it("désigne un bot gagnant par son id, aucun joueur vainqueur dans les stats", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)
			env.RoundManager.onCharacterDied(alice, function() end)
			env.tick(61)
			T.expectEqual(env.RoundManager.getState(), "result")
			local result = env.remotes.roundResult.last()
			T.expectEqual(result.outcome, "winner")
			T.expectEqual(result.winnerId, bot.id)
			T.expectEqual(result.winnerName, nil, "plus de nom affiché : le client le résout (#295)")
			T.expectEqual(env.roundEnds[1].winner, bot, "aucun joueur compté vainqueur")
		end)
	end)

	T.describe("RoundManager : retour au menu en partie (#157)", function()
		T.it("retire le score de la manche du joueur et garde les morts qu'il a infligées", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(alice, bot, "AWP", false)
			env.RoundManager.onCharacterDied(bot, function() end)

			env.RoundManager.withdraw(alice)

			local scores = env.remotes.scoreUpdate.last()
			T.expectEqual(scores[alice.id], nil, "retiré du classement")
			T.expectEqual(scores[bot.id].deaths, 1, "la mort du bot reste comptée")
		end)

		T.it("ne compte pas la disparition de son personnage comme une mort ni ne le fait réapparaître", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", true)
			-- Coup ancien : départ libre (#217)
			env.wait(10)
			local deathsBefore = #env.remotes.playerDied.sent

			env.RoundManager.withdraw(alice)
			local respawned = false
			local killer = env.RoundManager.onCharacterDied(alice, function()
				respawned = true
			end)
			env.flush()

			T.expectEqual(killer, nil, "aucun kill crédité à l'adversaire")
			T.expectEqual(#env.remotes.playerDied.sent, deathsBefore, "aucune mort annoncée")
			T.expectEqual(env.remotes.scoreUpdate.last()[alice.id], nil, "score pas recréé")
			T.expectEqual(env.remotes.scoreUpdate.last()[bot.id].kills, 0)
			T.expectEqual(respawned, false)
		end)

		T.it("n'attribue plus de kill à un joueur revenu au menu", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(alice, bot, "AWP", false)
			env.RoundManager.withdraw(alice)

			T.expectEqual(env.RoundManager.onCharacterDied(bot, function() end), nil, "chute sans tueur")
			T.expectEqual(env.remotes.playerDied.last().killerName, nil)
			T.expectEqual(env.remotes.scoreUpdate.last()[bot.id].deaths, 1, "la mort du bot compte")
		end)

		T.it("compte de nouveau ses kills et ses morts quand il relance une partie", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.withdraw(alice)

			env.RoundManager.addParticipant(alice)
			T.expectEqual(env.remotes.scoreUpdate.last()[alice.id].kills, 0, "de retour au classement, à zéro")
			env.RoundManager.recordDamage(alice, bot, "AWP", false)
			env.RoundManager.onCharacterDied(bot, function() end)
			T.expectEqual(env.remotes.scoreUpdate.last()[alice.id].kills, 1, "kill compté avant sa première mort")

			local respawned = false
			env.RoundManager.onCharacterDied(alice, function()
				respawned = true
			end)
			env.flush()
			T.expectEqual(env.remotes.scoreUpdate.last()[alice.id].deaths, 1)
			T.expectEqual(respawned, true, "réapparition programmée de nouveau")
		end)
	end)

	T.describe("RoundManager : départ juste après un coup reçu (#217)", function()
		T.it("compte un départ 4,9 s après un coup comme une mort, kill au dernier attaquant", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.new(10, 0, 0))
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", true)
			env.wait(4.9)

			local died, killer = env.RoundManager.withdraw(alice)

			T.expectEqual(died, true, "départ compté comme une mort")
			T.expectEqual(killer, bot, "kill au dernier attaquant")
			T.expectEqual(env.remotes.scoreUpdate.last()[bot.id].kills, 1, "kill compté au round")
			T.expectEqual(env.remotes.scoreUpdate.last()[alice.id], nil, "le partant quitte le classement")
			local death = env.remotes.playerDied.last()
			T.expectEqual(death.victimId, alice.id, "kill feed : victime")
			T.expectEqual(death.killerName, "Marcel", "kill feed : tueur")
			T.expectEqual(death.weapon, "AWP")
			T.expectEqual(death.headshot, true)
		end)

		T.it("laisse partir librement 5,1 s après le coup", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)
			env.wait(5.1)
			local deathsBefore = #env.remotes.playerDied.sent

			local died, killer = env.RoundManager.withdraw(alice)

			T.expectEqual(died, false)
			T.expectEqual(killer, nil)
			T.expectEqual(#env.remotes.playerDied.sent, deathsBefore, "aucune mort annoncée")
			T.expectEqual(env.remotes.scoreUpdate.last()[bot.id].kills, 0)
		end)

		T.it("laisse partir librement sans coup reçu", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)

			T.expectEqual((env.RoundManager.withdraw(alice)), false)
			T.expectEqual(#env.remotes.playerDied.sent, 0)
		end)

		T.it("crédite le kill à un attaquant mort entre-temps", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bob = env.addPlayer(2, "Bob", Vector3.new(5, 0, 0))
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bob, alice, "AWP", false)
			env.RoundManager.onCharacterDied(bob, function() end) -- Bob meurt d'une chute
			env.wait(1)

			local died, killer = env.RoundManager.withdraw(alice)

			T.expectEqual(died, true)
			T.expectEqual(killer, bob, "toujours inscrit : crédité comme pour une mort normale")
			T.expectEqual(env.remotes.scoreUpdate.last()[bob.id].kills, 1)
		end)

		T.it("laisse partir librement si l'attaquant a quitté le jeu", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)
			env.Participants.remove(bot)
			env.RoundManager.removeParticipant(bot)

			T.expectEqual((env.RoundManager.withdraw(alice)), false, "personne à créditer")
		end)

		T.it("laisse partir librement si l'attaquant est lui-même revenu au menu", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bob = env.addPlayer(2, "Bob", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bob, alice, "AWP", false)
			env.RoundManager.withdraw(bob)

			T.expectEqual((env.RoundManager.withdraw(alice)), false, "ses coups en attente sont oubliés (#157)")
		end)

		T.it("ne compte qu'une mort pour un double clic, puis ni mort ni réapparition", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)

			T.expectEqual((env.RoundManager.withdraw(alice)), true)
			T.expectEqual((env.RoundManager.withdraw(alice)), false, "second clic")
			local respawned = false
			local killer = env.RoundManager.onCharacterDied(alice, function()
				respawned = true
			end)
			env.flush()
			T.expectEqual(killer, nil, "destruction du personnage non comptée")
			T.expectEqual(#env.remotes.playerDied.sent, 1, "une seule annonce")
			T.expectEqual(env.remotes.scoreUpdate.last()[bot.id].kills, 1)
			T.expectEqual(respawned, false)
		end)

		T.it("laisse partir librement après un coup absorbé par la protection d'apparition", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false, true)

			T.expectEqual((env.RoundManager.withdraw(alice)), false, "aucun PV perdu")
		end)

		T.it("garde le tueur d'un coup absorbé par la protection, pour une chute qui suit", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false, true)

			T.expectEqual(env.RoundManager.onCharacterDied(alice, function() end), bot)
		end)

		T.it("ne compte rien hors d'un round actif", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)

			T.expectEqual((env.RoundManager.withdraw(alice)), false)
		end)
	end)
	T.describe("RoundManager : fin de manche et stats persistantes (#296)", function()
		-- Cette méthode permet de lister les ids des participants signalés à une fin de manche lorsqu'un test les compare.
		local function endedIds(roundEnd): string
			local ids = {}
			for _, participant in roundEnd.participants do
				table.insert(ids, participant.id)
			end
			table.sort(ids)
			return table.concat(ids, ",")
		end

		T.it("signale les participants en jeu et le vainqueur désigné par id", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bob = env.addPlayer(2, "Bob", Vector3.new(0, 0, 5))
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 10))
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bob, bot, "AWP", false)
			env.RoundManager.onCharacterDied(bot, function() end)
			env.tick(61)
			T.expectEqual(#env.roundEnds, 1, "une fin de manche")
			local roundEnd = env.roundEnds[1]
			T.expectEqual(endedIds(roundEnd), string.format("%d,%d,%d", bot.id, alice.id, bob.id))
			T.expectEqual(roundEnd.winner, bob)
			T.expectEqual(env.remotes.roundResult.last().outcome, "winner")
			T.expectEqual(env.remotes.roundResult.last().winnerId, bob.id)
		end)

		T.it("départage deux homonymes par leur id", function()
			local env = setup()
			local first = env.addPlayer(1, "Alice", Vector3.zero)
			local second = env.addPlayer(2, "Alice", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(second, first, "AWP", false)
			env.RoundManager.onCharacterDied(first, function() end)
			env.tick(61)
			T.expectEqual(env.roundEnds[1].winner, second)
		end)

		T.it("ne compte pas un joueur resté au menu, ni dans les stats, ni sur le podium", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local idle = env.addPlayer(2, "Paul") -- au classement depuis son arrivée, jamais apparu
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			-- Alice tue le bot puis meurt d'une chute (1 kill, 1 mort) ; Paul reste à 0 kill, 0 mort
			env.RoundManager.recordDamage(alice, bot, "AWP", false)
			env.RoundManager.onCharacterDied(bot, function() end)
			env.RoundManager.onCharacterDied(alice, function() end)
			env.tick(61)
			local roundEnd = env.roundEnds[1]
			T.expectEqual(endedIds(roundEnd), string.format("%d,%d", bot.id, alice.id))
			T.expectEqual(roundEnd.winner, alice)
			for _, score in env.remotes.roundResult.last().scores do
				T.expect(score.id ~= idle.id, "Paul n'a pas joué : absent du podium")
			end
			T.expectEqual(#env.remotes.roundResult.last().scores, 2)
		end)

		T.it("compte un joueur mort en attente de réapparition à la fin", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.onCharacterDied(alice, function() end)
			alice.player.Character = nil -- corps détruit, pas encore réapparu
			env.tick(61)
			T.expectEqual(endedIds(env.roundEnds[1]), tostring(alice.id))
			T.expectEqual(env.roundEnds[1].winner, nil, "aucun kill : pas de vainqueur (#295)")
		end)

		T.it("ne compte pas un joueur revenu au menu pendant la manche", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bob = env.addPlayer(2, "Bob", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			env.RoundManager.withdraw(bob)
			env.tick(61)
			T.expectEqual(endedIds(env.roundEnds[1]), tostring(alice.id))
		end)

		T.it("sans participant en jeu : pas de vainqueur", function()
			local env = setup()
			env.addPlayer(1, "Paul")
			env.RoundManager.startRound(60)
			env.tick(61)
			T.expectEqual(#env.roundEnds[1].participants, 0)
			T.expectEqual(env.roundEnds[1].winner, nil)
			T.expectEqual(env.remotes.roundResult.last().outcome, "none")
			T.expectEqual(env.remotes.roundResult.last().winnerId, nil)
		end)
	end)

	T.describe("RoundManager : vainqueur aux cas limites (#295)", function()
		-- Cette méthode permet de faire tuer `victim` par `killer` lorsqu'un test compose les scores d'une manche.
		local function kill(env, killer, victim)
			env.RoundManager.recordDamage(killer, victim, "AWP", false)
			env.RoundManager.onCharacterDied(victim, function() end)
		end

		T.it("départage une égalité de kills aux morts", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bob = env.addPlayer(2, "Bob", Vector3.new(0, 0, 5))
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 10))
			env.RoundManager.startRound(60)
			kill(env, alice, bot)
			kill(env, bob, bot)
			kill(env, bot, alice) -- 1 kill chacun, Alice 1 mort, Bob 0
			env.tick(61)
			T.expectEqual(env.remotes.roundResult.last().outcome, "winner")
			T.expectEqual(env.remotes.roundResult.last().winnerId, bob.id)
			T.expectEqual(env.roundEnds[1].winner, bob)
		end)

		T.it("ne désigne personne à égalité parfaite en tête, quel que soit l'ordre d'inscription", function()
			for _, order in { { 1, 2 }, { 2, 1 } } do
				local env = setup()
				local players = {}
				for _, userId in order do
					players[userId] = env.addPlayer(userId, "J" .. userId, Vector3.new(0, 0, userId * 5))
				end
				local bot = env.addBot("Marcel", Vector3.zero)
				env.RoundManager.startRound(60)
				kill(env, players[1], bot)
				kill(env, players[2], bot)
				env.tick(61)
				local result = env.remotes.roundResult.last()
				T.expectEqual(result.outcome, "tie", "ordre " .. table.concat(order, ","))
				T.expectEqual(result.winnerId, nil)
				T.expectEqual(env.roundEnds[1].winner, nil, "aucun vainqueur dans les stats")
				T.expectEqual(#env.roundEnds[1].participants, 3, "manche jouée comptée pour chacun")
			end
		end)

		T.it("ne désigne personne quand aucun kill n'a été fait", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			env.RoundManager.onCharacterDied(alice, function() end) -- chute : 0 kill, 1 mort ; le bot 0 kill, 0 mort
			env.tick(61)
			local result = env.remotes.roundResult.last()
			T.expectEqual(result.outcome, "none")
			T.expectEqual(result.winnerId, nil)
			T.expectEqual(env.roundEnds[1].winner, nil)
			T.expectEqual(#result.scores, 2, "le podium montre quand même les participants")
			for _, score in result.scores do
				T.expect(score.id == alice.id or score.id == bot.id, "score envoyé avec son id")
			end
		end)
	end)

	T.describe("RoundManager : manches enchaînées (#300)", function()
		T.it("reste en result RESULT_DURATION, puis repasse idle avec les scores remis à zéro", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(alice, bot, "AWP", false)
			env.RoundManager.onCharacterDied(bot, function() end)
			env.flush() -- réapparition du bot (round actif)
			table.clear(env.delays)
			env.tick(61)
			T.expectEqual(env.RoundManager.getState(), "result")
			T.expectEqual(env.delays[1], env.GameConfig.RESULT_DURATION, "bannière : une seule source, GameConfig")
			env.flush()
			T.expectEqual(env.RoundManager.getState(), "idle")
			T.expectEqual(env.remotes.roundState.last().state, "idle")
		end)

		T.it("démarre la manche suivante avec des scores neufs pour un joueur qui enchaîne", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.new(0, 0, 5))
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(alice, bot, "AWP", false)
			env.RoundManager.onCharacterDied(bot, function() end)
			env.RoundManager.recordDamage(alice, bot, "AWP", false) -- coup encore en attente à la fin de la manche
			env.tick(61)
			env.flush()
			-- Demande d'apparition acceptée après la bannière (beforeSpawn) : round démarré, joueur réinscrit
			env.RoundManager.startRound(60)
			env.RoundManager.addParticipant(alice)
			T.expectEqual(env.RoundManager.getState(), "active")
			local scores = env.remotes.scoreUpdate.last()
			T.expectEqual(scores[alice.id].kills, 0, "kills de la manche précédente oubliés")
			T.expectEqual(scores[bot.id], nil, "bot réinscrit seulement à sa réapparition (BotManager)")
			-- Un coup de la manche précédente ne désigne plus de tueur
			env.Participants.setCharacter(bot, makeCharacter(Vector3.zero)) -- réapparu (BotManager)
			env.RoundManager.addParticipant(bot)
			local killer = env.RoundManager.onCharacterDied(bot, function() end)
			T.expectEqual(killer, nil)
		end)

		T.it("enchaîne trois manches de suite", function()
			local env = setup()
			env.addPlayer(1, "Alice", Vector3.zero)
			for round = 1, 3 do
				env.RoundManager.startRound(60)
				T.expectEqual(env.RoundManager.getState(), "active", "manche " .. round)
				env.tick(61)
				T.expectEqual(env.RoundManager.getState(), "result", "manche " .. round)
				env.flush()
				T.expectEqual(env.RoundManager.getState(), "idle", "manche " .. round)
			end
			T.expectEqual(#env.roundEnds, 3)
		end)
	end)
end

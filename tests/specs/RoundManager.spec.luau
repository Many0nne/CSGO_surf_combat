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

	-- Cette méthode permet de monter un RoundManager avec services, remotes et `task` simulés lorsqu'un test démarre ;
	-- les délais (réapparition, fin de résultat) ne partent que quand le test appelle flush, et tick fait avancer le timer.
	local function setup()
		local players, owners = {}, {}
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
		local fakeTask = {
			delay = function(_seconds, fn, ...)
				table.insert(pending, table.pack(fn, ...))
			end,
		}
		local loader = Loader.new(services, { task = fakeTask })
		local RoundManager = loader:require("src/server/RoundManager")
		local Participants = loader:require("src/server/Participants")
		local remotes = {
			roundState = fakeRemote(),
			scoreUpdate = fakeRemote(),
			roundResult = fakeRemote(),
			playerDied = fakeRemote(),
		}
		RoundManager.init(remotes)

		local env = { RoundManager = RoundManager, Participants = Participants, remotes = remotes }
		function env.addPlayer(userId: number, name: string, position: Vector3)
			local player = { UserId = userId, Name = name, Character = makeCharacter(position) }
			owners[player.Character] = player
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

		T.it("désigne un bot gagnant avec le préfixe BOT", function()
			local env = setup()
			local alice = env.addPlayer(1, "Alice", Vector3.zero)
			local bot = env.addBot("Marcel", Vector3.zero)
			env.RoundManager.startRound(60)
			env.RoundManager.recordDamage(bot, alice, "AWP", false)
			env.RoundManager.onCharacterDied(alice, function() end)
			env.tick(61)
			T.expectEqual(env.RoundManager.getState(), "result")
			T.expectEqual(env.remotes.roundResult.last().winnerName, "BOT Marcel")
		end)
	end)
end

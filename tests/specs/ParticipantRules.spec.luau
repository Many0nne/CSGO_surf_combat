-- Règles de l'identité joueur/bot (#137) et registre des participants.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/ParticipantRules")

	T.describe("ParticipantRules", function()
		T.it("reconnaît un bot à son id négatif", function()
			T.expectEqual(Rules.isBotId(-1), true)
			T.expectEqual(Rules.isBotId(12345), false)
		end)

		T.it("donne au nouveau bot le premier id négatif libre", function()
			T.expectEqual(Rules.nextBotId({}), -1)
			T.expectEqual(Rules.nextBotId({ [-1] = true, [-2] = true, [42] = true }), -3)
			T.expectEqual(Rules.nextBotId({ [-2] = true }), -1, "un id libéré resert")
		end)

		T.it("préfixe le nom d'un bot", function()
			T.expectEqual(Rules.displayName("Marcel", true), "BOT Marcel")
			T.expectEqual(Rules.displayName("Alice", false), "Alice")
			T.expectEqual(Rules.displayName("Alice"), "Alice")
		end)

		T.it("ne compte dans les stats que les morts d'un joueur hors kill de bot", function()
			T.expectEqual(Rules.countsInStats(false, false), true, "tué par un joueur")
			T.expectEqual(Rules.countsInStats(false, nil), true, "chute")
			T.expectEqual(Rules.countsInStats(false, true), false, "tué par un bot")
			T.expectEqual(Rules.countsInStats(true, false), false, "un bot n'a pas de stats")
		end)
	end)

	T.describe("Participants", function()
		-- Cette méthode permet de charger un registre neuf avec un service Players simulé lorsqu'un test démarre.
		local function setup()
			local owners = {}
			local loader = Loader.new({
				Players = {
					GetPlayerFromCharacter = function(_, character)
						return owners[character]
					end,
				},
			})
			return loader:require("src/server/Participants"), owners
		end

		T.it("inscrit un joueur une seule fois sous son UserId", function()
			local Participants = setup()
			local player = { UserId = 7, Name = "Alice" }
			local p = Participants.fromPlayer(player :: any)
			T.expectEqual(Participants.fromPlayer(player :: any), p)
			T.expectEqual(p.id, 7)
			T.expectEqual(p.isBot, false)
			T.expectEqual(Participants.get(7), p)
		end)

		T.it("retrouve joueur et bot depuis leur personnage", function()
			local Participants, owners = setup()
			local player = { UserId = 7, Name = "Alice", Character = Instance.new("Model") }
			owners[player.Character] = player
			T.expectEqual(Participants.fromCharacter(player.Character), nil, "joueur pas encore inscrit")
			Participants.fromPlayer(player :: any)
			local bot = Participants.addBot("Marcel")
			local botChar = Instance.new("Model")
			Participants.setCharacter(bot, botChar)
			T.expectEqual(Participants.fromCharacter(player.Character), Participants.fromPlayer(player :: any))
			T.expectEqual(Participants.fromCharacter(botChar), bot)
			T.expectEqual(Participants.characterOf(bot), botChar)
			T.expectEqual(Participants.characterOf(Participants.fromPlayer(player :: any)), player.Character)
			T.expectEqual(Participants.fromCharacter(Instance.new("Model")), nil)
		end)

		T.it("ne réinscrit pas un joueur parti dont le corps est touché", function()
			local Participants, owners = setup()
			local player = { UserId = 7, Name = "Alice", Character = Instance.new("Model") }
			owners[player.Character] = player
			Participants.remove(Participants.fromPlayer(player :: any))
			T.expectEqual(Participants.fromCharacter(player.Character), nil)
			T.expectEqual(Participants.get(7), nil)
		end)

		T.it("libère l'id d'un bot retiré", function()
			local Participants = setup()
			local first = Participants.addBot("Marcel")
			local second = Participants.addBot("Lucie")
			T.expectEqual(first.id, -1)
			T.expectEqual(second.id, -2)
			Participants.remove(first)
			T.expectEqual(Participants.isRegistered(first), false)
			T.expectEqual(Participants.addBot("Paul").id, -1)
		end)
	end)
end

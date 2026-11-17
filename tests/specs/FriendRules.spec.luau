-- Liste d'amis du lobby (#523) : statuts, tri, actions et raisons des actions impossibles.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/FriendRules")

	local PLACE, JOB = 100, "job-ici"

	-- Cette méthode permet de construire le contexte d'une ligne lorsqu'un test choisit une action (valeurs par défaut :
	-- jeu publié, invitation permise, serveur pas plein, groupe vide).
	local function ctx(overrides: { [string]: any }?)
		local base = { studio = false, canInvite = true, serverFull = false, partyIds = {} }
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	-- Cette méthode permet de trouver un ami par son id dans une liste lorsqu'un test lit son statut.
	local function find(list, id: number)
		for _, friend in list do
			if friend.id == id then
				return friend
			end
		end
		return nil
	end

	T.describe("FriendRules.merge", function()
		local all = {
			{ Id = 1, Username = "zed", DisplayName = "Zed" },
			{ Id = 2, Username = "amy", DisplayName = "" },
			{ Id = 3, Username = "bob", DisplayName = "Bob" },
			{ Id = 4, Username = "cid", DisplayName = "Cid" },
			{ Id = 5, Username = "dan", DisplayName = "Dan" },
		}
		local online = {
			{ VisitorId = 2, UserName = "amy", LocationType = 4, PlaceId = PLACE, GameId = "job-ailleurs" },
			{ VisitorId = 3, UserName = "bob", LocationType = 4, PlaceId = 999, GameId = "autre-jeu" },
			{ VisitorId = 4, UserName = "cid", LocationType = 4, PlaceId = PLACE, GameId = JOB },
		}

		T.it("donne à chacun son statut : ici, dans le jeu, en ligne, hors ligne", function()
			local list = Rules.merge(all, online, PLACE, JOB, { [4] = true })
			T.expectEqual(find(list, 4).status, "here")
			T.expectEqual(find(list, 2).status, "game")
			T.expectEqual(find(list, 2).jobId, "job-ailleurs")
			T.expectEqual(find(list, 3).status, "online", "dans un autre jeu")
			T.expectEqual(find(list, 1).status, "offline")
		end)

		T.it("trie du plus proche au plus lointain, puis par nom", function()
			local list = Rules.merge(all, online, PLACE, JOB, { [4] = true })
			local names = {}
			for _, friend in list do
				table.insert(names, friend.name)
			end
			T.expectEqual(table.concat(names, ","), "Cid,amy,Bob,Dan,Zed")
		end)

		T.it("un ami sur mobile ou Xbox dans ce jeu est « dans le jeu »", function()
			local mobile = { { VisitorId = 9, UserName = "gus", LocationType = 1, PlaceId = PLACE, GameId = "job-m" } }
			T.expectEqual(Rules.merge({}, mobile, PLACE, JOB, {})[1].status, "game", "mobile")
			local xbox = { { VisitorId = 9, UserName = "gus", LocationType = 5, PlaceId = PLACE, GameId = "job-x" } }
			T.expectEqual(Rules.merge({}, xbox, PLACE, JOB, {})[1].status, "game", "Xbox")
			local studio = { { VisitorId = 9, UserName = "gus", LocationType = 3, PlaceId = PLACE, GameId = "job-s" } }
			T.expectEqual(Rules.merge({}, studio, PLACE, JOB, {})[1].status, "online", "Studio")
		end)

		T.it("prend le nom d'utilisateur sans nom affiché", function()
			local list = Rules.merge(all, online, PLACE, JOB, {})
			T.expectEqual(find(list, 2).name, "amy")
		end)

		T.it("un ami sur ce serveur est « ici » même sans GameId (confidentialité)", function()
			local list = Rules.merge({ { Id = 7, Username = "eve" } }, {}, PLACE, JOB, { [7] = true })
			T.expectEqual(find(list, 7).status, "here")
		end)

		T.it("un ami dans ce jeu sur ce serveur n'est pas à téléporter", function()
			local list = Rules.merge(all, online, PLACE, JOB, {})
			T.expectEqual(
				find(list, 4).status,
				"online",
				"GameId = ce serveur mais absent des joueurs : pas « dans le jeu »"
			)
		end)

		T.it("ajoute un ami en ligne absent de la première liste, ignore les entrées illisibles", function()
			local list = Rules.merge(
				{ "x", { Id = "1" } },
				{ { VisitorId = 8, UserName = "fay", LocationType = 2 } },
				PLACE,
				JOB,
				{}
			)
			T.expectEqual(#list, 1)
			T.expectEqual(list[1].status, "online")
		end)
	end)

	T.describe("FriendRules.action", function()
		T.it("REJOINDRE un ami dans le jeu, ici ou ailleurs", function()
			T.expectEqual((Rules.action({ id = 1, name = "a", status = "here" }, ctx())), "follow")
			local action, enabled = Rules.action({ id = 1, name = "a", status = "game", jobId = "j" }, ctx())
			T.expectEqual(action, "follow")
			T.expectEqual(enabled, true)
		end)

		T.it("INVITER un ami en ligne ou hors ligne", function()
			T.expectEqual((Rules.action({ id = 1, name = "a", status = "online" }, ctx())), "invite")
			local action, enabled = Rules.action({ id = 1, name = "a", status = "offline" }, ctx())
			T.expectEqual(action, "invite")
			T.expectEqual(enabled, true)
		end)

		T.it("aucune action pour un ami déjà dans le groupe", function()
			local action = Rules.action({ id = 1, name = "a", status = "here" }, ctx({ partyIds = { [1] = true } }))
			T.expectEqual(action, nil)
			T.expectEqual(
				Rules.statusLabel({ id = 1, name = "a", status = "here" }, ctx({ partyIds = { [1] = true } })),
				Rules.IN_PARTY_LABEL
			)
		end)

		T.it("Studio : invitation et téléportation impossibles, REJOINDRE sur ce serveur possible", function()
			local studio = ctx({ studio = true })
			local _, enabledInvite, reason = Rules.action({ id = 1, name = "a", status = "online" }, studio)
			T.expectEqual(enabledInvite, false)
			T.expectEqual(reason, "studio")
			local _, enabledFollow = Rules.action({ id = 1, name = "a", status = "game", jobId = "j" }, studio)
			T.expectEqual(enabledFollow, false)
			local _, enabledHere = Rules.action({ id = 1, name = "a", status = "here" }, studio)
			T.expectEqual(enabledHere, true)
		end)

		T.it("invitation refusée par Roblox ou serveur plein : désactivée avec sa raison", function()
			local _, enabled, reason =
				Rules.action({ id = 1, name = "a", status = "online" }, ctx({ canInvite = false }))
			T.expectEqual(enabled, false)
			T.expectEqual(reason, "refused")
			_, enabled, reason = Rules.action({ id = 1, name = "a", status = "online" }, ctx({ serverFull = true }))
			T.expectEqual(enabled, false)
			T.expectEqual(reason, "full")
		end)

		T.it("droit d'inviter pas encore connu : le clic le redemande", function()
			local _, enabled = Rules.action({ id = 1, name = "a", status = "online" }, ctx({ canInvite = nil }))
			T.expectEqual(enabled, true)
		end)
	end)

	T.describe("FriendRules.reasons", function()
		T.it("une ligne par raison, sans doublon, dans l'ordre", function()
			local friends = {
				{ id = 1, name = "a", status = "online" },
				{ id = 2, name = "b", status = "offline" },
				{ id = 3, name = "c", status = "game", jobId = "j" },
			}
			local lines = Rules.reasons(friends, ctx({ studio = true }))
			T.expectEqual(#lines, 1)
			T.expectEqual(lines[1], Rules.REASONS.studio)
			T.expectEqual(#Rules.reasons(friends, ctx()), 0, "tout possible")
		end)
	end)

	T.describe("FriendRules.debugEntries", function()
		T.it("liste les joueurs du serveur ici, puis un ami de chaque statut", function()
			local all, online = Rules.debugEntries({ { id = -2, name = "Player2" } }, PLACE)
			local list = Rules.merge(all, online, PLACE, JOB, { [-1] = true, [-2] = true })
			T.expectEqual(list[1].id, -2)
			T.expectEqual(list[1].status, "here")
			local statuses = {}
			for _, friend in list do
				statuses[friend.status] = (statuses[friend.status] or 0) + 1
			end
			T.expectEqual(statuses.game, 1)
			T.expectEqual(statuses.online, 1)
			T.expectEqual(statuses.offline, 1)
		end)
	end)
end

-- Lobby entre amis (#523) : groupes, hôte, présence, lancement, arrivée d'un invité, départs.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/PartyRules")

	-- Cette méthode permet de comparer deux listes d'ids sans tenir compte de l'ordre lorsqu'un test lit les joueurs à
	-- republier.
	local function sameSet(actual: { number }, expected: { number }, message: string?)
		local sortedA, sortedE = table.clone(actual), table.clone(expected)
		table.sort(sortedA)
		table.sort(sortedE)
		T.expectEqual(table.concat(sortedA, ","), table.concat(sortedE, ","), message)
	end

	-- Cette méthode permet de créer un registre avec les joueurs `ids` inscrits lorsqu'un test démarre.
	local function registry(ids: { number })
		local reg = Rules.new()
		for _, id in ids do
			Rules.add(reg, id)
		end
		return reg
	end

	T.describe("PartyRules : arrivée et groupe", function()
		T.it("inscrit un joueur seul dans son groupe, hôte, au menu", function()
			local reg = registry({ 1 })
			T.expectEqual(Rules.hostOf(reg, 1), 1)
			T.expectEqual(table.concat(Rules.membersOf(reg, 1), ","), "1")
			T.expectEqual(Rules.presenceOf(reg, 1), "menu")
		end)

		T.it("fait entrer un invité dans le groupe de l'hôte, hôte inchangé", function()
			local reg = registry({ 1, 2 })
			local result, changed = Rules.join(reg, 2, 1)
			T.expectEqual(result, "ok")
			T.expectEqual(Rules.hostOf(reg, 2), 1)
			T.expectEqual(table.concat(Rules.membersOf(reg, 1), ","), "1,2", "hôte en premier, puis l'arrivant")
			sameSet(changed, { 1, 2 })
		end)

		T.it("rejoint le groupe d'un ami membre (pas l'hôte) : même groupe que lui", function()
			local reg = registry({ 1, 2, 3 })
			Rules.join(reg, 2, 1)
			T.expectEqual((Rules.join(reg, 3, 2)), "ok")
			T.expectEqual(Rules.hostOf(reg, 3), 1)
			T.expectEqual(table.concat(Rules.membersOf(reg, 1), ","), "1,2,3")
		end)

		T.it("refuse de se rejoindre soi-même, un ami absent ou un groupe déjà commun", function()
			local reg = registry({ 1, 2 })
			T.expectEqual((Rules.join(reg, 1, 1)), "self")
			T.expectEqual((Rules.join(reg, 1, 99)), "unknown", "ami pas sur le serveur")
			T.expectEqual((Rules.join(reg, 99, 1)), "unknown", "joueur pas inscrit")
			Rules.join(reg, 2, 1)
			T.expectEqual((Rules.join(reg, 1, 2)), "already")
			T.expectEqual(Rules.hostOf(reg, 1), 1, "rien changé")
		end)

		T.it("un hôte qui rejoint un autre groupe transmet le sien au membre suivant", function()
			local reg = registry({ 1, 2, 3 })
			Rules.join(reg, 2, 1)
			local result, changed = Rules.join(reg, 1, 3)
			T.expectEqual(result, "ok")
			T.expectEqual(Rules.hostOf(reg, 2), 2, "2 devient hôte de l'ancien groupe")
			T.expectEqual(Rules.hostOf(reg, 1), 3)
			T.expectEqual(table.concat(Rules.membersOf(reg, 3), ","), "3,1")
			sameSet(changed, { 2, 3, 1 })
		end)
	end)

	T.describe("PartyRules : départs", function()
		T.it("déconnexion de l'hôte : le membre suivant devient hôte, sans blocage", function()
			local reg = registry({ 1, 2, 3 })
			Rules.join(reg, 2, 1)
			Rules.join(reg, 3, 1)
			local changed = Rules.remove(reg, 1)
			sameSet(changed, { 2, 3 })
			T.expectEqual(Rules.hostOf(reg, 2), 2)
			T.expectEqual(Rules.hostOf(reg, 3), 2)
			T.expectEqual(table.concat(Rules.membersOf(reg, 3), ","), "2,3")
			T.expectEqual(Rules.hostOf(reg, 1), nil)
			T.expectEqual(Rules.launchState(true, nil), "launch", "le nouvel hôte peut lancer")
		end)

		T.it("déconnexion d'un membre : l'hôte garde son groupe", function()
			local reg = registry({ 1, 2, 3 })
			Rules.join(reg, 2, 1)
			Rules.join(reg, 3, 1)
			sameSet(Rules.remove(reg, 2), { 1, 3 })
			T.expectEqual(table.concat(Rules.membersOf(reg, 1), ","), "1,3")
		end)

		T.it("déconnexion d'un joueur seul : rien à republier", function()
			local reg = registry({ 1 })
			T.expectEqual(#Rules.remove(reg, 1), 0)
			T.expectEqual(Rules.hostOf(reg, 1), nil)
		end)

		T.it("QUITTER LE GROUPE : le joueur repart seul, hôte transmis s'il l'était", function()
			local reg = registry({ 1, 2, 3 })
			Rules.join(reg, 2, 1)
			Rules.join(reg, 3, 1)
			sameSet(Rules.leave(reg, 1), { 2, 3 })
			T.expectEqual(Rules.hostOf(reg, 1), 1, "seul, hôte de son groupe")
			T.expectEqual(table.concat(Rules.membersOf(reg, 1), ","), "1")
			T.expectEqual(Rules.hostOf(reg, 3), 2)
		end)

		T.it("QUITTER LE GROUPE seul : sans effet", function()
			local reg = registry({ 1 })
			T.expectEqual(#Rules.leave(reg, 1), 0)
			T.expectEqual(Rules.hostOf(reg, 1), 1)
		end)
	end)

	T.describe("PartyRules : lancer", function()
		T.it("un membre attend l'hôte dans le lobby ; l'hôte lance", function()
			T.expectEqual(Rules.launchState(true, "lobby"), "launch")
			T.expectEqual(Rules.launchState(false, "lobby"), "waitHost")
		end)

		T.it("un hôte au menu ou en partie ne bloque pas ses membres", function()
			T.expectEqual(Rules.launchState(false, "menu"), "launch", "hôte revenu au menu")
			T.expectEqual(Rules.launchState(false, "game"), "launch", "hôte en partie : le membre le rejoint")
			T.expectEqual(Rules.launchState(false, nil), "launch", "hôte inconnu")
		end)

		T.it("LANCER de l'hôte fait entrer les seuls membres présents dans le lobby", function()
			local reg = registry({ 1, 2, 3, 4 })
			for _, id in { 2, 3, 4 } do
				Rules.join(reg, id, 1)
			end
			Rules.setPresence(reg, 1, "lobby")
			Rules.setPresence(reg, 2, "lobby")
			Rules.setPresence(reg, 3, "menu")
			Rules.setPresence(reg, 4, "game")
			sameSet(Rules.launch(reg, 1), { 2 })
			T.expectEqual(Rules.presenceOf(reg, 1), "game")
			T.expectEqual(Rules.presenceOf(reg, 2), "game")
			T.expectEqual(Rules.presenceOf(reg, 3), "menu", "au menu : pas tiré dans la manche")
		end)

		T.it("LANCER d'un hôte hors du lobby ne tire personne", function()
			local reg = registry({ 1, 2 })
			Rules.join(reg, 2, 1)
			Rules.setPresence(reg, 2, "lobby")
			Rules.setPresence(reg, 1, "game")
			T.expectEqual(#Rules.launch(reg, 1), 0)
			T.expectEqual(Rules.presenceOf(reg, 2), "lobby")
		end)

		T.it("LANCER d'un membre : lui seul entre dans la manche", function()
			local reg = registry({ 1, 2, 3 })
			Rules.join(reg, 2, 1)
			Rules.join(reg, 3, 1)
			Rules.setPresence(reg, 3, "lobby")
			T.expectEqual(#Rules.launch(reg, 2), 0)
			T.expectEqual(Rules.presenceOf(reg, 2), "game")
			T.expectEqual(Rules.presenceOf(reg, 3), "lobby")
		end)

		T.it("ignore la présence d'un joueur non inscrit", function()
			local reg = registry({})
			Rules.setPresence(reg, 5, "lobby")
			T.expectEqual(Rules.presenceOf(reg, 5), "menu")
			T.expectEqual(#Rules.launch(reg, 5), 0)
		end)
	end)

	T.describe("PartyRules : demandes et données d'arrivée", function()
		T.it("lit les demandes connues, l'id seulement pour REJOINDRE", function()
			T.expectEqual((Rules.readRequest("open", 0)), "open")
			local action, target = Rules.readRequest("follow", 42)
			T.expectEqual(action, "follow")
			T.expectEqual(target, 42)
			local _, ignored = Rules.readRequest("launch", 42)
			T.expectEqual(ignored, nil, "id ignoré hors REJOINDRE")
		end)

		T.it("refuse une demande inconnue ou un id invalide", function()
			T.expectEqual((Rules.readRequest("kick", 0)), nil)
			T.expectEqual((Rules.readRequest(nil, 0)), nil)
			T.expectEqual((Rules.readRequest("follow", 0)), nil, "id nul")
			T.expectEqual((Rules.readRequest("follow", 1.5)), nil, "id non entier")
			T.expectEqual((Rules.readRequest("follow", "42")), nil, "texte")
			T.expectEqual((Rules.readRequest("follow", math.huge)), nil, "infini")
		end)

		T.it("lit l'hôte dans les données de lancement d'une invitation", function()
			T.expectEqual(Rules.readJoinHost({ LaunchData = Rules.launchData(123) }), 123)
			T.expectEqual(Rules.readJoinHost({ LaunchData = " 77 " }), 77)
		end)

		T.it("lit l'hôte dans les données de téléportation de REJOINDRE", function()
			T.expectEqual(Rules.readJoinHost({ TeleportData = { partyHost = 456 } }), 456)
			T.expectEqual(Rules.readJoinHost({ TeleportData = { partyHost = 456 }, LaunchData = "1" }), 456)
		end)

		T.it("ignore des données d'arrivée absentes ou illisibles", function()
			T.expectEqual(Rules.readJoinHost(nil), nil)
			T.expectEqual(Rules.readJoinHost({}), nil)
			T.expectEqual(Rules.readJoinHost({ LaunchData = "" }), nil)
			T.expectEqual(Rules.readJoinHost({ LaunchData = "abc" }), nil)
			T.expectEqual(Rules.readJoinHost({ LaunchData = "-5" }), nil)
			T.expectEqual(
				Rules.readJoinHost({ TeleportData = { training = true } }),
				nil,
				"téléportation d'entraînement"
			)
			T.expectEqual(Rules.readJoinHost({ TeleportData = { partyHost = -1 } }), nil)
			T.expectEqual(Rules.readJoinHost({ TeleportData = { partyHost = 1.5 } }), nil)
		end)

		T.it("donne un message pour chaque réponse du serveur", function()
			for _, status in
				{ "teleporting", "studio", "failed", "full", "notFound", "notFriend", "busy", "hostMissing" }
			do
				T.expect(Rules.notice(status) ~= nil, status)
			end
			T.expectEqual(Rules.notice("autre"), nil)
			T.expectEqual(Rules.notice(3), nil)
		end)
	end)
end

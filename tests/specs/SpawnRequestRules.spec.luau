-- Demande d'apparition du client (#219) : renvoi sans réponse ou après un refus temporaire, abandon borné, débit
-- compatible avec la garde du serveur.
return function(T, Loader)
	local Rules = Loader.new():require("src/client/systems/game/SpawnRequestRules")
	local RemoteGuard = Loader.new():require("src/server/RemoteGuard")
	local N = Loader.new():require("src/shared/NetworkProtocol").Names

	-- Cette méthode permet de rejouer la surveillance d'une demande jusqu'à untilT lorsqu'un test simule le serveur
	-- (serverReply(n, t) : réponse ou nil, délai) ; renvoie la fin, son instant et les instants des envois.
	local function simulate(serverReply, untilT: number, hasLiveCharacter: boolean?)
		local attempt = Rules.new(0)
		local sends = {}
		local inbox = {}
		local t = 0
		while t <= untilT do
			-- Réponses arrivées
			for i = #inbox, 1, -1 do
				local item = inbox[i]
				if item.at <= t then
					table.remove(inbox, i)
					if Rules.onReply(attempt, item.answer, t, hasLiveCharacter == true) == "adopt" then
						return "adopt", t, sends
					end
				end
			end
			local action = Rules.onTick(attempt, t)
			if action == "giveUp" then
				return "giveUp", t, sends
			elseif action == "send" then
				Rules.noteSent(attempt, t)
				table.insert(sends, t)
				local answer, delay = serverReply(#sends, t)
				if answer then
					table.insert(inbox, { answer = answer, at = t + (delay or 0) })
				end
			end
			t += Rules.TICK
		end
		return "running", t, sends
	end

	T.describe("SpawnRequestRules : envoi et renvoi", function()
		T.it("envoie tout de suite, puis attend le personnage après « accepted »", function()
			local outcome, _, sends = simulate(function()
				return { status = "accepted" }, 0.1
			end, 10)
			T.expectEqual(outcome, "running")
			T.expectEqual(#sends, 1)
			T.expectEqual(sends[1], 0)
		end)

		T.it("renvoie après REPLY_TIMEOUT sans réponse (serveur figé), un seul envoi accepté suffit", function()
			local outcome, _, sends = simulate(function(index)
				if index == 1 then
					return nil -- perdue
				end
				return { status = "accepted" }, 0.2
			end, 10)
			T.expectEqual(outcome, "running")
			T.expectEqual(#sends, 2)
			T.expectNear(sends[2], Rules.REPLY_TIMEOUT, Rules.TICK)
		end)

		T.it("« spawning » (chargement déjà en vol) vaut acceptation : pas de renvoi", function()
			local _, _, sends = simulate(function()
				return { status = "spawning" }, 0
			end, 10)
			T.expectEqual(#sends, 1)
		end)

		T.it("bannière de fin : renvoi jusqu'au round suivant", function()
			local outcome, _, sends = simulate(function(_, t)
				return { status = if t < 6 then "result" else "accepted" }, 0.05
			end, 12)
			T.expectEqual(outcome, "running")
			T.expectEqual(sends[#sends] >= 6, true, "dernier envoi après la bannière")
			T.expectEqual(#sends >= 2, true)
		end)

		T.it("demande précoce : renvoi après le délai restant annoncé", function()
			local _, _, sends = simulate(function(index)
				if index == 1 then
					return { status = "early", retryIn = 2 }, 0
				end
				return { status = "accepted" }, 0
			end, 10)
			T.expectEqual(#sends, 2)
			T.expectEqual(sends[2] >= 2 + Rules.EARLY_MARGIN - 1e-9, true, "pas avant le délai")
			T.expectEqual(sends[2] < 2 + Rules.EARLY_MARGIN + 2 * Rules.TICK, true)
		end)

		T.it("échec du chargement : renvoi", function()
			local _, _, sends = simulate(function(index)
				return { status = if index == 1 then "failed" else "accepted" }, 0
			end, 10)
			T.expectEqual(#sends, 2)
		end)

		T.it("« alive » vivant pour le serveur et le client : reprise du personnage", function()
			local outcome = simulate(function()
				return { status = "alive", live = true }, 0
			end, 10, true)
			T.expectEqual(outcome, "adopt")
		end)

		T.it("« alive » vivant pour le serveur, mort pour le client : renvoi, pas de reprise", function()
			local outcome, _, sends = simulate(function(index)
				return { status = if index == 1 then "alive" else "accepted", live = true }, 0
			end, 10, false)
			T.expectEqual(outcome, "running")
			T.expectEqual(#sends, 2)
		end)

		T.it("« alive » sur un corps (mort pas encore répliquée au client) : renvoi, pas de reprise", function()
			local outcome, _, sends = simulate(function(index)
				return { status = if index == 1 then "alive" else "accepted", live = false }, 0
			end, 10, true)
			T.expectEqual(outcome, "running")
			T.expectEqual(#sends, 2)
		end)

		T.it("traite chaque statut que le serveur peut envoyer (SpawnRules.REPLY_STATUSES)", function()
			local SpawnRules = Loader.new():require("src/server/SpawnRules")
			for _, status in SpawnRules.REPLY_STATUSES do
				local attempt = Rules.new(0)
				Rules.noteSent(attempt, 0)
				local action = Rules.onReply(attempt, { status = status, retryIn = 1 }, 0.1, false)
				local handled = action == "adopt" or attempt.acceptedAt ~= nil or attempt.retryAt ~= nil
				T.expectEqual(handled, true, status)
			end
		end)

		T.it("ignore une réponse illisible", function()
			local attempt = Rules.new(0)
			Rules.noteSent(attempt, 0)
			T.expectEqual(Rules.onReply(attempt, "accepted", 0, false), "wait")
			T.expectEqual(Rules.onReply(attempt, nil, 0, false), "wait")
			T.expectEqual(attempt.unanswered, 1)
		end)
	end)

	T.describe("SpawnRequestRules : jamais bloqué en SPAWNING", function()
		T.it("abandonne après MAX_UNANSWERED envois sans réponse", function()
			local outcome, t, sends = simulate(function()
				return nil
			end, 60)
			T.expectEqual(outcome, "giveUp")
			T.expectEqual(#sends, Rules.MAX_UNANSWERED)
			T.expectEqual(t <= Rules.REPLY_TIMEOUT * Rules.MAX_UNANSWERED + Rules.TICK, true)
		end)

		T.it("abandonne si le personnage n'arrive pas après acceptation", function()
			local outcome, t = simulate(function()
				return { status = "accepted" }, 0
			end, 60)
			T.expectEqual(outcome, "giveUp")
			T.expectNear(t, Rules.LOAD_TIMEOUT, Rules.TICK)
		end)

		T.it("abandonne au plus tard après GIVE_UP_AFTER, même refusé sans fin", function()
			local outcome, t = simulate(function()
				return { status = "result" }, 0
			end, 120)
			T.expectEqual(outcome, "giveUp")
			T.expectNear(t, Rules.GIVE_UP_AFTER, Rules.TICK)
		end)

		T.it("abandonne si le remote n'existe jamais (aucun envoi possible)", function()
			local attempt = Rules.new(0)
			local t = 0
			while Rules.onTick(attempt, t) == "send" do
				t += Rules.TICK -- l'envoi n'a pas pu partir : noteSent pas appelé
			end
			T.expectEqual(Rules.onTick(attempt, t), "giveUp")
			T.expectNear(t, Rules.REPLY_TIMEOUT * Rules.MAX_UNANSWERED, Rules.TICK)
		end)

		T.it("acceptée juste avant GIVE_UP_AFTER : le chargement garde LOAD_TIMEOUT", function()
			local outcome, t = simulate(function(_, sendT)
				return { status = if sendT < Rules.GIVE_UP_AFTER - 1 then "result" else "accepted" }, 0
			end, 120)
			T.expectEqual(outcome, "giveUp")
			T.expectEqual(t > Rules.GIVE_UP_AFTER + Rules.LOAD_TIMEOUT - 2, true, "pas abandonnée à GIVE_UP_AFTER")
			T.expectEqual(t <= Rules.GIVE_UP_AFTER + Rules.LOAD_TIMEOUT + Rules.TICK, true, "borne totale")
		end)

		T.it("une réponse remet à zéro les envois sans réponse", function()
			local attempt = Rules.new(0)
			Rules.noteSent(attempt, 0)
			Rules.noteSent(attempt, 3)
			Rules.onReply(attempt, { status = "result" }, 3.1, false)
			T.expectEqual(attempt.unanswered, 0)
		end)
	end)

	T.describe("SpawnRequestRules : débit accepté par la garde du serveur", function()
		local rule = RemoteGuard.RULES[N.REQUEST_SPAWN]

		-- Cette méthode permet de vérifier qu'une suite d'envois passe toute la garde RequestSpawn lorsqu'un scénario
		-- de renvoi est rejoué.
		local function allAdmitted(sends): boolean
			local bucket = RemoteGuard.newBucket(rule.burst, 0)
			for _, t in sends do
				if not RemoteGuard.take(bucket, rule.rate, rule.burst, t) then
					return false
				end
			end
			return true
		end

		T.it("aucun renvoi n'est écarté par le débit (refus en boucle, sans réponse, précoce)", function()
			for _, status in { "result", "alive", "failed" } do
				local _, _, sends = simulate(function()
					return { status = status }, 0
				end, 40)
				T.expectEqual(allAdmitted(sends), true, status)
			end
			local _, _, silent = simulate(function()
				return nil
			end, 40)
			T.expectEqual(allAdmitted(silent), true, "sans réponse")
			local _, _, early = simulate(function()
				return { status = "early", retryIn = 0 }, 0
			end, 40)
			T.expectEqual(allAdmitted(early), true, "précoce sans délai")
		end)

		T.it("deux envois sont toujours espacés d'au moins MIN_RESEND", function()
			T.expectEqual(Rules.MIN_RESEND >= 1 / rule.rate, true)
			local _, _, sends = simulate(function()
				return { status = "early", retryIn = 0 }, 0
			end, 30)
			for i = 2, #sends do
				T.expectEqual(sends[i] - sends[i - 1] >= Rules.MIN_RESEND - 1e-9, true, "envoi " .. i)
			end
		end)
	end)

	T.describe("SpawnRequestRules : attente en DEAD (#245)", function()
		local WAIT_FOR = 2.5 + 3

		-- Cette méthode permet de rejouer l'attente en DEAD jusqu'à untilT lorsqu'un test simule le serveur
		-- (characterAt : instant d'arrivée du personnage ou nil ; serverReply(n, t) comme simulate) ; renvoie la fin,
		-- son instant et les instants des envois.
		local function simulateDead(characterAt: number?, serverReply, untilT: number)
			local watch = Rules.newDeadWatch(0)
			local sends = {}
			local inbox = {}
			local t = 0
			while t <= untilT do
				if characterAt and t >= characterAt then
					return "respawned", t, sends
				end
				for i = #inbox, 1, -1 do
					local item = inbox[i]
					if item.at <= t then
						table.remove(inbox, i)
						Rules.onReply(watch.attempt, item.answer, t, false)
					end
				end
				local action = Rules.onDeadTick(watch, t, WAIT_FOR)
				if action == "giveUp" then
					return "giveUp", t, sends
				elseif action == "send" then
					Rules.noteSent(watch.attempt, t)
					table.insert(sends, t)
					local answer, delay = serverReply(#sends, t)
					if answer then
						table.insert(inbox, { answer = answer, at = t + (delay or 0) })
					end
				end
				t += Rules.TICK
			end
			return "running", t, sends
		end

		T.it("cas nominal : réapparition du serveur avant la marge, aucune redemande", function()
			local outcome, _, sends = simulateDead(2.5 + 0.8, function()
				error("pas de redemande attendue")
			end, 30)
			T.expectEqual(outcome, "respawned")
			T.expectEqual(#sends, 0)
		end)

		T.it("attend sans rien envoyer jusqu'à RESPAWN_DELAY + marge", function()
			local watch = Rules.newDeadWatch(10)
			for t = 10, 10 + WAIT_FOR - 0.01, Rules.TICK do
				T.expectEqual(Rules.onDeadTick(watch, t, WAIT_FOR), "wait")
			end
			T.expectEqual(watch.attempt, nil)
		end)

		T.it("dépassement : une seule redemande, puis le personnage arrive", function()
			local outcome, _, sends = simulateDead(WAIT_FOR + 1, function()
				return { status = "accepted" }, 0.1
			end, 30)
			T.expectEqual(outcome, "respawned")
			T.expectEqual(#sends, 1)
			T.expectNear(sends[1], WAIT_FOR, Rules.TICK)
		end)

		T.it("redemande échouée (chargement en échec) : retour au menu après DEAD_GIVE_UP_AFTER", function()
			local outcome, t, sends = simulateDead(nil, function()
				return { status = "failed" }, 0.05
			end, 120)
			T.expectEqual(outcome, "giveUp")
			T.expectNear(t, WAIT_FOR + Rules.DEAD_GIVE_UP_AFTER, Rules.TICK)
			T.expectEqual(#sends >= 2, true, "renvoyée après l'échec")
		end)

		T.it("redemande sans réponse : retour au menu borné", function()
			local outcome, t = simulateDead(nil, function()
				return nil
			end, 120)
			T.expectEqual(outcome, "giveUp")
			T.expectEqual(t <= WAIT_FOR + Rules.DEAD_GIVE_UP_AFTER + Rules.TICK, true)
		end)

		T.it("redemande acceptée sans personnage : retour au menu après LOAD_TIMEOUT", function()
			local outcome, t = simulateDead(nil, function()
				return { status = "accepted" }, 0
			end, 120)
			T.expectEqual(outcome, "giveUp")
			T.expectNear(t, WAIT_FOR + Rules.LOAD_TIMEOUT, Rules.TICK)
		end)

		T.it("la borne courte ne touche pas une demande lancée par JOUER", function()
			T.expectEqual(Rules.new(0).giveUpAfter, Rules.GIVE_UP_AFTER)
			T.expectEqual(Rules.DEAD_GIVE_UP_AFTER < Rules.GIVE_UP_AFTER, true)
		end)

		T.it("débit de la redemande accepté par la garde du serveur", function()
			local rule = RemoteGuard.RULES[N.REQUEST_SPAWN]
			local _, _, sends = simulateDead(nil, function()
				return { status = "failed" }, 0
			end, 60)
			local bucket = RemoteGuard.newBucket(rule.burst, 0)
			for _, t in sends do
				T.expectEqual(RemoteGuard.take(bucket, rule.rate, rule.burst, t), true, "envoi à " .. t)
			end
		end)
	end)
end

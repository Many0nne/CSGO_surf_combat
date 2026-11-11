-- Demande d'apparition du client (#219) : renvoi sans réponse ou après un refus temporaire, abandon borné, débit
-- compatible avec la garde du serveur.
return function(T, Loader)
	local Rules = Loader.new():require("src/client/systems/game/SpawnRequestRules")
	local RemoteGuard = Loader.new():require("src/server/RemoteGuard")
	local N = Loader.new():require("src/shared/NetworkProtocol").Names

	-- Cette méthode permet de simuler la surveillance d'une demande de 0 à untilT lorsqu'un test rejoue un échange ;
	-- serverReply(sendIndex, t) renvoie la réponse à un envoi (nil : perdue) et son délai d'arrivée. Renvoie la fin
	-- ("giveUp", "adopt" ou "running"), l'instant de la fin et les instants des envois.
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

		T.it("« alive » avec un personnage local vivant : reprise du personnage", function()
			local outcome = simulate(function()
				return { status = "alive" }, 0
			end, 10, true)
			T.expectEqual(outcome, "adopt")
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
end

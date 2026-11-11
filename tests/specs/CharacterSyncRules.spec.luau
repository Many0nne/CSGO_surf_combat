return function(T, Loader)
	local Rules = Loader.new():require("src/shared/CharacterSyncRules")
	local MovementConfig = Loader.new():require("src/shared/MovementConfig")

	T.describe("CharacterSyncRules.isWellFormed", function()
		T.it("accepte un Vector3 et un angle finis", function()
			T.expectEqual(Rules.isWellFormed(Vector3.new(1, 2, 3), 0.5), true)
		end)

		T.it("rejette une valeur forgée, infinie ou NaN", function()
			T.expectEqual(Rules.isWellFormed({ X = 1, Y = 2, Z = 3 }, 0), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(0 / 0, 0, 0), 0), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(math.huge, 0, 0), 0), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(0, 0, 0), "0"), false)
			T.expectEqual(Rules.isWellFormed(Vector3.new(0, 0, 0), 0 / 0), false)
		end)
	end)

	T.describe("CharacterSyncRules.tryMove (seau de distance, #172)", function()
		local maxSpeed = MovementConfig.MAX_SPEED_SERVER
		local cap = MovementConfig.MAX_DELTA_POS
		local interval = Rules.SEND_INTERVAL

		-- Cette méthode permet de rejouer une suite de paquets (heure d'arrivée serveur, position annoncée) lorsqu'un
		-- test simule un client : renvoie le nombre de refus et la dernière position acceptée (point de départ en 0).
		local function replay(packets: { { t: number, pos: Vector3 } }): (number, Vector3)
			local budget = Rules.newBudget(0)
			local lastPos = Vector3.zero
			local refused = 0
			for _, packet in packets do
				if Rules.tryMove(budget, lastPos, packet.pos, packet.t) then
					lastPos = packet.pos
				else
					refused += 1
				end
			end
			return refused, lastPos
		end

		-- Cette méthode permet de produire une gigue pseudo-aléatoire reproductible (0..1) lorsqu'un test décale
		-- l'arrivée des paquets.
		local seed = 12345
		local function noise(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end

		T.it("accepte 300 studs/s soutenus à 20 Hz pendant 10 s", function()
			local packets = {}
			for i = 1, 200 do
				table.insert(packets, { t = i * interval, pos = Vector3.new(maxSpeed * i * interval, 0, 0) })
			end
			T.expectEqual((replay(packets)), 0)
		end)

		T.it("accepte un surf à 220 studs/s qui descend, avec une gigue réseau jusqu'à 80 ms", function()
			local packets = {}
			local arrival = 0
			for i = 1, 400 do
				local sentAt = i * interval
				-- Arrivée retardée de 0 à 80 ms, jamais avant le paquet précédent (ordre conservé)
				arrival = math.max(arrival, sentAt + noise() * 0.08)
				local pos = Vector3.new(200 * sentAt, -90 * sentAt, 20 * sentAt)
				table.insert(packets, { t = arrival, pos = pos })
			end
			T.expectEqual((replay(packets)), 0)
		end)

		T.it("accepte des paquets groupés : 0,2 s de paquets arrivés d'un coup à 250 studs/s", function()
			local packets = {}
			for i = 1, 40 do
				local sentAt = i * interval
				-- Les paquets 10 à 13 restent bloqués et arrivent en même temps que le 14e
				local arrival = if i >= 10 and i <= 13 then 14 * interval else sentAt
				table.insert(packets, { t = arrival, pos = Vector3.new(250 * sentAt, 0, 0) })
			end
			T.expectEqual((replay(packets)), 0)
		end)

		T.it(
			"accepte une rafale légitime : 1 s à 40 Hz à 280 studs/s (paquets en double, débit de la garde)",
			function()
				local packets = {}
				for i = 1, 40 do
					local t = i * interval / 2
					table.insert(packets, { t = t, pos = Vector3.new(280 * t, 0, 0) })
				end
				T.expectEqual((replay(packets)), 0)
			end
		)

		T.it(
			"borne un tricheur à 300 studs/s, quel que soit son débit (ancienne faille : 400 à 800 studs/s)",
			function()
				for _, rate in { 20, 40 } do
					local budget = Rules.newBudget(0)
					local lastPos = Vector3.zero
					for i = 1, rate * 10 do
						-- Il annonce 20 studs par paquet (800 studs/s à 40 Hz) depuis sa dernière position acceptée
						local target = lastPos + Vector3.new(20, 0, 0)
						if Rules.tryMove(budget, lastPos, target, i / rate) then
							lastPos = target
						end
					end
					T.expect(
						lastPos.X <= maxSpeed * 10 + cap,
						string.format("%d Hz : %.0f studs en 10 s", rate, lastPos.X)
					)
				end
			end
		)

		T.it("refuse une téléportation après un silence, quelle que soit sa durée", function()
			for _, silence in { 1, 5, 60 } do
				local budget = Rules.newBudget(0)
				local jump = Vector3.new(maxSpeed * silence, 0, 0)
				T.expectEqual(Rules.tryMove(budget, Vector3.zero, jump, silence), false, silence .. " s de silence")
			end
		end)

		T.it("plafonne le budget après un silence à MAX_DELTA_POS + MAX_SPEED_SERVER × MAX_SILENCE", function()
			local limit = cap + maxSpeed * MovementConfig.MAX_SILENCE
			T.expectEqual(Rules.tryMove(Rules.newBudget(0), Vector3.zero, Vector3.new(limit - 0.1, 0, 0), 10), true)
			T.expectEqual(Rules.tryMove(Rules.newBudget(0), Vector3.zero, Vector3.new(limit + 0.1, 0, 0), 10), false)
		end)

		T.it("n'accumule rien pendant une suite de refus (l'ancienne règle finissait par accepter)", function()
			local budget = Rules.newBudget(0)
			local far = Vector3.new(300, 0, 0)
			for i = 1, 100 do
				T.expectEqual(Rules.tryMove(budget, Vector3.zero, far, i * interval), false, "paquet " .. i)
			end
		end)

		T.it("garde au plus MAX_DELTA_POS de côté après une longue immobilité", function()
			local budget = Rules.newBudget(0)
			for i = 1, 100 do
				Rules.tryMove(budget, Vector3.zero, Vector3.zero, i * interval)
			end
			T.expectEqual(budget.stored, cap)
		end)

		T.it("laisse repartir un client corrigé : arrêté à la position acceptée, il reprend sans refus", function()
			local budget = Rules.newBudget(0)
			local accepted = Vector3.new(100, 0, 0)
			local lastPos = accepted
			-- Paquet refusé à t = 1 (téléport), correction appliquée après un aller-retour de 0,3 s, puis le client
			-- repart à l'arrêt depuis la position acceptée : course à 30 studs/s, chute libre (gravité 110).
			T.expectEqual(Rules.tryMove(budget, lastPos, Vector3.new(900, 0, 0), 1), false)
			for i = 1, 40 do
				local dt = i * interval
				local pos = accepted + Vector3.new(30 * dt, -55 * dt * dt, 0)
				T.expectEqual(Rules.tryMove(budget, lastPos, pos, 1.3 + dt), true, "paquet " .. i)
				lastPos = pos
			end
		end)
	end)

	T.describe("CharacterSyncRules.awaitsAck", function()
		T.it("n'ignore rien sans correction en attente", function()
			T.expectEqual(Rules.awaitsAck(nil, 0), false)
		end)

		T.it("ignore les paquets envoyés avant d'avoir appliqué la correction, pas les suivants", function()
			T.expectEqual(Rules.awaitsAck(3, 2), true)
			T.expectEqual(Rules.awaitsAck(3, 3), false)
			T.expectEqual(Rules.awaitsAck(3, 7), false, "un numéro forgé ne fait que reprendre la validation")
		end)
	end)

	T.describe("CharacterSyncRules.yawOf", function()
		T.it("retrouve l'angle d'une rotation autour de Y", function()
			for _, angle in { 0, 0.7, -2.5, math.pi / 2 } do
				T.expectNear(Rules.yawOf(CFrame.Angles(0, angle, 0).LookVector), angle, 1e-5)
			end
		end)
	end)

	T.describe("CharacterSyncRules.push", function()
		T.it("ignore un paquet en retard et borne la taille du tampon", function()
			local buffer = {}
			Rules.push(buffer, { t = 1, pos = Vector3.zero, yaw = 0 })
			Rules.push(buffer, { t = 0.5, pos = Vector3.one, yaw = 0 })
			T.expectEqual(#buffer, 1)
			for i = 2, Rules.BUFFER_SIZE + 5 do
				Rules.push(buffer, { t = i, pos = Vector3.zero, yaw = 0 })
			end
			T.expectEqual(#buffer, Rules.BUFFER_SIZE)
			T.expectEqual(buffer[#buffer].t, Rules.BUFFER_SIZE + 5)
		end)
	end)

	T.describe("CharacterSyncRules.sample", function()
		local buffer = {
			{ t = 1, pos = Vector3.new(0, 0, 0), yaw = 0 },
			{ t = 2, pos = Vector3.new(10, 0, 0), yaw = 1 },
		}

		T.it("interpole entre les deux paquets qui encadrent l'instant", function()
			local pos, yaw = Rules.sample(buffer, 1.25)
			T.expectNear(pos.X, 2.5, 1e-5)
			T.expectNear(yaw, 0.25, 1e-5)
		end)

		T.it("reste sur les extrémités sans extrapoler", function()
			T.expectNear(Rules.sample(buffer, 0).X, 0, 1e-5)
			T.expectNear(Rules.sample(buffer, 5).X, 10, 1e-5)
		end)

		T.it("tourne par le plus court chemin au passage de ±π", function()
			local wrap = {
				{ t = 0, pos = Vector3.zero, yaw = math.pi - 0.1 },
				{ t = 1, pos = Vector3.zero, yaw = -math.pi + 0.1 },
			}
			local _, yaw = Rules.sample(wrap, 0.5)
			T.expectNear(math.abs(yaw), math.pi, 1e-5)
		end)

		T.it("ne renvoie rien sans paquet", function()
			T.expectEqual(Rules.sample({}, 1), nil)
		end)
	end)
end

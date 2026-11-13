-- Comportement des bots (#141) : perception, mémoire, cible, états, destinations, biais, regard en combat.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/BotBehaviorRules")
	local Config = Loader.new():require("src/shared/BotConfig")

	-- Cette méthode permet de rejouer une suite de tirages fixe lorsqu'un test a besoin de hasard.
	local function sequence(values: { number }): () -> number
		local i = 0
		return function()
			i = i % #values + 1
			return values[i]
		end
	end

	local function wp(x: number, score: number, cover: number?)
		return { position = Vector3.new(x, 0, 0), score = score, cover = cover or 0 }
	end

	T.describe("BotBehaviorRules", function()
		T.it("voit seulement dans son champ de vision", function()
			local eye = Vector3.zero
			-- Cap 0 : regarde vers -Z
			T.expectEqual(Rules.inFieldOfView(eye, 0, Vector3.new(0, 0, -10), 100), true, "droit devant")
			T.expectEqual(Rules.inFieldOfView(eye, 0, Vector3.new(0, 0, 10), 100), false, "derrière")
			T.expectEqual(Rules.inFieldOfView(eye, 0, Vector3.new(10, 0, -10), 100), true, "45° : dans les 50°")
			T.expectEqual(Rules.inFieldOfView(eye, 0, Vector3.new(10, 0, -5), 100), false, "63° : hors champ")
			T.expectEqual(Rules.inFieldOfView(eye, 350, Vector3.new(1, 0, -10), 100), true, "passe par 0")
			T.expectEqual(Rules.inFieldOfView(eye, 90, Vector3.new(10, 50, 0), 100), true, "hauteur ignorée")
		end)

		T.it("entend un tir à portée, à position approximative", function()
			local listener = Vector3.zero
			local shooter = Vector3.new(100, 0, 0)
			T.expectEqual(Rules.heardPosition(listener, Vector3.new(500, 0, 0), 200, 0.2, sequence({ 0.5 })), nil)
			for _, roll in { 0, 0.3, 0.99 } do
				local heard = Rules.heardPosition(listener, shooter, 200, 0.2, sequence({ roll, 0.7 })) :: Vector3
				T.expectEqual((heard - shooter).Magnitude <= 20 + 1e-6, true, "au plus 20 % de la distance")
			end
			local exact = Rules.heardPosition(listener, shooter, 200, 0, sequence({ 0.9 })) :: Vector3
			T.expectEqual((exact - shooter).Magnitude < 1e-6, true, "sans flou : position exacte")
		end)

		T.it("garde la dernière position connue et oublie après le délai", function()
			local memory = {}
			Rules.remember(memory, 1, Vector3.new(1, 0, 0), 10, true, true)
			Rules.remember(memory, 1, Vector3.new(9, 0, 0), 10, false, true)
			T.expectEqual(memory[1].position.X, 1, "un tir entendu au même instant ne remplace pas la vue")
			Rules.remember(memory, 1, Vector3.new(5, 0, 0), 12, false, true)
			T.expectEqual(memory[1].position.X, 5, "un tir plus récent la remplace")
			Rules.remember(memory, 2, Vector3.new(2, 0, 0), 14, true, false)
			local freshest = Rules.forget(memory, 15, 8)
			T.expectEqual(freshest and freshest.position.X, 2, "souvenir le plus récent")
			T.expectEqual(Rules.forget(memory, 21, 8) and memory[1], nil, "contact de 12 oublié à 21")
			T.expectEqual(Rules.forget(memory, 30, 8), nil, "mémoire vide")
		end)

		T.it("préfère un humain, puis la cible la plus proche", function()
			T.expectEqual(Rules.pickTarget({}), nil)
			local target = Rules.pickTarget({
				{ id = -1, isHuman = false, distance = 10 },
				{ id = 7, isHuman = true, distance = 80 },
				{ id = 8, isHuman = true, distance = 40 },
			})
			T.expectEqual(target and target.id, 8)
		end)

		T.it("ne préfère un humain que s'il est à moins de HUMAN_PREF_RANGE (#298)", function()
			local range = Config.HUMAN_PREF_RANGE
			local near = Rules.pickTarget({
				{ id = -1, isHuman = false, distance = 10 },
				{ id = 7, isHuman = true, distance = range },
			})
			T.expectEqual(near and near.id, 7, "humain au seuil : préféré au bot plus proche")
			local far = Rules.pickTarget({
				{ id = 7, isHuman = true, distance = range + 1 },
				{ id = -1, isHuman = false, distance = 10 },
			})
			T.expectEqual(far and far.id, -1, "humain au-delà du seuil : le plus proche l'emporte")
			local closer = Rules.pickTarget({
				{ id = -1, isHuman = false, distance = range + 50 },
				{ id = 7, isHuman = true, distance = range + 10 },
			})
			T.expectEqual(closer and closer.id, 7, "au-delà du seuil, un humain plus proche reste choisi")
			local twoHumans = Rules.pickTarget({
				{ id = 8, isHuman = true, distance = range + 5 },
				{ id = 7, isHuman = true, distance = range - 5 },
				{ id = -1, isHuman = false, distance = 1 },
			})
			T.expectEqual(twoHumans and twoHumans.id, 7, "humain proche avant bot et humain lointain")
		end)

		T.it("garde l'humain visé un peu au-delà du seuil, pas de va-et-vient (#298)", function()
			local range, margin = Config.HUMAN_PREF_RANGE, Config.HUMAN_PREF_MARGIN
			local candidates = {
				{ id = -1, isHuman = false, distance = 10 },
				{ id = 7, isHuman = true, distance = range + margin / 2 },
			}
			T.expectEqual((Rules.pickTarget(candidates) :: any).id, -1, "pas encore visé : le bot proche")
			T.expectEqual((Rules.pickTarget(candidates, 7) :: any).id, 7, "déjà visé : gardé dans la marge")
			candidates[2].distance = range + margin + 1
			T.expectEqual((Rules.pickTarget(candidates, 7) :: any).id, -1, "au-delà de la marge : lâché")
			-- Au-delà du seuil, à distances presque égales : la cible actuelle reste choisie
			local far = range + 30
			local even = {
				{ id = 7, isHuman = true, distance = far + 2 },
				{ id = -1, isHuman = false, distance = far },
			}
			T.expectEqual(
				(Rules.pickTarget(even, 7) :: any).id,
				7,
				"humain visé gardé face à un bot à peine plus proche"
			)
			T.expectEqual((Rules.pickTarget(even, -1) :: any).id, -1, "bot visé gardé de même")
			even[1].distance = far - margin - 1
			T.expectEqual((Rules.pickTarget(even, -1) :: any).id, 7, "nettement plus proche : il change de cible")
		end)

		T.it("ne préfère pas un humain encore dans son délai de grâce (#298)", function()
			local target = Rules.pickTarget({
				{ id = 7, isHuman = true, distance = 50, inGrace = true },
				{ id = -1, isHuman = false, distance = 20 },
			})
			T.expectEqual(target and target.id, -1, "en grâce : plus de préférence, le bot plus proche l'emporte")
			local graceOver = Rules.pickTarget({
				{ id = 7, isHuman = true, distance = 50, inGrace = false },
				{ id = -1, isHuman = false, distance = 20 },
			})
			T.expectEqual(graceOver and graceOver.id, 7, "grâce finie : l'humain proche repasse avant")
			local alone = Rules.pickTarget({ { id = 7, isHuman = true, distance = 20, inGrace = true } })
			T.expectEqual(alone and alone.id, 7, "seul candidat : reste la cible")
		end)

		T.it("garde un instant une cible sortie du champ, puis ne la poursuit que parfois", function()
			T.expectEqual(Rules.keepTarget(10, 10 + Config.TARGET_KEEP_TIME), true)
			T.expectEqual(Rules.keepTarget(10, 10 + Config.TARGET_KEEP_TIME + 0.1), false)
			T.expectEqual(Rules.investigateLost(0), Config.LOST_CHASE_CHANCE > 0)
			T.expectEqual(Rules.investigateLost(0.999), Config.LOST_CHASE_CHANCE >= 1)
		end)

		T.it("choisit son état", function()
			local base = {
				state = "chercher",
				hasTarget = false,
				freshest = nil,
				investigated = -math.huge,
				wantsReplace = false,
				replaceDone = true,
				investigateDone = true,
			}
			local function with(changes)
				local input = table.clone(base)
				for k, v in changes do
					input[k] = v
				end
				return Rules.nextState(input)
			end
			local memory = { position = Vector3.zero, at = 5, seen = false, isHuman = true }
			T.expectEqual(with({}), "chercher", "aucune information")
			T.expectEqual(with({ hasTarget = true, wantsReplace = true }), "combattre", "voir prime")
			T.expectEqual(with({ freshest = memory }), "enqueter", "tir entendu")
			T.expectEqual(with({ freshest = memory, investigated = 5 }), "chercher", "contact déjà fouillé")
			T.expectEqual(
				with({ state = "enqueter", freshest = memory, investigated = 5, investigateDone = false }),
				"enqueter",
				"fouille en cours"
			)
			T.expectEqual(with({ wantsReplace = true, freshest = memory }), "replacer", "repli avant l'enquête")
			T.expectEqual(with({ state = "replacer", replaceDone = false }), "replacer", "repli en cours")
			T.expectEqual(with({ state = "replacer", replaceDone = true }), "chercher", "repli terminé")
		end)

		T.it("se replace quand le duel est perdu d'avance", function()
			T.expectEqual(Rules.duelLost(30, 100), true)
			T.expectEqual(Rules.duelLost(80, 100), false)
			T.expectEqual(Rules.duelLost(0, 100), false, "mort : rien à faire")
		end)

		T.it("répartit les destinations : passage récent, autres bots, distance", function()
			local points = { wp(10, 1), wp(20, 1), wp(30, 0.2) }
			local ctx = {
				from = Vector3.zero,
				lastVisit = { [1] = 100 },
				claimed = { [2] = 1 },
				now = 110,
				avoid = nil,
				biasCenter = nil,
			}
			T.expectEqual(Rules.pickDestination(points, ctx, sequence({ 0 })), 3, "1 visité, 2 déjà pris")
			ctx.lastVisit = {}
			ctx.claimed = {}
			T.expectEqual(Rules.pickDestination(points, ctx, sequence({ 0 })), 1, "à note égale, le plus proche")
			ctx.avoid = 1
			T.expectEqual(Rules.pickDestination(points, ctx, sequence({ 0 })), 2, "pas le point où il est")
			local recent = Rules.destinationScore(1, points[1], {
				from = Vector3.zero,
				lastVisit = { [1] = 100 },
				claimed = {},
				now = 100 + Config.DEST_RECENT_TIME,
				avoid = nil,
				biasCenter = nil,
			}, 0)
			local fresh = Rules.destinationScore(
				1,
				points[1],
				{ from = Vector3.zero, lastVisit = {}, claimed = {}, now = 0, avoid = nil, biasCenter = nil },
				0
			)
			T.expectEqual(math.abs(recent - fresh) < 1e-6, true, "malus de passage éteint après DEST_RECENT_TIME")
		end)

		T.it("biais vers les humains : après le délai, du côté de l'humain le plus proche", function()
			T.expectEqual(Rules.biasActive(100, 100 - Config.BIAS_DELAY + 1), false)
			T.expectEqual(Rules.biasActive(100, 100 - Config.BIAS_DELAY), Config.BIAS_DELAY > 0)
			T.expectEqual(Rules.biasCenter(Vector3.zero, {}, sequence({ 0.5 })), nil, "sans humain")
			local human = Vector3.new(300, 0, 0)
			local center =
				Rules.biasCenter(Vector3.zero, { Vector3.new(-900, 0, 0), human }, sequence({ 1, 0.25 })) :: Vector3
			T.expectEqual((center - human).Magnitude <= Config.BIAS_SPREAD + 1e-6, true, "zone autour de l'humain")
			T.expectEqual((center - human).Magnitude > 1, true, "pas sa position exacte")
			local points = { wp(-300, 1), wp(300, 0.5) }
			local ctx = { from = Vector3.zero, lastVisit = {}, claimed = {}, now = 0, avoid = nil, biasCenter = human }
			T.expectEqual(Rules.pickDestination(points, ctx, sequence({ 0 })), 2, "le biais l'emporte sur la note")
		end)

		T.it("se replie vers un point couvert, loin de la menace", function()
			local points = { wp(-40, 0, 0.9), wp(40, 0, 0.9), wp(30, 0, 0.1), wp(5, 0, 1), wp(500, 0, 1) }
			local threat = Vector3.new(100, 0, 0)
			T.expectEqual(
				Rules.pickCover(points, Vector3.zero, threat, nil, sequence({ 0 })),
				1,
				"côté opposé à la menace"
			)
			T.expectEqual(
				Rules.pickCover(points, Vector3.zero, nil, nil, sequence({ 0 })),
				1,
				"sans menace : le plus couvert à portée"
			)
			T.expectEqual(Rules.pickCover({ wp(5, 0, 1) }, Vector3.zero, nil, nil, sequence({ 0 })), nil, "trop près")
		end)

		T.it("regarde loin en tenant un angle", function()
			local from = Vector3.zero
			T.expectEqual(Rules.pickLookPoint(from, { Vector3.new(5, 0, 0) }, sequence({ 0.5 })), nil, "trop près")
			local far = Vector3.new(0, 0, 100)
			local pick = Rules.pickLookPoint(from, { Vector3.new(5, 0, 0), far }, sequence({ 0.5 }))
			T.expectEqual(pick, far)
		end)

		T.it("se tourne vers la cible le temps d'un tir, puis rend son regard à sa course", function()
			local ready = Config.REACTION_TIME + Config.COMBAT_AIM_TIME
			local looking, fire = Rules.combatGaze(0, nil)
			T.expectEqual(looking, true, "se tourne dès qu'il voit")
			T.expectEqual(fire, false, "pas de tir avant le temps de réaction")
			_, fire = Rules.combatGaze(ready, nil)
			T.expectEqual(fire, true, "tir après réaction et visée")
			looking, fire = Rules.combatGaze(ready + 0.1, 0.1)
			T.expectEqual(looking, false, "après le tir : regard rendu à la course")
			T.expectEqual(fire, false)
			looking, fire = Rules.combatGaze(5, Config.COMBAT_COOLDOWN + 0.01)
			T.expectEqual(looking, true, "revient sur la cible")
			T.expectEqual(fire, false, "visée avant de retirer")
			_, fire = Rules.combatGaze(5, Config.COMBAT_COOLDOWN + Config.COMBAT_AIM_TIME)
			T.expectEqual(fire, true, "retire")
		end)
	end)
end

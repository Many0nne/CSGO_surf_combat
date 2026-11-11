-- Règles des rampes de surf empruntées par les bots (#142) : repère d'une rampe, entrée, atterrissage, coût de
-- l'arête et choix du chemin, rejeu du trajet (position à l'instant t, vitesse sous le plafond du serveur).
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/RampRules")
	local Nav = Loader.new():require("src/shared/NavRules")
	local Config = Loader.new():require("src/shared/BotConfig")
	local Movement = Loader.new():require("src/shared/MovementConfig")

	-- Rampe d'essai comme celles de Dizzy : 130 studs le long de X, 104 dans la pente à 62°, face tournée vers −Z
	local ANGLE = math.rad(62)
	local CENTER = Vector3.new(0, 47.5, 0)
	local RAMP_CF = CFrame.new(CENTER) * CFrame.Angles(ANGLE, 0, 0)
	local RAMP_SIZE = Vector3.new(130, 0.6, 104)

	-- Cette méthode permet de donner le repère de la rampe d'essai lorsqu'un cas en a besoin.
	local function frame()
		return Rules.frameOf(RAMP_CF, RAMP_SIZE)
	end

	-- Cette méthode permet de construire un trajet rectiligne de test lorsqu'un cas rejoue un trajet : count points
	-- espacés de step, tous les dt secondes.
	local function straight(count: number, step: Vector3, dt: number)
		local points, states = {}, {}
		for i = 1, count do
			points[i] = step * (i - 1)
			states[i] = if i == 1 or i == count then Rules.GROUND else Rules.SURF
		end
		return {
			dt = dt,
			points = points,
			states = states,
			duration = (count - 1) * dt,
			entry = 1,
			exit = 2,
			ramp = 1,
			direction = 1,
			peakSpeed = step.Magnitude / dt,
		}
	end

	T.describe("RampRules", function()
		T.it("trouve le repère d'une rampe : normale de surf, longueur horizontale, montée dans la pente", function()
			local f = frame()
			T.expect(f ~= nil, "une face de surf de 130 × 104 est une rampe")
			T.expect(
				f.n.Y >= Movement.SURF_NORMAL_MIN and f.n.Y < Movement.SURF_NORMAL_Y,
				"normale dans la plage du surf"
			)
			T.expectNear(math.abs(f.u.X), 1, 1e-4, "longueur le long de X")
			T.expect(f.v.Y > 0, "v monte la pente")
			T.expectNear(f.halfU, 65, 1e-4)
			T.expectNear(f.halfV, 52, 1e-4)
			T.expectNear((f.center - CENTER):Dot(f.n), 0.3, 1e-3, "centre posé sur la face de glisse")
		end)

		T.it("écarte un sol, un mur et une petite pente", function()
			T.expectEqual(Rules.frameOf(CFrame.new(), Vector3.new(130, 1, 104)), nil, "sol plat : marchable")
			T.expectEqual(
				Rules.frameOf(CFrame.Angles(math.rad(89), 0, 0), Vector3.new(130, 1, 104)),
				nil,
				"face quasi verticale : un mur"
			)
			T.expectEqual(Rules.frameOf(RAMP_CF, Vector3.new(20, 0.6, 20)), nil, "trop petite")
		end)

		T.it("reconnaît deux pièces de la même rampe, pas deux rampes différentes", function()
			local f = frame()
			local skin = Rules.frameOf(RAMP_CF * CFrame.new(0, 0.3, 0), Vector3.new(130, 1.2, 104))
			T.expect(Rules.sameRamp(f, skin), "peau posée sur la rampe")
			local far = Rules.frameOf(RAMP_CF + Vector3.new(400, 0, 0), RAMP_SIZE)
			T.expectEqual(Rules.sameRamp(f, far), false, "autre rampe")
		end)

		T.it("mesure ce qui dépasse du bout de départ selon le sens", function()
			local f = frame()
			local eastEnd = Rules.surfacePoint(f, f.halfU, 0)
			local past = eastEnd + f.u * 5
			T.expectNear(Rules.beyondStart(f, -1, past), 5, 1e-3, "départ côté +u en allant vers −u")
			T.expectNear(Rules.beyondStart(f, 1, past), -(2 * f.halfU + 5), 1e-3, "c'est l'arrivée en allant vers +u")
		end)

		T.it("vise la rampe sous le sommet du saut, et refuse une entrée hors de la face", function()
			local f = frame()
			for _, direction in { 1, -1 } do
				local target = Rules.entryTarget(f, direction, 70)
				T.expect(target ~= nil, "sol à 70 : sur la face")
				T.expectNear(target.Y, 70 + Config.RAMP_ENTRY_RISE, 1e-3, "à RAMP_ENTRY_RISE au-dessus du sol")
				local u = Rules.toLocal(f, target)
				T.expectNear(direction * u, -(f.halfU - Config.RAMP_ENTRY_INSET), 1e-3, "près du bout de départ")
				local approach = Rules.approachPoint(f, direction, target)
				T.expectNear(Rules.beyondStart(f, direction, approach), Config.RAMP_APPROACH_OUT, 1e-3)
				local _, _, h = Rules.toLocal(f, approach)
				T.expectNear(h, Config.RAMP_APPROACH_LIFT, 1e-3, "devant la face")
			end
			T.expectEqual(Rules.entryTarget(f, 1, 200), nil, "sol au-dessus de la rampe")
			T.expectEqual(Rules.entryTarget(f, 1, -50), nil, "sol sous la rampe")
		end)

		T.it("choisit les cases d'entrée les mieux placées, écartées entre elles", function()
			local candidates = {
				{ id = 1, position = Vector3.new(0, 0, 0), score = 1 },
				{ id = 2, position = Vector3.new(2, 0, 0), score = 2 }, -- trop près de 1
				{ id = 3, position = Vector3.new(10, 0, 0), score = 3 },
				{ id = 4, position = Vector3.new(20, 0, 0), score = 0.5 },
			}
			local picked = Rules.pickEntries(candidates, 3, 6)
			T.expectEqual(table.concat(picked, ","), "4,1,3")
			T.expectEqual(#Rules.pickEntries(candidates, 1, 6), 1, "count au plus")
		end)

		T.it("donne le temps de chute jusqu'à un sol, nil s'il est hors d'atteinte", function()
			local g = -Movement.GRAVITY
			T.expectNear(Rules.fallTime(20, 0, 0), math.sqrt(40 / g), 1e-6, "chute libre de 20 studs")
			local jump = Rules.fallTime(0, Movement.JUMP_VELOCITY, 0)
			T.expectNear(jump, 2 * Movement.JUMP_VELOCITY / g, 1e-6, "saut et retour au même niveau")
			T.expectEqual(Rules.fallTime(0, 0, 10), nil, "sol plus haut, sans élan vers le haut")
		end)

		T.it("choisit la case où il retomberait en quittant la rampe (point de reprise)", function()
			local pos = Vector3.new(0, 93, 0)
			local velocity = Vector3.new(-30, 0, 0)
			local t = Rules.fallTime(93, 0, 70)
			local landX = -30 * t
			local candidates = {
				{ id = 1, position = Vector3.new(landX + 1, 70, 0) }, -- là où il retombe
				{ id = 2, position = Vector3.new(-2, 70, 0) }, -- plus près de lui, mais il la dépasse
				{ id = 3, position = Vector3.new(landX, 96, 0) }, -- plus haute que lui
				{ id = 4, position = Vector3.new(landX, 70, Config.RAMP_EXIT_RADIUS + 5) }, -- trop loin
			}
			T.expectEqual(Rules.pickLanding(pos, velocity, candidates), 1)
			-- Une case intérieure passe avant une case de bord, même un peu plus loin du point de chute
			local edge = { id = 5, position = Vector3.new(landX, 70, 0), interior = false }
			local inner = { id = 6, position = Vector3.new(landX + 4, 70, 0), interior = true }
			T.expectEqual(Rules.pickLanding(pos, velocity, { edge, inner }), 6, "case intérieure")
			T.expectEqual(Rules.pickLanding(pos, velocity, { edge }), 5, "sans case intérieure : la plus proche")
			T.expectEqual(Rules.pickLanding(pos, velocity, { candidates[3], candidates[4] }), nil, "aucune case")
			local wanted = Rules.landingVelocity(pos, velocity, candidates[2].position, 30)
			T.expectNear(wanted.X, -2 / t, 1e-4, "vitesse qui retombe sur la case visée")
			T.expect(
				Rules.landingVelocity(pos, velocity, candidates[2].position, 1).Magnitude <= 1 + 1e-6,
				"plafonnée"
			)
		end)

		T.it("dirige la vitesse horizontale par petits pas en gardant la vitesse verticale", function()
			local v = Rules.steer(Vector3.new(30, -10, 0), Vector3.new(0, 0, 30), 6)
			T.expectNear(v.Y, -10, 1e-6)
			T.expectNear((Vector3.new(v.X, 0, v.Z) - Vector3.new(30, 0, 0)).Magnitude, 6, 1e-4, "au plus maxDelta")
			local reached = Rules.steer(Vector3.new(29, 0, 0), Vector3.new(30, 0, 0), 6)
			T.expectNear(reached.X, 30, 1e-6, "atteinte quand l'écart est petit")
		end)

		T.it("garde un trajet qui traverse la rampe sous les plafonds de vitesse et de durée", function()
			T.expect(Rules.accept(5, 60, 120, 130), "trajet normal")
			T.expectEqual(Rules.accept(5, 60, 20, 130), false, "rampe à peine parcourue")
			T.expectEqual(Rules.accept(Config.RAMP_MAX_TIME + 1, 60, 120, 130), false, "trop long")
			T.expectEqual(Rules.accept(5, Config.RAMP_MAX_SPEED + 1, 120, 130), false, "trop rapide")
			T.expect(Config.RAMP_MAX_SPEED < Movement.MAX_SPEED_SERVER, "plafond des rampes sous celui du serveur")
		end)

		T.it("rejoue un trajet : position à l'instant t, vitesse, état, bornes", function()
			local traj = straight(5, Vector3.new(2, 0, 0), 0.1) -- 20 studs/s, 0,4 s
			local foot, velocity, state = Rules.sample(traj, 0.15)
			T.expectNear(foot.X, 3, 1e-4, "entre le 2e et le 3e point")
			T.expectNear(velocity.X, 20, 1e-4)
			T.expectEqual(state, Rules.SURF)
			T.expectNear(Rules.sample(traj, -1).X, 0, 1e-6, "avant le départ : premier point")
			local last, lastVelocity, lastState = Rules.sample(traj, 10)
			T.expectNear(last.X, 8, 1e-4, "après la fin : dernier point")
			T.expectNear(lastVelocity.X, 20, 1e-4, "vitesse du dernier segment")
			T.expectEqual(lastState, Rules.GROUND)
			T.expectNear(Rules.peakSpeed(traj.points, traj.dt), 20, 1e-4)
			-- Vitesse relue à chaque tick du rejeu : jamais au-dessus du plafond du serveur
			local fast = straight(40, Vector3.new(3, -1, 0), 1 / 64)
			for t = 0, fast.duration, 1 / 64 do
				local _, v = Rules.sample(fast, t)
				T.expect(v.Magnitude < Movement.MAX_SPEED_SERVER, "sous MAX_SPEED_SERVER")
			end
		end)

		T.it("résorbe l'écart de départ en RAMP_BLEND_TIME", function()
			local offset = Vector3.new(2, 0, 0)
			T.expectNear(Rules.blend(offset, 0).X, 2, 1e-6)
			T.expectNear(Rules.blend(offset, Config.RAMP_BLEND_TIME / 2).X, 1, 1e-6)
			T.expectNear(Rules.blend(offset, Config.RAMP_BLEND_TIME).Magnitude, 0, 1e-6)
			T.expectNear(Rules.blend(offset, 5).Magnitude, 0, 1e-6)
		end)

		T.it("lance le trajet seulement au sol, sur la case d'entrée", function()
			local entry = Vector3.new(10, 70, 0)
			T.expect(Rules.canStart(entry + Vector3.new(1, 0, 1), entry, true))
			T.expectEqual(Rules.canStart(entry + Vector3.new(1, 0, 1), entry, false), false, "en l'air")
			T.expectEqual(Rules.canStart(entry + Vector3.new(Config.RAMP_START_DIST + 1, 0, 0), entry, true), false)
			T.expectEqual(Rules.canStart(entry + Vector3.new(0, 10, 0), entry, true), false, "à un autre étage")
		end)
	end)

	T.describe("NavRules : arête de rampe", function()
		-- Cette méthode permet de construire un couloir en U de cases (aller en z = 0, retour en z = 8) avec une arête de
		-- rampe de a vers b de durée duration, lorsqu'un cas compare le chemin avec et sans rampe.
		local function corridor(count: number, a: number, b: number, duration: number?)
			local positions, out, outKind = {}, {}, {}
			local half = count // 2
			for i = 1, count do
				positions[i] = if i <= half then Vector3.new((i - 1) * 4, 0, 0) else Vector3.new((count - i) * 4, 0, 8)
				out[i], outKind[i] = {}, {}
			end
			for i = 1, count - 1 do
				table.insert(out[i], i + 1)
				table.insert(outKind[i], Nav.WALK)
				table.insert(out[i + 1], i)
				table.insert(outKind[i + 1], Nav.WALK)
			end
			local rampCost = {}
			if duration then
				table.insert(out[a], b)
				table.insert(outKind[a], Nav.RAMP)
				rampCost[Nav.edgeKey(a, b)] = Nav.rampCost(duration, (positions[b] - positions[a]).Magnitude)
			end
			return { positions = positions, out = out, outKind = outKind, rampCost = rampCost }
		end

		T.it("coûte la distance courue pendant le trajet, plus un forfait", function()
			T.expectNear(Nav.rampCost(4, 50), 4 * Movement.RUN_SPEED + Config.RAMP_COST_EXTRA, 1e-6)
			T.expect(Nav.rampCost(5, 50) > Nav.rampCost(4, 50), "plus long, plus cher")
			-- Trajet plus rapide que la course : jamais sous la distance à vol d'oiseau (heuristique de l'A*)
			T.expectNear(Nav.rampCost(1, 400), 400 + Config.RAMP_COST_EXTRA, 1e-6)
		end)

		T.it("prend la rampe quand elle raccourcit le chemin", function()
			-- 60 cases (~240 studs à pied, ~8 s) ; rampe de 1 à 60, 8 studs plus loin, en 3 s (110 studs de coût)
			local path = Nav.findPath(corridor(60, 1, 60, 3), 1, 60)
			T.expectEqual(#path, 2, "case d'entrée puis case de sortie")
			T.expectEqual(path[2], 60)
		end)

		T.it("ne la prend pas quand elle n'y gagne rien", function()
			-- Rampe de 1 à 10 en 3 s (110 studs) contre ~40 studs à pied
			local path = Nav.findPath(corridor(10, 1, 10, 3), 1, 10)
			T.expectEqual(#path, 10, "à pied")
			-- Destination avant la sortie : la rampe ne mène pas plus près
			local before = Nav.findPath(corridor(60, 1, 60, 3), 1, 20)
			T.expectEqual(#before, 20, "à pied")
		end)

		T.it("ne prend jamais une arête de rampe écartée", function()
			local banned = { [Nav.edgeKey(1, 60)] = true }
			local path = Nav.findPath(corridor(60, 1, 60, 3), 1, 60, banned)
			T.expectEqual(#path, 60, "à pied")
		end)

		T.it("ne compte pas les deux bouts d'une rampe comme points voisins", function()
			-- Cases 1-2 et 59-60 dans deux points ; seule la rampe les relie
			local graph = corridor(60, 1, 60, 3)
			local cellWaypoint = { [1] = 1, [2] = 1, [59] = 2, [60] = 2 }
			local edges = Nav.waypointEdges(graph, cellWaypoint)
			T.expectEqual(edges[1], nil, "pas de voisin par la rampe (enquête, #141)")
		end)

		T.it("sans rampe dans la map, le chemin reste celui à pied", function()
			local path = Nav.findPath(corridor(60, 1, 60, nil), 1, 60)
			T.expectEqual(#path, 60)
		end)
	end)
end

-- Règles du plan de navigation des bots (#140) : classement des pas, recherche de chemin, composante gardée,
-- regroupement en points, notes, suivi de chemin.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/NavRules")
	local Config = Loader.new():require("src/shared/BotConfig")
	local Movement = Loader.new():require("src/shared/MovementConfig")

	-- Cette méthode permet de comparer deux nombres à 1e-6 près lorsqu'un test mesure une distance.
	local function near(a: number, b: number, msg: string?)
		T.expectEqual(math.abs(a - b) < 1e-6, true, (msg or "") .. " : " .. tostring(a) .. " ≠ " .. tostring(b))
	end

	-- Cette méthode permet de construire un graphe de test lorsqu'un cas a besoin de cases et d'arêtes.
	local function graph(positions, edges)
		local out, outKind = {}, {}
		for i = 1, #positions do
			out[i], outKind[i] = {}, {}
		end
		for _, e in edges do
			table.insert(out[e[1]], e[2])
			table.insert(outKind[e[1]], e[3] or Rules.WALK)
			if e[4] then -- arête dans les deux sens
				table.insert(out[e[2]], e[1])
				table.insert(outKind[e[2]], e[3] or Rules.WALK)
			end
		end
		return { positions = positions, out = out, outKind = outKind }
	end

	-- Cette méthode permet de construire une rangée de cases au sol espacées de 4 studs lorsqu'un cas en a besoin.
	local function row(n, y, z)
		local list = {}
		for i = 1, n do
			list[i] = Vector3.new((i - 1) * 4, y or 0, z or 0)
		end
		return list
	end

	T.describe("NavRules", function()
		T.it("classe les pas : marche, descente, saut, impossible", function()
			T.expectEqual(Rules.stepKind(0, 4), Rules.WALK)
			T.expectEqual(Rules.stepKind(Movement.STEPUP_HEIGHT, 0), Rules.WALK, "une marche sur place")
			T.expectEqual(Rules.stepKind(3.5, 4), Rules.WALK, "pente d'escalier (mur d'air à 20-25°)")
			T.expectEqual(Rules.stepKind(-20, 4), Rules.DROP)
			T.expectEqual(Rules.stepKind(-(Config.NAV_MAX_DROP + 1), 4), nil, "trop profond")
			T.expectEqual(Rules.stepKind(Config.NAV_JUMP_UP_MAX, 1), Rules.JUMP)
			T.expectEqual(Rules.stepKind(Config.NAV_JUMP_UP_MAX + 2, 1), nil, "trop haut pour un saut")
		end)

		T.it("coûte plus cher un saut ou une échelle qu'un pas de même longueur", function()
			local a, b = Vector3.zero, Vector3.new(4, 0, 0)
			T.expectEqual(Rules.edgeCost(a, b, Rules.JUMP) > Rules.edgeCost(a, b, Rules.WALK), true)
			T.expectEqual(Rules.edgeCost(a, b, Rules.LADDER) > Rules.edgeCost(a, b, Rules.JUMP), true)
		end)

		T.it("trouve le plus court chemin et contourne un obstacle", function()
			-- Carré 1-2-3 en haut, 1-4-5-3 en bas : le haut est plus court
			local positions = {
				Vector3.new(0, 0, 0),
				Vector3.new(4, 0, 0),
				Vector3.new(8, 0, 0),
				Vector3.new(0, 0, 4),
				Vector3.new(8, 0, 4),
			}
			local g = graph(positions, {
				{ 1, 2, nil, true },
				{ 2, 3, nil, true },
				{ 1, 4, nil, true },
				{ 4, 5, nil, true },
				{ 5, 3, nil, true },
			})
			local path = Rules.findPath(g, 1, 3) :: { number }
			T.expectEqual(table.concat(path, ","), "1,2,3")
			local banned = { [Rules.edgeKey(2, 3)] = true }
			local detour = Rules.findPath(g, 1, 3, banned) :: { number }
			T.expectEqual(table.concat(detour, ","), "1,4,5,3", "arête écartée : détour")
			T.expectEqual(table.concat(Rules.findPath(g, 2, 2) :: { number }, ","), "2", "départ = arrivée")
		end)

		T.it("respecte le sens des arêtes (descente sans retour)", function()
			local g = graph({ Vector3.new(0, 10, 0), Vector3.new(4, 0, 0) }, { { 1, 2, Rules.DROP } })
			T.expectEqual(Rules.findPath(g, 1, 2) ~= nil, true)
			T.expectEqual(Rules.findPath(g, 2, 1), nil, "pas de chemin pour remonter")
		end)

		T.it("ne garde que les cases d'où l'on va partout et revient", function()
			-- 1-2-3 reliés ; 4 : fosse sans sortie (descente depuis 3) ; 5 : dessus de mur jamais atteint
			local positions = row(5)
			local g = graph(
				positions,
				{ { 1, 2, nil, true }, { 2, 3, nil, true }, { 3, 4, Rules.DROP }, { 5, 1, Rules.DROP } }
			)
			local keep = Rules.stronglyConnected(g, 1)
			T.expectEqual(keep[1] and keep[2] and keep[3], true)
			T.expectEqual(keep[4], nil, "fosse sans sortie écartée")
			T.expectEqual(keep[5], nil, "case qu'on ne peut pas rejoindre écartée")
		end)

		T.it("regroupe les cases par carré et par étage, et fond les petites zones", function()
			local size = Config.NAV_WAYPOINT_SIZE
			-- 12 cases sur une rangée (44 studs) : deux carrés de 24 studs
			local positions = row(12, 0, 2)
			local edges = {}
			for i = 1, 11 do
				table.insert(edges, { i, i + 1, nil, true })
			end
			-- Une case isolée en hauteur (étage), reliée par une échelle : zone à part, même trop petite
			table.insert(positions, Vector3.new(2, 30, 2))
			table.insert(edges, { 1, 13, Rules.LADDER })
			table.insert(edges, { 13, 1, Rules.DROP })
			local g = graph(positions, edges)
			local keep = {}
			for i = 1, #positions do
				keep[i] = true
			end
			local waypoints, cellWaypoint = Rules.cluster(g, keep, size, Config.NAV_WAYPOINT_MIN)
			T.expectEqual(#waypoints, 3, "deux carrés au sol + l'étage")
			T.expectEqual(cellWaypoint[1] == cellWaypoint[6], true, "même carré")
			T.expectEqual(cellWaypoint[1] ~= cellWaypoint[7], true, "carré suivant")
			T.expectEqual(cellWaypoint[13] ~= cellWaypoint[1], true, "l'étage n'est pas fondu au sol (pas de marche)")
			local edgesWp = Rules.waypointEdges(g, cellWaypoint)
			T.expectEqual(edgesWp[cellWaypoint[1]][cellWaypoint[13]], Rules.LADDER)
			T.expectEqual(edgesWp[cellWaypoint[1]][cellWaypoint[7]], Rules.WALK)
		end)

		T.it("fond une petite zone dans sa voisine reliée à pied", function()
			local size = Config.NAV_WAYPOINT_SIZE
			-- 6 cases dans le premier carré, 1 seule qui déborde dans le suivant
			local positions = {}
			for i = 1, 6 do
				positions[i] = Vector3.new(size - 1 - (6 - i) * 2, 0, 2)
			end
			positions[7] = Vector3.new(size + 1, 0, 2)
			local edges = {}
			for i = 1, 6 do
				table.insert(edges, { i, i + 1, nil, true })
			end
			local g = graph(positions, edges)
			local keep = {}
			for i = 1, 7 do
				keep[i] = true
			end
			local waypoints, cellWaypoint = Rules.cluster(g, keep, size, Config.NAV_WAYPOINT_MIN)
			T.expectEqual(#waypoints, 1)
			T.expectEqual(cellWaypoint[7], cellWaypoint[1])
		end)

		T.it("mesure couvert, couloir et profondeur", function()
			local far = math.huge
			T.expectEqual(Rules.coverShare({ 1, far, far, far, 2, far, far, far }), 0.25)
			T.expectEqual(Rules.isNarrow({ 5, far, far, far, 6, far, far, far }), true, "murs face à face à 11 studs")
			T.expectEqual(Rules.isNarrow({ 5, 6, far, far, far, far, far, far }), false, "deux murs voisins : un angle")
			local pos = Vector3.new(0, -20, 0)
			local others = { pos, Vector3.new(10, 0, 0), Vector3.new(0, 0, 10), Vector3.new(500, -80, 0) }
			T.expectEqual(Rules.depthBelow(pos, others, 40), 20, "20 studs sous ses voisins, le lointain ignoré")
			T.expectEqual(Rules.depthBelow(Vector3.new(0, 10, 0), { Vector3.zero }, 40), 0, "plus haut : 0")
		end)

		T.it("classe les points par ordre de priorité", function()
			local base = { slopeShare = 0, depth = 0, nearRamp = false, nearLadder = false, narrow = false }
			local function with(changes)
				local info = table.clone(base)
				for k, v in changes do
					info[k] = v
				end
				return Rules.classify(info)
			end
			T.expectEqual(with({}), "piece")
			T.expectEqual(with({ narrow = true }), "couloir")
			T.expectEqual(with({ depth = Config.NAV_PIT_DEPTH, narrow = true }), "fosse")
			T.expectEqual(with({ slopeShare = 0.6, depth = 99 }), "escalier")
			T.expectEqual(with({ nearLadder = true, slopeShare = 1 }), "echelle")
			T.expectEqual(with({ nearRamp = true, nearLadder = true }), "rampe")
		end)

		T.it("note d'abord la vue, puis la hauteur et le couvert", function()
			local wide = Rules.fixedScore(10, 10, 0, 0, "piece")
			local high = Rules.fixedScore(0, 10, 1, 1, "piece")
			T.expectEqual(wide > high, true, "la vue prime")
			T.expectEqual(Rules.fixedScore(5, 10, 1, 0, "piece") > Rules.fixedScore(5, 10, 0, 0, "piece"), true)
			T.expectEqual(Rules.fixedScore(0, 0, 0, 0, "piece"), 0, "map sans vue : pas de division par 0")
		end)

		T.it("sait quand une case est atteinte", function()
			local target = Vector3.new(10, 0, 0)
			T.expectEqual(Rules.reached(Vector3.new(9, 0.5, 0), target), true)
			T.expectEqual(Rules.reached(Vector3.new(7, 0, 0), target), false, "trop loin")
			T.expectEqual(Rules.reached(Vector3.new(10, 10, 0), target), false, "au-dessus : pas encore descendu")
		end)

		T.it("raccourcit en ligne droite, jamais au-delà d'un saut ou d'un virage", function()
			local W, J = Rules.WALK, Rules.JUMP
			local straight = row(6)
			local kinds = { W, W, W, W, W, W }
			T.expectEqual(Rules.lookAhead(Vector3.new(-1, 0, 0), straight, kinds, 2), 6, "ligne droite : jusqu'au bout")
			local withJump = { W, W, W, J, W, W }
			T.expectEqual(Rules.lookAhead(Vector3.new(-1, 0, 0), straight, withJump, 2), 3, "s'arrête avant le saut")
			-- Angle droit en 4 : le raccourci ne coupe pas le coin
			local corner = {
				Vector3.new(0, 0, 0),
				Vector3.new(4, 0, 0),
				Vector3.new(8, 0, 0),
				Vector3.new(8, 0, 4),
				Vector3.new(8, 0, 8),
			}
			T.expectEqual(
				Rules.lookAhead(Vector3.new(0, 0, 0), corner, { W, W, W, W, W }, 2),
				3,
				"virage : pas de coin coupé"
			)
		end)

		T.it("mesure la largeur de passage de chaque case (#151)", function()
			-- Grille 7 × 7 reliée à pied dans les 8 directions : bord = 0, centre = 3
			local positions, edges, id = {}, {}, {}
			for x = 0, 6 do
				for z = 0, 6 do
					table.insert(positions, Vector3.new(x * 4, 0, z * 4))
					id[x * 10 + z] = #positions
				end
			end
			for x = 0, 6 do
				for z = 0, 6 do
					for dx = -1, 1 do
						for dz = -1, 1 do
							local other = id[(x + dx) * 10 + (z + dz)]
							if
								(dx ~= 0 or dz ~= 0)
								and other
								and x + dx >= 0
								and x + dx <= 6
								and z + dz >= 0
								and z + dz <= 6
							then
								table.insert(edges, { id[x * 10 + z], other })
							end
						end
					end
				end
			end
			local steps = Rules.clearance(graph(positions, edges), 8)
			T.expectEqual(steps[id[0]], 0, "coin : bord")
			T.expectEqual(steps[id[3]], 0, "côté : bord")
			T.expectEqual(steps[id[11]], 1, "un pas du bord")
			T.expectEqual(steps[id[33]], 3, "centre")
			T.expectEqual(Rules.clearance(graph(positions, edges), 2)[id[33]], 2, "borné")
			local costs = Rules.borderCosts(steps)
			T.expectEqual(costs[id[0]], Config.NAV_BORDER_COST, "bord : surcoût plein")
			T.expectEqual(costs[id[11]], Config.NAV_BORDER_COST / 2, "un pas du bord : moitié")
			T.expectEqual(costs[id[33]], 0, "centre : aucun")
		end)

		T.it("suit le chemin d'un bot qui bhoppe, hauteur ignorée (#151)", function()
			local W, J = Rules.WALK, Rules.JUMP
			local line, kinds = {}, {}
			for i = 1, 20 do
				line[i], kinds[i] = Vector3.new((i - 1) * 4, 0, 0), W
			end
			T.expectEqual(Rules.walkStretchEnd(line, kinds, 2), 20, "marche jusqu'au bout")
			kinds[10] = J
			T.expectEqual(Rules.walkStretchEnd(line, kinds, 2), 9, "s'arrête avant un saut")
			kinds[10] = W
			line[8] = Vector3.new(28, 3, 0)
			T.expectEqual(Rules.walkStretchEnd(line, kinds, 2), 20, "une pente se survole")
			line[8] = Vector3.new(28, 0, 0)

			-- 6 studs au-dessus de x = 21 : sur le segment 6 → 7 (x 20 à 24)
			T.expectEqual(Rules.advanceAlong(Vector3.new(21, 6, 0.5), line, 2, 20), 7, "survolé : avance quand même")
			T.expectEqual(Rules.advanceAlong(Vector3.new(21, -8, 0), line, 2, 20), 2, "sous le trajet : n'avance pas")
			T.expectEqual(
				Rules.advanceAlong(Vector3.new(70, 6, 0), line, 2, 20),
				2 + Config.BHOP_ADVANCE_WINDOW,
				"fenêtre bornée"
			)

			near(Rules.distanceAlong(Vector3.new(2, 5, 0), line, 2, 20), 74, "longueur horizontale restante")
			local aim = Rules.pointAlong(Vector3.new(2, 0, 0), line, 2, 20, 10)
			near(aim.X, 12, "point visé 10 studs devant")
			near(Rules.pointAlong(Vector3.new(2, 0, 0), line, 2, 20, 1000).X, 76, "borné au bout")
		end)

		T.it("ralentit avant un virage serré, pas en ligne droite (#151)", function()
			local dt = 1 / 64
			T.expectEqual(
				Rules.circumradius(Vector3.new(0, 0, 0), Vector3.new(4, 0, 0), Vector3.new(8, 0, 0)),
				math.huge
			)
			near(Rules.circumradius(Vector3.new(10, 0, 0), Vector3.new(0, 0, 10), Vector3.new(-10, 0, 0)), 10, "cercle")
			-- Ligne droite puis angle droit à x = 40
			local corner, widths = {}, {}
			for i = 1, 11 do
				corner[i], widths[i] = Vector3.new((i - 1) * 4, 0, 0), 8
			end
			for i = 1, 10 do
				corner[11 + i], widths[11 + i] = Vector3.new(40, 0, i * 4), 8
			end
			local foot = Vector3.new(0, 0, 0)
			T.expectEqual(
				Rules.cornerSpeed(foot, corner, widths, 2, 21, 20, dt),
				math.huge,
				"angle trop loin : ignoré"
			)
			local slow = Rules.cornerSpeed(foot, corner, widths, 2, 21, 60, dt)
			T.expectEqual(slow < 100, true, "angle droit dans l'horizon : ralentit (" .. slow .. ")")
			local wide = {}
			for i = 1, 21 do
				wide[i] = 32
			end
			T.expectEqual(
				Rules.cornerSpeed(foot, corner, wide, 2, 21, 60, dt) > slow,
				true,
				"passage large : plus vite"
			)
			local edge = table.clone(widths)
			edge[4] = 0
			T.expectEqual(
				Rules.cornerSpeed(foot, corner, edge, 2, 21, 20, dt),
				Config.BHOP_NARROW_SPEED,
				"le long d'un bord"
			)
		end)

		T.it("saute plus tôt quand il court plus vite", function()
			local run = Movement.RUN_SPEED
			T.expectEqual(Rules.shouldJump(5, run), true)
			T.expectEqual(Rules.shouldJump(5, 0), false, "à l'arrêt : seulement au pied du rebord")
			T.expectEqual(Rules.shouldJump(1, 0), true)
			T.expectEqual(Rules.shouldJump(20, run), false)
		end)

		T.it("compte le temps sans se rapprocher de la cible", function()
			local best, stalled = Rules.progress(math.huge, 0, 10, 0.1)
			T.expectEqual(best, 10)
			T.expectEqual(stalled, 0)
			best, stalled = Rules.progress(best, stalled, 9.8, 0.1)
			T.expectEqual(stalled > 0, true, "0,2 stud : pas un progrès")
			best, stalled = Rules.progress(best, stalled, 9, 0.1)
			T.expectEqual(stalled, 0, "1 stud : progrès, compteur remis à 0")
		end)
	end)
end

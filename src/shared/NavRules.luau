-- Règles pures du plan de navigation des bots (#140, décision 3 de #133), testées (tests/specs/NavRules.spec.luau).
-- Le plan est une grille de cases praticables (sondée par NavBuilder dans la vraie collision de la map) reliées par
-- des arêtes orientées (marche, descente, saut, échelle, rampe de surf #142). Les cases sont regroupées en points de passage notés, qui
-- servent de destinations ; la recherche de chemin se fait case par case, le suivi saute les cases alignées.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local BotRules = require(ReplicatedStorage.Shared.BotRules)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local NavRules = {}

-- Types d'arête (index des tables NAV_COST_*)
NavRules.WALK = 1
NavRules.DROP = 2
NavRules.JUMP = 3
NavRules.LADDER = 4
NavRules.RAMP = 5 -- rampe de surf (#142) : trajet simulé de la case d'entrée à la case de sortie (RampRules)
NavRules.KIND_NAMES = { "marche", "descente", "saut", "echelle", "rampe" }

export type Graph = {
	positions: { Vector3 }, -- point du sol de chaque case
	out: { { number } }, -- cases d'arrivée des arêtes sortantes
	outKind: { { number } }, -- type de chaque arête sortante
	cellCost: { number }?, -- surcoût d'arrivée sur chaque case (bord d'un passage, #151), en studs
	rampCost: { [number]: number }?, -- coût de chaque arête de rampe (clé edgeKey, #142), d'après la durée du trajet
}

-- Cette méthode permet de donner la clé d'une arête orientée lorsqu'on veut la mettre à l'écart (ids < 1e6).
function NavRules.edgeKey(from: number, to: number): number
	return from * 1e6 + to
end

-- Cette méthode permet de donner la plus grande montée franchie à pied entre deux cases distantes de horizontal
-- studs lorsqu'on classe un pas : une marche, plus la pente la plus raide autorisée.
function NavRules.walkRise(horizontal: number): number
	return MovementConfig.STEPUP_HEIGHT + horizontal * math.tan(math.rad(BotConfig.NAV_WALK_SLOPE))
end

-- Cette méthode permet de classer le passage d'une case à une case voisine lorsque le plan est construit, selon la
-- différence de hauteur dy (arrivée − départ) : marche, descente d'un rebord, saut sur un rebord, ou nil (trop haut,
-- trop profond).
function NavRules.stepKind(dy: number, horizontal: number): number?
	if math.abs(dy) <= NavRules.walkRise(horizontal) then
		return NavRules.WALK
	elseif dy < 0 then
		return if -dy <= BotConfig.NAV_MAX_DROP then NavRules.DROP else nil
	end
	return if dy <= BotConfig.NAV_JUMP_UP_MAX then NavRules.JUMP else nil
end

-- Cette méthode permet de donner le coût d'une arête lorsque la recherche de chemin la parcourt : longueur pondérée
-- par son type, plus un forfait (un saut ou une échelle coûtent plus qu'un pas).
function NavRules.edgeCost(a: Vector3, b: Vector3, kind: number): number
	return (b - a).Magnitude * BotConfig.NAV_COST_FACTOR[kind] + BotConfig.NAV_COST_EXTRA[kind]
end

-- Cette méthode permet de donner le coût d'une arête de rampe lorsque le plan l'ajoute (#142) : distance que le bot
-- aurait courue pendant la durée du trajet, plus un forfait (risque) ; une rampe n'est prise que si elle raccourcit.
function NavRules.rampCost(duration: number): number
	return duration * MovementConfig.RUN_SPEED + BotConfig.RAMP_COST_EXTRA
end

-- Cette méthode permet de chercher le plus court chemin entre deux cases lorsqu'un bot choisit où aller (A*, tas
-- binaire) ; banned écarte des arêtes (clés edgeKey). Renvoie la liste des cases, départ et arrivée compris, ou nil.
-- Recherche reprenable : `run(budget)` explore au plus budget cases puis renvoie "running" (à reprendre au prochain
-- appel), "found" (le chemin est dans `path`) ou "none" (aucun chemin).
export type Search = { path: { number }?, run: (budget: number) -> string }

-- Cette méthode permet de préparer une recherche de chemin lorsqu'un bot doit l'étaler sur plusieurs ticks (#145) : même
-- A* que findPath, que l'appelant fait avancer par tranches de cases pour ne pas figer une frame serveur.
function NavRules.newSearch(
	graph: Graph,
	start: number,
	goal: number,
	banned: { [number]: boolean }?,
	weight: number?
): Search
	local search: Search = {
		path = nil,
		run = function(_budget: number): string
			return "none"
		end,
	}
	if start == goal then
		search.path = { start }
		search.run = function(_budget: number): string
			return "found"
		end
		return search
	end
	-- weight > 1 : heuristique pondérée, bien moins de cases explorées pour un chemin au plus weight fois plus long
	local w = weight or 1
	local positions, out, outKind, cellCost = graph.positions, graph.out, graph.outKind, graph.cellCost
	local rampCost = graph.rampCost
	local goalPos = positions[goal]
	local gScore: { [number]: number } = { [start] = 0 }
	local cameFrom: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	local heapNode: { number } = { start }
	local heapF: { number } = { (positions[start] - goalPos).Magnitude * w }

	local function push(node: number, f: number)
		local i = #heapNode + 1
		heapNode[i], heapF[i] = node, f
		while i > 1 do
			local parent = i // 2
			if heapF[parent] <= heapF[i] then
				break
			end
			heapNode[parent], heapNode[i] = heapNode[i], heapNode[parent]
			heapF[parent], heapF[i] = heapF[i], heapF[parent]
			i = parent
		end
	end

	local function pop(): number
		local top = heapNode[1]
		local n = #heapNode
		heapNode[1], heapF[1] = heapNode[n], heapF[n]
		heapNode[n], heapF[n] = nil, nil
		n -= 1
		local i = 1
		while true do
			local l, r = i * 2, i * 2 + 1
			local smallest = i
			if l <= n and heapF[l] < heapF[smallest] then
				smallest = l
			end
			if r <= n and heapF[r] < heapF[smallest] then
				smallest = r
			end
			if smallest == i then
				break
			end
			heapNode[smallest], heapNode[i] = heapNode[i], heapNode[smallest]
			heapF[smallest], heapF[i] = heapF[i], heapF[smallest]
			i = smallest
		end
		return top
	end

	search.run = function(budget: number): string
		if search.path then
			return "found"
		end
		local expanded = 0
		while #heapNode > 0 do
			if expanded >= budget then
				return "running"
			end
			expanded += 1
			local node = pop()
			if node == goal then
				local path = { goal }
				while cameFrom[path[1]] do
					table.insert(path, 1, cameFrom[path[1]])
				end
				search.path = path
				return "found"
			end
			if not closed[node] then
				closed[node] = true
				local base = gScore[node]
				local nodePos = positions[node]
				local targets, kinds = out[node], outKind[node]
				for k, to in targets do
					if not closed[to] and not (banned and banned[NavRules.edgeKey(node, to)]) then
						local kind = kinds[k]
						local ramp = if kind == NavRules.RAMP and rampCost
							then rampCost[NavRules.edgeKey(node, to)]
							else nil
						local g = base
							+ (ramp or NavRules.edgeCost(nodePos, positions[to], kind))
							+ (if cellCost then cellCost[to] else 0)
						local known = gScore[to]
						if known == nil or g < known then
							gScore[to] = g
							cameFrom[to] = node
							push(to, g + (positions[to] - goalPos).Magnitude * w)
						end
					end
				end
			end
		end
		return "none"
	end
	return search
end

-- Cette méthode permet de chercher le plus court chemin entre deux cases d'une traite (tests, outils) : voir newSearch
-- pour la version étalée sur plusieurs ticks.
function NavRules.findPath(
	graph: Graph,
	start: number,
	goal: number,
	banned: { [number]: boolean }?,
	weight: number?
): { number }?
	local search = NavRules.newSearch(graph, start, goal, banned, weight)
	search.run(math.huge)
	return search.path
end

-- Cette méthode permet de garder les cases d'où l'on peut aller partout et revenir lorsque le plan est construit :
-- composante fortement connexe de la case seed (atteignables depuis seed et qui atteignent seed). Écarte les dessus de
-- murs et les fonds de fosse sans sortie.
function NavRules.stronglyConnected(graph: Graph, seed: number): { [number]: boolean }
	local out = graph.out
	local incoming: { { number } } = {}
	for from, targets in out do
		for _, to in targets do
			local list = incoming[to]
			if not list then
				list = {}
				incoming[to] = list
			end
			table.insert(list, from)
		end
	end
	local function reach(adj: { [number]: { number } }): { [number]: boolean }
		local seen = { [seed] = true }
		local stack = { seed }
		while #stack > 0 do
			local node = table.remove(stack) :: number
			local list = adj[node]
			if list then
				for _, nxt in list do
					if not seen[nxt] then
						seen[nxt] = true
						table.insert(stack, nxt)
					end
				end
			end
		end
		return seen
	end

	local forward = reach(out)
	local backward = reach(incoming)
	local both = {}
	for node in forward do
		if backward[node] then
			both[node] = true
		end
	end
	return both
end

export type Waypoint = {
	cell: number, -- case représentative (la plus proche du centre de la zone)
	cells: { number },
	position: Vector3,
}

-- Cette méthode permet de regrouper les cases gardées (keep) en points de passage lorsque le plan est construit :
-- une zone par carré de size studs et par étage (cases reliées à pied dans le carré) ; une zone de moins de minCells
-- cases rejoint une voisine reliée à pied. Renvoie les points et le point de chaque case.
function NavRules.cluster(
	graph: Graph,
	keep: { [number]: boolean },
	size: number,
	minCells: number
): ({ Waypoint }, { [number]: number })
	local positions, out, outKind = graph.positions, graph.out, graph.outKind
	local function square(cell: number): string
		local p = positions[cell]
		return math.floor(p.X / size) .. ":" .. math.floor(p.Z / size)
	end

	-- Zones : parcours en largeur des marches à l'intérieur d'un même carré
	local zoneOf: { [number]: number } = {}
	local zones: { { number } } = {}
	local ids = {}
	for cell in keep do
		table.insert(ids, cell)
	end
	table.sort(ids)
	for _, cell in ids do
		if not zoneOf[cell] then
			local key = square(cell)
			local zone = { cell }
			local id = #zones + 1
			zones[id] = zone
			zoneOf[cell] = id
			local head = 1
			while head <= #zone do
				local node = zone[head]
				head += 1
				for k, to in out[node] do
					if outKind[node][k] == NavRules.WALK and keep[to] and not zoneOf[to] and square(to) == key then
						zoneOf[to] = id
						table.insert(zone, to)
					end
				end
			end
		end
	end

	-- Petites zones : fondues dans la plus grande zone voisine reliée à pied
	for id, zone in zones do
		if #zone > 0 and #zone < minCells then
			local best, bestSize = nil, 0
			for _, node in zone do
				for k, to in out[node] do
					local other = zoneOf[to]
					if other and other ~= id and outKind[node][k] == NavRules.WALK and #zones[other] > bestSize then
						best, bestSize = other, #zones[other]
					end
				end
			end
			if best then
				for _, node in zone do
					zoneOf[node] = best
					table.insert(zones[best], node)
				end
				zones[id] = {}
			end
		end
	end

	local waypoints: { Waypoint } = {}
	local cellWaypoint: { [number]: number } = {}
	for _, zone in zones do
		if #zone > 0 then
			local sum = Vector3.zero
			for _, node in zone do
				sum += positions[node]
			end
			local center = sum / #zone
			local rep, repDist = zone[1], math.huge
			for _, node in zone do
				local d = (positions[node] - center).Magnitude
				if d < repDist then
					rep, repDist = node, d
				end
			end
			table.insert(waypoints, { cell = rep, cells = zone, position = positions[rep] })
			for _, node in zone do
				cellWaypoint[node] = #waypoints
			end
		end
	end
	return waypoints, cellWaypoint
end

-- Cette méthode permet de relier les points de passage lorsque le plan est construit : une arête du point A au point
-- B si une case de A mène à une case de B, avec le type le plus simple trouvé (marche avant descente, saut, échelle).
function NavRules.waypointEdges(graph: Graph, cellWaypoint: { [number]: number }): { { [number]: number } }
	local edges: { { [number]: number } } = {}
	for from, targets in graph.out do
		local a = cellWaypoint[from]
		if a then
			for k, to in targets do
				local b = cellWaypoint[to]
				if b and b ~= a then
					local list = edges[a]
					if not list then
						list = {}
						edges[a] = list
					end
					local kind = graph.outKind[from][k]
					if list[b] == nil or kind < list[b] then
						list[b] = kind
					end
				end
			end
		end
	end
	return edges
end

-- Cette méthode permet de mesurer le couvert autour d'un point lorsqu'on le note : part des 8 directions où un mur
-- est à moins de NAV_COVER_DIST (dists : distance au mur par direction, math.huge sans mur).
function NavRules.coverShare(dists: { number }): number
	local hits = 0
	for _, d in dists do
		if d <= BotConfig.NAV_COVER_DIST then
			hits += 1
		end
	end
	return hits / math.max(#dists, 1)
end

-- Cette méthode permet de savoir si un point est dans un couloir lorsqu'on le classe : deux murs opposés (directions
-- i et i + 4 des 8) à moins de NAV_NARROW_WIDTH l'un de l'autre.
function NavRules.isNarrow(dists: { number }): boolean
	for i = 1, 4 do
		local a, b = dists[i], dists[i + 4]
		if a and b and a + b <= BotConfig.NAV_NARROW_WIDTH then
			return true
		end
	end
	return false
end

-- Cette méthode permet de mesurer de combien un point est plus bas que les points voisins (rayon en studs, à
-- l'horizontale) lorsqu'on cherche les fosses ; 0 sans voisin.
function NavRules.depthBelow(position: Vector3, others: { Vector3 }, radius: number): number
	local sum, count = 0, 0
	for _, other in others do
		local dx, dz = other.X - position.X, other.Z - position.Z
		if dx * dx + dz * dz <= radius * radius and other ~= position then
			sum += other.Y
			count += 1
		end
	end
	if count == 0 then
		return 0
	end
	return math.max(0, sum / count - position.Y)
end

export type PointInfo = {
	slopeShare: number, -- part des cases en pente (escalier)
	depth: number, -- profondeur sous les voisins (depthBelow)
	nearRamp: boolean,
	nearLadder: boolean,
	narrow: boolean,
}

-- Cette méthode permet de donner le type d'un point de passage lorsqu'on le note : entrée de rampe, pied ou haut
-- d'échelle, escalier, fosse, couloir, sinon pièce.
function NavRules.classify(info: PointInfo): string
	if info.nearRamp then
		return "rampe"
	elseif info.nearLadder then
		return "echelle"
	elseif info.slopeShare >= 0.5 then
		return "escalier"
	elseif info.depth >= BotConfig.NAV_PIT_DEPTH then
		return "fosse"
	elseif info.narrow then
		return "couloir"
	end
	return "piece"
end

-- Cette méthode permet de calculer la note fixe d'un point lorsque le plan est construit (décision 3 de #133) : vue
-- (points visibles rapportés au maximum de la map, critère principal), hauteur (0 à 1 dans la map), couvert (0 à 1),
-- bonus du type.
function NavRules.fixedScore(view: number, viewMax: number, height: number, cover: number, kind: string): number
	local viewPart = if viewMax > 0 then view / viewMax else 0
	return BotConfig.NAV_SCORE_VIEW * viewPart
		+ BotConfig.NAV_SCORE_HEIGHT * math.clamp(height, 0, 1)
		+ BotConfig.NAV_SCORE_COVER * math.clamp(cover, 0, 1)
		+ (BotConfig.NAV_SCORE_KIND[kind] or 0)
end

-- Cette méthode permet de savoir si un bot a atteint une case lorsqu'il suit son chemin : proche à l'horizontale et
-- à hauteur voisine (foot = sous les pieds du bot).
function NavRules.reached(foot: Vector3, target: Vector3): boolean
	local dx, dz = target.X - foot.X, target.Z - foot.Z
	return dx * dx + dz * dz <= BotConfig.NAV_REACH_RADIUS * BotConfig.NAV_REACH_RADIUS
		and math.abs(target.Y - foot.Y) <= BotConfig.NAV_REACH_DY
end

-- Cette méthode permet de donner la distance horizontale d'un point au segment [a, b] lorsqu'on teste un raccourci.
local function distToSegmentXZ(p: Vector3, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = if len2 > 1e-9 then math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1) else 0
	local dx, dz = a.X + abx * t - p.X, a.Z + abz * t - p.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Cette méthode permet de choisir la case visée lorsqu'un bot suit son chemin : la plus lointaine, à partir de
-- l'index i, qu'on rejoint en ligne droite depuis foot (arêtes de marche seulement, cases sautées proches de la
-- ligne, sans changer de hauteur plus qu'une marche par case). kinds[j] est le type de l'arête qui arrive en j.
function NavRules.lookAhead(foot: Vector3, points: { Vector3 }, kinds: { number }, i: number): number
	local best = i
	local last = math.min(#points, i + BotConfig.NAV_LOOKAHEAD)
	for k = i + 1, last do
		if kinds[k] ~= NavRules.WALK then
			break
		end
		local ok = true
		for j = i, k - 1 do
			if distToSegmentXZ(points[j], foot, points[k]) > BotConfig.NAV_SHORTCUT_TOL then
				ok = false
				break
			end
		end
		if not ok then
			break
		end
		best = k
	end
	return best
end

-- Bunny hop (#151) --------------------------------------------------------------------------------------------------

-- Cette méthode permet de donner la distance horizontale entre deux points lorsqu'on mesure un trajet.
local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = b.X - a.X, b.Z - a.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Cette méthode permet de mesurer la largeur de passage de chaque case lorsque le plan est construit : nombre de pas
-- de marche jusqu'à la case de bord la plus proche (bord : moins de 8 voisines rejointes à pied, donc un mur ou un
-- vide à côté), borné à maxSteps. 0 = case de bord.
function NavRules.clearance(graph: Graph, maxSteps: number): { number }
	local out, outKind = graph.out, graph.outKind
	local count = #graph.positions
	local steps = table.create(count, maxSteps)
	local queue = {}
	for id = 1, count do
		local walks = 0
		for k in out[id] do
			if outKind[id][k] == NavRules.WALK then
				walks += 1
			end
		end
		if walks < 8 then
			steps[id] = 0
			table.insert(queue, id)
		end
	end
	local head = 1
	while head <= #queue do
		local node = queue[head]
		head += 1
		local nextSteps = steps[node] + 1
		if nextSteps < maxSteps then
			for k, to in out[node] do
				if outKind[node][k] == NavRules.WALK and steps[to] > nextSteps then
					steps[to] = nextSteps
					table.insert(queue, to)
				end
			end
		end
	end
	return steps
end

-- Cette méthode permet de trouver le bout de la portion de marche devant un bot qui bhoppe lorsqu'il suit son
-- chemin : dernier index atteint par des arêtes de marche (pentes et marches se survolent ; un saut, une échelle ou
-- une descente de rebord se prennent à vitesse de course). kinds[i] doit être une marche.
function NavRules.walkStretchEnd(points: { Vector3 }, kinds: { number }, i: number): number
	local k = i
	while k < #points and kinds[k + 1] == NavRules.WALK do
		k += 1
	end
	return k
end

-- Cette méthode permet de donner le surcoût d'arrivée sur chaque case lorsque le plan est construit : les cases au
-- bord d'un passage (largeur 0 ou 1, NavRules.clearance) coûtent plus, pour que les chemins passent au milieu (plus
-- naturel, et le bot y bhoppe plus vite).
function NavRules.borderCosts(clearance: { number }): { number }
	local costs = table.create(#clearance, 0)
	for id, steps in clearance do
		if steps <= 0 then
			costs[id] = BotConfig.NAV_BORDER_COST
		elseif steps == 1 then
			costs[id] = BotConfig.NAV_BORDER_COST / 2
		end
	end
	return costs
end

-- Cette méthode permet d'avancer dans le chemin d'un bot qui bhoppe lorsqu'il le survole : index de la fin du segment
-- le plus proche à l'horizontale (hauteur ignorée, sauf sous le trajet), entre i et last. En l'air, les cases ne
-- sont jamais « atteintes » (pieds trop hauts) : c'est l'avancée le long du chemin qui compte.
function NavRules.advanceAlong(foot: Vector3, points: { Vector3 }, i: number, last: number): number
	if i < 2 then
		return i
	end
	local best, bestDist = i, math.huge
	for j = i, math.min(last, i + BotConfig.BHOP_ADVANCE_WINDOW) do
		local a, b = points[j - 1], points[j]
		if foot.Y >= math.min(a.Y, b.Y) - BotConfig.NAV_REACH_DY then
			local d = distToSegmentXZ(foot, a, b)
			if d < bestDist then
				best, bestDist = j, d
			end
		end
	end
	return best
end

-- Cette méthode permet de mesurer la longueur horizontale du chemin restant de foot jusqu'à l'index last lorsqu'un
-- bot décide de ressauter.
function NavRules.distanceAlong(foot: Vector3, points: { Vector3 }, i: number, last: number): number
	local total, cur = 0, foot
	for j = i, last do
		total += flatDist(cur, points[j])
		cur = points[j]
	end
	return total
end

-- Cette méthode permet de donner le point du chemin situé dist studs devant foot (à l'horizontale, sans dépasser
-- l'index last) lorsqu'un bot qui bhoppe choisit où viser (poursuite).
function NavRules.pointAlong(foot: Vector3, points: { Vector3 }, i: number, last: number, dist: number): Vector3
	local cur = foot
	for j = i, last do
		local p = points[j]
		local seg = flatDist(cur, p)
		if seg >= dist and seg > 1e-6 then
			return cur:Lerp(p, dist / seg)
		end
		dist -= seg
		cur = p
	end
	return points[last]
end

-- Cette méthode permet de donner le rayon du cercle passant par trois points (à l'horizontale) lorsqu'on mesure un
-- virage ; math.huge s'ils sont alignés.
function NavRules.circumradius(a: Vector3, b: Vector3, c: Vector3): number
	local cross = (b.X - a.X) * (c.Z - a.Z) - (b.Z - a.Z) * (c.X - a.X)
	if math.abs(cross) < 1e-6 then
		return math.huge
	end
	return flatDist(a, b) * flatDist(b, c) * flatDist(c, a) / (2 * math.abs(cross))
end

-- Cette méthode permet de donner la vitesse permise par les virages du chemin dans les horizon studs devant foot
-- lorsqu'un bot qui bhoppe règle sa vitesse : à chaque case, rayon du virage mesuré sur BHOP_CURVE_CELLS cases de
-- part et d'autre, agrandi d'une part de la largeur de passage (widths, studs : il coupe le virage), puis vitesse
-- qui tient ce rayon (BotRules.turnSpeed) ; BHOP_NARROW_SPEED au plus sur une case de bord.
function NavRules.cornerSpeed(
	foot: Vector3,
	points: { Vector3 },
	widths: { number },
	i: number,
	last: number,
	horizon: number,
	dt: number
): number
	local span = BotConfig.BHOP_CURVE_CELLS
	local first = math.max(i - span, 1)
	local best = math.huge
	local travelled, cur = 0, foot
	for j = i, last do
		travelled += flatDist(cur, points[j])
		cur = points[j]
		if travelled > horizon then
			break
		end
		local width = widths[j] or 0
		local radius =
			NavRules.circumradius(points[math.max(j - span, first)], points[j], points[math.min(j + span, last)])
		best = math.min(best, BotRules.turnSpeed(radius + width * BotConfig.BHOP_WIDTH_USE, dt))
		if width <= 0 then
			best = math.min(best, BotConfig.BHOP_NARROW_SPEED)
		end
	end
	return best
end

-- Cette méthode permet de savoir s'il faut sauter lorsque le bot court vers un rebord à monter : le rebord (milieu de
-- l'arête) est à moins de la distance parcourue pendant NAV_JUMP_LEAD_TIME, plus son rayon.
function NavRules.shouldJump(distToLedge: number, speed: number): boolean
	return distToLedge <= speed * BotConfig.NAV_JUMP_LEAD_TIME + MovementConfig.CHAR_RADIUS + 0.5
end

-- Cette méthode permet de suivre les progrès d'un bot vers sa cible lorsqu'un tick passe : renvoie le nouveau
-- meilleur écart et le temps passé sans s'en rapprocher d'au moins 0,5 stud.
function NavRules.progress(best: number, stalled: number, dist: number, dt: number): (number, number)
	if dist < best - 0.5 then
		return dist, 0
	end
	return best, stalled + dt
end

return NavRules

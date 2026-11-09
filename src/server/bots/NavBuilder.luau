-- Construction du plan de navigation d'une map (#140), au démarrage du serveur, dans la vraie collision (murs d'air
-- compris) :
-- 1. grille de colonnes tous les NAV_GRID studs : chaque surface marchable rencontrée de haut en bas devient une case
--    si un corps y tient debout (GetPartsInPart) ;
-- 2. arêtes vers les 8 colonnes voisines : marche (boîte du corps balayée de case à case), descente d'un rebord et
--    saut sur un rebord (même trajet en L, parcouru dans un sens ou dans l'autre), plus une arête par échelle ;
-- 3. cases gardées : celles d'où l'on va partout et revient (NavRules.stronglyConnected depuis un point d'apparition) ;
-- 4. points de passage (NavRules.cluster) et leur note fixe (vue entre points, hauteur, couvert, type).
-- Le calcul est étalé sur plusieurs frames (NAV_BUILD_BUDGET par frame). Règles pures : NavRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local LadderRules = require(ReplicatedStorage.Shared.LadderRules)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local NavRules = require(ReplicatedStorage.Shared.NavRules)

local NavBuilder = {}

export type Ladder = {
	cframe: CFrame,
	size: Vector3,
	normal: Vector3, -- normale sortante horizontale (du mur vers le grimpeur)
	bottom: number?, -- case du pied
	top: number?, -- case du haut
}

export type PlanWaypoint = {
	cell: number,
	cells: { number },
	position: Vector3,
	kind: string,
	score: number,
	view: number,
	cover: number,
}

export type Plan = {
	mapName: string,
	grid: number,
	originX: number,
	originZ: number,
	graph: NavRules.Graph,
	columns: { [number]: { number } }, -- clé de colonne → cases, de haut en bas
	cellColumn: { number },
	slope: { [number]: boolean }, -- case en pente (normale < 0,97)
	keep: { [number]: boolean },
	waypoints: { PlanWaypoint },
	cellWaypoint: { [number]: number },
	waypointEdges: { { [number]: number } },
	ladders: { Ladder },
	stats: { [string]: number },
}

local DIRS = {
	{ 1, 0 },
	{ 1, 1 },
	{ 0, 1 },
	{ -1, 1 },
	{ -1, 0 },
	{ -1, -1 },
	{ 0, -1 },
	{ 1, -1 },
}

-- Cette méthode permet de donner la clé d'une colonne de la grille lorsqu'on range ou cherche ses cases.
function NavBuilder.columnKey(ix: number, iz: number): number
	return ix * 100000 + iz
end

-- Cette méthode permet de construire le plan de navigation de la map lorsque le serveur démarre ; à appeler dans un
-- thread qui peut céder la main (task.wait entre deux tranches de calcul).
function NavBuilder.build(map: Instance): Plan
	local started = os.clock()
	local sliceStart = os.clock()
	-- Cette méthode permet de rendre la main au moteur lorsque la tranche de calcul de la frame est écoulée.
	local function slice()
		if os.clock() - sliceStart > BotConfig.NAV_BUILD_BUDGET then
			task.wait()
			sliceStart = os.clock()
		end
	end

	local G = BotConfig.NAV_GRID
	local R = BotConfig.NAV_BODY_RADIUS
	local B, T = BotConfig.NAV_BODY_BOTTOM, BotConfig.NAV_BODY_TOP
	local bodyLift = Vector3.new(0, (B + T) / 2, 0)
	local bodySize = Vector3.new(2 * R, T - B, 2 * R)

	-- Requêtes : seulement la map, seulement ce qui bloque un personnage
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Include
	castParams.FilterDescendantsInstances = { map }
	castParams.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { map }
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	-- Vue et couvert : les murs d'air n'arrêtent ni le regard ni les balles
	local clips = map:FindFirstChild("Clips")
	local viewParams = RaycastParams.new()
	viewParams.FilterType = Enum.RaycastFilterType.Include
	viewParams.FilterDescendantsInstances = { map }
	viewParams.RespectCanCollide = true

	local probe = Instance.new("Part")
	probe.Name = "NavProbe"
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.CanTouch = false
	probe.Transparency = 1
	probe.Size = bodySize
	probe.Parent = workspace

	-- Emprise : pièces qui bloquent, au-dessus de la hauteur de mort
	local killY = map:GetAttribute("KillHeight")
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, inst in map:GetDescendants() do
		if inst:IsA("BasePart") and inst.CanCollide then
			local p, r = inst.Position, inst.Size.Magnitude / 2
			minX, minY, minZ = math.min(minX, p.X - r), math.min(minY, p.Y - r), math.min(minZ, p.Z - r)
			maxX, maxY, maxZ = math.max(maxX, p.X + r), math.max(maxY, p.Y + r), math.max(maxZ, p.Z + r)
		end
	end
	local bottomY = if type(killY) == "number" then math.max(minY, killY) else minY
	local topY = maxY + 5
	local nx, nz = math.ceil((maxX - minX) / G), math.ceil((maxZ - minZ) / G)

	-- 1. Cases
	local positions: { Vector3 } = {}
	local cellColumn: { number } = {}
	local columns: { [number]: { number } } = {}
	local slope: { [number]: boolean } = {}
	for ix = 0, nx do
		for iz = 0, nz do
			local x, z = minX + (ix + 0.5) * G, minZ + (iz + 0.5) * G
			local y = topY
			for _ = 1, 24 do
				local hit = workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, bottomY - y, 0), castParams)
				if not hit then
					break
				end
				if hit.Normal.Y >= MovementConfig.SURF_NORMAL_Y then
					probe.CFrame = CFrame.new(hit.Position + bodyLift)
					if #workspace:GetPartsInPart(probe, overlap) == 0 then
						table.insert(positions, hit.Position)
						local id = #positions
						local key = NavBuilder.columnKey(ix, iz)
						cellColumn[id] = key
						local list = columns[key]
						if not list then
							list = {}
							columns[key] = list
						end
						table.insert(list, id)
						if hit.Normal.Y < 0.97 then
							slope[id] = true
						end
					end
				end
				y = hit.Position.Y - 0.05
			end
			slice()
		end
	end
	probe:Destroy()

	-- 2. Arêtes
	local out: { { number } } = {}
	local outKind: { { number } } = {}
	for id = 1, #positions do
		out[id] = {}
		outKind[id] = {}
	end
	local edgeSet: { [number]: boolean } = {}
	local counts = { 0, 0, 0, 0 }
	-- Cette méthode permet d'ajouter une arête orientée lorsqu'elle est validée (une seule par paire et par sens).
	local function addEdge(a: number, b: number, kind: number)
		local key = NavRules.edgeKey(a, b)
		if edgeSet[key] then
			return
		end
		edgeSet[key] = true
		table.insert(out[a], b)
		table.insert(outKind[a], kind)
		counts[kind] += 1
	end
	-- Cette méthode permet de savoir si la boîte du corps passe d'un centre à un autre sans rien toucher.
	local function sweepClear(from: Vector3, to: Vector3): boolean
		local delta = to - from
		if delta.Magnitude < 1e-3 then
			return true
		end
		return workspace:Blockcast(CFrame.new(from), bodySize, delta, castParams) == nil
	end

	local phaseStart = os.clock()
	local phases = { cells = phaseStart - started }

	-- Marche : symétrique, testée sur 4 directions et posée dans les deux sens
	for a = 1, #positions do
		local pa = positions[a]
		local key = cellColumn[a]
		local ix, iz = key // 100000, key % 100000
		for d = 1, 4 do
			local dir = DIRS[d]
			local list = columns[NavBuilder.columnKey(ix + dir[1], iz + dir[2])]
			if list then
				local horizontal = if dir[1] ~= 0 and dir[2] ~= 0 then G * math.sqrt(2) else G
				local walkB, walkAbs = nil, math.huge
				for _, b in list do
					local dy = positions[b].Y - pa.Y
					if NavRules.stepKind(dy, horizontal) == NavRules.WALK and math.abs(dy) < walkAbs then
						walkB, walkAbs = b, math.abs(dy)
					end
				end
				if walkB and sweepClear(pa + bodyLift, positions[walkB] + bodyLift) then
					addEdge(a, walkB, NavRules.WALK)
					addEdge(walkB, a, NavRules.WALK)
				end
			end
		end
		slice()
	end
	phases.walk = os.clock() - phaseStart
	phaseStart = os.clock()

	-- Rebords : depuis a, vers la plus haute case plus basse qu'une marche d'une colonne voisine qu'il ne rejoint pas
	-- à pied (un rebord trop raide pour la marche est aussi essayé ici). Descente de a, et saut de b vers a s'il
	-- est assez bas : même trajet en L, parcouru dans un sens ou dans l'autre.
	for a = 1, #positions do
		local pa = positions[a]
		local key = cellColumn[a]
		local ix, iz = key // 100000, key % 100000
		local walked: { [number]: boolean } = {}
		for k, to in out[a] do
			if outKind[a][k] == NavRules.WALK then
				walked[cellColumn[to]] = true
			end
		end
		for _, dir in DIRS do
			local columnKey = NavBuilder.columnKey(ix + dir[1], iz + dir[2])
			local list = columns[columnKey]
			if list and not walked[columnKey] then
				local dropB, dropY = nil, -math.huge
				for _, b in list do
					local y = positions[b].Y
					local depth = pa.Y - y
					if depth > MovementConfig.STEPUP_HEIGHT and depth <= BotConfig.NAV_MAX_DROP and y > dropY then
						dropB, dropY = b, y
					end
				end
				if dropB then
					local pb = positions[dropB]
					local over = Vector3.new(pb.X, pa.Y, pb.Z) + bodyLift
					if sweepClear(pa + bodyLift, over) and sweepClear(over, pb + bodyLift) then
						addEdge(a, dropB, NavRules.DROP)
						if pa.Y - pb.Y <= BotConfig.NAV_JUMP_UP_MAX then
							addEdge(dropB, a, NavRules.JUMP)
						end
					end
				end
			end
		end
		slice()
	end
	phases.ledges = os.clock() - phaseStart

	local graph: NavRules.Graph = { positions = positions, out = out, outKind = outKind }

	-- Cette méthode permet de trouver la case la plus proche d'un point lorsqu'on accroche une échelle ou un point
	-- d'apparition au plan ; accept filtre les cases (nil : toutes).
	local function nearest(point: Vector3, radius: number, accept: ((number) -> boolean)?): number?
		local cx, cz = math.floor((point.X - minX) / G), math.floor((point.Z - minZ) / G)
		local span = math.ceil(radius / G)
		local best, bestDist = nil, radius
		for dx = -span, span do
			for dz = -span, span do
				local list = columns[NavBuilder.columnKey(cx + dx, cz + dz)]
				if list then
					for _, id in list do
						local dist = (positions[id] - point).Magnitude
						if dist < bestDist and (not accept or accept(id)) then
							best, bestDist = id, dist
						end
					end
				end
			end
		end
		return best
	end

	-- Échelles : du pied (devant le mur) au haut (derrière l'acrotère)
	local ladders: { Ladder } = {}
	local ladderFolder = map:FindFirstChild(LadderRules.LADDERS_FOLDER)
	if ladderFolder then
		for _, part in ladderFolder:GetChildren() do
			if part:IsA("BasePart") then
				local look = part.CFrame.LookVector
				local normal = Vector3.new(look.X, 0, look.Z).Unit
				local center = part.Position
				local lowY, highY = center.Y - part.Size.Y / 2, center.Y + part.Size.Y / 2
				local foot = Vector3.new(center.X, lowY, center.Z) + normal * (R + 1)
				local wallTop = highY - MovementConfig.CHAR_HEIGHT_STAND
				local bottomCell = nearest(foot, 8, function(id)
					return math.abs(positions[id].Y - lowY) <= 4
				end)
				local topCell = nearest(Vector3.new(center.X, wallTop, center.Z) - normal * 3, 10, function(id)
					local p = positions[id]
					return p.Y > lowY + MovementConfig.CHAR_HEIGHT_STAND and (p - center):Dot(normal) < 0
				end)
				if bottomCell and topCell then
					addEdge(bottomCell, topCell, NavRules.LADDER)
				else
					warn(
						string.format(
							"[Nav] échelle %s non reliée au plan (pied %s, haut %s)",
							part:GetFullName(),
							tostring(bottomCell),
							tostring(topCell)
						)
					)
				end
				table.insert(
					ladders,
					{ cframe = part.CFrame, size = part.Size, normal = normal, bottom = bottomCell, top = topCell }
				)
			end
		end
	end

	-- 3. Cases gardées, depuis le point d'apparition au sol le plus central (sinon la case la plus reliée)
	local seed: number? = nil
	local spawns = map:FindFirstChild("GroundSpawns")
	if spawns then
		for _, spawn in spawns:GetChildren() do
			if spawn:IsA("BasePart") then
				seed = nearest(spawn.Position, 12)
				if seed then
					break
				end
			end
		end
	end
	if not seed then
		local bestDegree = -1
		for id = 1, #positions do
			if #out[id] > bestDegree then
				seed, bestDegree = id, #out[id]
			end
		end
	end
	local keep = if seed then NavRules.stronglyConnected(graph, seed) else {}
	slice()

	-- 4. Points de passage et notes
	local clusters, cellWaypoint =
		NavRules.cluster(graph, keep, BotConfig.NAV_WAYPOINT_SIZE, BotConfig.NAV_WAYPOINT_MIN)
	local waypointEdges = NavRules.waypointEdges(graph, cellWaypoint)
	local wpPositions: { Vector3 } = {}
	local wpMinY, wpMaxY = math.huge, -math.huge
	for i, wp in clusters do
		wpPositions[i] = wp.position
		wpMinY, wpMaxY = math.min(wpMinY, wp.position.Y), math.max(wpMaxY, wp.position.Y)
	end
	if clips then
		-- Vue et couvert sans les murs d'air : Include de tout le reste de la map
		local include = {}
		for _, child in map:GetChildren() do
			if child ~= clips then
				table.insert(include, child)
			end
		end
		viewParams.FilterDescendantsInstances = include
	end

	phaseStart = os.clock()
	local views = table.create(#clusters, 0)
	local eye = Vector3.new(0, BotConfig.NAV_EYE_HEIGHT, 0)
	local range2 = BotConfig.NAV_VIEW_RANGE * BotConfig.NAV_VIEW_RANGE
	for i = 1, #clusters do
		local from = wpPositions[i] + eye
		for j = i + 1, #clusters do
			local delta = wpPositions[j] + eye - from
			if delta:Dot(delta) <= range2 and not workspace:Raycast(from, delta, viewParams) then
				views[i] += 1
				views[j] += 1
			end
		end
		slice()
	end
	phases.view = os.clock() - phaseStart
	local viewMax = 0
	for _, v in views do
		viewMax = math.max(viewMax, v)
	end

	local ladderCells: { [number]: boolean } = {}
	for _, ladder in ladders do
		if ladder.bottom then
			ladderCells[ladder.bottom] = true
		end
		if ladder.top then
			ladderCells[ladder.top] = true
		end
	end
	local ramps = map:FindFirstChild("Ramps")
	local rampParams = OverlapParams.new()
	rampParams.FilterType = Enum.RaycastFilterType.Include
	rampParams.FilterDescendantsInstances = if ramps then { ramps } else {}
	rampParams.MaxParts = 1
	local scanDist = math.max(BotConfig.NAV_COVER_DIST, BotConfig.NAV_NARROW_WIDTH)

	local waypoints: { PlanWaypoint } = {}
	for i, wp in clusters do
		local waist = wp.position + Vector3.new(0, 2.5, 0)
		local dists = {}
		for k = 0, 7 do
			local angle = k * math.pi / 4
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle)) * scanDist
			local hit = workspace:Raycast(waist, dir, viewParams)
			dists[k + 1] = if hit then hit.Distance else math.huge
		end
		local slopeCount, nearLadder = 0, false
		for _, cell in wp.cells do
			if slope[cell] then
				slopeCount += 1
			end
			if ladderCells[cell] then
				nearLadder = true
			end
		end
		local nearRamp = ramps ~= nil
			and #workspace:GetPartBoundsInRadius(wp.position, BotConfig.NAV_RAMP_DIST, rampParams) > 0
		local kind = NavRules.classify({
			slopeShare = slopeCount / #wp.cells,
			depth = NavRules.depthBelow(wp.position, wpPositions, 40),
			nearRamp = nearRamp,
			nearLadder = nearLadder,
			narrow = NavRules.isNarrow(dists),
		})
		local cover = NavRules.coverShare(dists)
		local height = if wpMaxY > wpMinY then (wp.position.Y - wpMinY) / (wpMaxY - wpMinY) else 0
		waypoints[i] = {
			cell = wp.cell,
			cells = wp.cells,
			position = wp.position,
			kind = kind,
			score = NavRules.fixedScore(views[i], viewMax, height, cover, kind),
			view = views[i],
			cover = cover,
		}
		slice()
	end

	local kept = 0
	for _ in keep do
		kept += 1
	end
	return {
		mapName = map.Name,
		grid = G,
		originX = minX,
		originZ = minZ,
		graph = graph,
		columns = columns,
		cellColumn = cellColumn,
		slope = slope,
		keep = keep,
		waypoints = waypoints,
		cellWaypoint = cellWaypoint,
		waypointEdges = waypointEdges,
		ladders = ladders,
		stats = {
			cells = #positions,
			kept = kept,
			walk = counts[NavRules.WALK],
			drop = counts[NavRules.DROP],
			jump = counts[NavRules.JUMP],
			ladder = counts[NavRules.LADDER],
			waypoints = #waypoints,
			seconds = os.clock() - started,
			secondsCells = phases.cells,
			secondsWalk = phases.walk,
			secondsLedges = phases.ledges,
			secondsView = phases.view,
		},
	}
end

return NavBuilder

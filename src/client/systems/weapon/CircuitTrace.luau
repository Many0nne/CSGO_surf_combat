-- CircuitTrace.luau
-- Effet de tir CIRCUIT (#567) : à la place du rayon, une piste de circuit imprimé magenta (presque droite, coudes à 45°,
-- tracé tiré à chaque tir par ShotEffectRules.circuitPath) se construit depuis la bouche du canon, où partent une
-- étincelle et un composant en cube (CircuitCube) ; une impulsion claire la parcourt jusqu'à l'impact, où un second cube
-- jaillit et un réseau de pistes fines pousse autour de lui (circuitBranches, dans le plan de la caméra). Tout s'éteint
-- ensuite, la piste de la bouche vers l'impact. Réglages et courbes dans ShotEffectRules (CIRCUIT_*).
-- Réserve de CIRCUIT_MAX_ACTIVE jeux (Attachments du Terrain ; Beams de piste, de halo, d'impulsion et du réseau ; un
-- émetteur d'étincelle), créés au premier besoin puis réutilisés : un tir ne crée aucune Instance. Réserve pleine :
-- `spawn` renvoie false et le tir garde le rayon ordinaire.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)
local CircuitCube = require(script.Parent.CircuitCube)

local CircuitTrace = {}

CircuitTrace.INSTANCE_NAME = "CircuitTrace"

local SEGMENTS = ShotEffectRules.CIRCUIT_MAX_SEGMENTS
local BRANCHES = ShotEffectRules.CIRCUIT_BRANCHES[2]
local BRANCH_POINTS = ShotEffectRules.CIRCUIT_BRANCH_TURNS[2] + 2 -- points d'une piste du réseau au plus
local STEPS = ShotEffectRules.FADE_STEPS
local PARKED = Vector3.new(0, -10000, 0)

-- Une piste du réseau dans un jeu : ses points (Attachments), ses Beams, le point de son carré final et son Beam
type Branch = { points: { Attachment }, beams: { Beam }, dotEnd: Attachment, dot: Beam }

-- Un jeu de la réserve : piste (points, Beams de piste et de halo par segment, paliers d'extinction), impulsion,
-- réseau, étincelle, et le tir qu'il montre (tracé, repère, instant de départ ; nil : libre)
type Set = {
	points: { Attachment },
	cores: { Beam },
	halos: { Beam },
	steps: { number },
	pulse: Beam,
	pulseA: Attachment,
	pulseB: Attachment,
	branches: { Branch },
	branchStep: number,
	flashPart: BasePart,
	flash: ParticleEmitter,
	path: { { number } },
	length: number,
	places: { number },
	starts: { number },
	origin: Vector3,
	forward: Vector3,
	up: Vector3,
	finish: Vector3,
	born: number?,
	impact: boolean,
	net: { { { number } } },
	netCenter: Vector3,
	netRight: Vector3,
	netUp: Vector3,
	netScale: number,
}

local pool: { Set } = {}
local folder: Folder? = nil
local stepConn: RBXScriptConnection? = nil
local terrain = workspace:WaitForChild("Terrain")

-- Transparences précalculées par palier d'extinction (0 : allumé) : pas de NumberSequence créée à chaque frame
local CORE_FADE: { NumberSequence } = {}
local HALO_FADE: { NumberSequence } = {}
for i = 0, STEPS do
	local f = i / STEPS
	CORE_FADE[i + 1] = NumberSequence.new(f)
	local halo = ShotEffectRules.CIRCUIT_HALO_TRANSPARENCY
	HALO_FADE[i + 1] = NumberSequence.new(halo + (1 - halo) * f)
end
-- Impulsion : claire au centre, effacée à ses deux bouts
local PULSE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})

-- Cette méthode permet de convertir une couleur { r, g, b } (0..255) des réglages en ColorSequence lorsqu'un Beam est
-- créé.
local function color(rgb: { number }): ColorSequence
	return ColorSequence.new(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
end

-- Cette méthode permet de créer un Attachment rangé hors de vue dans le Terrain lorsqu'un jeu de la réserve est créé.
local function attachment(): Attachment
	local a = Instance.new("Attachment")
	a.Name = CircuitTrace.INSTANCE_NAME
	a.WorldPosition = PARKED
	a.Parent = terrain
	return a
end

-- Cette méthode permet de créer un Beam lumineux face à la caméra entre deux Attachments lorsqu'un jeu de la réserve
-- est créé ; éteint tant que le jeu est libre.
local function beam(a0: Attachment, a1: Attachment, width: number, rgb: { number }): Beam
	local b = Instance.new("Beam")
	b.Name = CircuitTrace.INSTANCE_NAME
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = width
	b.Width1 = width
	b.Color = color(rgb)
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 1
	b.Enabled = false
	b.Parent = a0
	return b
end

-- Cette méthode permet de créer la pièce invisible et l'émetteur de l'étincelle du tir (une particule à la demande,
-- lumineuse, face à la caméra) lorsqu'un jeu de la réserve est créé.
local function flashEmitter(): (BasePart, ParticleEmitter)
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = CircuitTrace.INSTANCE_NAME
		created.Parent = workspace
		folder = created
	end
	local part = Instance.new("Part")
	part.Name = CircuitTrace.INSTANCE_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	part.Position = PARKED
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = CircuitTrace.INSTANCE_NAME
	emitter.Texture = ShotEffectRules.CIRCUIT_FLASH_IMAGE
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(ShotEffectRules.CIRCUIT_FLASH_LIFE)
	emitter.Speed = NumberRange.new(0)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = part
	part.Parent = folder
	return part, emitter
end

-- Cette méthode permet de créer un jeu de la réserve (piste, impulsion, réseau, étincelle) lorsqu'un tir CIRCUIT n'en
-- trouve pas de libre et que la réserve n'est pas pleine.
local function make(): Set
	local points, cores, halos, steps = {}, {}, {}, {}
	for i = 1, SEGMENTS + 1 do
		points[i] = attachment()
	end
	for i = 1, SEGMENTS do
		halos[i] = beam(points[i], points[i + 1], ShotEffectRules.CIRCUIT_HALO_WIDTH, ShotEffectRules.CIRCUIT_HALO_RGB)
		cores[i] = beam(points[i], points[i + 1], ShotEffectRules.CIRCUIT_WIDTH, ShotEffectRules.CIRCUIT_RGB)
		steps[i] = -1
	end
	local pulseA, pulseB = attachment(), attachment()
	local pulse = beam(pulseA, pulseB, ShotEffectRules.CIRCUIT_PULSE_WIDTH, ShotEffectRules.CIRCUIT_PULSE_RGB)
	pulse.Transparency = PULSE_TRANSPARENCY
	local branches = {}
	for k = 1, BRANCHES do
		local bp, bb = {}, {}
		for i = 1, BRANCH_POINTS do
			bp[i] = attachment()
		end
		for i = 1, BRANCH_POINTS - 1 do
			bb[i] = beam(bp[i], bp[i + 1], 0.05, ShotEffectRules.CIRCUIT_RGB)
		end
		local dotEnd = attachment()
		local dot = beam(bp[1], dotEnd, 0.1, ShotEffectRules.CIRCUIT_PULSE_RGB)
		branches[k] = { points = bp, beams = bb, dotEnd = dotEnd, dot = dot }
	end
	local flashPart, flash = flashEmitter()
	return {
		points = points,
		cores = cores,
		halos = halos,
		steps = steps,
		pulse = pulse,
		pulseA = pulseA,
		pulseB = pulseB,
		branches = branches,
		branchStep = -1,
		flashPart = flashPart,
		flash = flash,
		path = {},
		length = 0,
		places = {},
		starts = {},
		origin = Vector3.zero,
		forward = Vector3.zAxis,
		up = Vector3.yAxis,
		finish = Vector3.zero,
		born = nil,
		impact = false,
		net = {},
		netCenter = Vector3.zero,
		netRight = Vector3.xAxis,
		netUp = Vector3.yAxis,
		netScale = 1,
	}
end

-- Cette méthode permet de savoir si les Instances d'un jeu existent encore lorsqu'il va resservir (un tiers a pu les
-- détruire).
local function intact(set: Set): boolean
	local lastBranch = set.branches[#set.branches]
	return set.points[1].Parent ~= nil
		and set.points[#set.points].Parent ~= nil
		and set.pulseA.Parent ~= nil
		and set.flashPart.Parent ~= nil
		and (lastBranch == nil or lastBranch.dotEnd.Parent ~= nil)
end

-- Cette méthode permet d'éteindre le réseau d'un jeu (Beams désactivés) lorsqu'un tir part ou que le jeu est libéré.
local function hideNet(set: Set)
	for _, branch in set.branches do
		for _, b in branch.beams do
			b.Enabled = false
		end
		branch.dot.Enabled = false
	end
	set.branchStep = -1
end

-- Cette méthode permet de libérer un jeu (Beams éteints, points rangés) lorsque sa piste est éteinte.
local function release(set: Set)
	set.born = nil
	for i = 1, SEGMENTS do
		set.cores[i].Enabled = false
		set.halos[i].Enabled = false
	end
	set.pulse.Enabled = false
	hideNet(set)
	for _, a in set.points do
		a.WorldPosition = PARKED
	end
end

-- Cette méthode permet de placer dans le monde un point de la piste { le long du tir, décalage latéral } lorsqu'un
-- point est posé.
local function world(set: Set, along: number, lateral: number): Vector3
	return set.origin + set.forward * along + set.up * lateral
end

-- Cette méthode permet de placer dans le monde un point du réseau d'impact { x, y } (unité : arête du cube) lorsqu'il
-- est posé : dans le plan de la caméra au moment de l'impact.
local function netWorld(set: Set, x: number, y: number): Vector3
	return set.netCenter + (set.netRight * x + set.netUp * y) * set.netScale
end

-- Cette méthode permet d'allumer le réseau d'impact (cube, pistes tirées dans le plan de la caméra) lorsque l'impulsion
-- arrive à l'impact.
local function startImpact(set: Set)
	set.impact = true
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else set.finish - set.forward * 50
	local distance = (eye - set.finish).Magnitude
	local edge = ShotEffectRules.circuitCubeSize(distance)
	local toEye = if distance > 1e-3 then (eye - set.finish) / distance else -set.forward
	-- cube et réseau avancés vers la caméra : pas enfoncés dans le mur ou la cible touchés
	set.netCenter = set.finish + toEye * edge * 0.7
	set.netRight = if camera then camera.CFrame.RightVector else Vector3.xAxis
	set.netUp = if camera then camera.CFrame.UpVector else Vector3.yAxis
	set.netScale = edge
	set.net = ShotEffectRules.circuitBranches(function(min, max)
		return min + math.random() * (max - min)
	end)
	CircuitCube.spawn(set.netCenter, edge, ShotEffectRules.CIRCUIT_CUBE_LIFE_IMPACT)
	local width = edge * ShotEffectRules.CIRCUIT_BRANCH_WIDTH
	local dot = edge * ShotEffectRules.CIRCUIT_BRANCH_DOT
	for k, branch in set.branches do
		local used = set.net[k] ~= nil
		for i, b in branch.beams do
			b.Width0 = width
			b.Width1 = width
			b.Enabled = used and set.net[k][i + 1] ~= nil
		end
		branch.dot.Width0 = dot
		branch.dot.Width1 = dot
		branch.dot.Enabled = false
	end
	set.branchStep = -1
end

-- Cette méthode permet de poser le réseau d'impact à un instant de sa vie (`since` : s depuis l'arrivée de
-- l'impulsion) lorsqu'une frame passe : pistes qui poussent du cube vers l'extérieur, carré au bout une fois
-- poussées, extinction.
local function poseNet(set: Set, since: number, elapsed: number)
	local grow = math.clamp(since / ShotEffectRules.CIRCUIT_BRANCH_GROW, 0, 1)
	for k, branch in set.branches do
		local pts = set.net[k]
		if pts then
			local total = ShotEffectRules.circuitLength(pts)
			local front = grow * total
			local walked = 0
			for i = 1, #pts do
				if i > 1 then
					walked += math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
				end
				local x, y
				if walked <= front then
					x, y = pts[i][1], pts[i][2]
				else
					x, y = ShotEffectRules.circuitPointAt(pts, front)
				end
				branch.points[i].WorldPosition = netWorld(set, x, y)
			end
			-- carré au bout : un Beam aussi long que large, dans le prolongement de la piste
			if grow >= 1 and not branch.dot.Enabled then
				local last, before = pts[#pts], pts[#pts - 1]
				local dx, dy = last[1] - before[1], last[2] - before[2]
				local len = math.sqrt(dx * dx + dy * dy)
				local size = ShotEffectRules.CIRCUIT_BRANCH_DOT
				branch.dot.Attachment0 = branch.points[#pts]
				branch.dotEnd.WorldPosition = netWorld(set, last[1] + dx / len * size, last[2] + dy / len * size)
				branch.dot.Enabled = true
			end
		end
	end
	local fade =
		math.clamp((elapsed - ShotEffectRules.CIRCUIT_BRANCH_FADE_FROM) / ShotEffectRules.CIRCUIT_FADE_TIME, 0, 1)
	local step = math.round(fade * STEPS)
	if step ~= set.branchStep then
		set.branchStep = step
		for _, branch in set.branches do
			for _, b in branch.beams do
				b.Transparency = CORE_FADE[step + 1]
			end
			branch.dot.Transparency = CORE_FADE[step + 1]
		end
	end
end

-- Cette méthode permet de poser la piste d'un jeu à un instant de sa vie lorsqu'une frame passe : points jusqu'au front
-- de construction, extinction de chaque segment, impulsion, réseau d'impact à l'arrivée de l'impulsion.
local function pose(set: Set, elapsed: number)
	local built, pulse = ShotEffectRules.circuitProgress(elapsed)
	local front = built * set.length
	local path = set.path
	local segments = #path - 1
	for i = 1, segments + 1 do
		local along, lateral
		if set.starts[i] <= front then
			along, lateral = path[i][1], path[i][2]
		else
			along, lateral = ShotEffectRules.circuitPointAt(path, front)
		end
		set.points[i].WorldPosition = world(set, along, lateral)
	end
	for i = 1, segments do
		local step = if set.starts[i] < front
			then math.round(ShotEffectRules.circuitFade(elapsed, set.places[i]) * STEPS)
			else STEPS
		if step ~= set.steps[i] then
			set.steps[i] = step
			set.cores[i].Transparency = CORE_FADE[step + 1]
			set.halos[i].Transparency = HALO_FADE[step + 1]
		end
	end
	if pulse then
		local head = pulse * set.length
		local a1, l1 = ShotEffectRules.circuitPointAt(path, head)
		local a0, l0 = ShotEffectRules.circuitPointAt(path, head - ShotEffectRules.CIRCUIT_PULSE_LENGTH)
		set.pulseA.WorldPosition = world(set, a0, l0)
		set.pulseB.WorldPosition = world(set, a1, l1)
		set.pulse.Enabled = true
	else
		set.pulse.Enabled = false
	end
	local arrival = ShotEffectRules.CIRCUIT_PULSE_FROM + ShotEffectRules.CIRCUIT_PULSE_TIME
	if elapsed >= arrival then
		if not set.impact then
			startImpact(set)
		end
		poseNet(set, elapsed - arrival, elapsed)
	end
end

-- Cette méthode permet d'animer les pistes en cours lorsqu'une frame passe, de libérer celles qui sont éteintes, et
-- d'arrêter la boucle sans piste.
local function step()
	local now = os.clock()
	local active = 0
	for _, set in pool do
		local born = set.born
		if born then
			local elapsed = now - born
			if elapsed >= ShotEffectRules.CIRCUIT_LIFETIME or not intact(set) then
				release(set)
			else
				active += 1
				pose(set, elapsed)
			end
		end
	end
	if active == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local timedStep = PerfMarkers.wrap("effets de tir", step)

-- Cette méthode permet de prendre un jeu libre de la réserve lorsqu'un tir CIRCUIT part (créé si la réserve n'est pas
-- pleine, recréé s'il a été abîmé) ; nil si tous sont occupés.
local function freeSet(): Set?
	for i, set in pool do
		if not set.born then
			if not intact(set) then
				set = make()
				pool[i] = set
			end
			return set
		end
	end
	if #pool < ShotEffectRules.CIRCUIT_MAX_ACTIVE then
		local set = make()
		table.insert(pool, set)
		return set
	end
	return nil
end

-- Cette méthode permet de montrer la piste CIRCUIT d'un tir lorsqu'il part, de la bouche `start` à l'impact `finish` :
-- tracé tiré au hasard dans le plan vertical du tir ; étincelle et cube au canon, plus petits chez le tireur
-- (`isLocal`), absents si `withMuzzle` est faux (tireur à la lunette). Renvoie false si la réserve est pleine (le tir
-- garde le rayon ordinaire).
function CircuitTrace.spawn(start: Vector3, finish: Vector3, isLocal: boolean, withMuzzle: boolean): boolean
	local offset = finish - start
	local length = offset.Magnitude
	if length < 1e-3 then
		return false
	end
	local set = freeSet()
	if not set then
		return false
	end
	local forward = offset / length
	-- latéral : la verticale débarrassée de sa part le long du tir (tir à la verticale : l'axe X)
	local up = Vector3.yAxis - forward * forward:Dot(Vector3.yAxis)
	if up.Magnitude < 1e-3 then
		up = Vector3.xAxis - forward * forward:Dot(Vector3.xAxis)
	end
	set.origin = start
	set.forward = forward
	set.up = up.Unit
	set.finish = finish
	set.path = ShotEffectRules.circuitPath(length, function(min, max)
		return min + math.random() * (max - min)
	end)
	set.length = ShotEffectRules.circuitLength(set.path)
	-- place de chaque point sur la piste (studs depuis la bouche) et place relative de chaque segment
	local starts, places = {}, {}
	local walked = 0
	for i = 1, #set.path do
		if i > 1 then
			local a, b = set.path[i - 1], set.path[i]
			walked += math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		end
		starts[i] = walked
	end
	for i = 1, #set.path - 1 do
		places[i] = if set.length > 0 then starts[i] / set.length else 0
	end
	set.starts = starts
	set.places = places
	for i = 1, SEGMENTS do
		local used = i < #set.path
		set.cores[i].Enabled = used
		set.halos[i].Enabled = used
		set.steps[i] = -1
	end
	hideNet(set)
	set.impact = false
	set.born = os.clock()
	if withMuzzle then
		set.flashPart.Position = start
		set.flash.Size = NumberSequence.new(
			if isLocal then ShotEffectRules.CIRCUIT_FLASH_SIZE_LOCAL else ShotEffectRules.CIRCUIT_FLASH_SIZE
		)
		set.flash:Emit(1)
		local edge = if isLocal then ShotEffectRules.CIRCUIT_CUBE_MUZZLE_LOCAL else ShotEffectRules.CIRCUIT_CUBE_MUZZLE
		-- cube un peu devant la bouche : il ne s'enfonce pas dans le canon
		CircuitCube.spawn(start + forward * edge, edge, ShotEffectRules.CIRCUIT_CUBE_LIFE_MUZZLE)
	end
	pose(set, 0)
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
	return true
end

return CircuitTrace

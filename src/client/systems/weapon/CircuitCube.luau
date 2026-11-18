-- CircuitCube.luau
-- Composant en cube de l'effet de tir CIRCUIT (#567) : un cadre de douze arêtes néon magenta autour d'un cœur cubique
-- clair, qui jaillit (pop), tourne sur lui-même pour montrer son volume, puis s'efface. Un au canon au tir, un à l'impact
-- à l'arrivée de l'impulsion (CircuitTrace). Réglages et courbe dans ShotEffectRules (CIRCUIT_CUBE_*, circuitCubeFrame).
-- Réserve de CIRCUIT_CUBES cubes (Parts ancrées en matériau Neon, sans collision), créés au premier besoin puis
-- réutilisés : un tir ne crée aucune Instance. Chaque frame, taille et place de chaque pièce sont recalculées.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)

local CircuitCube = {}

CircuitCube.INSTANCE_NAME = "CircuitCube"

-- Pièce d'un cube : la Part, sa place dans un cube d'arête 1 (centre, demi-tailles), si c'est le cœur
type Piece = { part: BasePart, offset: Vector3, size: Vector3 }
-- Cube de la réserve : ses pièces, sa place, son arête (studs), son orientation de départ, son axe de rotation, sa vie,
-- son instant de départ (nil : libre)
type Cube = {
	pieces: { Piece },
	position: Vector3,
	edge: number,
	base: CFrame,
	axis: Vector3,
	life: number,
	born: number?,
}

local pool: { Cube } = {}
local folder: Folder? = nil
local stepConn: RBXScriptConnection? = nil
local PARKED = CFrame.new(0, -10000, 0)

-- Cette méthode permet de créer une pièce du cube (Part néon ancrée, sans collision ni requête) lorsqu'un cube de la
-- réserve est créé.
local function piece(parent: Instance, rgb: { number }, offset: Vector3, size: Vector3): Piece
	local part = Instance.new("Part")
	part.Name = CircuitCube.INSTANCE_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	part.Transparency = 1
	part.CFrame = PARKED
	part.Parent = parent
	return { part = part, offset = offset, size = size }
end

-- Cette méthode permet de créer un cube de la réserve (cœur et douze arêtes, rangés hors de vue) lorsqu'un tir en
-- demande un et que la réserve n'est pas pleine.
local function make(): Cube
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = CircuitCube.INSTANCE_NAME
		created.Parent = workspace
		folder = created
	end
	local model = Instance.new("Model")
	model.Name = CircuitCube.INSTANCE_NAME
	local pieces = {}
	local core = ShotEffectRules.CIRCUIT_CUBE_CORE
	table.insert(pieces, piece(model, ShotEffectRules.CIRCUIT_PULSE_RGB, Vector3.zero, Vector3.one * core))
	-- douze arêtes : quatre parallèles à chaque axe, aux coins de la face perpendiculaire
	local t = ShotEffectRules.CIRCUIT_CUBE_EDGE
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	for a = 1, 3 do
		local along = axes[a]
		local u, v = axes[a % 3 + 1], axes[(a + 1) % 3 + 1]
		for _, su in { -0.5, 0.5 } do
			for _, sv in { -0.5, 0.5 } do
				local size = along * (1 + t) + (u + v) * t
				table.insert(pieces, piece(model, ShotEffectRules.CIRCUIT_RGB, u * su + v * sv, size))
			end
		end
	end
	model.Parent = folder
	return {
		pieces = pieces,
		position = Vector3.zero,
		edge = 0,
		base = CFrame.identity,
		axis = Vector3.yAxis,
		life = 0,
		born = nil,
	}
end

-- Cette méthode permet de cacher un cube (pièces rangées hors de vue, transparentes) lorsque sa vie est finie.
local function park(cube: Cube)
	cube.born = nil
	for _, p in cube.pieces do
		p.part.Transparency = 1
		p.part.CFrame = PARKED
	end
end

-- Cette méthode permet de poser un cube à un instant de sa vie lorsqu'une frame passe : échelle du pop, rotation
-- autour de son axe, transparence du fondu (le cœur reste un peu plus opaque que le cadre).
local function pose(cube: Cube, elapsed: number)
	local scale, fade = ShotEffectRules.circuitCubeFrame(elapsed, cube.life)
	local s = math.max(scale, 0.02) * cube.edge
	local spin = math.rad(ShotEffectRules.CIRCUIT_CUBE_SPIN) * elapsed
	local frame = CFrame.new(cube.position) * CFrame.fromAxisAngle(cube.axis, spin) * cube.base
	for _, p in cube.pieces do
		p.part.Size = p.size * s
		p.part.CFrame = frame * CFrame.new(p.offset * s)
		p.part.Transparency = fade
	end
end

-- Cette méthode permet d'animer les cubes en cours lorsqu'une frame passe, de ranger ceux dont la vie est finie, et
-- d'arrêter la boucle sans cube.
local function step()
	local now = os.clock()
	local active = 0
	for _, cube in pool do
		local born = cube.born
		if born then
			local elapsed = now - born
			if elapsed >= cube.life or not cube.pieces[1].part.Parent then
				park(cube)
			else
				active += 1
				pose(cube, elapsed)
			end
		end
	end
	if active == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local timedStep = PerfMarkers.wrap("effets de tir", step)

-- Cette méthode permet de faire jaillir un cube lorsqu'un tir CIRCUIT le demande : centré sur `position`, d'arête
-- `edge` studs, vivant `life` s, tourné de CIRCUIT_CUBE_TILT degrés au hasard et pivotant autour d'un axe tiré au
-- hasard. Sans effet si la réserve est pleine.
function CircuitCube.spawn(position: Vector3, edge: number, life: number)
	local index: number? = nil
	for i, c in pool do
		if not c.born then
			index = i
			break
		end
	end
	if not index then
		if #pool >= ShotEffectRules.CIRCUIT_CUBES then
			return
		end
		table.insert(pool, make())
		index = #pool
	end
	local slot = index :: number
	if not pool[slot].pieces[1].part.Parent then -- détruit par un tiers : le recréer
		pool[slot] = make()
	end
	local c = pool[slot]
	local tilt = math.rad(ShotEffectRules.CIRCUIT_CUBE_TILT)
	c.position = position
	c.edge = edge
	c.base = CFrame.Angles(tilt * (math.random() * 2 - 1), tilt * (math.random() * 2 - 1), tilt)
	c.axis = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5).Unit
	c.life = life
	c.born = os.clock()
	pose(c, 0)
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
end

return CircuitCube

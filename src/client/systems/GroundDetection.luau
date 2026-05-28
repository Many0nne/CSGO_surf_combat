local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage.Shared.MovementConfig)
local CharacterDimensions = require(script.Parent.CharacterDimensions)

local CAST_RADIUS = Config.CHAR_RADIUS - 0.05
local HALF_HEIGHT = Config.CHAR_HEIGHT_STAND / 2
local CENTER_OFFSET = 0
local CAST_SKIN   = 0.5    -- augmenté de 0.15 : détection jusqu'à ~1.45 studs sous les pieds
local CAST_DIST   = HALF_HEIGHT + CAST_SKIN
local CAST_DIR    = Vector3.new(0, -CAST_DIST, 0)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

export type GroundInfo = {
	onGround    : boolean,
	normal      : Vector3,
	slopeAngle  : number,
	distance    : number,
	material    : Enum.Material,
	hitPosition : Vector3,
}

local GROUND_MISS: GroundInfo = {
	onGround    = false,
	normal      = Vector3.yAxis,
	slopeAngle  = 0,
	distance    = math.huge,
	material    = Enum.Material.Air,
	hitPosition = Vector3.zero,
}

local GroundDetection = {}

local function refreshDims()
	local stand = CharacterDimensions.getStand()
	CAST_RADIUS = stand.radius - 0.05
	HALF_HEIGHT = stand.halfHeight
	CENTER_OFFSET = stand.centerOffset
	CAST_DIST = HALF_HEIGHT + CAST_SKIN
	CAST_DIR = Vector3.new(0, -CAST_DIST, 0)
end

-- Appeler à chaque CharacterAdded pour exclure les parts du character du cast.
function GroundDetection.init(character: Model)
	params.FilterDescendantsInstances = { character }
	refreshDims()
end

-- Retourne l'état du sol sous rootPart.
function GroundDetection.getGroundInfo(rootPart: BasePart): GroundInfo
	local origin = rootPart.Position + Vector3.new(0, CENTER_OFFSET, 0)
	local result = workspace:Spherecast(origin, CAST_RADIUS, CAST_DIR, params)
	if not result then
		return GROUND_MISS
	end

	local normal     = result.Normal
	local cosAngle   = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
	local slopeAngle = math.deg(math.acos(cosAngle))

	-- Surface trop raide : non-marchable, le joueur reste en l'air (équivalent CategorizePosition Source).
	local onGround = slopeAngle <= Config.SLOPE_ANGLE_MAX

	return {
		onGround    = onGround,
		normal      = normal,
		slopeAngle  = slopeAngle,
		distance    = result.Distance - HALF_HEIGHT,
		material    = result.Material,
		hitPosition = result.Position,
	}
end

return GroundDetection

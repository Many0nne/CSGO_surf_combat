local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.MovementConfig)

local CAST_RADIUS = Config.CHAR_RADIUS - 0.05
local HALF_HEIGHT = Config.CHAR_HEIGHT_STAND / 2
local CAST_SKIN   = 0.15
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

-- Appeler à chaque CharacterAdded pour exclure les parts du character du cast.
function GroundDetection.init(character: Model)
	params.FilterDescendantsInstances = { character }
end

-- Retourne l'état du sol sous rootPart.
function GroundDetection.getGroundInfo(rootPart: BasePart): GroundInfo
	local result = workspace:Spherecast(rootPart.Position, CAST_RADIUS, CAST_DIR, params)
	if not result then
		return GROUND_MISS
	end

	local normal     = result.Normal
	local cosAngle   = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
	local slopeAngle = math.deg(math.acos(cosAngle))

	return {
		onGround    = true,
		normal      = normal,
		slopeAngle  = slopeAngle,
		distance    = result.Distance - HALF_HEIGHT,
		material    = result.Material,
		hitPosition = result.Position,
	}
end

return GroundDetection

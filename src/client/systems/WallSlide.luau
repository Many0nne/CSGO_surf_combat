local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config       = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local RADIUS = Config.CHAR_RADIUS - 0.05

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local WallSlide = {}

function WallSlide.init(character: Model)
	castParams.FilterDescendantsInstances = { character }
end

-- Résout la collision de mur pour un déplacement aérien.
-- Retourne (newVelocity, moveVec) où moveVec est le déplacement à appliquer ce tick.
function WallSlide.resolve(hrp: BasePart, velocity: Vector3, dt: number): (Vector3, Vector3)
	local moveVec = velocity * dt
	if moveVec.Magnitude < 1e-5 then return velocity, moveVec end

	local hit = workspace:Spherecast(hrp.Position, RADIUS, moveVec, castParams)
	if not hit then return velocity, moveVec end

	local newVelocity = PhysicsUtils.projectOnPlane(velocity, hit.Normal)
	return newVelocity, newVelocity * dt
end

return WallSlide

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local HeadCollisionResolver = {}

local castParams: RaycastParams

function HeadCollisionResolver.init(char: Model)
	castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { char, workspace.CurrentCamera }
end

function HeadCollisionResolver.getHeadHitAlongMove(startPos: Vector3, moveVec: Vector3, radius: number): RaycastResult?
	if moveVec.Magnitude < 1e-4 then return nil end
	return workspace:Spherecast(startPos, radius, moveVec, castParams)
end

function HeadCollisionResolver.resolve(
	moveVec: Vector3,
	hrpPos: Vector3,
	info: { rootToTop: number, radius: number }
): (Vector3, boolean)
	if moveVec.Magnitude < 1e-4 then return moveVec, false end

	local headCenter = Vector3.new(
		hrpPos.X,
		hrpPos.Y + info.rootToTop - info.radius,
		hrpPos.Z
	)
	local hit = workspace:Spherecast(headCenter, info.radius, moveVec, castParams)
	if not hit then return moveVec, false end

	local isCeiling = hit.Normal.Y < -0.15
	local isHeadWall = not isCeiling and math.abs(hit.Normal.Y) < 0.65
	if not isCeiling and not isHeadWall then return moveVec, false end

	local clipped = PhysicsUtils.projectOnPlane(moveVec, hit.Normal)
	if isCeiling then
		clipped = Vector3.new(clipped.X, math.min(0, clipped.Y), clipped.Z)
	end

	return clipped, true
end

return HeadCollisionResolver

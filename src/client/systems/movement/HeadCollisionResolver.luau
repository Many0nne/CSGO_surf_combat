local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local HeadCollisionResolver = {}

local castParams: RaycastParams

local SKIN = 0.05 -- studs, marge anti-pénétration


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

	local dir = moveVec.Unit
	local dist = moveVec.Magnitude
	-- on recule de SKIN : détecte le contact AVANT la pénétration
	local hit = workspace:Spherecast(headCenter - dir * SKIN, info.radius, dir * (dist + SKIN), castParams)
	if not hit then return moveVec, false end

	-- on ne clippe que si on RENTRE dans la surface (sinon on annulerait la séparation)
	if moveVec:Dot(hit.Normal) >= 0 then return moveVec, false end

	local clipped = PhysicsUtils.projectOnPlane(moveVec, hit.Normal)
	if hit.Normal.Y < -0.15 then -- plafond : pas de composante verticale positive résiduelle
		clipped = Vector3.new(clipped.X, math.min(0, clipped.Y), clipped.Z)
	end

	return clipped, true
end

local lastSafeCenter: Vector3? = nil

local function headCenterOf(hrpPos, info)
	return Vector3.new(hrpPos.X, hrpPos.Y + info.rootToTop - info.radius, hrpPos.Z)
end

-- renvoie le déplacement réellement applicable + la vélocité clippée
function HeadCollisionResolver.sweep(moveVec, hrpPos, info)
	local from = lastSafeCenter or headCenterOf(hrpPos, info)
	local target = headCenterOf(hrpPos, info) + moveVec
	local delta = target - from
	if delta.Magnitude < 1e-4 then lastSafeCenter = from; return moveVec, moveVec, false end

	local hit = workspace:Spherecast(from, info.radius, delta, castParams)
	if not hit then
		lastSafeCenter = target
		return moveVec, moveVec, false
	end

	local allowed = math.max(0, hit.Distance - SKIN)
	local stop = from + delta.Unit * allowed
	lastSafeCenter = stop

	local vel = moveVec
	if moveVec:Dot(hit.Normal) < 0 then
		vel = PhysicsUtils.projectOnPlane(moveVec, hit.Normal)
		if hit.Normal.Y < -0.15 then
			vel = Vector3.new(vel.X, math.min(0, vel.Y), vel.Z)
		end
	end

	local appliedMove = stop - headCenterOf(hrpPos, info) -- déplacement à appliquer cette frame
	return appliedMove, vel, true
end

return HeadCollisionResolver

-- Collisions de la tête (plafond, mur haut) pendant un déplacement. Une instance par personnage (#139).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local HeadCollisionResolver = {}
HeadCollisionResolver.__index = HeadCollisionResolver

export type HeadCollisionResolver = typeof(setmetatable(
	{} :: { castParams: RaycastParams, lastSafeCenter: Vector3? },
	HeadCollisionResolver
))

local SKIN = 0.05 -- studs, marge anti-pénétration

-- Cette méthode permet de préparer les collisions de tête d'un personnage lorsqu'il apparaît (ses pièces exclues).
function HeadCollisionResolver.new(char: Model): HeadCollisionResolver
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { char, workspace.CurrentCamera }
	return setmetatable({ castParams = castParams, lastSafeCenter = nil }, HeadCollisionResolver)
end

function HeadCollisionResolver.getHeadHitAlongMove(
	self: HeadCollisionResolver,
	startPos: Vector3,
	moveVec: Vector3,
	radius: number
): RaycastResult?
	if moveVec.Magnitude < 1e-4 then
		return nil
	end
	return workspace:Spherecast(startPos, radius, moveVec, self.castParams)
end

function HeadCollisionResolver.resolve(
	self: HeadCollisionResolver,
	moveVec: Vector3,
	hrpPos: Vector3,
	info: { rootToTop: number, radius: number }
): (Vector3, boolean)
	if moveVec.Magnitude < 1e-4 then
		return moveVec, false
	end

	local headCenter = Vector3.new(hrpPos.X, hrpPos.Y + info.rootToTop - info.radius, hrpPos.Z)

	local dir = moveVec.Unit
	local dist = moveVec.Magnitude
	-- on recule de SKIN : détecte le contact AVANT la pénétration
	local hit = workspace:Spherecast(headCenter - dir * SKIN, info.radius, dir * (dist + SKIN), self.castParams)
	if not hit then
		return moveVec, false
	end

	-- on ne clippe que si on RENTRE dans la surface (sinon on annulerait la séparation)
	if moveVec:Dot(hit.Normal) >= 0 then
		return moveVec, false
	end

	local clipped = PhysicsUtils.projectOnPlane(moveVec, hit.Normal)
	if hit.Normal.Y < -0.15 then -- plafond : pas de composante verticale positive résiduelle
		clipped = Vector3.new(clipped.X, math.min(0, clipped.Y), clipped.Z)
	end

	return clipped, true
end

local function headCenterOf(hrpPos, info)
	return Vector3.new(hrpPos.X, hrpPos.Y + info.rootToTop - info.radius, hrpPos.Z)
end

-- renvoie le déplacement réellement applicable + la vélocité clippée
function HeadCollisionResolver.sweep(self: HeadCollisionResolver, moveVec, hrpPos, info)
	local from = self.lastSafeCenter or headCenterOf(hrpPos, info)
	local target = headCenterOf(hrpPos, info) + moveVec
	local delta = target - from
	if delta.Magnitude < 1e-4 then
		self.lastSafeCenter = from
		return moveVec, moveVec, false
	end

	local hit = workspace:Spherecast(from, info.radius, delta, self.castParams)
	if not hit then
		self.lastSafeCenter = target
		return moveVec, moveVec, false
	end

	local allowed = math.max(0, hit.Distance - SKIN)
	local stop = from + delta.Unit * allowed
	self.lastSafeCenter = stop

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

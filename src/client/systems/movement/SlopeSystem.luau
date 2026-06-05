local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config       = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local GRAVITY_VEC = Vector3.new(0, Config.GRAVITY, 0)

local SlopeSystem = {}

-- Projette wishdir sur le plan de la pente (pentes douces ≤ 45°).
function SlopeSystem.projectWishDir(wishdir: Vector3, surfaceNormal: Vector3): Vector3
	return PhysicsUtils.safeNormalize(PhysicsUtils.projectOnPlane(wishdir, surfaceNormal))
end

-- Applique le modèle physique complet de glissement sur pente (> 45°) :
--   1. Projection de la velocity sur le plan (contrainte de surface)
--   2. Décomposition gravité → g_parallel (moteur) + g_perp (force normale)
--   3. Friction proportionnelle à la force normale (s'oppose au mouvement)
--   4. Accélération gravitationnelle parallèle à la pente
function SlopeSystem.slideStep(velocity: Vector3, surfaceNormal: Vector3, dt: number): Vector3
	-- 1. Projeter la velocity sur le plan de la pente (élimine la dérive perpendiculaire)
	velocity = PhysicsUtils.projectOnPlane(velocity, surfaceNormal)

	-- 2. Décomposer la gravité
	local g_parallel = PhysicsUtils.projectOnPlane(GRAVITY_VEC, surfaceNormal)
	local g_perp     = GRAVITY_VEC - g_parallel  -- composante dans la normale → force normale

	-- 3. Friction proportionnelle à la force normale (s'oppose au mouvement dans les deux sens)
	local speed = velocity.Magnitude
	if speed > 1e-4 then
		local frictionDecel = math.min(Config.SLOPE_FRICTION * g_perp.Magnitude * dt, speed)
		velocity = velocity - velocity.Unit * frictionDecel
	end

	-- 4. Gravité parallèle à la pente (accélère vers le bas de la pente)
	velocity = velocity + g_parallel * dt

	return velocity
end

return SlopeSystem

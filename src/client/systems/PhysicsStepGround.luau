local PhysicsUtils = require(game:GetService("ReplicatedStorage").Shared.PhysicsUtils)
local Config       = require(game:GetService("ReplicatedStorage").Shared.MovementConfig)

local PhysicsStepGround = {}

-- Applique friction puis accélération Source au sol.
-- velocityXZ : vitesse horizontale entrante (Y ignoré)
-- wishdir    : direction normalisée souhaitée (Vector3 XZ)
-- wishspeed  : vitesse cible (run / walk / backward)
-- Retourne le nouveau vecteur XZ.
function PhysicsStepGround.step(
	velocityXZ: Vector3,
	wishdir: Vector3,
	wishspeed: number,
	dt: number
): Vector3
	local v = PhysicsUtils.applyFriction(velocityXZ, Config.FRICTION, Config.STOP_SPEED, dt)
	v = PhysicsUtils.accelerate(v, wishdir, wishspeed, Config.GROUND_ACCEL, dt)
	return v
end

return PhysicsStepGround

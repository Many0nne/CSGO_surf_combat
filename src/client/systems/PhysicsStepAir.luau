local PhysicsUtils = require(game:GetService("ReplicatedStorage").Shared.PhysicsUtils)
local Config       = require(game:GetService("ReplicatedStorage").Shared.MovementConfig)

local PhysicsStepAir = {}

-- Applique l'accélération aérienne Source (air strafe, sans friction).
-- Modèle Source: wishspeed capé (GetAirSpeedCap), accel * wishspeed * dt.
function PhysicsStepAir.step(velocity: Vector3, wishdir: Vector3, wishspeed: number, dt: number): Vector3
	if wishdir.Magnitude < 1e-4 then
		return velocity
	end

	local airWishspeed = math.min(wishspeed, Config.AIR_SPEED_CAP)

	-- Mode air pur : XZ uniquement, Y géré séparément par la gravité
	local xz           = PhysicsUtils.getXZ(velocity)
	local currentSpeed = xz:Dot(wishdir)
	local addSpeed     = airWishspeed - currentSpeed
	if addSpeed <= 0 then return velocity end

	local accelSpeed = math.min(Config.AIR_ACCEL * airWishspeed * dt, addSpeed)
	return PhysicsUtils.setXZ(velocity, xz + wishdir * accelSpeed)
end

return PhysicsStepAir

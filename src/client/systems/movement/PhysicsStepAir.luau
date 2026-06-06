local Config       = require(game:GetService("ReplicatedStorage").Shared.MovementConfig)

local PhysicsStepAir = {}

-- Applique l'accélération aérienne Source (air strafe, sans friction).
-- Modèle Source: dot 3D sur velocity complète (Y inclus), accel * wishspeed * dt * surfaceFriction.
function PhysicsStepAir.step(velocity: Vector3, wishdir: Vector3, wishspeed: number, surfaceFriction: number, dt: number): Vector3
	if wishdir.Magnitude < 1e-4 then
		return velocity
	end

	local airWishspeed = math.min(wishspeed, Config.AIR_SPEED_CAP)

	-- Source: dot produit 3D (Y inclus) — sur une rampe, la composante Y est significative
	local currentSpeed = velocity:Dot(wishdir)
	local addSpeed     = airWishspeed - currentSpeed
	if addSpeed <= 0 then return velocity end

	-- Source: accel * wishspeed (non-cappé) * dt * surfaceFriction
	local accelSpeed = math.min(Config.AIR_ACCEL * wishspeed * dt * surfaceFriction, addSpeed)
	return velocity + wishdir * accelSpeed
end

return PhysicsStepAir

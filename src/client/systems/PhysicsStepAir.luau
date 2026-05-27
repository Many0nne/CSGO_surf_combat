local PhysicsUtils = require(game:GetService("ReplicatedStorage").Shared.PhysicsUtils)
local Config       = require(game:GetService("ReplicatedStorage").Shared.MovementConfig)

local PhysicsStepAir = {}

-- Applique l'accélération aérienne Source (air strafe, sans friction).
-- surfNormal : si fourni, wishdir est projeté sur le plan de la rampe (mode surf).
-- En mode surf l'accélération opère en 3D ; en air pur sur XZ uniquement.
-- Dans les deux cas, wishspeed est plafonné à Config.AIR_SPEED_CAP pour le calcul de addSpeed
-- (équivalent de GetAirSpeedCap() dans Source — élargit la fenêtre d'angle utile).
function PhysicsStepAir.step(velocity: Vector3, wishdir: Vector3, wishspeed: number, dt: number, surfNormal: Vector3?): Vector3
	if wishdir.Magnitude < 1e-4 then
		return velocity
	end

	local airWishspeed = math.min(wishspeed, Config.AIR_SPEED_CAP)

	if surfNormal then
		-- Mode surf : projeter wishdir sur le plan de la rampe, travailler en 3D
		local projDir = PhysicsUtils.safeNormalize(PhysicsUtils.projectOnPlane(wishdir, surfNormal))
		if projDir.Magnitude < 1e-4 then return velocity end

		local currentSpeed = velocity:Dot(projDir)
		local addSpeed     = airWishspeed - currentSpeed
		if addSpeed <= 0 then return velocity end

		local accelSpeed = math.min(Config.AIR_ACCEL * dt, addSpeed)
		return velocity + projDir * accelSpeed
	else
		-- Mode air pur : XZ uniquement, Y géré séparément par la gravité
		local xz           = PhysicsUtils.getXZ(velocity)
		local currentSpeed = xz:Dot(wishdir)
		local addSpeed     = airWishspeed - currentSpeed
		if addSpeed <= 0 then return velocity end

		local accelSpeed = math.min(Config.AIR_ACCEL * dt, addSpeed)
		return PhysicsUtils.setXZ(velocity, xz + wishdir * accelSpeed)
	end
end

return PhysicsStepAir

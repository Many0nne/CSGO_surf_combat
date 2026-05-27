local PhysicsUtils = {}

-- Retourne la composante XZ d'un Vector3 (Y = 0)
function PhysicsUtils.getXZ(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Remplace les composantes XZ en conservant Y
function PhysicsUtils.setXZ(v: Vector3, xz: Vector3): Vector3
	return Vector3.new(xz.X, v.Y, xz.Z)
end

-- Normalise un vecteur sans erreur si magnitude == 0
function PhysicsUtils.safeNormalize(v: Vector3): Vector3
	local mag = v.Magnitude
	if mag < 1e-6 then
		return Vector3.zero
	end
	return v / mag
end

-- Projette v sur un plan défini par sa normale
function PhysicsUtils.projectOnPlane(v: Vector3, normal: Vector3): Vector3
	return v - normal * v:Dot(normal)
end

-- Lerp entre deux Vector3
function PhysicsUtils.lerpV3(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

-- Angle en degrés entre deux vecteurs (robuste aux vecteurs nuls)
function PhysicsUtils.angleDeg(a: Vector3, b: Vector3): number
	local magA, magB = a.Magnitude, b.Magnitude
	if magA < 1e-6 or magB < 1e-6 then
		return 0
	end
	local cosAngle = math.clamp(a:Dot(b) / (magA * magB), -1, 1)
	return math.deg(math.acos(cosAngle))
end

-- Applique la friction Source à la vitesse horizontale
-- Retourne la nouvelle vitesse XZ
function PhysicsUtils.applyFriction(
	velocityXZ: Vector3,
	friction: number,
	stopSpeed: number,
	dt: number
): Vector3
	local speed = velocityXZ.Magnitude
	if speed < 1e-4 then
		return Vector3.zero
	end
	local control = math.max(speed, stopSpeed)
	local drop = control * friction * dt
	local newSpeed = math.max(speed - drop, 0)
	return velocityXZ * (newSpeed / speed)
end

-- Applique l'accélération Source (ground ou air) à la vitesse horizontale
-- Retourne la nouvelle vitesse XZ
function PhysicsUtils.accelerate(
    velocityXZ: Vector3,
    wishdir: Vector3,
    wishspeed: number,
    accel: number,
    dt: number
): Vector3
    local currentSpeed = velocityXZ:Dot(wishdir)
    local addSpeed = wishspeed - currentSpeed

    -- Ne pas limiter addSpeed, même si currentSpeed < 0
    if addSpeed <= 0 then
        return velocityXZ
    end

    local accelSpeed = math.min(accel * dt, addSpeed)
    return velocityXZ + wishdir * accelSpeed
end

return PhysicsUtils

-- ViewmodelMotion.luau
-- Couche procédurale du viewmodel (#19) : sway (retard sur la rotation caméra), bob de marche/course, inclinaison
-- en strafe et impact d'atterrissage. Module pur : retourne un décalage CFrame dans le repère caméra.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.ViewmodelConfig)

local ViewmodelMotion = {}
ViewmodelMotion.__index = ViewmodelMotion

export type MotionInput = {
	speed: number, -- vitesse horizontale (studs/s)
	lateral: number, -- vitesse le long de la droite caméra (studs/s, + = vers la droite)
	onGround: boolean,
	verticalSpeed: number,
}

-- Cette méthode permet d'avancer un ressort amorti d'un pas dt lorsqu'une valeur doit suivre une cible en douceur.
function ViewmodelMotion.spring(pos: Vector3, vel: Vector3, target: Vector3, speed: number, damping: number, dt: number)
	local accel = (target - pos) * (speed * speed) - vel * (2 * damping * speed)
	vel += accel * dt
	pos += vel * dt
	return pos, vel
end

-- Cette méthode permet de borner chaque composante d'un vecteur lorsqu'un sway ne doit pas dépasser son maximum.
local function clampVec(v: Vector3, max: number): Vector3
	return Vector3.new(math.clamp(v.X, -max, max), math.clamp(v.Y, -max, max), math.clamp(v.Z, -max, max))
end

-- Cette méthode permet de calculer le décalage de bob à une phase donnée lorsqu'on marche (figure en 8) ;
-- weight vaut 0 à l'arrêt ou en l'air et ~1 à pleine vitesse de course.
function ViewmodelMotion.bobOffset(phase: number, weight: number): (Vector3, number)
	local x = math.sin(phase) * Config.BOB_AMP_X * weight
	local y = -math.abs(math.sin(phase)) * Config.BOB_AMP_Y * weight
	local roll = math.sin(phase) * Config.BOB_ROLL * weight
	return Vector3.new(x, y, 0), roll
end

-- Cette méthode permet de créer l'état procédural lorsqu'un viewmodel est actif.
function ViewmodelMotion.new()
	local self = setmetatable({}, ViewmodelMotion)
	self:reset()
	return self
end

-- Cette méthode permet de remettre l'état à zéro lorsque l'arme change ou que le personnage réapparaît.
function ViewmodelMotion:reset()
	self.lastCam = nil :: CFrame?
	self.rotPos, self.rotVel = Vector3.zero, Vector3.zero
	self.posPos, self.posVel = Vector3.zero, Vector3.zero
	self.bobPhase = 0
	self.bobWeight = 0
	self.tilt = 0
	self.land, self.landVel = Vector3.zero, Vector3.zero
	self.wasGrounded = true
	self.fallSpeed = 0
end

-- Cette méthode permet de calculer le décalage procédural de la frame lorsqu'on connaît la caméra et le mouvement.
function ViewmodelMotion:update(dt: number, camCFrame: CFrame, motion: MotionInput): CFrame
	if dt <= 0 then
		dt = 1 / 60
	end

	-- Sway : vitesse angulaire de la caméra ramenée à une frame de 60 Hz pour ne pas dépendre du framerate
	local lastCam = self.lastCam or camCFrame
	self.lastCam = camCFrame
	local dPitch, dYaw = lastCam:ToObjectSpace(camCFrame):ToOrientation()
	local frameScale = (1 / 60) / dt
	local pitchDeg = math.deg(dPitch) * frameScale
	local yawDeg = math.deg(dYaw) * frameScale
	local rotTarget = clampVec(
		Vector3.new(-pitchDeg, -yawDeg, -yawDeg * Config.SWAY_ROLL_PER_YAW) * Config.SWAY_ROT_PER_DEG,
		Config.SWAY_MAX_ROT
	)
	-- L'arme reste en arrière : tourner à gauche la décale à droite, lever les yeux la fait descendre
	local posTarget = clampVec(Vector3.new(yawDeg, -pitchDeg, 0) * Config.SWAY_POS_PER_DEG, Config.SWAY_MAX_POS)
	self.rotPos, self.rotVel = ViewmodelMotion.spring(
		self.rotPos,
		self.rotVel,
		rotTarget,
		Config.SWAY_SPRING_SPEED,
		Config.SWAY_SPRING_DAMPING,
		dt
	)
	self.posPos, self.posVel = ViewmodelMotion.spring(
		self.posPos,
		self.posVel,
		posTarget,
		Config.SWAY_SPRING_SPEED,
		Config.SWAY_SPRING_DAMPING,
		dt
	)

	-- Bob : poids lissé selon la vitesse au sol, phase qui avance avec la cadence des pas
	local speedRatio = math.clamp(motion.speed / Config.BOB_REF_SPEED, 0, 1.25)
	local targetWeight = motion.onGround and speedRatio or 0
	local fade = 1 - math.exp(-Config.BOB_FADE_SPEED * dt)
	self.bobWeight += (targetWeight - self.bobWeight) * fade
	if self.bobWeight > 0.005 then
		local freq = Config.BOB_FREQ * math.max(Config.BOB_FREQ_MIN_SCALE, speedRatio)
		self.bobPhase = (self.bobPhase + dt * freq * math.pi) % (2 * math.pi)
	end
	local bobPos, bobRoll = ViewmodelMotion.bobOffset(self.bobPhase, self.bobWeight)

	-- Inclinaison en strafe : roulis vers le côté où l'on se déplace
	local tiltTarget = math.clamp(motion.lateral / Config.BOB_REF_SPEED, -1, 1) * Config.STRAFE_TILT_MAX
	self.tilt += (tiltTarget - self.tilt) * (1 - math.exp(-Config.STRAFE_TILT_SPEED * dt))

	-- Atterrissage : impulsion vers le bas proportionnelle à la vitesse de chute
	if motion.onGround and not self.wasGrounded and self.fallSpeed >= Config.LAND_MIN_SPEED then
		local kick = math.min(self.fallSpeed * Config.LAND_KICK_PER_SPEED, Config.LAND_KICK_MAX)
		self.landVel -= Vector3.new(0, kick * Config.LAND_SPRING_SPEED, 0)
	end
	if not motion.onGround then
		self.fallSpeed = math.max(0, -motion.verticalSpeed)
	end
	self.wasGrounded = motion.onGround
	self.land, self.landVel = ViewmodelMotion.spring(
		self.land,
		self.landVel,
		Vector3.zero,
		Config.LAND_SPRING_SPEED,
		Config.LAND_SPRING_DAMPING,
		dt
	)

	local pos = self.posPos + bobPos + self.land
	local rot = self.rotPos + Vector3.new(self.land.Y * 12, 0, bobRoll - self.tilt)
	return CFrame.new(pos) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

return ViewmodelMotion

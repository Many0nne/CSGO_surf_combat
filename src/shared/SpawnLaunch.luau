-- Règles pures du lancement depuis le soleil (#69) : le serveur projette le joueur depuis un point
-- Maps.Map.SunLaunch.* (LookVector = direction, attribut Speed), le client applique la vitesse et oriente la caméra.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local SpawnLaunch = {}

-- Attributs posés par le serveur sur le personnage, lus par MovementController
SpawnLaunch.ORIGIN_ATTRIBUTE = "LaunchOrigin"
SpawnLaunch.VELOCITY_ATTRIBUTE = "LaunchVelocity"

-- Inclinaison de la caméra au lancement : on regarde la ville en contrebas sans fixer le sol
local PITCH_MIN = -30
local PITCH_MAX = 10

-- Cette méthode permet de calculer la vitesse de lancement lorsqu'un point de lancement donne sa direction
-- (LookVector) et sa vitesse en studs/s, bornée entre 0 et la limite du serveur MAX_SPEED_SERVER (#212).
function SpawnLaunch.velocity(direction: Vector3, speed: number): Vector3
	if speed ~= speed then
		return Vector3.zero -- NaN : attribut corrompu
	end
	return direction.Unit * math.clamp(speed, 0, MovementConfig.MAX_SPEED_SERVER)
end

-- Cette méthode permet de convertir une direction en angles de FPSCamera (yaw, pitch en degrés) lorsque le joueur
-- doit regarder là où il est projeté. Convention de FPSCamera : CFrame.Angles(0, rad(-yaw), 0) * CFrame.Angles(rad(pitch), 0, 0).
function SpawnLaunch.cameraAngles(direction: Vector3): (number, number)
	local d = direction.Unit
	local yaw = math.deg(math.atan2(d.X, -d.Z))
	local pitch = math.clamp(math.deg(math.asin(math.clamp(d.Y, -1, 1))), PITCH_MIN, PITCH_MAX)
	return yaw, pitch
end

return SpawnLaunch

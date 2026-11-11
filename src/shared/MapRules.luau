-- Règles pures des maps : boosts de vitesse posés dans Maps.Map.Boosts et hauteur de mort sous l'île.
-- Le client détecte et applique les boosts (MovementController via BoostSystem), le serveur tue sous KillHeight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local MapRules = {}

-- Dossier des boosts dans Maps.Map, et attributs posés par le générateur sur chaque volume déclencheur
MapRules.BOOSTS_FOLDER = "Boosts"
MapRules.KIND_ATTRIBUTE = "Kind" -- "Geyser" | "Launcher" | "Portal"
MapRules.VELOCITY_ATTRIBUTE = "Velocity" -- Geyser, Launcher : vitesse imposée (Vector3, studs/s)
MapRules.BOOST_ATTRIBUTE = "Boost" -- Portal : vitesse ajoutée dans le sens du mouvement (studs/s)
MapRules.COOLDOWN_ATTRIBUTE = "Cooldown" -- secondes avant de pouvoir reprendre le même boost

-- Attribut de Maps.Map : sous cette hauteur, le joueur est tombé de l'île et meurt
MapRules.KILL_HEIGHT_ATTRIBUTE = "KillHeight"

MapRules.DEFAULT_COOLDOWN = { Geyser = 3, Launcher = 3, Portal = 1 }

-- Cette méthode permet de savoir si un point est dans le volume d'un boost (boîte orientée) lorsqu'on teste
-- la position du joueur ; margin élargit la boîte (rayon du personnage).
function MapRules.contains(cf: CFrame, size: Vector3, pos: Vector3, margin: number): boolean
	local p = cf:PointToObjectSpace(pos)
	return math.abs(p.X) <= size.X / 2 + margin
		and math.abs(p.Y) <= size.Y / 2 + margin
		and math.abs(p.Z) <= size.Z / 2 + margin
end

-- Cette méthode permet de borner la vitesse imposée par un geyser ou un lanceur lorsqu'il se déclenche (#212) :
-- même direction, norme ramenée à la limite du serveur (MAX_SPEED_SERVER) si la map en déclare plus.
function MapRules.imposedVelocity(setVelocity: Vector3): Vector3
	local maxSpeed = MovementConfig.MAX_SPEED_SERVER
	local speed = setVelocity.Magnitude
	if speed <= maxSpeed then
		return setVelocity
	end
	return setVelocity * (maxSpeed / speed)
end

-- Cette méthode permet de calculer la vitesse après un boost lorsqu'un joueur le déclenche :
-- Geyser et Launcher imposent leur vitesse (norme bornée par imposedVelocity), Portal ajoute `boost` à la vitesse
-- horizontale (sens du mouvement, ou `forward` si le joueur est presque à l'arrêt), plafonnée à maxSpeed
-- (MAX_HORIZONTAL_SPEED). nil si le boost est mal configuré.
function MapRules.velocityAfter(
	kind: string,
	velocity: Vector3,
	setVelocity: Vector3?,
	boost: number?,
	forward: Vector3,
	maxSpeed: number
): Vector3?
	if kind == "Geyser" or kind == "Launcher" then
		return if typeof(setVelocity) == "Vector3" then MapRules.imposedVelocity(setVelocity) else nil
	end
	if kind ~= "Portal" or type(boost) ~= "number" then
		return nil
	end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local dir = if flat.Magnitude > 1 then flat.Unit else Vector3.new(forward.X, 0, forward.Z)
	if dir.Magnitude < 1e-3 then
		return nil
	end
	dir = dir.Unit
	local speed = math.max(flat.Magnitude, math.min(flat.Magnitude + boost, maxSpeed))
	return Vector3.new(dir.X * speed, velocity.Y, dir.Z * speed)
end

-- Cette méthode permet de savoir si un joueur est tombé de l'île lorsque la map déclare une hauteur de mort.
function MapRules.isBelowKillHeight(y: number, killHeight: any): boolean
	return type(killHeight) == "number" and y < killHeight
end

-- Cette méthode permet de calculer la vitesse de départ d'un saut balistique lorsqu'on veut atteindre `to`
-- depuis `from` en `time` secondes sous la gravité `gravity` (négative), sans contrôle en l'air.
function MapRules.ballisticVelocity(from: Vector3, to: Vector3, time: number, gravity: number): Vector3
	local d = to - from
	return Vector3.new(d.X / time, d.Y / time - 0.5 * gravity * time, d.Z / time)
end

return MapRules

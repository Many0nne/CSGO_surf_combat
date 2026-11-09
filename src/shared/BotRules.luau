-- Règles pures des bots (#133), testées (tests/specs/BotRules.spec.luau) : cap et regard, gêne, choix du nom et du
-- nombre de bots demandé en Studio. Règles de navigation : NavRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)

local BotRules = {}

-- Cette méthode permet de convertir le cap d'un bot (degrés, convention de la caméra FPS) en direction de marche
-- horizontale lorsqu'il avance tout droit.
function BotRules.headingDir(yawDeg: number): Vector3
	local r = math.rad(yawDeg)
	return Vector3.new(math.sin(r), 0, -math.cos(r))
end

-- Cette méthode permet de donner l'orientation de la racine d'un bot qui regarde vers son cap lorsqu'il bouge.
function BotRules.headingRotation(yawDeg: number): CFrame
	return CFrame.Angles(0, math.rad(-yawDeg), 0)
end

-- Cette méthode permet de donner le cap (degrés, convention de la caméra FPS) d'une direction horizontale lorsque le
-- bot doit regarder où il va ; nil pour une direction nulle.
function BotRules.yawOf(dir: Vector3): number?
	if dir.X * dir.X + dir.Z * dir.Z < 1e-8 then
		return nil
	end
	return math.deg(math.atan2(dir.X, -dir.Z)) % 360
end

-- Cette méthode permet de tourner le regard du bot vers un cap à vitesse limitée lorsqu'il change de direction
-- (rate en °/s), par le plus court côté.
function BotRules.turnToward(yawDeg: number, targetDeg: number, rate: number, dt: number): number
	local delta = (targetDeg - yawDeg + 180) % 360 - 180
	local maxStep = rate * dt
	return (yawDeg + math.clamp(delta, -maxStep, maxStep)) % 360
end

-- Cette méthode permet de mettre à jour le temps passé gêné lorsqu'un tick au sol est joué : il grandit tant que la
-- vitesse au sol reste sous STUCK_SPEED_RATIO de la vitesse voulue, et revient à 0 sinon (ou en l'air).
function BotRules.stuckTime(previous: number, grounded: boolean, speed: number, wishSpeed: number, dt: number): number
	if not grounded or wishSpeed <= 0 or speed >= wishSpeed * BotConfig.STUCK_SPEED_RATIO then
		return 0
	end
	return previous + dt
end

-- Cette méthode permet de donner un nom à un nouveau bot lorsqu'il entre en jeu : le premier nom de la liste qui
-- n'est pas déjà porté, sinon un nom numéroté.
function BotRules.pickName(taken: { [string]: boolean }): string
	for _, name in BotConfig.NAMES do
		if not taken[name] then
			return name
		end
	end
	local n = #BotConfig.NAMES + 1
	while taken["Bot" .. n] do
		n += 1
	end
	return "Bot" .. n
end

-- Cette méthode permet de lire le nombre de bots demandé par l'attribut de debug lorsqu'il change : entier borné à
-- [0, MAX_BOTS], 0 pour une valeur absente ou invalide.
function BotRules.requestedCount(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, BotConfig.MAX_BOTS)
end

return BotRules

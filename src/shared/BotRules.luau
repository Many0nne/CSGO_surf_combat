-- Règles pures des bots (#133), testées (tests/specs/BotRules.spec.luau). Étape 3/9 (#139) : marche d'essai
-- (direction, sauts, demi-tour quand il est gêné), choix du nom et du nombre de bots demandé en Studio.
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

-- Cette méthode permet de tirer le délai avant le prochain saut lorsque le bot vient de sauter ; roll ∈ [0, 1].
function BotRules.nextJumpDelay(roll: number): number
	return BotConfig.WANDER_JUMP_MIN + (BotConfig.WANDER_JUMP_MAX - BotConfig.WANDER_JUMP_MIN) * roll
end

-- Cette méthode permet de mettre à jour le temps passé gêné lorsqu'un tick au sol est joué : il grandit tant que la
-- vitesse au sol reste sous STUCK_SPEED_RATIO de la vitesse voulue, et revient à 0 sinon (ou en l'air).
function BotRules.stuckTime(previous: number, grounded: boolean, speed: number, wishSpeed: number, dt: number): number
	if not grounded or wishSpeed <= 0 or speed >= wishSpeed * BotConfig.STUCK_SPEED_RATIO then
		return 0
	end
	return previous + dt
end

-- Cette méthode permet de savoir si le bot doit faire demi-tour lorsqu'il est gêné depuis stuck secondes.
function BotRules.shouldTurn(stuck: number): boolean
	return stuck >= BotConfig.STUCK_TIME
end

-- Cette méthode permet de choisir le nouveau cap après un demi-tour lorsque le bot bute sur un mur ; roll ∈ [0, 1].
function BotRules.turnedYaw(yawDeg: number, roll: number): number
	local turn = BotConfig.TURN_MIN + (BotConfig.TURN_MAX - BotConfig.TURN_MIN) * roll
	return (yawDeg + turn) % 360
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

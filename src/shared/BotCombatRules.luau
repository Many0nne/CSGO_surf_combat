-- Règles pures du combat des bots (#143, décision 4 de #133) : direction du tir d'après le regard réel du bot (tourné
-- à vitesse limitée, jamais de visée instantanée), dispersion selon la vitesse de la cible (pas selon celle du bot :
-- un joueur n'a pas de malus en courant ni en l'air), délai de grâce à l'apparition, choix de l'arme (couteau à
-- quelques studs) et conditions d'un tir. Utilisées par BotArsenal et BotBrain, testées en Lune.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local MathRules = require(ReplicatedStorage.Shared.MathRules)

local BotCombatRules = {}

-- Arme d'un bot : fusil à distance, couteau au contact, pris dans l'inventaire par défaut (#267 : Ka-Bar et AWP)
BotCombatRules.RIFLE = "AWP"
BotCombatRules.KNIFE = "KaBar"
-- Attribut serveur d'un personnage (joueur ou bot) : os.clock() de son apparition (SpawnManager.place)
BotCombatRules.SPAWNED_AT_ATTRIBUTE = "SpawnedAt"

-- Cette méthode permet de lire le vecteur horizontal d'un cap lorsque le tir part du regard du bot (cap 0 : vers -Z,
-- même convention que BotRules.yawOf).
function BotCombatRules.forwardOf(yawDeg: number): Vector3
	local yaw = math.rad(yawDeg)
	return Vector3.new(math.sin(yaw), 0, -math.cos(yaw))
end

-- Cette méthode permet de mesurer l'écart entre le cap du bot et la direction d'un point lorsqu'il vise (°, de 0 à
-- 180, hauteur ignorée) ; 0 si le point est à la verticale des yeux.
function BotCombatRules.yawError(eye: Vector3, yawDeg: number, point: Vector3): number
	return MathRules.horizontalAngle(point - eye, BotCombatRules.forwardOf(yawDeg), 1e-6) or 0
end

-- Cette méthode permet de calculer la direction (unitaire) d'un tir lorsque le bot tire : cap réel du bot à
-- l'horizontale, hauteur vers le point visé. Un bot mal tourné tire à côté.
function BotCombatRules.aimDirection(eye: Vector3, yawDeg: number, point: Vector3): Vector3
	local offset = point - eye
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local dir = BotCombatRules.forwardOf(yawDeg) * horizontal + Vector3.new(0, offset.Y, 0)
	if dir.Magnitude < 1e-6 then
		return BotCombatRules.forwardOf(yawDeg)
	end
	return dir.Unit
end

-- Cette méthode permet de calculer la dispersion d'un tir lorsque le bot tire sur une cible (demi-angle du cône, °) :
-- base, plus un malus selon la vitesse de la cible (plus dure à suivre), plafonnée.
function BotCombatRules.spread(targetSpeed: number): number
	local spread = BotConfig.AIM_SPREAD + BotConfig.AIM_SPREAD_SPEED * math.max(targetSpeed, 0)
	return math.min(spread, BotConfig.AIM_SPREAD_MAX)
end

-- Cette méthode permet d'écarter la direction d'un tir au hasard lorsque le bot tire : direction tirée uniformément
-- dans le disque du cône de demi-angle spreadDeg (deux tirages dans [0, 1[).
function BotCombatRules.scatter(dir: Vector3, spreadDeg: number, rand: () -> number): Vector3
	if spreadDeg <= 0 then
		return dir
	end
	local radius = math.tan(math.rad(spreadDeg)) * math.sqrt(rand())
	local angle = 2 * math.pi * rand()
	local helper = if math.abs(dir.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local right = dir:Cross(helper).Unit
	local up = right:Cross(dir).Unit
	return (dir + right * (radius * math.cos(angle)) + up * (radius * math.sin(angle))).Unit
end

-- Cette méthode permet de savoir si une cible est encore dans son délai de grâce lorsqu'un bot pourrait lui tirer
-- dessus : apparue depuis moins de SPAWN_GRACE (spawnedAt nil : inconnu, pas de grâce).
function BotCombatRules.inSpawnGrace(spawnedAt: number?, now: number): boolean
	return spawnedAt ~= nil and now - spawnedAt < BotConfig.SPAWN_GRACE
end

-- Cette méthode permet de choisir l'arme d'un bot lorsqu'il a une cible (distance entre les racines, nil sans
-- cible) : couteau sous KNIFE_RANGE, fusil au-delà de KNIFE_DROP_RANGE ; entre les deux il garde la sienne (pas de
-- va-et-vient).
function BotCombatRules.chooseWeapon(current: string, distance: number?): string
	if distance and distance <= BotConfig.KNIFE_RANGE then
		return BotCombatRules.KNIFE
	end
	if not distance or distance > BotConfig.KNIFE_DROP_RANGE then
		return BotCombatRules.RIFLE
	end
	return current
end

export type FireInput = {
	visible: boolean, -- cible vue à ce regard (champ de vision et ligne de vue dégagée)
	inGrace: boolean, -- cible dans son délai de grâce
	ready: boolean, -- arme sortie, réarmée et chargée
	yawError: number, -- écart entre son cap et la cible (°)
	distance: number, -- distance à la cible (studs)
	range: number, -- portée de l'arme tenue (studs)
	holdFire: boolean?, -- tir interdit (debug DebugBotsPassive : cible humaine alors que les bots sont passifs)
}

-- Cette méthode permet de décider si un bot peut tirer lorsque son temps de réaction et de visée est passé : tir non
-- interdit, cible vue, hors délai de grâce, arme prête, à portée et regard tourné vers elle (FIRE_YAW_TOLERANCE).
function BotCombatRules.canFire(input: FireInput): boolean
	return not input.holdFire
		and input.visible
		and not input.inGrace
		and input.ready
		and input.distance <= input.range
		and input.yawError <= BotConfig.FIRE_YAW_TOLERANCE
end

return BotCombatRules

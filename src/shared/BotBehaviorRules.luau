-- Règles pures du comportement des bots (#141), testées (tests/specs/BotBehaviorRules.spec.luau) : perception (champ
-- de vision, ouïe des tirs), mémoire des cibles, choix de la cible, machine d'états (chercher, enquêter, combattre,
-- se replacer), note dynamique des destinations, biais vers les humains, cycle du regard en combat.
-- Le hasard est passé en fonction (rand : nombre dans [0, 1[) pour rester testable hors Roblox.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local MathRules = require(ReplicatedStorage.Shared.MathRules)

local BotBehaviorRules = {}

export type State = "chercher" | "enqueter" | "combattre" | "replacer"

-- Souvenir d'une cible : dernière position vue ou entendue
export type Memory = {
	position: Vector3,
	at: number, -- instant du dernier contact (s)
	seen: boolean, -- vue (true) ou seulement entendue
	isHuman: boolean,
}

export type Candidate = {
	id: number,
	isHuman: boolean,
	distance: number,
	inGrace: boolean?, -- encore dans son délai de grâce d'apparition (pas de tir possible)
}

export type StateInput = {
	state: State,
	hasTarget: boolean, -- une cible est vue en ce moment
	freshest: Memory?, -- souvenir le plus récent encore en mémoire
	investigated: number, -- instant du contact déjà enquêté (on n'y retourne pas)
	wantsReplace: boolean, -- kill ou duel perdu d'avance : se replacer
	replaceDone: boolean, -- point de repli atteint
	investigateDone: boolean, -- dernière position et points voisins fouillés
}

export type WaypointInfo = {
	position: Vector3,
	score: number, -- note fixe (NavBuilder)
	cover: number, -- part des 8 directions avec un mur proche (0 à 1)
}

export type DestinationContext = {
	from: Vector3, -- position du bot
	lastVisit: { [number]: number }, -- point → instant du dernier passage de ce bot
	claimed: { [number]: number }, -- point → nombre d'autres bots qui y vont
	now: number,
	avoid: number?, -- point où il se trouve
	biasCenter: Vector3?, -- zone floue autour de l'humain le plus proche (biais), nil sans biais
}

-- Perception ---------------------------------------------------------------------------------------------------------

-- Cette méthode permet de savoir si une position est dans le champ de vision d'un bot lorsqu'il regarde autour de lui :
-- angle horizontal entre son cap (yawDeg, convention de la caméra FPS) et la cible au plus la moitié de fovDeg.
function BotBehaviorRules.inFieldOfView(eye: Vector3, yawDeg: number, target: Vector3, fovDeg: number): boolean
	local dx, dz = target.X - eye.X, target.Z - eye.Z
	if dx * dx + dz * dz < 1e-6 then
		return true
	end
	local delta = math.abs(MathRules.angleDeltaDeg(yawDeg, MathRules.headingDeg(dx, dz)))
	return delta <= fovDeg / 2
end

-- Cette méthode permet de donner la position qu'un bot croit entendre lorsqu'un tir part : nil au-delà de radius,
-- sinon la position du tireur décalée au hasard dans un disque horizontal de rayon distance × fuzz.
function BotBehaviorRules.heardPosition(
	listener: Vector3,
	shooter: Vector3,
	radius: number,
	fuzz: number,
	rand: () -> number
): Vector3?
	local distance = (shooter - listener).Magnitude
	if distance > radius then
		return nil
	end
	local spread = distance * fuzz * math.sqrt(rand())
	local angle = rand() * 2 * math.pi
	return shooter + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread)
end

-- Mémoire -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de noter un contact avec une cible lorsqu'un bot la voit ou l'entend ; un tir entendu ne
-- remplace pas une position vue plus récente ou du même instant.
function BotBehaviorRules.remember(
	memory: { [number]: Memory },
	id: number,
	position: Vector3,
	now: number,
	seen: boolean,
	isHuman: boolean
)
	local previous = memory[id]
	if previous and previous.seen and not seen and previous.at >= now then
		return
	end
	memory[id] = { position = position, at = now, seen = seen, isHuman = isHuman }
end

-- Cette méthode permet d'oublier les cibles sans contact depuis ttl secondes lorsqu'un bot met à jour sa mémoire, et
-- renvoie le souvenir le plus récent qui reste (nil si la mémoire est vide).
function BotBehaviorRules.forget(memory: { [number]: Memory }, now: number, ttl: number): Memory?
	local freshest: Memory? = nil
	for id, entry in memory do
		if now - entry.at > ttl then
			memory[id] = nil
		elseif not freshest or entry.at > freshest.at then
			freshest = entry
		end
	end
	return freshest
end

-- Cette méthode permet de savoir si un candidat passe avant les autres lorsqu'un bot choisit sa cible (#298) : un
-- humain hors délai de grâce à moins de HUMAN_PREF_RANGE, marge HUMAN_PREF_MARGIN en plus s'il est déjà
-- la cible (pas de va-et-vient au seuil, qui relancerait le temps de réaction à chaque regard).
local function preferred(c: Candidate, currentId: number?): boolean
	local range = BotConfig.HUMAN_PREF_RANGE
	if c.id == currentId then
		range += BotConfig.HUMAN_PREF_MARGIN
	end
	return c.isHuman and not c.inGrace and c.distance <= range
end

-- Cette méthode permet de choisir la cible d'un bot parmi celles qu'il voit lorsqu'il en voit plusieurs : un humain
-- proche et hors grâce plutôt qu'un bot, puis la plus proche (currentId : cible actuelle) ; nil sans candidat.
function BotBehaviorRules.pickTarget(candidates: { Candidate }, currentId: number?): Candidate?
	local best: Candidate? = nil
	local bestPreferred = false
	for _, c in candidates do
		local p = preferred(c, currentId)
		if not best or (p and not bestPreferred) or (p == bestPreferred and c.distance < best.distance) then
			best, bestPreferred = c, p
		end
	end
	return best
end

-- Cette méthode permet de savoir si un bot garde en tête une cible qu'il ne voit plus lorsqu'elle sort de son champ
-- (il reprend sa course après un tir) : vue il y a au plus TARGET_KEEP_TIME secondes.
function BotBehaviorRules.keepTarget(lastSeenAt: number, now: number): boolean
	return now - lastSeenAt <= BotConfig.TARGET_KEEP_TIME
end

-- Cette méthode permet de décider si un bot enquête sur une cible perdue de vue lorsqu'il l'oublie (roll dans
-- [0, 1[) : seulement parfois, il ne poursuit pas une cible plus rapide que lui, il reprend sa course.
function BotBehaviorRules.investigateLost(roll: number): boolean
	return roll < BotConfig.LOST_CHASE_CHANCE
end

-- États ---------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de choisir l'état d'un bot lorsqu'il réfléchit : combattre s'il voit une cible ; sinon se
-- replacer jusqu'au point de repli ; sinon enquêter sur un contact pas encore fouillé (tir entendu, cible perdue de
-- vue) jusqu'à la fin de la fouille ; sinon chercher.
function BotBehaviorRules.nextState(input: StateInput): State
	if input.hasTarget then
		return "combattre"
	end
	if input.wantsReplace or (input.state == "replacer" and not input.replaceDone) then
		return "replacer"
	end
	local fresh = input.freshest
	if fresh and fresh.at > input.investigated then
		return "enqueter"
	end
	if input.state == "enqueter" and not input.investigateDone then
		return "enqueter"
	end
	return "chercher"
end

-- Cette méthode permet de savoir si un bot qui a perdu des PV doit se replacer lorsqu'il est touché en combat : duel
-- perdu d'avance sous REPLACE_HEALTH de ses PV.
function BotBehaviorRules.duelLost(health: number, maxHealth: number): boolean
	return maxHealth > 0 and health > 0 and health / maxHealth < BotConfig.REPLACE_HEALTH
end

-- Note dynamique des destinations ------------------------------------------------------------------------------------

-- Cette méthode permet de noter un point comme destination de recherche lorsqu'un bot en choisit une : note fixe,
-- malus si ce bot y est passé récemment ou si d'autres bots y vont, malus de distance, bonus près de la zone de biais,
-- part de hasard (roll dans [0, 1[).
function BotBehaviorRules.destinationScore(
	index: number,
	wp: WaypointInfo,
	ctx: DestinationContext,
	roll: number
): number
	local score = wp.score * BotConfig.DEST_WEIGHT_FIXED
	local visited = ctx.lastVisit[index]
	if visited and ctx.now - visited < BotConfig.DEST_RECENT_TIME then
		score -= BotConfig.DEST_RECENT_MALUS * (1 - (ctx.now - visited) / BotConfig.DEST_RECENT_TIME)
	end
	score -= (ctx.claimed[index] or 0) * BotConfig.DEST_CLAIMED_MALUS
	local distance = (wp.position - ctx.from).Magnitude
	score -= math.min(distance / BotConfig.DEST_DISTANCE_SCALE, 1) * BotConfig.DEST_DISTANCE_MALUS
	if ctx.biasCenter then
		local d = (wp.position - ctx.biasCenter).Magnitude
		score += BotConfig.BIAS_BONUS * math.max(0, 1 - d / BotConfig.BIAS_RADIUS)
	end
	return score + roll * BotConfig.DEST_RANDOM
end

-- Cette méthode permet de choisir la destination de recherche d'un bot lorsqu'il n'en a plus : le point de meilleure
-- note dynamique, hors du point où il se trouve ; nil sans point.
function BotBehaviorRules.pickDestination(
	waypoints: { WaypointInfo },
	ctx: DestinationContext,
	rand: () -> number
): number?
	local best, bestScore = nil, -math.huge
	for i, wp in waypoints do
		if i ~= ctx.avoid then
			local score = BotBehaviorRules.destinationScore(i, wp, ctx, rand())
			if score > bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best or (if #waypoints > 0 then 1 else nil)
end

-- Cette méthode permet de choisir un point de repli lorsqu'un bot se replace : le point de meilleur couvert à moins
-- de REPLACE_RADIUS, en s'éloignant de la menace (dernière position connue de la cible, nil si aucune) ; nil sans
-- point à portée.
function BotBehaviorRules.pickCover(
	waypoints: { WaypointInfo },
	from: Vector3,
	threat: Vector3?,
	avoid: number?,
	rand: () -> number
): number?
	local best, bestScore = nil, -math.huge
	for i, wp in waypoints do
		local distance = (wp.position - from).Magnitude
		if i ~= avoid and distance <= BotConfig.REPLACE_RADIUS and distance >= BotConfig.REPLACE_MIN_DIST then
			local score = wp.cover * BotConfig.REPLACE_W_COVER + rand() * BotConfig.DEST_RANDOM
			if threat then
				-- Plus loin de la menace qu'au départ : bonus ; plus près : malus
				local gain = (wp.position - threat).Magnitude - (from - threat).Magnitude
				score += math.clamp(gain / BotConfig.REPLACE_RADIUS, -1, 1) * BotConfig.REPLACE_W_AWAY
			end
			if score > bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

-- Cette méthode permet de savoir si le biais vers les humains s'applique lorsqu'un bot choisit une destination : après
-- BIAS_DELAY secondes sans contact (0 = désactivé).
function BotBehaviorRules.biasActive(now: number, lastContact: number): boolean
	return BotConfig.BIAS_DELAY > 0 and now - lastContact >= BotConfig.BIAS_DELAY
end

-- Cette méthode permet de donner le centre de la zone vers laquelle un bot sans contact se dirige lorsque le biais
-- s'applique : la position de l'humain le plus proche décalée au hasard d'au plus BIAS_SPREAD (il sait de quel côté
-- chercher, pas où est le joueur) ; nil sans humain en jeu.
function BotBehaviorRules.biasCenter(from: Vector3, humans: { Vector3 }, rand: () -> number): Vector3?
	local nearest, best = nil, math.huge
	for _, pos in humans do
		local d = (pos - from).Magnitude
		if d < best then
			nearest, best = pos, d
		end
	end
	if not nearest then
		return nil
	end
	local spread = BotConfig.BIAS_SPREAD * math.sqrt(rand())
	local angle = rand() * 2 * math.pi
	return nearest + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread)
end

-- Cette méthode permet de choisir où regarder en tenant un angle lorsqu'un bot s'arrête sur un point : un point
-- visible à au moins HOLD_LOOK_MIN studs, tiré au hasard en favorisant les plus lointains ; nil sans point visible.
function BotBehaviorRules.pickLookPoint(from: Vector3, visible: { Vector3 }, rand: () -> number): Vector3?
	local total = 0
	local weights = {}
	for i, pos in visible do
		local d = (pos - from).Magnitude
		weights[i] = if d >= BotConfig.HOLD_LOOK_MIN then d else 0
		total += weights[i]
	end
	if total <= 0 then
		return nil
	end
	local pick = rand() * total
	for i, w in weights do
		pick -= w
		if pick < 0 and w > 0 then
			return visible[i]
		end
	end
	return nil
end

-- Regard en combat ----------------------------------------------------------------------------------------------------

-- Cette méthode permet de suivre le cycle du regard d'un bot en combat lorsqu'il voit une cible (#141, sans tir avant
-- #143) : il se tourne vers elle dès qu'il la voit, tire après REACTION_TIME puis COMBAT_AIM_TIME (seenFor : temps
-- depuis qu'il la voit), puis rend son regard à sa course pendant COMBAT_COOLDOWN (sinceShot : temps depuis le
-- dernier tir, nil si aucun). Renvoie (regarde la cible, tire maintenant).
function BotBehaviorRules.combatGaze(seenFor: number, sinceShot: number?): (boolean, boolean)
	if sinceShot and sinceShot < BotConfig.COMBAT_COOLDOWN then
		return false, false
	end
	local ready = BotConfig.REACTION_TIME + BotConfig.COMBAT_AIM_TIME
	if sinceShot then
		-- Après un tir, la cible déjà vue : il revient sur elle et retire après COMBAT_AIM_TIME
		local aiming = sinceShot - BotConfig.COMBAT_COOLDOWN
		return true, aiming >= BotConfig.COMBAT_AIM_TIME
	end
	return true, seenFor >= ready
end

return BotBehaviorRules

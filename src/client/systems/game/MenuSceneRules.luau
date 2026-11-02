-- Règles pures de la scène du menu (sans Instance ni service) : amortis, visée vers le curseur, trajectoire du
-- surfeur qui frôle la caméra, touche d'un tir. Testées sous Lune (tests/specs/MenuSceneRules.spec.luau).
local MenuSceneRules = {}

-- Rayon (px) autour d'un surfeur dans lequel un tir le touche : assez large pour une cible à plus de 400 studs/s
MenuSceneRules.HIT_RADIUS = 36
-- Durée de retour au repos du recul d'un tir (s)
MenuSceneRules.KICK_TIME = 0.31

-- Cette méthode permet de rapprocher une valeur de sa cible à chaque image lorsqu'un mouvement doit rester souple,
-- sans jamais la dépasser même sur une image très longue.
function MenuSceneRules.damp(current: number, target: number, dt: number, rate: number): number
	return current + (target - current) * math.min(1, dt * rate)
end

-- Cette méthode permet de convertir la position du curseur (-1 à 1 sur chaque axe) et le recul courant en angles
-- (degrés) lorsque la caméra et l'arme suivent la souris : l'arme bouge bien plus que la caméra.
function MenuSceneRules.aimAngles(nx: number, ny: number, kick: number)
	return {
		camYaw = -nx * 4,
		camPitch = -ny * 3 + kick * 2.2,
		gunYaw = -nx * 13,
		gunPitch = -ny * 8 + kick * 7,
	}
end

-- Cette méthode permet de calculer le recul restant lorsque du temps passe après un tir (1 au tir, 0 au repos).
function MenuSceneRules.decayKick(kick: number, dt: number): number
	return math.max(0, kick - dt / MenuSceneRules.KICK_TIME)
end

-- Cette méthode permet de calculer un point d'une courbe de Bézier quadratique lorsqu'un surfeur frôle la caméra ;
-- `a`, `b`, `c` acceptent tout type additionnable (nombre, Vector3).
function MenuSceneRules.bezier(a: any, b: any, c: any, t: number): any
	local u = 1 - t
	return a * (u * u) + b * (2 * t * u) + c * (t * t)
end

-- Cette méthode permet de savoir si un tir touche une cible visible à l'écran lorsque le joueur tire depuis le menu.
function MenuSceneRules.isHit(shotX: number, shotY: number, targetX: number, targetY: number, depth: number): boolean
	if depth <= 0 then
		return false
	end
	local dx, dy = shotX - targetX, shotY - targetY
	return dx * dx + dy * dy <= MenuSceneRules.HIT_RADIUS * MenuSceneRules.HIT_RADIUS
end

return MenuSceneRules

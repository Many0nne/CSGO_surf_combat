-- Règles pures de la salle des miroirs du menu (sans Instance ni service) : amortis, léger suivi du curseur, pose des
-- éclats (dispersion, reconstitution en oscillation amortie), FOV selon le format de l'écran.
-- Testées sous Lune (tests/specs/MenuSceneRules.spec.luau). Constantes reprises de tools/menu/mirrors.py.
local MenuSceneRules = {}

-- Durée de retour au repos du recul d'un tir (s)
MenuSceneRules.KICK_TIME = 0.31
-- Durée de la dispersion d'un jeu d'éclats au changement d'arme (s)
MenuSceneRules.SCATTER_TIME = 0.6
-- Rotation lente (rad/s) d'un éclat dispersé qui attend son tour, et des éclats vides du fond
MenuSceneRules.DRIFT_SPEED = 0.15
MenuSceneRules.IDLE_SPIN = 0.14
-- Oscillation amortie de la reconstitution : amortissement (1/s) et fréquences (Hz) du pivot et du balancement
MenuSceneRules.DAMPING = 1.6
MenuSceneRules.SWING_HZ = 0.32
MenuSceneRules.TILT_HZ = 0.6
-- Au-delà de cette durée après sa libération, un éclat est considéré posé (amplitude < 0,1 %)
MenuSceneRules.SETTLE_TIME = 4.5

-- Cette méthode permet de rapprocher une valeur de sa cible à chaque image lorsqu'un mouvement doit rester souple,
-- sans jamais la dépasser même sur une image très longue.
function MenuSceneRules.damp(current: number, target: number, dt: number, rate: number): number
	return current + (target - current) * math.min(1, dt * rate)
end

-- Cette méthode permet de convertir la position du curseur (-1 à 1 sur chaque axe) et le recul courant en angles de
-- caméra (degrés) lorsque la vue suit la souris : un léger mouvement, la reconstitution ne dépend que de la position.
function MenuSceneRules.aimAngles(nx: number, ny: number, kick: number)
	return {
		camYaw = -nx * 1.5,
		camPitch = -ny * 1 + kick * 0.8,
	}
end

-- Cette méthode permet de calculer le recul restant lorsque du temps passe après un tir (1 au tir, 0 au repos).
function MenuSceneRules.decayKick(kick: number, dt: number): number
	return math.max(0, kick - dt / MenuSceneRules.KICK_TIME)
end

-- Cette méthode permet de donner le FOV vertical (degrés) lorsque l'écran n'est pas au format de référence : plus
-- étroit, on ouvre le FOV pour garder la largeur de référence (sinon l'arme sort du cadre) ; plus large, on le garde.
function MenuSceneRules.fitFov(verticalFov: number, aspectRef: number, aspect: number): number
	if aspect >= aspectRef then
		return verticalFov
	end
	local halfWidth = math.tan(math.rad(verticalFov) / 2) * aspectRef
	return math.deg(2 * math.atan(halfWidth / aspect))
end

-- Cette méthode permet de donner l'avancement (0 à 1, ralenti en fin) de la dispersion lorsqu'un jeu d'éclats s'ouvre.
function MenuSceneRules.scatterProgress(elapsed: number): number
	local t = math.clamp(elapsed / MenuSceneRules.SCATTER_TIME, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

-- Cette méthode permet de poser un éclat pendant la reconstitution, `lt` secondes après sa libération (négatif tant
-- qu'il attend) : il tourne lentement depuis sa position dispersée, puis revient face caméra en oscillation amortie.
-- Renvoie l'angle autour du fil et le balancement (radians).
function MenuSceneRules.settle(angle: number, tilt: number, lt: number): (number, number)
	if lt <= 0 then
		return angle + MenuSceneRules.DRIFT_SPEED * lt, tilt
	end
	local k = math.exp(-MenuSceneRules.DAMPING * lt)
	return angle * k * math.cos(2 * math.pi * MenuSceneRules.SWING_HZ * lt),
		tilt * k * math.cos(2 * math.pi * MenuSceneRules.TILT_HZ * lt)
end

return MenuSceneRules

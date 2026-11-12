-- Règles pures de la scène de l'accueil du menu (#253, sans Instance ni service) : amortis, léger suivi du curseur, FOV
-- selon le format de l'écran, choix des pièces de la map copiées (champ de la caméra), défilement des armes, respiration
-- du personnage, barres de la fiche d'arme. Testées sous Lune (tests/specs/MenuSceneRules.spec.luau).
local MenuSceneRules = {}

-- Respiration du personnage en pose : amplitude (rad) de la rotation de la taille et période (s)
MenuSceneRules.BREATH_ANGLE = math.rad(0.8)
MenuSceneRules.BREATH_PERIOD = 4.2

-- Vecteur lu par composantes : un Vector3 en jeu, une table sous Lune (pas de Vector3 hors Roblox)
type Vec = Vector3 | { X: number, Y: number, Z: number }

-- Cette méthode permet de rapprocher une valeur de sa cible à chaque image lorsqu'un mouvement doit rester souple,
-- sans jamais la dépasser même sur une image très longue.
function MenuSceneRules.damp(current: number, target: number, dt: number, rate: number): number
	return current + (target - current) * math.min(1, dt * rate)
end

-- Cette méthode permet de convertir la position du curseur (-1 à 1 sur chaque axe) en angles de caméra (degrés)
-- lorsque la vue suit la souris : un léger mouvement, le personnage reste cadré.
function MenuSceneRules.aimAngles(nx: number, ny: number)
	return {
		camYaw = -nx * 1.5,
		camPitch = -ny * 1,
	}
end

-- Cette méthode permet de donner le FOV vertical (degrés) lorsque l'écran n'est pas au format de référence : plus
-- étroit, on ouvre le FOV pour garder la largeur de référence (sinon le personnage et l'arme sortent du cadre) ; plus
-- large, on le garde.
function MenuSceneRules.fitFov(verticalFov: number, aspectRef: number, aspect: number): number
	if aspect >= aspectRef then
		return verticalFov
	end
	local halfWidth = math.tan(math.rad(verticalFov) / 2) * aspectRef
	return math.deg(2 * math.atan(halfWidth / aspect))
end

-- Cette méthode permet de décider si une pièce de la map (sphère englobante `center`, `radius`) doit être copiée pour
-- la scène lorsque le menu construit sa copie : dans le cône de la caméra (`eye`, `forward` unitaire, demi-angle de
-- tangente `tanHalf`) jusqu'à `maxDistance`, ou à moins de `nearRadius` de la caméra (ombres et bords du cadre).
function MenuSceneRules.inView(
	center: Vec,
	radius: number,
	eye: Vec,
	forward: Vec,
	tanHalf: number,
	maxDistance: number,
	nearRadius: number
): boolean
	local dx, dy, dz = center.X - eye.X, center.Y - eye.Y, center.Z - eye.Z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance <= nearRadius + radius then
		return true
	end
	local along = dx * forward.X + dy * forward.Y + dz * forward.Z
	if along < -radius or along > maxDistance + radius then
		return false
	end
	local lateral = math.sqrt(math.max(0, distance * distance - along * along))
	return lateral <= math.max(along, 0) * tanHalf + radius
end

-- Cette méthode permet de donner le rang (1 à count) de l'élément suivant ou précédent lorsque le joueur fait défiler
-- (emplacements de l'accueil à la molette, #280) : on revient au début après le dernier.
function MenuSceneRules.cycleIndex(index: number, step: number, count: number): number
	if count <= 0 then
		return 1
	end
	return (index - 1 + step) % count + 1
end

-- Cette méthode permet de donner la rotation (rad) de la taille du personnage à l'instant `t` (s) lorsqu'il respire
-- en pose : une oscillation lente et faible, nulle à t = 0.
function MenuSceneRules.breathAngle(t: number): number
	return MenuSceneRules.BREATH_ANGLE * math.sin(2 * math.pi * t / MenuSceneRules.BREATH_PERIOD)
end

-- Cette méthode permet de compter les segments pleins d'une barre de la fiche d'arme lorsque la valeur est rapportée au
-- maximum des armes du menu : au moins un segment pour une valeur positive.
function MenuSceneRules.statSegments(value: number, max: number, count: number): number
	if max <= 0 or value <= 0 then
		return 0
	end
	return math.clamp(math.round(value / max * count), 1, count)
end

-- Cette méthode permet de nommer un skin dans l'écran d'équipement (#280) lorsqu'il est affiché : « D'ORIGINE » sans
-- skin, sinon la fin de son id en majuscules (« skin.awp.dragon_lore » → « DRAGON LORE », en attendant #268).
function MenuSceneRules.skinLabel(skinId: string?): string
	if not skinId then
		return "D'ORIGINE"
	end
	local last = string.match(skinId, "([^%.]+)$") or skinId
	return string.upper((string.gsub(last, "_", " ")))
end

return MenuSceneRules

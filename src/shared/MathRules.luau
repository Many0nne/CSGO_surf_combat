-- Calculs purs partagés (#225) : nombre fini (ni NaN ni ±inf), écart d'angle par le plus court côté, cap d'une
-- direction horizontale. Une seule copie, pour que le client, le serveur et les règles anti-triche arrondissent pareil.
-- Aucun service ni workspace : testé sous Lune (tests/specs/MathRules.spec.luau).
-- Conventions : les fonctions sans suffixe travaillent en radians, `Deg` en degrés ; un cap est mesuré comme celui de
-- la caméra FPS (0 vers -Z, positif vers +X), cf. headingDeg.

local MathRules = {}

-- Cette méthode permet de vérifier qu'une valeur reçue est un nombre fini lorsqu'on valide un argument ou une horloge
-- (NaN, +inf et -inf refusés, tout autre type aussi).
function MathRules.isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Cette méthode permet de vérifier qu'une valeur reçue est un Vector3 aux trois composantes finies lorsqu'on valide
-- une position ou une direction.
function MathRules.isFiniteVector3(v: any): boolean
	return typeof(v) == "Vector3" and MathRules.isFinite(v.X) and MathRules.isFinite(v.Y) and MathRules.isFinite(v.Z)
end

-- Cette méthode permet de vérifier qu'un nombre est fini et de valeur absolue au plus bound lorsqu'on borne une
-- coordonnée ou un angle reçus d'un client.
function MathRules.isBounded(n: any, bound: number): boolean
	return MathRules.isFinite(n) and math.abs(n) <= bound
end

-- Cette méthode permet de vérifier qu'un Vector3 est fini et que chaque composante vaut au plus bound en valeur
-- absolue lorsqu'on borne un point reçu d'un client.
function MathRules.isBoundedVector3(v: any, bound: number): boolean
	return typeof(v) == "Vector3"
		and MathRules.isBounded(v.X, bound)
		and MathRules.isBounded(v.Y, bound)
		and MathRules.isBounded(v.Z, bound)
end

-- Cette méthode permet de ramener un angle (rad) dans [-π, π[ lorsqu'on compare ou interpole des caps.
function MathRules.wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Cette méthode permet de ramener un angle (degrés) dans [-180, 180[ lorsqu'on compare ou fait tourner des caps.
function MathRules.wrapAngleDeg(angle: number): number
	return (angle + 180) % 360 - 180
end

-- Cette méthode permet de trouver la plus courte rotation signée (rad) de a vers b lorsqu'on interpole un cap
-- (passage par ±π).
function MathRules.angleDelta(a: number, b: number): number
	return MathRules.wrapAngle(b - a)
end

-- Cette méthode permet de trouver la plus courte rotation signée (degrés) de a vers b lorsqu'on tourne vers un cap
-- (passage par 0°/360°).
function MathRules.angleDeltaDeg(a: number, b: number): number
	return MathRules.wrapAngleDeg(b - a)
end

-- Cette méthode permet de lire la longueur horizontale (plan XZ, hauteur ignorée) d'un vecteur lorsqu'on décide si son
-- cap est défini.
function MathRules.horizontalLength(v: Vector3): number
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- Cette méthode permet de lire le cap (degrés, de -180 à 180) d'une direction horizontale (dx, dz) lorsqu'on oriente
-- un regard : convention de la caméra FPS, 0 vers -Z, positif vers +X. Une direction nulle n'a pas de cap (le résultat
-- vaut alors 180, atan2(0, -0) = π) : le test de seuil reste à l'appelant.
function MathRules.headingDeg(dx: number, dz: number): number
	return math.deg(math.atan2(dx, -dz))
end

-- Cette méthode permet de mesurer l'écart de cap horizontal (degrés, de 0 à 180, hauteur ignorée) entre deux vecteurs
-- lorsqu'on compare un regard et une direction ; nil si l'un des deux a une longueur horizontale sous minLength
-- (cap indéfini : vecteur vertical ou nul).
function MathRules.horizontalAngle(a: Vector3, b: Vector3, minLength: number): number?
	local flatA = Vector3.new(a.X, 0, a.Z)
	local flatB = Vector3.new(b.X, 0, b.Z)
	if flatA.Magnitude < minLength or flatB.Magnitude < minLength then
		return nil
	end
	local cos = math.clamp(flatA.Unit:Dot(flatB.Unit), -1, 1)
	return math.deg(math.acos(cos))
end

return MathRules

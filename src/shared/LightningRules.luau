-- Éclair de tir d'un skin (#520, AWP ORAGE) : règles pures du rendu client (LightningBolt), testées sous Lune
-- (tests/specs/LightningRules.spec.luau).
-- Forme : un tronc brisé du canon au point d'impact (déplacement du milieu, à plusieurs échelles), des branches qui en
-- partent vers l'avant et des brindilles sur les branches, tirés au hasard à chaque tir (`rand` fourni par l'appelant).
-- Le tronc reste dans un tube autour du rayon de visée : il se resserre près du canon et du point d'impact.
-- Éclat : un flash, une retombée, un second flash, puis un fondu (`intensity`). Purement visuel : la trajectoire et les
-- dégâts restent ceux du raycast.

local LightningRules = {}

-- Tirage au hasard fourni par l'appelant : nombre réel dans [min, max] (Random:NextNumber en jeu, suite fixe en test)
export type Rand = (min: number, max: number) -> number
-- Une ligne brisée de l'éclair : ses points dans l'ordre, et sa sorte (réglages de rendu dans KINDS)
export type Polyline = { points: { Vector3 }, kind: string }

-- Tronc : longueur visée d'un segment (studs), nombre maximal de subdivisions (2^MAX_LEVELS segments), écart du
-- milieu en fraction de la longueur du segment, plafonné en studs à chaque niveau.
LightningRules.TRUNK_SEGMENT = 3
LightningRules.MAX_LEVELS = 5
LightningRules.TRUNK_ROUGHNESS = 0.42
LightningRules.TRUNK_MAX_OFFSET = 2
-- Distances (studs) sur lesquelles l'écart grandit depuis le canon et depuis le point d'impact : l'éclair sort bien du
-- canon et finit sur l'impact, sans grand zigzag sous les yeux du tireur.
LightningRules.RAMP_FROM_MUZZLE = 14
LightningRules.RAMP_TO_IMPACT = 4
-- Branches : une tous les BRANCH_SPACING studs de tronc (au moins une, au plus MAX_BRANCHES), pas avant
-- BRANCH_MIN_START studs du canon ; longueur en studs (au plus la moitié du tronc), angle avec le tronc (degrés).
LightningRules.BRANCH_SPACING = 6
LightningRules.MAX_BRANCHES = 10
LightningRules.BRANCH_MIN_START = 5
LightningRules.BRANCH_LENGTH = { 4, 14 }
LightningRules.BRANCH_ANGLE = { 20, 55 }
-- 4 segments par branche : chaque Beam coûte au tir (≈ 5 µs d'écritures), le détail se joue sur le tronc
LightningRules.BRANCH_LEVELS = 2
LightningRules.BRANCH_ROUGHNESS = 0.4
LightningRules.BRANCH_MAX_OFFSET = 1
-- Brindille sur une branche : probabilité, longueur en fraction de la branche, subdivisions.
LightningRules.TWIG_CHANCE = 0.85
LightningRules.TWIG_LENGTH = { 0.35, 0.6 }
LightningRules.TWIG_LEVELS = 2

-- Rendu de chaque sorte de ligne : couches de Beams superposées, de la plus large à la plus fine (largeur en studs,
-- transparence de base multipliée par l'éclat, couleur "glow" ou "core"). Un Beam sans texture a des bords nets : un
-- voile large très transparent, un halo plus serré et un cœur fin donnent une lueur qui s'estompe vers l'extérieur.
export type Layer = { width: number, alpha: number, color: string }
LightningRules.KINDS = {
	trunk = {
		-- plus large, un segment vu en enfilade (tir qui s'éloigne) dessine des carrés de lumière
		{ width = 0.6, alpha = 0.8, color = "glow" },
		{ width = 0.35, alpha = 0.3, color = "glow" },
		{ width = 0.1, alpha = 0, color = "core" },
	},
	branch = {
		{ width = 0.3, alpha = 0.55, color = "glow" },
		{ width = 0.05, alpha = 0.05, color = "core" },
	},
	twig = {
		{ width = 0.05, alpha = 0.2, color = "glow" },
	},
} :: { [string]: { Layer } }
-- Couleurs : cœur clair teinté de vert, halo vert franc (cf. références de l'issue : tronc éclatant, lueur colorée ;
-- additif, un cœur trop blanc vire au jaune pâle sur le décor chaud de la map)
LightningRules.CORE_RGB = { 170, 255, 185 }
LightningRules.GLOW_RGB = { 30, 255, 80 }
-- Lueur projetée sur le décor : une PointLight verte à LIGHT_OFFSET studs du canon le long de l'éclair.
LightningRules.LIGHT_BRIGHTNESS = 2
LightningRules.LIGHT_RANGE = 12
LightningRules.LIGHT_OFFSET = 6

-- Durée de vie (s) et déroulé de l'éclat, en fraction de la vie : flash jusqu'à FLASH_END, retombée à DIM jusqu'à
-- RESTRIKE, second flash jusqu'à FADE_START, puis fondu jusqu'à 0.
LightningRules.LIFETIME = 0.25
LightningRules.FLASH_END = 0.15
LightningRules.DIM = 0.35
LightningRules.RESTRIKE = 0.3
LightningRules.FADE_START = 0.45
-- Paliers de transparence (une NumberSequence précalculée par palier, comme le rayon de balle)
LightningRules.FADE_STEPS = 20
-- Éclairs en cours au plus : au-delà, le tir garde le rayon de balle ordinaire.
LightningRules.MAX_ACTIVE = 3

-- Cette méthode permet de trouver deux directions perpendiculaires à un axe lorsqu'on écarte des points de cet axe.
local function basis(axis: Vector3): (Vector3, Vector3)
	local helper = if math.abs(axis.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local p1 = axis:Cross(helper).Unit
	return p1, axis:Cross(p1).Unit
end

-- Cette méthode permet de briser un segment en ligne de 2^levels segments lorsqu'on dessine un trait d'éclair : à
-- chaque niveau, chaque milieu s'écarte au hasard perpendiculairement à l'axe.
local function jagged(
	a: Vector3,
	b: Vector3,
	levels: number,
	roughness: number,
	maxOffset: number,
	rand: Rand
): { Vector3 }
	local axis = b - a
	if axis.Magnitude < 1e-6 then
		return { a, b }
	end
	local p1, p2 = basis(axis.Unit)
	local points = { a, b }
	for _ = 1, levels do
		local nextPoints = { points[1] }
		for i = 1, #points - 1 do
			local p, q = points[i], points[i + 1]
			local mid = (p + q) / 2
			local offset = math.min((q - p).Magnitude * roughness, maxOffset) * rand(0.3, 1)
			local angle = rand(0, 2 * math.pi)
			table.insert(nextPoints, mid + (p1 * math.cos(angle) + p2 * math.sin(angle)) * offset)
			table.insert(nextPoints, q)
		end
		points = nextPoints
	end
	return points
end

-- Cette méthode permet de choisir une direction écartée d'un angle tiré au hasard (en degrés) d'une direction donnée
-- lorsqu'une branche ou une brindille part.
local function deviate(direction: Vector3, angleRange: { number }, rand: Rand): Vector3
	local p1, p2 = basis(direction)
	local spin = rand(0, 2 * math.pi)
	local side = p1 * math.cos(spin) + p2 * math.sin(spin)
	local angle = math.rad(rand(angleRange[1], angleRange[2]))
	return (direction * math.cos(angle) + side * math.sin(angle)).Unit
end

-- Cette méthode permet de compter les subdivisions du tronc lorsqu'un éclair est tiré : assez pour des segments
-- d'environ TRUNK_SEGMENT studs, au plus MAX_LEVELS.
function LightningRules.trunkLevels(length: number): number
	if length <= LightningRules.TRUNK_SEGMENT then
		return 1
	end
	local levels = math.ceil(math.log(length / LightningRules.TRUNK_SEGMENT, 2))
	return math.clamp(levels, 1, LightningRules.MAX_LEVELS)
end

-- Cette méthode permet de donner la part d'écart permise au tronc à une distance `along` du canon lorsqu'un éclair
-- est dessiné : 0 au canon et à l'impact, 1 au-delà des rampes RAMP_FROM_MUZZLE et RAMP_TO_IMPACT.
function LightningRules.envelope(along: number, length: number): number
	local fromMuzzle = math.clamp(along / LightningRules.RAMP_FROM_MUZZLE, 0, 1)
	local toImpact = math.clamp((length - along) / LightningRules.RAMP_TO_IMPACT, 0, 1)
	return math.min(fromMuzzle, toImpact)
end

-- Cette méthode permet de compter les branches d'un éclair lorsqu'il est tiré, selon la longueur du tronc.
function LightningRules.branchCount(length: number): number
	return math.clamp(math.floor(length / LightningRules.BRANCH_SPACING), 1, LightningRules.MAX_BRANCHES)
end

-- Cette méthode permet de dessiner un éclair du canon (start) au point d'impact (finish) lorsqu'un tir part : tronc
-- brisé, branches et brindilles, tirés avec `rand` ; vide si les deux points sont confondus.
function LightningRules.build(start: Vector3, finish: Vector3, rand: Rand): { Polyline }
	local path = finish - start
	local length = path.Magnitude
	if length < 1e-3 then
		return {}
	end
	local axis = path / length
	local trunk = jagged(
		start,
		finish,
		LightningRules.trunkLevels(length),
		LightningRules.TRUNK_ROUGHNESS,
		LightningRules.TRUNK_MAX_OFFSET,
		rand
	)
	-- écart à l'axe ramené selon la position le long du rayon : nul au canon et à l'impact, entier entre les deux
	for i = 2, #trunk - 1 do
		local along = math.clamp((trunk[i] - start):Dot(axis), 0, length)
		local onAxis = start + axis * along
		trunk[i] = onAxis + (trunk[i] - onAxis) * LightningRules.envelope(along, length)
	end
	local lines: { Polyline } = { { points = trunk, kind = "trunk" } }

	-- points du tronc assez loin du canon pour porter une branche (pas le dernier : l'impact)
	local candidates = {}
	for i = 2, #trunk - 1 do
		if (trunk[i] - start):Dot(axis) >= LightningRules.BRANCH_MIN_START then
			table.insert(candidates, i)
		end
	end
	if #candidates == 0 then
		return lines
	end
	for _ = 1, LightningRules.branchCount(length) do
		local index = candidates[math.clamp(math.floor(rand(1, #candidates + 1)), 1, #candidates)]
		local root = trunk[index]
		local along = (trunk[index + 1] - root)
		local direction =
			deviate(if along.Magnitude > 1e-6 then along.Unit else axis, LightningRules.BRANCH_ANGLE, rand)
		-- pas plus long que ce qui reste jusqu'à l'impact : une branche ne dépasse pas le point touché
		local remaining = length - (root - start):Dot(axis)
		local branchLength = math.min(
			rand(LightningRules.BRANCH_LENGTH[1], LightningRules.BRANCH_LENGTH[2]),
			length / 2,
			math.max(remaining, LightningRules.BRANCH_LENGTH[1] / 2)
		)
		local branch = jagged(
			root,
			root + direction * branchLength,
			LightningRules.BRANCH_LEVELS,
			LightningRules.BRANCH_ROUGHNESS,
			LightningRules.BRANCH_MAX_OFFSET,
			rand
		)
		table.insert(lines, { points = branch, kind = "branch" })

		if rand(0, 1) < LightningRules.TWIG_CHANCE and #branch > 2 then
			local twigIndex = math.clamp(math.floor(rand(2, #branch)), 2, #branch - 1)
			local twigRoot = branch[twigIndex]
			local twigDirection = deviate(direction, LightningRules.BRANCH_ANGLE, rand)
			local twigLength = branchLength * rand(LightningRules.TWIG_LENGTH[1], LightningRules.TWIG_LENGTH[2])
			local twig = jagged(
				twigRoot,
				twigRoot + twigDirection * twigLength,
				LightningRules.TWIG_LEVELS,
				LightningRules.BRANCH_ROUGHNESS,
				LightningRules.BRANCH_MAX_OFFSET,
				rand
			)
			table.insert(lines, { points = twig, kind = "twig" })
		end
	end
	return lines
end

-- Cette méthode permet de donner l'éclat d'un éclair lorsqu'il vieillit (1 : plein, 0 : éteint) : flash, retombée,
-- second flash, puis fondu de plus en plus rapide jusqu'à LIFETIME.
function LightningRules.intensity(elapsed: number): number
	local t = elapsed / LightningRules.LIFETIME
	if t < 0 then
		return 1
	elseif t >= 1 then
		return 0
	elseif t < LightningRules.FLASH_END then
		return 1
	elseif t < LightningRules.RESTRIKE then
		return LightningRules.DIM
	elseif t < LightningRules.FADE_START then
		return 1
	end
	local fade = (t - LightningRules.FADE_START) / (1 - LightningRules.FADE_START)
	return 1 - fade * fade
end

-- Cette méthode permet de choisir le palier de transparence d'un trait lorsqu'une frame passe (0 : opaque,
-- FADE_STEPS : invisible), d'après sa transparence de base et l'éclat de l'éclair ; caché : dernier palier.
function LightningRules.fadeStep(baseAlpha: number, intensity: number, hidden: boolean): number
	if hidden then
		return LightningRules.FADE_STEPS
	end
	local transparency = 1 - (1 - baseAlpha) * math.clamp(intensity, 0, 1)
	return math.round(transparency * LightningRules.FADE_STEPS)
end

-- Cette méthode permet de compter au plus les segments de chaque sorte de ligne et les points d'un éclair lorsqu'on
-- prépare la réserve d'Instances d'un éclair complet (segments par sorte, points).
function LightningRules.maxCounts(): ({ [string]: number }, number)
	local branches = LightningRules.MAX_BRANCHES
	local trunk = 2 ^ LightningRules.MAX_LEVELS
	local branch = 2 ^ LightningRules.BRANCH_LEVELS
	local twig = 2 ^ LightningRules.TWIG_LEVELS
	local segments = { trunk = trunk, branch = branches * branch, twig = branches * twig }
	local points = (trunk + 1) + branches * (branch + 1) + branches * (twig + 1)
	return segments, points
end

-- Cette méthode permet de savoir si un nouvel éclair peut être tiré lorsqu'un tir le demande (MAX_ACTIVE en cours).
function LightningRules.hasRoom(activeCount: number): boolean
	return activeCount < LightningRules.MAX_ACTIVE
end

return LightningRules

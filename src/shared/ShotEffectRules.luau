-- Effets visuels du tir (#54) : règles pures du client (ShotEffects), testées sous Lune
-- (tests/specs/ShotEffectRules.spec.luau).
-- Flamme de bouche : le ParticleEmitter MuzzleEffect de l'Attachment ShootPart du canon (Barrel) de l'arme émet
-- quelques particules au tir ; LockedToPart, il suit le recul. Rayon : Beam du canon jusqu'au point d'impact (ou la
-- portée maximale), qui s'efface en TRACER_LIFETIME. Chez le tireur sur son viewmodel, chez les autres sur l'arme 3P
-- (même pièces, clonées du viewmodel par WeaponThirdPerson), pour chaque tir relayé par le serveur (ShotFired, #156).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local ShotSoundRules = require(ReplicatedStorage.Shared.ShotSoundRules)

local ShotEffectRules = {}

-- Styles d'effet de tir qu'un item `effect` peut déclarer (`shotEffect` du catalogue, #520, #566) et leur interrupteur :
-- un style à false (ou un nom inconnu) est ignoré, le joueur tire avec le rayon ordinaire. `lightning` : éclair vert
-- (ÉCLAIR, LightningBolt) ; `pan` : explosion « PAN ! » devant le canon (PanBurst), rayon ordinaire ; `temper` : ruban
-- d'acier torsadé à écailles (TREMPE), mis de côté le 18/11/2026 (peu lisible du point de vue du tireur) : aucun item ne
-- le porte, rendu gardé pour plus tard (#567) ; `balise` : ruban de chantier qui se déroule (BALISE, #567).
ShotEffectRules.STYLES = { lightning = true, pan = true, temper = false, balise = true }

-- Bouche du canon dans le modèle de l'arme (viewmodel ou 3P) : chemin de l'Attachment, puis nom de son effet.
-- Une arme à distance sans ce chemin tire sans flamme, et son rayon part de l'origine du tir (l'œil).
ShotEffectRules.MUZZLE_PATH = { "Barrel", "ShootPart" }
ShotEffectRules.MUZZLE_EFFECT = "MuzzleEffect"
-- Particules émises par tir : elles naissent au même point, sans rotation aléatoire ; en ajouter rend la flamme plus
-- opaque, pas plus grande (taille et durée : réglages du ParticleEmitter dans le viewmodel).
ShotEffectRules.MUZZLE_EMIT_COUNT = 2

-- Rayon de la balle : largeur (studs, face à la caméra), durée de vie (s) pendant laquelle il s'efface, couleur.
ShotEffectRules.TRACER_WIDTH = 0.08
ShotEffectRules.TRACER_LIFETIME = 0.2
ShotEffectRules.TRACER_RGB = { 255, 240, 180 }
-- Un rayon plus court que ça (studs) n'est pas tracé : canon collé à un mur, ou bouche du canon au-delà de l'impact.
ShotEffectRules.TRACER_MIN_LENGTH = 1
-- Bouche du canon à plus de cette distance (studs) de l'origine du tir : le rayon part de l'origine. Un tireur distant
-- est dessiné en retard (interpolation, CharacterSync) alors que l'origine relayée est à jour : comme dans CS, le
-- rayon va du canon dessiné à l'impact réel, un peu de biais quand le tireur va vite. Ce seuil n'écarte qu'un canon
-- sans rapport avec le tir (personnage pas encore à jour, réapparition), pas le retard d'un surfeur rapide.
ShotEffectRules.MUZZLE_MAX_OFFSET = 25
-- Distance (studs) sous laquelle un rayon venu d'un autre ne s'approche pas de notre caméra : il s'arrête avant, au
-- lieu de finir dans l'œil quand le tir nous touche (un Beam face à la caméra y couvrirait l'écran).
ShotEffectRules.NEAR_CAMERA = 3
-- Un rayon déjà tracé que la caméra approche à moins de cette distance (studs) est masqué pour la frame : le rayon
-- reste dans le monde, la caméra peut le traverser (surf). Inférieur à la distance œil-bouche du canon du viewmodel.
ShotEffectRules.HIDE_RADIUS = 1
-- Paliers du fondu : la transparence est arrondie au 1/FADE_STEPS, une séquence précalculée par palier.
ShotEffectRules.FADE_STEPS = 20
-- Rayons en cours au plus : au-delà, un tir relayé n'a pas de rayon, seulement sa flamme. Le tir local a toujours le
-- sien (une AWP ne tire pas pendant la vie d'un rayon) et compte parmi les rayons en cours.
ShotEffectRules.MAX_ACTIVE = 16
-- Nom des Instances créées pour un rayon (repérables en Studio, comptées par la vérification « aucune instance »).
ShotEffectRules.INSTANCE_NAME = "ShotTracer"
-- Filet : un rayon est détruit au plus tard après sa durée de vie plus cette marge (s), même si sa boucle s'arrête.
ShotEffectRules.LIFETIME_MARGIN = 0.5

-- TREMPE (#566, style `temper`), d'après la planche de concept validée (ruban d'acier torsadé qui refroidit, écailles
-- d'oxyde qui s'en détachent) : ruban plus large et plus long à s'effacer que le rayon ordinaire, torsadé (texture
-- TEMPER_RIBBON_IMAGE répétée tous les TEMPER_TWIST_LENGTH studs, qui défile à TEMPER_TWIST_SPEED : le ruban tourne),
-- aux couleurs de revenu de l'acier, paille à la bouche (le plus chaud) puis bronze, pourpre et bleu profond vers
-- l'impact. Les franges (bandes plus claires) défilent vers l'impact à TEMPER_SPEED (longueurs de rayon par seconde), et
-- le front des couleurs ondule de TEMPER_WAVE (part de la longueur) : le rayon n'est jamais deux fois le même.
ShotEffectRules.TEMPER_WIDTH = 0.3
ShotEffectRules.TEMPER_LIFETIME = 0.3
-- Textures (assets/effects/temper_textures.py), publiées en Decal : id de l'image contenue
ShotEffectRules.TEMPER_RIBBON_IMAGE = "rbxassetid://127964327625411"
ShotEffectRules.TEMPER_FLAKE_IMAGE = "rbxassetid://77905204616866"
ShotEffectRules.TEMPER_TWIST_LENGTH = 2.4
ShotEffectRules.TEMPER_TWIST_SPEED = 2
-- Teintes plus saturées que celles du skin : un Beam sans relief ni reflet les rend plus pâles (comparé en jeu).
ShotEffectRules.TEMPER_STOPS = {
	{ 0.0, { 245, 205, 90 } }, -- paille, à la bouche
	{ 0.3, { 215, 115, 30 } }, -- bronze
	{ 0.6, { 135, 45, 200 } }, -- pourpre
	{ 1.0, { 30, 50, 210 } }, -- bleu profond, vers l'impact
}
-- Écailles d'oxyde : semées le long du rayon (TEMPER_FLAKES_PER_STUD, bornées), elles tombent en refroidissant (paille
-- → bleu-gris au fil de leur vie) ; taille (studs), vie (s), vitesse de départ (studs/s), gravité (studs/s²)
ShotEffectRules.TEMPER_FLAKES_PER_STUD = 0.35
ShotEffectRules.TEMPER_FLAKES_MIN = 6
ShotEffectRules.TEMPER_FLAKES_MAX = 36
ShotEffectRules.TEMPER_FLAKE_SIZE = { 0.05, 0.14 } -- à 0,28, les écailles proches de la caméra mangeaient le ruban
ShotEffectRules.TEMPER_FLAKE_LIFE = { 0.45, 0.8 }
ShotEffectRules.TEMPER_FLAKE_SPEED = { 0.5, 2.5 }
ShotEffectRules.TEMPER_FLAKE_GRAVITY = 14
-- Couleurs des écailles au fil de leur vie, par tronçon du rayon (de la bouche vers l'impact) : chaque écaille part de
-- la couleur du ruban là où elle s'en détache, puis refroidit jusqu'au bleu-gris
ShotEffectRules.TEMPER_FLAKE_SECTIONS = {
	{ { 0, { 245, 205, 90 } }, { 0.5, { 215, 115, 30 } }, { 1, { 120, 140, 185 } } }, -- paille → bronze
	{ { 0, { 215, 115, 30 } }, { 0.5, { 135, 45, 200 } }, { 1, { 120, 140, 185 } } }, -- bronze → pourpre
	{ { 0, { 135, 45, 200 } }, { 0.5, { 30, 50, 210 } }, { 1, { 120, 140, 185 } } }, -- pourpre → bleu
}
-- Écailles en cours au plus (une réserve de ce nombre d'émetteurs, utilisés à tour de rôle)
ShotEffectRules.TEMPER_FLAKE_EMITTERS = 4
ShotEffectRules.TEMPER_FRINGES = 3 -- franges sur la longueur du rayon
ShotEffectRules.TEMPER_FRINGE_GAIN = 0.25 -- éclaircissement au cœur d'une frange (vers le blanc)
ShotEffectRules.TEMPER_SPEED = 2.5
ShotEffectRules.TEMPER_WAVE = 0.06
-- Points de la ColorSequence (Roblox en accepte 20 au plus)
ShotEffectRules.TEMPER_KEYPOINTS = 16
-- Segments du Beam : avec un seul, Roblox n'interpole qu'entre les deux bouts (bleu → paille en passant par le gris)
-- et le violet et le bronze disparaissent
ShotEffectRules.TEMPER_SEGMENTS = 20
-- Lumière additive : à 0,6 les couleurs sont lavées vers le blanc sur le décor clair, à 0 le rayon est terne dans le noir
ShotEffectRules.TEMPER_LIGHT_EMISSION = 0.25

-- PAN ! (#566, style `pan`) : l'explosion « PAN ! » de la crosse du skin jaillit devant le canon, en volume, avec le
-- rayon ordinaire. Largeur en studs, plus petite chez le tireur pour ne pas cacher sa cible ; avance devant la bouche du
-- canon (studs) ; pop (s) jusqu'au dépassement PAN_OVERSHOOT, puis retour à 1 ; fondu sur la fin de PAN_LIFETIME.
-- Modèle en volume (ReplicatedStorage.Props.PanBurst, assets/effects/pan_burst_3d.py) : face avant vers -Z, pivot au
-- centre, PAN_MODEL_WIDTH studs de large à l'échelle 1. Il jaillit tourné de PAN_TURN degrés et pivote face à la caméra
-- pendant le pop et la pose : on voit le relief, puis on lit l'onomatopée.
ShotEffectRules.PAN_MODEL = "PanBurst"
ShotEffectRules.PAN_MODEL_WIDTH = 4
ShotEffectRules.PAN_TURN = 35
ShotEffectRules.PAN_WIDTH = 4
ShotEffectRules.PAN_WIDTH_LOCAL = 1.4
ShotEffectRules.PAN_AHEAD = 1.6
ShotEffectRules.PAN_AHEAD_LOCAL = 1.2
ShotEffectRules.PAN_AHEAD_DEMO = 3.5 -- aperçu du menu : le canon y est au bord du cadre, l'explosion s'en écarte
-- Aperçu et révélation du shop : l'AWP de profil, canon vers le bord droit et caméra proche ; explosion plus petite,
-- collée à la bouche, pour rester dans le cadre
ShotEffectRules.PAN_AHEAD_SHOP = 0.8
ShotEffectRules.PAN_WIDTH_SHOP = 2
ShotEffectRules.PAN_LIFETIME = 0.32
ShotEffectRules.PAN_POP = 0.06
ShotEffectRules.PAN_SETTLE = 0.1
ShotEffectRules.PAN_OVERSHOOT = 1.15
ShotEffectRules.PAN_FADE_FROM = 0.55 -- part de la vie à partir de laquelle il s'efface
ShotEffectRules.PAN_TILT = 14 -- inclinaison tirée à chaque tir, en degrés (±)
-- Le rayon part à cette part de la largeur de l'explosion au-delà de son centre (son bord, pointes comprises)
ShotEffectRules.PAN_TRACER_GAP = 0.5
-- Explosions en cours au plus (une réserve de ce nombre de BillboardGui, créée au premier tir PAN !)
ShotEffectRules.PAN_MAX_ACTIVE = 6

-- BALISE (#567, style `balise`), d'après la planche de concept retenue le 18/11/2026 : un ruban de chantier (chevrons
-- orange sur noir, liseré blanc, couleurs du skin BALISE) se déroule de la bouche du canon jusqu'à l'impact en
-- BALISE_UNROLL s, chevrons qui défilent vers la cible, puis se rétracte vers l'impact de BALISE_RETRACT_FROM à
-- BALISE_LIFETIME. Une boucle zébrée tourne à la bouche du canon au tir, trois chevrons s'ouvrent autour de l'impact à
-- l'arrivée du ruban. Textures : assets/effects/balise_textures.py, publiées en Decal (id de l'image contenue).
ShotEffectRules.BALISE_TAPE_IMAGE = "rbxassetid://138484076872781"
ShotEffectRules.BALISE_RING_IMAGE = "rbxassetid://82072650119477"
ShotEffectRules.BALISE_MARK_IMAGE = "rbxassetid://81577689344071"
ShotEffectRules.BALISE_WIDTH = 0.45 -- à 0,2, un pointillé vu de côté
ShotEffectRules.BALISE_TAPE_LENGTH = 2 -- studs du ruban pour un tronçon de texture (deux chevrons)
ShotEffectRules.BALISE_TAPE_SPEED = 3 -- défilement des chevrons vers la cible
ShotEffectRules.BALISE_LIFETIME = 0.32
ShotEffectRules.BALISE_UNROLL = 0.06
ShotEffectRules.BALISE_RETRACT_FROM = 0.2
-- Boucle du canon : diamètre (studs) au début et à la fin de sa vie, plus petite chez le tireur (bouche à 2 ou 3 studs
-- de l'œil) ; vie (s), vitesse de rotation (degrés/s)
ShotEffectRules.BALISE_RING_SIZE = { 0.9, 1.6 }
ShotEffectRules.BALISE_RING_SIZE_LOCAL = { 0.35, 0.8 }
ShotEffectRules.BALISE_RING_LIFE = 0.16
ShotEffectRules.BALISE_RING_SPIN = 720
-- Marque d'impact : sa taille suit la distance de la caméra (angle constant, lisible de loin comme de près), bornée ;
-- elle s'ouvre de BALISE_MARK_OPEN fois sa taille jusqu'à sa taille pleine, puis s'efface. Vie (s), décalage vers la
-- caméra (studs, pour ne pas s'enfoncer dans le mur touché).
-- À 0,05, 24 pixels de large à 35 studs en vue du tireur (FOV vertical 90°) : la marque ne se voyait pas
ShotEffectRules.BALISE_MARK_ANGLE = 0.1 -- taille / distance (à 0,13, plus grosse que la cible vue de côté)
ShotEffectRules.BALISE_MARK_SIZE = { 1.5, 10 }
ShotEffectRules.BALISE_MARK_OPEN = 0.55
ShotEffectRules.BALISE_MARK_LIFE = 0.28
ShotEffectRules.BALISE_MARK_ZOFFSET = 1.5
-- Jeux d'émetteurs (boucle et marque) en réserve, utilisés à tour de rôle
ShotEffectRules.BALISE_EMITTERS = 4

-- Cette méthode permet de calculer la transparence d'un rayon lorsqu'il vieillit : opaque au tir, il s'efface de
-- plus en plus vite (courbe quadratique) jusqu'à disparaître à `lifetime` (TRACER_LIFETIME par défaut).
function ShotEffectRules.tracerTransparency(elapsed: number, lifetime: number?): number
	local t = math.clamp(elapsed / (lifetime or ShotEffectRules.TRACER_LIFETIME), 0, 1)
	return t * t
end

-- Cette méthode permet de donner la durée de vie d'un rayon selon le style de tir (TREMPE s'efface plus lentement)
-- lorsqu'il est créé.
function ShotEffectRules.tracerLifetime(style: string?): number
	if style == "temper" then
		return ShotEffectRules.TEMPER_LIFETIME
	elseif style == "balise" then
		return ShotEffectRules.BALISE_LIFETIME
	end
	return ShotEffectRules.TRACER_LIFETIME
end

-- Cette méthode permet de savoir quelle partie du rayon le ruban BALISE couvre à un instant de sa vie (`elapsed`, s)
-- lorsqu'une frame passe : sa queue et sa tête en part du rayon (0 : bouche du canon, 1 : impact). Il se déroule de la
-- bouche à l'impact, reste tendu, puis se rétracte vers l'impact.
function ShotEffectRules.baliseSpan(elapsed: number): (number, number)
	local unroll = ShotEffectRules.BALISE_UNROLL
	local head = if unroll > 0 then math.clamp(elapsed / unroll, 0, 1) else 1
	local from, life = ShotEffectRules.BALISE_RETRACT_FROM, ShotEffectRules.BALISE_LIFETIME
	local tail = if life > from then math.clamp((elapsed - from) / (life - from), 0, 1) else 0
	-- rétraction plus rapide sur la fin (le ruban est tiré d'un coup)
	return tail * tail, head
end

-- Cette méthode permet de donner la taille pleine (studs) de la marque d'impact BALISE lorsqu'elle apparaît, vue d'une
-- caméra à `distance` studs de l'impact : proportionnelle à la distance, bornée par BALISE_MARK_SIZE.
function ShotEffectRules.baliseMarkSize(distance: number): number
	local bounds = ShotEffectRules.BALISE_MARK_SIZE
	return math.clamp(distance * ShotEffectRules.BALISE_MARK_ANGLE, bounds[1], bounds[2])
end

-- Cette méthode permet de lire la couleur de base de TREMPE en un point du rayon (0 : bouche, 1 : impact) lorsque ses
-- couleurs sont composées : interpolation linéaire entre les étapes de TEMPER_STOPS, en RGB 0..255.
local function temperBase(x: number): (number, number, number)
	local stops = ShotEffectRules.TEMPER_STOPS
	x = math.clamp(x, 0, 1)
	for i = 2, #stops do
		local a, b = stops[i - 1], stops[i]
		if x <= b[1] then
			local t = if b[1] > a[1] then (x - a[1]) / (b[1] - a[1]) else 0
			return a[2][1] + (b[2][1] - a[2][1]) * t,
				a[2][2] + (b[2][2] - a[2][2]) * t,
				a[2][3] + (b[2][3] - a[2][3]) * t
		end
	end
	local last = stops[#stops][2]
	return last[1], last[2], last[3]
end

-- Cette méthode permet de composer les couleurs de TREMPE le long du rayon à un instant (`elapsed`, s) lorsqu'il est créé
-- puis à chaque frame : TEMPER_KEYPOINTS points { position 0..1, r, g, b } (0..255), du dégradé de l'acier décalé par une
-- onde (`seed` : tirage du tir) et éclairci au passage des franges qui défilent vers l'impact.
function ShotEffectRules.temperKeypoints(elapsed: number, seed: number): { { number } }
	local points = {}
	local n = ShotEffectRules.TEMPER_KEYPOINTS
	local phase = elapsed * ShotEffectRules.TEMPER_SPEED
	for i = 0, n - 1 do
		local x = i / (n - 1)
		local wave = ShotEffectRules.TEMPER_WAVE * math.sin((x * 2.3 + seed) * math.pi * 2 + phase * 3)
		local r, g, b = temperBase(x + wave)
		-- frange : bosse en cosinus, une par 1/TEMPER_FRINGES, qui avance vers l'impact
		local fringe = (math.cos(((x - phase) * ShotEffectRules.TEMPER_FRINGES + seed) * math.pi * 2) + 1) / 2
		local lift = ShotEffectRules.TEMPER_FRINGE_GAIN * fringe ^ 4
		points[i + 1] = { x, r + (255 - r) * lift, g + (255 - g) * lift, b + (255 - b) * lift }
	end
	return points
end

-- Cette méthode permet de donner l'échelle et la transparence de l'explosion PAN ! à un instant de sa vie (`elapsed`,
-- s) lorsqu'elle est animée : pop de 0 à PAN_OVERSHOOT, retour à 1, puis fondu ; transparence 1 une fois sa vie finie.
function ShotEffectRules.panFrame(elapsed: number): (number, number)
	local pop, settle = ShotEffectRules.PAN_POP, ShotEffectRules.PAN_SETTLE
	local over = ShotEffectRules.PAN_OVERSHOOT
	local scale
	if elapsed <= 0 then
		scale = 0
	elseif elapsed < pop then
		local t = elapsed / pop
		scale = over * (1 - (1 - t) * (1 - t))
	elseif elapsed < pop + settle then
		scale = over + (1 - over) * ((elapsed - pop) / settle)
	else
		scale = 1
	end
	local life = ShotEffectRules.PAN_LIFETIME
	local from = life * ShotEffectRules.PAN_FADE_FROM
	local transparency = if elapsed >= life then 1 elseif elapsed <= from then 0 else (elapsed - from) / (life - from)
	return scale, transparency
end

-- Cette méthode permet de faire partir le rayon du bord de l'explosion PAN ! (centre `center`, largeur `width`) lorsque
-- les deux sont tracés : départ avancé de PAN_TRACER_GAP largeur au-delà du centre, sans dépasser l'impact moins
-- TRACER_MIN_LENGTH (sinon le départ d'origine).
function ShotEffectRules.panTracerStart(start: Vector3, finish: Vector3, center: Vector3, width: number): Vector3
	local path = finish - start
	local length = path.Magnitude
	if length <= 0 then
		return start
	end
	local unit = path / length
	local along = (center - start):Dot(unit) + width * ShotEffectRules.PAN_TRACER_GAP
	if along <= 0 or along > length - ShotEffectRules.TRACER_MIN_LENGTH then
		return start
	end
	return start + unit * along
end

-- Cette méthode permet de compter les écailles d'oxyde de TREMPE semées le long d'un rayon de `length` studs lorsqu'il
-- est tracé : proportionnel à sa longueur, borné par TEMPER_FLAKES_MIN et TEMPER_FLAKES_MAX.
function ShotEffectRules.temperFlakeCount(length: number): number
	local count = math.floor(length * ShotEffectRules.TEMPER_FLAKES_PER_STUD + 0.5)
	return math.clamp(count, ShotEffectRules.TEMPER_FLAKES_MIN, ShotEffectRules.TEMPER_FLAKES_MAX)
end

-- Cette méthode permet de répartir `total` écailles entre les tronçons du rayon (TEMPER_FLAKE_SECTIONS) lorsqu'un tir
-- TREMPE les sème : parts égales, le reste aux premiers tronçons (près de la bouche).
function ShotEffectRules.temperFlakeSplit(total: number): { number }
	local sections = #ShotEffectRules.TEMPER_FLAKE_SECTIONS
	local counts = {}
	for i = 1, sections do
		counts[i] = total // sections + (if i <= total % sections then 1 else 0)
	end
	return counts
end

-- Cette méthode permet de donner l'angle (degrés) dont l'explosion PAN ! est encore tournée par rapport à la caméra à un
-- instant de sa vie : PAN_TURN au tir, ramené à 0 en douceur à la fin de la pose (PAN_POP + PAN_SETTLE).
function ShotEffectRules.panTurn(elapsed: number): number
	local t = math.clamp(elapsed / (ShotEffectRules.PAN_POP + ShotEffectRules.PAN_SETTLE), 0, 1)
	return ShotEffectRules.PAN_TURN * (1 - t) * (1 - t)
end

-- Cette méthode permet de placer l'explosion PAN ! lorsqu'un tir part : devant la bouche du canon dans la direction du
-- tir, plus près chez le tireur (`aheadOverride`, `widthOverride` : avance et largeur imposées, démonstrations) ; sans
-- s'avancer au-delà de la moitié du rayon (cible collée au canon). Renvoie sa position et sa largeur (studs).
function ShotEffectRules.panPlacement(
	start: Vector3,
	finish: Vector3,
	isLocal: boolean,
	aheadOverride: number?,
	widthOverride: number?
): (Vector3, number)
	local path = finish - start
	local length = path.Magnitude
	local ahead = aheadOverride or if isLocal then ShotEffectRules.PAN_AHEAD_LOCAL else ShotEffectRules.PAN_AHEAD
	local width = widthOverride or if isLocal then ShotEffectRules.PAN_WIDTH_LOCAL else ShotEffectRules.PAN_WIDTH
	if length <= 0 then
		return start, width
	end
	return start + path / length * math.min(ahead, length / 2), width
end

-- Cette méthode permet de trouver la fin d'un rayon lorsqu'un tir part : le point touché, sinon l'origine prolongée
-- de la portée dans la direction du tir (tir dans le vide).
function ShotEffectRules.endpoint(origin: Vector3, direction: Vector3, hitPosition: Vector3?, range: number): Vector3
	if hitPosition then
		return hitPosition
	end
	local unit = if direction.Magnitude > 0 then direction.Unit else direction
	return origin + unit * range
end

-- Cette méthode permet de choisir le départ du rayon lorsqu'un tir part : la bouche du canon si elle est connue et
-- proche de l'origine du tir (MUZZLE_MAX_OFFSET), sinon l'origine ; nil si le rayon serait trop court ou partirait
-- d'au-delà de l'impact (canon dans un mur).
function ShotEffectRules.tracerStart(origin: Vector3, muzzle: Vector3?, endpoint: Vector3): Vector3?
	if muzzle and (muzzle - origin).Magnitude > ShotEffectRules.MUZZLE_MAX_OFFSET then
		muzzle = nil
	end
	local start = muzzle or origin
	local path = endpoint - origin
	local length = path.Magnitude
	if length < ShotEffectRules.TRACER_MIN_LENGTH then
		return nil
	end
	-- avancée de la bouche du canon sur l'axe du tir : au-delà de l'impact (moins la longueur minimale), pas de rayon
	if muzzle and (muzzle - origin):Dot(path / length) > length - ShotEffectRules.TRACER_MIN_LENGTH then
		return nil
	end
	if (endpoint - start).Magnitude < ShotEffectRules.TRACER_MIN_LENGTH then
		return nil
	end
	return start
end

-- Cette méthode permet de mesurer où un segment passe au plus près d'un point lorsqu'on teste un rayon contre la
-- caméra : distance le long du segment depuis start (bornée), distance au point, longueur du segment.
function ShotEffectRules.closestApproach(start: Vector3, endpoint: Vector3, point: Vector3): (number, number, number)
	local path = endpoint - start
	local length = path.Magnitude
	if length <= 0 then
		return 0, (point - start).Magnitude, 0
	end
	local unit = path / length
	local along = math.clamp((point - start):Dot(unit), 0, length)
	return along, (point - (start + unit * along)).Magnitude, length
end

-- Cette méthode permet de retirer d'un rayon venu d'un autre sa partie à moins de NEAR_CAMERA de notre caméra
-- lorsqu'il nous touche, nous frôle ou part d'à côté de nous : la partie avant cette sphère si elle est assez longue,
-- sinon celle d'après ; nil s'il n'en reste presque rien. Renvoie le début et la fin du rayon gardé.
function ShotEffectRules.clipNearCamera(start: Vector3, endpoint: Vector3, camera: Vector3): (Vector3?, Vector3?)
	local path = endpoint - start
	local length = path.Magnitude
	if length <= 0 then
		return nil, nil
	end
	local unit = path / length
	-- point de la droite du rayon le plus proche de la caméra (non borné au segment), et sa distance à elle
	local along = (camera - start):Dot(unit)
	local miss = (camera - (start + unit * along)).Magnitude
	local radius = ShotEffectRules.NEAR_CAMERA
	if miss >= radius then
		return start, endpoint
	end
	local half = math.sqrt(radius * radius - miss * miss)
	local enter, exit = along - half, along + half
	if enter >= length or exit <= 0 then
		return start, endpoint -- la sphère est avant le début ou après la fin du rayon
	end
	local minLength = ShotEffectRules.TRACER_MIN_LENGTH
	if enter >= minLength then
		return start, start + unit * enter
	end
	if length - exit >= minLength then
		return start + unit * exit, endpoint
	end
	return nil, nil
end

-- Cette méthode permet de savoir si un rayon déjà tracé doit être masqué lorsqu'une frame passe : la caméra, qui a
-- bougé depuis le tir, en est à moins de HIDE_RADIUS (un Beam face à la caméra couvrirait l'écran).
function ShotEffectRules.isTooClose(start: Vector3, endpoint: Vector3, camera: Vector3): boolean
	local _, miss = ShotEffectRules.closestApproach(start, endpoint, camera)
	return miss < ShotEffectRules.HIDE_RADIUS
end

-- Cette méthode permet de choisir le palier de transparence d'un rayon lorsqu'il vieillit (0 : opaque, FADE_STEPS :
-- invisible) : un rayon caché par la caméra prend le dernier palier ; `lifetime` : sa durée de vie (tracerLifetime).
function ShotEffectRules.fadeStep(elapsed: number, hidden: boolean, lifetime: number?): number
	if hidden then
		return ShotEffectRules.FADE_STEPS
	end
	return math.round(ShotEffectRules.tracerTransparency(elapsed, lifetime) * ShotEffectRules.FADE_STEPS)
end

-- Cette méthode permet de décider si les effets d'un tir relayé sont montrés lorsqu'il arrive : le tir d'un autre
-- (le tireur voit déjà les siens), hors écrans du menu (mêmes états que le son, la salle du menu flotte au-dessus de
-- la map).
function ShotEffectRules.shouldShow(shooter: any, localCharacter: any, state: string?): boolean
	return ShotSoundRules.isOthersShot(shooter, localCharacter, state)
end

-- Cette méthode permet de savoir si un tir relayé a droit à son rayon lorsqu'il arrive (la flamme, elle, part
-- toujours) : pas au-delà de MAX_ACTIVE rayons en cours.
function ShotEffectRules.hasRoom(activeCount: number): boolean
	return activeCount < ShotEffectRules.MAX_ACTIVE
end

-- Cette méthode permet de trouver le style joué par un item d'effet de tir (#566) lorsqu'un tir part : nil sans effet,
-- pour un id inconnu, un item qui n'est pas un effet ou un style désactivé.
function ShotEffectRules.styleOf(effectId: any): string?
	if type(effectId) ~= "string" or effectId == "" then
		return nil
	end
	local item = InventoryRules.item(effectId)
	local style = item and item.type == InventoryRules.Type.EFFECT and item.shotEffect
	if type(style) == "string" and ShotEffectRules.STYLES[style] == true then
		return style
	end
	return nil
end

-- Cette méthode permet de lire le style de tir d'un joueur lorsqu'un de ses tirs est relayé : ses attributs
-- informatifs `EquippedItems` et `OwnedItems` (posés par le serveur) relus comme l'équipement résolu, nil sans effet.
function ShotEffectRules.styleOfPlayer(equippedText: any, ownedText: any): string?
	local resolved = InventoryRules.decodeEquipped(equippedText, InventoryRules.decode(ownedText))
	return ShotEffectRules.styleOf(InventoryRules.effectOf(resolved))
end

-- Cette méthode permet de savoir si un style de tir est activé lorsque le client démarre (réserve à préparer ou non).
function ShotEffectRules.isEnabled(style: string): boolean
	return ShotEffectRules.STYLES[style] == true
end

return ShotEffectRules

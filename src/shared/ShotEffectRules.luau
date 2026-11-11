-- Effets visuels du tir (#54) : règles pures du client (ShotEffects), testées sous Lune
-- (tests/specs/ShotEffectRules.spec.luau).
-- Flamme de bouche : le ParticleEmitter MuzzleEffect de l'Attachment ShootPart du canon (Barrel) de l'arme émet
-- quelques particules au tir ; LockedToPart, il suit le recul. Rayon : Beam du canon jusqu'au point d'impact (ou la
-- portée maximale), qui s'efface en TRACER_LIFETIME. Chez le tireur sur son viewmodel, chez les autres sur l'arme 3P
-- (même pièces, clonées du viewmodel par WeaponThirdPerson), pour chaque tir relayé par le serveur (ShotFired, #156).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShotSoundRules = require(ReplicatedStorage.Shared.ShotSoundRules)

local ShotEffectRules = {}

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

-- Cette méthode permet de calculer la transparence d'un rayon lorsqu'il vieillit : opaque au tir, il s'efface de
-- plus en plus vite (courbe quadratique) jusqu'à disparaître à TRACER_LIFETIME.
function ShotEffectRules.tracerTransparency(elapsed: number): number
	local t = math.clamp(elapsed / ShotEffectRules.TRACER_LIFETIME, 0, 1)
	return t * t
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
-- invisible) : un rayon caché par la caméra prend le dernier palier.
function ShotEffectRules.fadeStep(elapsed: number, hidden: boolean): number
	if hidden then
		return ShotEffectRules.FADE_STEPS
	end
	return math.round(ShotEffectRules.tracerTransparency(elapsed) * ShotEffectRules.FADE_STEPS)
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

return ShotEffectRules

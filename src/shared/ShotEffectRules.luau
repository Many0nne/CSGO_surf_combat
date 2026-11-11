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
-- Rayons en cours au plus (les tirs des autres) : au-delà, un tir de plus n'a pas de rayon (beaucoup de bots).
ShotEffectRules.MAX_ACTIVE = 16
-- Nom des Instances créées pour un rayon (repérables en Studio, comptées par la vérification « aucune instance »).
ShotEffectRules.INSTANCE_NAME = "ShotTracer"
-- Filet : un rayon est détruit au plus tard après sa durée de vie plus cette marge (s), même si sa boucle s'arrête.
ShotEffectRules.LIFETIME_MARGIN = 0.5

-- Cette méthode permet de calculer la transparence d'un rayon lorsqu'il vieillit : opaque au tir, il s'efface de
-- plus en plus vite (courbe quadratique) jusqu'à disparaître à TRACER_LIFETIME.
function ShotEffectRules.tracerTransparency(elapsed: number, lifetime: number?): number
	local life = lifetime or ShotEffectRules.TRACER_LIFETIME
	if not (life > 0) then
		return 1
	end
	local t = math.clamp(elapsed / life, 0, 1)
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

-- Cette méthode permet de choisir le départ du rayon lorsqu'un tir part : la bouche du canon si elle est connue,
-- sinon l'origine du tir ; nil si le rayon serait trop court ou partirait d'au-delà de l'impact (canon dans un mur).
function ShotEffectRules.tracerStart(origin: Vector3, muzzle: Vector3?, endpoint: Vector3): Vector3?
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

-- Cette méthode permet de décider si les effets d'un tir relayé sont montrés lorsqu'il arrive : le tir d'un autre
-- (le tireur voit déjà les siens), hors écrans du menu (mêmes états que le son, la salle du menu flotte au-dessus de
-- la map).
function ShotEffectRules.shouldShow(shooter: any, localCharacter: any, state: string?): boolean
	if shooter == nil or shooter == localCharacter then
		return false
	end
	return state ~= nil and ShotSoundRules.AUDIBLE_STATES[state] == true
end

-- Cette méthode permet de savoir si un tir relayé a droit à son rayon lorsqu'il arrive (la flamme, elle, part
-- toujours) : pas au-delà de MAX_ACTIVE rayons en cours.
function ShotEffectRules.hasRoom(activeCount: number): boolean
	return activeCount < ShotEffectRules.MAX_ACTIVE
end

return ShotEffectRules

-- Règles pures de validation d'un tir de joueur (#174, docs/anticheat.md « T1 ») : le client envoie l'origine, la
-- direction, le point d'impact et l'instant du tir ; le serveur vérifie que ce tir pouvait toucher la partie annoncée.
-- Aucun service hors les modules partagés (ReplicatedStorage), ni workspace : positions rembobinées, vitesses et
-- raycast de ligne de vue sont fournis par l'appelant (Validator). Testées sous Lune (tests/specs/ShotRules.spec.luau, tests/specs/Validator.spec.luau).
-- Chaque contrôle a un mode : "log" (violation journalisée, tir appliqué : phase de mesure) ou "block" (tir refusé).
-- Durée d'equip et chargeur (#175, « T2 ») : règles pures ici aussi, l'état (instants, compteurs) vit dans Validator.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local ShotRules = {}

export type Mode = "log" | "block"
-- Mêmes valeurs que CheatLog.Severity (ShotRules ne dépend pas de CheatLog, qui demande des services).
export type Severity = "low" | "medium" | "high"
export type Shot = { origin: Vector3, direction: Vector3, hitPos: Vector3, shotTime: number }

ShotRules.Mode = { LOG = "log" :: Mode, BLOCK = "block" :: Mode }

-- Contrôles, dans l'ordre où le Validator les applique.
ShotRules.Check = {
	SHAPE = "shape", -- forme des arguments (direction unitaire, coordonnées bornées)
	ORIGIN = "origin", -- origine près du tireur
	DIRECTION = "direction", -- rayon et point d'impact sur la partie annoncée, rembobinée
	DISTANCE = "distance", -- |hitPos - origin| dans la portée
	LINE_OF_SIGHT = "lineOfSight", -- aucun obstacle de la map entre origine et impact
	EQUIP = "equip", -- arme sortie depuis sa durée d'equip (#175, tir et mêlée)
	MAGAZINE = "magazine", -- chargeur non vide, ou rechargé (#175, tir)
}

-- Catégories du journal (mêmes valeurs que CheatLog.Category) : le contrôle d'equip vaut aussi pour la mêlée.
ShotRules.Category = { HITSCAN = "Hitscan", MELEE = "Melee" }

-- Mode de chaque contrôle. "log" tant que les faux positifs ne sont pas mesurés en jeu (docs/anticheat.md, « T1 » :
-- procédure pour passer en "block") ; forme et distance ne dépendent pas du réseau, donc bloquants d'emblée. Equip et
-- chargeur (#175) : règles déterministes à tolérance de gigue, sans faux positif mesuré, bloquants d'emblée.
ShotRules.MODES = {
	shape = "block",
	origin = "log",
	direction = "log",
	distance = "block",
	lineOfSight = "log",
	equip = "block",
	magazine = "block",
} :: { [string]: Mode }

-- Gravité d'un échec au journal (valeurs de CheatLog.Severity) : une forme impossible ne vient jamais de notre client
-- (forte) ; les autres s'expliquent par le réseau ou un bug de tolérance (moyennes, docs/anticheat.md).
ShotRules.SEVERITY = {
	shape = "high",
	origin = "medium",
	direction = "medium",
	distance = "medium",
	lineOfSight = "medium",
	equip = "medium",
	magazine = "medium",
} :: { [string]: Severity }

-- Ancienne borne du serveur (studs entre racines), avant #174 : tout tir au-delà était refusé. Pendant la phase de
-- mesure, un échec de ces contrôles en mode "log" refuse quand même le tir au-delà de cette distance : la validation
-- n'est jamais plus permissive qu'avant (tir à travers un mur à 2 000 studs). Pas "direction", dont un faux positif a
-- été mesuré : un tir lointain légitime ne doit pas tomber dessus.
ShotRules.LOG_ONLY_RANGE = 250
ShotRules.LOG_ONLY_RANGE_CHECKS = { origin = true, lineOfSight = true } :: { [string]: boolean }

-- Au-delà de cette coordonnée (studs), un point est absurde ou forgé (même borne que les positions synchronisées).
ShotRules.MAX_COORD = CharacterSyncRules.MAX_COORD
-- Écart toléré entre |direction| et 1 : notre client envoie LookVector (unitaire à 1e-6 près).
ShotRules.UNIT_TOLERANCE = 1e-3
-- Origine : à moins de ORIGIN_BASE + vitesse du tireur × ORIGIN_SPEED_FACTOR studs de sa position (caméra à 2,5 studs
-- au-dessus de la racine, CameraConfig.CAM_HEIGHT_STAND ; le client est en avance sur le serveur de sa latence).
ShotRules.ORIGIN_BASE = 5
ShotRules.ORIGIN_SPEED_FACTOR = 0.1
-- Direction : le rayon et le point d'impact passent à moins de rayon de la partie + DIRECTION_BASE + vitesse de la
-- cible × DIRECTION_SPEED_FACTOR de la partie rembobinée (accroupi, animation absente du rig serveur, interpolation,
-- erreur d'horloge du client).
ShotRules.DIRECTION_BASE = 2
ShotRules.DIRECTION_SPEED_FACTOR = 0.05
-- Écart maximal (studs) entre le point d'impact et le rayon annoncé : notre client prend l'impact sur son rayon.
ShotRules.HIT_ON_RAY = 0.5
-- Portée : celle du rayon du client (WeaponConfig.HITSCAN_RANGE), plus une marge.
ShotRules.RANGE_TOLERANCE = 10
-- La ligne de vue s'arrête à cette distance (studs) avant l'impact : la surface de la cible n'est pas un obstacle.
ShotRules.LINE_OF_SIGHT_END_MARGIN = 0.5
-- Fenêtre (s) sur laquelle la vitesse d'un personnage est estimée dans son historique.
ShotRules.SPEED_WINDOW = 0.1
-- Equip (#175) : une touche est acceptée à partir de equippedAt + EquipTime - EQUIP_TOLERANCE. equippedAt est
-- l'arrivée de l'outil dans le personnage sur le serveur, la touche arrive au moins EquipTime plus tard (le client
-- honnête n'est jamais prêt plus tôt, #184) : la tolérance couvre la gigue entre les deux paquets.
ShotRules.EQUIP_TOLERANCE = 0.2
-- Chargeur (#175) : un rechargement compte comme fini ReloadTime - RELOAD_TOLERANCE après l'arrivée de l'action
-- Reload (même gigue entre l'action et la touche suivante).
ShotRules.RELOAD_TOLERANCE = 0.2

-- Cette méthode permet de vérifier qu'un nombre est fini et borné lorsqu'un argument de tir arrive.
local function isBounded(n: any, bound: number): boolean
	return type(n) == "number" and n == n and math.abs(n) <= bound
end

-- Cette méthode permet de vérifier qu'un Vector3 est fini et borné lorsqu'un point de tir arrive.
local function isBoundedVector(v: any): boolean
	return typeof(v) == "Vector3"
		and isBounded(v.X, ShotRules.MAX_COORD)
		and isBounded(v.Y, ShotRules.MAX_COORD)
		and isBounded(v.Z, ShotRules.MAX_COORD)
end

-- Cette méthode permet de vérifier la forme d'un tir lorsqu'il arrive (style CharacterSyncRules.isWellFormed) :
-- trois Vector3 finis et bornés, direction unitaire, instant fini. Renvoie false et la raison sinon.
function ShotRules.isWellFormed(shot: any): (boolean, string?)
	if type(shot) ~= "table" then
		return false, "tir sans origine ni direction"
	end
	if not isBoundedVector(shot.origin) then
		return false, "origine invalide"
	end
	if not isBoundedVector(shot.hitPos) then
		return false, "point d'impact invalide"
	end
	if not isBoundedVector(shot.direction) then
		return false, "direction invalide"
	end
	local length = shot.direction.Magnitude
	if math.abs(length - 1) > ShotRules.UNIT_TOLERANCE then
		return false, string.format("direction non unitaire (%.3f)", length)
	end
	-- Instant : horloge serveur en secondes ; seul le fini compte, il est borné ensuite au rembobinage
	local t = shot.shotTime
	if type(t) ~= "number" or t ~= t or t == math.huge or t == -math.huge then
		return false, "instant invalide"
	end
	return true
end

-- Cette méthode permet de savoir à quel instant rembobiner la cible lorsqu'un tir arrive : le tireur la voyait
-- INTERP_DELAY avant shotTime ; borné à [now - MAX_REWIND, now] pour qu'un client ne réclame pas une position ancienne.
function ShotRules.rewindTime(shotTime: number, now: number): number
	return math.clamp(shotTime - CharacterSyncRules.INTERP_DELAY, now - PositionHistory.MAX_REWIND, now)
end

-- Cette méthode permet de borner l'instant du tir lorsqu'on cherche la position du tireur au moment du tir.
function ShotRules.shooterTime(shotTime: number, now: number): number
	return math.clamp(shotTime, now - PositionHistory.MAX_REWIND, now)
end

-- Cette méthode permet de vérifier l'origine lorsqu'un tir arrive : à moins de ORIGIN_BASE + vitesse × facteur de
-- l'une des positions connues du tireur (position rembobinée à shotTime, position actuelle).
function ShotRules.checkOrigin(origin: Vector3, shooterPositions: { Vector3 }, shooterSpeed: number): (boolean, string?)
	local limit = ShotRules.ORIGIN_BASE + shooterSpeed * ShotRules.ORIGIN_SPEED_FACTOR
	local best = math.huge
	for _, pos in shooterPositions do
		best = math.min(best, (origin - pos).Magnitude)
	end
	if best <= limit then
		return true
	end
	return false, string.format("origine à %.1f studs du tireur (max %.1f)", best, limit)
end

-- Cette méthode permet de mesurer un point par rapport à un rayon lorsqu'on vérifie la visée : distance au rayon
-- (perpendiculaire, au point de départ si le point est derrière) et abscisse le long du rayon.
function ShotRules.distanceToRay(origin: Vector3, direction: Vector3, point: Vector3): (number, number)
	local along = (point - origin):Dot(direction)
	local closest = origin + direction * math.max(along, 0)
	return (point - closest).Magnitude, along
end

-- Cette méthode permet de calculer la distance permise autour du centre d'une partie lorsqu'on vérifie la visée :
-- rayon englobant de la partie + DIRECTION_BASE + vitesse de la cible × DIRECTION_SPEED_FACTOR.
function ShotRules.directionLimit(partRadius: number, targetSpeed: number): number
	return partRadius + ShotRules.DIRECTION_BASE + targetSpeed * ShotRules.DIRECTION_SPEED_FACTOR
end

-- Cette méthode permet de vérifier la visée lorsqu'un tir arrive : le point d'impact est sur le rayon, devant
-- l'origine, et le rayon comme l'impact passent à moins de limit (directionLimit) de la partie annoncée rembobinée.
function ShotRules.checkDirection(shot: Shot, partCenter: Vector3, limit: number): (boolean, string?)
	local hitOffRay, hitAlong = ShotRules.distanceToRay(shot.origin, shot.direction, shot.hitPos)
	if hitAlong < 0 or hitOffRay > ShotRules.HIT_ON_RAY then
		return false, string.format("impact hors du rayon (%.1f studs)", hitOffRay)
	end
	local rayMiss = ShotRules.distanceToRay(shot.origin, shot.direction, partCenter)
	if rayMiss > limit then
		return false, string.format("rayon à %.1f studs de la partie (max %.1f)", rayMiss, limit)
	end
	local hitMiss = (shot.hitPos - partCenter).Magnitude
	if hitMiss > limit then
		return false, string.format("impact à %.1f studs de la partie (max %.1f)", hitMiss, limit)
	end
	return true
end

-- Cette méthode permet de vérifier la portée lorsqu'un tir arrive : |hitPos - origin| au plus la portée du client.
function ShotRules.checkDistance(shot: Shot): (boolean, string?)
	local limit = WeaponConfig.HITSCAN_RANGE + ShotRules.RANGE_TOLERANCE
	local distance = (shot.hitPos - shot.origin).Magnitude
	if distance <= limit then
		return true
	end
	return false, string.format("tir à %.0f studs (max %.0f)", distance, limit)
end

-- Cette méthode permet de calculer le segment à tester contre la map lorsqu'on vérifie la ligne de vue : de l'origine
-- jusqu'à LINE_OF_SIGHT_END_MARGIN avant le point visé ; nil s'il est plus près que la marge (rien à tester).
function ShotRules.lineOfSightSegment(origin: Vector3, target: Vector3): (Vector3?, Vector3?)
	local delta = target - origin
	local length = delta.Magnitude
	if length <= ShotRules.LINE_OF_SIGHT_END_MARGIN then
		return nil, nil
	end
	return origin, delta.Unit * (length - ShotRules.LINE_OF_SIGHT_END_MARGIN)
end

-- Cette méthode permet de choisir la fenêtre où mesurer une vitesse autour de t lorsqu'on règle une tolérance :
-- SPEED_WINDOW centrée sur t, décalée pour tenir dans [now - MAX_REWIND, now] plutôt que raccourcie.
function ShotRules.speedWindow(t: number, now: number): (number?, number?)
	local oldest = now - PositionHistory.MAX_REWIND
	local from = math.clamp(t - ShotRules.SPEED_WINDOW / 2, oldest, now)
	local to = math.min(from + ShotRules.SPEED_WINDOW, now)
	from = math.max(to - ShotRules.SPEED_WINDOW, oldest)
	if to - from <= 0 then
		return nil, nil
	end
	return from, to
end

-- Cette méthode permet d'estimer la vitesse d'un personnage lorsqu'on règle une tolérance : distance entre deux
-- positions de son historique divisée par leur écart de temps ; 0 sans historique.
function ShotRules.speedBetween(older: Vector3?, newer: Vector3?, dt: number): number
	if not older or not newer or dt <= 0 then
		return 0
	end
	return (newer - older).Magnitude / dt
end

-- Cette méthode permet de vérifier la durée d'equip lorsqu'une touche arrive : l'outil en main est arrivé dans le
-- personnage (equippedAt, nil s'il n'a pas été vu par le serveur) depuis au moins equipTime - EQUIP_TOLERANCE.
function ShotRules.checkEquip(equippedAt: number?, equipTime: number, now: number): (boolean, string?)
	if equippedAt == nil then
		return false, "arme en main sans equip vu par le serveur"
	end
	local elapsed = now - equippedAt
	if elapsed >= equipTime - ShotRules.EQUIP_TOLERANCE then
		return true
	end
	return false,
		string.format("touche %.2f s après l'equip (min %.2f s)", elapsed, equipTime - ShotRules.EQUIP_TOLERANCE)
end

-- Chargeur d'une arme d'un participant (#175) : touches acceptées depuis le dernier rechargement fini, rechargement
-- en cours (instant de l'action Reload) et touches déjà comptées à son début (celles d'après restent dues).
export type Magazine = { shots: number, reloadAt: number?, shotsAtReload: number }

-- Cette méthode permet de créer le chargeur plein d'une arme lorsqu'elle tire ou recharge pour la première fois.
function ShotRules.newMagazine(): Magazine
	return { shots = 0, reloadAt = nil, shotsAtReload = 0 }
end

-- Cette méthode permet de terminer le rechargement en cours lorsqu'il a duré reloadTime - RELOAD_TOLERANCE : le
-- chargeur est rempli (réserve illimitée, #165), seules restent dues les touches acceptées pendant le rechargement.
function ShotRules.settleReload(mag: Magazine, reloadTime: number, now: number)
	local reloadAt = mag.reloadAt
	if reloadAt and now - reloadAt >= reloadTime - ShotRules.RELOAD_TOLERANCE then
		mag.shots = math.max(0, mag.shots - mag.shotsAtReload)
		mag.reloadAt = nil
		mag.shotsAtReload = 0
	end
end

-- Cette méthode permet de démarrer un rechargement lorsque l'action Reload arrive : un rechargement déjà fini est
-- d'abord compté, un rechargement inachevé repart de zéro.
function ShotRules.startReload(mag: Magazine, reloadTime: number, now: number)
	ShotRules.settleReload(mag, reloadTime, now)
	mag.reloadAt = now
	mag.shotsAtReload = mag.shots
end

-- Cette méthode permet d'annuler le rechargement en cours lorsque l'arme est rangée ou changée (comme le client) ;
-- un rechargement déjà fini reste acquis.
function ShotRules.cancelReload(mag: Magazine, reloadTime: number, now: number)
	ShotRules.settleReload(mag, reloadTime, now)
	mag.reloadAt = nil
	mag.shotsAtReload = 0
end

-- Cette méthode permet de vérifier le chargeur lorsqu'une touche arrive : moins de size touches acceptées depuis le
-- dernier rechargement fini.
function ShotRules.checkMagazine(mag: Magazine, size: number, reloadTime: number, now: number): (boolean, string?)
	ShotRules.settleReload(mag, reloadTime, now)
	if mag.shots < size then
		return true
	end
	local reloadAt = mag.reloadAt
	if reloadAt then
		return false,
			string.format(
				"chargeur vide (%d touches), rechargement depuis %.2f s (min %.2f s)",
				mag.shots,
				now - reloadAt,
				reloadTime - ShotRules.RELOAD_TOLERANCE
			)
	end
	return false, string.format("chargeur vide (%d touches) sans rechargement", mag.shots)
end

-- Cette méthode permet de compter une touche acceptée dans le chargeur lorsqu'elle est appliquée.
function ShotRules.countShot(mag: Magazine)
	mag.shots += 1
end

-- Cette méthode permet de savoir si l'échec d'un contrôle refuse le tir lorsqu'il est constaté (mode "block") ;
-- un contrôle sans mode connu bloque, par prudence.
function ShotRules.blocks(check: string, modes: { [string]: Mode }?): boolean
	return (modes or ShotRules.MODES)[check] ~= ShotRules.Mode.LOG
end

-- Cette méthode permet de savoir si l'échec d'un contrôle refuse le tir lorsqu'il est constaté : mode "block", ou
-- contrôle couvert par LOG_ONLY_RANGE pour un tir dont les racines sont à plus de LOG_ONLY_RANGE studs.
function ShotRules.refuses(check: string, rootDistance: number, modes: { [string]: Mode }?): boolean
	return ShotRules.blocks(check, modes)
		or (ShotRules.LOG_ONLY_RANGE_CHECKS[check] == true and rootDistance > ShotRules.LOG_ONLY_RANGE)
end

return ShotRules

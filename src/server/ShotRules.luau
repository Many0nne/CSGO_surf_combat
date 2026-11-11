-- Règles pures de validation d'un tir de joueur (#174, docs/anticheat.md « T1 ») : le client envoie l'origine, la
-- direction, le point d'impact et l'instant du tir ; le serveur vérifie que ce tir pouvait toucher la partie annoncée.
-- Aucun service hors les modules partagés (ReplicatedStorage), ni workspace : positions rembobinées, vitesses et
-- raycast de ligne de vue sont fournis par l'appelant (Validator). Testées sous Lune (tests/specs/ShotRules.spec.luau, tests/specs/Validator.spec.luau).
-- Chaque contrôle a un mode : "log" (violation journalisée, tir appliqué : phase de mesure) ou "block" (tir refusé).
-- Durée d'equip et chargeur (#175, « T2 ») : règles pures ici aussi, l'état (instants, compteurs) vit dans Validator.
-- Mêlée (#176, « M1 ») : orientation du tireur et ligne de vue vers la cible rembobinée, mêmes modes et même journal.
-- Instant annoncé (#214) : shotTime (tir) et hitTime (mêlée) bornés par le ping du tireur, contrôle « ping ».
-- Pose rembobinée (#213) : la partie visée est replacée selon le cap et l'accroupi de la cible à l'instant rembobiné.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CheatTypes = require(ServerScriptService.Server.CheatTypes)
local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local ShotRules = {}

export type Mode = "log" | "block"
-- Gravités du journal : CheatTypes, que CheatLog ré-exporte (ShotRules ne dépend pas de CheatLog, qui demande des
-- services).
export type Severity = CheatTypes.Severity
export type Shot = { origin: Vector3, direction: Vector3, hitPos: Vector3, shotTime: number }
-- Pose rembobinée d'un personnage (#213) : racine, cap (rad, nil si inconnu) et accroupi (nil si inconnu).
export type Pose = { pos: Vector3, yaw: number?, crouching: boolean? }

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
	ORIENTATION = "orientation", -- cible devant le cap du tireur (#176, mêlée)
	MELEE_LINE_OF_SIGHT = "meleeLineOfSight", -- aucun obstacle de la map entre tireur et cible (#176, mêlée)
	SHOT_LINK = "shotLink", -- touche rattachée à un ShotFired accepté du même instant (#216, tir)
	PING = "ping", -- instant annoncé (shotTime, hitTime) dans la borne du ping du tireur (#214, tir et mêlée)
}

-- Mode de chaque contrôle. "log" tant que les faux positifs ne sont pas mesurés en jeu (docs/anticheat.md, « T1 » :
-- procédure pour passer en "block") ; forme et distance ne dépendent pas du réseau, donc bloquants d'emblée. Equip et
-- chargeur (#175) : règles déterministes à tolérance de gigue, sans faux positif mesuré, bloquants d'emblée. Mêlée
-- (#176) : cap du tireur relayé à 20 Hz, faux positifs possibles en rotation rapide, journal seul jusqu'à mesure en jeu.
-- Touche sans tir rattaché (#216) : un ShotFired écarté par le relais (cadence à la gigue près, origine) la rend
-- orpheline chez un joueur honnête, journal seul jusqu'à mesure en jeu ; le chargeur la compte quand même.
-- Instant hors du ping (#214) : pic de latence, horloge mal synchronisée, journal seul jusqu'à mesure en jeu publié
-- (Studio n'a pas de latence).
ShotRules.MODES = {
	shape = "block",
	origin = "log",
	direction = "log",
	distance = "block",
	lineOfSight = "log",
	equip = "block",
	magazine = "block",
	orientation = "log",
	meleeLineOfSight = "log",
	shotLink = "log",
	ping = "log",
} :: { [string]: Mode }

-- Gravité d'un échec au journal (CheatTypes.Severity) : une forme impossible ne vient jamais de notre client
-- (forte) ; les autres s'expliquent par le réseau ou un bug de tolérance (moyennes, docs/anticheat.md).
ShotRules.SEVERITY = {
	shape = CheatTypes.Severity.HIGH,
	origin = CheatTypes.Severity.MEDIUM,
	direction = CheatTypes.Severity.MEDIUM,
	distance = CheatTypes.Severity.MEDIUM,
	lineOfSight = CheatTypes.Severity.MEDIUM,
	equip = CheatTypes.Severity.MEDIUM,
	magazine = CheatTypes.Severity.MEDIUM,
	orientation = CheatTypes.Severity.MEDIUM,
	meleeLineOfSight = CheatTypes.Severity.MEDIUM,
	-- Faible : un tir relayé écarté de peu (gigue) en produit, et le chargeur reste compté (#216)
	shotLink = CheatTypes.Severity.LOW,
	ping = CheatTypes.Severity.MEDIUM,
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
-- Cadence d'une arme (s) : un tir est accepté FireDelay - CADENCE_TOLERANCE après le précédent (gigue entre deux
-- paquets). Partagée par les touches (Validator) et le relais des tirs aux autres clients (ShotRelayRules, #156).
ShotRules.CADENCE_TOLERANCE = 0.15
-- Fenêtre (s) sur laquelle la vitesse d'un personnage est estimée dans son historique.
ShotRules.SPEED_WINDOW = 0.1
-- Equip (#175) : une touche est acceptée à partir de equippedAt + EquipTime - EQUIP_TOLERANCE. equippedAt est
-- l'arrivée de l'outil dans le personnage sur le serveur, la touche arrive au moins EquipTime plus tard (le client
-- honnête n'est jamais prêt plus tôt, #184) : la tolérance couvre la gigue entre les deux paquets.
ShotRules.EQUIP_TOLERANCE = 0.2
-- Chargeur (#175) : un rechargement compte comme fini ReloadTime - RELOAD_TOLERANCE après l'arrivée de l'action
-- Reload (même gigue entre l'action et la touche suivante).
ShotRules.RELOAD_TOLERANCE = 0.2
-- Changement d'arme pendant un rechargement : celui-ci compte comme fini s'il ne lui manquait pas plus de
-- RELOAD_CANCEL_TOLERANCE (s). Une action Reload arrivée en retard ne doit pas faire refuser tout le chargeur suivant à
-- un joueur qui a fini de recharger puis changé d'arme aussitôt ; un tricheur n'y gagne rien, ressortir l'arme lui
-- coûte son equip (AWP : 1,38 s au moins), plus que cette marge.
ShotRules.RELOAD_CANCEL_TOLERANCE = 1
-- Mêlée (#176) : angle horizontal maximal (degrés) entre le cap du tireur et la direction de la racine de la cible.
-- Le rayon du client part de la caméra, au cap de la racine (MovementController) ; la géométrie seule demande
-- asin(MELEE_BODY_RADIUS / distance), soit 15° à 7,5 studs : le reste couvre le retard du cap relayé (20 Hz, plus la
-- gigue), environ 1 000°/s de rotation pendant 50 ms.
ShotRules.MELEE_MAX_ANGLE = 70
-- Demi-largeur (studs) d'un personnage vu de dessus, bras compris : le rayon peut toucher le bord du corps plutôt que
-- son axe, l'angle permis est élargi de asin(MELEE_BODY_RADIUS / distance horizontale) (90° au contact).
ShotRules.MELEE_BODY_RADIUS = 2
-- Instant annoncé (#214) : un tir honnête arrive now - shotTime = aller simple + délais de frame après son départ.
-- Borne = ping du tireur (Player:GetNetworkPing, aller-retour moyen mesuré par le moteur) × PING_FACTOR + PING_MARGIN.
-- Facteur 2 : un remote fiable perdu est renvoyé (un aller-retour de plus), un aller peut être plus lent que le
-- retour, et des retours du DevForum disent que GetNetworkPing rend la moitié de l'aller-retour (la doc dit
-- l'aller-retour) : à vérifier en jeu publié avant de serrer. La marge couvre la frame du tir, le tick réseau du
-- client, le Heartbeat du serveur et la synchronisation de GetServerTimeNow. Un instant plus ancien vise une position
-- de la cible que le tireur ne voyait plus (« backtrack »).
ShotRules.PING_FACTOR = 2
ShotRules.PING_MARGIN = 0.1
-- Avance tolérée (s) d'un instant annoncé sur l'horloge serveur (erreur de synchronisation de GetServerTimeNow).
ShotRules.CLOCK_TOLERANCE = 0.05
-- Accroupi (#213) : baisse (studs) des parties au-dessus de la racine telle que la voit le tireur. Le rig 3P ne
-- s'accroupit pas (CharacterConfig.ANIMATIONS : CROUCH_IDLE et CROUCH_WALK vides, repli sur IDLE et WALK) : un tireur
-- voit la cible debout, accroupie ou non, donc 0. À régler sur la piste publiée le jour où elle existe (le test
-- « CROUCH_DROP suit la piste 3P » de ShotRules.spec.luau échoue tant que les deux ne concordent pas).
ShotRules.CROUCH_DROP = 0

-- Cette méthode permet de vérifier qu'un Vector3 est fini et borné par MAX_COORD lorsqu'un point de tir arrive.
local function isBoundedVector(v: any): boolean
	return MathRules.isBoundedVector3(v, ShotRules.MAX_COORD)
end

ShotRules.isBoundedVector = isBoundedVector

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
	if not MathRules.isFinite(t) then
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

-- Cette méthode permet de calculer le plus grand écart permis (s) entre l'instant annoncé et l'arrivée lorsqu'un tir
-- ou un coup arrive : ping (aller-retour, s) × PING_FACTOR + PING_MARGIN.
function ShotRules.maxShotDelay(ping: number): number
	return math.max(ping, 0) * ShotRules.PING_FACTOR + ShotRules.PING_MARGIN
end

-- Cette méthode permet de vérifier l'instant annoncé (shotTime, hitTime) lorsqu'un tir ou un coup arrive : pas plus
-- ancien que maxShotDelay(ping) ni en avance de plus de CLOCK_TOLERANCE sur now. Sans ping connu (nil, non fini) :
-- accepté, rien à comparer.
function ShotRules.checkShotDelay(shotTime: number, now: number, ping: number?): (boolean, string?)
	if ping == nil or not MathRules.isFinite(ping) then
		return true
	end
	local delay = now - shotTime
	local limit = ShotRules.maxShotDelay(ping)
	if delay < -ShotRules.CLOCK_TOLERANCE then
		return false, string.format("instant %.2f s dans le futur (max %.2f s)", -delay, ShotRules.CLOCK_TOLERANCE)
	end
	if delay > limit then
		return false,
			string.format("instant %.2f s avant l'arrivée (max %.2f s, ping %.0f ms)", delay, limit, ping * 1000)
	end
	return true
end

-- Cette méthode permet de replacer une partie de la cible dans sa pose rembobinée lorsqu'on vérifie un tir ou un coup
-- (#213) : décalage de la partie pris sur le rig serveur dans le repère de sa racine (rootCFrame, rootPos), corrigé de
-- CROUCH_DROP si l'accroupi diffère (parties au-dessus de la racine), tourné au cap rembobiné (cap actuel s'il est
-- inconnu) et posé sur la racine rembobinée.
function ShotRules.posedPartCenter(
	rootCFrame: CFrame,
	rootPos: Vector3,
	partPos: Vector3,
	crouchingNow: boolean?,
	pose: Pose
): Vector3
	-- Rotation seule : la position de la racine est lue à part (sous Lune, Position et CFrame sont posées séparément)
	local offset = rootCFrame:VectorToObjectSpace(partPos - rootPos)
	local drop = ShotRules.CROUCH_DROP
	if offset.Y > 0 and crouchingNow ~= nil and pose.crouching ~= nil and crouchingNow ~= pose.crouching then
		offset += Vector3.new(0, if pose.crouching then -drop else drop, 0)
	end
	local yaw = pose.yaw
	local world = if yaw
		then CFrame.Angles(0, yaw, 0):VectorToWorldSpace(offset)
		else rootCFrame:VectorToWorldSpace(offset)
	return pose.pos + world
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

-- Chargeur d'une arme d'un participant (#175) : tirs comptés depuis le dernier rechargement fini (ShotFired acceptés et
-- touches orphelines, #215), et rechargement
-- en cours (instant de l'action Reload, nil sinon).
-- lastShotAt : arrivée du dernier tir compté (borne le début d'un rechargement, Validator.noteReload).
export type Magazine = { shots: number, reloadAt: number?, lastShotAt: number? }

-- Cette méthode permet de créer le chargeur plein d'une arme lorsqu'elle tire ou recharge pour la première fois.
function ShotRules.newMagazine(): Magazine
	return { shots = 0, reloadAt = nil, lastShotAt = nil }
end

-- Cette méthode permet de terminer le rechargement en cours lorsqu'il a duré reloadTime - tolerance (RELOAD_TOLERANCE
-- par défaut) : le chargeur est rempli (réserve illimitée, #165).
function ShotRules.settleReload(mag: Magazine, reloadTime: number, now: number, tolerance: number?)
	local reloadAt = mag.reloadAt
	if reloadAt and now - reloadAt >= reloadTime - (tolerance or ShotRules.RELOAD_TOLERANCE) then
		mag.shots = 0
		mag.reloadAt = nil
	end
end

-- Cette méthode permet de démarrer un rechargement lorsque l'action Reload arrive : un rechargement déjà fini est
-- d'abord compté, un rechargement inachevé repart de zéro.
function ShotRules.startReload(mag: Magazine, reloadTime: number, now: number)
	ShotRules.settleReload(mag, reloadTime, now)
	mag.reloadAt = now
end

-- Cette méthode permet d'annuler le rechargement en cours lorsque l'arme est rangée ou changée (comme le client) ;
-- un rechargement fini, à RELOAD_CANCEL_TOLERANCE près (retard de l'action Reload), reste acquis.
function ShotRules.cancelReload(mag: Magazine, reloadTime: number, now: number)
	ShotRules.settleReload(mag, reloadTime, now, ShotRules.RELOAD_CANCEL_TOLERANCE)
	mag.reloadAt = nil
end

-- Cette méthode permet de vérifier le chargeur lorsqu'un tir arrive (ShotFired, ou touche orpheline) : aucun rechargement
-- inachevé (le client ne tire pas en RELOADING, un Reload en boucle ne remet rien à zéro) et moins de size tirs comptés
-- depuis le dernier rechargement.
function ShotRules.checkMagazine(mag: Magazine, size: number, reloadTime: number, now: number): (boolean, string?)
	ShotRules.settleReload(mag, reloadTime, now)
	local reloadAt = mag.reloadAt
	if reloadAt then
		return false,
			string.format(
				"tir pendant le rechargement (depuis %.2f s, min %.2f s)",
				-- Un Reload reçu pendant l'equip démarre à la fin de l'equip : pas de durée négative au journal
				math.max(0, now - reloadAt),
				reloadTime - ShotRules.RELOAD_TOLERANCE
			)
	end
	if mag.shots < size then
		return true
	end
	return false, string.format("chargeur vide (%d tirs) sans rechargement", mag.shots)
end

-- Cette méthode permet de compter un tir dans le chargeur lorsqu'il est accepté : ShotFired relayé, ou touche orpheline
-- appliquée (#215 : chaque tir n'est compté qu'une fois).
function ShotRules.countShot(mag: Magazine, now: number)
	mag.shots += 1
	mag.lastShotAt = now
end

-- Cette méthode permet de mesurer l'angle horizontal (degrés) entre un cap et la direction d'un point à un autre
-- lorsqu'on vérifie l'orientation d'un coup ; renvoie aussi la distance horizontale (angle nil si elle est nulle).
function ShotRules.horizontalAngle(look: Vector3, from: Vector3, to: Vector3): (number?, number)
	local delta = to - from
	return MathRules.horizontalAngle(look, delta, 1e-3), MathRules.horizontalLength(delta)
end

-- Cette méthode permet de calculer l'angle permis (degrés) lorsqu'on vérifie l'orientation d'un coup : MELEE_MAX_ANGLE
-- plus l'angle sous lequel le tireur voit la demi-largeur du corps de la cible (bord du corps touché), d'après la
-- distance 3D : une cible juste au-dessous, mais loin en hauteur, n'ouvre pas l'angle (rampe de surf).
function ShotRules.meleeAngleLimit(distance: number): number
	local ratio = if distance > 0 then math.min(1, ShotRules.MELEE_BODY_RADIUS / distance) else 1
	return ShotRules.MELEE_MAX_ANGLE + math.deg(math.asin(ratio))
end

-- Cette méthode permet de vérifier qu'une position de la cible est devant le tireur lorsqu'un coup de mêlée arrive :
-- angle horizontal entre son cap (look) et la cible au plus meleeAngleLimit. Renvoie aussi l'excès d'angle (degrés,
-- négatif ou nul si accepté) et le détail, pour retenir la position la plus proche au journal.
function ShotRules.checkMeleeOrientation(
	look: Vector3,
	attackerPos: Vector3,
	targetPos: Vector3
): (boolean, number, string?)
	local angle, horizontal = ShotRules.horizontalAngle(look, attackerPos, targetPos)
	local delta = targetPos - attackerPos
	if
		angle == nil or (horizontal <= ShotRules.MELEE_BODY_RADIUS and math.abs(delta.Y) > ShotRules.MELEE_BODY_RADIUS)
	then
		-- Cible à l'aplomb du tireur, nettement au-dessus ou au-dessous : son corps passe sous (ou sur) le tireur, un
		-- regard vers le bas (ou le haut) la touche quel que soit le cap. À même hauteur, l'angle permis s'applique
		return true, -math.huge, nil
	end
	local distance = delta.Magnitude
	local limit = ShotRules.meleeAngleLimit(distance)
	local excess = angle - limit
	if excess <= 0 then
		return true, excess, nil
	end
	return false, excess, string.format("cible à %.0f° du cap (max %.0f°) à %.1f studs", angle, limit, distance)
end

-- Cette méthode permet de lister les segments à tester contre la map lorsqu'on vérifie la ligne de vue d'un coup :
-- racine à racine, et œil du tireur (eyeOffset, hauteur de la caméra) à tête de la cible (headOffset) pour un obstacle
-- bas par-dessus lequel la caméra frappe. Un seul segment dégagé suffit ; segments nuls (cibles collées) omis.
function ShotRules.meleeSightSegments(
	attackerPos: Vector3,
	targetPos: Vector3,
	eyeOffset: Vector3,
	headOffset: Vector3
): { { from: Vector3, delta: Vector3 } }
	local segments = {}
	for _, ends in { { Vector3.zero, Vector3.zero }, { eyeOffset, headOffset } } do
		local from, delta = ShotRules.lineOfSightSegment(attackerPos + ends[1], targetPos + ends[2])
		if from and delta then
			table.insert(segments, { from = from, delta = delta })
		end
	end
	return segments
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

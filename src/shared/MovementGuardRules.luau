-- Règles pures du noclip, du vol et du vide (#177, docs/anticheat.md « D2 »). Le serveur (CharacterSync) juge chaque
-- position acceptée par le seau de distance (D1) : il fournit la géométrie de la map (rayons, surfaces proches,
-- échelles, boosts) sous forme de fonctions, ce module décide. Sans raycast ni workspace : testable sous Lune.
--
-- - Noclip : le segment entre deux positions (centre du personnage) ne traverse pas de paroi, ou un détour court existe
--   (arête de rampe, coin de mur frôlés à grande vitesse : la corde coupe l'angle, la trajectoire non).
-- - Vol : loin de toute surface, la hauteur reste sous l'enveloppe balistique partie du dernier décollage (gravité,
--   chute plafonnée à MAX_FALL_SPEED), avec une marge de temps pour la gigue réseau et une vitesse de décollage
--   estimée large (saut, rampe, boost, lancement depuis le soleil).
-- - Vide : un joueur en l'air sans paquet depuis VOID_SILENCE, dont même la plus haute position possible est passée
--   sous la hauteur de mort, au-dessus du vide, est tombé.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapRules = require(ReplicatedStorage.Shared.MapRules)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local MovementGuardRules = {}

-- Modes : true = la violation est refusée et corrigée (CharacterSync.refuse, comme le seau de D1) ; false = journal
-- seul (violation comptée dans CheatLog, position appliquée). Noclip et vol restent en journal seul tant que surf,
-- échelles et boosts n'ont pas été observés sans faux positif en jeu publié (procédure : docs/anticheat.md, D2).
MovementGuardRules.ENFORCE_NOCLIP = false
MovementGuardRules.ENFORCE_FLIGHT = false
-- Vide : true = le joueur est tué (KillZone) ; false = journal seul. Actif : seuils larges, un honnête dans ce cas
-- tombait de toute façon.
MovementGuardRules.ENFORCE_VOID = true

-- Noclip : écart (studs) du point milieu des détours essayés quand le segment direct touche une paroi, base plus une
-- part de la longueur du segment (la corde d'un virage rapide s'écarte plus de la trajectoire).
MovementGuardRules.NOCLIP_DETOUR_BASE = 2
MovementGuardRules.NOCLIP_DETOUR_RATIO = 0.25
-- En dessous de cette longueur (studs), un segment n'est pas testé.
MovementGuardRules.NOCLIP_MIN_LENGTH = 0.05

-- Vol : distance (studs) du centre du personnage à une surface en dessous de laquelle il est porté (sol, rampe, bord
-- de mur). Debout, le centre est à ~2,4 studs du sol ; la marge couvre le paquet pris juste après un rebond de bhop.
MovementGuardRules.SUPPORT_REACH = 6
-- Une surface ne porte que si elle est sous le personnage ou à côté et inclinée vers le haut : composante Y minimale de
-- la direction surface → centre (un mur vertical ne porte pas, une rampe de surf si).
MovementGuardRules.SUPPORT_MIN_NORMAL_Y = 0.05
-- Marge de temps (s) de l'enveloppe : l'heure d'arrivée d'un paquet peut s'écarter de son heure d'envoi (gigue, paquets
-- groupés, retard d'une correction).
MovementGuardRules.FLIGHT_TIME_SLACK = 0.25
-- Marge de hauteur (studs) au-dessus de l'enveloppe.
MovementGuardRules.FLIGHT_HEIGHT_TOLERANCE = 3
-- Intervalle minimal (s) entre deux paquets d'un client honnête : le client envoie à SEND_INTERVAL en reportant le
-- reste, deux envois sont donc séparés d'au moins une frame et d'au moins SEND_INTERVAL moins une frame, soit au moins
-- la moitié de SEND_INTERVAL. Sert à majorer la vitesse verticale au décollage.
MovementGuardRules.MIN_PACKET_INTERVAL = 0.5 / MovementConfig.NET_SYNC_RATE
-- Marge (studs/s) ajoutée à la vitesse verticale déduite des paquets en l'air (positions affichées interpolées entre
-- deux pas, glissement sur un mur presque vertical).
MovementGuardRules.REFINE_MARGIN = 10
-- Pas (studs) des points testés le long d'un segment pour trouver un support : un contact entre deux paquets (rebond
-- de bhop, arête de rampe frôlée à grande vitesse) n'est pas manqué.
MovementGuardRules.SUPPORT_STEP = 3

-- Vide : silence (s) au-delà duquel un joueur en l'air peut être déclaré tombé.
MovementGuardRules.VOID_SILENCE = 2
-- Marge horizontale (studs) de la zone où chercher un sol sous un joueur silencieux.
MovementGuardRules.VOID_PROBE_MARGIN = 6

local GRAVITY = -MovementConfig.GRAVITY -- intensité (positive)
local SEND_INTERVAL = 1 / MovementConfig.NET_SYNC_RATE
local MAX_FALL = MovementConfig.MAX_FALL_SPEED

-- Pièce de la map vue par les règles : un Part ou une table équivalente (tests).
export type Box = { CFrame: CFrame, Size: Vector3 }

-- Vol d'un personnage : `anchored` faux tant qu'il est porté (le prochain paquet en l'air fixe l'enveloppe) ;
-- l'enveloppe part de (anchorAt, anchorY) avec la vitesse verticale anchorVy au plus. lastAt/lastY : dernier paquet
-- jugé. launchVy : vitesse verticale imposée connue (lancement, geyser) à prendre au prochain décollage. baseY : hauteur
-- du premier paquet en l'air, et count : paquets en l'air reçus depuis, pour resserrer l'enveloppe. suspect : le
-- paquet précédent dépassait l'enveloppe (un vol n'est signalé qu'au second de suite).
export type Flight = {
	anchored: boolean,
	anchorAt: number,
	anchorY: number,
	anchorVy: number,
	lastAt: number,
	lastY: number,
	launchVy: number,
	baseY: number,
	count: number,
	suspect: boolean,
}

-- Suivi D2 d'un personnage : vol, `fresh` tant que le premier paquet (dont le point de départ est la racine posée par
-- le serveur, pas une position du client) n'est pas passé, heardAt = heure du dernier paquet reçu (jugé ou ignoré en
-- attente d'accusé : le client vit), speedXZ = vitesse horizontale majorée du dernier paquet jugé (vide).
export type Guard = { flight: Flight, fresh: boolean, heardAt: number, speedXZ: number }

-- Géométrie fournie par le serveur : `isBlocked(a, b)` = un rayon de a vers b touche une paroi de la map ;
-- `support(from, to)` = (porté le long du segment ou sur une échelle, vitesse verticale imposée par un boost touché le
-- long du segment ou 0).
export type Geometry = {
	isBlocked: (Vector3, Vector3) -> boolean,
	support: (Vector3, Vector3) -> (boolean, number),
}

export type Verdict = { rule: string, enforce: boolean, detail: string }

-- Cette méthode permet de calculer les points milieux des détours essayés lorsqu'un segment touche une paroi : milieu
-- décalé dans quatre directions perpendiculaires (haut, bas, côtés ; deux horizontales pour un segment vertical).
function MovementGuardRules.detours(from: Vector3, to: Vector3): { Vector3 }
	local delta = to - from
	local length = delta.Magnitude
	local dir = delta / length
	local side = dir:Cross(Vector3.yAxis)
	local up
	if side.Magnitude < 0.1 then
		side, up = Vector3.xAxis, Vector3.zAxis
	else
		side = side.Unit
		up = side:Cross(dir).Unit
	end
	local offset = MovementGuardRules.NOCLIP_DETOUR_BASE + MovementGuardRules.NOCLIP_DETOUR_RATIO * length
	local mid = (from + to) / 2
	return { mid + up * offset, mid - up * offset, mid + side * offset, mid - side * offset }
end

-- Cette méthode permet de décider si un déplacement traverse une paroi lorsque le serveur reçoit une position : le
-- segment direct est libre, ou l'un des détours courts (deux segments par le milieu décalé) l'est ; sinon noclip.
function MovementGuardRules.crossesWall(from: Vector3, to: Vector3, isBlocked: (Vector3, Vector3) -> boolean): boolean
	if (to - from).Magnitude < MovementGuardRules.NOCLIP_MIN_LENGTH or not isBlocked(from, to) then
		return false
	end
	for _, mid in MovementGuardRules.detours(from, to) do
		if not isBlocked(from, mid) and not isBlocked(mid, to) then
			return false
		end
	end
	return true
end

-- Cette méthode permet de savoir si une pièce porte un personnage dont le centre est en `center` lorsque le serveur
-- cherche un support : point de la boîte orientée le plus proche à moins de SUPPORT_REACH, et sous le centre ou à côté
-- en pente (centre dans la boîte : porté, cas d'un coin ou d'un WedgePart, dont la boîte est un majorant).
function MovementGuardRules.supports(box: Box, center: Vector3): boolean
	local rel = box.CFrame:PointToObjectSpace(center)
	local half = box.Size / 2
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	local away = center - box.CFrame:PointToWorldSpace(clamped)
	local distance = away.Magnitude
	if distance < 1e-3 then
		return true
	end
	return distance <= MovementGuardRules.SUPPORT_REACH and away.Y / distance >= MovementGuardRules.SUPPORT_MIN_NORMAL_Y
end

-- Cette méthode permet de savoir si une des pièces proches porte le personnage le long d'un segment lorsque le serveur
-- cherche un support : points espacés d'au plus SUPPORT_STEP, du premier pas jusqu'à l'arrivée (le départ a été
-- jugé au paquet précédent).
function MovementGuardRules.supportedAlong(parts: { Box }, from: Vector3, to: Vector3): boolean
	local steps = math.max(1, math.ceil((to - from).Magnitude / MovementGuardRules.SUPPORT_STEP))
	for _, part in parts do
		for i = 1, steps do
			if MovementGuardRules.supports(part, from:Lerp(to, i / steps)) then
				return true
			end
		end
	end
	return false
end

-- Cette méthode permet de savoir si un segment passe dans un volume (échelle, boost) lorsque le serveur ne voit que
-- deux positions espacées : milieu du segment dans la boîte élargie du rayon du personnage et d'un demi-segment.
function MovementGuardRules.touchesVolume(from: Vector3, to: Vector3, cf: CFrame, size: Vector3): boolean
	local half = (to - from).Magnitude / 2
	return MapRules.contains(cf, size, (from + to) / 2, MovementConfig.CHAR_RADIUS + half)
end

-- Cette méthode permet de créer le suivi du vol d'un personnage lorsque le serveur commence à le suivre (apparition) :
-- porté jusqu'au premier paquet, avec la vitesse verticale du lancement depuis le soleil s'il y en a un.
function MovementGuardRules.newFlight(now: number, y: number, launchVy: number?): Flight
	return {
		anchored = false,
		anchorAt = now,
		anchorY = y,
		anchorVy = 0,
		lastAt = now,
		lastY = y,
		launchVy = math.max(launchVy or 0, 0),
		baseY = y,
		count = 0,
		suspect = false,
	}
end

-- Cette méthode permet de créer le suivi D2 d'un personnage lorsque le serveur reçoit son premier paquet.
function MovementGuardRules.newGuard(now: number, pos: Vector3, launchVy: number?): Guard
	return { flight = MovementGuardRules.newFlight(now, pos.Y, launchVy), fresh = true, heardAt = now, speedXZ = 0 }
end

-- Cette méthode permet de repartir d'une correction lorsque le serveur renvoie le client à sa dernière position
-- acceptée (y) : le client y est replacé vitesse nulle puis tombe ; enveloppe ancrée là, avec la vitesse d'un saut
-- pour couvrir le délai avant que le client n'applique la correction.
function MovementGuardRules.restart(flight: Flight, now: number, y: number)
	flight.anchored = true
	flight.anchorAt = now
	flight.anchorY = y
	flight.anchorVy = MovementConfig.JUMP_VELOCITY
	flight.lastAt = now
	flight.lastY = y
	flight.launchVy = 0
	flight.baseY = y
	flight.count = 0
	flight.suspect = false
end

-- Cette méthode permet de majorer la vitesse verticale au décollage lorsqu'un premier paquet en l'air arrive : montée
-- depuis le paquet précédent sur l'intervalle minimal d'un client, ou vitesse imposée connue, plus un saut (rebond ou
-- rampe pendant l'intervalle), bornée par la vitesse maximale du serveur.
local function takeoffVy(flight: Flight, y: number): number
	local rise = math.max(0, y - flight.lastY) / MovementGuardRules.MIN_PACKET_INTERVAL
	local cap = math.max(MovementConfig.MAX_SPEED_SERVER, flight.launchVy) + MovementConfig.JUMP_VELOCITY
	return math.min(math.max(rise, flight.launchVy) + MovementConfig.JUMP_VELOCITY, cap)
end

-- Cette méthode permet de majorer la vitesse verticale actuelle d'un joueur en chute libre lorsque sa hauteur a varié
-- de `rise` depuis le premier paquet en l'air, en au moins `elapsed` secondes : sur une parabole, v = rise/E - g·E/2,
-- maximum sur E ≥ elapsed ; jamais sous -MAX_FALL_SPEED (chute plafonnée, la parabole ne vaut plus).
local function maxVyAfter(rise: number, elapsed: number): number
	local e = elapsed
	if rise < 0 then
		e = math.max(elapsed, math.sqrt(-2 * rise / GRAVITY))
	end
	return math.max(rise / e - 0.5 * GRAVITY * e, -MAX_FALL)
end

-- Cette méthode permet de calculer la hauteur gagnée s secondes après un décollage à la vitesse verticale vy lorsqu'on
-- trace l'enveloppe : gravité, puis chute à vitesse constante une fois MAX_FALL_SPEED atteinte.
function MovementGuardRules.ballistic(vy: number, s: number): number
	local terminalAt = (vy + MAX_FALL) / GRAVITY
	if s <= terminalAt then
		return vy * s - 0.5 * GRAVITY * s * s
	end
	return vy * terminalAt - 0.5 * GRAVITY * terminalAt * terminalAt - MAX_FALL * (s - terminalAt)
end

-- Cette méthode permet de connaître la plus haute position possible d'un joueur honnête à l'instant now lorsqu'il est
-- en l'air : maximum de l'enveloppe sur [τ - FLIGHT_TIME_SLACK, τ + FLIGHT_TIME_SLACK] (courbe concave : sommet borné
-- à l'intervalle), plus FLIGHT_HEIGHT_TOLERANCE. math.huge s'il est porté.
function MovementGuardRules.ceiling(flight: Flight, now: number): number
	if not flight.anchored then
		return math.huge
	end
	local tau = now - flight.anchorAt
	local slack = MovementGuardRules.FLIGHT_TIME_SLACK
	local s = math.clamp(flight.anchorVy / GRAVITY, math.max(0, tau - slack), tau + slack)
	return flight.anchorY
		+ MovementGuardRules.ballistic(flight.anchorVy, s)
		+ MovementGuardRules.FLIGHT_HEIGHT_TOLERANCE
end

-- Cette méthode permet de juger la hauteur d'un paquet lorsqu'il arrive : porté, l'enveloppe attend le décollage ;
-- premier paquet en l'air, l'enveloppe part de lui ; ensuite, deux paquets de suite au-dessus de l'enveloppe = vol
-- (un seul : paquet arrivé en désordre). Sous l'enveloppe, elle est resserrée : la hauteur gagnée depuis le premier
-- paquet en l'air, en un temps au moins égal à celui de ses paquets (deux de marge pour le désordre), majore la vitesse
-- actuelle. Renvoie (honnête, dépassement en studs). Après un vol, l'enveloppe repart de ce point à l'arrêt : un joueur
-- qui plane encore n'est signalé qu'une fois cette nouvelle marge épuisée, pas à chaque paquet.
function MovementGuardRules.observe(flight: Flight, now: number, y: number, supported: boolean): (boolean, number)
	if supported then
		flight.anchored = false
		flight.suspect = false
		flight.lastAt, flight.lastY = now, y
		return true, 0
	end
	if not flight.anchored then
		flight.anchored = true
		flight.anchorAt, flight.anchorY, flight.anchorVy = now, y, takeoffVy(flight, y)
		flight.launchVy = 0
		flight.lastAt, flight.lastY = now, y
		flight.baseY, flight.count = y, 0
		return true, 0
	end
	local limit = MovementGuardRules.ceiling(flight, now)
	flight.lastAt, flight.lastY = now, y
	flight.count += 1
	if y > limit then
		-- Un seul paquet au-dessus : peut-être un paquet ancien arrivé après un plus récent (non fiable), ignoré
		if not flight.suspect then
			flight.suspect = true
			return true, 0
		end
		flight.suspect = false
		flight.anchorAt, flight.anchorY, flight.anchorVy = now, y, 0
		flight.baseY, flight.count = y, 0
		return false, y - limit
	end
	flight.suspect = false
	-- Deux paquets de marge : le premier paquet en l'air ou celui-ci peuvent être arrivés en désordre
	local packets = flight.count - 2
	if packets >= 2 then
		local elapsed = math.max(packets * MovementGuardRules.MIN_PACKET_INTERVAL, (packets - 1) * SEND_INTERVAL)
		local vy = maxVyAfter(y - flight.baseY, elapsed) + MovementGuardRules.REFINE_MARGIN
		if vy < flight.anchorVy - GRAVITY * (now - flight.anchorAt) then
			flight.anchorAt, flight.anchorY, flight.anchorVy = now, y, vy
		end
	end
	return true, 0
end

-- Cette méthode permet de juger un paquet déjà accepté par le seau de distance lorsqu'il arrive : noclip (sauf premier
-- paquet), puis vol. Renvoie nil, ou la violation avec son mode. En mode bloquant, la position sera refusée : c'est à
-- l'appelant de repartir de lastPos (CharacterSync.refuse appelle restart) ; en journal seul, le suivi continue depuis
-- la position appliquée.
function MovementGuardRules.judge(
	guard: Guard,
	lastPos: Vector3,
	pos: Vector3,
	now: number,
	geometry: Geometry
): Verdict?
	local fresh = guard.fresh
	guard.fresh = false
	local flight = guard.flight
	local step = pos - lastPos
	guard.speedXZ = Vector3.new(step.X, 0, step.Z).Magnitude
		/ math.max(now - flight.lastAt, MovementGuardRules.MIN_PACKET_INTERVAL)
	local noclip: Verdict? = nil
	if not fresh and MovementGuardRules.crossesWall(lastPos, pos, geometry.isBlocked) then
		noclip = {
			rule = "noclip",
			enforce = MovementGuardRules.ENFORCE_NOCLIP,
			detail = string.format("noclip : traversée d'une paroi sur %.1f studs", step.Magnitude),
		}
		if MovementGuardRules.ENFORCE_NOCLIP then
			return noclip
		end
	end
	local supported, launchVy = geometry.support(lastPos, pos)
	-- Vitesse imposée retenue jusqu'au décollage suivant, oubliée dès un paquet porté sans boost (boost déjà dépassé)
	if launchVy > 0 then
		flight.launchVy = math.max(flight.launchVy, launchVy)
	elseif supported then
		flight.launchVy = 0
	end
	local honest, excess = MovementGuardRules.observe(flight, now, pos.Y, supported or launchVy > 0)
	-- Journal seul : un paquet n'est signalé qu'une fois, le noclip d'abord ; le vol a quand même suivi la position
	if noclip or honest then
		return noclip
	end
	return {
		rule = "flight",
		enforce = MovementGuardRules.ENFORCE_FLIGHT,
		detail = string.format("vol : %.1f studs au-dessus de la trajectoire balistique", excess),
	}
end

-- Cette méthode permet de délimiter la zone où un joueur silencieux a pu atterrir lorsque le serveur cherche un sol
-- avant de le déclarer tombé : boîte centrée sur sa dernière position, de la hauteur de mort au sommet de l'enveloppe,
-- large de ce qu'il a pu parcourir (vitesse horizontale majorée plus une course, gagnée en air strafe) depuis.
function MovementGuardRules.voidProbe(
	guard: Guard,
	lastPos: Vector3,
	now: number,
	killHeight: number
): (CFrame, Vector3)
	local flight = guard.flight
	local elapsed = math.max(0, now - flight.lastAt) + MovementGuardRules.FLIGHT_TIME_SLACK
	local reach = MovementGuardRules.VOID_PROBE_MARGIN + (guard.speedXZ + MovementConfig.RUN_SPEED) * elapsed
	local apex = flight.anchorY
		+ MovementGuardRules.ballistic(flight.anchorVy, math.max(flight.anchorVy / GRAVITY, 0))
		+ MovementGuardRules.FLIGHT_HEIGHT_TOLERANCE
	local top = math.max(apex, lastPos.Y + MovementGuardRules.FLIGHT_HEIGHT_TOLERANCE)
	local bottom = math.min(killHeight, top)
	local center = Vector3.new(lastPos.X, (top + bottom) / 2, lastPos.Z)
	return CFrame.new(center), Vector3.new(2 * reach, top - bottom, 2 * reach)
end

-- Cette méthode permet de savoir si un joueur silencieux est tombé dans le vide lorsque le serveur passe en revue les
-- personnages suivis : en l'air, sans paquet reçu depuis VOID_SILENCE, même sa plus haute position possible est sous
-- la hauteur de mort, et aucun sol dans la zone où il a pu atterrir (hasFloor, appelé en dernier : requête serveur
-- sur voidProbe).
function MovementGuardRules.fellIntoVoid(
	guard: Guard,
	now: number,
	killHeight: number?,
	hasFloor: () -> boolean
): boolean
	if type(killHeight) ~= "number" or not guard.flight.anchored then
		return false
	end
	if now - guard.heardAt < MovementGuardRules.VOID_SILENCE then
		return false
	end
	return MovementGuardRules.ceiling(guard.flight, now) < killHeight and not hasFloor()
end

return MovementGuardRules

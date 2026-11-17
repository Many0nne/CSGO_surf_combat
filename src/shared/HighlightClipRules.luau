-- Règles pures du clip de la partie (#499), sans Instance ni service (testées sous Lune,
-- tests/specs/HighlightClipRules.spec.luau). Le clip est rejoué à partir de données, sans vidéo :
-- - client du tireur : tampon circulaire de la caméra (format des démos, DemoClipRules : position, hauteur des yeux,
--   lacet cumulé et tangage en degrés de FPSCamera, touches, vitesse), préalloué, rien envoyé en continu ;
-- - serveur : tampon des positions acceptées de chaque participant (dédié, plus long que PositionHistory sans changer le
--   rembobinage, #173) et des tirs acceptés ;
-- - au figeage d'un record : fenêtre de chaque piste échantillonnée à pas fixe, caméra du tireur recalée sur
--   l'historique serveur (repli : POV reconstruit depuis la position, le cap et les tirs serveur, tangage dégradé) ;
-- - transport : séries d'entiers en écart avec la ligne précédente (même principe que DemoClipRules.encode).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MathRules = require(ReplicatedStorage.Shared.MathRules)

local HighlightClipRules = {}

HighlightClipRules.VERSION = 1
-- Durée maximale d'un clip (s), multi-kill compris : même valeur que HighlightRules.MAX_DURATION (serveur, testé).
HighlightClipRules.MAX_DURATION = 8
-- Marge (s) ajoutée à la phase de résultat quand un clip est joué : fondus d'entrée et de sortie, figurants à charger.
HighlightClipRules.CLIP_MARGIN = 1

-- Caméra du client : cadence et durée couverte. Plus long que le clip maximal : la demande du serveur part ~1 s après le
-- dernier kill et arrive avec la latence.
HighlightClipRules.CAMERA_HZ = 30
HighlightClipRules.CAMERA_SECONDS = 10
HighlightClipRules.CAMERA_CAPACITY = HighlightClipRules.CAMERA_HZ * HighlightClipRules.CAMERA_SECONDS
-- Écart minimal entre deux échantillons caméra (s) : 90 % de la période, la gigue des images ne saute pas d'échantillon.
HighlightClipRules.CAMERA_SPACING = 0.9 / HighlightClipRules.CAMERA_HZ

-- Historique serveur des participants : durée, écart minimal (celui de PositionHistory), trou au-delà duquel le
-- personnage est absent (mort, réapparition).
HighlightClipRules.TRACK_SECONDS = 10
HighlightClipRules.TRACK_SPACING = 0.03
HighlightClipRules.TRACK_CAPACITY = math.ceil(HighlightClipRules.TRACK_SECONDS / HighlightClipRules.TRACK_SPACING) + 1
HighlightClipRules.TRACK_MAX_GAP = 0.25
-- Recul d'horloge (s) toléré sans vider une piste (même règle que PositionHistory).
HighlightClipRules.MAX_CLOCK_STEP = 0.5
-- Tirs acceptés gardés par participant (AWP : un tir par 1,5 s ; couteau : 2,5 par s).
HighlightClipRules.SHOT_CAPACITY = 32

-- Cadences du clip transmis : caméra du tireur et figurants.
HighlightClipRules.POV_HZ = 30
HighlightClipRules.ACTOR_HZ = 20

-- Recalage de la caméra du client sur l'historique serveur (anti-aimbot caché) :
-- - position : écart à la piste serveur, cherché dans ± POV_LAG_WINDOW (latence), au plus POV_MAX_DRIFT studs ; une part
--   POV_MAX_DRIFT_SHARE des échantillons peut dépasser (correction réseau) ;
-- - visée : à chaque tir accepté, la caméra regarde la direction du tir à POV_MAX_AIM_ERROR degrés près (le tir part de
--   la caméra, sans dispersion : HitscanSystem), cherchée dans ± POV_AIM_WINDOW.
HighlightClipRules.POV_LAG_WINDOW = 0.3
HighlightClipRules.POV_LAG_STEP = 0.05
HighlightClipRules.POV_MAX_DRIFT = 8
HighlightClipRules.POV_MAX_DRIFT_SHARE = 0.1
HighlightClipRules.POV_MAX_AIM_ERROR = 6
HighlightClipRules.POV_AIM_WINDOW = 0.1
-- Trou maximal (s) entre deux échantillons du client pour interpoler ; au-delà, le POV serveur prend le relais.
HighlightClipRules.POV_MAX_GAP = 0.15
-- Taille maximale du tampon renvoyé par le client (octets) : 300 échantillons de ~30 caractères, avec marge.
HighlightClipRules.POV_MAX_BYTES = 16000

-- POV reconstruit (bot, client absent ou recalage refusé) : hauteur des yeux debout (FPSCamera : hauteur - 0,4), et
-- durée (s) pendant laquelle la visée d'un tir tire la caméra vers sa direction ; au-delà, tangage ramené à 0.
HighlightClipRules.DEFAULT_EYE = CameraConfig.CAM_HEIGHT_STAND - 0.4
HighlightClipRules.AIM_HOLD = 0.6

-- Échelles des séries (valeur × échelle, arrondie) :
-- - tampon caméra renvoyé par le client : t relatif (ms), x, y, z, yeux, lacet, tangage (centièmes), touches, vitesse ;
-- - caméra du clip : x, y, z, yeux, lacet, tangage ;
-- - figurant : x, y, z (centièmes de stud), cap (millièmes de rad).
HighlightClipRules.CAMERA_SCALES = table.freeze({ 1000, 100, 100, 100, 100, 100, 100, 1, 10 })
HighlightClipRules.POV_SCALES = table.freeze({ 100, 100, 100, 100, 100, 100 })
HighlightClipRules.ACTOR_SCALES = table.freeze({ 100, 100, 100, 1000 })

-- Échantillon du tampon caméra : t (horloge serveur), x, y, z, yeux, lacet, tangage, touches, vitesse.
export type CameraRow = { number }
-- Ligne d'une série : nombres, ou false (absent : personnage mort, hors historique).
export type Row = { number } | false

export type CameraRing = {
	capacity: number,
	count: number,
	head: number, -- indice du dernier échantillon écrit (0 : vide)
	t: { number },
	x: { number },
	y: { number },
	z: { number },
	eye: { number },
	yaw: { number },
	pitch: { number },
	keys: { number },
	speed: { number },
}

export type Track = {
	count: number,
	first: number,
	times: { number },
	positions: { Vector3 },
	yaws: { number },
	latestT: number,
}

-- Tir accepté : instant (horloge serveur), direction, et visé (tir à distance, direction de la caméra) ou non (coup de
-- couteau : direction de la racine, hors du recalage et de la visée reconstruite).
export type ShotRing = { count: number, head: number, times: { number }, dirs: { Vector3 }, aimed: { boolean } }
export type Shot = { t: number, dir: Vector3, aimed: boolean }

-- Clip transmis aux clients à la fin de la partie (temps relatifs au début du clip, en s).
export type Clip = {
	version: number,
	duration: number,
	killerId: number,
	killerName: string,
	weapon: string,
	tool: string?, -- Tool du tireur (ReplicatedStorage.Tools) : viewmodel et son décalage
	skinId: string?,
	degraded: boolean, -- POV reconstruit par le serveur (bot, client absent, recalage refusé)
	pov: string,
	actors: { { id: number, name: string, track: string } },
	shots: { { t: number, id: number, dir: Vector3? } }, -- dir : tir visé (rayon de la balle), nil pour le couteau
	kills: { { t: number, victimId: number, headshot: boolean, direction: Vector3? } },
}

-- ── Durées ─────────────────────────────────────────────────────────────────

-- Cette méthode permet de donner la durée de la phase de résultat (s) lorsque la manche se termine : bannière
-- (GameConfig.RESULT_DURATION), plus le clip et sa marge s'il y en a un. Seule source, serveur et client.
function HighlightClipRules.resultDuration(clipDuration: number?): number
	if not clipDuration or clipDuration <= 0 then
		return GameConfig.RESULT_DURATION
	end
	return GameConfig.RESULT_DURATION + clipDuration + HighlightClipRules.CLIP_MARGIN
end

-- Cette méthode permet de compter les échantillons d'une fenêtre [start, stop] à la cadence hz lorsqu'elle est figée.
function HighlightClipRules.rowCount(start: number, stop: number, hz: number): number
	return math.max(math.floor((stop - start) * hz + 1e-6) + 1, 1)
end

-- ── Séries d'entiers ───────────────────────────────────────────────────────

-- Cette méthode permet d'arrondir une valeur à l'entier le plus proche lorsqu'une série est écrite.
local function round(value: number): number
	return math.floor(value + 0.5)
end

-- Cette méthode permet d'écrire des lignes de nombres en texte compact lorsqu'un clip ou un tampon part sur le réseau :
-- chaque valeur × son échelle, arrondie, en écart avec la dernière ligne présente (la première en absolu) ; valeurs
-- séparées par « , », lignes par « ; », ligne absente « _ ».
function HighlightClipRules.encodeSeries(rows: { Row }, scales: { number }): string
	local parts = table.create(#rows)
	local previous = table.create(#scales, 0)
	for i, row in rows do
		if row == false then
			parts[i] = "_"
			continue
		end
		local words = table.create(#scales)
		for k, scale in scales do
			local quantized = round((row :: { number })[k] * scale)
			words[k] = string.format("%d", quantized - previous[k])
			previous[k] = quantized
		end
		parts[i] = table.concat(words, ",")
	end
	return table.concat(parts, ";")
end

-- Cette méthode permet de relire une série écrite par encodeSeries lorsqu'elle arrive ; nil et la raison si le texte
-- est illisible, a trop de lignes (maxRows) ou une ligne d'une autre largeur que `scales`.
function HighlightClipRules.decodeSeries(text: any, scales: { number }, maxRows: number): ({ Row }?, string?)
	if type(text) ~= "string" then
		return nil, "texte attendu"
	end
	local rows: { Row } = {}
	local totals = table.create(#scales, 0)
	for line in string.gmatch(text, "[^;]+") do
		if #rows >= maxRows then
			return nil, "plus de " .. maxRows .. " lignes"
		end
		if line == "_" then
			table.insert(rows, false)
			continue
		end
		local row = table.create(#scales)
		local k = 0
		for word in string.gmatch(line, "[^,]+") do
			k += 1
			local value = tonumber(word)
			if k > #scales or not value or value ~= math.floor(value) or math.abs(value) > 1e12 then
				return nil, "ligne " .. (#rows + 1) .. " illisible"
			end
			totals[k] += value
			row[k] = totals[k] / scales[k]
		end
		if k ~= #scales then
			return nil, "ligne " .. (#rows + 1) .. " incomplète"
		end
		table.insert(rows, row)
	end
	return rows, nil
end

-- ── Tampon caméra du client ────────────────────────────────────────────────

-- Cette méthode permet de créer le tampon caméra du client lorsqu'il démarre : tableaux préalloués, aucune allocation
-- ensuite (un tableau par champ, écrit à l'index tournant).
function HighlightClipRules.newCameraRing(capacity: number?): CameraRing
	local n = capacity or HighlightClipRules.CAMERA_CAPACITY
	return {
		capacity = n,
		count = 0,
		head = 0,
		t = table.create(n, 0),
		x = table.create(n, 0),
		y = table.create(n, 0),
		z = table.create(n, 0),
		eye = table.create(n, 0),
		yaw = table.create(n, 0),
		pitch = table.create(n, 0),
		keys = table.create(n, 0),
		speed = table.create(n, 0),
	}
end

-- Cette méthode permet de savoir si un échantillon caméra est dû à l'instant t lorsque le client rend une image :
-- tampon vide, CAMERA_SPACING écoulé, ou horloge revenue en arrière (le tampon repart alors de zéro, cf. pushCamera).
function HighlightClipRules.cameraDue(ring: CameraRing, t: number): boolean
	if ring.count == 0 then
		return true
	end
	local last = ring.t[ring.head]
	return t < last or t - last >= HighlightClipRules.CAMERA_SPACING
end

-- Cette méthode permet d'écrire un échantillon caméra à l'index tournant lorsqu'il est dû (le plus ancien est écrasé
-- quand le tampon est plein) ; un recul d'horloge vide d'abord le tampon. Aucune allocation.
function HighlightClipRules.pushCamera(
	ring: CameraRing,
	t: number,
	x: number,
	y: number,
	z: number,
	eye: number,
	yaw: number,
	pitch: number,
	keys: number,
	speed: number
)
	if ring.count > 0 and t < ring.t[ring.head] then
		ring.count = 0
	end
	local i = ring.head % ring.capacity + 1
	ring.head = i
	ring.t[i], ring.x[i], ring.y[i], ring.z[i] = t, x, y, z
	ring.eye[i], ring.yaw[i], ring.pitch[i] = eye, yaw, pitch
	ring.keys[i], ring.speed[i] = keys, speed
	if ring.count < ring.capacity then
		ring.count += 1
	end
end

-- Cette méthode permet d'extraire du tampon, dans l'ordre, les échantillons qui couvrent [start, stop] (plus un de part et
-- d'autre pour encadrer les bords) lorsque le serveur demande la caméra ; temps relatifs à `start`. Seule allocation du
-- tampon, à la demande.
function HighlightClipRules.cameraRows(ring: CameraRing, start: number, stop: number): { CameraRow }
	local rows: { CameraRow } = {}
	local n, cap = ring.count, ring.capacity
	local oldest = (ring.head - n) % cap
	local previous: number? = nil
	for k = 1, n do
		local i = (oldest + k - 1) % cap + 1
		local t = ring.t[i]
		if t < start then
			previous = i
			continue
		end
		if previous then
			local p = previous :: number
			table.insert(rows, {
				ring.t[p] - start,
				ring.x[p],
				ring.y[p],
				ring.z[p],
				ring.eye[p],
				ring.yaw[p],
				ring.pitch[p],
				ring.keys[p],
				ring.speed[p],
			})
			previous = nil
		end
		table.insert(rows, {
			t - start,
			ring.x[i],
			ring.y[i],
			ring.z[i],
			ring.eye[i],
			ring.yaw[i],
			ring.pitch[i],
			ring.keys[i],
			ring.speed[i],
		})
		if t > stop then
			break
		end
	end
	return rows
end

-- ── Historique serveur ─────────────────────────────────────────────────────

-- Cette méthode permet de créer la piste vide d'un participant lorsque sa première position acceptée arrive.
function HighlightClipRules.newTrack(): Track
	local n = HighlightClipRules.TRACK_CAPACITY
	return {
		count = 0,
		first = 1,
		times = table.create(n, 0),
		positions = table.create(n, Vector3.zero),
		yaws = table.create(n, 0),
		latestT = -math.huge,
	}
end

-- Cette méthode permet de lire l'indice du k-ième relevé (1 = plus ancien) lorsqu'on parcourt une piste circulaire.
local function slot(track: Track, k: number): number
	return (track.first - 1 + k - 1) % HighlightClipRules.TRACK_CAPACITY + 1
end

-- Cette méthode permet d'ajouter une position acceptée (horloge serveur, cap en rad) à la piste d'un participant
-- lorsqu'elle est posée : retenue si TRACK_SPACING est passé depuis la précédente (le plus ancien relevé est écrasé
-- quand la piste est pleine). Valeurs non finies refusées ; un grand recul d'horloge repart d'une piste vide.
function HighlightClipRules.recordTrack(track: Track, t: number, pos: Vector3, yaw: number): boolean
	if not MathRules.isFinite(t) or not MathRules.isFinite(pos.Magnitude) or not MathRules.isFinite(yaw) then
		return false
	end
	if t < track.latestT then
		if track.latestT - t < HighlightClipRules.MAX_CLOCK_STEP then
			return false
		end
		track.count = 0
		track.first = 1
	elseif track.count > 0 and t - track.latestT < HighlightClipRules.TRACK_SPACING then
		return false
	end
	track.latestT = t
	local n = track.count
	local i
	if n < HighlightClipRules.TRACK_CAPACITY then
		track.count = n + 1
		i = slot(track, n + 1)
	else
		i = track.first
		track.first = i % HighlightClipRules.TRACK_CAPACITY + 1
	end
	track.times[i] = t
	track.positions[i] = pos
	track.yaws[i] = yaw
	return true
end

-- Cette méthode permet de lire la position et le cap d'un participant à l'instant t lorsque le clip est figé :
-- interpolés entre les deux relevés qui encadrent t ; nil hors de la piste (au-delà de TRACK_MAX_GAP de ses bords) ou
-- dans un trou de plus de TRACK_MAX_GAP (mort, réapparition).
function HighlightClipRules.trackAt(track: Track, t: number): (Vector3?, number?)
	local n = track.count
	if n == 0 or t ~= t then
		return nil, nil
	end
	local gap = HighlightClipRules.TRACK_MAX_GAP
	local times = track.times
	local oldest, newest = slot(track, 1), slot(track, n)
	if t < times[oldest] then
		return if times[oldest] - t <= gap then track.positions[oldest] else nil,
			if times[oldest] - t <= gap then track.yaws[oldest] else nil
	end
	if t >= times[newest] then
		return if t - times[newest] <= gap then track.positions[newest] else nil,
			if t - times[newest] <= gap then track.yaws[newest] else nil
	end
	-- Recherche dichotomique du dernier relevé <= t
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[slot(track, mid)] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = slot(track, lo), slot(track, hi)
	local ta, tb = times[a], times[b]
	if tb - ta > gap then
		return nil, nil
	end
	local alpha = if tb > ta then (t - ta) / (tb - ta) else 0
	local ya = track.yaws[a]
	return track.positions[a]:Lerp(track.positions[b], alpha), ya + MathRules.angleDelta(ya, track.yaws[b]) * alpha
end

-- Cette méthode permet d'échantillonner la piste d'un participant à pas fixe sur la fenêtre du clip lorsqu'il est figé :
-- lignes { x, y, z, cap } ou false (absent), et si au moins une ligne est présente.
function HighlightClipRules.trackRows(track: Track, start: number, count: number, hz: number): ({ Row }, boolean)
	local rows: { Row } = table.create(count)
	local any = false
	for i = 1, count do
		local pos, yaw = HighlightClipRules.trackAt(track, start + (i - 1) / hz)
		if pos and yaw then
			rows[i] = { pos.X, pos.Y, pos.Z, yaw }
			any = true
		else
			rows[i] = false
		end
	end
	return rows, any
end

-- ── Tirs acceptés ──────────────────────────────────────────────────────────

-- Cette méthode permet de créer le tampon des tirs d'un participant lorsque son premier tir accepté arrive.
function HighlightClipRules.newShotRing(): ShotRing
	local n = HighlightClipRules.SHOT_CAPACITY
	return {
		count = 0,
		head = 0,
		times = table.create(n, 0),
		dirs = table.create(n, Vector3.zero),
		aimed = table.create(n, true),
	}
end

-- Cette méthode permet de retenir un tir accepté (instant, direction ; `aimed` faux pour un coup de couteau) lorsqu'il
-- est relayé ; le plus ancien est écrasé.
function HighlightClipRules.pushShot(ring: ShotRing, t: number, dir: Vector3, aimed: boolean?)
	local i = ring.head % HighlightClipRules.SHOT_CAPACITY + 1
	ring.head = i
	ring.times[i] = t
	ring.dirs[i] = dir
	ring.aimed[i] = aimed ~= false
	ring.count = math.min(ring.count + 1, HighlightClipRules.SHOT_CAPACITY)
end

-- Cette méthode permet de lister, dans l'ordre, les tirs tombés dans [start, stop] lorsque le clip est figé.
function HighlightClipRules.shotsIn(ring: ShotRing, start: number, stop: number): { Shot }
	local shots: { Shot } = {}
	local cap = HighlightClipRules.SHOT_CAPACITY
	local oldest = (ring.head - ring.count) % cap
	for k = 1, ring.count do
		local i = (oldest + k - 1) % cap + 1
		local t = ring.times[i]
		if t >= start and t <= stop then
			table.insert(shots, { t = t, dir = ring.dirs[i], aimed = ring.aimed[i] })
		end
	end
	return shots
end

-- ── Caméra : angles et recalage ────────────────────────────────────────────

-- Cette méthode permet de donner la direction regardée par une caméra (lacet et tangage en degrés, ceux de FPSCamera)
-- lorsqu'on la compare à un tir.
function HighlightClipRules.lookOf(yaw: number, pitch: number): Vector3
	local y, p = math.rad(yaw), math.rad(pitch)
	return Vector3.new(math.sin(y) * math.cos(p), math.sin(p), -math.cos(y) * math.cos(p))
end

-- Cette méthode permet de convertir une direction en lacet et tangage de caméra (degrés, convention FPSCamera)
-- lorsqu'un POV est reconstruit à partir des tirs.
function HighlightClipRules.anglesOf(dir: Vector3): (number, number)
	local unit = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.new(0, 0, -1)
	return math.deg(math.atan2(unit.X, -unit.Z)), math.deg(math.asin(math.clamp(unit.Y, -1, 1)))
end

-- Cette méthode permet de convertir le cap serveur d'une racine (rad, CharacterSyncRules.yawOf) en lacet de caméra
-- (degrés, FPSCamera tourne la racine de -lacet) lorsqu'un POV est reconstruit.
function HighlightClipRules.cameraYawOf(rootYaw: number): number
	return -math.deg(rootYaw)
end

-- Cette méthode permet d'interpoler les échantillons du client à l'instant t (relatif) lorsqu'on les recale ou les
-- rééchantillonne ; `cursor` (indice de départ) avance avec t croissant. Renvoie la ligne interpolée (t, x, y, z, yeux,
-- lacet, tangage) ou nil si t n'est pas encadré à POV_MAX_GAP près, puis le curseur.
local function clientAt(rows: { CameraRow }, t: number, cursor: number): ({ number }?, number)
	local n = #rows
	local i = math.max(cursor, 1)
	while i < n and rows[i + 1][1] <= t do
		i += 1
	end
	local a, b = rows[i], rows[i + 1]
	if not a or a[1] > t then
		return nil, i
	end
	if not b then
		return if t - a[1] <= 1e-6 then a else nil, i
	end
	if b[1] - a[1] > HighlightClipRules.POV_MAX_GAP then
		return nil, i
	end
	local alpha = if b[1] > a[1] then (t - a[1]) / (b[1] - a[1]) else 0
	local out = table.create(7)
	for k = 1, 7 do
		out[k] = a[k] + (b[k] - a[k]) * alpha
	end
	return out, i
end

-- Cette méthode permet de vérifier que la caméra renvoyée par le client correspond à ce que le serveur a vu lorsqu'un
-- record est figé : positions proches de la piste serveur (latence tolérée), et caméra tournée vers chaque tir accepté.
-- `rows` : temps relatifs à `start` ; `serverAt(t)` : position serveur à l'instant absolu t (nil hors piste). Renvoie
-- false et la raison au premier écart (rows triés et finis, vérifiés au décodage).
function HighlightClipRules.checkPov(
	rows: { CameraRow },
	start: number,
	serverAt: (number) -> Vector3?,
	shots: { Shot }
): (boolean, string?)
	if #rows < 2 then
		return false, "caméra vide"
	end
	for i = 2, #rows do
		if rows[i][1] <= rows[i - 1][1] then
			return false, "temps non croissants"
		end
	end
	local measured, drifting = 0, 0
	local steps = math.floor(HighlightClipRules.POV_LAG_WINDOW / HighlightClipRules.POV_LAG_STEP + 0.5)
	for _, row in rows do
		local t = start + row[1]
		local here = Vector3.new(row[2], row[3], row[4])
		local best = math.huge
		for k = -steps, steps do
			local pos = serverAt(t + k * HighlightClipRules.POV_LAG_STEP)
			if pos then
				best = math.min(best, (pos - here).Magnitude)
			end
		end
		if best < math.huge then
			measured += 1
			if best > HighlightClipRules.POV_MAX_DRIFT then
				drifting += 1
			end
		end
	end
	if measured == 0 then
		return false, "aucune position serveur en regard"
	end
	if drifting > measured * HighlightClipRules.POV_MAX_DRIFT_SHARE then
		return false, string.format("position : %d échantillons sur %d trop loin du serveur", drifting, measured)
	end
	for _, shot in shots do
		if not shot.aimed then
			continue
		end
		local rel = shot.t - start
		local bestAngle = math.huge
		local window = HighlightClipRules.POV_AIM_WINDOW
		for k = -2, 2 do
			local sample = clientAt(rows, rel + k * window / 2, 1)
			if sample then
				local look = HighlightClipRules.lookOf(sample[6], sample[7])
				local dot = math.clamp(look:Dot(shot.dir.Unit), -1, 1)
				bestAngle = math.min(bestAngle, math.deg(math.acos(dot)))
			end
		end
		if bestAngle == math.huge then
			return false, string.format("tir à %.2f s hors de la caméra", rel)
		end
		if bestAngle > HighlightClipRules.POV_MAX_AIM_ERROR then
			return false, string.format("visée à %.1f° du tir à %.2f s", bestAngle, rel)
		end
	end
	return true, nil
end

-- Cette méthode permet de construire la caméra du clip à pas fixe (POV_HZ, `count` lignes depuis `start`) lorsqu'un
-- record est figé : échantillons du client interpolés là où ils sont fiables (`clientRows`, temps relatifs à `start`,
-- nil si refusés ou absents), sinon POV reconstruit depuis la piste serveur (`serverAt(t)` : position et cap racine)
-- et les tirs : visée tirée vers chaque tir pendant AIM_HOLD, tangage ramené à 0 ailleurs (tangage dégradé). Lacets
-- déroulés d'une ligne à l'autre (pas de saut de 360°). Lignes { x, y, z, yeux, lacet, tangage } ou false.
function HighlightClipRules.buildPov(
	start: number,
	count: number,
	clientRows: { CameraRow }?,
	serverAt: (number) -> (Vector3?, number?),
	shots: { Shot }
): { Row }
	local rows: { Row } = table.create(count)
	local previousYaw: number? = nil
	local cursor = 1
	local hold = HighlightClipRules.AIM_HOLD
	for i = 1, count do
		local rel = (i - 1) / HighlightClipRules.POV_HZ
		local sample = nil
		if clientRows then
			sample, cursor = clientAt(clientRows, rel, cursor)
		end
		local x, y, z, eye, yaw, pitch
		if sample then
			x, y, z, eye, yaw, pitch = sample[2], sample[3], sample[4], sample[5], sample[6], sample[7]
		else
			local pos, rootYaw = serverAt(start + rel)
			if not pos or not rootYaw then
				rows[i] = false
				continue
			end
			x, y, z, eye = pos.X, pos.Y, pos.Z, HighlightClipRules.DEFAULT_EYE
			yaw = HighlightClipRules.cameraYawOf(rootYaw)
			pitch = 0
			-- Tir le plus proche dans AIM_HOLD : visée tirée vers lui, d'autant plus qu'il est proche
			local bestWeight, shotYaw, shotPitch = 0, 0, 0
			for _, shot in shots do
				local weight = 1 - math.abs(shot.t - (start + rel)) / hold
				if shot.aimed and weight > bestWeight then
					bestWeight = weight
					shotYaw, shotPitch = HighlightClipRules.anglesOf(shot.dir)
				end
			end
			if bestWeight > 0 then
				local eased = math.min(bestWeight * 2, 1)
				yaw += MathRules.angleDeltaDeg(yaw, shotYaw) * eased
				pitch = shotPitch * eased
			end
		end
		if previousYaw then
			yaw = previousYaw + MathRules.angleDeltaDeg(previousYaw, yaw)
		end
		previousYaw = yaw
		rows[i] = { x, y, z, eye, yaw, pitch }
	end
	return rows
end

-- ── Lecture ────────────────────────────────────────────────────────────────

-- Cette méthode permet d'interpoler une série à pas fixe à l'instant t (s depuis le début) lorsque le client rejoue le
-- clip ; écrit la ligne dans `out` (aucune allocation) et renvoie true, ou false si t tombe sur une ligne absente.
-- `angleIndex` : colonne d'un cap en rad, interpolée par le plus court chemin.
function HighlightClipRules.sampleRows(
	rows: { Row },
	hz: number,
	t: number,
	out: { number },
	angleIndex: number?
): boolean
	local n = #rows
	if n == 0 then
		return false
	end
	local position = math.clamp(t * hz, 0, n - 1)
	local i = math.min(math.floor(position) + 1, n)
	local alpha = position - (i - 1)
	local a, b = rows[i], rows[math.min(i + 1, n)]
	if a == false and b == false then
		return false
	end
	if a == false or b == false then
		local only = if a == false then b else a
		-- Bord d'une absence : la ligne présente seulement si t en est la plus proche
		if (a == false and alpha < 0.5) or (b == false and alpha >= 0.5) then
			return false
		end
		for k, value in only :: { number } do
			out[k] = value
		end
		return true
	end
	local ra, rb = a :: { number }, b :: { number }
	for k, value in ra do
		if k == angleIndex then
			out[k] = value + MathRules.angleDelta(value, rb[k]) * alpha
		else
			out[k] = value + (rb[k] - value) * alpha
		end
	end
	return true
end

-- Cette méthode permet de vérifier la forme d'un clip reçu lorsque la fin de partie arrive (champ `clip` de RoundResult) ;
-- nil s'il est absent ou abîmé (le client passe alors directement à la suite).
function HighlightClipRules.readClip(data: any): Clip?
	if type(data) ~= "table" or data.version ~= HighlightClipRules.VERSION then
		return nil
	end
	local duration = data.duration
	if
		not MathRules.isFinite(duration)
		or duration <= 0
		or duration > HighlightClipRules.MAX_DURATION + 1
		or type(data.pov) ~= "string"
		or type(data.weapon) ~= "string"
		or type(data.killerName) ~= "string"
		or type(data.actors) ~= "table"
		or type(data.shots) ~= "table"
		or type(data.kills) ~= "table"
	then
		return nil
	end
	return data :: Clip
end

return HighlightClipRules

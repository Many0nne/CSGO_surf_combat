-- Règles pures des démos rejouées de l'écran Apprendre (#285), sans Instance ni service : format texte d'un clip
-- (encodage, décodage), état à un instant t (interpolation entre échantillons, touches, rotation de la souris), bouclage
-- et fondu au point de bouclage, choix des pièces de la map autour de la trajectoire.
-- Un clip est une suite d'échantillons pris à pas fixe (`hz`) par l'enregistreur de Studio (debug/ClipRecorder) : position
-- de la racine, hauteur des yeux au-dessus d'elle, angles de la caméra (lacet cumulé, sans repli à 360°, et tangage, en
-- degrés, ceux de FPSCamera), touches de mouvement tenues, vitesse horizontale. La racine est tournée du seul lacet de la
-- caméra (MovementController) : sa rotation n'est pas enregistrée à part. La souris se lit dans la rotation du lacet
-- (degrés par seconde), indépendante de la sensibilité du joueur qui a enregistré.
-- Testées sous Lune (tests/specs/DemoClipRules.spec.luau).
local DemoClipRules = {}

DemoClipRules.VERSION = 1
DemoClipRules.HEADER = "CLIP"

-- Actions de KeyBindings enregistrées, dans l'ordre de leurs bits (1, 2, 4…)
DemoClipRules.KEY_ORDER = table.freeze({ "forward", "left", "back", "right", "jump", "crouch" })

-- Rotation de la souris (degrés par seconde) qui remplit l'indicateur ; lissée sur ± TURN_WINDOW échantillons
DemoClipRules.TURN_FULL = 400
DemoClipRules.TURN_WINDOW = 2

export type Sample = {
	x: number,
	y: number,
	z: number,
	eye: number, -- hauteur de la caméra au-dessus de la racine (studs)
	yaw: number,
	pitch: number,
	keys: number, -- masque des actions de KEY_ORDER
	speed: number, -- vitesse horizontale (studs/s)
}

export type Clip = {
	version: number,
	hz: number,
	map: string,
	samples: { Sample },
}

-- État rejoué à un instant : échantillon interpolé, plus la rotation de la souris (degrés par seconde, positive à droite)
export type State = Sample & { turn: number }

-- Point lu par composantes : un Vector3 en jeu, une table sous Lune
type Vec = Vector3 | { X: number, Y: number, Z: number }

-- Cette méthode permet de composer le masque des touches tenues lorsque l'enregistreur prend un échantillon ; `held`
-- donne, par action de KEY_ORDER, si l'une de ses touches est enfoncée.
function DemoClipRules.keysMask(held: { [string]: boolean }): number
	local mask = 0
	for i, action in DemoClipRules.KEY_ORDER do
		if held[action] then
			mask += 2 ^ (i - 1)
		end
	end
	return mask
end

-- Cette méthode permet de savoir si une action est tenue dans un masque de touches lorsque le lecteur peint les touches.
function DemoClipRules.isHeld(mask: number, action: string): boolean
	for i, name in DemoClipRules.KEY_ORDER do
		if name == action then
			return math.floor(mask / 2 ^ (i - 1)) % 2 == 1
		end
	end
	return false
end

-- Champs suivis d'un échantillon à l'autre : écrits en entiers (valeur x échelle), en écart avec l'échantillon précédent
-- (le premier en valeur absolue). Les écarts sont pris entre valeurs déjà arrondies : aucune dérive à la relecture.
-- `keys` (masque) et `speed` (x 10) sont écrits en valeur absolue.
local DELTA_FIELDS = { "x", "y", "z", "eye", "yaw", "pitch" }
local DELTA_SCALE = 100 -- centièmes de stud ou de degré
local SPEED_SCALE = 10

-- Cette méthode permet d'arrondir une valeur à l'entier le plus proche lorsqu'un clip est écrit.
local function round(value: number): number
	return math.floor(value + 0.5)
end

-- Cette méthode permet d'écrire un clip en texte compact (une ligne d'en-tête, puis une ligne d'entiers par échantillon)
-- lorsque l'enregistreur termine une prise ; ce texte est celui des modules de données (ui/DemoClips).
function DemoClipRules.encode(clip: Clip): string
	local lines = { string.format("%s %d %d %s", DemoClipRules.HEADER, DemoClipRules.VERSION, clip.hz, clip.map) }
	local previous = { 0, 0, 0, 0, 0, 0 }
	for _, s in clip.samples do
		local words = {}
		for i, field in DELTA_FIELDS do
			local quantized = round((s :: any)[field] * DELTA_SCALE)
			words[i] = string.format("%d", quantized - previous[i])
			previous[i] = quantized
		end
		table.insert(words, string.format("%d", s.keys))
		table.insert(words, string.format("%d", round(s.speed * SPEED_SCALE)))
		table.insert(lines, table.concat(words, " "))
	end
	return table.concat(lines, "\n")
end

-- Cette méthode permet de relire un clip écrit par `encode` lorsque le lecteur charge un module de données ; renvoie nil
-- et la raison si le texte est vide, d'une autre version ou abîmé, ou s'il a moins de deux échantillons.
function DemoClipRules.decode(text: string): (Clip?, string?)
	local header, rest = string.match(text, "^([^\n]*)\n?(.*)$")
	if not header then
		return nil, "texte vide"
	end
	local tag, version, hz, map = string.match(header, "^(%u+) (%d+) (%d+) (%S+)%s*$")
	if tag ~= DemoClipRules.HEADER then
		return nil, "en-tête absent"
	end
	if tonumber(version) ~= DemoClipRules.VERSION then
		return nil, "version " .. tostring(version) .. " inconnue"
	end
	local rate = tonumber(hz) :: number
	if rate <= 0 then
		return nil, "cadence nulle"
	end
	local samples: { Sample } = {}
	local totals = { 0, 0, 0, 0, 0, 0 }
	local lineNumber = 1
	for line in string.gmatch(rest, "[^\n]+") do
		lineNumber += 1
		local values = {}
		for word in string.gmatch(line, "%S+") do
			local value = tonumber(word)
			if not value then
				return nil, "ligne " .. lineNumber .. " illisible"
			end
			table.insert(values, value)
		end
		if #values ~= #DELTA_FIELDS + 2 then
			return nil, "ligne " .. lineNumber .. " illisible"
		end
		local sample: any = {}
		for i, field in DELTA_FIELDS do
			totals[i] += values[i]
			sample[field] = totals[i] / DELTA_SCALE
		end
		sample.keys = values[#DELTA_FIELDS + 1]
		sample.speed = values[#DELTA_FIELDS + 2] / SPEED_SCALE
		table.insert(samples, sample)
	end
	if #samples < 2 then
		return nil, "moins de deux échantillons"
	end
	return { version = DemoClipRules.VERSION, hz = rate, map = map :: string, samples = samples }, nil
end

-- Copie d'une prise dans la sortie de Studio (elle survit à l'arrêt du playtest, pas Player.DebugClips) : lignes
-- « [ClipData <nom> <prise> <i>/<n>] <morceau> », sauts de ligne et espaces du texte remplacés par LOG_BREAK et
-- LOG_SPACE : aucun blanc dans un morceau, que la sortie pourrait rogner en fin de ligne.
DemoClipRules.LOG_TAG = "ClipData"
DemoClipRules.LOG_BREAK = "/"
DemoClipRules.LOG_SPACE = ","
DemoClipRules.LOG_CHUNK = 2000

-- Cette méthode permet de découper le texte d'une prise en lignes de sortie lorsque l'enregistreur la recopie dans la
-- sortie de Studio ; `take` numérote les prises de la session pour que la dernière l'emporte au recollage.
function DemoClipRules.toLogLines(name: string, take: number, text: string): { string }
	local flat = string.gsub(string.gsub(text, "\n", DemoClipRules.LOG_BREAK), " ", DemoClipRules.LOG_SPACE)
	local count = math.max(1, math.ceil(#flat / DemoClipRules.LOG_CHUNK))
	local lines = {}
	for i = 1, count do
		local first = (i - 1) * DemoClipRules.LOG_CHUNK + 1
		local chunk = string.sub(flat, first, first + DemoClipRules.LOG_CHUNK - 1)
		table.insert(lines, string.format("[%s %s %d %d/%d] %s", DemoClipRules.LOG_TAG, name, take, i, count, chunk))
	end
	return lines
end

-- Cette méthode permet de recoller la dernière prise complète d'un clip à partir d'une copie de la sortie de Studio
-- lorsque la prise n'a pas pu être lue dans le joueur (playtest arrêté) ; nil et la raison si aucune n'est complète.
function DemoClipRules.fromLog(log: string, name: string): (string?, string?)
	local takes: { [number]: { count: number, parts: { [number]: string } } } = {}
	local pattern = "%[" .. DemoClipRules.LOG_TAG .. " (%S+) (%d+) (%d+)/(%d+)%] (%S+)"
	for clipName, take, index, count, chunk in string.gmatch(log, pattern) do
		if clipName == name then
			local id = tonumber(take) :: number
			local entry = takes[id] or { count = tonumber(count) :: number, parts = {} }
			takes[id] = entry
			entry.parts[tonumber(index) :: number] = chunk
		end
	end
	local best: number? = nil
	for id, entry in takes do
		local complete = true
		for i = 1, entry.count do
			if not entry.parts[i] then
				complete = false
			end
		end
		if complete and (best == nil or id > best) then
			best = id
		end
	end
	if not best then
		return nil, if next(takes) then "aucune prise complète de " .. name else "aucune prise de " .. name
	end
	local entry = takes[best :: number]
	local flat = table.concat(entry.parts, "", 1, entry.count)
	local text = string.gsub(string.gsub(flat, DemoClipRules.LOG_BREAK, "\n"), DemoClipRules.LOG_SPACE, " ")
	return text, nil
end

-- Cette méthode permet de donner la durée d'un clip (secondes, du premier au dernier échantillon) lorsque le lecteur
-- boucle ou affiche sa longueur.
function DemoClipRules.duration(clip: Clip): number
	return (#clip.samples - 1) / clip.hz
end

-- Cette méthode permet de ramener un temps écoulé dans la durée du clip lorsque le lecteur le rejoue en boucle.
function DemoClipRules.loopTime(t: number, duration: number): number
	if duration <= 0 then
		return 0
	end
	return t % duration
end

-- Cette méthode permet de donner l'opacité du voile noir (0 : rien, 1 : noir) lorsque la lecture approche du point de
-- bouclage : fondu au noir sur `fade` secondes avant la fin, puis retour sur `fade` secondes après le début.
function DemoClipRules.loopFade(t: number, duration: number, fade: number): number
	if fade <= 0 or duration <= 2 * fade then
		return 0
	end
	if t < fade then
		return 1 - t / fade
	end
	if t > duration - fade then
		return (t - (duration - fade)) / fade
	end
	return 0
end

-- Cette méthode permet d'interpoler une valeur par une spline de Catmull-Rom (passe par les échantillons, sans cassure à
-- chacun d'eux) lorsque le lecteur rejoue un mouvement entre deux échantillons `p1` et `p2`.
local function catmullRom(p0: number, p1: number, p2: number, p3: number, alpha: number): number
	local a2, a3 = alpha * alpha, alpha * alpha * alpha
	return 0.5
		* ((2 * p1) + (-p0 + p2) * alpha + (2 * p0 - 5 * p1 + 4 * p2 - p3) * a2 + (-p0 + 3 * p1 - 3 * p2 + p3) * a3)
end

-- Cette méthode permet de mesurer la rotation de la souris (degrés par seconde) autour de l'échantillon `index` lorsque
-- le lecteur affiche l'indicateur : écart de lacet sur ± TURN_WINDOW échantillons, bornés au clip.
local function turnAround(clip: Clip, index: number): number
	local samples = clip.samples
	local first = math.max(1, index - DemoClipRules.TURN_WINDOW)
	local last = math.min(#samples, index + DemoClipRules.TURN_WINDOW)
	if last == first then
		return 0
	end
	return (samples[last].yaw - samples[first].yaw) * clip.hz / (last - first)
end

-- Cette méthode permet de donner l'état rejoué d'un clip à l'instant `t` (secondes, ramené dans le clip) lorsque le
-- lecteur rend une image : position et angles interpolés, vitesse interpolée, touches de l'échantillon en cours (sans
-- interpolation : une touche est enfoncée ou non), rotation de la souris interpolée.
function DemoClipRules.sampleAt(clip: Clip, t: number): State
	local samples = clip.samples
	local count = #samples
	local position = math.clamp(t, 0, DemoClipRules.duration(clip)) * clip.hz
	local i1 = math.min(math.floor(position) + 1, count - 1)
	local alpha = math.clamp(position - (i1 - 1), 0, 1)
	local s0 = samples[math.max(i1 - 1, 1)]
	local s1, s2 = samples[i1], samples[i1 + 1]
	local s3 = samples[math.min(i1 + 2, count)]
	-- Cette méthode permet d'interpoler un champ de l'échantillon lorsque l'état est composé.
	local function curve(field: string): number
		local a0, a1, a2, a3 = s0 :: any, s1 :: any, s2 :: any, s3 :: any
		return catmullRom(a0[field], a1[field], a2[field], a3[field], alpha)
	end
	local turn1, turn2 = turnAround(clip, i1), turnAround(clip, i1 + 1)
	return {
		x = curve("x"),
		y = curve("y"),
		z = curve("z"),
		eye = curve("eye"),
		yaw = curve("yaw"),
		pitch = curve("pitch"),
		keys = if alpha < 1 then s1.keys else s2.keys,
		speed = s1.speed + (s2.speed - s1.speed) * alpha,
		turn = turn1 + (turn2 - turn1) * alpha,
	}
end

-- Cette méthode permet de convertir la rotation de la souris en remplissage de l'indicateur (-1 : à fond à gauche, 1 :
-- à fond à droite) lorsque le lecteur l'affiche.
function DemoClipRules.turnFill(turn: number): number
	return math.clamp(turn / DemoClipRules.TURN_FULL, -1, 1)
end

-- Cette méthode permet de mélanger deux échantillons lorsque l'enregistreur place un échantillon à pas fixe entre deux
-- images rendues : position, angles et vitesse interpolés, touches de l'image la plus proche.
function DemoClipRules.lerpSample(a: Sample, b: Sample, alpha: number): Sample
	-- Cette méthode permet d'interpoler un nombre lorsque deux échantillons sont mélangés.
	local function mix(x: number, y: number): number
		return x + (y - x) * alpha
	end
	return {
		x = mix(a.x, b.x),
		y = mix(a.y, b.y),
		z = mix(a.z, b.z),
		eye = mix(a.eye, b.eye),
		yaw = mix(a.yaw, b.yaw),
		pitch = mix(a.pitch, b.pitch),
		keys = if alpha < 0.5 then a.keys else b.keys,
		speed = mix(a.speed, b.speed),
	}
end

-- Cette méthode permet de relever un point de passage tous les `every` échantillons (plus le dernier) lorsque le lecteur
-- choisit les pièces de la map à copier autour des trajectoires.
function DemoClipRules.pathPoints(clip: Clip, every: number): { { X: number, Y: number, Z: number } }
	local points = {}
	local samples = clip.samples
	for i = 1, #samples, math.max(1, every) do
		local s = samples[i]
		table.insert(points, { X = s.x, Y = s.y + s.eye, Z = s.z })
	end
	local last = samples[#samples]
	table.insert(points, { X = last.x, Y = last.y + last.eye, Z = last.z })
	return points
end

-- Cette méthode permet de décider si une pièce de la map (sphère englobante `center`, `radius`) est copiée dans le
-- lecteur lorsqu'il se prépare : à moins de `maxDistance` d'un point de passage.
function DemoClipRules.nearPath(center: Vec, radius: number, points: { Vec }, maxDistance: number): boolean
	local reach = maxDistance + radius
	local reach2 = reach * reach
	for _, p in points do
		local dx, dy, dz = center.X - p.X, center.Y - p.Y, center.Z - p.Z
		if dx * dx + dy * dy + dz * dz <= reach2 then
			return true
		end
	end
	return false
end

return DemoClipRules

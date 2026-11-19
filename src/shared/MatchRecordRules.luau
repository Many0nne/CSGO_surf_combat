-- Règles pures de l'enregistreur de partie (#582), sans Instance ni service (testées sous Lune,
-- tests/specs/MatchRecordRules.spec.luau). Une partie jouée dans le jeu publié est notée en données, puis reconstruite
-- dans Studio pour en filmer des rushes (docs/promo.md, « Enregistreur de partie ») :
-- - serveur (MatchRecorder) : position et cap de chaque participant à ACTOR_HZ, tirs, armes et skins, tenues, actions
--   de l'arme 3P (tir, recharge, sortie), kills et morts ; un morceau par CHUNK_SECONDS, envoyé au client qui enregistre ;
-- - client qui enregistre (debug/MatchRecorder) : sa caméra à POV_HZ (position, yeux, lacet, tangage, champ de vision,
--   lunette) et ses inspections, ajoutées au morceau, puis recopiées dans la console (journal Roblox) en lignes
--   `[MatchRec …]` ;
-- - outil tools/matchrec/extract.luau : recolle les morceaux d'un journal dans recordings/<Nom>/ ; rejeu dans Studio
--   (debug/MatchReplay) : morceaux fusionnés en une partie (`newMatch`, `addChunk`, `finish`), lue à l'instant voulu.
-- Temps : horloge serveur (GetServerTimeNow) des deux côtés ; dans un morceau, relatifs à son début `t0` ; dans une
-- partie fusionnée, relatifs au début du premier morceau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HighlightClipRules = require(ReplicatedStorage.Shared.HighlightClipRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)

local MatchRecordRules = {}

MatchRecordRules.VERSION = 1
-- Cadences : participants (serveur) et caméra du joueur qui enregistre (client)
MatchRecordRules.ACTOR_HZ = 20
MatchRecordRules.POV_HZ = 30
-- Écart minimal entre deux relevés (s) : 90 % de la période, la gigue des images ne saute pas de relevé
MatchRecordRules.ACTOR_SPACING = 0.9 / MatchRecordRules.ACTOR_HZ
MatchRecordRules.POV_SPACING = 0.9 / MatchRecordRules.POV_HZ
-- Durée d'un morceau (s) et durée maximale d'un enregistrement (s), au-delà il s'arrête de lui-même
MatchRecordRules.CHUNK_SECONDS = 5
MatchRecordRules.MAX_SECONDS = 20 * 60
-- Trou (s) entre deux relevés au-delà duquel le personnage est absent (mort, réapparition, hors partie)
MatchRecordRules.MAX_GAP = 0.3
-- Transport dans la console : étiquette, longueur du texte par ligne
MatchRecordRules.LOG_TAG = "MatchRec"
MatchRecordRules.LOG_CHUNK = 800

-- Échelles des séries (valeur × échelle, arrondie, HighlightClipRules.encodeSeries) :
-- - participant : t relatif au morceau (ms), x, y, z (centièmes de stud), cap (millièmes de rad) ;
-- - caméra : t (ms), x, y, z, yeux (centièmes), lacet, tangage (centièmes de degré), champ de vision (dixièmes de
--   degré), drapeaux (FLAG_*).
MatchRecordRules.ACTOR_SCALES = table.freeze({ 1000, 100, 100, 100, 1000 })
MatchRecordRules.POV_SCALES = table.freeze({ 1000, 100, 100, 100, 100, 100, 100, 10, 1 })
-- Drapeaux de la caméra : lunette mise (viewmodel caché, ScopeOverlay)
MatchRecordRules.FLAG_SCOPED = 1
-- Lignes au plus par série d'un morceau (marge pour la gigue)
MatchRecordRules.MAX_ROWS = 2 * MatchRecordRules.POV_HZ * MatchRecordRules.CHUNK_SECONDS

-- Types d'évènements d'un morceau
MatchRecordRules.Event = table.freeze({
	SHOT = "shot", -- id ; dx, dy, dz : direction d'un tir visé (absente pour un coup de couteau)
	EQUIP = "equip", -- id ; tool, skin : arme sortie (absente : mains vides)
	KILL = "kill", -- id du tueur, victim, w (arme), hs (tête), dx, dy, dz (du tueur vers la victime)
	DEATH = "death", -- id
	OUTFIT = "outfit", -- id ; o : tenue (#521, absente : d'origine)
	ACTION = "act", -- id ; a : action de l'arme 3P (Shoot, Reload, Equip)
	INSPECT = "inspect", -- id (joueur qui enregistre, client)
})

local KNOWN_EVENTS: { [string]: boolean } = {}
for _, kind in MatchRecordRules.Event do
	KNOWN_EVENTS[kind] = true
end

export type Event = {
	t: number,
	k: string,
	id: number,
	tool: string?,
	skin: string?,
	victim: number?,
	w: string?,
	hs: boolean?,
	dx: number?,
	dy: number?,
	dz: number?,
	o: string?,
	a: string?,
}

-- Morceau tel qu'il circule (JSON) : série et évènements relatifs à t0
export type Chunk = {
	v: number,
	rec: string,
	seq: number,
	t0: number,
	t1: number,
	last: boolean?,
	meta: { [string]: any }?,
	actors: { { id: number, name: string, bot: boolean, track: string } },
	events: { Event },
	pov: string?,
}

-- Piste lue : temps (s depuis le début de la partie) et colonnes de valeurs (une table par colonne)
export type Track = { t: { number }, cols: { { number } } }
export type Actor = { id: number, name: string, bot: boolean, track: Track }

export type Match = {
	rec: string?,
	meta: { [string]: any },
	start: number?, -- t0 du premier morceau (horloge serveur)
	duration: number,
	me: number?, -- id du joueur qui enregistre
	actors: { [number]: Actor },
	pov: Track,
	events: { Event },
	seqs: { [number]: boolean },
	missing: { number },
}

-- ── Valeurs ────────────────────────────────────────────────────────────────

-- Cette méthode permet d'arrondir un nombre au millième lorsqu'il part dans un morceau (JSON plus court).
function MatchRecordRules.milli(value: number): number
	return math.floor(value * 1000 + 0.5) / 1000
end

-- Cette méthode permet de lire une direction rangée dans un évènement (dx, dy, dz) lorsqu'elle est rejouée ; nil si
-- elle est absente ou nulle.
function MatchRecordRules.directionOf(event: Event): Vector3?
	if not (MathRules.isFinite(event.dx) and MathRules.isFinite(event.dy) and MathRules.isFinite(event.dz)) then
		return nil
	end
	local dir = Vector3.new(event.dx :: number, event.dy :: number, event.dz :: number)
	return if dir.Magnitude > 1e-6 then dir.Unit else nil
end

-- Cette méthode permet de ranger une direction dans un évènement (arrondie au millième) lorsqu'il est noté ; rien si
-- elle est absente, nulle ou non finie.
function MatchRecordRules.setDirection(event: Event, dir: Vector3?)
	if not dir or not MathRules.isFiniteVector3(dir) or dir.Magnitude < 1e-6 then
		return
	end
	local unit = dir.Unit
	event.dx, event.dy, event.dz =
		MatchRecordRules.milli(unit.X), MatchRecordRules.milli(unit.Y), MatchRecordRules.milli(unit.Z)
end

-- ── Transport dans la console ──────────────────────────────────────────────

-- Cette méthode permet de rendre un texte sans espace ni retour à la ligne lorsqu'il part dans la console (une ligne
-- du journal se lit jusqu'au premier blanc) : « % », espace, tabulation et retours encodés en %XX.
function MatchRecordRules.escape(text: string): string
	return (string.gsub(text, "[%%%s]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- Cette méthode permet de relire un texte écrit par escape lorsqu'il est recollé.
function MatchRecordRules.unescape(text: string): string
	return (string.gsub(text, "%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16) :: number)
	end))
end

-- Cette méthode permet de découper un morceau en lignes de console lorsque le client qui enregistre le reçoit :
-- « [MatchRec <enregistrement> <morceau> i/n] texte ».
function MatchRecordRules.toLogLines(rec: string, seq: number, text: string): { string }
	local flat = MatchRecordRules.escape(text)
	local size = MatchRecordRules.LOG_CHUNK
	local count = math.max(1, math.ceil(#flat / size))
	local lines = table.create(count)
	for i = 1, count do
		local first = (i - 1) * size + 1
		lines[i] = string.format(
			"[%s %s %d %d/%d] %s",
			MatchRecordRules.LOG_TAG,
			rec,
			seq,
			i,
			count,
			string.sub(flat, first, first + size - 1)
		)
	end
	return lines
end

-- Cette méthode permet de recoller les morceaux de chaque enregistrement trouvés dans un journal (ou une copie de la
-- console) lorsque l'outil d'extraction le lit : par enregistrement, le texte de chaque morceau complet ; une ligne
-- vue deux fois (journal relu) n'est gardée qu'une fois.
function MatchRecordRules.fromLog(log: string): { [string]: { [number]: string } }
	local parts: { [string]: { [number]: { count: number, lines: { [number]: string } } } } = {}
	local pattern = "%[" .. MatchRecordRules.LOG_TAG .. " (%S+) (%d+) (%d+)/(%d+)%] (%S+)"
	for rec, seq, index, count, text in string.gmatch(log, pattern) do
		local byRec = parts[rec] or {}
		parts[rec] = byRec
		local n = tonumber(seq) :: number
		local entry = byRec[n] or { count = tonumber(count) :: number, lines = {} }
		byRec[n] = entry
		entry.lines[tonumber(index) :: number] = text
	end
	local out: { [string]: { [number]: string } } = {}
	for rec, byRec in parts do
		local chunks: { [number]: string } = {}
		for seq, entry in byRec do
			local complete = true
			for i = 1, entry.count do
				if not entry.lines[i] then
					complete = false
					break
				end
			end
			if complete then
				chunks[seq] = MatchRecordRules.unescape(table.concat(entry.lines, "", 1, entry.count))
			end
		end
		if next(chunks) then
			out[rec] = chunks
		end
	end
	return out
end

-- ── Morceaux ───────────────────────────────────────────────────────────────

-- Cette méthode permet de vérifier la forme d'un morceau décodé (JSON) lorsqu'il est fusionné ; nil et la raison s'il
-- est abîmé ou d'une autre version. Les évènements inconnus ou abîmés sont retirés.
function MatchRecordRules.readChunk(data: any): (Chunk?, string?)
	if type(data) ~= "table" then
		return nil, "table attendue"
	end
	if data.v ~= MatchRecordRules.VERSION then
		return nil, "version " .. tostring(data.v)
	end
	if
		type(data.rec) ~= "string"
		or not MathRules.isFinite(data.seq)
		or not MathRules.isFinite(data.t0)
		or not MathRules.isFinite(data.t1)
		or data.t1 < data.t0
		or type(data.actors) ~= "table"
		or type(data.events) ~= "table"
		or (data.pov ~= nil and type(data.pov) ~= "string")
	then
		return nil, "champs manquants"
	end
	local events = {}
	for _, event in data.events do
		if
			type(event) == "table"
			and MathRules.isFinite(event.t)
			and MathRules.isFinite(event.id)
			and KNOWN_EVENTS[event.k]
		then
			table.insert(events, event)
		end
	end
	data.events = events
	local actors = {}
	for _, actor in data.actors do
		if type(actor) == "table" and MathRules.isFinite(actor.id) and type(actor.track) == "string" then
			table.insert(actors, actor)
		end
	end
	data.actors = actors
	return data :: Chunk, nil
end

-- ── Partie fusionnée ───────────────────────────────────────────────────────

-- Cette méthode permet de créer une piste vide à `width` colonnes lorsqu'un participant ou la caméra apparaît.
local function newTrack(width: number): Track
	local cols = table.create(width)
	for k = 1, width do
		cols[k] = {}
	end
	return { t = {}, cols = cols }
end

-- Cette méthode permet de créer une partie vide lorsque le rejeu ou l'outil d'extraction commence à fusionner.
function MatchRecordRules.newMatch(): Match
	return {
		rec = nil,
		meta = {},
		start = nil,
		duration = 0,
		me = nil,
		actors = {},
		pov = newTrack(#MatchRecordRules.POV_SCALES - 1),
		events = {},
		seqs = {},
		missing = {},
	}
end

-- Cette méthode permet d'ajouter à une piste les lignes d'une série d'un morceau lorsqu'il est fusionné : temps
-- ramenés au début de la partie (`offset` = t0 du morceau - début), lignes non croissantes écartées.
local function appendSeries(track: Track, text: string, scales: { number }, offset: number): boolean
	local rows = HighlightClipRules.decodeSeries(text, scales, MatchRecordRules.MAX_ROWS)
	if not rows then
		return false
	end
	local times = track.t
	for _, row in rows do
		if row == false then
			continue
		end
		local values = row :: { number }
		local t = values[1] + offset
		if #times > 0 and t <= times[#times] then
			continue
		end
		table.insert(times, t)
		for k, col in track.cols do
			table.insert(col, values[k + 1])
		end
	end
	return true
end

-- Cette méthode permet de fusionner un morceau vérifié (readChunk) dans une partie lorsqu'il est lu : pistes des
-- participants et caméra prolongées, évènements ramenés au début de la partie. Les morceaux doivent arriver dans
-- l'ordre (`finish` trie quand même les évènements) ; un morceau d'un autre enregistrement est refusé.
function MatchRecordRules.addChunk(match: Match, chunk: Chunk): (boolean, string?)
	if match.rec and chunk.rec ~= match.rec then
		return false, "autre enregistrement"
	end
	match.rec = chunk.rec
	if match.start == nil then
		match.start = chunk.t0
	end
	local offset = chunk.t0 - (match.start :: number)
	if chunk.meta then
		for key, value in chunk.meta do
			match.meta[key] = value
		end
		if MathRules.isFinite(chunk.meta.me) then
			match.me = chunk.meta.me
		end
	end
	match.seqs[chunk.seq] = true
	match.duration = math.max(match.duration, chunk.t1 - (match.start :: number))
	for _, entry in chunk.actors do
		local actor = match.actors[entry.id]
		if not actor then
			actor = {
				id = entry.id,
				name = if type(entry.name) == "string" then entry.name else "?",
				bot = entry.bot == true,
				track = newTrack(#MatchRecordRules.ACTOR_SCALES - 1),
			}
			match.actors[entry.id] = actor
		end
		appendSeries((actor :: Actor).track, entry.track, MatchRecordRules.ACTOR_SCALES, offset)
	end
	if chunk.pov then
		appendSeries(match.pov, chunk.pov, MatchRecordRules.POV_SCALES, offset)
	end
	for _, event in chunk.events do
		local copy = table.clone(event)
		copy.t = event.t + offset
		table.insert(match.events, copy)
	end
	return true, nil
end

-- Cette méthode permet de terminer la fusion lorsque tous les morceaux sont lus : évènements triés (ordre stable à
-- instant égal), morceaux manquants listés (de 1 au dernier reçu).
function MatchRecordRules.finish(match: Match): Match
	for i, event in match.events do
		(event :: any)._order = i
	end
	table.sort(match.events, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return (a :: any)._order < (b :: any)._order
	end)
	for _, event in match.events do
		(event :: any)._order = nil
	end
	local last = 0
	for seq in match.seqs do
		last = math.max(last, seq)
	end
	table.clear(match.missing)
	for seq = 1, last do
		if not match.seqs[seq] then
			table.insert(match.missing, seq)
		end
	end
	return match
end

-- ── Lecture ────────────────────────────────────────────────────────────────

-- Cette méthode permet de trouver le dernier relevé d'une piste à l'instant t ou avant lorsqu'elle est lue (0 avant le
-- premier) ; `hint` (indice de l'image précédente) évite la recherche quand t avance peu.
function MatchRecordRules.indexAt(track: Track, t: number, hint: number?): number
	local times = track.t
	local n = #times
	if n == 0 or t < times[1] then
		return 0
	end
	local h = hint or 0
	if h >= 1 and h <= n and times[h] <= t then
		-- Avance de quelques relevés au plus depuis l'image précédente
		for i = h, math.min(h + 4, n) do
			if i == n or times[i + 1] > t then
				return i
			end
		end
	end
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

-- Cette méthode permet d'interpoler une piste à l'instant t lorsqu'une image est rendue : valeurs écrites dans `out`
-- (aucune allocation), présence (false hors de la piste ou dans un trou de plus de MAX_GAP), puis l'indice trouvé (à
-- repasser en `hint`). `angleCol` : colonne d'un cap en rad, interpolée par le plus court chemin ; `stepCols` :
-- colonnes recopiées sans interpolation (drapeaux).
function MatchRecordRules.sample(
	track: Track,
	t: number,
	out: { number },
	hint: number?,
	angleCol: number?,
	stepCols: { [number]: boolean }?
): (boolean, number)
	local i = MatchRecordRules.indexAt(track, t, hint)
	local times = track.t
	local n = #times
	local gap = MatchRecordRules.MAX_GAP
	if i == 0 then
		if n == 0 or times[1] - t > gap then
			return false, 0
		end
		for k, col in track.cols do
			out[k] = col[1]
		end
		return true, 0
	end
	if i == n or times[i + 1] - times[i] > gap then
		-- Dernier relevé (ou bord d'un trou) : tenu au plus MAX_GAP
		if t - times[i] > gap then
			return false, i
		end
		for k, col in track.cols do
			out[k] = col[i]
		end
		return true, i
	end
	local ta, tb = times[i], times[i + 1]
	local alpha = if tb > ta then (t - ta) / (tb - ta) else 0
	for k, col in track.cols do
		local a, b = col[i], col[i + 1]
		if stepCols and stepCols[k] then
			out[k] = a
		elseif k == angleCol then
			out[k] = a + MathRules.angleDelta(a, b) * alpha
		else
			out[k] = a + (b - a) * alpha
		end
	end
	return true, i
end

-- Cette méthode permet de lister, dans l'ordre, les évènements d'un participant d'un type donné lorsque le rejeu
-- prépare ses changements d'arme ou de tenue.
function MatchRecordRules.eventsOf(match: Match, kind: string, id: number?): { Event }
	local out = {}
	for _, event in match.events do
		if event.k == kind and (id == nil or event.id == id) then
			table.insert(out, event)
		end
	end
	return out
end

-- Cette méthode permet de trouver le dernier évènement d'une liste triée à l'instant t ou avant lorsque le rejeu
-- démarre en cours de partie (arme et tenue déjà en place) ; nil s'il n'y en a pas.
function MatchRecordRules.lastBefore(list: { Event }, t: number): Event?
	local found: Event? = nil
	for _, event in list do
		if event.t > t then
			break
		end
		found = event
	end
	return found
end

-- Cette méthode permet de trouver le kill qui a causé la mort d'un participant (même victime, à 0,5 s près)
-- lorsque le rejeu fait tomber son corps : arme, tête et direction du ragdoll.
function MatchRecordRules.killOf(match: Match, victim: number, t: number): Event?
	local best: Event? = nil
	for _, event in match.events do
		if event.k == MatchRecordRules.Event.KILL and event.victim == victim and math.abs(event.t - t) <= 0.5 then
			if not best or math.abs(event.t - t) < math.abs(best.t - t) then
				best = event
			end
		end
	end
	return best
end

-- Cette méthode permet de résumer une partie lorsque l'outil d'extraction l'écrit ou que le rejeu démarre : durée,
-- participants, kills, tirs, caméra du joueur.
function MatchRecordRules.summary(match: Match): { [string]: any }
	local actors, kills, shots = 0, 0, 0
	for _ in match.actors do
		actors += 1
	end
	for _, event in match.events do
		if event.k == MatchRecordRules.Event.KILL then
			kills += 1
		elseif event.k == MatchRecordRules.Event.SHOT then
			shots += 1
		end
	end
	return {
		duration = match.duration,
		actors = actors,
		kills = kills,
		shots = shots,
		povRows = #match.pov.t,
		missing = #match.missing,
	}
end

return MatchRecordRules

-- PerfRouteRules.luau (shared)
-- Règles pures des parcours rejoués pour mesurer les performances en mouvement (#379, cf. docs/performance.md,
-- « Parcours rejoué ») : format texte d'une piste (entrées de chaque tick fixe du mouvement, points de contrôle),
-- découpe dans la console et recollage, coupe d'une prise, écart avec la piste et ligne de bilan du rejeu.
-- Sans service Roblox : testées sous Lune.
--
-- Format (une ligne par élément, entiers) :
--   ROUTE <version> <map> <ticks>
--   C x y z vx vy vz lacet tangage arme   point de contrôle, état au début du tick suivant (centièmes de stud,
--                                         millièmes de degré ; arme = nom du Tool tenu, « - » si aucun)
--   E arme                                changement d'arme avant le tick suivant
--   touches dlacet dtangage [tirs]        un tick : masque des touches, écarts d'angle avec le tick précédent
--   x<n>                                  la ligne de tick précédente répétée n fois de plus

local PerfRouteRules = {}

PerfRouteRules.VERSION = 1
-- Un point de contrôle par seconde de jeu (64 ticks, StepTiming) : écart mesuré et recalage au plus tard 1 s après
PerfRouteRules.CHECK_EVERY = 64
-- Écart (studs) au-delà duquel le rejeu replace le personnage sur la piste
PerfRouteRules.DRIFT_MAX = 4
-- Déplacement (studs) d'un tick au suivant au-delà duquel l'enregistreur voit une téléportation et pose un point de
-- contrôle : plus du double du plus grand pas possible (vitesse serveur max ≈ 450 studs/s, 7 studs par tick)
PerfRouteRules.TELEPORT_JUMP = 16
-- Longueur maximale d'une prise (ticks) : 5 min, environ 150 Ko de texte
PerfRouteRules.MAX_TICKS = 64 * 300

-- Masque des touches d'un tick : actions tenues, puis appuis (fronts) tombés depuis le tick précédent.
PerfRouteRules.KEYS = {
	forward = 1,
	left = 2,
	back = 4,
	right = 8,
	jump = 16,
	crouch = 32,
	walk = 64,
}
PerfRouteRules.PRESSES = {
	jump = 128,
	reload = 256,
	inspect = 512,
}

-- Découpe dans la console, comme les clips de démo (DemoClipRules) : morceaux sans blanc, que la sortie pourrait rogner.
-- 800 caractères : le journal de Studio (%LOCALAPPDATA%\Roblox\logs) coupe une ligne vers 950 caractères, en-tête
-- compris (mesuré le 2026-11-15) ; la console de Studio, elle, la garde entière.
PerfRouteRules.LOG_TAG = "PerfRoute"
PerfRouteRules.LOG_BREAK = "/"
PerfRouteRules.LOG_SPACE = ","
PerfRouteRules.LOG_CHUNK = 800

export type Check = { x: number, y: number, z: number, vx: number, vy: number, vz: number }
export type Tick = {
	keys: number,
	yaw: number, -- millièmes de degré
	pitch: number,
	fire: number, -- tirs (Tool.Activated) tombés pendant ce tick
	tool: string, -- Tool tenu, "" si aucun
	check: Check?,
}
export type Route = { version: number, map: string, ticks: { Tick } }

-- Cette méthode permet de composer le masque d'un tick lorsque l'enregistreur lit les touches tenues et les appuis
-- tombés depuis le tick précédent.
function PerfRouteRules.keysFrom(held: { [string]: boolean }, presses: { [string]: boolean }): number
	local mask = 0
	for action, bit in PerfRouteRules.KEYS do
		if held[action] then
			mask += bit
		end
	end
	for action, bit in PerfRouteRules.PRESSES do
		if presses[action] then
			mask += bit
		end
	end
	return mask
end

-- Cette méthode permet de relire les touches tenues et les appuis d'un masque lorsque le rejeu alimente les entrées.
function PerfRouteRules.split(mask: number): ({ [string]: boolean }, { [string]: boolean })
	local held, presses = {}, {}
	for action, bit in PerfRouteRules.KEYS do
		held[action] = bit32.btest(mask, bit)
	end
	for action, bit in PerfRouteRules.PRESSES do
		presses[action] = bit32.btest(mask, bit)
	end
	return held, presses
end

-- Cette méthode permet d'arrondir un angle en millièmes de degré lorsque l'enregistreur note la caméra.
function PerfRouteRules.milli(deg: number): number
	return math.round(deg * 1000)
end

-- Cette méthode permet de noter un point de contrôle (position et vitesse en centièmes de stud) lorsque l'enregistreur
-- en pose un.
function PerfRouteRules.check(x: number, y: number, z: number, vx: number, vy: number, vz: number): Check
	return {
		x = math.round(x * 100),
		y = math.round(y * 100),
		z = math.round(z * 100),
		vx = math.round(vx * 100),
		vy = math.round(vy * 100),
		vz = math.round(vz * 100),
	}
end

-- Cette méthode permet de mesurer l'écart (studs) entre une position et un point de contrôle lorsque le rejeu
-- l'atteint.
function PerfRouteRules.drift(check: Check, x: number, y: number, z: number): number
	local dx, dy, dz = x - check.x / 100, y - check.y / 100, z - check.z / 100
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Cette méthode permet d'écrire un nom d'arme sans blanc lorsqu'il entre dans une ligne de la piste (« - » : aucune).
local function toolToken(tool: string): string
	if tool == "" then
		return "-"
	end
	return (string.gsub(tool, " ", "~"))
end

-- Cette méthode permet de relire un nom d'arme écrit par toolToken lorsque la piste est décodée.
local function toolFrom(token: string): string
	if token == "-" then
		return ""
	end
	return (string.gsub(token, "~", " "))
end

-- Cette méthode permet d'écrire une piste en texte lorsque l'enregistreur s'arrête ou qu'une prise est coupée ; la
-- piste doit commencer par un point de contrôle.
function PerfRouteRules.encode(route: Route): string
	local lines = { string.format("ROUTE %d %s %d", PerfRouteRules.VERSION, route.map, #route.ticks) }
	local prevYaw, prevPitch, prevTool = 0, 0, ""
	local lastTickLine: string? = nil
	local repeats = 0
	-- Cette méthode permet d'écrire les répétitions en attente lorsque la suite de ticks identiques s'interrompt.
	local function flush()
		if repeats > 0 then
			table.insert(lines, "x" .. repeats)
			repeats = 0
		end
	end
	for _, t in route.ticks do
		local c = t.check
		if c then
			flush()
			table.insert(
				lines,
				string.format(
					"C %d %d %d %d %d %d %d %d %s",
					c.x,
					c.y,
					c.z,
					c.vx,
					c.vy,
					c.vz,
					t.yaw,
					t.pitch,
					toolToken(t.tool)
				)
			)
			prevYaw, prevPitch, prevTool = t.yaw, t.pitch, t.tool
			lastTickLine = nil
		elseif t.tool ~= prevTool then
			flush()
			table.insert(lines, "E " .. toolToken(t.tool))
			prevTool = t.tool
			lastTickLine = nil
		end
		local line = string.format("%d %d %d", t.keys, t.yaw - prevYaw, t.pitch - prevPitch)
		if t.fire > 0 then
			line ..= " " .. t.fire
		end
		prevYaw, prevPitch = t.yaw, t.pitch
		if line == lastTickLine then
			repeats += 1
		else
			flush()
			table.insert(lines, line)
			lastTickLine = line
		end
	end
	flush()
	return table.concat(lines, "\n")
end

-- Cette méthode permet de lire une piste écrite par encode lorsque le rejeu la charge ou qu'un outil la coupe ; nil et
-- la raison si le texte est illisible.
function PerfRouteRules.decode(text: string): (Route?, string?)
	local lines = {}
	for line in string.gmatch(text, "[^\n]+") do
		line = string.gsub(line, "\r", "")
		if string.find(line, "%S") then
			table.insert(lines, line)
		end
	end
	local version, map, count = string.match(lines[1] or "", "^ROUTE (%d+) (%S+) (%d+)$")
	if not version then
		return nil, "en-tête ROUTE absent"
	end
	if tonumber(version) ~= PerfRouteRules.VERSION then
		return nil, "version " .. version .. " inconnue"
	end
	local ticks: { Tick } = {}
	local yaw, pitch, tool = 0, 0, ""
	local pendingCheck: Check? = nil
	local lastLine: { keys: number, dyaw: number, dpitch: number, fire: number }? = nil
	-- Cette méthode permet d'ajouter un tick à partir d'une ligne de tick lorsque le décodage la lit ou la répète.
	local function push(entry: { keys: number, dyaw: number, dpitch: number, fire: number })
		yaw += entry.dyaw
		pitch += entry.dpitch
		table.insert(ticks, {
			keys = entry.keys,
			yaw = yaw,
			pitch = pitch,
			fire = entry.fire,
			tool = tool,
			check = pendingCheck,
		})
		pendingCheck = nil
	end
	for i = 2, #lines do
		local line = lines[i]
		local kind = string.sub(line, 1, 1)
		if kind == "C" then
			local f = {}
			for word in string.gmatch(string.sub(line, 3), "%S+") do
				table.insert(f, word)
			end
			local n: { number } = {}
			for k = 1, 8 do
				local value = tonumber(f[k])
				if not value then
					return nil, "ligne " .. i .. " : point de contrôle illisible"
				end
				n[k] = value
			end
			if #f ~= 9 then
				return nil, "ligne " .. i .. " : point de contrôle illisible"
			end
			pendingCheck = { x = n[1], y = n[2], z = n[3], vx = n[4], vy = n[5], vz = n[6] }
			yaw, pitch, tool = n[7], n[8], toolFrom(f[9])
			lastLine = nil
		elseif kind == "E" then
			local token = string.match(line, "^E (%S+)$")
			if not token then
				return nil, "ligne " .. i .. " : changement d'arme illisible"
			end
			tool = toolFrom(token)
			lastLine = nil
		elseif kind == "x" then
			local n = tonumber(string.sub(line, 2))
			if not n or not lastLine then
				return nil, "ligne " .. i .. " : répétition sans tick"
			end
			for _ = 1, n do
				push(lastLine)
			end
		else
			local k, dy, dp, fire = string.match(line, "^(%d+) (%-?%d+) (%-?%d+) ?(%d*)$")
			if not k then
				return nil, "ligne " .. i .. " : tick illisible"
			end
			local entry = {
				keys = tonumber(k) :: number,
				dyaw = tonumber(dy) :: number,
				dpitch = tonumber(dp) :: number,
				fire = tonumber(fire) or 0,
			}
			push(entry)
			-- Une répétition ajoute de nouveau les mêmes écarts d'angle (encode compare les lignes écrites)
			lastLine = entry
		end
	end
	if #ticks ~= tonumber(count) then
		return nil, string.format("%d ticks lus pour %s annoncés", #ticks, count)
	end
	if #ticks == 0 or not ticks[1].check then
		return nil, "la piste ne commence pas par un point de contrôle"
	end
	return { version = PerfRouteRules.VERSION, map = map, ticks = ticks }, nil
end

-- Cette méthode permet de donner l'index du premier point de contrôle à partir de `from` lorsque le rejeu doit
-- reprendre la piste (réapparition) ; nil s'il n'en reste plus.
function PerfRouteRules.nextCheck(route: Route, from: number): number?
	for i = math.max(1, from), #route.ticks do
		if route.ticks[i].check then
			return i
		end
	end
	return nil
end

-- Cette méthode permet de garder la partie d'une piste entre deux instants (secondes) lorsqu'une prise est coupée ;
-- le début recule au point de contrôle précédent (le rejeu part toujours d'un point de contrôle).
function PerfRouteRules.trim(route: Route, firstS: number, lastS: number): (Route?, string?)
	local first = math.max(1, math.floor(firstS * 64) + 1)
	local last = math.min(#route.ticks, math.floor(lastS * 64) + 1)
	while first > 1 and not route.ticks[first].check do
		first -= 1
	end
	if first > last then
		return nil, "rien entre " .. firstS .. " et " .. lastS .. " s"
	end
	return { version = route.version, map = route.map, ticks = table.move(route.ticks, first, last, 1, {}) }, nil
end

-- Cette méthode permet de donner la durée de jeu d'une piste (secondes) lorsqu'un bilan l'affiche.
function PerfRouteRules.duration(route: Route): number
	return #route.ticks / 64
end

-- Cette méthode permet de découper le texte d'une piste en lignes de sortie lorsque l'enregistreur la recopie dans la
-- console ; `take` numérote la prise (l'heure en ms) : la plus grande l'emporte au recollage.
function PerfRouteRules.toLogLines(name: string, take: number, text: string): { string }
	local flat = string.gsub(string.gsub(text, "\n", PerfRouteRules.LOG_BREAK), " ", PerfRouteRules.LOG_SPACE)
	local count = math.max(1, math.ceil(#flat / PerfRouteRules.LOG_CHUNK))
	local lines = {}
	for i = 1, count do
		local first = (i - 1) * PerfRouteRules.LOG_CHUNK + 1
		local chunk = string.sub(flat, first, first + PerfRouteRules.LOG_CHUNK - 1)
		table.insert(lines, string.format("[%s %s %d %d/%d] %s", PerfRouteRules.LOG_TAG, name, take, i, count, chunk))
	end
	return lines
end

-- Cette méthode permet de recoller la dernière prise complète d'une piste à partir d'une copie de la console ou d'un
-- journal Roblox lorsque l'outil d'extraction la lit ; nil et la raison si aucune n'est complète.
function PerfRouteRules.fromLog(log: string, name: string): (string?, string?)
	local takes: { [number]: { count: number, parts: { [number]: string } } } = {}
	local pattern = "%[" .. PerfRouteRules.LOG_TAG .. " (%S+) (%d+) (%d+)/(%d+)%] (%S+)"
	for routeName, take, index, count, chunk in string.gmatch(log, pattern) do
		if routeName == name then
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
	return (string.gsub(string.gsub(flat, PerfRouteRules.LOG_BREAK, "\n"), PerfRouteRules.LOG_SPACE, " ")), nil
end

export type RunStats = {
	name: string,
	status: string, -- "fini" ou la raison de l'arrêt
	ticks: number, -- ticks rejoués
	total: number, -- ticks de la piste
	fps: number,
	p99Ms: number,
	maxMs: number,
	hitches: number, -- frames de plus de HITCH_MS
	checks: number, -- points de contrôle atteints
	driftMean: number,
	driftMax: number,
	recalages: number,
	respawns: number,
	memStartMb: number,
	memEndMb: number,
}

-- Frame lente comptée dans le bilan du rejeu (ms) : trois frames à 60 FPS
PerfRouteRules.HITCH_MS = 50

-- Cette méthode permet de rédiger la ligne de bilan d'un rejeu lorsqu'il s'arrête : rythme, frames lentes, fidélité à
-- la piste (écart aux points de contrôle, recalages, réapparitions) et mémoire.
function PerfRouteRules.runLine(s: RunStats): string
	return string.format(
		"[Perf] RUN %s %s %.0f/%.0fs | FPS %.0f p99 %.1fms max %.1fms, %d frames > %dms | écart moy %.2f max %.2f studs"
			.. " sur %d contrôles, %d recalages, %d réapparitions | mém %.0f -> %.0f Mo",
		s.name,
		s.status,
		s.ticks / 64,
		s.total / 64,
		s.fps,
		s.p99Ms,
		s.maxMs,
		s.hitches,
		PerfRouteRules.HITCH_MS,
		s.driftMean,
		s.driftMax,
		s.checks,
		s.recalages,
		s.respawns,
		s.memStartMb,
		s.memEndMb
	)
end

return PerfRouteRules

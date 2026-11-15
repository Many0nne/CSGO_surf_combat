-- PerfMarkers.luau (shared)
-- Repères de coût des boucles par frame (cf. docs/performance.md). `wrap` entoure un callback d'un
-- debug.profilebegin/profileend : le MicroProfiler (Ctrl+F6) affiche alors son coût sous ce nom. Quand `timing` vaut
-- true (overlay ouvert, rejeu de parcours), il additionne aussi le temps et le nombre d'appels, relevés par `collect`
-- (remis à zéro à chaque relevé : overlay F3, sonde serveur) ou par `mark` et `since` (cumul jamais remis à zéro :
-- une mesure longue, comme le rejeu de parcours, ne prend rien aux relevés de l'overlay).

local PerfMarkers = {}

-- debug.profilebegin n'existe que dans Roblox : sous Lune (tests), les repères ne font que compter.
local profilebegin = (debug :: any).profilebegin or function(_label: string) end
local profileend = (debug :: any).profileend or function() end

PerfMarkers.timing = false

export type Totals = { [string]: { time: number, calls: number, max: number } }

-- time, calls, max : depuis le dernier `collect` ; sumTime, sumCalls : depuis le démarrage ; peak : pire appel depuis
-- le dernier `mark`
type Entry = { time: number, calls: number, max: number, sumTime: number, sumCalls: number, peak: number }

local totals: { [string]: Entry } = {}

-- Cette méthode permet de rendre le compteur d'un repère, créé au besoin, lorsqu'un callback est entouré ou qu'un
-- temps est ajouté à la main.
local function entryOf(label: string): Entry
	local entry = totals[label]
	if not entry then
		entry = { time = 0, calls = 0, max = 0, sumTime = 0, sumCalls = 0, peak = 0 }
		totals[label] = entry
	end
	return entry
end

-- Cette méthode permet d'ajouter un appel chronométré à un compteur lorsque le chronométrage est actif.
local function add(entry: Entry, spent: number)
	entry.time += spent
	entry.calls += 1
	entry.sumTime += spent
	entry.sumCalls += 1
	if spent > entry.max then
		entry.max = spent
	end
	if spent > entry.peak then
		entry.peak = spent
	end
end

-- Cette méthode permet d'entourer d'un repère nommé un callback sans valeur de retour (RenderStep, Heartbeat,
-- RenderStepped) lorsqu'on veut voir son coût dans le MicroProfiler et l'overlay.
function PerfMarkers.wrap<A...>(label: string, fn: (A...) -> ()): (A...) -> ()
	local entry = entryOf(label)
	return function(...: A...)
		profilebegin(label)
		if PerfMarkers.timing then
			local t0 = os.clock()
			fn(...)
			add(entry, os.clock() - t0)
		else
			fn(...)
		end
		profileend()
	end
end

-- Cette méthode permet d'ajouter un temps mesuré à la main sous un nom lorsqu'un appel renvoie une valeur (que `wrap`
-- ne gère pas) ; sans effet si le chronométrage est inactif.
function PerfMarkers.record(label: string, seconds: number)
	if not PerfMarkers.timing then
		return
	end
	add(entryOf(label), seconds)
end

-- Cette méthode permet de relever les totaux accumulés depuis le relevé précédent puis de les remettre à zéro
-- lorsque l'overlay rafraîchit son affichage.
function PerfMarkers.collect(): Totals
	local out = {}
	for label, entry in totals do
		out[label] = { time = entry.time, calls = entry.calls, max = entry.max }
		entry.time, entry.calls, entry.max = 0, 0, 0
	end
	return out
end

-- Cette méthode permet de noter le cumul de chaque repère et de repartir d'un pire appel nul lorsqu'une mesure longue
-- commence (rejeu de parcours) ; le résultat se passe à `since`. Une seule mesure longue à la fois.
function PerfMarkers.mark(): Totals
	local out = {}
	for label, entry in totals do
		out[label] = { time = entry.sumTime, calls = entry.sumCalls, max = 0 }
		entry.peak = 0
	end
	return out
end

-- Cette méthode permet de rendre le temps, les appels et le pire appel de chaque repère depuis un `mark` lorsque la
-- mesure longue se termine, sans rien remettre à zéro (les relevés `collect` de l'overlay ne sont pas touchés).
function PerfMarkers.since(start: Totals): Totals
	local out = {}
	for label, entry in totals do
		local from = start[label]
		out[label] = {
			time = entry.sumTime - (if from then from.time else 0),
			calls = entry.sumCalls - (if from then from.calls else 0),
			max = entry.peak,
		}
	end
	return out
end

return PerfMarkers

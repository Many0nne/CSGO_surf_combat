-- PerfMarkers.luau (shared)
-- Repères de coût des boucles par frame (cf. docs/performance.md). `wrap` entoure un callback d'un
-- debug.profilebegin/profileend : le MicroProfiler (Ctrl+F6) affiche alors son coût sous ce nom. Quand `timing` vaut
-- true (overlay ouvert), il additionne aussi le temps et le nombre d'appels, relevés par `collect`.

local PerfMarkers = {}

-- debug.profilebegin n'existe que dans Roblox : sous Lune (tests), les repères ne font que compter.
local profilebegin = (debug :: any).profilebegin or function(_label: string) end
local profileend = (debug :: any).profileend or function() end

PerfMarkers.timing = false

local totals: { [string]: { time: number, calls: number, max: number } } = {}

-- Cette méthode permet d'entourer d'un repère nommé un callback sans valeur de retour (RenderStep, Heartbeat,
-- RenderStepped) lorsqu'on veut voir son coût dans le MicroProfiler et l'overlay.
function PerfMarkers.wrap<A...>(label: string, fn: (A...) -> ()): (A...) -> ()
	local entry = totals[label]
	if not entry then
		entry = { time = 0, calls = 0, max = 0 }
		totals[label] = entry
	end
	return function(...: A...)
		profilebegin(label)
		if PerfMarkers.timing then
			local t0 = os.clock()
			fn(...)
			local spent = os.clock() - t0
			entry.time += spent
			entry.calls += 1
			if spent > entry.max then
				entry.max = spent
			end
		else
			fn(...)
		end
		profileend()
	end
end

-- Cette méthode permet de relever les totaux accumulés depuis le relevé précédent puis de les remettre à zéro
-- lorsque l'overlay rafraîchit son affichage.
function PerfMarkers.collect(): { [string]: { time: number, calls: number, max: number } }
	local out = {}
	for label, entry in totals do
		out[label] = { time = entry.time, calls = entry.calls, max = entry.max }
		entry.time, entry.calls, entry.max = 0, 0, 0
	end
	return out
end

return PerfMarkers

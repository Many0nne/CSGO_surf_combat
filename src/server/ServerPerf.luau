-- ServerPerf.luau (server)
-- Sonde de coût du serveur (#145, cf. docs/performance.md) : l'attribut Workspace `PerfServer` (true) chronomètre les
-- repères de scripts du serveur (`srv bots`, `srv round`) et écrit une ligne `[Perf] SRV` toutes les 10 s dans la
-- console serveur (F9 > Server) : durée des Heartbeat, coût des scripts, bots en jeu, mémoire. false l'arrête (dernier bilan).
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local PerfRules = require(ReplicatedStorage.Shared.PerfRules)

local ATTRIBUTE = "PerfServer"
local LOG_PERIOD = 10 -- secondes entre deux bilans
local MAX_MARKERS = 6

local ServerPerf = {}

local connection: RBXScriptConnection? = nil
local dts: { number } = {}
local totals: PerfRules.MarkerTotals = {}
local openedAt = 0
local lastLog = 0
local botInfo: () -> (number, number) = function()
	return 0, 0
end

-- Cette méthode permet d'additionner les repères relevés lorsqu'un bilan accumule plusieurs relevés.
local function accumulate(from: PerfRules.MarkerTotals)
	for label, t in from do
		local into = totals[label]
		if not into then
			totals[label] = { time = t.time, calls = t.calls, max = t.max }
		else
			into.time += t.time
			into.calls += t.calls
			into.max = math.max(into.max, t.max)
		end
	end
end

-- Cette méthode permet d'écrire le bilan de la période lorsque LOG_PERIOD s'est écoulée ou que la sonde s'arrête.
local function logSummary()
	if #dts == 0 then
		return
	end
	accumulate(PerfMarkers.collect())
	local s = PerfRules.frameStats(dts)
	local scripts = {}
	for i, m in PerfRules.markerReport(totals, s.frames) do
		if i > MAX_MARKERS then
			break
		end
		table.insert(
			scripts,
			string.format("%s %.3fms×%.1f (max %.2f)", m.label, m.msPerFrame, m.callsPerFrame, m.maxMs)
		)
	end
	local total, alive = botInfo()
	print(
		string.format(
			"[Perf] SRV t=%.0fs Heartbeat méd %.1fms p99 %.1fms max %.1fms | bots %d (%d en jeu) | mém %.0f Mo, Lua %.1f Mo"
				.. " | scripts : %s",
			os.clock() - openedAt,
			s.medianMs,
			s.p99Ms,
			s.maxMs,
			total,
			alive,
			Stats:GetTotalMemoryUsageMb(),
			gcinfo() / 1024,
			table.concat(scripts, ", ")
		)
	)
	dts = {}
	totals = {}
	lastLog = os.clock()
end

-- Cette méthode permet de démarrer ou d'arrêter la sonde lorsque l'attribut Workspace `PerfServer` change.
local function apply()
	local on = workspace:GetAttribute(ATTRIBUTE) == true
	if on and not connection then
		dts, totals = {}, {}
		PerfMarkers.collect()
		PerfMarkers.timing = true
		openedAt, lastLog = os.clock(), os.clock()
		connection = RunService.Heartbeat:Connect(function(dt: number)
			table.insert(dts, dt)
			if os.clock() - lastLog >= LOG_PERIOD then
				logSummary()
			end
		end)
		print("[Perf] SRV sonde serveur ouverte : une ligne toutes les " .. LOG_PERIOD .. " s")
	elseif not on and connection then
		logSummary()
		connection:Disconnect()
		connection = nil
		PerfMarkers.timing = false
		print("[Perf] SRV sonde serveur fermée")
	end
end

-- Cette méthode permet de brancher la sonde lorsque le serveur démarre ; `info` renvoie le nombre de bots et celui des
-- bots en jeu au moment du bilan.
function ServerPerf.init(info: () -> (number, number))
	botInfo = info
	workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(apply)
	apply()
end

return ServerPerf

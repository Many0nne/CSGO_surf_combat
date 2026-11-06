-- PerfRules.luau (shared)
-- Règles pures de l'environnement de mesure des performances (cf. docs/performance.md) : qui peut ouvrir l'overlay,
-- écarts mémoire entre deux relevés, classement du coût des scripts. Sans service Roblox : testées sous Lune.

local PerfRules = {}

-- Catégories mémoire affichées par l'overlay, avec leur libellé court (Enum.DeveloperMemoryTag).
PerfRules.OVERLAY_TAGS = {
	{ tag = "LuaHeap", label = "Lua" },
	{ tag = "Script", label = "Scripts" },
	{ tag = "Instances", label = "Instances" },
	{ tag = "Signals", label = "Signaux" },
	{ tag = "GraphicsTexture", label = "Textures" },
	{ tag = "GraphicsParts", label = "Pièces" },
	{ tag = "GraphicsMeshParts", label = "Maillages" },
	{ tag = "GraphicsParticles", label = "Particules" },
	{ tag = "GraphicsTerrain", label = "Terrain" },
	{ tag = "Gui", label = "UI" },
	{ tag = "Sounds", label = "Sons" },
	{ tag = "Animation", label = "Anim" },
	{ tag = "BaseParts", label = "BaseParts" },
	{ tag = "PhysicsCollision", label = "Collisions" },
}

PerfRules.MEMORY_DIFF_MIN_MB = 0.5 -- en dessous, une variation de catégorie n'est pas signalée
PerfRules.MEMORY_DIFF_MAX = 5 -- catégories citées au plus par relevé
PerfRules.MIN_ROUND_DURATION = 10 -- secondes : en dessous, l'attribut Workspace RoundDuration est ignoré

export type MemorySnapshot = {
	index: number,
	reason: string,
	totalMb: number,
	instanceCount: number,
	luaKb: number, -- gcinfo() de la VM qui relève
	tags: { [string]: number }, -- Mo par Enum.DeveloperMemoryTag (nom)
}

export type MarkerTotals = { [string]: { time: number, calls: number, max: number } }

export type MarkerLine = { label: string, msPerFrame: number, callsPerFrame: number, maxMs: number }

-- Cette méthode permet de dire si un joueur peut ouvrir les outils de mesure lorsque le jeu tourne dans Studio
-- (toujours) ou publié (seulement le créateur, si le jeu appartient à un utilisateur et non à un groupe).
function PerfRules.canUse(isStudio: boolean, userId: number, creatorId: number, ownedByUser: boolean): boolean
	if isStudio then
		return true
	end
	return ownedByUser and creatorId ~= 0 and userId == creatorId
end

-- Cette méthode permet de lister les catégories mémoire qui ont le plus varié entre deux relevés lorsqu'on cherche
-- une fuite (les plus fortes hausses d'abord, puis les baisses, au-delà de MEMORY_DIFF_MIN_MB).
function PerfRules.memoryDiff(prev: { [string]: number }, cur: { [string]: number }): { { tag: string, delta: number } }
	local diffs = {}
	for tag, mb in cur do
		local delta = mb - (prev[tag] or 0)
		if math.abs(delta) >= PerfRules.MEMORY_DIFF_MIN_MB then
			table.insert(diffs, { tag = tag, delta = delta })
		end
	end
	table.sort(diffs, function(a, b)
		if a.delta ~= b.delta then
			return a.delta > b.delta
		end
		return a.tag < b.tag
	end)
	while #diffs > PerfRules.MEMORY_DIFF_MAX do
		table.remove(diffs)
	end
	return diffs
end

-- Cette méthode permet d'écrire un écart signé avec une décimale lorsqu'une ligne de relevé compare deux valeurs.
local function signed(value: number): string
	return string.format("%+.1f", value)
end

-- Cette méthode permet de rédiger la ligne de console d'un relevé mémoire lorsqu'on le compare au précédent et au
-- premier de la session (une hausse qui ne redescend jamais d'un spawn à l'autre signale une fuite).
function PerfRules.formatSnapshot(
	side: string,
	cur: MemorySnapshot,
	prev: MemorySnapshot?,
	first: MemorySnapshot?
): string
	local parts = {
		string.format("MEM %s #%d %s : total %.0f Mo", side, cur.index, cur.reason, cur.totalMb),
	}
	if prev then
		table.insert(parts, string.format(" (%s depuis #%d", signed(cur.totalMb - prev.totalMb), prev.index))
		if first and first ~= prev then
			table.insert(parts, string.format(", %s depuis #%d", signed(cur.totalMb - first.totalMb), first.index))
		end
		table.insert(parts, ")")
	end
	table.insert(parts, string.format(" | Instances %d", cur.instanceCount))
	if prev then
		table.insert(parts, string.format(" (%+d)", cur.instanceCount - prev.instanceCount))
	end
	table.insert(parts, string.format(" | Lua %.1f Mo", cur.luaKb / 1024))
	if prev then
		table.insert(parts, string.format(" (%s)", signed((cur.luaKb - prev.luaKb) / 1024)))
		local diffs = PerfRules.memoryDiff(prev.tags, cur.tags)
		if #diffs > 0 then
			local list = {}
			for _, d in diffs do
				table.insert(list, d.tag .. " " .. signed(d.delta))
			end
			table.insert(parts, " | écarts Mo : " .. table.concat(list, ", "))
		end
	end
	return table.concat(parts)
end

-- Cette méthode permet de ramener les totaux des repères de scripts à une frame moyenne lorsque l'overlay affiche
-- leur coût (du plus cher au moins cher ; un nombre d'appels par frame supérieur à 1 signale une connexion en double).
function PerfRules.markerReport(totals: MarkerTotals, frames: number): { MarkerLine }
	local lines = {}
	if frames <= 0 then
		return lines
	end
	for label, t in totals do
		table.insert(lines, {
			label = label,
			msPerFrame = t.time * 1000 / frames,
			callsPerFrame = t.calls / frames,
			maxMs = t.max * 1000,
		})
	end
	table.sort(lines, function(a, b)
		if a.msPerFrame ~= b.msPerFrame then
			return a.msPerFrame > b.msPerFrame
		end
		return a.label < b.label
	end)
	return lines
end

export type BenchSummary = {
	gpuMeanMs: number,
	gpuP95Ms: number,
	cpuMeanMs: number,
	frameMedianMs: number,
	frameP99Ms: number,
	frames: number,
}

-- Cette méthode permet de lire le centile p (0..1) d'une liste lorsque le banc résume une phase (copie triée).
local function percentile(values: { number }, p: number): number
	local n = #values
	if n == 0 then
		return 0
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[math.clamp(math.ceil(p * n), 1, n)]
end

-- Cette méthode permet de résumer une phase du banc (F4) lorsque ses frames ont été relevées : temps GPU et CPU du
-- rendu (ms, par frame) et durée des frames (ms).
function PerfRules.benchSummary(gpuMs: { number }, cpuMs: { number }, frameMs: { number }): BenchSummary
	local gpuSum, cpuSum = 0, 0
	for _, v in gpuMs do
		gpuSum += v
	end
	for _, v in cpuMs do
		cpuSum += v
	end
	return {
		gpuMeanMs = #gpuMs > 0 and gpuSum / #gpuMs or 0,
		gpuP95Ms = percentile(gpuMs, 0.95),
		cpuMeanMs = #cpuMs > 0 and cpuSum / #cpuMs or 0,
		frameMedianMs = percentile(frameMs, 0.5),
		frameP99Ms = percentile(frameMs, 0.99),
		frames = #frameMs,
	}
end

-- Cette méthode permet de dire si une phase du banc est exploitable lorsqu'elle se termine : fenêtre restée au premier
-- plan, et GPU mesuré (un client en arrière-plan ne rend presque rien, GPU à 0).
function PerfRules.benchPhaseValid(s: BenchSummary, focusLost: boolean): boolean
	return not focusLost and s.frames > 0 and s.gpuMeanMs > 0
end

-- Cette méthode permet de rédiger la ligne de console d'une phase du banc lorsqu'elle se termine, avec l'écart de GPU
-- par rapport à la référence (nil pour la référence elle-même).
function PerfRules.formatBenchLine(name: string, s: BenchSummary, valid: boolean, refGpuMs: number?): string
	local delta = ""
	if refGpuMs and valid then
		delta = string.format(" (%+.1f)", s.gpuMeanMs - refGpuMs)
	end
	return string.format(
		"BANC %-30s GPU moy %5.1f%s p95 %5.1f | CPU moy %5.1f | frame méd %5.1f p99 %5.1f ms%s",
		name,
		s.gpuMeanMs,
		delta,
		s.gpuP95Ms,
		s.cpuMeanMs,
		s.frameMedianMs,
		s.frameP99Ms,
		valid and "" or " | INVALIDE (fenêtre en arrière-plan : refaire le banc)"
	)
end

-- Cette méthode permet de choisir la durée d'un round lorsqu'il démarre : l'attribut Workspace `RoundDuration` (mesure
-- mémoire sur plusieurs rounds, #95) remplace la durée par défaut s'il vaut un nombre d'au moins MIN_ROUND_DURATION.
function PerfRules.roundDuration(default: number, override: any): number
	if type(override) == "number" and override == override and override >= PerfRules.MIN_ROUND_DURATION then
		return override
	end
	return default
end

return PerfRules

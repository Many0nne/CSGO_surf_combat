-- MemoryTracker.luau (shared)
-- Relevés mémoire datés pour repérer une fuite (cf. docs/performance.md) : à chaque événement de cycle de vie (spawn,
-- fin de round, départ d'un joueur), une ligne `[Perf] MEM ...` compare la mémoire par catégorie, le nombre
-- d'Instances et le tas Lua au relevé précédent et au premier. Utilisé côté client et côté serveur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local PerfRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PerfRules"))

local MemoryTracker = {}

local side = if RunService:IsServer() then "SERVEUR" else "CLIENT"
local enabled = false
local count = 0
local first: PerfRules.MemorySnapshot?
local last: PerfRules.MemorySnapshot?

-- Cette méthode permet de lire la mémoire de toutes les catégories lorsqu'un relevé ou l'overlay en a besoin
-- (table vide si le moteur ne suit pas la mémoire, comme dans le client publié : chaque lecture y écrirait un warning).
function MemoryTracker.readTags(): { [string]: number }
	local tags = {}
	if not Stats.MemoryTrackingEnabled then
		return tags
	end
	for _, item in Enum.DeveloperMemoryTag:GetEnumItems() do
		tags[item.Name] = Stats:GetMemoryUsageMbForTag(item)
	end
	return tags
end

-- Cette méthode permet d'activer les relevés lorsque le joueur ou le serveur a le droit de mesurer (Studio, créateur).
function MemoryTracker.enable()
	enabled = true
end

-- Cette méthode permet d'écrire un relevé daté dans la console lorsqu'un événement du cycle de vie a lieu
-- (rien tant que les relevés ne sont pas activés).
function MemoryTracker.snapshot(reason: string)
	if not enabled then
		return
	end
	count += 1
	local cur: PerfRules.MemorySnapshot = {
		index = count,
		reason = reason,
		totalMb = Stats:GetTotalMemoryUsageMb(),
		instanceCount = Stats.InstanceCount,
		luaKb = gcinfo(),
		tags = MemoryTracker.readTags(),
	}
	print("[Perf] " .. PerfRules.formatSnapshot(side, cur, last, first))
	first = first or cur
	last = cur
end

return MemoryTracker

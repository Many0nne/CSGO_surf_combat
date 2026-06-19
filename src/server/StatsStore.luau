local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")

local SCHEMA_VERSION    = 1
local AUTO_SAVE_INTERVAL = 120

local store = DataStoreService:GetDataStore("PlayerStats_v1")

type Stats   = { kills: number, deaths: number, roundsPlayed: number, roundsWon: number }
type Profile = { schemaVersion: number, stats: Stats }

local profiles:     { [number]: Profile } = {}
local saveDisabled: { [number]: boolean } = {}

local StatsStore = {}

local DEFAULT_STATS: Stats = { kills = 0, deaths = 0, roundsPlayed = 0, roundsWon = 0 }

local function key(player: Player): string
	return tostring(player.UserId)
end

local function tryGet(k: string): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(store.GetAsync, store, k)
		if ok then return true, result end
		task.wait(2 ^ attempt)
	end
	return false, nil
end

local function trySet(k: string, data: any): boolean
	for attempt = 1, 3 do
		local ok = pcall(store.SetAsync, store, k, data)
		if ok then return true end
		task.wait(2 ^ attempt)
	end
	return false
end

function StatsStore.load(player: Player)
	local ok, data = tryGet(key(player))
	if not ok then
		-- Load failed: disable save for this session to avoid wiping data
		saveDisabled[player.UserId] = true
		profiles[player.UserId] = { schemaVersion = SCHEMA_VERSION, stats = table.clone(DEFAULT_STATS) }
		warn("[StatsStore] load failed for", player.Name, "— save disabled this session")
		return
	end
	if data == nil then
		profiles[player.UserId] = { schemaVersion = SCHEMA_VERSION, stats = table.clone(DEFAULT_STATS) }
	else
		-- Forward migration
		if data.schemaVersion ~= SCHEMA_VERSION then
			data.schemaVersion = SCHEMA_VERSION
			for field, default in pairs(DEFAULT_STATS) do
				if data.stats[field] == nil then
					data.stats[field] = default
				end
			end
		end
		profiles[player.UserId] = data
	end
end

function StatsStore.save(player: Player)
	if saveDisabled[player.UserId] then return end
	local profile = profiles[player.UserId]
	if not profile then return end
	trySet(key(player), profile)
end

function StatsStore.getStats(player: Player): Stats
	local profile = profiles[player.UserId]
	return profile and profile.stats or table.clone(DEFAULT_STATS)
end

function StatsStore.recordKill(player: Player)
	local p = profiles[player.UserId]
	if p then p.stats.kills += 1 end
end

function StatsStore.recordDeath(player: Player)
	local p = profiles[player.UserId]
	if p then p.stats.deaths += 1 end
end

function StatsStore.recordRoundEnd(player: Player, won: boolean)
	local p = profiles[player.UserId]
	if not p then return end
	p.stats.roundsPlayed += 1
	if won then p.stats.roundsWon += 1 end
end

function StatsStore.init()
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				StatsStore.save(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		StatsStore.save(player)
		profiles[player.UserId]     = nil
		saveDisabled[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			StatsStore.save(player)
		end
	end)
end

return StatsStore

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

type Score = { name: string, kills: number, deaths: number, firstKillTick: number }

local RoundManager = {}

local state      = "idle"  -- "idle" | "active" | "result"
local timeLeft   = 0
-- Combatant id: real players use their positive UserId, bots use a synthetic
-- negative id. Both slot into these [number]-keyed tables.
local scores: { [number]: Score } = {}       -- keyed by combatant id
local lastAttacker: { [number]: number } = {}  -- victim id → attacker id

local roundStateRmt:  RemoteEvent
local scoreUpdateRmt: RemoteEvent
local roundResultRmt: RemoteEvent
local playerDiedRmt:  RemoteEvent

local timerConn: RBXScriptConnection?

-- ── helpers ────────────────────────────────────────────────────────────────

local function broadcastState()
	roundStateRmt:FireAllClients({ state = state, timeLeft = math.ceil(timeLeft) })
end

local function broadcastScores()
	scoreUpdateRmt:FireAllClients(scores)
end

function RoundManager.ensureScoreById(id: number, name: string): Score
	if not scores[id] then
		scores[id] = { name = name, kills = 0, deaths = 0, firstKillTick = 0 }
		broadcastScores()
	end
	return scores[id]
end

function RoundManager.removeScoreById(id: number)
	scores[id]       = nil
	lastAttacker[id] = nil
	broadcastScores()
end

local function ensureScore(player: Player): Score
	return RoundManager.ensureScoreById(player.UserId, player.Name)
end

local function computeWinner(): string
	local bestName   = "Personne"
	local bestKills  = -1
	local bestDeaths = math.huge
	local bestTick   = math.huge
	for _, score in pairs(scores) do
		if  score.kills > bestKills
		or (score.kills == bestKills and score.deaths < bestDeaths)
		or (score.kills == bestKills and score.deaths == bestDeaths and score.firstKillTick < bestTick)
		then
			bestKills  = score.kills
			bestDeaths = score.deaths
			bestTick   = score.firstKillTick
			bestName   = score.name
		end
	end
	return bestName
end

-- ── round lifecycle ────────────────────────────────────────────────────────

local function endRound()
	if timerConn then timerConn:Disconnect(); timerConn = nil end
	state = "result"

	local winnerName = computeWinner()
	roundResultRmt:FireAllClients({ winnerName = winnerName, scores = scores })

	-- Destroy all characters so clients return to lobby state
	for _, player in Players:GetPlayers() do
		if player.Character then
			player.Character:Destroy()
		end
	end

	task.delay(6, function()  -- RESULT_DURATION
		state  = "idle"
		scores = {}
		lastAttacker = {}
		broadcastState()
	end)
end

function RoundManager.startRound(duration: number)
	if state == "active" then return end
	state    = "active"
	timeLeft = duration
	broadcastState()
	broadcastScores()

	local lastBroadcastSecond = math.ceil(timeLeft)

	timerConn = RunService.Heartbeat:Connect(function(dt)
		if state ~= "active" then
			if timerConn then timerConn:Disconnect(); timerConn = nil end
			return
		end
		timeLeft = timeLeft - dt
		if timeLeft <= 0 then
			timeLeft = 0
			endRound()
			return
		end
		local currentSecond = math.ceil(timeLeft)
		if currentSecond ~= lastBroadcastSecond then
			lastBroadcastSecond = currentSecond
			broadcastState()
		end
	end)
end

-- ── combat recording ───────────────────────────────────────────────────────

function RoundManager.recordDamageById(attackerId: number, victimId: number)
	if attackerId ~= victimId then
		lastAttacker[victimId] = attackerId
	end
end

function RoundManager.recordDamage(attacker: Player, victim: Player)
	if victim then
		RoundManager.recordDamageById(attacker.UserId, victim.UserId)
	end
end

-- Generic death/attribution for any tracked combatant (player or bot).
-- Returns the attacker id (or nil) so callers can decide on persistent stats.
function RoundManager.onCombatantDied(victimId: number, victimPlayer: Player?): number?
	if state ~= "active" then return nil end

	local victimScore = scores[victimId]
	if not victimScore then return nil end
	victimScore.deaths += 1

	local attackerId = lastAttacker[victimId]
	lastAttacker[victimId] = nil

	if attackerId and attackerId ~= victimId then
		local as = scores[attackerId]
		if as then
			as.kills += 1
			if as.firstKillTick == 0 then
				as.firstKillTick = tick()
			end
		end
	end

	broadcastScores()
	if victimPlayer then
		playerDiedRmt:FireClient(victimPlayer, { killerId = attackerId })
	end
	return attackerId
end

-- Player wrapper: handles death + the player-specific respawn schedule.
-- Returns the attacker id so init.server can gate persistent stats.
function RoundManager.onCharacterDied(victim: Player, spawnFn: (Player) -> ()): number?
	ensureScore(victim)
	local attackerId = RoundManager.onCombatantDied(victim.UserId, victim)

	task.delay(2.5, function()  -- RESPAWN_DELAY
		if state == "active" and victim.Parent then
			spawnFn(victim)
		end
	end)
	return attackerId
end

-- ── player lifecycle ───────────────────────────────────────────────────────

function RoundManager.addPlayer(player: Player)
	ensureScore(player)
	broadcastScores()
end

function RoundManager.removePlayer(player: Player)
	scores[player.UserId]       = nil
	lastAttacker[player.UserId] = nil
	broadcastScores()
	if state == "active" and #Players:GetPlayers() == 0 then
		if timerConn then timerConn:Disconnect(); timerConn = nil end
		state  = "idle"
		scores = {}
	end
end

-- ── accessors ──────────────────────────────────────────────────────────────

function RoundManager.getState(): string
	return state
end

function RoundManager.isActive(): boolean
	return state == "active"
end

-- ── init ───────────────────────────────────────────────────────────────────

function RoundManager.init(remotes: {
	roundState:   RemoteEvent,
	scoreUpdate:  RemoteEvent,
	roundResult:  RemoteEvent,
	playerDied:   RemoteEvent,
})
	roundStateRmt  = remotes.roundState
	scoreUpdateRmt = remotes.scoreUpdate
	roundResultRmt = remotes.roundResult
	playerDiedRmt  = remotes.playerDied
end

return RoundManager

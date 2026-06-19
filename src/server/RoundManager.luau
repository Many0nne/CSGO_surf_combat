local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

type Score = { name: string, kills: number, deaths: number, firstKillTick: number }

local RoundManager = {}

local state      = "idle"  -- "idle" | "active" | "result"
local timeLeft   = 0
local scores: { [number]: Score } = {}       -- keyed by UserId
local lastAttacker: { [number]: number } = {}  -- victimUserId → attackerUserId

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

local function ensureScore(player: Player): Score
	local uid = player.UserId
	if not scores[uid] then
		scores[uid] = { name = player.Name, kills = 0, deaths = 0, firstKillTick = 0 }
	end
	return scores[uid]
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

function RoundManager.recordDamage(attacker: Player, victim: Player)
	if victim then
		lastAttacker[victim.UserId] = attacker.UserId
	end
end

function RoundManager.onCharacterDied(victim: Player, spawnFn: (Player) -> ())
	if state ~= "active" then return end

	local victimScore = ensureScore(victim)
	victimScore.deaths += 1

	local attackerUid = lastAttacker[victim.UserId]
	lastAttacker[victim.UserId] = nil

	if attackerUid then
		local attacker = Players:GetPlayerByUserId(attackerUid)
		if attacker and attacker ~= victim then
			local as = ensureScore(attacker)
			as.kills += 1
			if as.firstKillTick == 0 then
				as.firstKillTick = tick()
			end
		end
	end

	broadcastScores()
	playerDiedRmt:FireClient(victim, { killerId = attackerUid })

	task.delay(2.5, function()  -- RESPAWN_DELAY
		if state == "active" and victim.Parent then
			spawnFn(victim)
		end
	end)
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

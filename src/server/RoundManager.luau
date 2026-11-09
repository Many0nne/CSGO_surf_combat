local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MemoryTracker = require(ReplicatedStorage.Shared.MemoryTracker)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ParticipantRules = require(ReplicatedStorage.Shared.ParticipantRules)
local Participants = require(ServerScriptService.Server.Participants)

type Participant = Participants.Participant
-- Score d'un participant (joueur ou bot), envoyé tel quel aux clients (classement, préfixe BOT)
type Score = { name: string, isBot: boolean, kills: number, deaths: number, firstKillTick: number }
-- Dernier coup reçu par une victime : tueur crédité, arme et tir à la tête affichés à la mort (#102)
type LastHit = { attackerId: number, weapon: string?, headshot: boolean }

local RoundManager = {}

local state = "idle" -- "idle" | "active" | "result"
local timeLeft = 0
local scores: { [number]: Score } = {} -- par id de participant
local lastAttacker: { [number]: LastHit } = {} -- id de la victime → dernier coup reçu

local roundStateRmt: RemoteEvent
local scoreUpdateRmt: RemoteEvent
local roundResultRmt: RemoteEvent
local playerDiedRmt: RemoteEvent

local timerConn: RBXScriptConnection?

-- ── helpers ────────────────────────────────────────────────────────────────

local function broadcastState()
	roundStateRmt:FireAllClients({ state = state, timeLeft = math.ceil(timeLeft) })
end

local function broadcastScores()
	scoreUpdateRmt:FireAllClients(scores)
end

local function ensureScore(participant: Participant): Score
	local id = participant.id
	if not scores[id] then
		scores[id] = { name = participant.name, isBot = participant.isBot, kills = 0, deaths = 0, firstKillTick = 0 }
		broadcastScores()
	end
	return scores[id]
end

local function computeWinner(): string
	local bestName = "Personne"
	local bestKills = -1
	local bestDeaths = math.huge
	local bestTick = math.huge
	for _, score in pairs(scores) do
		if
			score.kills > bestKills
			or (score.kills == bestKills and score.deaths < bestDeaths)
			or (score.kills == bestKills and score.deaths == bestDeaths and score.firstKillTick < bestTick)
		then
			bestKills = score.kills
			bestDeaths = score.deaths
			bestTick = score.firstKillTick
			bestName = ParticipantRules.displayName(score.name, score.isBot)
		end
	end
	return bestName
end

-- ── round lifecycle ────────────────────────────────────────────────────────

local function endRound()
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
	state = "result"

	local winnerName = computeWinner()
	roundResultRmt:FireAllClients({ winnerName = winnerName, scores = scores })

	-- Personnages détruits (joueurs et bots) : les clients repassent par le menu
	for _, participant in Participants.all() do
		local character = Participants.characterOf(participant)
		if character then
			character:Destroy()
		end
	end

	task.delay(6, function() -- RESULT_DURATION
		state = "idle"
		scores = {}
		lastAttacker = {}
		broadcastState()
		-- personnages détruits depuis 6 s : ce qui reste d'un round à l'autre est candidat à une fuite
		MemoryTracker.snapshot("fin de round")
	end)
end

function RoundManager.startRound(duration: number)
	if state == "active" then
		return
	end
	state = "active"
	timeLeft = duration
	-- base de comparaison du round, avant l'apparition de son premier personnage (cf. docs/performance.md)
	MemoryTracker.snapshot(string.format("début de round (%d s)", duration))
	broadcastState()
	broadcastScores()

	local lastBroadcastSecond = math.ceil(timeLeft)

	timerConn = RunService.Heartbeat:Connect(PerfMarkers.wrap("srv round", function(dt)
		if state ~= "active" then
			if timerConn then
				timerConn:Disconnect()
				timerConn = nil
			end
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
	end))
end

-- ── combat recording ───────────────────────────────────────────────────────

-- Cette méthode permet de retenir le dernier coup porté à une victime (tireur, arme, tir à la tête) lorsqu'une touche
-- est validée ; c'est lui qui désigne le tueur à la mort.
function RoundManager.recordDamage(attacker: Participant, victim: Participant, weapon: string?, headshot: boolean?)
	if victim and attacker ~= victim then
		lastAttacker[victim.id] = { attackerId = attacker.id, weapon = weapon, headshot = headshot == true }
	end
end

-- Cette méthode permet de lire la position de la racine d'un participant lorsqu'on décrit sa mort (nil sans personnage).
local function rootPosition(participant: Participant?): Vector3?
	local char = participant and Participants.characterOf(participant)
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- Cette méthode permet d'annoncer une mort à tous les clients (écran du tué, kill feed, corps) lorsqu'elle est comptée ;
-- noms et drapeaux bot inclus, le client ne trouvant pas de Player pour un bot ; direction = du tueur vers la victime.
local function announceDeath(victim: Participant, hit: LastHit?, killer: Participant?)
	local position = rootPosition(victim)
	local killerPos = rootPosition(killer)
	local direction = nil
	if position and killerPos and (position - killerPos).Magnitude > 0.01 then
		direction = (position - killerPos).Unit
	end
	playerDiedRmt:FireAllClients({
		victimId = victim.id,
		victimName = victim.name,
		victimIsBot = victim.isBot,
		killerId = killer and killer.id,
		killerName = killer and killer.name,
		killerIsBot = killer ~= nil and killer.isBot,
		weapon = hit and hit.weapon,
		headshot = hit ~= nil and hit.headshot,
		position = position,
		direction = direction,
	})
end

-- Cette méthode permet de compter la mort d'un participant et le kill de son dernier attaquant lorsqu'un round est
-- actif ; elle renvoie le tueur crédité (nil pour une chute, ou un tueur parti depuis).
local function recordDeath(victim: Participant): Participant?
	if state ~= "active" then
		return nil
	end

	local victimId = victim.id
	local victimScore = scores[victimId]
	if not victimScore then
		return nil
	end
	victimScore.deaths += 1

	local hit = lastAttacker[victimId]
	lastAttacker[victimId] = nil
	local killer = if hit and hit.attackerId ~= victimId then Participants.get(hit.attackerId) else nil

	if killer then
		local as = scores[killer.id]
		if as then
			as.kills += 1
			if as.firstKillTick == 0 then
				as.firstKillTick = os.clock()
			end
		end
	end

	broadcastScores()
	announceDeath(victim, hit, killer)
	return killer
end

-- Cette méthode permet de compter la mort d'un participant et de programmer sa réapparition lorsqu'il meurt ; elle
-- renvoie le tueur crédité, pour décider si la mort compte dans les stats persistantes (ParticipantRules.countsInStats).
function RoundManager.onCharacterDied(victim: Participant, respawn: () -> ()): Participant?
	ensureScore(victim)
	local killer = recordDeath(victim)

	task.delay(GameConfig.RESPAWN_DELAY, function()
		if state == "active" and Participants.isRegistered(victim) then
			respawn()
		end
	end)
	return killer
end

-- ── participant lifecycle ──────────────────────────────────────────────────

-- Cette méthode permet d'inscrire un participant (joueur ou bot) au classement lorsqu'il entre dans le jeu.
function RoundManager.addParticipant(participant: Participant)
	ensureScore(participant)
	broadcastScores()
end

-- Cette méthode permet de retirer un participant du classement lorsqu'il quitte le jeu ; le round s'arrête quand il
-- ne reste plus aucun joueur (des bots seuls ne le font pas durer).
function RoundManager.removeParticipant(participant: Participant)
	scores[participant.id] = nil
	lastAttacker[participant.id] = nil
	broadcastScores()
	if state == "active" and #Players:GetPlayers() == 0 then
		if timerConn then
			timerConn:Disconnect()
			timerConn = nil
		end
		state = "idle"
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
	roundState: RemoteEvent,
	scoreUpdate: RemoteEvent,
	roundResult: RemoteEvent,
	playerDied: RemoteEvent,
})
	roundStateRmt = remotes.roundState
	scoreUpdateRmt = remotes.scoreUpdate
	roundResultRmt = remotes.roundResult
	playerDiedRmt = remotes.playerDied
end

return RoundManager

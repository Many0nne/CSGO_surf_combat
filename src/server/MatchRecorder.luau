-- Enregistreur de partie (#582), côté serveur : pendant qu'un joueur autorisé enregistre (Studio, ou créateur du jeu
-- publié : PerfRules.canUse), toute la partie est notée en données, pour être reconstruite dans Studio et filmée
-- (docs/promo.md, « Enregistreur de partie ») :
-- - position et cap de la racine de chaque participant en vie (joueurs et bots) à MatchRecordRules.ACTOR_HZ ;
-- - tenue portée (#521) et action de l'arme 3P (tir, recharge, sortie : attributs de WeaponThirdPerson), relevées à
--   chaque échantillon et notées quand elles changent ;
-- - tirs acceptés, armes sorties et leur skin, kills, morts : relayés par HighlightService (observateur), même hors
--   manche active et sur un serveur d'entraînement ;
-- - rejeu fidèle (#586) : effet de tir équipé de chaque joueur (relevé comme la tenue), pas et atterrissages
--   (FootstepService, branché par init), touches confirmées au joueur qui enregistre (hitmarker), état et timer de la
--   manche et classement (RoundManager, relevés toutes les ROUND_SPACING s, notés au début de chaque morceau et quand
--   ils changent).
-- Un morceau part au client qui enregistre toutes les CHUNK_SECONDS (remote MatchRecord, JSON) : il y ajoute sa caméra
-- et le recopie dans la console. Rien n'est gardé ici au-delà du morceau en cours ; aucun coût sans enregistrement.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local MatchRecordRules = require(ReplicatedStorage.Shared.MatchRecordRules)
local HighlightClipRules = require(ReplicatedStorage.Shared.HighlightClipRules)
local PerfRules = require(ReplicatedStorage.Shared.PerfRules)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)
local CheatLog = require(script.Parent.CheatLog)
local Participants = require(script.Parent.Participants)

type Participant = Participants.Participant
type Event = MatchRecordRules.Event

local E = MatchRecordRules.Event

export type Deps = {
	remote: RemoteEvent,
	-- Skin équipé sur l'outil d'un participant (bots : d'origine), pour les armes déjà en main au départ
	skinOf: (Participant, string) -> string?,
	-- Effet de tir équipé d'un participant (style de ShotEffectRules ; bots : nil)
	styleOf: (Participant) -> string?,
	-- État de la manche, temps restant (s) et classement par id (RoundManager)
	round: () -> (string, number, { [number]: any }),
}

-- Écart (s) entre deux relevés de la manche et du classement
local ROUND_SPACING = 0.5

type Session = {
	owner: Player,
	rec: string,
	seq: number,
	startedAt: number, -- horloge serveur du début
	t0: number, -- début du morceau en cours
	lastSample: number,
	rows: { [number]: { HighlightClipRules.Row } },
	names: { [number]: { name: string, bot: boolean } },
	events: { Event },
	outfits: { [number]: string | false },
	styles: { [number]: string | false },
	actions: { [Model]: number },
	lastRound: number,
	roundState: string?,
	scoresKey: string?,
}

local MatchRecorder = {}

local deps: Deps? = nil
local session: Session? = nil

-- Cette méthode permet d'écrire une ligne préfixée dans la sortie lorsque l'enregistrement change d'état (vue aussi
-- dans la console du jeu publié, par le créateur seul : F9 > Server).
local function log(text: string)
	print("[MatchRecord] " .. text)
end

-- Cette méthode permet de dire si un joueur peut enregistrer lorsqu'il le demande (mêmes droits que l'overlay F3).
local function canRecord(player: Player): boolean
	local ownedByUser = game.CreatorType == Enum.CreatorType.User
	return PerfRules.canUse(RunService:IsStudio(), player.UserId, game.CreatorId, ownedByUser)
end

-- Cette méthode permet de noter un évènement du morceau en cours lorsqu'il arrive (temps absolu ramené au morceau) ;
-- rien sans enregistrement.
local function push(t: number, event: Event)
	local s = session
	if not s then
		return
	end
	event.t = MatchRecordRules.milli(t - s.t0)
	table.insert(s.events, event)
end

-- Cette méthode permet de lire la racine d'un participant en vie lorsqu'il est échantillonné (nil s'il est mort,
-- absent ou sans racine).
local function liveRoot(participant: Participant): (Model?, BasePart?)
	local char = Participants.characterOf(participant)
	if not char then
		return nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return char, nil
	end
	return char, root
end

-- Cette méthode permet de relever la position, le cap, la tenue et l'action 3P de chaque participant lorsqu'un
-- échantillon est dû.
local function sample(s: Session, now: number)
	for _, participant in Participants.all() do
		local id = participant.id
		local char, root = liveRoot(participant)
		if not char or not root then
			continue
		end
		if not s.names[id] then
			s.names[id] = { name = participant.name, bot = participant.isBot }
		end
		local rows = s.rows[id]
		if not rows then
			rows = {}
			s.rows[id] = rows
		end
		local pos = root.Position
		local _, yaw = root.CFrame:ToEulerAnglesYXZ()
		table.insert(rows, { now - s.t0, pos.X, pos.Y, pos.Z, yaw })
		local outfit = CharacterAppearance.outfitOf(char) or false
		if s.outfits[id] ~= outfit then
			s.outfits[id] = outfit
			push(now, { t = 0, k = E.OUTFIT, id = id, o = if outfit then outfit else nil })
		end
		local d = deps
		local style = (d and d.styleOf(participant)) or false
		if s.styles[id] ~= style then
			s.styles[id] = style
			push(now, { t = 0, k = E.FX, id = id, s = if style then style else nil })
		end
		local at = char:GetAttribute(WeaponThirdPerson.ACTION_AT_ATTR)
		local action = char:GetAttribute(WeaponThirdPerson.ACTION_ATTR)
		if type(at) == "number" and type(action) == "string" and s.actions[char] ~= at then
			local first = s.actions[char] == nil
			s.actions[char] = at
			-- Action déjà passée quand le personnage est vu pour la première fois : pas rejouée
			if not first or now - at < 0.5 then
				push(math.max(at, s.t0), { t = 0, k = E.ACTION, id = id, a = action })
			end
		end
	end
end

-- Cette méthode permet de relever l'état de la manche (timer) et le classement lorsqu'un relevé est dû : notés quand ils
-- changent, et au début de chaque morceau (rejeu lancé en cours de partie, morceau perdu).
local function sampleRound(s: Session, now: number)
	local d = deps
	if not d then
		return
	end
	local state, left, scores = d.round()
	if state ~= s.roundState then
		s.roundState = state
		push(now, { t = 0, k = E.ROUND, id = 0, s = state, l = MatchRecordRules.milli(left) })
	end
	local list, key = MatchRecordRules.encodeScores(scores)
	if key ~= s.scoresKey then
		s.scoresKey = key
		push(now, { t = 0, k = E.SCORES, id = 0, sc = list })
	end
end

-- Cette méthode permet d'envoyer le morceau en cours au client qui enregistre lorsqu'il est plein ou que
-- l'enregistrement s'arrête, puis d'en commencer un nouveau.
local function flush(s: Session, now: number, last: boolean)
	local d = deps
	if not d then
		return
	end
	s.seq += 1
	local actors = {}
	for id, rows in s.rows do
		local info = s.names[id]
		table.insert(actors, {
			id = id,
			name = info and info.name or "?",
			bot = info ~= nil and info.bot,
			track = HighlightClipRules.encodeSeries(rows, MatchRecordRules.ACTOR_SCALES),
		})
	end
	local chunk: { [string]: any } = {
		v = MatchRecordRules.VERSION,
		rec = s.rec,
		seq = s.seq,
		t0 = s.t0,
		t1 = now,
		last = if last then true else nil,
		actors = actors,
		events = s.events,
	}
	if s.seq == 1 then
		chunk.meta = {
			me = s.owner.UserId,
			name = s.owner.Name,
			map = MapSelection.currentName(),
			place = game.PlaceVersion,
			date = DateTime.now():ToIsoDate(),
		}
	end
	local ok, text = pcall(HttpService.JSONEncode, HttpService, chunk)
	if ok and s.owner.Parent == Players then
		d.remote:FireClient(s.owner, "chunk", s.seq, s.t0, now, text)
	elseif not ok then
		warn("[MatchRecord] morceau " .. s.seq .. " illisible : " .. tostring(text))
	end
	s.t0 = now
	s.rows = {}
	s.events = {}
	-- Timer et classement repris au début du morceau suivant
	s.roundState = nil
	s.scoresKey = nil
	if not last then
		sampleRound(s, now)
		s.lastRound = now
	end
end

-- Cette méthode permet de noter l'arme en main de chaque participant au début d'un enregistrement (les changements
-- suivants arrivent par HighlightService).
local function noteHeldWeapons(now: number)
	local d = deps :: Deps
	for _, participant in Participants.all() do
		local char = Participants.characterOf(participant)
		local tool = char and char:FindFirstChildOfClass("Tool")
		if tool then
			push(
				now,
				{ t = 0, k = E.EQUIP, id = participant.id, tool = tool.Name, skin = d.skinOf(participant, tool.Name) }
			)
		end
	end
end

-- Cette méthode permet de lancer un enregistrement pour un joueur autorisé lorsqu'il le demande ; un seul à la fois
-- par serveur (refusé si un autre joueur enregistre déjà).
local function start(player: Player)
	local d = deps
	if not d then
		return
	end
	if session then
		if session.owner ~= player then
			d.remote:FireClient(player, "refused", "un autre joueur enregistre déjà")
		end
		return
	end
	local now = workspace:GetServerTimeNow()
	local s: Session = {
		owner = player,
		rec = tostring(DateTime.now().UnixTimestampMillis),
		seq = 0,
		startedAt = now,
		t0 = now,
		lastSample = -math.huge,
		rows = {},
		names = {},
		events = {},
		outfits = {},
		styles = {},
		actions = setmetatable({}, { __mode = "k" }) :: any,
		lastRound = now,
		roundState = nil,
		scoresKey = nil,
	}
	session = s
	noteHeldWeapons(now)
	sample(s, now)
	sampleRound(s, now)
	s.lastSample = now
	log(string.format("REC %s par %s", s.rec, player.Name))
	d.remote:FireClient(player, "started", s.rec, now)
end

-- Cette méthode permet d'arrêter l'enregistrement en cours (dernier morceau envoyé) lorsque son joueur le demande,
-- part, ou que la durée maximale est atteinte.
function MatchRecorder.stop(reason: string?)
	local s = session
	if not s then
		return
	end
	local now = workspace:GetServerTimeNow()
	flush(s, now, true)
	session = nil
	log(
		string.format(
			"STOP %s : %.1f s, %d morceau(x)%s",
			s.rec,
			now - s.startedAt,
			s.seq,
			if reason then " (" .. reason .. ")" else ""
		)
	)
	local d = deps
	if d and s.owner.Parent == Players then
		d.remote:FireClient(s.owner, "stopped", s.rec, s.seq, now - s.startedAt)
	end
end

-- Cette méthode permet d'échantillonner et de découper l'enregistrement lorsqu'une frame serveur passe.
local function onHeartbeat()
	local s = session
	if not s then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - s.lastSample >= MatchRecordRules.ACTOR_SPACING then
		s.lastSample = now
		sample(s, now)
	end
	if now - s.lastRound >= ROUND_SPACING then
		s.lastRound = now
		sampleRound(s, now)
	end
	if now - s.startedAt >= MatchRecordRules.MAX_SECONDS then
		MatchRecorder.stop("durée maximale")
	elseif now - s.t0 >= MatchRecordRules.CHUNK_SECONDS then
		flush(s, now, false)
	end
end

-- ── Observateur de HighlightService ────────────────────────────────────────

-- Cette méthode permet de noter un tir accepté (instant serveur, direction ; `aimed` faux pour un coup de couteau)
-- lorsque HighlightService le reçoit.
function MatchRecorder.onShot(participant: Participant, t: number, direction: Vector3, aimed: boolean)
	if not session then
		return
	end
	local event: Event = { t = 0, k = E.SHOT, id = participant.id }
	if aimed then
		MatchRecordRules.setDirection(event, direction)
	end
	push(t, event)
end

-- Cette méthode permet de noter une arme sortie (outil, skin) ou rangée (outil nil) lorsque HighlightService la voit.
function MatchRecorder.onEquip(participant: Participant, toolName: string?, skinId: string?)
	if not session then
		return
	end
	push(workspace:GetServerTimeNow(), { t = 0, k = E.EQUIP, id = participant.id, tool = toolName, skin = skinId })
end

-- Cette méthode permet de noter un kill crédité lorsque HighlightService le reçoit : arme, tête, direction du tueur
-- vers la victime (ragdoll du rejeu).
function MatchRecorder.onKill(
	victim: Participant,
	killer: Participant,
	hit: { weapon: string?, headshot: boolean, at: number? }
)
	if not session then
		return
	end
	local event: Event = {
		t = 0,
		k = E.KILL,
		id = killer.id,
		victim = victim.id,
		w = hit.weapon,
		hs = hit.headshot == true,
	}
	local _, victimRoot = liveRoot(victim)
	local victimChar = Participants.characterOf(victim)
	local killerChar = Participants.characterOf(killer)
	local a = killerChar and killerChar:FindFirstChild("HumanoidRootPart")
	local b = victimRoot or (victimChar and victimChar:FindFirstChild("HumanoidRootPart"))
	if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
		MatchRecordRules.setDirection(event, b.Position - a.Position)
	end
	push(workspace:GetServerTimeNow(), event)
end

-- Cette méthode permet de noter la mort d'un participant lorsque HighlightService la reçoit (avant son kill).
function MatchRecorder.onDeath(participant: Participant)
	if not session then
		return
	end
	push(workspace:GetServerTimeNow(), { t = 0, k = E.DEATH, id = participant.id })
end

-- Cette méthode permet de noter une touche confirmée au joueur qui enregistre (hitmarker, son de touche) lorsque le
-- serveur la lui annonce ; les touches des autres joueurs ne se voient pas de son écran.
function MatchRecorder.onHitConfirm(player: Player, isKill: boolean, isHeadshot: boolean)
	local s = session
	if not s or s.owner ~= player then
		return
	end
	push(workspace:GetServerTimeNow(), {
		t = 0,
		k = E.HIT,
		id = player.UserId,
		kl = if isKill then true else nil,
		hs = if isHeadshot then true else nil,
	})
end

-- Cette méthode permet de noter un pas ou un atterrissage lorsque FootstepService le détecte (tous les participants,
-- joueur qui enregistre compris : son client joue ses pas sans passer par le serveur, mais le serveur les juge aussi).
function MatchRecorder.onFootstep(participant: Participant, kind: string)
	if not session then
		return
	end
	push(
		workspace:GetServerTimeNow(),
		{ t = 0, k = E.STEP, id = participant.id, ld = if kind == "land" then true else nil }
	)
end

-- Cette méthode permet de brancher l'enregistreur lorsque le serveur démarre : demandes du client (start, stop),
-- départ du joueur qui enregistre, échantillonnage à chaque frame.
function MatchRecorder.init(dependencies: Deps)
	deps = dependencies
	dependencies.remote.OnServerEvent:Connect(function(player, action)
		if not CheatLog.admit(player, dependencies.remote.Name, action) then
			return
		end
		if not canRecord(player) then
			return
		end
		if action == "start" then
			start(player)
		elseif action == "stop" and session and session.owner == player then
			MatchRecorder.stop(nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if session and session.owner == player then
			MatchRecorder.stop("joueur parti")
		end
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MatchRecorder

-- Journal des violations anti-triche (#170, docs/anticheat.md « Réponse aux triches »). Chaque parade y signale une
-- violation (participant, catégorie, gravité, détail) :
-- - warn limité par joueur (WARN_INTERVAL) dans la console serveur ;
-- - compteurs par joueur, catégorie et gravité, et score qui décroît dans le temps (seau qui fuit) ;
-- - kick à KICK_HIGH_COUNT violations fortes dans la session (jamais dans Studio : journal seulement) ;
-- - au départ d'un joueur qui a des violations, résumé posté au webhook en jeu publié (affiché dans Studio).
-- Les bots sont ignorés. CheatLog.admit branche la garde commune des remotes (RemoteGuard) sur ce journal.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Participants = require(ServerScriptService.Server.Participants)
local RemoteGuard = require(ServerScriptService.Server.RemoteGuard)
local Webhook = require(ServerScriptService.Server.Webhook)

local CheatLog = {}

export type Severity = "low" | "medium" | "high"

-- Gravités (docs/anticheat.md « Classer les violations ») :
-- - LOW : comptée seulement, l'action est déjà ignorée (débit dépassé, tir un peu tôt) ; faux positifs fréquents ;
-- - MEDIUM : suspecte mais explicable par le réseau (tir sans ligne de vue, téléport refusé) ; entre dans le score ;
-- - HIGH : impossible pour notre client (type d'argument, remote de debug en jeu) ; kick à KICK_HIGH_COUNT.
CheatLog.Severity = {
	LOW = "low" :: Severity,
	MEDIUM = "medium" :: Severity,
	HIGH = "high" :: Severity,
}

-- Catégories : une par parade. Les suivantes sont réservées aux issues du plan (#160) pour garder des noms stables
-- dans le journal ; toute nouvelle parade ajoute la sienne ici et dans docs/anticheat.md.
CheatLog.Category = {
	REMOTE_RATE = "RemoteRate", -- débit d'un remote dépassé (RemoteGuard)
	REMOTE_ARGS = "RemoteArgs", -- argument d'un type impossible (RemoteGuard)
	SPAWN = "Spawn", -- réapparition (#171)
	MOVEMENT = "Movement", -- vitesse, téléport, noclip, vol (#172)
	HITSCAN = "Hitscan", -- tir : origine, direction, ligne de vue, equip, chargeur (#174, #175)
	MELEE = "Melee", -- mêlée : equip (#175), orientation, ligne de vue (#176)
	-- statistiques de visée signalées (#178, AimStats) : toujours faible, chiffres bruts pour revue humaine, jamais de
	-- sanction ; un seul signalement suffit au résumé de fin de session (worthSummary)
	AIM = "Aim",
}

-- Poids d'une violation dans le score, et décroissance du score (points par seconde).
CheatLog.SCORE_WEIGHT = { low = 1, medium = 5, high = 20 } :: { [Severity]: number }
CheatLog.SCORE_DECAY = 1
-- Violations fortes dans une session avant le kick (pas 1 : marge pour nos propres bugs, visibles au journal).
CheatLog.KICK_HIGH_COUNT = 3
-- Une même source (remote, parade) ne compte qu'une violation forte pour le kick par intervalle (s) : un bug de notre
-- client sur un remote à 20 Hz (position NaN) ne doit pas expulser en 150 ms ; toutes restent au journal et au score.
CheatLog.HIGH_SOURCE_INTERVAL = 1
-- Délai minimal entre deux warns pour un même joueur (s) ; les violations entre deux warns sont comptées.
CheatLog.WARN_INTERVAL = 2
-- Longueur maximale d'un détail (octets) : un détail peut contenir une valeur envoyée par le client.
CheatLog.MAX_DETAIL = 160
CheatLog.KICK_MESSAGE = "Déconnecté : comportement anormal détecté par le serveur."
-- StringValue de ServerScriptService lus pour le résumé, dans l'ordre (cf. Webhook) : un webhook dédié, sinon celui
-- du feedback.
CheatLog.WEBHOOK_NAMES = { "CheatLogWebhookUrl", "FeedbackWebhookUrl" }
-- Attente maximale (s) des résumés encore en cours d'envoi à l'arrêt du serveur.
CheatLog.CLOSE_TIMEOUT = 20
-- Violations faibles seules à partir desquelles un résumé est envoyé (en dessous : rafales réseau, pas de bruit au
-- webhook) ; une violation moyenne ou forte suffit toujours.
CheatLog.SUMMARY_MIN_LOW = 10

local SEVERITY_RANK: { [string]: number } = { low = 1, medium = 2, high = 3 }
local SEVERITY_LABEL: { [string]: string } = { low = "faible", medium = "moyenne", high = "forte" }

export type Violation = { category: string, severity: Severity, detail: string, at: number }
export type Record = {
	id: number,
	name: string,
	counts: { [string]: { [Severity]: number } },
	total: number,
	highCount: number,
	score: number,
	scoreAt: number,
	maxScore: number,
	worst: Violation?,
	lastWarnAt: number,
	unwarned: number,
	highAt: { [string]: number },
	kicked: boolean,
	aim: string?, -- dernier relevé des statistiques de visée signalées (#178), affiché au résumé
}

local records: { [number]: Record } = {}
local guard = RemoteGuard.new()
-- Résumés en cours d'envoi (attendus à l'arrêt du serveur), remotes sans règle déjà signalés.
local pendingSummaries = 0
local warnedNoRule: { [string]: boolean } = {}
-- Rappels lancés au départ d'un joueur avant la clôture de son bilan (ex. statistiques de visée finales, #178), et
-- joueur en cours de clôture : ses signalements sont gardés même s'il n'a déjà plus de Parent.
local closingHooks: { ({ Player }) -> () } = {}
local closingPlayers: { [Player]: boolean } = {}

-- Cette méthode permet de lire l'horloge du serveur lorsqu'une violation est datée (os.clock, simulable en test).
local function now(): number
	return os.clock()
end

-- Cette méthode permet de lire le score d'un joueur à l'instant t lorsqu'il faut l'augmenter ou le résumer : le score
-- perd SCORE_DECAY points par seconde depuis la dernière violation, sans descendre sous 0.
local function decayedScore(record: Record, t: number): number
	return math.max(0, record.score - math.max(t - record.scoreAt, 0) * CheatLog.SCORE_DECAY)
end

-- Cette méthode permet de rendre un détail sûr lorsqu'il entre au journal (valeur forgée par le client) : coupé à
-- MAX_DETAIL octets sans couper un caractère, octets non UTF-8 remplacés par « ? » (le JSON du webhook l'exige).
local function clip(detail: string): string
	-- Borne le travail : un caractère commencé avant MAX_DETAIL tient dans les 4 octets suivants
	local text = string.sub(detail, 1, CheatLog.MAX_DETAIL + 4)
	local truncated = #detail > CheatLog.MAX_DETAIL
	-- Seuls les octets invalides deviennent « ? » : les accents valides autour restent
	while true do
		local len, bad = utf8.len(text)
		if len or not bad then
			break
		end
		text = string.sub(text, 1, bad - 1) .. "?" .. string.sub(text, bad + 1)
	end
	if #text > CheatLog.MAX_DETAIL then
		-- Coupe au début d'un caractère (pas sur un octet de continuation 0x80-0xBF)
		local cut = CheatLog.MAX_DETAIL + 1
		while cut > 1 and (string.byte(text, cut) :: number) >= 0x80 and (string.byte(text, cut) :: number) < 0xC0 do
			cut -= 1
		end
		text = string.sub(text, 1, cut - 1)
	end
	return if truncated then text .. "…" else text
end

-- Cette méthode permet d'écrire une violation dans la console lorsqu'elle arrive, au plus une fois par WARN_INTERVAL
-- et par joueur ; le warn suivant dit combien de violations n'ont pas été affichées entre-temps.
local function warnLimited(record: Record, violation: Violation)
	if violation.at - record.lastWarnAt < CheatLog.WARN_INTERVAL then
		record.unwarned += 1
		return
	end
	local skipped = if record.unwarned > 0 then string.format(" (+%d non affichées)", record.unwarned) else ""
	record.lastWarnAt = violation.at
	record.unwarned = 0
	warn(
		string.format(
			"[CheatLog] %s (%d) %s %s : %s — score %.0f%s",
			record.name,
			record.id,
			violation.category,
			SEVERITY_LABEL[violation.severity],
			violation.detail,
			record.score,
			skipped
		)
	)
end

-- Cette méthode permet de signaler une violation lorsqu'une parade la constate : compteurs, score, warn limité, puis
-- kick à KICK_HIGH_COUNT violations fortes comptées (une par source et par HIGH_SOURCE_INTERVAL ; source = remote ou
-- parade, la catégorie par défaut). Joueur seulement, hors Studio ; un bot est ignoré.
function CheatLog.report(
	participant: Participants.Participant,
	category: string,
	severity: Severity,
	detail: string,
	source: string?
)
	-- Bot, ou joueur déjà parti (parade différée) : rien à recréer pour lui, sauf pendant la clôture de son bilan
	local owner = participant.player
	if participant.isBot or (owner and not owner.Parent and not closingPlayers[owner]) then
		return
	end
	assert(SEVERITY_RANK[severity], "CheatLog.report : gravité inconnue " .. tostring(severity))
	local t = now()
	local record = records[participant.id]
	if not record then
		record = {
			id = participant.id,
			name = participant.name,
			counts = {},
			total = 0,
			highCount = 0,
			score = 0,
			scoreAt = t,
			maxScore = 0,
			worst = nil,
			lastWarnAt = -math.huge,
			unwarned = 0,
			highAt = {},
			kicked = false,
			aim = nil,
		}
		records[participant.id] = record
	end
	local violation: Violation = { category = category, severity = severity, detail = clip(detail), at = t }

	local perCategory = record.counts[category]
	if not perCategory then
		perCategory = { low = 0, medium = 0, high = 0 }
		record.counts[category] = perCategory
	end
	perCategory[severity] += 1
	if category == CheatLog.Category.AIM then
		-- Relevé de visée (#178) : pas une violation. Compté dans sa catégorie et gardé pour le résumé, mais hors du
		-- total, du score, de la « pire » violation et du warn limité (au plus un relevé par joueur toutes les 120 s)
		record.aim = violation.detail
		warn(string.format("[CheatLog] %s (%d) Aim : %s", record.name, record.id, violation.detail))
		return
	end
	record.total += 1
	record.score = decayedScore(record, t) + CheatLog.SCORE_WEIGHT[severity]
	record.scoreAt = t
	record.maxScore = math.max(record.maxScore, record.score)
	local worst = record.worst
	if not worst or SEVERITY_RANK[severity] > SEVERITY_RANK[worst.severity] then
		record.worst = violation
	end
	warnLimited(record, violation)

	if severity ~= CheatLog.Severity.HIGH then
		return
	end
	local key = source or category
	if t - (record.highAt[key] or -math.huge) < CheatLog.HIGH_SOURCE_INTERVAL then
		return
	end
	record.highAt[key] = t
	record.highCount += 1
	local player = participant.player
	if record.highCount < CheatLog.KICK_HIGH_COUNT or record.kicked or not player then
		return
	end
	if RunService:IsStudio() then
		-- Une seule fois, au seuil : les violations fortes suivantes restent au journal (warn limité)
		if record.highCount > CheatLog.KICK_HIGH_COUNT then
			return
		end
		warn(
			string.format(
				"[CheatLog] %s : %d violations fortes, kick ignoré dans Studio",
				record.name,
				record.highCount
			)
		)
		return
	end
	record.kicked = true
	warn(string.format("[CheatLog] %s (%d) expulsé : %d violations fortes", record.name, record.id, record.highCount))
	player:Kick(CheatLog.KICK_MESSAGE)
end

-- Cette méthode permet de lire le bilan d'un joueur lorsqu'il part ou qu'un test le vérifie : nil sans violation.
-- Le score est celui de l'instant présent (décroissance appliquée).
function CheatLog.summary(id: number): Record?
	local record = records[id]
	if not record then
		return nil
	end
	local copy = table.clone(record)
	copy.score = decayedScore(record, now())
	return copy
end

-- Cette méthode permet de contrôler un appel de remote client → serveur lorsqu'il arrive, avant son handler :
-- débit dépassé = ignoré + violation faible, type impossible = ignoré + violation forte, Instance absente = ignoré.
-- Renvoie true si le handler peut traiter l'appel.
function CheatLog.admit(player: Player, remoteName: string, ...: any): boolean
	-- Joueur déjà parti (appel traité après PlayerRemoving, ex. juste après un kick) : rien à recréer pour lui
	if not player.Parent then
		return false
	end
	local verdict, reason = guard:check(player, remoteName, now(), ...)
	if verdict == "ok" then
		return true
	end
	if verdict == "norule" then
		-- Bug de notre serveur (règle oubliée dans RemoteGuard.RULES), pas une triche : refusé sans violation
		if not warnedNoRule[remoteName] then
			warnedNoRule[remoteName] = true
			warn("[CheatLog] remote sans règle dans RemoteGuard.RULES, appels refusés : " .. remoteName)
		end
	elseif verdict == "rate" then
		CheatLog.report(
			Participants.fromPlayer(player),
			CheatLog.Category.REMOTE_RATE,
			CheatLog.Severity.LOW,
			remoteName .. " : " .. (reason or "")
		)
	elseif verdict == "malformed" then
		CheatLog.report(
			Participants.fromPlayer(player),
			CheatLog.Category.REMOTE_ARGS,
			CheatLog.Severity.HIGH,
			remoteName .. " : " .. (reason or ""),
			remoteName
		)
	end
	return false
end

-- Cette méthode permet de mettre en forme le résumé d'un joueur lorsqu'il part avec des violations : nom, UserId,
-- compteurs par catégorie, score maximal, pire violation et kick.
function CheatLog.buildEmbed(record: Record): { [string]: any }
	local fields = {}
	for category, perCategory in record.counts do
		table.insert(fields, {
			name = category,
			value = string.format(
				"forte %d · moyenne %d · faible %d",
				perCategory.high,
				perCategory.medium,
				perCategory.low
			),
			inline = true,
		})
	end
	table.sort(fields, function(a, b)
		return a.name < b.name
	end)
	local worst = record.worst
	local lines = {
		string.format(
			"%d violations, %d fortes comptées pour le kick, score max %.0f",
			record.total,
			record.highCount,
			record.maxScore
		),
	}
	if worst then
		table.insert(
			lines,
			string.format("Pire : %s %s — %s", worst.category, SEVERITY_LABEL[worst.severity], worst.detail)
		)
	end
	if record.aim then
		table.insert(lines, "Visée (dernier relevé, revue humaine) : " .. record.aim)
	end
	if record.kicked then
		table.insert(lines, "Expulsé pendant la session.")
	end
	return {
		title = "Anti-triche : " .. record.name,
		description = table.concat(lines, "\n"),
		color = 12597547,
		fields = fields,
		footer = { text = record.name .. "  |  UserId " .. record.id },
	}
end

-- Cette méthode permet de transmettre le résumé d'un joueur lorsqu'il part : webhook en jeu publié, console dans
-- Studio. Bloquant (requête HTTP) : à lancer dans son propre fil.
local function sendSummary(record: Record)
	if RunService:IsStudio() then
		print(string.format("[CheatLog] résumé de %s : %s", record.name, CheatLog.buildEmbed(record).description))
		return
	end
	local url = Webhook.url(table.unpack(CheatLog.WEBHOOK_NAMES))
	if not url then
		warn("[CheatLog] aucun webhook configuré, résumé de " .. record.name .. " perdu")
		return
	end
	local ok, err = Webhook.post(url, CheatLog.buildEmbed(record))
	if not ok then
		warn("[CheatLog] envoi du résumé impossible :", err)
	end
end

-- Cette méthode permet d'envoyer un résumé en tenant le compte des envois en cours lorsqu'un joueur part, pour que
-- l'arrêt du serveur les attende.
local function trackedSummary(record: Record)
	pendingSummaries += 1
	local ok, err = pcall(sendSummary, record)
	pendingSummaries -= 1
	if not ok then
		warn("[CheatLog] résumé de " .. record.name .. " perdu :", err)
	end
end

-- Cette méthode permet de décider si un bilan mérite un résumé lorsque le joueur part : une violation moyenne ou
-- forte, au moins SUMMARY_MIN_LOW violations faibles, ou un signalement des statistiques de visée (#178).
function CheatLog.worthSummary(record: Record): boolean
	local worst = record.worst
	return (worst ~= nil and SEVERITY_RANK[worst.severity] >= SEVERITY_RANK.medium)
		or record.total >= CheatLog.SUMMARY_MIN_LOW
		or record.aim ~= nil
end

-- Cette méthode permet d'inscrire un rappel lancé au départ de joueurs (un seul, ou tous ensemble à l'arrêt du
-- serveur), avant la clôture de leur bilan, lorsqu'une parade veut y signaler un dernier relevé (visée, #178).
function CheatLog.onClosing(hook: ({ Player }) -> ())
	table.insert(closingHooks, hook)
end

-- Cette méthode permet de lancer les rappels de clôture de joueurs qui partent : leurs report y sont gardés même sans
-- Parent (PlayerRemoving différé) ; une erreur n'empêche ni les rappels suivants ni le résumé.
local function runClosingHooks(players: { Player })
	for _, player in players do
		closingPlayers[player] = true
	end
	for _, hook in closingHooks do
		local ok, err = pcall(hook, players)
		if not ok then
			warn("[CheatLog] rappel de clôture en échec :", err)
		end
	end
	table.clear(closingPlayers)
end

-- Cette méthode permet d'oublier un joueur qui part lorsque son bilan est clos : seaux de la garde libérés, résumé
-- envoyé si le bilan le mérite (worthSummary).
function CheatLog.onPlayerRemoving(player: Player)
	runClosingHooks({ player })
	guard:forget(player)
	local record = records[player.UserId]
	records[player.UserId] = nil
	if record and CheatLog.worthSummary(record) then
		task.spawn(trackedSummary, record)
	end
end

-- Cette méthode permet de brancher le départ des joueurs lorsque le serveur démarre ; à l'arrêt, les résumés des
-- joueurs encore là sont envoyés et tous les envois attendus (CLOSE_TIMEOUT au plus).
function CheatLog.init()
	Players.PlayerRemoving:Connect(CheatLog.onPlayerRemoving)
	game:BindToClose(function()
		-- Joueurs encore là à l'arrêt : leur PlayerRemoving peut arriver après ce rappel. Tous ensemble, pour que chaque
		-- parade les juge contre la même population
		runClosingHooks(Players:GetPlayers())
		for id, record in records do
			records[id] = nil
			if CheatLog.worthSummary(record) then
				task.spawn(trackedSummary, record)
			end
		end
		local deadline = os.clock() + CheatLog.CLOSE_TIMEOUT
		while pendingSummaries > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return CheatLog

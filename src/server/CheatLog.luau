-- Journal des violations anti-triche (#170, docs/anticheat.md « Réponse aux triches »). Chaque parade y signale une
-- violation (participant, catégorie, gravité, détail, contrôle) :
-- - warn limité par joueur (WARN_INTERVAL) dans la console serveur ;
-- - compteurs par joueur, catégorie et gravité, et par contrôle (#297), score qui décroît dans le temps (seau qui fuit) ;
-- - kick à KICK_HIGH_COUNT violations fortes dans la session (jamais dans Studio : journal seulement) ;
-- - au départ d'un joueur qui a des violations, résumé posté au webhook en jeu publié (affiché dans Studio).
-- Mesure des faux positifs (#297) : dénominateurs par joueur (tirs, coups, positions jugés, CheatLog.judged), ping
-- échantillonné, et relevé agrégé du serveur toutes les REPORT_INTERVAL secondes et à l'arrêt (taux par contrôle).
-- Les bots sont ignorés. CheatLog.admit branche la garde commune des remotes (RemoteGuard) sur ce journal.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CheatTypes = require(ServerScriptService.Server.CheatTypes)
local Participants = require(ServerScriptService.Server.Participants)
local RemoteGuard = require(ServerScriptService.Server.RemoteGuard)
local Webhook = require(ServerScriptService.Server.Webhook)

local CheatLog = {}

export type Severity = CheatTypes.Severity

-- Gravités et catégories : définies dans CheatTypes (une seule source, lisible par les règles pures sans services),
-- ré-exportées ici pour les appelants du journal. Toute nouvelle parade ajoute sa catégorie dans CheatTypes.
CheatLog.Severity = CheatTypes.Severity
CheatLog.Category = CheatTypes.Category

-- Ce qu'une parade a jugé (#297), dénominateur des taux : une touche de tir, un coup de mêlée, un paquet de position.
export type JudgedKind = "shot" | "melee" | "position"
CheatLog.Judged = { SHOT = "shot" :: JudgedKind, MELEE = "melee" :: JudgedKind, POSITION = "position" :: JudgedKind }
-- Dénominateur de chaque catégorie : ses contrôles jugent une à une les touches, coups ou positions. Les autres
-- catégories (garde des remotes, apparition, inventaire, visée) n'ont pas de dénominateur : nombres bruts.
CheatLog.DENOMINATOR = {
	[CheatTypes.Category.HITSCAN] = "shot",
	[CheatTypes.Category.MELEE] = "melee",
	[CheatTypes.Category.MOVEMENT] = "position",
} :: { [string]: JudgedKind }
-- Contrôles qui ne jugent pas chaque élément de leur catégorie : le vide est jugé par passage de boucle, pas par
-- paquet ; le taux de touches orphelines (#246) est signalé une fois par palier d'orphelines, pas par touche (le taux
-- par touche est celui de Hitscan:shotLink).
CheatLog.NO_DENOMINATOR = { ["Movement:void"] = true, ["Hitscan:orphanRate"] = true } :: { [string]: boolean }

-- Poids d'une violation dans le score, et décroissance du score (points par seconde).
CheatLog.SCORE_WEIGHT = { low = 1, medium = 5, high = 20 } :: { [Severity]: number }
CheatLog.SCORE_DECAY = 1
-- Violations fortes dans une session avant le kick (pas 1 : marge pour nos propres bugs, visibles au journal).
CheatLog.KICK_HIGH_COUNT = 3
-- Un même contrôle (remote, parade) ne compte qu'une violation forte pour le kick par intervalle (s) : un bug de notre
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
-- StringValue lus pour le relevé agrégé (#297) : le webhook dédié seulement. Un relevé part toutes les REPORT_INTERVAL
-- dès qu'un joueur est en jeu : sans webhook dédié, il reste en console plutôt que d'encombrer le salon du feedback.
CheatLog.REPORT_WEBHOOK_NAMES = { "CheatLogWebhookUrl" }
-- Essais d'envoi au webhook, et attente (s) multipliée par le numéro d'essai entre deux ; après le dernier échec, le
-- message est écrit en entier dans la console serveur (repli : il n'est jamais perdu en silence).
CheatLog.WEBHOOK_ATTEMPTS = 3
CheatLog.WEBHOOK_RETRY_DELAY = 2
-- Attente maximale (s) des résumés encore en cours d'envoi à l'arrêt du serveur.
CheatLog.CLOSE_TIMEOUT = 20
-- Violations faibles seules à partir desquelles un résumé est envoyé (en dessous : rafales réseau, pas de bruit au
-- webhook) ; une violation moyenne ou forte suffit toujours.
CheatLog.SUMMARY_MIN_LOW = 10
-- Période (s) du relevé agrégé du serveur (#297) ; aussi émis à l'arrêt, et à la demande par l'attribut Workspace
-- REPORT_ATTRIBUTE (true, remis à nil après le relevé : vérification en Studio sans attendre la période).
CheatLog.REPORT_INTERVAL = 600
CheatLog.REPORT_ATTRIBUTE = "CheatLogReport"
-- Période (s) d'échantillonnage du ping des joueurs (Player:GetNetworkPing), et largeur (ms) des classes de
-- l'histogramme qui donne la médiane sans garder chaque mesure.
CheatLog.PING_SAMPLE_INTERVAL = 5
CheatLog.PING_BUCKET_MS = 10
-- Limites d'un embed Discord (caractères) : valeur d'un champ, description. Au-delà le webhook répond 400 à chaque
-- essai : les lignes en trop sont remplacées par « … (+N) ».
CheatLog.MAX_FIELD_VALUE = 1000
CheatLog.MAX_DESCRIPTION = 3800
-- Limite de l'embed entier (titre, description, champs, pied : 6000 chez Discord, marge comprise).
CheatLog.MAX_EMBED_TOTAL = 5800

local SEVERITY_RANK: { [string]: number } = { low = 1, medium = 2, high = 3 }
local SEVERITY_LABEL: { [string]: string } = { low = "faible", medium = "moyenne", high = "forte" }
local JUDGED_LABEL: { [string]: string } = { shot = "touches", melee = "coups", position = "positions" }
local JUDGED_ORDER: { JudgedKind } = { "shot", "melee", "position" }

-- Histogramme de ping (ms) : classes de PING_BUCKET_MS, nombre de mesures, maximum exact.
export type PingHistogram = { buckets: { [number]: number }, n: number, max: number }
-- Ping résumé : médiane (à la classe près) et maximum (ms), nombre de mesures ; nil sans mesure.
export type PingStats = { medianMs: number, maxMs: number, samples: number }
export type Violation = { category: string, check: string, severity: Severity, detail: string, at: number }
export type Record = {
	id: number,
	name: string,
	counts: { [string]: { [Severity]: number } },
	-- Par contrôle (« Catégorie:contrôle », ou la catégorie seule sans contrôle nommé), puis par gravité (#297)
	checks: { [string]: { [Severity]: number } },
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
	-- Posés par summary et à la clôture (#297) : dénominateurs et ping de la session du joueur
	judged: { [string]: number }?,
	ping: PingStats?,
}
-- Session d'un joueur, avec ou sans violation (#297) : ce que les parades ont jugé, et son ping.
type Session = { judged: { [string]: number }, ping: PingHistogram }
-- Période du relevé agrégé : violations par contrôle, relevés de visée signalés (#178, pas des violations), jugés,
-- ping et joueurs vus (avec ou sans violation).
export type Period = {
	startedAt: number,
	checks: { [string]: number },
	aim: number,
	judged: { [string]: number },
	ping: PingHistogram,
	players: { [number]: boolean },
	flagged: { [number]: boolean },
}

local records: { [number]: Record } = {}
local sessions: { [number]: Session } = {}
local guard = RemoteGuard.new()
-- Envois en cours (résumés, relevés : attendus à l'arrêt du serveur), remotes sans règle déjà signalés.
local pendingSends = 0
local warnedNoRule: { [string]: boolean } = {}
-- Arrêt du serveur commencé (BindToClose) : bilans clos et dernier relevé émis, plus rien n'est compté (un départ
-- traité après ne recrée pas un bilan sans session ni un second résumé).
local closed = false
-- Rappels lancés au départ d'un joueur avant la clôture de son bilan (ex. statistiques de visée finales, #178), et
-- joueur en cours de clôture : ses signalements sont gardés même s'il n'a déjà plus de Parent.
local closingHooks: { ({ Player }, boolean) -> () } = {}
local closingPlayers: { [Player]: boolean } = {}
-- Joueurs dont le bilan est clos (onPlayerRemoving) : PlayerRemoving arrive quand Parent est encore Players, un paquet
-- ou une parade traités juste après ne doivent pas recréer de bilan ni de session (clés faibles : rien ne fuit).
local departed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Cette méthode permet de lire l'horloge du serveur lorsqu'une violation est datée (os.clock, simulable en test).
local function now(): number
	return os.clock()
end

-- Cette méthode permet de créer un histogramme de ping vide lorsqu'une session ou une période commence.
local function newPing(): PingHistogram
	return { buckets = {}, n = 0, max = 0 }
end

-- Cette méthode permet de créer une période vide du relevé agrégé lorsque le serveur démarre ou qu'un relevé est émis.
local function newPeriod(t: number): Period
	return { startedAt = t, checks = {}, aim = 0, judged = {}, ping = newPing(), players = {}, flagged = {} }
end

local period: Period = newPeriod(now())

-- Cette méthode permet d'ajouter une mesure de ping (ms) à un histogramme lorsqu'un échantillon arrive.
local function addPing(ping: PingHistogram, ms: number)
	local bucket = math.floor(ms / CheatLog.PING_BUCKET_MS)
	ping.buckets[bucket] = (ping.buckets[bucket] or 0) + 1
	ping.n += 1
	ping.max = math.max(ping.max, ms)
end

-- Cette méthode permet de résumer un histogramme de ping lorsqu'un bilan ou un relevé l'affiche : médiane au milieu
-- de sa classe (bornée par le maximum), maximum exact ; nil sans mesure.
function CheatLog.pingStats(ping: PingHistogram): PingStats?
	if ping.n == 0 then
		return nil
	end
	local keys = {}
	for bucket in ping.buckets do
		table.insert(keys, bucket)
	end
	table.sort(keys)
	local target, seen = math.ceil(ping.n / 2), 0
	local median = 0
	for _, bucket in keys do
		seen += ping.buckets[bucket]
		if seen >= target then
			median = math.min((bucket + 0.5) * CheatLog.PING_BUCKET_MS, ping.max)
			break
		end
	end
	return { medianMs = median, maxMs = ping.max, samples = ping.n }
end

-- Cette méthode permet de nommer le contrôle d'une violation lorsqu'elle est comptée : « Catégorie:contrôle », ou la
-- catégorie seule si la parade ne nomme pas de contrôle (ou le nomme comme sa catégorie).
local function checkKey(category: string, check: string?): string
	if check == nil or check == "" or check == category then
		return category
	end
	return category .. ":" .. check
end

-- Cette méthode permet de lire le dénominateur d'un contrôle lorsqu'un taux est calculé : touches, coups ou positions
-- jugés selon sa catégorie ; nil pour un contrôle sans dénominateur (garde des remotes, vide…).
function CheatLog.denominatorOf(key: string): JudgedKind?
	if CheatLog.NO_DENOMINATOR[key] then
		return nil
	end
	local category = string.match(key, "^([^:]+)") or key
	return CheatLog.DENOMINATOR[category]
end

-- Cette méthode permet de savoir si un participant est suivi par le journal lorsqu'une parade le signale : joueur
-- présent (ou en cours de clôture), jamais un bot ni un joueur au bilan déjà clos, et rien une fois l'arrêt du
-- serveur clos (closed).
local function isTracked(participant: Participants.Participant): boolean
	if closed or participant.isBot then
		return false
	end
	local owner = participant.player
	if not owner or closingPlayers[owner] then
		return true
	end
	return owner.Parent ~= nil and not departed[owner]
end

-- Cette méthode permet de lire le ping d'un joueur (s, Player:GetNetworkPing) lorsqu'une parade le borne (#214) ou
-- que le journal l'échantillonne (#297) : une seule lecture pour les deux ; nil en cas d'erreur du moteur.
function CheatLog.pingOf(player: Player): number?
	local ok, ping = pcall(player.GetNetworkPing, player)
	return if ok and type(ping) == "number" then ping else nil
end

-- Cette méthode permet de lire la session d'un joueur suivi lorsqu'une parade juge ou qu'un ping arrive ; créée vide.
local function sessionOf(participant: Participants.Participant): Session
	local session = sessions[participant.id]
	if not session then
		session = { judged = {}, ping = newPing() }
		sessions[participant.id] = session
	end
	return session
end

-- Cette méthode permet de compter un élément jugé par une parade lorsqu'elle l'examine (#297) : touche de tir, coup de
-- mêlée ou paquet de position d'un joueur, dénominateur des taux de violations. Bot ou joueur parti ignoré.
function CheatLog.judged(participant: Participants.Participant, kind: JudgedKind)
	if not isTracked(participant) then
		return
	end
	local session = sessionOf(participant)
	session.judged[kind] = (session.judged[kind] or 0) + 1
	period.judged[kind] = (period.judged[kind] or 0) + 1
	period.players[participant.id] = true
end

-- Cette méthode permet de noter un échantillon de ping (s, Player:GetNetworkPing) d'un joueur lorsque la boucle
-- d'échantillonnage passe (#297) : histogramme de sa session et de la période. Valeur non finie ou négative ignorée.
function CheatLog.notePing(participant: Participants.Participant, seconds: number)
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
		return
	end
	if not isTracked(participant) then
		return
	end
	local ms = seconds * 1000
	addPing(sessionOf(participant).ping, ms)
	addPing(period.ping, ms)
	period.players[participant.id] = true
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

-- Cette méthode permet de choisir la violation la plus parlante d'un bilan lorsqu'une nouvelle arrive (#297) : la plus
-- grave ; à gravité égale, celle du contrôle qui en compte le plus à cette gravité (une répétition dit plus qu'un
-- incident isolé), la plus récente de ce contrôle en cas d'égalité.
local function isMoreTelling(record: Record, candidate: Violation, current: Violation?): boolean
	if not current then
		return true
	end
	local rank, currentRank = SEVERITY_RANK[candidate.severity], SEVERITY_RANK[current.severity]
	if rank ~= currentRank then
		return rank > currentRank
	end
	local count = record.checks[candidate.check][candidate.severity]
	local currentCount = record.checks[current.check][current.severity]
	return count >= currentCount
end

-- Cette méthode permet de signaler une violation lorsqu'une parade la constate : compteurs (catégorie, contrôle),
-- score, warn limité, puis kick à KICK_HIGH_COUNT violations fortes comptées (une par contrôle et par
-- HIGH_SOURCE_INTERVAL). check = nom du contrôle (#297 : contrôle de ShotRules, règle de déplacement, remote de la
-- garde…), compté sous « Catégorie:check » ; sans lui, la catégorie seule. Joueur seulement, hors Studio ; bot ignoré.
function CheatLog.report(
	participant: Participants.Participant,
	category: string,
	severity: Severity,
	detail: string,
	check: string?
)
	-- Bot, ou joueur déjà parti (parade différée) : rien à recréer pour lui, sauf pendant la clôture de son bilan
	if not isTracked(participant) then
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
			checks = {},
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
	local key = checkKey(category, check)
	local violation: Violation =
		{ category = category, check = key, severity = severity, detail = clip(detail), at = t }

	local perCategory = record.counts[category]
	if not perCategory then
		perCategory = { low = 0, medium = 0, high = 0 }
		record.counts[category] = perCategory
	end
	perCategory[severity] += 1
	local perCheck = record.checks[key]
	if not perCheck then
		perCheck = { low = 0, medium = 0, high = 0 }
		record.checks[key] = perCheck
	end
	perCheck[severity] += 1
	period.players[participant.id] = true
	if category == CheatLog.Category.AIM then
		-- Relevé de visée (#178) : pas une violation. Compté dans sa catégorie et gardé pour le résumé, mais hors du
		-- total, du score, de la « pire » violation, du warn limité (au plus un relevé par joueur toutes les 120 s) et
		-- des contrôles en violation du relevé agrégé (une ligne à part)
		record.aim = violation.detail
		period.aim += 1
		warn(string.format("[CheatLog] %s (%d) Aim : %s", record.name, record.id, violation.detail))
		return
	end
	period.checks[key] = (period.checks[key] or 0) + 1
	period.flagged[participant.id] = true
	record.total += 1
	record.score = decayedScore(record, t) + CheatLog.SCORE_WEIGHT[severity]
	record.scoreAt = t
	record.maxScore = math.max(record.maxScore, record.score)
	if isMoreTelling(record, violation, record.worst) then
		record.worst = violation
	end
	warnLimited(record, violation)

	if severity ~= CheatLog.Severity.HIGH then
		return
	end
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

-- Cette méthode permet de joindre à une copie du bilan les dénominateurs et le ping de la session du joueur lorsqu'il
-- est lu ou clos (#297).
local function withSession(record: Record, session: Session?): Record
	local copy = table.clone(record)
	copy.judged = if session then table.clone(session.judged) else {}
	copy.ping = if session then CheatLog.pingStats(session.ping) else nil
	return copy
end

-- Cette méthode permet de lire le bilan d'un joueur lorsqu'il part ou qu'un test le vérifie : nil sans violation.
-- Le score est celui de l'instant présent (décroissance appliquée) ; dénominateurs et ping de la session joints.
function CheatLog.summary(id: number): Record?
	local record = records[id]
	if not record then
		return nil
	end
	local copy = withSession(record, sessions[id])
	copy.score = decayedScore(record, now())
	return copy
end

-- Cette méthode permet de lire ce qu'une parade a jugé pour un joueur lorsqu'un test ou un bilan le vérifie (#297),
-- avec ou sans violation : nombres par sorte (touches, coups, positions) et ping ; nil sans session.
function CheatLog.session(id: number): { judged: { [string]: number }, ping: PingStats? }?
	local session = sessions[id]
	if not session then
		return nil
	end
	return { judged = table.clone(session.judged), ping = CheatLog.pingStats(session.ping) }
end

-- Cette méthode permet de contrôler un appel de remote client → serveur lorsqu'il arrive, avant son handler :
-- débit dépassé = ignoré + violation faible, type impossible = ignoré + violation forte, Instance absente = ignoré.
-- Le remote est le contrôle (#297). Renvoie true si le handler peut traiter l'appel.
function CheatLog.admit(player: Player, remoteName: string, ...: any): boolean
	-- Joueur déjà parti (appel traité après PlayerRemoving, ex. juste après un kick) : rien à recréer pour lui, pas même
	-- les seaux de la garde
	if not player.Parent or departed[player] then
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
			remoteName .. " : " .. (reason or ""),
			remoteName
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

-- Cette méthode permet d'écrire un taux de violations lorsqu'un résumé ou un relevé l'affiche : « N / D touches
-- (x,xx %) », ou le nombre seul sans dénominateur connu.
local function rateText(count: number, kind: JudgedKind?, judged: { [string]: number }): string
	if not kind then
		return tostring(count)
	end
	local total = judged[kind] or 0
	if total == 0 then
		return string.format("%d / 0 %s", count, JUDGED_LABEL[kind])
	end
	return string.format("%d / %d %s (%.2f %%)", count, total, JUDGED_LABEL[kind], 100 * count / total)
end

-- Cette méthode permet d'écrire les jugés d'une session ou d'une période lorsqu'un résumé ou un relevé les affiche :
-- « 120 touches · 15 coups · 4300 positions ».
local function judgedText(judged: { [string]: number }): string
	local parts = {}
	for _, kind in JUDGED_ORDER do
		table.insert(parts, string.format("%d %s", judged[kind] or 0, JUDGED_LABEL[kind]))
	end
	return table.concat(parts, " · ")
end

-- Cette méthode permet d'écrire un ping résumé lorsqu'un résumé ou un relevé l'affiche.
local function pingText(ping: PingStats?): string
	if not ping then
		return "Ping : aucune mesure"
	end
	return string.format("Ping : médiane %.0f ms, max %.0f ms (%d mesures)", ping.medianMs, ping.maxMs, ping.samples)
end

-- Cette méthode permet de lister les clés d'une table triées lorsqu'un résumé ou un relevé doit être stable.
local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Cette méthode permet de mesurer un texte d'embed (caractères, comme Discord) lorsqu'on vérifie ses limites.
local function textLength(text: string): number
	return utf8.len(text) or #text
end

-- Cette méthode permet d'assembler des lignes sous une longueur maximale (caractères) lorsqu'un champ ou une
-- description d'embed doit tenir dans les limites de Discord : les lignes en trop deviennent « … (+N) ».
function CheatLog.joinCapped(lines: { string }, max: number): string
	local kept, size = {}, 0
	for i, line in lines do
		-- Dernière ligne : jusqu'à max ; avant elle, place gardée pour « … (+N) » (au plus une douzaine de caractères)
		local cost = textLength(line) + (if i > 1 then 1 else 0)
		local limit = if i == #lines then max else max - 16
		if size + cost > limit then
			table.insert(kept, string.format("… (+%d)", #lines - i + 1))
			return table.concat(kept, "\n")
		end
		table.insert(kept, line)
		size += cost
	end
	return table.concat(kept, "\n")
end

-- Cette méthode permet de mettre en forme le résumé d'un joueur lorsqu'il part avec des violations : nom, UserId,
-- compteurs par catégorie et par contrôle (taux sur ses jugés), jugés, ping, score maximal, pire violation et kick.
-- Champs bornés pour que l'embed entier tienne sous MAX_EMBED_TOTAL (la place est partagée entre les champs).
function CheatLog.buildEmbed(record: Record): { [string]: any }
	local judged = record.judged or {}
	local checkKeys = sortedKeys(record.checks or {})
	local fields = {}
	for category, perCategory in record.counts do
		-- Relevés de visée (#178) : pas des violations, ne pas les présenter comme des « faibles »
		local lines = {
			if category == CheatLog.Category.AIM
				then string.format("%d relevé(s) signalé(s), revue humaine", perCategory.low)
				else string.format(
					"forte %d · moyenne %d · faible %d",
					perCategory.high,
					perCategory.medium,
					perCategory.low
				),
		}
		-- Un contrôle par ligne (#297), avec son taux sur les jugés du joueur
		local prefix = category .. ":"
		for _, key in checkKeys do
			if string.sub(key, 1, #prefix) == prefix then
				local perCheck = record.checks[key]
				local count = perCheck.low + perCheck.medium + perCheck.high
				table.insert(
					lines,
					string.sub(key, #prefix + 1) .. " " .. rateText(count, CheatLog.denominatorOf(key), judged)
				)
			end
		end
		table.insert(fields, { name = category, lines = lines, inline = true })
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
		"Jugés : " .. judgedText(judged),
		pingText(record.ping),
	}
	if worst then
		table.insert(
			lines,
			string.format("Pire : %s %s — %s", worst.check, SEVERITY_LABEL[worst.severity], worst.detail)
		)
	end
	if record.aim then
		table.insert(lines, "Visée (dernier relevé, revue humaine) : " .. record.aim)
	end
	if record.kicked then
		table.insert(lines, "Expulsé pendant la session.")
	end
	local title = "Anti-triche : " .. record.name
	local description = CheatLog.joinCapped(lines, CheatLog.MAX_DESCRIPTION)
	local footer = record.name .. "  |  UserId " .. record.id
	-- Place laissée aux valeurs des champs : le total de l'embed, moins le reste, partagé à parts égales
	local budget = CheatLog.MAX_EMBED_TOTAL - textLength(title) - textLength(description) - textLength(footer)
	for _, field in fields do
		budget -= textLength(field.name)
	end
	-- Plancher : au moins la ligne des gravités et « … (+N) » par champ (description bornée, au plus 8 catégories)
	local perField = math.clamp(math.floor(budget / math.max(#fields, 1)), 64, CheatLog.MAX_FIELD_VALUE)
	for _, field in fields do
		field.value = CheatLog.joinCapped(field.lines, perField)
		field.lines = nil
	end
	return {
		title = title,
		description = description,
		color = 12597547,
		fields = fields,
		footer = { text = footer },
	}
end

-- Cette méthode permet de mettre en forme le relevé agrégé d'une période lorsqu'il est émis (#297) : joueurs vus
-- (avec ou sans violation), jugés, ping, puis chaque contrôle en violation avec son taux sur les jugés de tous.
-- Un contrôle absent n'a aucune violation sur la période.
function CheatLog.buildReport(p: Period, t: number, reason: string): { [string]: any }
	local players, flagged = 0, 0
	for id in p.players do
		players += 1
		if p.flagged[id] then
			flagged += 1
		end
	end
	local lines = {
		string.format("Période de %.1f min (%s)", math.max(t - p.startedAt, 0) / 60, reason),
		string.format("Joueurs : %d, dont %d avec violation", players, flagged),
		"Jugés : " .. judgedText(p.judged),
		pingText(CheatLog.pingStats(p.ping)),
	}
	if p.aim > 0 then
		-- Statistiques de visée (#178) : pas des violations, à part des contrôles
		table.insert(lines, string.format("Relevés de visée signalés : %d (revue humaine)", p.aim))
	end
	local keys = sortedKeys(p.checks)
	if #keys == 0 then
		table.insert(lines, "Aucune violation.")
	end
	for _, key in keys do
		table.insert(lines, key .. " : " .. rateText(p.checks[key], CheatLog.denominatorOf(key), p.judged))
	end
	local jobId = (game :: any).JobId
	return {
		title = "Anti-triche : relevé du serveur",
		description = CheatLog.joinCapped(lines, CheatLog.MAX_DESCRIPTION),
		color = 5793266,
		footer = { text = "Serveur " .. (if type(jobId) == "string" and jobId ~= "" then jobId else "?") },
	}
end

-- Cette méthode permet d'écrire un embed en texte lorsqu'il va dans la console (Studio, ou repli après l'échec du
-- webhook) : titre, description, champs, pied.
function CheatLog.consoleText(embed: { [string]: any }): string
	local lines = { embed.title, embed.description }
	for _, field in embed.fields or {} do
		table.insert(lines, field.name .. " : " .. (string.gsub(field.value, "\n", " ; ")))
	end
	if embed.footer then
		table.insert(lines, embed.footer.text)
	end
	return table.concat(lines, "\n")
end

-- Cette méthode permet de transmettre un embed lorsqu'un résumé ou un relevé est prêt : console dans Studio, sinon
-- webhook avec nouveaux essais (WEBHOOK_ATTEMPTS), puis repli sur la console en entier si l'envoi échoue ou qu'aucun
-- webhook n'est configuré parmi names (StringValue, dans l'ordre). optional : un webhook absent est un réglage prévu
-- (relevé sans webhook dédié), le message va en console par print, sans avertissement. Bloquant : dans son propre fil.
local function deliver(embed: { [string]: any }, label: string, names: { string }, optional: boolean)
	if RunService:IsStudio() then
		print(string.format("[CheatLog] %s :\n%s", label, CheatLog.consoleText(embed)))
		return
	end
	local url = Webhook.url(table.unpack(names))
	if not url and optional then
		print(string.format("[CheatLog] %s :\n%s", label, CheatLog.consoleText(embed)))
		return
	end
	if url then
		local ok, err, attempts =
			Webhook.postWithRetry(url, embed, CheatLog.WEBHOOK_ATTEMPTS, CheatLog.WEBHOOK_RETRY_DELAY)
		if ok then
			return
		end
		warn(string.format("[CheatLog] envoi au webhook impossible après %d essai(s) : %s", attempts, tostring(err)))
	else
		warn("[CheatLog] aucun webhook configuré")
	end
	warn(string.format("[CheatLog] %s (repli console) :\n%s", label, CheatLog.consoleText(embed)))
end

-- Cette méthode permet de construire puis transmettre un embed en tenant le compte des envois en cours lorsqu'un
-- résumé ou un relevé part, pour que l'arrêt du serveur les attende ; une erreur est écrite avec son libellé.
local function tracked(label: string, build: () -> { [string]: any }, names: { string }, optional: boolean)
	pendingSends += 1
	local ok, err = pcall(function()
		deliver(build(), label, names, optional)
	end)
	pendingSends -= 1
	if not ok then
		warn("[CheatLog] " .. label .. " perdu :", err)
	end
end

-- Cette méthode permet d'envoyer le résumé d'un joueur dans son propre fil lorsqu'il part (webhook dédié, sinon
-- celui du feedback).
local function trackedSummary(record: Record)
	tracked("résumé de " .. record.name, function()
		return CheatLog.buildEmbed(record)
	end, CheatLog.WEBHOOK_NAMES, false)
end

-- Cette méthode permet d'envoyer un relevé agrégé dans son propre fil lorsqu'il est émis (webhook dédié seulement ;
-- sans lui, console sans avertissement).
local function trackedReport(embed: { [string]: any })
	tracked("relevé du serveur", function()
		return embed
	end, CheatLog.REPORT_WEBHOOK_NAMES, true)
end

-- Cette méthode permet d'émettre le relevé agrégé de la période écoulée lorsque REPORT_INTERVAL est passé, à l'arrêt
-- ou à la demande (#297), puis d'ouvrir la période suivante. Rien n'est émis pour une période sans joueur ni
-- violation. Renvoie l'embed émis (nil sinon).
function CheatLog.flushReport(reason: string): { [string]: any }?
	local p = period
	local t = now()
	period = newPeriod(t)
	if next(p.players) == nil then
		return nil
	end
	local embed = CheatLog.buildReport(p, t, reason)
	task.spawn(trackedReport, embed)
	return embed
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
-- serveur : shuttingDown), avant la clôture de leur bilan, lorsqu'une parade veut y signaler un dernier relevé (#178).
function CheatLog.onClosing(hook: ({ Player }, boolean) -> ())
	table.insert(closingHooks, hook)
end

-- Cette méthode permet de lancer les rappels de clôture de joueurs qui partent : leurs report y sont gardés même sans
-- Parent (PlayerRemoving différé) ; une erreur n'empêche ni les rappels suivants ni le résumé.
local function runClosingHooks(players: { Player }, shuttingDown: boolean)
	for _, player in players do
		closingPlayers[player] = true
	end
	for _, hook in closingHooks do
		local ok, err = pcall(hook, players, shuttingDown)
		if not ok then
			warn("[CheatLog] rappel de clôture en échec :", err)
		end
	end
	table.clear(closingPlayers)
end

-- Cette méthode permet d'oublier un joueur qui part lorsque son bilan est clos : seaux de la garde libérés, résumé
-- envoyé si le bilan le mérite (worthSummary), avec ses jugés et son ping ; ce qu'il a fait reste au relevé agrégé.
function CheatLog.onPlayerRemoving(player: Player)
	departed[player] = true
	guard:forget(player)
	-- Après l'arrêt (close) : bilans déjà clos et rappels déjà lancés pour tous
	if closed then
		return
	end
	runClosingHooks({ player }, false)
	local record = records[player.UserId]
	local session = sessions[player.UserId]
	records[player.UserId] = nil
	sessions[player.UserId] = nil
	if record and CheatLog.worthSummary(record) then
		task.spawn(trackedSummary, withSession(record, session))
	end
end

-- Cette méthode permet d'échantillonner le ping de tous les joueurs lorsque la boucle du journal passe (#297) ; une
-- erreur du moteur sur un joueur n'arrête pas les autres.
local function samplePings()
	for _, player in Players:GetPlayers() do
		local ping = CheatLog.pingOf(player)
		if ping then
			CheatLog.notePing(Participants.fromPlayer(player), ping)
		end
	end
end

-- Cette méthode permet de faire tourner la boucle du journal lorsque le serveur démarre : ping échantillonné toutes les
-- PING_SAMPLE_INTERVAL secondes, relevé agrégé toutes les REPORT_INTERVAL ; une erreur n'arrête pas la boucle.
local function runSamplingLoop()
	while true do
		task.wait(CheatLog.PING_SAMPLE_INTERVAL)
		local ok, err = pcall(samplePings)
		if not ok then
			warn("[CheatLog] mesure du ping en échec :", err)
		end
		-- Mesuré depuis le début de la période : un relevé à la demande la redémarre aussi
		if now() - period.startedAt >= CheatLog.REPORT_INTERVAL then
			ok, err = pcall(CheatLog.flushReport, "périodique")
			if not ok then
				warn("[CheatLog] relevé périodique en échec :", err)
			end
		end
	end
end

-- Cette méthode permet d'émettre le relevé à la demande lorsque l'attribut Workspace REPORT_ATTRIBUTE passe à true
-- (vérification en Studio, contexte Server) ; l'attribut est remis à nil.
local function onReportRequested()
	if workspace:GetAttribute(CheatLog.REPORT_ATTRIBUTE) ~= true then
		return
	end
	workspace:SetAttribute(CheatLog.REPORT_ATTRIBUTE, nil)
	if not CheatLog.flushReport("à la demande") then
		print("[CheatLog] relevé du serveur : rien à relever sur la période")
	end
end

-- Cette méthode permet de brancher le départ des joueurs, l'échantillonnage du ping et le relevé périodique lorsque
-- le serveur démarre ; à l'arrêt, les résumés des joueurs encore là et le dernier relevé sont envoyés, et tous les
-- envois attendus (CLOSE_TIMEOUT au plus).
function CheatLog.init()
	Players.PlayerRemoving:Connect(CheatLog.onPlayerRemoving)
	task.spawn(runSamplingLoop)
	workspace:GetAttributeChangedSignal(CheatLog.REPORT_ATTRIBUTE):Connect(onReportRequested)
	game:BindToClose(CheatLog.close)
end

-- Cette méthode permet de clore le journal lorsque le serveur s'arrête (BindToClose) : rappels de clôture des joueurs
-- encore là (tous ensemble, contre la même population), leurs résumés et le dernier relevé envoyés, puis plus rien
-- n'est compté (closed) ; attend les envois CLOSE_TIMEOUT au plus.
function CheatLog.close()
	-- Joueurs encore là à l'arrêt : leur PlayerRemoving peut arriver après ce rappel
	runClosingHooks(Players:GetPlayers(), true)
	for id, record in records do
		records[id] = nil
		if CheatLog.worthSummary(record) then
			task.spawn(trackedSummary, withSession(record, sessions[id]))
		end
	end
	table.clear(sessions)
	CheatLog.flushReport("arrêt du serveur")
	closed = true
	local deadline = os.clock() + CheatLog.CLOSE_TIMEOUT
	while pendingSends > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return CheatLog

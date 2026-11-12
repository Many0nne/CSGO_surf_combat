-- Statistiques de visée par joueur (#178, docs/anticheat.md « Aimbot et triggerbot ») : règles pures, sans service ni
-- workspace, testées sous Lune (tests/specs/AimStats.spec.luau).
-- Un aimbot envoie des tirs valides : on ne peut que le repérer statistiquement. Par joueur et par session : tirs
-- acceptés (ShotFired), touches qui ont fait des dégâts, touches rattachées à leur tir par shotTime (#216, taux de
-- touches) ou orphelines (anomalie), touches à la tête, et touches précédées d'un « flick » (cap qui
-- tourne d'au moins FLICK_MIN_ANGLE entre le dernier cap reçu par CharacterSync et la direction de la touche, validée
-- par le Validator, en FLICK_MAX_AGE au plus ; pas la direction de ShotFired, que rien ne vérifie contre la touche).
-- Un joueur est signalé sur une statistique seulement si elle dépasse de Z_THRESHOLD écarts-types la moyenne des
-- AUTRES joueurs du serveur (au moins MIN_POPULATION, chacun avec MIN_HITS touches) ET un plancher absolu (FLOOR).
-- Sortie : chiffres bruts pour revue humaine (console, CheatLog). Jamais de sanction ni de tir refusé : rien ici ne
-- renvoie de verdict sur un tir. Bots exclus (ni comptés, ni dans la population).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)
local ShotLinkRules = require(ServerScriptService.Server.ShotLinkRules)

local AimStats = {}

-- Touches minimales d'un joueur pour être jugé et pour entrer dans la population (moins : bruit statistique).
AimStats.MIN_HITS = 30
-- Autres joueurs jugeables minimum pour juger quelqu'un : en dessous (serveur de 2 joueurs), personne n'est signalé.
AimStats.MIN_POPULATION = 5
-- Écarts-types au-dessus de la moyenne des autres joueurs pour signaler une statistique.
AimStats.Z_THRESHOLD = 3
-- Planchers absolus (fractions) : une statistique sous son plancher n'est jamais signalée, même très au-dessus d'une
-- population faible (ex. 40 % de tête parmi des joueurs à 10 %). Prudents : à l'AWP, les bons joueurs visent la tête.
AimStats.FLOOR = {
	headshotRate = 0.6, -- touches à la tête / touches
	hitRate = 0.75, -- tirs qui touchent / tirs acceptés
	flickRate = 0.3, -- touches précédées d'un flick / touches
}
-- Écart-type minimal de la population par statistique : des autres joueurs presque identiques ne doivent pas rendre
-- suspect un écart de quelques points.
AimStats.MIN_SPREAD = 0.05
-- Flick : rotation horizontale d'au moins FLICK_MIN_ANGLE (degrés) entre le dernier cap reçu avant le tir et la
-- direction de la touche, ce cap datant d'au plus FLICK_MAX_AGE (s) à l'arrivée du tir (2 paquets CharacterSync à
-- 20 Hz ; plus vieux : pas de mesure). Soit au moins 300 °/s : au-dessus d'un air strafe de surf ordinaire.
AimStats.FLICK_MIN_ANGLE = 30
AimStats.FLICK_MAX_AGE = 0.1
-- Durée minimale (s) retenue pour la vitesse angulaire affichée (paquets groupés : un écart de 1 ms ferait 25 000 °/s).
AimStats.MIN_SPEED_DT = 1 / 20
-- Touches orphelines (#246) : Roblox garantit l'ordre des remotes d'une connexion, donc un client honnête envoie
-- ShotFired avant sa touche ; seul un ShotFired écarté par le relais (cadence à 0,15 s près, origine lointaine) en
-- fait une orpheline, ce qui reste rare. Un client qui ne l'envoie jamais n'en produit que des orphelines. Violation
-- à ORPHAN_MIN_HITS orphelines au moins ET plus de ORPHAN_MAX_RATE des touches (0,25 : un honnête en a au plus
-- quelques-unes sur des centaines), puis à chaque nouveau palier de ORPHAN_MIN_HITS (journal borné).
AimStats.ORPHAN_MIN_HITS = 5
AimStats.ORPHAN_MAX_RATE = 0.25
-- Direction de tir presque verticale : cap indéfini, flick non mesuré (composante horizontale minimale).
local MIN_HORIZONTAL = 0.1

-- Cap reçu avant un tir et son âge à l'arrivée du tir (#216), gardé avec le tir dans un registre ShotLinkRules (data) :
-- figé là, un paquet de position arrivé entre le tir et sa touche (non fiable contre fiable) ne fausse pas le flick.
export type ShotYaw = { yaw: number?, yawAge: number? }

export type Stats = {
	name: string,
	shots: number, -- tirs acceptés (ShotFired relayé)
	hits: number, -- touches acceptées par le Validator qui ont fait des dégâts
	headshots: number,
	hitShots: number, -- tirs rattachés à une touche (#216 : par shotTime, rattachement décidé par le Validator)
	orphanHits: number, -- touches sans tir rattaché (#216 : anomalie ; #246 : comptée comme un tir qui touche)
	orphanAlerts: number, -- violations « touches orphelines » déjà levées (#246)
	measured: number, -- touches dont le flick a pu être mesuré
	flickHits: number, -- touches précédées d'un flick
	peakSpeed: number, -- vitesse angulaire maximale mesurée (°/s)
	recent: ShotLinkRules.Ledger, -- tirs récents en attente de leur touche (data : ShotYaw)
	reportedShots: number, -- tirs au dernier résumé périodique
	everFlagged: boolean, -- signalé au moins une fois dans la session (son relevé final va alors au journal)
}

export type Metric = "headshotRate" | "hitRate" | "flickRate"
local METRICS: { Metric } = { "headshotRate", "hitRate", "flickRate" }
local LABELS: { [Metric]: string } = { headshotRate = "tête", hitRate = "touches", flickRate = "flick" }

export type Verdict = {
	judged: boolean, -- assez de touches et de population pour un z-score
	z: { [string]: number }, -- par statistique (Metric)
	flagged: { Metric }, -- statistiques au-delà du seuil relatif ET du plancher
}

-- report : le relevé va à CheatLog (signalé ; au départ, aussi s'il l'a été plus tôt, pour que le dernier relevé du
-- résumé soit vraiment le dernier).
export type Entry = { id: number, stats: Stats, verdict: Verdict, line: string, report: boolean }

-- Joueurs suivis, par id de participant (UserId) ; frozen : arrêt du serveur, relevés finaux faits, plus rien compté.
export type State = { players: { [number]: Stats }, frozen: boolean }

-- Cette méthode permet de créer l'état des statistiques lorsque le serveur démarre (ou qu'un test commence).
function AimStats.new(): State
	return { players = {}, frozen = false }
end

-- Cette méthode permet de ne plus rien compter lorsque le serveur s'arrête et que les relevés finaux sont faits (un
-- tir pendant l'attente de l'arrêt ne recrée pas de statistiques partielles).
function AimStats.freeze(state: State)
	state.frozen = true
end

-- Cette méthode permet de retrouver (ou de créer) les statistiques d'un joueur lorsqu'il tire ; nil pour un bot.
local function statsOf(state: State, participant: any): Stats?
	if participant.isBot or state.frozen then
		return nil
	end
	local stats = state.players[participant.id]
	if not stats then
		stats = {
			name = participant.name,
			shots = 0,
			hits = 0,
			headshots = 0,
			hitShots = 0,
			orphanHits = 0,
			orphanAlerts = 0,
			measured = 0,
			flickHits = 0,
			peakSpeed = 0,
			recent = ShotLinkRules.new(),
			reportedShots = 0,
			everFlagged = false,
		}
		state.players[participant.id] = stats
	end
	return stats
end

-- Cette méthode permet de mesurer la rotation horizontale (degrés, 0 à 180) entre un cap et la direction d'un tir
-- lorsqu'un tir arrive ; nil si la direction est presque verticale (cap indéfini).
function AimStats.yawDelta(yaw: number, direction: Vector3): number?
	if MathRules.horizontalLength(direction) < MIN_HORIZONTAL then
		return nil
	end
	return math.deg(math.abs(MathRules.angleDelta(yaw, CharacterSyncRules.yawOf(direction))))
end

-- Cette méthode permet de compter un tir accepté lorsqu'il est relayé (ShotFired) : le dernier cap reçu (lastYaw à
-- lastYawAt, même horloge que now) est figé pour le flick de sa touche, retrouvée par shotTime. Aucun veto.
function AimStats.noteShot(
	state: State,
	participant: any,
	now: number,
	lastYaw: number?,
	lastYawAt: number?,
	shotTime: number?
)
	local stats = statsOf(state, participant)
	if not stats then
		return
	end
	stats.shots += 1
	if type(shotTime) ~= "number" then
		return
	end
	local shotYaw: ShotYaw = { yaw = lastYaw, yawAge = if lastYaw and lastYawAt then now - lastYawAt else nil }
	ShotLinkRules.record(stats.recent, shotTime, now, true, false, shotYaw)
end

-- Cette méthode permet de compter une touche qui a fait des dégâts lorsqu'elle est appliquée : rattachée au tir
-- linkedShotTime (décidé par le Validator, #216 ; nil : orpheline, anomalie hors du taux de touches) ; flick mesuré
-- alors entre le cap figé à ce tir et la direction validée de la touche. Ne renvoie rien : aucun veto.
function AimStats.noteHit(
	state: State,
	participant: any,
	isHeadshot: boolean,
	now: number,
	direction: Vector3?,
	linkedShotTime: number?
)
	local stats = statsOf(state, participant)
	if not stats then
		return
	end
	stats.hits += 1
	if isHeadshot then
		stats.headshots += 1
	end
	local record = ShotLinkRules.find(stats.recent, linkedShotTime, now, "hit")
	if not record then
		-- Touche sans tir rattaché (#246) : comptée comme un tir qui touche (le client n'a pas annoncé le tir), pour que
		-- le joueur qui ne l'envoie jamais ne sorte pas du taux de touches ; pas de flick (aucun cap figé)
		stats.orphanHits += 1
		stats.shots += 1
		stats.hitShots += 1
		return
	end
	record.hit = true
	stats.hitShots += 1
	local shotYaw: ShotYaw = record.data or {}
	local yaw, age = shotYaw.yaw, shotYaw.yawAge
	if not direction or not yaw or not age or age < 0 or age > AimStats.FLICK_MAX_AGE then
		return
	end
	local delta = AimStats.yawDelta(yaw, direction)
	if not delta then
		return
	end
	stats.measured += 1
	stats.peakSpeed = math.max(stats.peakSpeed, delta / math.max(age, AimStats.MIN_SPEED_DT))
	if delta >= AimStats.FLICK_MIN_ANGLE then
		stats.flickHits += 1
	end
end

-- Cette méthode permet de lever la violation « touches orphelines » (#246) lorsqu'une touche vient d'être comptée :
-- renvoie le détail à journaliser si le joueur franchit un nouveau palier d'orphelines au-delà du taux toléré, sinon nil.
-- Journal seul : aucun tir n'est refusé ici.
function AimStats.orphanAlert(state: State, participant: any): string?
	local stats = if participant.isBot then nil else state.players[participant.id]
	if not stats or stats.hits == 0 then
		return nil
	end
	local rate = stats.orphanHits / stats.hits
	if stats.orphanHits < (stats.orphanAlerts + 1) * AimStats.ORPHAN_MIN_HITS or rate <= AimStats.ORPHAN_MAX_RATE then
		return nil
	end
	stats.orphanAlerts += 1
	return string.format(
		"touches sans ShotFired : %d sur %d (%d%%, max %d%%)",
		stats.orphanHits,
		stats.hits,
		math.floor(rate * 100 + 0.5),
		math.floor(AimStats.ORPHAN_MAX_RATE * 100 + 0.5)
	)
end

-- Cette méthode permet de lire une statistique d'un joueur (fraction) lorsqu'on le juge ou l'affiche ; 0 sans dénominateur.
function AimStats.rate(stats: Stats, metric: Metric): number
	if metric == "hitRate" then
		return if stats.shots > 0 then stats.hitShots / stats.shots else 0
	end
	if stats.hits == 0 then
		return 0
	end
	return (if metric == "headshotRate" then stats.headshots else stats.flickHits) / stats.hits
end

-- Cette méthode permet de juger un joueur contre la population du serveur lorsqu'un résumé est produit : z-score de
-- chaque statistique contre les AUTRES joueurs jugeables (MIN_HITS touches), signalé au-delà de Z_THRESHOLD et du plancher.
function AimStats.judge(state: State, id: number): Verdict
	local verdict: Verdict = { judged = false, z = {}, flagged = {} }
	local stats = state.players[id]
	if not stats or stats.hits < AimStats.MIN_HITS then
		return verdict
	end
	local others = {}
	for otherId, other in state.players do
		if otherId ~= id and other.hits >= AimStats.MIN_HITS then
			table.insert(others, other)
		end
	end
	if #others < AimStats.MIN_POPULATION then
		return verdict
	end
	verdict.judged = true
	for _, metric in METRICS do
		local sum = 0
		for _, other in others do
			sum += AimStats.rate(other, metric)
		end
		local mean = sum / #others
		local squares = 0
		for _, other in others do
			squares += (AimStats.rate(other, metric) - mean) ^ 2
		end
		-- Écart-type d'échantillon (n - 1) : plus large sur une petite population, donc plus prudent
		local spread = math.max(math.sqrt(squares / (#others - 1)), AimStats.MIN_SPREAD)
		local value = AimStats.rate(stats, metric)
		local z = (value - mean) / spread
		verdict.z[metric] = z
		if z >= AimStats.Z_THRESHOLD and value >= AimStats.FLOOR[metric] then
			table.insert(verdict.flagged, metric)
		end
	end
	return verdict
end

-- Cette méthode permet de mettre en forme les chiffres bruts d'un joueur lorsqu'ils vont au journal : compact (le
-- détail de CheatLog est coupé à 160 octets), signalement et son z d'abord, puis les chiffres, puis les autres z.
-- « but » = tirs rattachés à une touche ; « touches » = toutes les touches acceptées (celles de MIN_HITS) ; « orph » =
-- touches sans tir rattaché (#216).
function AimStats.describe(stats: Stats, verdict: Verdict): string
	-- Cette méthode permet d'arrondir une statistique en pourcentage lorsqu'elle est affichée.
	local function pct(metric: Metric): number
		return math.floor(AimStats.rate(stats, metric) * 100 + 0.5)
	end
	local parts = {}
	if #verdict.flagged > 0 then
		local names = {}
		for _, metric in verdict.flagged do
			table.insert(names, string.format("%s%+.1f", LABELS[metric], verdict.z[metric]))
		end
		table.insert(parts, "SIGNALÉ z " .. table.concat(names, " ") .. " |")
	end
	table.insert(
		parts,
		string.format(
			"tirs %d but %d (%d%%) touches %d orph %d tête %d (%d%%) flick %d (%d%%) mesurés %d pic %.0f°/s",
			stats.shots,
			stats.hitShots,
			pct("hitRate"),
			stats.hits,
			stats.orphanHits,
			stats.headshots,
			pct("headshotRate"),
			stats.flickHits,
			pct("flickRate"),
			stats.measured,
			stats.peakSpeed
		)
	)
	if verdict.judged then
		-- z des statistiques non signalées (celles signalées sont déjà en tête)
		local others = {}
		for _, metric in METRICS do
			if not table.find(verdict.flagged, metric) then
				table.insert(others, string.format("%s %+.1f", LABELS[metric], verdict.z[metric]))
			end
		end
		if #others > 0 then
			table.insert(parts, "| z " .. table.concat(others, " "))
		end
	elseif stats.hits < AimStats.MIN_HITS then
		table.insert(parts, string.format("| non jugé (%d/%d touches)", stats.hits, AimStats.MIN_HITS))
	else
		table.insert(parts, "| non jugé (population trop petite)")
	end
	return table.concat(parts, " ")
end

-- Cette méthode permet de produire le résumé d'un joueur lorsqu'il est demandé (périodique, fin de session) ; final :
-- le relevé va aussi au journal si le joueur a été signalé plus tôt dans la session.
local function entryOf(state: State, id: number, stats: Stats, final: boolean): Entry
	local verdict = AimStats.judge(state, id)
	local flagged = #verdict.flagged > 0
	local report = flagged or (final and stats.everFlagged)
	stats.everFlagged = stats.everFlagged or flagged
	return { id = id, stats = stats, verdict = verdict, line = AimStats.describe(stats, verdict), report = report }
end

-- Cette méthode permet de produire le résumé périodique lorsque son intervalle tombe : un résumé par joueur qui a tiré
-- depuis le précédent (les inactifs ne refont pas de bruit), trié par id.
function AimStats.periodic(state: State): { Entry }
	local entries = {}
	for id, stats in state.players do
		if stats.shots > stats.reportedShots then
			table.insert(entries, entryOf(state, id, stats, false))
		end
	end
	-- Après le jugement de tous (un même tour voit la même population)
	for _, entry in entries do
		entry.stats.reportedShots = entry.stats.shots
	end
	table.sort(entries, function(a, b)
		return a.id < b.id
	end)
	return entries
end

-- Cette méthode permet de clore la session de joueurs qui partent (un seul, ou tous à l'arrêt du serveur) : résumé
-- final de chacun, tous jugés contre la même population avant d'être oubliés (aucune fuite). Joueurs inconnus ignorés.
function AimStats.close(state: State, ids: { number }): { Entry }
	local entries = {}
	for _, id in ids do
		local stats = state.players[id]
		if stats then
			table.insert(entries, entryOf(state, id, stats, true))
		end
	end
	for _, entry in entries do
		state.players[entry.id] = nil
	end
	return entries
end

-- Cette méthode permet de compter les joueurs suivis lorsqu'un test vérifie le nettoyage.
function AimStats.count(state: State): number
	local n = 0
	for _ in state.players do
		n += 1
	end
	return n
end

return AimStats

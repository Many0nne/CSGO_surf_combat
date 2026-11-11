-- Statistiques de visée par joueur (#178, docs/anticheat.md « Aimbot et triggerbot ») : règles pures, sans service ni
-- workspace, testées sous Lune (tests/specs/AimStats.spec.luau).
-- Un aimbot envoie des tirs valides : on ne peut que le repérer statistiquement. Par joueur et par session : tirs
-- acceptés (ShotFired), touches acceptées, touches à la tête, et « flicks » (cap qui tourne d'au moins FLICK_MIN_ANGLE
-- entre le dernier cap reçu par CharacterSync et la direction du tir, en FLICK_MAX_AGE au plus) suivis d'une touche.
-- Un joueur est signalé sur une statistique seulement si elle dépasse de Z_THRESHOLD écarts-types la moyenne des
-- AUTRES joueurs du serveur (au moins MIN_POPULATION, chacun avec MIN_HITS touches) ET un plancher absolu (FLOOR).
-- Sortie : chiffres bruts pour revue humaine (console, CheatLog). Jamais de sanction ni de tir refusé : rien ici ne
-- renvoie de verdict sur un tir. Bots exclus (ni comptés, ni dans la population).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)

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
-- Flick : rotation horizontale d'au moins FLICK_MIN_ANGLE (degrés) entre le dernier cap reçu et la direction du tir,
-- ce cap datant d'au plus FLICK_MAX_AGE (s) (3 paquets CharacterSync à 20 Hz ; plus vieux : pas de mesure).
AimStats.FLICK_MIN_ANGLE = 25
AimStats.FLICK_MAX_AGE = 0.15
-- Durée minimale (s) retenue pour la vitesse angulaire affichée (paquets groupés : un écart de 1 ms ferait 25 000 °/s).
AimStats.MIN_SPEED_DT = 1 / 20
-- Une touche est rattachée au dernier tir s'il date d'au plus HIT_LINK_WINDOW (s) (le client envoie ShotFired juste
-- avant la touche, sur deux remotes fiables, donc dans cet ordre) ; une seule touche comptée par tir.
AimStats.HIT_LINK_WINDOW = 0.5
-- Direction de tir presque verticale : cap indéfini, flick non mesuré (composante horizontale minimale).
local MIN_HORIZONTAL = 0.1

export type Stats = {
	name: string,
	shots: number, -- tirs acceptés (ShotFired relayé)
	hits: number, -- touches acceptées par le Validator
	headshots: number,
	hitShots: number, -- tirs rattachés à au moins une touche
	measured: number, -- tirs dont le flick a pu être mesuré
	flicks: number,
	flickHits: number, -- touches rattachées à un tir avec flick
	peakSpeed: number, -- vitesse angulaire maximale mesurée (°/s)
	lastShotAt: number?,
	lastShotFlick: boolean,
	lastShotHit: boolean,
	reportedShots: number, -- tirs au dernier résumé périodique
}

export type Metric = "headshotRate" | "hitRate" | "flickRate"
local METRICS: { Metric } = { "headshotRate", "hitRate", "flickRate" }
local LABELS: { [Metric]: string } = { headshotRate = "tête", hitRate = "touches", flickRate = "flick" }

export type Verdict = {
	judged: boolean, -- assez de touches et de population pour un z-score
	z: { [string]: number }, -- par statistique (Metric)
	flagged: { Metric }, -- statistiques au-delà du seuil relatif ET du plancher
}

export type Entry = { id: number, stats: Stats, verdict: Verdict, line: string }

-- Joueurs suivis, par id de participant (UserId).
export type State = { players: { [number]: Stats } }

-- Cette méthode permet de créer l'état des statistiques lorsque le serveur démarre (ou qu'un test commence).
function AimStats.new(): State
	return { players = {} }
end

-- Cette méthode permet de retrouver (ou de créer) les statistiques d'un joueur lorsqu'il tire ; nil pour un bot.
local function statsOf(state: State, participant: any): Stats?
	if participant.isBot then
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
			measured = 0,
			flicks = 0,
			flickHits = 0,
			peakSpeed = 0,
			lastShotAt = nil,
			lastShotFlick = false,
			lastShotHit = false,
			reportedShots = 0,
		}
		state.players[participant.id] = stats
	end
	return stats
end

-- Cette méthode permet de mesurer la rotation horizontale (degrés, 0 à 180) entre un cap et la direction d'un tir
-- lorsqu'un tir arrive ; nil si la direction est presque verticale (cap indéfini).
function AimStats.yawDelta(yaw: number, direction: Vector3): number?
	if Vector3.new(direction.X, 0, direction.Z).Magnitude < MIN_HORIZONTAL then
		return nil
	end
	local delta = (CharacterSyncRules.yawOf(direction) - yaw) % (2 * math.pi)
	if delta > math.pi then
		delta = 2 * math.pi - delta
	end
	return math.deg(delta)
end

-- Cette méthode permet de compter un tir accepté lorsqu'il est relayé (ShotFired) : flick mesuré contre le dernier cap
-- reçu (lastYaw, reçu à lastYawAt, même horloge que now) s'il est assez récent. Ne renvoie rien : aucun veto.
function AimStats.noteShot(
	state: State,
	participant: any,
	direction: Vector3,
	now: number,
	lastYaw: number?,
	lastYawAt: number?
)
	local stats = statsOf(state, participant)
	if not stats then
		return
	end
	stats.shots += 1
	stats.lastShotAt = now
	stats.lastShotHit = false
	stats.lastShotFlick = false
	if not lastYaw or not lastYawAt then
		return
	end
	local age = now - lastYawAt
	if age < 0 or age > AimStats.FLICK_MAX_AGE then
		return
	end
	local delta = AimStats.yawDelta(lastYaw, direction)
	if not delta then
		return
	end
	stats.measured += 1
	stats.peakSpeed = math.max(stats.peakSpeed, delta / math.max(age, AimStats.MIN_SPEED_DT))
	if delta >= AimStats.FLICK_MIN_ANGLE then
		stats.flicks += 1
		stats.lastShotFlick = true
	end
end

-- Cette méthode permet de compter une touche acceptée par le Validator lorsqu'elle est appliquée : rattachée au dernier
-- tir s'il est récent et pas encore touché (taux de touches, flick suivi d'une touche). Ne renvoie rien : aucun veto.
function AimStats.noteHit(state: State, participant: any, isHeadshot: boolean, now: number)
	local stats = statsOf(state, participant)
	if not stats then
		return
	end
	stats.hits += 1
	if isHeadshot then
		stats.headshots += 1
	end
	local shotAt = stats.lastShotAt
	if shotAt and not stats.lastShotHit and now - shotAt >= 0 and now - shotAt <= AimStats.HIT_LINK_WINDOW then
		stats.lastShotHit = true
		stats.hitShots += 1
		if stats.lastShotFlick then
			stats.flickHits += 1
		end
	end
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
		local spread = math.max(math.sqrt(squares / #others), AimStats.MIN_SPREAD)
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
-- détail de CheatLog est coupé à 160 octets), signalement d'abord, puis tirs, touches, tête, flicks, z-scores.
function AimStats.describe(stats: Stats, verdict: Verdict): string
	local function pct(metric: Metric): number
		return math.floor(AimStats.rate(stats, metric) * 100 + 0.5)
	end
	local parts = {}
	if #verdict.flagged > 0 then
		local names = {}
		for _, metric in verdict.flagged do
			table.insert(names, string.format("%s z%+.1f", LABELS[metric], verdict.z[metric]))
		end
		table.insert(parts, "SIGNALÉ " .. table.concat(names, ", ") .. " |")
	end
	table.insert(
		parts,
		string.format(
			"tirs %d, touches %d (%d%%), tête %d (%d%%), flick touché %d (%d%%), flicks %d/%d, pic %.0f°/s",
			stats.shots,
			stats.hitShots,
			pct("hitRate"),
			stats.headshots,
			pct("headshotRate"),
			stats.flickHits,
			pct("flickRate"),
			stats.flicks,
			stats.measured,
			stats.peakSpeed
		)
	)
	if verdict.judged then
		table.insert(
			parts,
			string.format(
				"| z tête %+.1f touches %+.1f flick %+.1f",
				verdict.z.headshotRate,
				verdict.z.hitRate,
				verdict.z.flickRate
			)
		)
	elseif stats.hits < AimStats.MIN_HITS then
		table.insert(parts, string.format("| non jugé (%d/%d touches)", stats.hits, AimStats.MIN_HITS))
	else
		table.insert(parts, "| non jugé (population trop petite)")
	end
	return table.concat(parts, " ")
end

-- Cette méthode permet de produire le résumé d'un joueur lorsqu'il est demandé (périodique, fin de session).
local function entryOf(state: State, id: number, stats: Stats): Entry
	local verdict = AimStats.judge(state, id)
	return { id = id, stats = stats, verdict = verdict, line = AimStats.describe(stats, verdict) }
end

-- Cette méthode permet de produire le résumé périodique lorsque son intervalle tombe : un résumé par joueur qui a tiré
-- depuis le précédent (les inactifs ne refont pas de bruit), trié par id.
function AimStats.periodic(state: State): { Entry }
	local entries = {}
	for id, stats in state.players do
		if stats.shots > stats.reportedShots then
			table.insert(entries, entryOf(state, id, stats))
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

-- Cette méthode permet de clore la session d'un joueur lorsqu'il part : résumé final (jugé contre la population encore
-- là) s'il a tiré, puis oubli de ses statistiques (aucune fuite). nil si rien à résumer.
function AimStats.close(state: State, id: number): Entry?
	local stats = state.players[id]
	if not stats then
		return nil
	end
	local entry = if stats.shots > 0 or stats.hits > 0 then entryOf(state, id, stats) else nil
	state.players[id] = nil
	return entry
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

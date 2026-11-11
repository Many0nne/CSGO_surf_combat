-- Historique pur des positions acceptées d'un personnage (#173), pour rembobiner une cible au moment d'un tir ou d'un
-- coup (compensation de latence, #174 et #176). Aucune dépendance à Roblox hors Vector3 et MathRules (module partagé,
-- sans service) : testable en Lune. Le serveur (CharacterSync) en garde un par personnage et l'alimente avec l'horloge
-- serveur (workspace:GetServerTimeNow()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathRules = require(ReplicatedStorage.Shared.MathRules)

local PositionHistory = {}

-- Durée couverte par le tampon (s).
PositionHistory.DURATION = 1
-- Cadence d'échantillonnage (Hz) : les joueurs envoient jusqu'à 40 paquets/s, on n'en garde que 20.
PositionHistory.SAMPLE_RATE = 20
-- Écart minimal entre deux relevés (s), 40 % sous la période nominale : la gigue d'un client à 20 Hz et le relais des
-- bots (écarts de 0,033 et 0,067 s) ne font pas sauter de relevé, alors qu'un flux à 40 Hz est ramené à 20 Hz.
PositionHistory.MIN_SPACING = 0.6 / PositionHistory.SAMPLE_RATE
-- Rembobinage maximal (s), borne de `sampleAt` : un client ne peut pas réclamer une position plus ancienne (#174 prévoit
-- 0,4 s : INTERP_DELAY de 0,1 s plus la latence). Doit rester <= DURATION.
PositionHistory.MAX_REWIND = 0.4
-- Écart maximal (s) entre deux relevés voisins pour interpoler : au-delà (paquets rejetés, à-coup serveur), la position
-- ne traverse pas le vide en ligne droite, on prend le relevé le plus proche.
PositionHistory.MAX_GAP = 0.25
-- Recul d'horloge (s) toléré sans vider le tampon : en deçà, le relevé en retard est simplement ignoré.
PositionHistory.MAX_CLOCK_STEP = 0.5
-- Relevés gardés : de quoi couvrir DURATION à l'écart minimal, plus un pour encadrer le plus ancien instant.
PositionHistory.CAPACITY = math.ceil(PositionHistory.DURATION / PositionHistory.MIN_SPACING) + 1

export type History = {
	times: { number },
	positions: { Vector3 },
	-- Indice (1..CAPACITY) du relevé le plus ancien ; count relevés valides à partir de lui, en rond.
	first: number,
	count: number,
	-- Dernière position acceptée, même écartée du tampon par MIN_SPACING : "maintenant" n'est jamais en retard.
	latestT: number,
	latestPos: Vector3,
}

-- Cette méthode permet de créer un historique vide lorsqu'un personnage apparaît.
function PositionHistory.new(): History
	return {
		times = table.create(PositionHistory.CAPACITY, 0),
		positions = table.create(PositionHistory.CAPACITY, Vector3.zero),
		first = 1,
		count = 0,
		latestT = -math.huge,
		latestPos = Vector3.zero,
	}
end

-- Cette méthode permet de lire l'indice du k-ième relevé (1 = plus ancien) lorsqu'on parcourt le tampon circulaire.
local function slot(history: History, k: number): number
	return (history.first - 1 + k - 1) % PositionHistory.CAPACITY + 1
end

-- Cette méthode permet d'ajouter une position acceptée à l'instant t (horloge serveur) lorsqu'elle arrive. Elle est
-- toujours retenue comme dernière position ; elle n'entre dans le tampon que si MIN_SPACING est passé depuis le relevé
-- précédent (le plus ancien est écrasé si plein). Un temps ou une position non finis sont refusés ; un recul d'horloge
-- d'au moins MAX_CLOCK_STEP repart d'un tampon vide.
function PositionHistory.record(history: History, t: number, pos: Vector3): boolean
	if not MathRules.isFinite(t) or not MathRules.isFiniteVector3(pos) then
		return false
	end
	if t < history.latestT then
		-- Petit recul (resynchronisation de l'horloge) : relevé ignoré ; grand recul : on repart de zéro
		if history.latestT - t < PositionHistory.MAX_CLOCK_STEP then
			return false
		end
		history.count = 0
		history.first = 1
	end
	history.latestT = t
	history.latestPos = pos
	local n = history.count
	if n > 0 and t - history.times[slot(history, n)] < PositionHistory.MIN_SPACING then
		return false
	end
	if n < PositionHistory.CAPACITY then
		history.count = n + 1
		local i = slot(history, n + 1)
		history.times[i] = t
		history.positions[i] = pos
	else
		-- Plein : le plus ancien emplacement devient le plus récent
		local i = history.first
		history.times[i] = t
		history.positions[i] = pos
		history.first = i % PositionHistory.CAPACITY + 1
	end
	return true
end

-- Cette méthode permet de connaître la position à l'instant t lorsqu'on rembobine une cible : t est borné à
-- [now - MAX_REWIND, now], puis la position est interpolée entre les deux relevés qui l'encadrent (le dernier est la
-- dernière position acceptée). Hors des relevés, le plus proche est renvoyé ; nil si vide ou si t n'est pas un nombre.
function PositionHistory.sampleAt(history: History, t: number, now: number): Vector3?
	local n = history.count
	if n == 0 or t ~= t or now ~= now then
		return nil
	end
	t = math.clamp(t, now - PositionHistory.MAX_REWIND, now)
	local times, positions = history.times, history.positions
	local oldest, newest = slot(history, 1), slot(history, n)
	if t <= times[oldest] then
		return positions[oldest]
	elseif t >= history.latestT then
		return history.latestPos
	end
	-- Encadrement [a, b] de t : le dernier point est la dernière position acceptée si elle est plus récente que le tampon
	local ta, pa, tb, pb
	if t >= times[newest] then
		ta, pa, tb, pb = times[newest], positions[newest], history.latestT, history.latestPos
	else
		-- n est petit (~35) : parcours linéaire depuis la fin
		for k = n - 1, 1, -1 do
			local a = slot(history, k)
			if times[a] <= t then
				local b = slot(history, k + 1)
				ta, pa, tb, pb = times[a], positions[a], times[b], positions[b]
				break
			end
		end
	end
	if not ta then
		return positions[oldest]
	end
	if tb - ta > PositionHistory.MAX_GAP then
		return if t - ta < tb - t then pa else pb
	end
	return pa:Lerp(pb, (t - ta) / (tb - ta))
end

return PositionHistory

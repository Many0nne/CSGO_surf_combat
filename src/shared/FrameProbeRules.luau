-- FrameProbeRules.luau
-- Règles pures de la sonde de saccades (client/debug/FrameProbe) : classe chaque frame rendue en
-- HITCH (frame lente), STUTTER (frames régulières mais déplacement irrégulier), ROTATION (rotation irrégulière)
-- ou TELEPORT (saut de position volontaire, ignoré), et résume une fenêtre de frames. Aucun accès au moteur.

local FrameProbeRules = {}

FrameProbeRules.HITCH_RATIO = 2 -- dt > 2x la médiane...
FrameProbeRules.HITCH_MIN_EXTRA = 0.010 -- ... et au moins 10 ms de plus que la médiane
FrameProbeRules.NORMAL_DT_RATIO = 1.5 -- au-delà, la frame n'est plus « régulière »
FrameProbeRules.NEIGHBOR_AGREE = 0.15 -- les deux voisines doivent s'accorder à 15 % près
FrameProbeRules.OUTLIER_DEVIATION = 0.3 -- la frame centrale s'en écarte de plus de 30 %
FrameProbeRules.MIN_SPEED = 2 -- studs/s : en dessous, le déplacement est trop faible pour juger
FrameProbeRules.MIN_YAW_RATE = 20 -- degrés/s : idem pour la rotation
FrameProbeRules.TELEPORT_DIST = 20 -- studs en une frame : respawn, lancement, kill zone

export type Sample = {
	dt: number, -- temps entre deux RenderStep
	hbDt: number, -- somme des dt Heartbeat écoulés depuis le rendu précédent
	steps: number, -- nombre de Heartbeat entre les deux rendus (1 attendu)
	disp: number, -- déplacement de la racine entre les deux rendus (studs)
	simSpeed: number, -- norme de la vitesse simulée par le MovementController (studs/s)
	yawRate: number, -- vitesse de rotation horizontale de la caméra (degrés/s, valeur absolue)
}

-- Cette méthode permet de calculer la médiane d'une liste de nombres lorsque la sonde estime le dt « normal ».
function FrameProbeRules.median(values: { number }): number
	local n = #values
	if n == 0 then
		return 0
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	if n % 2 == 1 then
		return sorted[(n + 1) // 2]
	end
	return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

-- Cette méthode permet de lire le centile p (0..1) d'une liste lorsque la sonde résume une fenêtre de frames.
function FrameProbeRules.percentile(values: { number }, p: number): number
	local n = #values
	if n == 0 then
		return 0
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[math.clamp(math.ceil(p * n), 1, n)]
end

-- Cette méthode permet de dire si b est une valeur isolée entre a et c lorsque les voisines s'accordent entre elles
-- mais pas avec b (pic ou creux d'une seule frame, robuste à une accélération progressive).
function FrameProbeRules.isIsolatedOutlier(a: number, b: number, c: number, minRef: number): boolean
	local ref = (a + c) / 2
	if ref < minRef then
		return false
	end
	if math.abs(a - c) / ref > FrameProbeRules.NEIGHBOR_AGREE then
		return false
	end
	return math.abs(b - ref) / ref > FrameProbeRules.OUTLIER_DEVIATION
end

-- Cette méthode permet de dire si une frame est lente lorsque son dt dépasse nettement la médiane récente.
function FrameProbeRules.isHitch(dt: number, medianDt: number): boolean
	return dt > math.max(medianDt * FrameProbeRules.HITCH_RATIO, medianDt + FrameProbeRules.HITCH_MIN_EXTRA)
end

-- Cette méthode permet de dire si une frame a un dt régulier lorsqu'on veut juger son déplacement à part du timing.
local function isNormalDt(dt: number, medianDt: number): boolean
	return dt <= medianDt * FrameProbeRules.NORMAL_DT_RATIO
end

-- Cette méthode permet d'attribuer une cause à un déplacement irrégulier lorsque la frame a un dt normal :
-- pas physique manquant ou doublé, simulation elle-même irrégulière, position modifiée hors simulation, ou décalage
-- entre le temps de rendu et le temps simulé.
function FrameProbeRules.stutterSource(prev: Sample, cur: Sample, nxt: Sample): string
	if cur.steps ~= 1 then
		return cur.steps == 0 and "pas_physique_manquant" or "pas_physique_double"
	end
	if FrameProbeRules.isIsolatedOutlier(prev.simSpeed, cur.simSpeed, nxt.simSpeed, FrameProbeRules.MIN_SPEED) then
		return "simulation"
	end
	local expected = cur.simSpeed * cur.hbDt
	if expected > 1e-3 and math.abs(cur.disp - expected) / expected > FrameProbeRules.OUTLIER_DEVIATION then
		return "position_hors_simulation"
	end
	return "timing_rendu_vs_heartbeat"
end

-- Cette méthode permet de classer la frame centrale d'un triplet lorsque la frame suivante est connue :
-- renvoie la liste des anomalies (vide si la frame est saine) et, pour un STUTTER, sa cause probable.
function FrameProbeRules.classify(prev: Sample, cur: Sample, nxt: Sample, medianDt: number): ({ string }, string?)
	if cur.disp > FrameProbeRules.TELEPORT_DIST then
		return { "TELEPORT" }, nil
	end
	local kinds = {}
	local source: string? = nil
	if FrameProbeRules.isHitch(cur.dt, medianDt) then
		table.insert(kinds, "HITCH")
	elseif isNormalDt(prev.dt, medianDt) and isNormalDt(cur.dt, medianDt) and isNormalDt(nxt.dt, medianDt) then
		local s0, s1, s2 = prev.disp / prev.dt, cur.disp / cur.dt, nxt.disp / nxt.dt
		if FrameProbeRules.isIsolatedOutlier(s0, s1, s2, FrameProbeRules.MIN_SPEED) then
			table.insert(kinds, "STUTTER")
			source = FrameProbeRules.stutterSource(prev, cur, nxt)
		end
		if FrameProbeRules.isIsolatedOutlier(prev.yawRate, cur.yawRate, nxt.yawRate, FrameProbeRules.MIN_YAW_RATE) then
			table.insert(kinds, "ROTATION")
		end
	end
	return kinds, source
end

-- Cette méthode permet de résumer une fenêtre de dt lorsque la sonde écrit son bilan périodique.
function FrameProbeRules.summarize(dts: { number }): { fps: number, p99Ms: number, maxMs: number }
	local med = FrameProbeRules.median(dts)
	local maxDt = 0
	for _, dt in dts do
		maxDt = math.max(maxDt, dt)
	end
	return {
		fps = med > 0 and 1 / med or 0,
		p99Ms = FrameProbeRules.percentile(dts, 0.99) * 1000,
		maxMs = maxDt * 1000,
	}
end

return FrameProbeRules

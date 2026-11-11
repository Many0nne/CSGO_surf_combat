-- Règles pures des rampes de surf empruntées par les bots (#142, décision 3 de #133), testées
-- (tests/specs/RampRules.spec.luau). Une rampe est une grande face de surf du dossier `Ramps` de la map, décrite par
-- son repère (Frame) : centre de la face de glisse, u le long de la rampe, v vers le haut de la pente, n la normale.
-- Le plan (NavBuilder) simule une fois par rampe et par sens le trajet d'un bot (RampSim : même physique que le
-- joueur, en appuyant vers la rampe) d'une case d'entrée à une case de sortie ; le trajet (Trajectory) devient une
-- arête du graphe, que les bots rejouent ensuite (BotMotion) sans simuler le surf.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local RampRules = {}

-- Repère d'une rampe : centre de la face de glisse, u (longueur), v (montée dans la pente), n (normale vers le haut),
-- demi-longueur et demi-largeur de la face
export type Frame = { center: Vector3, u: Vector3, v: Vector3, n: Vector3, halfU: number, halfV: number }

-- Trajet d'un bot sur une rampe : pieds du bot tous les dt secondes, de la case d'entrée (départ en courant) à
-- l'atterrissage sur la case de sortie ; states[i] : 0 au sol, 1 en l'air, 2 en surf (animation)
export type Trajectory = {
	dt: number,
	points: { Vector3 },
	states: { number },
	duration: number,
	entry: number, -- case d'entrée
	exit: number, -- case de sortie
	ramp: number, -- index de la rampe dans le plan
	direction: number, -- sens le long de u (1 ou −1)
	peakSpeed: number,
}

RampRules.GROUND = 0
RampRules.AIR = 1
RampRules.SURF = 2

-- Cette méthode permet de donner le repère d'une pièce lorsque le plan cherche les rampes : face de normale dans la plage
-- du surf et d'au moins RAMP_MIN_AREA studs², longueur = son axe le plus horizontal ; nil sans telle face.
function RampRules.frameOf(cf: CFrame, size: Vector3): Frame?
	local axes = { { cf.XVector, size.X }, { cf.YVector, size.Y }, { cf.ZVector, size.Z } }
	local best: Frame? = nil
	local bestArea = 0
	for i = 1, 3 do
		local axis, thickness = axes[i][1], axes[i][2]
		local n = if axis.Y < 0 then -axis else axis
		if n.Y >= MovementConfig.SURF_NORMAL_MIN and n.Y < MovementConfig.SURF_NORMAL_Y then
			local a, b = axes[i % 3 + 1], axes[(i + 1) % 3 + 1]
			local area = a[2] * b[2]
			if area >= BotConfig.RAMP_MIN_AREA and area > bestArea then
				local along, other = a, b
				if math.abs(b[1].Y) < math.abs(a[1].Y) then
					along, other = b, a
				end
				local u = along[1].Unit
				local v = n:Cross(u).Unit
				if v.Y < 0 then
					v = -v
				end
				bestArea = area
				best = {
					center = cf.Position + n * (thickness / 2),
					u = u,
					v = v,
					n = n,
					halfU = along[2] / 2,
					halfV = other[2] / 2,
				}
			end
		end
	end
	return best
end

-- Cette méthode permet de savoir si deux repères sont la même rampe lorsque le plan en trouve plusieurs pièces (peau,
-- mur d'air posé dessus) : faces parallèles à moins de 2 studs, centre de b dans l'emprise de a.
function RampRules.sameRamp(a: Frame, b: Frame): boolean
	if a.n:Dot(b.n) < 0.99 then
		return false
	end
	local d = b.center - a.center
	return math.abs(d:Dot(a.n)) <= 2 and math.abs(d:Dot(a.u)) <= a.halfU and math.abs(d:Dot(a.v)) <= a.halfV
end

-- Cette méthode permet de placer un point dans le repère d'une rampe lorsqu'on le compare à ses bords : renvoie
-- (u, v, h), h = hauteur au-dessus du plan de la face, le long de la normale.
function RampRules.toLocal(frame: Frame, p: Vector3): (number, number, number)
	local d = p - frame.center
	return d:Dot(frame.u), d:Dot(frame.v), d:Dot(frame.n)
end

-- Cette méthode permet de donner le point de la face de glisse aux coordonnées (u, v) lorsqu'on vise la rampe.
function RampRules.surfacePoint(frame: Frame, u: number, v: number): Vector3
	return frame.center + frame.u * u + frame.v * v
end

-- Cette méthode permet de mesurer de combien un point dépasse du bout de départ d'une rampe parcourue dans le sens
-- direction (1 : vers +u) lorsqu'on cherche les cases d'entrée : positif hors de la rampe, côté départ.
function RampRules.beyondStart(frame: Frame, direction: number, p: Vector3): number
	local u = RampRules.toLocal(frame, p)
	return -direction * u - frame.halfU
end

-- Cette méthode permet de donner le point visé sur la rampe lorsque le bot y saute d'un sol à floorY : à RAMP_ENTRY_INSET
-- du bout de départ, RAMP_ENTRY_RISE au-dessus du sol ; nil si cette hauteur n'est pas sur la face.
function RampRules.entryTarget(frame: Frame, direction: number, floorY: number): Vector3?
	local u = -direction * (frame.halfU - BotConfig.RAMP_ENTRY_INSET)
	if frame.v.Y < 1e-3 then
		return nil
	end
	local v = (floorY + BotConfig.RAMP_ENTRY_RISE - frame.center.Y - frame.u.Y * u) / frame.v.Y
	local margin = BotConfig.RAMP_EDGE_MARGIN
	if v < -frame.halfV + margin or v > frame.halfV - margin then
		return nil
	end
	return RampRules.surfacePoint(frame, u, v)
end

-- Cette méthode permet de donner le point de passage lorsque le bot se lance vers la rampe : au-delà du bout de départ
-- (RAMP_APPROACH_OUT), devant la face (RAMP_APPROACH_LIFT), pour ne passer ni derrière elle ni dans sa tranche.
function RampRules.approachPoint(frame: Frame, direction: number, target: Vector3): Vector3
	local _, v = RampRules.toLocal(frame, target)
	local u = -direction * (frame.halfU + BotConfig.RAMP_APPROACH_OUT)
	return RampRules.surfacePoint(frame, u, v) + frame.n * BotConfig.RAMP_APPROACH_LIFT
end

-- Cette méthode permet de choisir les cases d'entrée à essayer lorsque le plan simule une rampe : les mieux notées
-- (score le plus bas : distance au point de passage), écartées d'au moins spacing studs entre elles, count au plus.
function RampRules.pickEntries(
	candidates: { { id: number, position: Vector3, score: number } },
	count: number,
	spacing: number
): { number }
	local sorted = table.clone(candidates)
	table.sort(sorted, function(a, b)
		if a.score == b.score then
			return a.id < b.id
		end
		return a.score < b.score
	end)
	local picked, positions = {}, {}
	for _, c in sorted do
		if #picked >= count then
			break
		end
		local ok = true
		for _, p in positions do
			if (p - c.position).Magnitude < spacing then
				ok = false
				break
			end
		end
		if ok then
			table.insert(picked, c.id)
			table.insert(positions, c.position)
		end
	end
	return picked
end

-- Cette méthode permet de donner le temps de chute d'une hauteur y avec une vitesse verticale vy jusqu'à la hauteur
-- floorY lorsqu'on prévoit un atterrissage (gravité du jeu) ; nil si le sol est trop haut pour être atteint.
function RampRules.fallTime(y: number, vy: number, floorY: number): number?
	local g = -MovementConfig.GRAVITY
	-- y + vy·t − g·t²/2 = floorY  →  (g/2)·t² − vy·t + (floorY − y) = 0, plus grande racine
	local disc = vy * vy - 2 * g * (floorY - y)
	if disc < 0 then
		return nil
	end
	return (vy + math.sqrt(disc)) / g
end

-- Cette méthode permet de choisir la case où atterrir lorsque le bot quitte la rampe : parmi les cases plus basses à
-- moins de RAMP_EXIT_RADIUS, la plus proche du point où il retomberait sans rien changer ; nil sans case.
function RampRules.pickLanding(
	pos: Vector3,
	velocity: Vector3,
	candidates: { { id: number, position: Vector3 } }
): number?
	local best, bestDist = nil, math.huge
	for _, c in candidates do
		local p = c.position
		local flat = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude
		if p.Y < pos.Y - 0.5 and pos.Y - p.Y <= BotConfig.NAV_MAX_DROP and flat <= BotConfig.RAMP_EXIT_RADIUS then
			local t = RampRules.fallTime(pos.Y, velocity.Y, p.Y)
			if t then
				local land = Vector3.new(pos.X + velocity.X * t, 0, pos.Z + velocity.Z * t)
				local d = Vector3.new(p.X - land.X, 0, p.Z - land.Z).Magnitude
				if d < bestDist or (d == bestDist and best and c.id < best) then
					best, bestDist = c.id, d
				end
			end
		end
	end
	return best
end

-- Cette méthode permet de rapprocher la vitesse horizontale d'une vitesse voulue lorsque le bot se dirige en l'air
-- (lancement, sortie de rampe) : au plus maxDelta studs/s par appel, vitesse verticale gardée.
function RampRules.steer(velocity: Vector3, wanted: Vector3, maxDelta: number): Vector3
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local goal = Vector3.new(wanted.X, 0, wanted.Z)
	local delta = goal - flat
	if delta.Magnitude > maxDelta then
		delta = delta.Unit * maxDelta
	end
	local result = flat + delta
	return Vector3.new(result.X, velocity.Y, result.Z)
end

-- Cette méthode permet de donner la vitesse horizontale qui fait retomber sur une case lorsque le bot a quitté la
-- rampe : le chemin restant divisé par le temps de chute, au plus maxSpeed ; nil si la case est trop haute.
function RampRules.landingVelocity(pos: Vector3, velocity: Vector3, target: Vector3, maxSpeed: number): Vector3?
	local t = RampRules.fallTime(pos.Y, velocity.Y, target.Y)
	if not t or t < 1e-3 then
		return nil
	end
	local wanted = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z) / t
	if wanted.Magnitude > maxSpeed then
		wanted = wanted.Unit * maxSpeed
	end
	return wanted
end

-- Cette méthode permet de mesurer le chemin parcouru le long de la rampe entre deux points lorsqu'on juge si un trajet
-- simulé la traverse vraiment (au moins RAMP_MIN_TRAVEL de sa longueur).
function RampRules.travel(frame: Frame, a: Vector3, b: Vector3): number
	return math.abs((b - a):Dot(frame.u))
end

-- Cette méthode permet de mesurer la plus grande vitesse d'un trajet lorsqu'on le garde : écart entre deux points
-- successifs divisé par dt.
function RampRules.peakSpeed(points: { Vector3 }, dt: number): number
	local peak = 0
	for i = 2, #points do
		peak = math.max(peak, (points[i] - points[i - 1]).Magnitude / dt)
	end
	return peak
end

-- Cette méthode permet de savoir si un trajet simulé devient une arête lorsque la simulation finit : sous RAMP_MAX_TIME
-- et RAMP_MAX_SPEED (et le plafond du serveur), au moins RAMP_MIN_TRAVEL de la rampe parcourue.
function RampRules.accept(duration: number, peakSpeed: number, travel: number, rampLength: number): boolean
	return duration <= BotConfig.RAMP_MAX_TIME
		and peakSpeed <= BotConfig.RAMP_MAX_SPEED
		and peakSpeed < MovementConfig.MAX_SPEED_SERVER
		and travel >= rampLength * BotConfig.RAMP_MIN_TRAVEL
end

-- Cette méthode permet de donner la position des pieds et la vitesse du bot à l'instant t d'un trajet lorsqu'il le
-- rejoue : interpolation entre deux points, t borné à la durée (vitesse du dernier segment à la fin).
function RampRules.sample(traj: Trajectory, t: number): (Vector3, Vector3, number)
	local points = traj.points
	local count = #points
	if count == 1 then
		return points[1], Vector3.zero, traj.states[1] or RampRules.GROUND
	end
	local x = math.clamp(t, 0, traj.duration) / traj.dt
	local i = math.min(math.floor(x) + 1, count - 1)
	local frac = math.clamp(x - (i - 1), 0, 1)
	local a, b = points[i], points[i + 1]
	local state = traj.states[if frac < 0.5 then i else i + 1] or RampRules.AIR
	return a:Lerp(b, frac), (b - a) / traj.dt, state
end

-- Cette méthode permet de résorber l'écart entre le bot et le départ du trajet lorsqu'il commence à le rejouer :
-- écart entier au départ, nul après RAMP_BLEND_TIME secondes.
function RampRules.blend(offset: Vector3, t: number): Vector3
	local blendTime = BotConfig.RAMP_BLEND_TIME
	if blendTime <= 0 then
		return Vector3.zero
	end
	return offset * math.max(0, 1 - t / blendTime)
end

-- Cette méthode permet de savoir si un bot peut lancer le trajet d'une rampe lorsqu'il arrive à la case d'entrée : au
-- sol, à moins de RAMP_START_DIST à l'horizontale et à hauteur voisine.
function RampRules.canStart(foot: Vector3, entry: Vector3, grounded: boolean): boolean
	if not grounded then
		return false
	end
	local flat = Vector3.new(entry.X - foot.X, 0, entry.Z - foot.Z).Magnitude
	return flat <= BotConfig.RAMP_START_DIST and math.abs(entry.Y - foot.Y) <= BotConfig.NAV_REACH_DY
end

return RampRules

-- Simulation du trajet d'un bot sur une rampe de surf (#142), faite une fois par le plan (NavBuilder) au démarrage du
-- serveur : même physique que le joueur (CharacterMotor, glissement sur la rampe compris), pilotée par un geste simple
-- de surfeur, puis gardée comme trajet (RampRules.Trajectory) que les bots rejouent sans simuler le surf.
-- 1. course depuis la case d'entrée vers le point de passage devant le bout de la rampe (RampRules.approachPoint),
--    puis vers le point visé sur la face ; saut près du point de passage ou au bord du vide ;
-- 2. surf : il appuie vers la rampe (direction horizontale opposée à la normale), comme un joueur qui tient sa
--    hauteur ; l'élan le porte le long de la rampe ;
-- 3. sortie (au-delà du bout d'arrivée, ou décroché) : il choisit la case où il retomberait (RampRules.pickLanding)
--    et s'y dirige en l'air ; arrivé au sol près d'une case, il freine jusqu'à sa vitesse de course sans en sortir
--    (RAMP_SETTLE_TIME au plus) : trajet réussi. Retombé avant la rampe ou glissé hors de la case : échec.
-- Règles pures : RampRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local CharacterMotor = require(ReplicatedStorage.Shared.movement.CharacterMotor)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local RampRules = require(ReplicatedStorage.Shared.RampRules)
local StepTiming = require(ReplicatedStorage.Shared.StepTiming)

local RampSim = {}

export type Candidate = { id: number, position: Vector3, interior: boolean? } -- interior : 8 voisines à pied

export type Params = {
	frame: RampRules.Frame,
	direction: number,
	ramp: number,
	entry: number,
	entryPos: Vector3,
	killY: number?,
	castParams: RaycastParams, -- requêtes dans la map (sol devant lui)
	cellsNear: (point: Vector3, radius: number) -> { Candidate },
	yield: (() -> ())?, -- appelé à chaque tick simulé (NavBuilder : rend la main quand la tranche de la frame est écoulée)
}

export type Rig = { model: Model, root: BasePart, body: BasePart }

-- Cette méthode permet de construire le corps simulé lorsque le plan simule les rampes : racine et corps de la
-- taille d'un personnage debout (MovementConfig), hors du Workspace, sans collision ni requête.
function RampSim.newRig(): Rig
	local model = Instance.new("Model")
	model.Name = "RampSimRig"
	local height = MovementConfig.CHAR_HEIGHT_STAND
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, height / 2, 0)
	root.Parent = model
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, height, 1)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(0, height / 2, 0)
	body.Parent = model
	model.PrimaryPart = root
	return { model = model, root = root, body = body }
end

-- Cette méthode permet de donner la direction horizontale d'un point vers un autre lorsqu'on dirige le corps simulé
-- (zéro s'ils sont l'un sur l'autre).
local function flatDir(from: Vector3, to: Vector3): Vector3
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.zero
end

-- Cette méthode permet de donner la distance horizontale entre deux points lorsqu'on compare le corps simulé à un but.
local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

-- Cette méthode permet de trouver la case la plus proche des pieds lorsque le corps simulé atterrit : à moins de
-- RAMP_LAND_RADIUS à l'horizontale et à hauteur voisine ; nil sinon.
local function landedCell(params: Params, foot: Vector3): number?
	local best, bestDist = nil, math.huge
	for _, c in params.cellsNear(foot, BotConfig.RAMP_LAND_RADIUS + 1) do
		local d = flatDist(foot, c.position)
		if
			d <= BotConfig.RAMP_LAND_RADIUS
			and math.abs(c.position.Y - foot.Y) <= BotConfig.NAV_REACH_DY
			and d < bestDist
		then
			best, bestDist = c.id, d
		end
	end
	return best
end

-- Cette méthode permet de simuler le trajet d'un bot sur une rampe depuis une case d'entrée lorsque le plan est
-- construit ; renvoie le trajet, ou nil et la raison de l'échec (affichée en debug).
function RampSim.simulate(rig: Rig, params: Params): (RampRules.Trajectory?, string)
	local frame, direction = params.frame, params.direction
	local target = RampRules.entryTarget(frame, direction, params.entryPos.Y)
	if not target then
		return nil, "hauteur hors de la rampe"
	end
	local approach = RampRules.approachPoint(frame, direction, target)
	local dt = StepTiming.TICK
	local run = MovementConfig.RUN_SPEED
	local inward = Vector3.new(-frame.n.X, 0, -frame.n.Z).Unit

	-- Corps reposé sur la case avant de le mesurer (la racine d'une simulation précédente est restée ailleurs)
	local standing = CFrame.new(params.entryPos + Vector3.new(0, MovementConfig.CHAR_HEIGHT_STAND / 2, 0))
	rig.root.CFrame = standing
	rig.body.CFrame = standing
	local motor = CharacterMotor.new(rig.model, rig.root, false)
	local ci = motor:standInfo()
	local lift = Vector3.new(0, ci.rootToBottom, 0)
	motor:teleport(CFrame.new(params.entryPos + lift))
	motor.velocity = flatDir(params.entryPos, approach) * run

	local points, states = { params.entryPos }, { RampRules.GROUND }
	local passed, jumped, touched = false, false, false
	local surfing, lost, settled = false, 0, 0
	local landing: Candidate? = nil
	local maxTicks = math.ceil(BotConfig.RAMP_MAX_TIME / dt)
	for _ = 1, maxTicks do
		if params.yield then
			params.yield()
		end
		local gnd = motor:beginTick(dt)
		local _, grounded, airborne = motor:updateState(gnd, false)
		local foot = motor.cframe.Position - lift
		local speed = Vector3.new(motor.velocity.X, 0, motor.velocity.Z).Magnitude
		if grounded and jumped and not touched then
			return nil, "saut trop court, retombé avant la rampe"
		elseif airborne and settled > 0 then
			return nil, "glissé hors de la case d'arrivée"
		end

		-- Point visé : le point de passage tant qu'il n'est pas devant la face, puis le point sur la rampe
		local beyond = RampRules.beyondStart(frame, direction, foot)
		local _, _, h = RampRules.toLocal(frame, foot)
		passed = passed
			or flatDist(foot, approach) < 3
			or (beyond <= BotConfig.RAMP_APPROACH_OUT and h >= BotConfig.RAMP_APPROACH_LIFT * 0.5)
		local aim = if passed then target else approach

		local jump = false
		if grounded and touched then
			-- Atterri : il freine vers la case d'arrivée jusqu'à sa vitesse de course, il doit y rester
			local exit = landedCell(params, foot)
			if not exit then
				return nil, string.format("atterri hors d'une case en %s", tostring(foot))
			end
			if settled > 0 and speed <= run + 1 then
				return RampSim._finish(params, points, states, dt, exit)
			elseif settled >= BotConfig.RAMP_SETTLE_TIME then
				return nil, string.format("encore à %.0f studs/s après l'atterrissage", speed)
			end
			settled += dt
			local goal = if landing then landing.position else foot
			motor:groundPhysics(gnd, flatDir(foot, goal), run, dt, false, false, false)
		elseif grounded then
			local wish = flatDir(foot, aim)
			if not jumped then
				-- Saut près du point de passage, ou au bord du vide (rien sous les pieds un peu plus loin)
				local ahead = motor.cframe.Position + wish * (ci.radius + 1.5)
				local floor = workspace:Raycast(ahead, Vector3.new(0, -(ci.rootToBottom + 2), 0), params.castParams)
				jump = flatDist(foot, approach) <= BotConfig.RAMP_JUMP_DIST or floor == nil
			end
			jumped = jumped or jump
			motor:groundPhysics(gnd, wish, run, dt, jump, false, false)
		elseif airborne then
			if motor.surfNormal then
				touched, surfing, lost = true, true, 0
			elseif surfing then
				lost += dt
			end
			local u = RampRules.toLocal(frame, foot)
			if surfing and (direction * u > frame.halfU or lost > 0.2) then
				-- Sortie : case d'arrivée choisie une fois, là où il retomberait
				surfing = false
				local nearby = params.cellsNear(foot, BotConfig.RAMP_EXIT_RADIUS)
				local id = RampRules.pickLanding(foot, motor.velocity, nearby)
				for _, c in nearby do
					if c.id == id then
						landing = c
					end
				end
				if not landing then
					return nil, string.format("aucune case où retomber depuis %s", tostring(foot))
				end
			end
			if surfing then
				-- Appui vers la rampe : le glissement (ClipVelocity) le maintient sur la face
				motor:airPhysics(inward, run, dt, false)
			else
				local wanted: Vector3? = nil
				if landing then
					wanted = RampRules.landingVelocity(foot, motor.velocity, landing.position, math.max(speed, run))
				elseif not touched then
					wanted = flatDir(foot, aim) * math.max(speed, run)
				end
				if wanted then
					motor.velocity = RampRules.steer(motor.velocity, wanted, BotConfig.RAMP_AIR_STEER * dt)
				end
				motor:airPhysics(Vector3.zero, 0, dt, false)
			end
		end
		motor:move(gnd, dt, ci, CFrame.new(), grounded, airborne, jump, false)
		motor:endTick(grounded)

		local now = motor.cframe.Position - lift
		table.insert(points, now)
		table.insert(
			states,
			if motor.surfNormal then RampRules.SURF elseif grounded and not jump then RampRules.GROUND else RampRules.AIR
		)
		if params.killY and now.Y < params.killY then
			return nil, "tombé hors de la map"
		end
	end
	return nil, "trop long"
end

-- Cette méthode permet de garder le trajet simulé lorsque le corps s'est arrêté sur la case d'arrivée, s'il passe les
-- plafonds de durée et de vitesse et parcourt assez de rampe (RampRules.accept) ; sinon nil et la raison.
function RampSim._finish(
	params: Params,
	points: { Vector3 },
	states: { number },
	dt: number,
	exit: number
): (RampRules.Trajectory?, string)
	local frame = params.frame
	local duration = (#points - 1) * dt
	local peak = RampRules.peakSpeed(points, dt)
	local travel = RampRules.travel(frame, params.entryPos, points[#points])
	if not RampRules.accept(duration, peak, travel, frame.halfU * 2) then
		return nil,
			string.format("refusé (%.1f s, %.0f studs/s, %.0f studs le long de la rampe)", duration, peak, travel)
	end
	return {
		dt = dt,
		points = points,
		states = states,
		duration = duration,
		entry = params.entry,
		exit = exit,
		ramp = params.ramp,
		direction = params.direction,
		peakSpeed = peak,
	},
		"ok"
end

return RampSim

--!strict
-- WallSlide v2 : portage de CGameMovement::TryPlayerMove (Source/Momentum) adapté aux
-- contraintes Roblox :
--   * Sous-pas (substepping) : Source tourne à 64-128 tick sur des faces planes ; à 60 fps
--     et 150+ u/s on parcourt > 1 rayon par frame, ce qui sur une rampe COURBE fait dépasser
--     la corde au-delà de la surface (séparation ou enfoncement). On découpe donc le mouvement
--     en sweeps <= ~0.5 rayon : aucune corde ne peut dépasser la courbure ni tunneler.
--   * Snap de surface : équivalent du ground-snap de Source. On recolle la capsule à la rampe
--     en sondant DEPUIS L'EXTÉRIEUR (sinon Roblox ignore les casts qui démarrent dans une part).

local SURF_THRESHOLD  = 0.7
local MAX_BUMPS       = 4
local MAX_CLIP_PLANES = 5
local SKIN            = 0.015
local PUSH_OUT        = 20.0   -- "a surfer cries"
local MAX_SUBSTEPS    = 48     -- couvre ~300 u/s meme a 20 fps
local MAX_DT          = 1/30  -- borne les sauts apres lag spike
local STEP_FACTOR     = 0.5    -- longueur max d'un sweep = STEP_FACTOR * radius
local SNAP_OUT        = 0.6    -- distance (en rayons) au-dessus de la surface d'ou l'on sonde
local SNAP_IN         = 1.4    -- distance (en rayons) vers la surface
local SNAP_MAX        = 1.0    -- decalage max (en rayons) qu'un snap peut appliquer
local LEAVE_SPEED     = 50     -- au-dela de cette vitesse SORTANTE, on ne recolle pas (saut/ejection)

local penProbe = Instance.new("Part")
penProbe.Anchored = true
penProbe.CanCollide = false
penProbe.CanQuery = false
penProbe.CanTouch = false
penProbe.Transparency = 1
penProbe.Name = "PenProbe"

local penOP = OverlapParams.new()
penOP.FilterType = Enum.RaycastFilterType.Exclude

local function penInfoRaw(pos: Vector3, radius: number, rtb: number, rtt: number): BasePart?
	local centerY = (rtt - rtb) * 0.5
	penProbe.Size = Vector3.new(radius * 2, rtt + rtb, radius * 2) * 0.9
	penProbe.CFrame = CFrame.new(pos + Vector3.new(0, centerY, 0))
	local parts = workspace:GetPartsInPart(penProbe, penOP)
	return parts[1]
end

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local WallSlide = {}

function WallSlide.init(character: Model)
	castParams.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	penOP.FilterDescendantsInstances = { character, workspace.CurrentCamera, penProbe }
	penProbe.Parent = workspace
end

function WallSlide.penInfo(pos: Vector3, ci: { rootToTop: number, rootToBottom: number, radius: number }): BasePart?
	return penInfoRaw(pos, ci.radius - 0.05, ci.rootToBottom, ci.rootToTop)
end

local function hullCast(pos: Vector3, radius: number, rtb: number, rtt: number, moveVec: Vector3): RaycastResult?
	if moveVec.Magnitude < 1e-5 then return nil end
	local centerY = (rtt - rtb) * 0.5
	local cf = CFrame.new(pos + Vector3.new(0, centerY, 0))
	local size = Vector3.new(radius * 2, rtt + rtb, radius * 2)
	return workspace:Blockcast(cf, size, moveVec, castParams)
end

local function clipVelocity(vel: Vector3, normal: Vector3, overbounce: number): Vector3
	local backoff = vel:Dot(normal) * overbounce
	local out = vel - normal * backoff
	local adjust = out:Dot(normal)
	if adjust < 0 then out = out - normal * adjust end
	return out
end

-- Collide-and-slide d'UN sous-pas. Renvoie (velocity, displacement, surfNormal?).
local function slideOnce(
	origin: Vector3, velocity: Vector3, dt: number,
	radius: number, rtb: number, rtt: number
): (Vector3, Vector3, Vector3?)
	local primal     = velocity
	local origVel    = velocity
	local disp       = Vector3.zero
	local found: Vector3? = nil
	local planes: { Vector3 } = {}
	local numplanes  = 0
	local timeLeft   = dt
	local pos        = origin

	for _bump = 1, MAX_BUMPS do
		if velocity.Magnitude < 1e-5 then break end
		local moveVec = velocity * timeLeft
		if moveVec.Magnitude < 1e-5 then break end

		local hit = hullCast(pos, radius, rtb, rtt, moveVec)
		if not hit then
			disp += moveVec
			break
		end

		local fullDist = moveVec.Magnitude
		local moveDir  = moveVec.Unit
		local moved    = math.max(0, hit.Distance - SKIN)

		if moved > 1e-4 then
			pos       += moveDir * moved
			disp      += moveDir * moved
			origVel    = velocity
			numplanes  = 0
			table.clear(planes)
		end

		found = hit.Normal
		timeLeft -= timeLeft * (hit.Distance / fullDist)

		if numplanes >= MAX_CLIP_PLANES then
			velocity = Vector3.zero
			break
		end
		numplanes += 1
		planes[numplanes] = hit.Normal

		if numplanes == 1 then
			velocity = clipVelocity(origVel, planes[1], 1.0)
			origVel = velocity
		else
			local resolved = false
			for i = 1, numplanes do
				local cand = clipVelocity(origVel, planes[i], 1.0)
				local ok = true
				for j = 1, numplanes do
					if j ~= i and cand:Dot(planes[j]) < 0 then ok = false break end
				end
				if ok then velocity = cand resolved = true break end
			end
			if not resolved then
				if numplanes ~= 2 then
					velocity = Vector3.zero
					break
				end
				if (planes[1] - planes[2]).Magnitude < 1e-3 then
					velocity = Vector3.new(
						origVel.X + PUSH_OUT * planes[1].X,
						velocity.Y,
						origVel.Z + PUSH_OUT * planes[1].Z)
					break
				end
				local crease = planes[1]:Cross(planes[2])
				if crease.Magnitude < 1e-4 then
					velocity = clipVelocity(velocity, planes[2], 1.0)
				else
					velocity = crease.Unit * crease.Unit:Dot(velocity)
				end
			end
			if velocity:Dot(primal) <= 0 then
				velocity = Vector3.zero
				break
			end
		end
	end

	return velocity, disp, found
end

function WallSlide.resolve(
	hrp: BasePart, velocity: Vector3, dt: number,
	lastSurfNormal: Vector3?,
	crouchInfo: { rootToTop: number, rootToBottom: number, radius: number, centerOffset: number }
): (Vector3, Vector3, Vector3?)
	local radius = crouchInfo.radius - 0.05
	local rtb, rtt = crouchInfo.rootToBottom, crouchInfo.rootToTop

	-- 1. Decoupage en sous-pas pour qu'aucun sweep ne depasse STEP_FACTOR * radius.
	dt = math.min(dt, MAX_DT)

	local maxStep  = radius * STEP_FACTOR
	local distFull = velocity.Magnitude * dt
	local nSub     = math.ceil(distFull / math.max(maxStep, 1e-3))

	if nSub > MAX_SUBSTEPS then
		-- au-dessus du budget : on limite la distance parcourue ce frame
		-- (leger rubber-band, preferable a un clip a travers le mur)
		nSub = MAX_SUBSTEPS
		dt   = nSub * maxStep / math.max(velocity.Magnitude, 1e-3)
	end

	local subDt = dt / math.max(nSub, 1)

	local origin      = hrp.Position
	local totalDisp   = Vector3.zero
	local foundNormal: Vector3? = nil
	local surfRef: Vector3?     = lastSurfNormal

	for _ = 1, nSub do
		if velocity.Magnitude < 1e-5 then break end
		local v, disp, n = slideOnce(origin, velocity, subDt, radius, rtb, rtt)
		velocity   = v
		origin    += disp
		totalDisp += disp
		if n then
			foundNormal = n
			if n.Y < SURF_THRESHOLD then surfRef = n end
		end
	end

	-- 2. Snap de surface : recoller la capsule a la rampe courbe.
	--    On sonde DEPUIS L'EXTERIEUR (origin + n*SNAP_OUT) vers la surface : ainsi le cast ne
	--    demarre jamais a l'interieur d'une part (sinon Roblox renvoie nil et on traverse).
	if surfRef and velocity:Dot(surfRef) < LEAVE_SPEED then
		local n = surfRef
		local outDist = radius * SNAP_OUT
		local inDist  = radius * (SNAP_OUT + SNAP_IN)
		local snapPos = origin + n * outDist
		local hit = hullCast(snapPos, radius, rtb, rtt, -n * inDist)
		if hit and hit.Normal.Y < SURF_THRESHOLD then
			-- shift le long de n pour reposer a SKIN de la surface (recolle des deux cotes)
			local shiftAmt = outDist - hit.Distance + SKIN
			if math.abs(shiftAmt) <= radius * SNAP_MAX then
				local shift = n * shiftAmt
				origin    += shift
				totalDisp += shift
				velocity = clipVelocity(velocity, hit.Normal, 1.0)
				foundNormal = hit.Normal
			end
		end
	end

	return velocity, totalDisp, foundNormal
end

function WallSlide.commitMove(
	fromSafe: Vector3, candidate: Vector3, velocity: Vector3,
	crouchInfo: { rootToTop: number, rootToBottom: number, radius: number }
): (Vector3, Vector3)
	local r = crouchInfo.radius - 0.05
	local rtb, rtt = crouchInfo.rootToBottom, crouchInfo.rootToTop
	local delta = candidate - fromSafe
	if delta.Magnitude < 1e-5 then return candidate, velocity end
	local dir = delta.Unit

	local hit = hullCast(fromSafe, r, rtb, rtt, delta)
	if not hit then
		-- convexite : la corde peut rater la courbe mais le point final etre dedans
		if penInfoRaw(candidate, r - 0.05, rtb, rtt) then
			return fromSafe, clipVelocity(velocity, dir, 1.0)
		end
		return candidate, velocity
	end

	-- Contact rasant : on longe la surface (dir quasi perpendiculaire a la normale).
	-- Le hull touche deja la rampe → distance ≈ 0, mais ce n'est pas un obstacle frontal.
	-- On garde le candidat tant qu'il ne penetre pas.
	if dir:Dot(hit.Normal) > -0.1 then
		if penInfoRaw(candidate, r - 0.05, rtb, rtt) then
			return fromSafe, clipVelocity(velocity, hit.Normal, 1.0)
		end
		return candidate, velocity
	end

	-- Obstruction frontale reelle : clamp + clip.
	local moved = math.max(0, hit.Distance - SKIN)
	local pos = fromSafe + dir * moved
	local vel = velocity
	if velocity:Dot(hit.Normal) < 0 then
		vel = clipVelocity(velocity, hit.Normal, 1.0)
	end
	return pos, vel
end

return WallSlide

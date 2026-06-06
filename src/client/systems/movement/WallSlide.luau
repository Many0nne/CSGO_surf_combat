local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config       = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local SURF_SKIN      = 1.5
local SURF_THRESHOLD = 0.7
local MAX_BUMPS      = 4
local RETRACE_LEN    = 0.1   -- décalage anti-rampbug (≈ momsurffix_ramp_initial_retrace_length)

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local WallSlide = {}

function WallSlide.init(character: Model)
	castParams.FilterDescendantsInstances = { character, workspace.CurrentCamera }
end

local function capsuleCast(
	bottomCenter: Vector3,
	topCenter: Vector3,
	radius: number,
	moveVec: Vector3,
	params: RaycastParams
): RaycastResult?
	if moveVec.Magnitude < 1e-5 then return nil end
	local midCenter = (bottomCenter + topCenter) * 0.5
	local best: RaycastResult? = nil
	for _, origin in ipairs({ bottomCenter, midCenter, topCenter }) do
		local hit = workspace:Spherecast(origin, radius, moveVec, params)
		if hit and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	return best
end

function WallSlide.resolve(
	hrp: BasePart,
	velocity: Vector3,
	dt: number,
	lastSurfNormal: Vector3?,
	crouchInfo: { rootToTop: number, rootToBottom: number, radius: number, centerOffset: number }
): (Vector3, Vector3, Vector3?)
	local radius  = crouchInfo.radius - 0.05
	local bCenter = hrp.Position - Vector3.new(0, crouchInfo.rootToBottom - radius, 0)
	local tCenter = hrp.Position + Vector3.new(0, crouchInfo.rootToTop  - radius, 0)

	local moveVec        = velocity * dt
	local primalVelocity = velocity
	local foundNormal : Vector3? = nil
	local validNormal : Vector3? = lastSurfNormal   -- dernier plan de surf "valide"
	local posOffset      = Vector3.zero             -- décalage anti-rampbug, appliqué à la fin
	local planes : { Vector3 } = {}

	for _bump = 1, MAX_BUMPS do
		if moveVec.Magnitude < 1e-5 then break end

		local hit = capsuleCast(bCenter, tCenter, radius, moveVec, castParams)
		if not hit then break end

		-- ANTI-RAMPBUG : une normale qui diffère brutalement du dernier plan surf valide
		-- est typiquement une mini-pente parasite sur une jointure. On l'esquive en
		-- décalant le cast le long du plan valide précédent (= "move away from the ramp").
		if validNormal and validNormal.Y < SURF_THRESHOLD and hit.Normal:Dot(validNormal) < 0.7 then
			local nudge = validNormal * RETRACE_LEN
			local reHit = capsuleCast(bCenter + nudge, tCenter + nudge, radius, moveVec, castParams)
			if (not reHit) or reHit.Normal:Dot(validNormal) >= 0.7 then
				bCenter   += nudge
				tCenter   += nudge
				posOffset += nudge
				if not reHit then break end
				hit = reHit
			end
		end

		foundNormal = hit.Normal

		local dotVel = velocity:Dot(hit.Normal)
		if dotVel < 0 then
			velocity = velocity - hit.Normal * dotVel
		end
		if hit.Normal.Y < -0.2 then
			velocity = Vector3.new(velocity.X, math.min(0, velocity.Y), velocity.Z)
		end
		if hit.Normal.Y < SURF_THRESHOLD then
			validNormal = hit.Normal   -- on ne mémorise comme "valide" que les plans surf
		end

		moveVec = velocity * dt
		table.insert(planes, hit.Normal)

		if #planes >= 2 then
			local n1 = planes[#planes - 1]
			local n2 = planes[#planes]
			local crease = n1:Cross(n2)
			if crease.Magnitude > 1e-4 then
				local creaseUnit = crease.Unit
				velocity = creaseUnit * primalVelocity:Dot(creaseUnit)
				if velocity:Dot(n1) < 0 or velocity:Dot(n2) < 0 then
					velocity = Vector3.zero
					moveVec  = Vector3.zero
					break
				end
				moveVec = velocity * dt
			else
				velocity = Vector3.zero
				moveVec  = Vector3.zero
				break
			end
		end
	end

	-- Maintien de contact surf (inchangé)
	if not foundNormal and lastSurfNormal then
		if velocity:Dot(lastSurfNormal) < 0 then
			local mCenter = (bCenter + tCenter) * 0.5
			local probe = workspace:Spherecast(mCenter, radius, -lastSurfNormal * SURF_SKIN, castParams)
			if probe and probe.Normal.Y < SURF_THRESHOLD then
				foundNormal = probe.Normal
			end
		end
	end

	return velocity, moveVec + posOffset, foundNormal
end

return WallSlide

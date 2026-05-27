local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config       = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local RADIUS       = Config.CHAR_RADIUS - 0.05
local SURF_SKIN    = 0.3   -- distance du probe de maintien de contact surf
local SURF_THRESHOLD = 0.7 -- normal.Y < seuil → surface est une rampe surf (≈45°)

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local WallSlide = {}

function WallSlide.init(character: Model)
	castParams.FilterDescendantsInstances = { character }
end

-- Résout la collision de mur/rampe pour un déplacement aérien.
-- lastSurfNormal : normale surf persistante du frame précédent (nil si aucune).
-- Retourne (newVelocity, moveVec, hitNormal) où hitNormal est nil si aucune surface détectée.
function WallSlide.resolve(hrp: BasePart, velocity: Vector3, dt: number, lastSurfNormal: Vector3?): (Vector3, Vector3, Vector3?)
	local moveVec    = velocity * dt
	local foundNormal: Vector3? = nil

	-- Passe 1 : cast dans la direction de la velocity
	if moveVec.Magnitude >= 1e-5 then
		local hit = workspace:Spherecast(hrp.Position, RADIUS, moveVec, castParams)
		if hit then
			foundNormal = hit.Normal
			velocity    = PhysicsUtils.projectOnPlane(velocity, hit.Normal)
			moveVec     = velocity * dt

			-- Passe 2 : re-cast dans la nouvelle direction (comme TryPlayerMove Source)
			if moveVec.Magnitude >= 1e-5 then
				local hit2 = workspace:Spherecast(hrp.Position, RADIUS, moveVec, castParams)
				if hit2 then
					velocity = PhysicsUtils.projectOnPlane(velocity, hit2.Normal)
					moveVec  = velocity * dt
				end
			end
		end
	end

	-- Probe de maintien de contact : ne sert qu'a garder la normale si on est encore "contre" la rampe.
	if not foundNormal and lastSurfNormal then
		-- Si on s'eloigne deja de la rampe, ne pas re-coller artificiellement.
		if velocity:Dot(lastSurfNormal) < 0 then
			local probeDir = -lastSurfNormal * SURF_SKIN
			local probe = workspace:Spherecast(hrp.Position, RADIUS, probeDir, castParams)
			if probe and probe.Normal.Y < SURF_THRESHOLD then
				foundNormal = probe.Normal
			end
		end
	end

	return velocity, moveVec, foundNormal
end

return WallSlide

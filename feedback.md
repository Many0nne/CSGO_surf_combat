Diagnostic des problèmes actuels
Il y a trois bugs principaux dans le système de collision de la tête :
1. Double bloc if headHit identique — la condition est évaluée deux fois, mais le deuxième bloc ne s'exécute jamais correctement car newPos.Y a déjà été modifié dans le premier.
2. Condition de détection erronée — headHit.Position.Y >= currentHead.Y - (crouchInfo.radius * 0.9) est presque toujours vraie pour n'importe quel hit. Il faut utiliser hit.Normal.Y pour distinguer plafond vs mur.
3. WallSlide ne cast que depuis le centre du corps — en l'air, les géométries qui touchent uniquement la tête (plafond bas, rebord) ne sont pas détectées, car le spherecast part de hrp.Position + centerOffset, jamais de la sphère haute.

Solution : capsule approximée + corrections
WallSlide.luau — cast depuis 3 points (bas, centre, haut)
lualocal ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config       = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local SURF_SKIN      = 0.3
local SURF_THRESHOLD = 0.7
local MAX_BUMPS      = 4
local SKIN           = 0.01

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local WallSlide = {}

function WallSlide.init(character: Model)
	castParams.FilterDescendantsInstances = { character }
end

-- Approximation capsule : 3 sphères (bas, centre, haut), retourne le hit le plus proche
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
		local h = workspace:Spherecast(origin, radius, moveVec, params)
		if h and (not best or h.Distance < best.Distance) then
			best = h
		end
	end
	return best
end

-- TryPlayerMove style (MAX_BUMPS passes + crease handling)
-- crouchInfo : { rootToTop, rootToBottom, radius, centerOffset }
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

	local moveVec     = velocity * dt
	local foundNormal : Vector3? = nil
	local planes      : { Vector3 } = {}

	for _bump = 1, MAX_BUMPS do
		if moveVec.Magnitude < 1e-5 then break end

		local hit = capsuleCast(bCenter, tCenter, radius, moveVec, castParams)
		if not hit then break end

		foundNormal = hit.Normal

		-- Clip velocity sur le plan de collision
		local dotVel = velocity:Dot(hit.Normal)
		if dotVel < 0 then
			velocity = velocity - hit.Normal * dotVel
		end

		-- Plafond détecté (normale pointe vers le bas) → tuer la composante montante
		if hit.Normal.Y < -0.2 then
			velocity = Vector3.new(velocity.X, math.min(0, velocity.Y), velocity.Z)
		end

		moveVec = velocity * dt
		table.insert(planes, hit.Normal)

		-- Crease handling : deux plans convergents → se déplacer le long de leur intersection
		if #planes >= 2 then
			local n1 = planes[#planes - 1]
			local n2 = planes[#planes]
			local crease = n1:Cross(n2)
			if crease.Magnitude > 1e-4 then
				local creaseUnit = crease.Unit
				velocity = creaseUnit * velocity:Dot(creaseUnit)
				moveVec  = velocity * dt
			else
				-- Plans opposés quasi-parallèles → bloqué
				velocity = Vector3.zero
				moveVec  = Vector3.zero
				break
			end
		end
	end

	-- Probe de maintien de contact surf
	if not foundNormal and lastSurfNormal then
		if velocity:Dot(lastSurfNormal) < 0 then
			local mCenter = (bCenter + tCenter) * 0.5
			local probe = workspace:Spherecast(mCenter, radius, -lastSurfNormal * SURF_SKIN, castParams)
			if probe and probe.Normal.Y < SURF_THRESHOLD then
				foundNormal = probe.Normal
			end
		end
	end

	return velocity, moveVec, foundNormal
end

return WallSlide

MovementController.luau — sections modifiées
Ajouter cette fonction locale (remplace les deux blocs if headHit en ground state) :
lua-- Détection de collision tête pour l'état sol (plafond bas, rebords latéraux)
-- Retourne le moveVec corrigé et un booléen "bloqué"
local function resolveHeadGround(
	moveVec: Vector3,
	hrpPos: Vector3,
	crouchInfo: { rootToTop: number, radius: number }
): (Vector3, boolean)
	if moveVec.Magnitude < 1e-4 then return moveVec, false end

	local headCenter = Vector3.new(
		hrpPos.X,
		hrpPos.Y + crouchInfo.rootToTop - crouchInfo.radius,
		hrpPos.Z
	)
	local hit = workspace:Spherecast(headCenter, crouchInfo.radius, moveVec, headCastParams)
	if not hit then return moveVec, false end

	-- Plafond (normale vers le bas) ou mur latéral à hauteur de tête
	local isCeiling = hit.Normal.Y < -0.15
	local isHeadWall = not isCeiling and math.abs(hit.Normal.Y) < 0.65
	if not isCeiling and not isHeadWall then return moveVec, false end

	-- Projeter le déplacement sur le plan de collision (Source-style ClipVelocity)
	local clipped = PhysicsUtils.projectOnPlane(moveVec, hit.Normal)

	-- Plafond : forcer Y à 0 (ne pas remonter dans le plafond)
	if isCeiling then
		clipped = Vector3.new(clipped.X, math.min(0, clipped.Y), clipped.Z)
	end

	if Config.HITBOX_DEBUG then
		print(string.format(
			"[HeadCol] %s normalY=%.2f moveY=%.3f→%.3f",
			isCeiling and "CEILING" or "HEADWALL",
			hit.Normal.Y, moveVec.Y, clipped.Y
		))
	end

	return clipped, true
end
Section 8 — état GROUNDED : remplacer les deux blocs if headHit par un seul appel :
lua-- Remplacer tout le bloc headHit (ground) existant par :
local headMoveVec = Vector3.new(
	newPos.X - hrp.Position.X,
	newPos.Y - hrp.Position.Y,
	newPos.Z - hrp.Position.Z
)
local clippedHead, headBlocked = resolveHeadGround(headMoveVec, hrp.Position, crouchInfo)
if headBlocked then
	newPos = hrp.Position + clippedHead
	-- Sync velocity si la tête est bloquée verticalement
	if math.abs(clippedHead.Y - headMoveVec.Y) > 1e-3 then
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
end

hrp.CFrame = CFrame.new(newPos) * targetRot
Section 8 — état AIRBORNE : passer crouchInfo à WallSlide et supprimer le bloc head séparé :
lua-- WallSlide prend maintenant crouchInfo, plus besoin du check head séparé
local newVel, moveVec, hitNormal = WallSlide.resolve(hrp, velocity, dt, surfNormal, crouchInfo)
velocity = newVel
local newPos = hrp.Position + moveVec

hrp.CFrame = CFrame.new(newPos) * targetRot

if hitNormal and hitNormal.Y < 0.7 then
	surfNormal = hitNormal
else
	surfNormal = nil
end

Pourquoi l'approximation capsule par 3 sphères fonctionne
Roblox n'expose pas de CapsuleCast natif. L'approximation par 3 casts (sphère basse, centre, sphère haute) couvre :
CastGéométrie détectéeSphère basseSol, marches, rampes sous les piedsCentreMurs à hauteur de corpsSphère hautePlafonds, rebords sous lesquels on passe
Le seul cas non couvert est une géométrie très fine qui passerait entre deux des trois sphères — en pratique négligeable avec un radius de ~1 stud. Si tu veux une couverture complète, tu peux augmenter à 5 points (quarts + extrémités), mais 3 est suffisant pour du gameplay.
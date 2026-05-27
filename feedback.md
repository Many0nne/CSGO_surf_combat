Les bugs sont clairs maintenant. Trois problèmes distincts dans WallSlide.resolve.

Bug 1 : Traversée du sol — projectOnPlane contre la normale du sol
Quand le joueur tombe et que le spherecast touche le sol (hit.Normal ≈ (0,1,0)), projectOnPlane(velocity, normal) retire la composante Y de la vélocité — ce qui est correct pour la vitesse. Mais newVelocity * dt comme moveVec positionne quand même le joueur à la destination pré-collision, pas à la surface.
Le spherecast retourne un hit.Position et une fraction — il faut s'arrêter là, pas continuer jusqu'à velocity * dt.
Bug 2 : Bhop cassé — même projectOnPlane
Quand le joueur atterrit, WallSlide.resolve est appelé en AIRBORNE (jumpLockout > 0 ou transition pas encore faite). Il touche le sol, fait projectOnPlane contre la normale → velocity.Y devient 0. Le tick suivant, MovementController voit velocity.Y = 0 au lieu de la vitesse de chute, et le bhop ne peut plus mesurer le bon momentum.
La vélocité ne doit jamais être clippée contre une surface onGround depuis WallSlide — c'est le rôle de la transition d'état dans MovementController.
Bug 3 : Pas de résolution multi-bump
Source fait jusqu'à 4 bumps par tick (PM_FlyMove). Ton resolve est single-pass : si le joueur touche un coin, il se coince.

WallSlide corrigé
luaulocal ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config       = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)

local RADIUS     = Config.CHAR_RADIUS - 0.05
local MAX_BUMPS  = 4
local MIN_NORMAL_Y = math.cos(math.rad(Config.SLOPE_ANGLE_MAX))  -- ~0.707 pour 45°

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local WallSlide = {}

function WallSlide.init(character: Model)
	castParams.FilterDescendantsInstances = { character }
end

function WallSlide.resolve(hrp: BasePart, velocity: Vector3, dt: number): (Vector3, Vector3)
	local remainingVel = velocity
	local totalMove    = Vector3.zero
	local timeLeft     = dt

	for _ = 1, MAX_BUMPS do
		local move = remainingVel * timeLeft
		if move.Magnitude < 1e-5 then break end

		local hit = workspace:Spherecast(hrp.Position + totalMove, RADIUS, move, castParams)
		if not hit then
			-- Pas de collision : déplacement libre
			totalMove = totalMove + move
			break
		end

		-- Avancer jusqu'au point de contact (avec légère marge pour éviter de coller)
		local safeFraction = math.max(hit.Distance / move.Magnitude - 0.001, 0)
		totalMove  = totalMove + move * safeFraction
		timeLeft   = timeLeft  * (1 - safeFraction)

		-- Ne clipper que contre les murs (normale majoritairement horizontale).
		-- Les surfaces walkable (sol plat/pente douce) sont gérées par MovementController.
		if hit.Normal.Y > MIN_NORMAL_Y then
			-- Sol ou pente douce : arrêter la descente mais ne pas modifier velocity
			-- MovementController va détecter onGround et gérer la transition
			remainingVel = Vector3.new(remainingVel.X, 0, remainingVel.Z)
			break
		end

		-- Mur / pente raide : ClipVelocity
		remainingVel = PhysicsUtils.projectOnPlane(remainingVel, hit.Normal)

		-- Si après clip la vélocité repart vers la surface, arrêter
		if remainingVel:Dot(hit.Normal) < 0 then
			remainingVel = Vector3.zero
			break
		end
	end

	return remainingVel, totalMove
end

return WallSlide

Ce que ça change concrètement
Traversée réglée : safeFraction arrête le joueur au point de contact exact, pas à velocity * dt.
Bhop réglé : quand hit.Normal.Y > MIN_NORMAL_Y (sol), on ne fait plus de projectOnPlane — velocity.Y reste intact pour que MovementController le lise correctement au tick de transition. On annule juste remainingVel.Y pour stopper la descente ce tick-là.
Multi-bump : 4 iterations comme PM_FlyMove de Source. Coins et arêtes résolus proprement.

Ajustement dans MovementController
Le hrp.CFrame += moveVec actuel ne préserve pas la rotation. À changer :
luauelse
    local newVel, moveVec = WallSlide.resolve(hrp, velocity, dt)
    velocity = newVel
    hrp.CFrame = CFrame.new(hrp.Position + moveVec) * hrp.CFrame.Rotation
end
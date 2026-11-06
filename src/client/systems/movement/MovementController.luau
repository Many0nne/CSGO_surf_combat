local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeadCollisionResolver = require(script.Parent.HeadCollisionResolver)
local GroundDetection = require(script.Parent.GroundDetection)
local PhysicsStepGround = require(script.Parent.PhysicsStepGround)
local PhysicsStepAir = require(script.Parent.PhysicsStepAir)
local StepupSystem = require(script.Parent.StepupSystem)
local WallSlide = require(script.Parent.WallSlide)
local SlopeSystem = require(script.Parent.SlopeSystem)
local CoyoteJump = require(script.Parent.CoyoteJump)
local BhopSystem = require(script.Parent.BhopSystem)
local CrouchSystem = require(script.Parent.CrouchSystem)
local BoostSystem = require(script.Parent.BoostSystem)
local LadderSystem = require(script.Parent.LadderSystem)
local WeaponSystem = require(script.Parent.Parent.weapon.WeaponSystem)
local CharacterSync = require(script.Parent.Parent.network.CharacterSync)
local InputModule = require(script.Parent.Parent.Parent.input.InputModule)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local MovementState = require(ReplicatedStorage.Shared.MovementState)
local SpawnLaunch = require(ReplicatedStorage.Shared.SpawnLaunch)
local LadderRules = require(ReplicatedStorage.Shared.LadderRules)
local CharacterAnimator = require(ReplicatedStorage.Shared.CharacterAnimator)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local StepTiming = require(ReplicatedStorage.Shared.StepTiming)

local JUMP_LOCKOUT = 0.15 -- empêche re-grounding immédiat après un saut
-- Boucle de mouvement, sur le rendu juste avant la caméra (cf. docs/performance.md, « Rythme du mouvement »)
local BIND_NAME = "MovementStep"

local slideParams = RaycastParams.new()
slideParams.FilterType = Enum.RaycastFilterType.Exclude

local MovementController = {}

local lastVelocity = Vector3.zero -- vitesse du dernier pas, lue par la sonde de saccades (debug/FrameProbe)
local stepCount, simulatedTime = 0, 0 -- pas simulés et temps simulé depuis le démarrage (sonde de saccades)

-- Cette méthode permet de lire la vitesse simulée au dernier pas lorsqu'un outil de debug la compare
-- au déplacement réellement rendu.
function MovementController.getVelocity(): Vector3
	return lastVelocity
end

-- Cette méthode permet de lire le nombre de pas et le temps simulés depuis le démarrage lorsque la sonde de saccades
-- compare, frame par frame, le temps simulé au temps rendu.
function MovementController.getStepStats(): (number, number)
	return stepCount, simulatedTime
end

function MovementController.init(char: Model, hrp: BasePart, hum: Humanoid, speedometer, camera)
	local velocity = Vector3.zero
	local state = MovementState.GROUNDED
	local jumpLockout = 0
	local surfNormal: Vector3? = nil -- normale de la rampe surf en contact (nil si aucune)
	local hitboxLogged = false
	local lastSafePos = hrp.Position
	-- Animations 3e personne : jouées sur l'Animator du personnage local, donc répliquées aux autres clients.
	local charAnimator = CharacterAnimator.new(hum)
	CrouchSystem.init(hrp)
	HeadCollisionResolver.init(char)

	CrouchSystem.init(hrp)
	HeadCollisionResolver.init(char)
	GroundDetection.init(char)
	WallSlide.init(char)
	BoostSystem.init()
	LadderSystem.init()
	local ladderRegrab = 0 -- délai avant de pouvoir reprendre une échelle après en avoir sauté

	-- Dernier CFrame posé par ce mouvement : le serveur pose aussi la racine (CharacterSync) et sa valeur, en retard
	-- d'un aller-retour, est répliquée jusqu'ici ; on la remplace par la nôtre avant chaque pas (sinon recul à 20 Hz).
	local ownCFrame: CFrame? = nil
	slideParams.FilterDescendantsInstances = { char, workspace.CurrentCamera }

	local wasGrounded = false

	-- Lancement depuis le soleil (#69) : le serveur pose l'origine puis la vitesse sur le personnage.
	local launched = false
	-- Cette méthode permet d'appliquer une seule fois le lancement du serveur lorsque ses attributs sont arrivés
	-- (déjà là à l'init, ou répliqués juste après) : position, vitesse en l'air et caméra tournée vers la ville.
	local function applyLaunch()
		local origin = char:GetAttribute(SpawnLaunch.ORIGIN_ATTRIBUTE)
		local launchVelocity = char:GetAttribute(SpawnLaunch.VELOCITY_ATTRIBUTE)
		if launched or typeof(origin) ~= "Vector3" or typeof(launchVelocity) ~= "Vector3" then
			return
		end
		launched = true
		hrp.CFrame = CFrame.new(origin) * hrp.CFrame.Rotation
		ownCFrame = hrp.CFrame
		lastSafePos = origin
		velocity = launchVelocity
		state = MovementState.AIRBORNE
		surfNormal = nil
		jumpLockout = JUMP_LOCKOUT
		if camera and camera.setAngles and launchVelocity.Magnitude > 1e-3 then
			camera.setAngles(SpawnLaunch.cameraAngles(launchVelocity))
		end
	end
	applyLaunch()
	char:GetAttributeChangedSignal(SpawnLaunch.VELOCITY_ATTRIBUTE):Connect(applyLaunch)

	-- Cette méthode permet d'avancer le personnage d'un pas de durée dt lorsque la boucle de rendu découpe sa frame
	-- en pas (un seul pas par frame normale, plusieurs après une frame lente : cf. StepTiming).
	local function step(dt: number)
		jumpLockout = math.max(0, jumpLockout - dt)
		ladderRegrab = math.max(0, ladderRegrab - dt)

		-- 1. Détection sol
		local gnd = GroundDetection.getGroundInfo(hrp, velocity.Y, wasGrounded)

		-- 2. Crouch (avant transitions d'état pour connaître halfHeight)
		local crouchInfo = CrouchSystem.update(dt)
		if camera then
			camera.setCamHeight(crouchInfo.camHeight)
		end
		if Config.HITBOX_DEBUG and not hitboxLogged then
			hitboxLogged = true
		end

		-- 3. Transitions d'état
		local isOnGround = gnd.onGround and jumpLockout <= 0
		if isOnGround then
			if state == MovementState.AIRBORNE or state == MovementState.CROUCHING then
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
				surfNormal = nil
			end
			state = crouchInfo.isCrouching and MovementState.CROUCHING or MovementState.GROUNDED
		elseif not gnd.onGround then
			state = crouchInfo.isCrouching and MovementState.CROUCHING or MovementState.AIRBORNE
		end
		-- gnd.onGround=true mais jumpLockout>0 → state reste AIRBORNE/CROUCHING

		local isGroundedState = state == MovementState.GROUNDED or (state == MovementState.CROUCHING and isOnGround)
		local isAirborneState = state == MovementState.AIRBORNE or (state == MovementState.CROUCHING and not isOnGround)

		-- 4. Saut (coyote + buffer + normal) — consomme isJumpPressed() en interne
		local shouldJump = CoyoteJump.update(gnd.onGround, dt)

		-- 5. Direction souhaitée depuis le yaw de la caméra FPS
		local wishdir = InputModule.getWishDir(camera and camera.getCameraYaw() or 0)

		-- 6. Vitesse cible selon mode
		local wishspeed = Config.RUN_SPEED
		if InputModule.isWalking() then
			wishspeed = Config.WALK_SPEED
		end
		if crouchInfo.isCrouching then
			wishspeed = Config.CROUCH_SPEED
		end
		wishspeed = wishspeed * WeaponSystem.getSpeedMultiplier()

		-- 6b. Échelle : remplace la physique sol/air tant qu'on est dans son volume (LadderRules). Au pied, une envie
		-- qui ne monte pas laisse la marche normale (s'écarter, longer le mur).
		local onLadder = false
		local ladderNormal = if ladderRegrab <= 0 then LadderSystem.find(hrp.Position) else nil
		if ladderNormal then
			if shouldJump then
				velocity = LadderRules.jumpOffVelocity(ladderNormal, Config.LADDER_JUMP_OFF)
				ladderRegrab = Config.LADDER_REGRAB
				onLadder = true
			else
				local pitch = camera and camera.getCameraPitch and camera.getCameraPitch() or 0
				local wish3D = InputModule.getWishDir3D(camera and camera.getCameraYaw() or 0, pitch)
				local climbSpeed = Config.LADDER_CLIMB_SPEED * wishspeed / Config.RUN_SPEED
				local climb = LadderRules.climbVelocity(wish3D, ladderNormal, climbSpeed, gnd.onGround)
				if not (gnd.onGround and climb.Y <= 0) then
					velocity = climb
					onLadder = true
				end
			end
			if onLadder then
				state = MovementState.AIRBORNE
				surfNormal = nil
				jumpLockout = JUMP_LOCKOUT
				isGroundedState = false
				isAirborneState = true
			end
		end

		-- 7. Physique
		local velXZ = PhysicsUtils.getXZ(velocity)
		local willJump = false -- saut effectif ce tick (visible jusqu'au déplacement étape 8)

		-- sur une échelle, la vitesse est déjà posée (6b) : ni friction, ni gravité, ni saut normal
		if isGroundedState then
			local projWishdir = gnd.slopeAngle > 1 and SlopeSystem.projectWishDir(wishdir, gnd.normal) or wishdir

			local bhop = BhopSystem.update(gnd.onGround, shouldJump, dt)

			if bhop.skipFriction then
				velXZ = PhysicsUtils.accelerate(velXZ, projWishdir, wishspeed, Config.GROUND_ACCEL, dt)
			else
				velXZ = PhysicsStepGround.step(velXZ, projWishdir, wishspeed, dt)
			end
			velocity = PhysicsUtils.setXZ(velocity, velXZ)

			willJump = shouldJump or bhop.forceJump
			if willJump then
				velocity = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				state = crouchInfo.isCrouching and MovementState.CROUCHING or MovementState.AIRBORNE
			else
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end
		elseif isAirborneState and not onLadder then
			-- StartGravity : demi-pas avant déplacement (schéma leapfrog Source)
			velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
			-- AirAccelerate Source (velocity 3D, surfaceFriction selon contact rampe)
			local surfFric = surfNormal and Config.SURF_FRICTION or 1.0
			velocity = PhysicsStepAir.step(velocity, wishdir, wishspeed, surfFric, dt)
			-- Coyote jump : Space pressé dans la fenêtre coyote
			if shouldJump then
				velocity = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				surfNormal = nil
			end
		end

		-- 8. Déplacer le character
		local targetRot = hrp.CFrame.Rotation
		if camera and camera.getCameraYaw then
			targetRot = CFrame.Angles(0, math.rad(-camera.getCameraYaw()), 0)
		end
		if isGroundedState then
			local snapY = gnd.hitPosition.Y + crouchInfo.rootToBottom
			local moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)

			local stepYOffset, wallNormal, slideNormal = StepupSystem.tryStepup(hrp, moveVec)

			if slideNormal then
				-- Ignorer si c'est la pente sur laquelle on se tient déjà (snapY gère le Y).
				-- Clipper uniquement pour les jointures / angles inattendus.
				local isCurrentGround = gnd.normal and slideNormal:Dot(gnd.normal) > 0.9
				if not isCurrentGround and not willJump then -- en bhop la rampe marchable ne mange pas la vitesse
					local d = velocity:Dot(slideNormal)
					if d < 0 then
						velocity = velocity - slideNormal * d
					end
					moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
				end
			elseif wallNormal and not stepYOffset then
				-- Vrai mur, stepup impossible → projeter la velocity sur le mur.
				local velXZ2 = PhysicsUtils.projectOnPlane(PhysicsUtils.getXZ(velocity), wallNormal)
				velocity = PhysicsUtils.setXZ(velocity, velXZ2)
				moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
			end

			local targetY = stepYOffset and (hrp.Position.Y + stepYOffset) or snapY
			local newPos = Vector3.new(hrp.Position.X + moveVec.X, targetY, hrp.Position.Z + moveVec.Z)

			-- Re-snap Y au sol à la DESTINATION : suit la rampe à la jointure plat→pente.
			-- Sans ça, à grande vitesse le déplacement XZ dépasse là où la rampe monte alors que
			-- le Y reste au niveau du sol actuel → on s'enfonce dans la pente → blocage/rollback
			-- en bhop. On ne fait MONTER que vers une surface marchable (jamais tomber dans un trou).
			if not stepYOffset and moveVec.Magnitude > 1e-3 then
				local up = Config.STEPUP_HEIGHT
				local org = Vector3.new(newPos.X, hrp.Position.Y + up, newPos.Z)
				local down = Vector3.new(0, -(up + crouchInfo.rootToBottom + 0.6), 0)
				local destHit = workspace:Spherecast(org, crouchInfo.radius * 0.9, down, slideParams)
				if destHit and destHit.Normal.Y >= Config.SURF_NORMAL_Y then
					local destSnapY = destHit.Position.Y + crouchInfo.rootToBottom
					if destSnapY > targetY then
						targetY = destSnapY
						newPos = Vector3.new(newPos.X, targetY, newPos.Z)
					end
				end
			end

			local headMoveVec =
				Vector3.new(newPos.X - hrp.Position.X, newPos.Y - hrp.Position.Y, newPos.Z - hrp.Position.Z)
			local clippedHead, headBlocked = HeadCollisionResolver.resolve(headMoveVec, hrp.Position, crouchInfo)
			if headBlocked then
				newPos = hrp.Position + clippedHead
				if math.abs(clippedHead.Y - headMoveVec.Y) > 1e-3 then
					velocity = Vector3.new(velocity.X, 0, velocity.Z)
				end
			end

			-- StepupSystem gère déjà la détection de murs (wallNormal) en grounded.
			-- commitMove causerait des faux positifs sur les pentes (hull cast diagonal → slope face).
			hrp.CFrame = CFrame.new(newPos) * targetRot
			if not WallSlide.penInfo(newPos, crouchInfo) then
				lastSafePos = newPos
			end
		elseif isAirborneState then
			-- Wallslide + surf via ClipVelocity (multi-pass + probe maintien de contact)
			local sBefore = PhysicsUtils.getXZ(velocity).Magnitude
			local newVel, moveVec, hitNormal, stepped = WallSlide.resolve(hrp, velocity, dt, surfNormal, crouchInfo)
			velocity = newVel
			local sResolve = PhysicsUtils.getXZ(velocity).Magnitude
			local candidate = hrp.Position + moveVec
			if stepped then
				-- Rebord enjambé en l'air : commitMove re-clipperait la face verticale, on l'évite.
				candidate = WallSlide.ejectUp(candidate, lastSafePos, crouchInfo)
			else
				candidate, velocity = WallSlide.commitMove(lastSafePos, candidate, velocity, crouchInfo)
			end
			if Config.MOVE_DEBUG then
				local sCommit = PhysicsUtils.getXZ(velocity).Magnitude
				local pen = WallSlide.penInfo(candidate, crouchInfo) ~= nil
				print(
					string.format(
						"[AIR] pos=%s velY=%.0f xz: before=%.0f afterResolve=%.0f afterCommit=%.0f disp=%.2f stepped=%s surf=%s pen=%s",
						tostring(hrp.Position),
						velocity.Y,
						sBefore,
						sResolve,
						sCommit,
						moveVec.Magnitude,
						tostring(stepped),
						surfNormal and ("Y" .. string.format("%.2f", surfNormal.Y)) or "nil",
						tostring(pen)
					)
				)
			end
			hrp.CFrame = CFrame.new(candidate) * targetRot
			if not WallSlide.penInfo(candidate, crouchInfo) then
				lastSafePos = candidate
			end

			-- FinishGravity : demi-pas après déplacement (schéma leapfrog Source), sauf sur une échelle
			if not onLadder then
				velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
			end
			-- Clamp fall speed uniquement hors surf
			if not surfNormal and velocity.Y < -Config.MAX_FALL_SPEED then
				velocity = Vector3.new(velocity.X, -Config.MAX_FALL_SPEED, velocity.Z)
			end

			-- Mise à jour de la surf normale persistante : UNIQUEMENT les vraies rampes surf
			-- (SURF_NORMAL_MIN <= Y < SURF_NORMAL_Y). Une face quasi verticale (Y < MIN) est un MUR,
			-- pas du surf : la stocker désactiverait à tort le clamp de chute et changerait la friction.
			if
				not onLadder
				and hitNormal
				and hitNormal.Y >= Config.SURF_NORMAL_MIN
				and hitNormal.Y < Config.SURF_NORMAL_Y
			then
				surfNormal = hitNormal
			else
				surfNormal = nil
			end
		end

		-- 8b. Boosts de la map (geyser, lanceur, portique) : un geyser ou un lanceur remet le joueur en l'air
		local boosted, boostKind = BoostSystem.check(hrp.Position, velocity, os.clock())
		if boosted then
			velocity = boosted
			if boostKind ~= "Portal" then
				state = MovementState.AIRBORNE
				surfNormal = nil
				jumpLockout = JUMP_LOCKOUT
				isGroundedState = false
				isAirborneState = true
			end
		end

		-- 9. Speedometer
		lastVelocity = velocity
		local spd = PhysicsUtils.getXZ(velocity).Magnitude

		if speedometer then
			speedometer.update(spd)
		end

		-- 10. Animation 3e personne
		charAnimator:update({
			onGround = isGroundedState,
			crouching = crouchInfo.isCrouching,
			surfing = isAirborneState and surfNormal ~= nil,
			speed = spd,
			verticalSpeed = velocity.Y,
		})

		wasGrounded = isGroundedState
		stepCount += 1
		simulatedTime += dt
	end

	-- Sur le rendu, juste avant la caméra (priorité Camera) : le perso avance du temps de la frame affichée, et la
	-- caméra lit dans la même frame la position que ce pas vient de poser. Sur Heartbeat, le pas suivait un autre
	-- chronomètre que l'image et le déplacement affiché variait de 30 % d'une frame à l'autre (saccades en surf).
	-- Rebrancher remplace la boucle du personnage précédent (sinon une boucle de plus par mort).
	RunService:UnbindFromRenderStep(BIND_NAME)
	RunService:BindToRenderStep(
		BIND_NAME,
		Enum.RenderPriority.Camera.Value - 1,
		PerfMarkers.wrap("mouvement", function(rawDt: number)
			if not hrp.Parent then
				return
			end
			if ownCFrame and hrp.CFrame ~= ownCFrame then
				hrp.CFrame = ownCFrame
			end
			local count, dt = StepTiming.split(rawDt)
			for _ = 1, count do
				step(dt)
			end
			ownCFrame = hrp.CFrame
			-- Position envoyée au serveur, qui la valide et la relaie aux autres joueurs (#75)
			CharacterSync.send(hrp, rawDt)
		end)
	)
end

return MovementController

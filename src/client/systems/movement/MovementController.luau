local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeadCollisionResolver = require(script.Parent.HeadCollisionResolver)
local GroundDetection   = require(script.Parent.GroundDetection)
local PhysicsStepGround = require(script.Parent.PhysicsStepGround)
local PhysicsStepAir    = require(script.Parent.PhysicsStepAir)
local StepupSystem      = require(script.Parent.StepupSystem)
local WallSlide         = require(script.Parent.WallSlide)
local SlopeSystem       = require(script.Parent.SlopeSystem)
local CoyoteJump        = require(script.Parent.CoyoteJump)
local BhopSystem        = require(script.Parent.BhopSystem)
local CrouchSystem      = require(script.Parent.CrouchSystem)
local WeaponSystem      = require(script.Parent.Parent.weapon.WeaponSystem)
local InputModule       = require(script.Parent.Parent.Parent.input.InputModule)
local PhysicsUtils      = require(ReplicatedStorage.Shared.PhysicsUtils)
local Config            = require(ReplicatedStorage.Shared.MovementConfig)
local MovementState     = require(ReplicatedStorage.Shared.MovementState)

local JUMP_LOCKOUT = 0.15  -- empêche re-grounding immédiat après un saut

local slideParams = RaycastParams.new()
slideParams.FilterType = Enum.RaycastFilterType.Exclude

local MovementController = {}

function MovementController.init(char: Model, hrp: BasePart, _hum: Humanoid, speedometer, camera)
	local velocity    = Vector3.zero
	local state       = MovementState.GROUNDED
	local jumpLockout = 0
	local surfNormal: Vector3? = nil  -- normale de la rampe surf en contact (nil si aucune)
	local hitboxLogged = false
	local lastSafePos = hrp.Position

	CrouchSystem.init(hrp)
	HeadCollisionResolver.init(char)

	CrouchSystem.init(hrp)
	HeadCollisionResolver.init(char)
	GroundDetection.init(char)
	WallSlide.init(char)
	slideParams.FilterDescendantsInstances = { char, workspace.CurrentCamera }

	local wasGrounded = false


	RunService.Heartbeat:Connect(function(rawDt)
		local dt = math.min(rawDt, 1/30)
		jumpLockout = math.max(0, jumpLockout - dt)

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

		-- 7. Physique
		local velXZ = PhysicsUtils.getXZ(velocity)
		local willJump = false  -- saut effectif ce tick (visible jusqu'au déplacement étape 8)

		if isGroundedState then
			local projWishdir = gnd.slopeAngle > 1
				and SlopeSystem.projectWishDir(wishdir, gnd.normal)
				or wishdir

			local bhop = BhopSystem.update(gnd.onGround, shouldJump, dt)

			if bhop.skipFriction then
				velXZ = PhysicsUtils.accelerate(velXZ, projWishdir, wishspeed, Config.GROUND_ACCEL, dt)
			else
				velXZ = PhysicsStepGround.step(velXZ, projWishdir, wishspeed, dt)
			end
			velocity = PhysicsUtils.setXZ(velocity, velXZ)

			willJump = shouldJump or bhop.forceJump
			if willJump then
				velocity    = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				state       = crouchInfo.isCrouching and MovementState.CROUCHING or MovementState.AIRBORNE
			else
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end

		elseif isAirborneState then
			-- StartGravity : demi-pas avant déplacement (schéma leapfrog Source)
			velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
			-- AirAccelerate Source (velocity 3D, surfaceFriction selon contact rampe)
			local surfFric = surfNormal and Config.SURF_FRICTION or 1.0
			velocity = PhysicsStepAir.step(velocity, wishdir, wishspeed, surfFric, dt)
			-- Coyote jump : Space pressé dans la fenêtre coyote
			if shouldJump then
				velocity    = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				surfNormal  = nil
			end
		end

		-- 8. Déplacer le character
		local targetRot = hrp.CFrame.Rotation
		if camera and camera.getCameraYaw then
			targetRot = CFrame.Angles(0, math.rad(-camera.getCameraYaw()), 0)
		end
		if isGroundedState then
			local snapY   = gnd.hitPosition.Y + crouchInfo.rootToBottom
			local moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)

			local stepYOffset, wallNormal, slideNormal = StepupSystem.tryStepup(hrp, moveVec)

			if slideNormal then
				-- Ignorer si c'est la pente sur laquelle on se tient déjà (snapY gère le Y).
				-- Clipper uniquement pour les jointures / angles inattendus.
				local isCurrentGround = gnd.normal and slideNormal:Dot(gnd.normal) > 0.9
				if not isCurrentGround and not willJump then  -- en bhop la rampe marchable ne mange pas la vitesse
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
				moveVec  = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
			end

			local targetY = stepYOffset and (hrp.Position.Y + stepYOffset) or snapY
			local newPos = Vector3.new(
				hrp.Position.X + moveVec.X,
				targetY,
				hrp.Position.Z + moveVec.Z
			)

			-- Re-snap Y au sol à la DESTINATION : suit la rampe à la jointure plat→pente.
			-- Sans ça, à grande vitesse le déplacement XZ dépasse là où la rampe monte alors que
			-- le Y reste au niveau du sol actuel → on s'enfonce dans la pente → blocage/rollback
			-- en bhop. On ne fait MONTER que vers une surface marchable (jamais tomber dans un trou).
			if not stepYOffset and moveVec.Magnitude > 1e-3 then
				local up   = Config.STEPUP_HEIGHT
				local org  = Vector3.new(newPos.X, hrp.Position.Y + up, newPos.Z)
				local down = Vector3.new(0, -(up + crouchInfo.rootToBottom + 0.6), 0)
				local destHit = workspace:Spherecast(org, crouchInfo.radius * 0.9, down, slideParams)
				if destHit and destHit.Normal.Y >= Config.SURF_NORMAL_Y then
					local destSnapY = destHit.Position.Y + crouchInfo.rootToBottom
					if destSnapY > targetY then
						targetY = destSnapY
						newPos  = Vector3.new(newPos.X, targetY, newPos.Z)
					end
				end
			end

			local headMoveVec = Vector3.new(
				newPos.X - hrp.Position.X,
				newPos.Y - hrp.Position.Y,
				newPos.Z - hrp.Position.Z
			)
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
				print(string.format(
					"[AIR] pos=%s velY=%.0f xz: before=%.0f afterResolve=%.0f afterCommit=%.0f disp=%.2f stepped=%s surf=%s pen=%s",
					tostring(hrp.Position), velocity.Y, sBefore, sResolve, sCommit, moveVec.Magnitude,
					tostring(stepped), surfNormal and ("Y" .. string.format("%.2f", surfNormal.Y)) or "nil", tostring(pen)))
			end
			hrp.CFrame = CFrame.new(candidate) * targetRot
			if not WallSlide.penInfo(candidate, crouchInfo) then
				lastSafePos = candidate
			end

			-- FinishGravity : demi-pas après déplacement (schéma leapfrog Source)
			velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
			-- Clamp fall speed uniquement hors surf
			if not surfNormal and velocity.Y < -Config.MAX_FALL_SPEED then
				velocity = Vector3.new(velocity.X, -Config.MAX_FALL_SPEED, velocity.Z)
			end

			-- Mise à jour de la surf normale persistante : UNIQUEMENT les vraies rampes surf
			-- (SURF_NORMAL_MIN <= Y < SURF_NORMAL_Y). Une face quasi verticale (Y < MIN) est un MUR,
			-- pas du surf : la stocker désactiverait à tort le clamp de chute et changerait la friction.
			if hitNormal and hitNormal.Y >= Config.SURF_NORMAL_MIN and hitNormal.Y < Config.SURF_NORMAL_Y then
				surfNormal = hitNormal
			else
				surfNormal = nil
			end
		end


		-- 9. Speedometer
		local spd = PhysicsUtils.getXZ(velocity).Magnitude

		if speedometer then
			speedometer.update(spd)
		end

		wasGrounded = isGroundedState

	end)
end

return MovementController

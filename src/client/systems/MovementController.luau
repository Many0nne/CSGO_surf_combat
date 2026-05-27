local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundDetection   = require(script.Parent.GroundDetection)
local PhysicsStepGround = require(script.Parent.PhysicsStepGround)
local PhysicsStepAir    = require(script.Parent.PhysicsStepAir)
local StepupSystem      = require(script.Parent.StepupSystem)
local WallSlide         = require(script.Parent.WallSlide)
local SlopeSystem       = require(script.Parent.SlopeSystem)
local CoyoteJump        = require(script.Parent.CoyoteJump)
local BhopSystem        = require(script.Parent.BhopSystem)
local CrouchSystem      = require(script.Parent.CrouchSystem)
local InputModule       = require(script.Parent.Parent.input.InputModule)
local PhysicsUtils      = require(ReplicatedStorage.Shared.PhysicsUtils)
local Config            = require(ReplicatedStorage.Shared.MovementConfig)
local MovementState     = require(ReplicatedStorage.Shared.MovementState)

local JUMP_LOCKOUT = 0.15  -- empêche re-grounding immédiat après un saut

local MovementController = {}

function MovementController.init(_char: Model, hrp: BasePart, _hum: Humanoid, speedometer, camera)
	local velocity    = Vector3.zero
	local state       = MovementState.GROUNDED
	local jumpLockout = 0
	local debugTick   = 0
	local surfNormal: Vector3? = nil  -- normale de la rampe surf en contact (nil si aucune)

	CrouchSystem.init(hrp)

	RunService.Heartbeat:Connect(function(dt)
		jumpLockout = math.max(0, jumpLockout - dt)

		-- 1. Détection sol
		local gnd = GroundDetection.getGroundInfo(hrp)

		-- 2. Crouch (avant transitions d'état pour connaître halfHeight)
		local crouchInfo = CrouchSystem.update(dt)
		if camera then
			camera.setCamHeight(crouchInfo.camHeight)
		end

		-- 3. Transitions d'état
		local isOnGround = gnd.onGround and jumpLockout <= 0
		if isOnGround then
			if state == MovementState.AIRBORNE or state == MovementState.CROUCHING_AIR then
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
				surfNormal = nil
			end
			state = crouchInfo.isCrouching and MovementState.CROUCHING_GROUND or MovementState.GROUNDED
		elseif not gnd.onGround then
			state = crouchInfo.isCrouching and MovementState.CROUCHING_AIR or MovementState.AIRBORNE
		end
		-- gnd.onGround=true mais jumpLockout>0 → state reste AIRBORNE/CROUCHING_AIR

		local isGroundedState = state == MovementState.GROUNDED or state == MovementState.CROUCHING_GROUND
		local isAirborneState = state == MovementState.AIRBORNE or state == MovementState.CROUCHING_AIR

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

		-- 7. Physique
		local velXZ = PhysicsUtils.getXZ(velocity)

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

			local willJump = shouldJump or bhop.forceJump
			if willJump then
				velocity    = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				state       = crouchInfo.isCrouching and MovementState.CROUCHING_AIR or MovementState.AIRBORNE
			else
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end

		elseif isAirborneState then
			-- AirAccelerate Source + gravité (pas de projection wishdir en surf)
			velocity = PhysicsStepAir.step(velocity, wishdir, wishspeed, dt)
			velocity += Vector3.new(0, Config.GRAVITY * dt, 0)
			-- Clamp fall speed uniquement hors surf
			if not surfNormal and velocity.Y < -Config.MAX_FALL_SPEED then
				velocity = Vector3.new(velocity.X, -Config.MAX_FALL_SPEED, velocity.Z)
			end
			-- Coyote jump : Space pressé dans la fenêtre coyote
			if shouldJump then
				velocity    = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				surfNormal  = nil
			end
		end

		-- 8. Déplacer le character
		if isGroundedState then
			local snapY   = gnd.hitPosition.Y + crouchInfo.halfHeight
			local moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
			local stepYOffset, wallNormal = StepupSystem.tryStepup(hrp, moveVec)

			-- Mur détecté, stepup impossible → projeter la velocity sur le mur
			if wallNormal and not stepYOffset then
				local velXZ2 = PhysicsUtils.projectOnPlane(PhysicsUtils.getXZ(velocity), wallNormal)
				velocity = PhysicsUtils.setXZ(velocity, velXZ2)
				moveVec  = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
			end

			local targetY = stepYOffset and (hrp.Position.Y + stepYOffset) or snapY
			hrp.CFrame = CFrame.new(
				hrp.Position.X + moveVec.X,
				targetY,
				hrp.Position.Z + moveVec.Z
			) * hrp.CFrame.Rotation
		elseif isAirborneState then
			-- Wallslide + surf via ClipVelocity (multi-pass + probe maintien de contact)
			local newVel, moveVec, hitNormal = WallSlide.resolve(hrp, velocity, dt, surfNormal)
			velocity = newVel
			hrp.CFrame += moveVec

			-- Mise à jour de la surf normale persistante
			if hitNormal and hitNormal.Y < 0.7 then
				surfNormal = hitNormal
			else
				surfNormal = nil
			end
		end

		-- 9. Speedometer + debug
		local spd = PhysicsUtils.getXZ(velocity).Magnitude
		if speedometer then
			speedometer.update(spd)
		end
		debugTick += dt
		if debugTick >= 0.5 then
			debugTick = 0
			print(string.format("[Speed] XZ=%.1f  Y=%.1f  state=%s", spd, velocity.Y, state))
		end
	end)
end

return MovementController

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
local InputModule       = require(script.Parent.Parent.input.InputModule)
local PhysicsUtils      = require(ReplicatedStorage.Shared.PhysicsUtils)
local Config            = require(ReplicatedStorage.Shared.MovementConfig)
local MovementState     = require(ReplicatedStorage.Shared.MovementState)

local HALF_HEIGHT  = Config.CHAR_HEIGHT_STAND / 2
local JUMP_LOCKOUT = 0.15  -- empêche re-grounding immédiat après un saut

local MovementController = {}

function MovementController.init(_char: Model, hrp: BasePart, _hum: Humanoid, speedometer, camera)
	local velocity   = Vector3.zero
	local state      = MovementState.GROUNDED
	local jumpLockout = 0
	local debugTick  = 0

	RunService.Heartbeat:Connect(function(dt)
		jumpLockout = math.max(0, jumpLockout - dt)

		-- 1. Détection sol
		local gnd = GroundDetection.getGroundInfo(hrp)

		-- 2. Transitions d'état
		if gnd.onGround and jumpLockout <= 0 then
			if state == MovementState.AIRBORNE then
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end
			state = MovementState.GROUNDED
		elseif not gnd.onGround then
			state = MovementState.AIRBORNE
		end
		-- gnd.onGround=true mais jumpLockout>0 → state reste AIRBORNE

		-- 3. Saut (coyote + buffer + normal) — consomme isJumpPressed() en interne
		local shouldJump = CoyoteJump.update(gnd.onGround, dt)

		-- 4. Direction souhaitée depuis le yaw de la caméra FPS
		local wishdir = InputModule.getWishDir(camera and camera.getCameraYaw() or 0)

		-- 5. Vitesse cible selon mode
		local wishspeed = Config.RUN_SPEED
		if InputModule.isWalking() then
			wishspeed = Config.WALK_SPEED
		end

		-- 6. Physique
		local velXZ = PhysicsUtils.getXZ(velocity)

		if state == MovementState.GROUNDED then
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
				state       = MovementState.AIRBORNE
			else
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end

		else
			-- AIRBORNE : AirAccelerate XZ only; pitch does not add Y velocity
			velocity = PhysicsStepAir.step(velocity, wishdir, wishspeed, dt)
			velocity += Vector3.new(0, Config.GRAVITY * dt, 0)
			if velocity.Y < -Config.MAX_FALL_SPEED then
				velocity = Vector3.new(velocity.X, -Config.MAX_FALL_SPEED, velocity.Z)
			end
			-- Coyote jump : Space pressé dans la fenêtre coyote
			if shouldJump then
				velocity    = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
			end
		end

		-- 7. Déplacer le character
		if state == MovementState.GROUNDED then
			local snapY   = gnd.hitPosition.Y + HALF_HEIGHT
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
		else
			-- AIRBORNE : wallslide + surf via ClipVelocity
			local newVel, moveVec = WallSlide.resolve(hrp, velocity, dt)
			velocity = newVel
			hrp.CFrame += moveVec
		end

		-- 8. Speedometer + debug
		local spd = PhysicsUtils.getXZ(velocity).Magnitude
		if speedometer then
			speedometer.update(spd)
		end
		debugTick += dt
		if debugTick >= 0.5 then
			debugTick = 0
			print(string.format("[Speed] XZ=%.1f  Y=%.1f  state=%s", spd, velocity.Y, state))
		end

		-- 9. Bonus : détection de bhop via changement rapide de wishdir — boost temporaire si angle > Config.STRAFE_ASSIST_DEG
		local lastWishdirTime = 0
		local lastWishdir = Vector3.zero

		-- Dans la boucle Heartbeat, avant de calculer wishdir :
		local currentTime = tick()
		if (currentTime - lastWishdirTime) < 0.1 and lastWishdir.Magnitude > 0 then
			-- Si wishdir a changé rapidement, appliquer un boost
			local angleChange = PhysicsUtils.angleDeg(lastWishdir, wishdir)
			if angleChange > 30 then  -- Changement de direction significatif
				wishspeed = wishspeed * 1.2  -- Boost de 20%
			end
		end
		lastWishdir = wishdir
		lastWishdirTime = currentTime
	end)
end

return MovementController

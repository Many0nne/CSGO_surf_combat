local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundDetection   = require(script.Parent.GroundDetection)
local PhysicsStepGround = require(script.Parent.PhysicsStepGround)
local StepupSystem      = require(script.Parent.StepupSystem)
local WallSlide         = require(script.Parent.WallSlide)
local SlopeSystem       = require(script.Parent.SlopeSystem)
local InputModule       = require(script.Parent.Parent.input.InputModule)
local PhysicsUtils      = require(ReplicatedStorage.Shared.PhysicsUtils)
local Config            = require(ReplicatedStorage.Shared.MovementConfig)
local MovementState     = require(ReplicatedStorage.Shared.MovementState)

local HALF_HEIGHT      = Config.CHAR_HEIGHT_STAND / 2
local JUMP_LOCKOUT     = 0.15  -- empêche re-grounding immédiat après un saut
local SLIDE_HYSTERESIS = 2     -- degrés : empêche l'oscillation autour de 45°

local MovementController = {}

function MovementController.init(_char: Model, hrp: BasePart, _hum: Humanoid, speedometer)
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
			local steep = state == MovementState.SLIDING
				and gnd.slopeAngle > (Config.SLOPE_ANGLE_MAX - SLIDE_HYSTERESIS)
				or  gnd.slopeAngle > Config.SLOPE_ANGLE_MAX
			if state == MovementState.AIRBORNE or (state == MovementState.SLIDING and not steep) then
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end
			state = steep and MovementState.SLIDING or MovementState.GROUNDED
		elseif not gnd.onGround then
			state = MovementState.AIRBORNE
		end
		-- gnd.onGround=true mais jumpLockout>0 → state reste AIRBORNE

		-- 3. Direction souhaitée (yaw=0 jusqu'à l'implémentation de FPSCamera)
		local wishdir = InputModule.getWishDir(0)

		-- 4. Vitesse cible selon mode
		local wishspeed = Config.RUN_SPEED
		if InputModule.isWalking() then
			wishspeed = Config.WALK_SPEED
		elseif InputModule.isBackwardOnly() then
			wishspeed = Config.BACKWARD_SPEED_MAX
		end

		-- 5. Physique
		local velXZ = PhysicsUtils.getXZ(velocity)

		if state == MovementState.GROUNDED then
			local projWishdir = gnd.slopeAngle > 1
				and SlopeSystem.projectWishDir(wishdir, gnd.normal)
				or wishdir
			velXZ   = PhysicsStepGround.step(velXZ, projWishdir, wishspeed, dt)
			velocity = PhysicsUtils.setXZ(velocity, velXZ)

			if InputModule.isJumpPressed() then
				velocity    = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
				jumpLockout = JUMP_LOCKOUT
				state       = MovementState.AIRBORNE
			else
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
			end

		elseif state == MovementState.SLIDING then
			-- Gravité projetée sur la pente
			velocity = SlopeSystem.slideStep(velocity, gnd.normal, dt)
			-- Surf : contrôle directionnel le long de la pente (air-accel style, sans friction)
			if wishdir.Magnitude > 1e-4 then
				local surfDir = PhysicsUtils.safeNormalize(PhysicsUtils.projectOnPlane(wishdir, gnd.normal))
				local addSpeed = Config.RUN_SPEED - velocity:Dot(surfDir)
				if addSpeed > 0 then
					local accelSpeed = math.min(Config.SURF_ACCEL * Config.RUN_SPEED * dt, addSpeed)
					velocity += surfDir * accelSpeed
				end
			end
			-- Pas de saut en SLIDING (pieds pas complètement en contact avec le sol)

		else
			-- Pas d'accélération air ici (étape 13) — gravité uniquement
			velocity = PhysicsUtils.setXZ(velocity, velXZ)
			velocity += Vector3.new(0, Config.GRAVITY * dt, 0)
		end

		-- 6. Déplacer le character
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
		elseif state == MovementState.SLIDING then
			local newVel, moveVec = WallSlide.resolve(hrp, velocity, dt)
			velocity = newVel
			local newX = hrp.Position.X + moveVec.X
			local newZ = hrp.Position.Z + moveVec.Z
			-- Snap Y à la surface de la pente au nouveau XZ (empêche d'enfoncer dans la géométrie)
			local targetY = gnd.normal.Y > 1e-4
				and (gnd.hitPosition.Y
					- (newX - gnd.hitPosition.X) * gnd.normal.X / gnd.normal.Y
					- (newZ - gnd.hitPosition.Z) * gnd.normal.Z / gnd.normal.Y
					+ HALF_HEIGHT)
				or (hrp.Position.Y + moveVec.Y)
			hrp.CFrame = CFrame.new(newX, targetY, newZ) * hrp.CFrame.Rotation
		else
			-- AIRBORNE : wallslide
			local newVel, moveVec = WallSlide.resolve(hrp, velocity, dt)
			velocity = newVel
			hrp.CFrame += moveVec
		end

		-- 7. Speedometer + debug
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

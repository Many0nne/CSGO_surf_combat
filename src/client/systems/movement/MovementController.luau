local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterMotor = require(ReplicatedStorage.Shared.movement.CharacterMotor)
local CoyoteJump = require(script.Parent.CoyoteJump)
local BhopSystem = require(script.Parent.BhopSystem)
local CrouchSystem = require(script.Parent.CrouchSystem)
local BoostSystem = require(script.Parent.BoostSystem)
local LadderSystem = require(script.Parent.LadderSystem)
local WeaponSystem = require(script.Parent.Parent.weapon.WeaponSystem)
local CharacterSync = require(script.Parent.Parent.network.CharacterSync)
local LocalSettings = require(script.Parent.Parent.settings.LocalSettings)
local InputModule = require(script.Parent.Parent.Parent.input.InputModule)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local SpawnLaunch = require(ReplicatedStorage.Shared.SpawnLaunch)
local LadderRules = require(ReplicatedStorage.Shared.LadderRules)
local CharacterAnimator = require(ReplicatedStorage.Shared.CharacterAnimator)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local StepTiming = require(ReplicatedStorage.Shared.StepTiming)

-- Boucle de mouvement, sur le rendu juste avant la caméra (cf. docs/performance.md, « Rythme du mouvement »)
local BIND_NAME = "MovementStep"

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

-- Cette méthode permet de couper la boucle de mouvement (entrées, physique, envoi de position) lorsque le joueur quitte
-- la partie par MENU PRINCIPAL, sans attendre la destruction de son personnage (#217) ; init la rebranche au spawn.
function MovementController.stop()
	RunService:UnbindFromRenderStep(BIND_NAME)
end

function MovementController.init(char: Model, hrp: BasePart, hum: Humanoid, speedometer, camera)
	-- Physique et collisions communes avec les bots (#139) ; la racine est écrite à chaque tick (échelles, boosts et
	-- accroupi lisent hrp.Position)
	local motor = CharacterMotor.new(char, hrp, true)
	local hitboxLogged = false
	-- Animations 3e personne : jouées sur l'Animator du personnage local, donc répliquées aux autres clients.
	local charAnimator = CharacterAnimator.new(hum)
	CrouchSystem.init(hrp, motor.dims)
	BoostSystem.init()
	LadderSystem.init()
	local ladderRegrab = 0 -- délai avant de pouvoir reprendre une échelle après en avoir sauté

	-- CFrame simulé au dernier tick : le serveur pose aussi la racine (CharacterSync) et sa valeur, en retard d'un
	-- aller-retour, est répliquée jusqu'ici ; on la remplace par la nôtre avant chaque tick (sinon recul à 20 Hz).
	-- La racine affiche ensuite une position interpolée entre prevCFrame (avant-dernier tick) et ownCFrame (#96).
	local ownCFrame: CFrame? = nil
	local prevCFrame: CFrame? = nil
	local tickAccumulator = 0 -- temps rendu pas encore simulé (< un tick)

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
		motor:teleport(CFrame.new(origin) * hrp.CFrame.Rotation)
		-- Téléportation : pas d'interpolation depuis l'ancienne position (sinon traînée d'une frame vers le soleil)
		ownCFrame = hrp.CFrame
		prevCFrame = hrp.CFrame
		motor.velocity = launchVelocity
		motor:setAirborne()
		if camera and camera.setAngles and launchVelocity.Magnitude > 1e-3 then
			camera.setAngles(SpawnLaunch.cameraAngles(launchVelocity))
		end
	end
	applyLaunch()
	char:GetAttributeChangedSignal(SpawnLaunch.VELOCITY_ATTRIBUTE):Connect(applyLaunch)

	-- Correction du serveur (#172) : position refusée, retour à la dernière position acceptée, vitesse nulle, sans
	-- interpolation depuis l'ancienne position ; l'état (sol, surf) est recalculé au tick suivant.
	CharacterSync.setCorrectionHandler(char, function(pos: Vector3)
		motor:teleport(CFrame.new(pos) * hrp.CFrame.Rotation)
		ownCFrame = hrp.CFrame
		prevCFrame = hrp.CFrame
		motor.velocity = Vector3.zero
		motor:setAirborne()
		lastVelocity = Vector3.zero
	end)

	-- Cette méthode permet d'avancer le personnage d'un tick fixe de durée dt lorsque la boucle de rendu a accumulé
	-- assez de temps (0, 1 ou plusieurs ticks par frame selon le FPS : cf. StepTiming).
	local function step(dt: number)
		ladderRegrab = math.max(0, ladderRegrab - dt)

		-- 1. Détection sol
		local gnd = motor:beginTick(dt)

		-- 2. Crouch (avant transitions d'état pour connaître halfHeight)
		local crouchInfo = CrouchSystem.update(dt)
		if camera then
			camera.setCamHeight(crouchInfo.camHeight)
		end
		if Config.HITBOX_DEBUG and not hitboxLogged then
			hitboxLogged = true
		end

		-- 3. Transitions d'état
		local _, isGroundedState, isAirborneState = motor:updateState(gnd, crouchInfo.isCrouching)

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
				motor.velocity = LadderRules.jumpOffVelocity(ladderNormal, Config.LADDER_JUMP_OFF)
				ladderRegrab = Config.LADDER_REGRAB
				onLadder = true
			else
				local pitch = camera and camera.getCameraPitch and camera.getCameraPitch() or 0
				local wish3D = InputModule.getWishDir3D(camera and camera.getCameraYaw() or 0, pitch)
				local climbSpeed = Config.LADDER_CLIMB_SPEED * wishspeed / Config.RUN_SPEED
				local climb = LadderRules.climbVelocity(wish3D, ladderNormal, climbSpeed, gnd.onGround)
				if not (gnd.onGround and climb.Y <= 0) then
					motor.velocity = climb
					onLadder = true
				end
			end
			if onLadder then
				motor:setAirborne()
				isGroundedState = false
				isAirborneState = true
			end
		end

		-- 7. Physique ; sur une échelle, la vitesse est déjà posée (6b) : ni friction, ni gravité, ni saut normal
		local willJump = false -- saut effectif ce tick (visible jusqu'au déplacement étape 8)
		if isGroundedState then
			local bhop =
				BhopSystem.update(gnd.onGround, shouldJump, dt, InputModule.isJumpHeld(), LocalSettings.get().autoBhop)
			willJump = motor:groundPhysics(
				gnd,
				wishdir,
				wishspeed,
				dt,
				shouldJump or bhop.forceJump,
				bhop.skipFriction,
				crouchInfo.isCrouching
			)
		elseif isAirborneState and not onLadder then
			-- Coyote jump : Space pressé dans la fenêtre coyote
			motor:airPhysics(wishdir, wishspeed, dt, shouldJump)
		end

		-- 8. Déplacer le character
		local targetRot = hrp.CFrame.Rotation
		if camera and camera.getCameraYaw then
			targetRot = CFrame.Angles(0, math.rad(-camera.getCameraYaw()), 0)
		end
		motor:move(gnd, dt, crouchInfo, targetRot, isGroundedState, isAirborneState, willJump, onLadder)

		-- 8b. Boosts de la map (geyser, lanceur, portique) : un geyser ou un lanceur remet le joueur en l'air
		local boosted, boostKind = BoostSystem.check(hrp.Position, motor.velocity, os.clock())
		if boosted then
			-- Plafond horizontal tout de suite : le compteur et l'animation de ce tick ne voient jamais plus (#212)
			motor.velocity = PhysicsUtils.clampHorizontal(boosted, Config.MAX_HORIZONTAL_SPEED)
			if boostKind ~= "Portal" then
				motor:setAirborne()
				isGroundedState = false
				isAirborneState = true
			end
		end

		-- 9. Speedometer
		local velocity = motor.velocity
		lastVelocity = velocity
		local spd = PhysicsUtils.getXZ(velocity).Magnitude

		if speedometer then
			speedometer.update(spd)
		end

		-- 10. Animation 3e personne
		charAnimator:update({
			onGround = isGroundedState,
			crouching = crouchInfo.isCrouching,
			surfing = isAirborneState and motor.surfNormal ~= nil,
			speed = spd,
			verticalSpeed = velocity.Y,
		})

		motor:endTick(isGroundedState)
		stepCount += 1
		simulatedTime += dt
	end

	-- Sur le rendu, juste avant la caméra (priorité Camera) : la physique joue les ticks fixes (64 Hz) contenus dans
	-- le temps de la frame, puis la racine est posée entre les deux derniers ticks, au prorata du temps restant, et la
	-- caméra lit cette position dans la même frame. Ticks fixes : même trajectoire quel que soit le FPS (#96).
	-- Rebrancher remplace la boucle du personnage précédent (sinon une boucle de plus par mort).
	RunService:UnbindFromRenderStep(BIND_NAME)
	RunService:BindToRenderStep(
		BIND_NAME,
		Enum.RenderPriority.Camera.Value - 1,
		PerfMarkers.wrap("mouvement", function(rawDt: number)
			if not hrp.Parent then
				return
			end
			-- La simulation repart toujours de la position simulée, pas de celle affichée ni de l'écho serveur
			if ownCFrame and hrp.CFrame ~= ownCFrame then
				hrp.CFrame = ownCFrame
			end
			motor:syncFromRoot()
			local ticks, alpha
			ticks, tickAccumulator, alpha = StepTiming.advance(tickAccumulator, rawDt)
			for _ = 1, ticks do
				prevCFrame = hrp.CFrame
				step(StepTiming.TICK)
			end
			ownCFrame = hrp.CFrame
			prevCFrame = prevCFrame or ownCFrame
			hrp.CFrame = (prevCFrame :: CFrame):Lerp(ownCFrame :: CFrame, alpha)
			-- Position envoyée au serveur, qui la valide et la relaie aux autres joueurs (#75)
			CharacterSync.send(hrp, rawDt, CrouchSystem.isCrouching())
		end)
	)
end

return MovementController

-- Cœur du mouvement d'un personnage (#139), commun au joueur local (MovementController, client) et aux bots
-- (BotMotion, serveur) : détection du sol, transitions sol/air, physique au sol et en l'air (Source), puis déplacement
-- avec collisions (marches, murs, tête, rampes). L'appelant fournit l'intention (direction, vitesse, saut, accroupi)
-- et garde ce qui dépend de lui (entrées, échelles, boosts, caméra, animation).
--
-- Un tick : beginTick → updateState → groundPhysics ou airPhysics → move → endTick.
-- La position simulée est `cframe` ; elle est écrite sur la racine à chaque tick si `writeRoot` (joueur : les systèmes
-- clients lisent hrp.Position entre deux ticks), sinon c'est l'appelant qui pose la racine (bot : à la cadence réseau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local MovementState = require(ReplicatedStorage.Shared.MovementState)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)
local CharacterDimensions = require(script.Parent.CharacterDimensions)
local GroundDetection = require(script.Parent.GroundDetection)
local StepupSystem = require(script.Parent.StepupSystem)
local WallSlide = require(script.Parent.WallSlide)
local HeadCollisionResolver = require(script.Parent.HeadCollisionResolver)
local SlopeSystem = require(script.Parent.SlopeSystem)
local PhysicsStepGround = require(script.Parent.PhysicsStepGround)
local PhysicsStepAir = require(script.Parent.PhysicsStepAir)

export type CrouchInfo = {
	isCrouching: boolean,
	halfHeight: number,
	rootToBottom: number,
	rootToTop: number,
	centerOffset: number,
	radius: number,
}

local CharacterMotor = {}
CharacterMotor.__index = CharacterMotor

-- Empêche de se reposer au sol juste après un saut, un lancement ou un boost (s).
CharacterMotor.JUMP_LOCKOUT = 0.15

export type CharacterMotor = typeof(setmetatable(
	{} :: {
		hrp: BasePart,
		writeRoot: boolean,
		dims: CharacterDimensions.CharacterDimensions,
		ground: GroundDetection.GroundDetection,
		stepup: StepupSystem.StepupSystem,
		wallSlide: WallSlide.WallSlide,
		head: HeadCollisionResolver.HeadCollisionResolver,
		slideParams: RaycastParams,
		cframe: CFrame,
		velocity: Vector3,
		state: string,
		jumpLockout: number,
		surfNormal: Vector3?, -- normale de la rampe surf en contact (nil si aucune)
		lastSafePos: Vector3,
		wasGrounded: boolean,
	},
	CharacterMotor
))

-- Cette méthode permet de préparer le mouvement d'un personnage lorsqu'il apparaît : dimensions mesurées sur son rig,
-- requêtes de collision qui l'excluent, état au sol à la position de sa racine.
function CharacterMotor.new(char: Model, hrp: BasePart, writeRoot: boolean): CharacterMotor
	local dims = CharacterDimensions.new(char, hrp)
	local slideParams = RaycastParams.new()
	slideParams.FilterType = Enum.RaycastFilterType.Exclude
	slideParams.FilterDescendantsInstances = { char, workspace.CurrentCamera }
	return setmetatable({
		hrp = hrp,
		writeRoot = writeRoot,
		dims = dims,
		ground = GroundDetection.new(char, dims),
		stepup = StepupSystem.new(char, dims),
		wallSlide = WallSlide.new(char),
		head = HeadCollisionResolver.new(char),
		slideParams = slideParams,
		cframe = hrp.CFrame,
		velocity = Vector3.zero,
		state = MovementState.GROUNDED,
		jumpLockout = 0,
		surfNormal = nil,
		lastSafePos = hrp.Position,
		wasGrounded = false,
	}, CharacterMotor)
end

-- Cette méthode permet de donner les dimensions debout du personnage lorsqu'il n'a pas de système d'accroupi (bot).
function CharacterMotor.standInfo(self: CharacterMotor): CrouchInfo
	local stand = self.dims:getStand()
	return {
		isCrouching = false,
		halfHeight = stand.halfHeight,
		rootToBottom = stand.rootToBottom,
		rootToTop = stand.rootToTop,
		centerOffset = stand.centerOffset,
		radius = stand.radius,
	}
end

-- Cette méthode permet de poser la position simulée lorsqu'elle change à la fin d'un déplacement.
function CharacterMotor._place(self: CharacterMotor, cf: CFrame)
	self.cframe = cf
	if self.writeRoot then
		self.hrp.CFrame = cf
	end
end

-- Cette méthode permet de repartir de la racine lorsque l'appelant l'a replacée lui-même (écho serveur, affichage
-- interpolé du joueur entre deux ticks).
function CharacterMotor.syncFromRoot(self: CharacterMotor)
	self.cframe = self.hrp.CFrame
end

-- Cette méthode permet de téléporter le personnage lorsqu'il est lancé depuis le soleil ou replacé : la position
-- devient aussi le dernier point sûr.
function CharacterMotor.teleport(self: CharacterMotor, cf: CFrame)
	self:_place(cf)
	self.hrp.CFrame = cf
	self.lastSafePos = cf.Position
end

-- Cette méthode permet de passer le personnage en l'air lorsqu'une force extérieure l'y projette (lancement,
-- échelle, geyser) : plus de rampe en contact, pas de retour au sol immédiat.
function CharacterMotor.setAirborne(self: CharacterMotor)
	self.state = MovementState.AIRBORNE
	self.surfNormal = nil
	self.jumpLockout = CharacterMotor.JUMP_LOCKOUT
end

-- Cette méthode permet de commencer un tick de durée dt lorsque la boucle de l'appelant en joue un : délai de saut
-- décompté, sol détecté sous la position simulée.
function CharacterMotor.beginTick(self: CharacterMotor, dt: number): GroundDetection.GroundInfo
	self.jumpLockout = math.max(0, self.jumpLockout - dt)
	return self.ground:getGroundInfo(self.cframe.Position, self.velocity.Y, self.wasGrounded)
end

-- Cette méthode permet de choisir l'état du tick (sol, air, accroupi) lorsque le sol vient d'être détecté ; renvoie
-- (au sol réellement, état sol, état air). Un atterrissage annule la vitesse verticale.
function CharacterMotor.updateState(
	self: CharacterMotor,
	gnd: GroundDetection.GroundInfo,
	crouching: boolean
): (boolean, boolean, boolean)
	local isOnGround = gnd.onGround and self.jumpLockout <= 0
	if isOnGround then
		if self.state == MovementState.AIRBORNE or self.state == MovementState.CROUCHING then
			self.velocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
			self.surfNormal = nil
		end
		self.state = crouching and MovementState.CROUCHING or MovementState.GROUNDED
	elseif not gnd.onGround then
		self.state = crouching and MovementState.CROUCHING or MovementState.AIRBORNE
	end
	-- gnd.onGround=true mais jumpLockout>0 → state reste AIRBORNE/CROUCHING
	local isGroundedState = self.state == MovementState.GROUNDED
		or (self.state == MovementState.CROUCHING and isOnGround)
	local isAirborneState = self.state == MovementState.AIRBORNE
		or (self.state == MovementState.CROUCHING and not isOnGround)
	return isOnGround, isGroundedState, isAirborneState
end

-- Cette méthode permet d'appliquer la physique au sol lorsque le tick est en état sol : friction et accélération
-- (sans friction en bhop), projection sur la pente, saut. Renvoie true si le personnage saute ce tick.
function CharacterMotor.groundPhysics(
	self: CharacterMotor,
	gnd: GroundDetection.GroundInfo,
	wishdir: Vector3,
	wishspeed: number,
	dt: number,
	jump: boolean,
	skipFriction: boolean,
	crouching: boolean
): boolean
	local velXZ = PhysicsUtils.getXZ(self.velocity)
	local projWishdir = gnd.slopeAngle > 1 and SlopeSystem.projectWishDir(wishdir, gnd.normal) or wishdir
	if skipFriction then
		velXZ = PhysicsUtils.accelerate(velXZ, projWishdir, wishspeed, Config.GROUND_ACCEL, dt)
	else
		velXZ = PhysicsStepGround.step(velXZ, projWishdir, wishspeed, dt)
	end
	local velocity = PhysicsUtils.setXZ(self.velocity, velXZ)
	if jump then
		velocity = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
		self.jumpLockout = CharacterMotor.JUMP_LOCKOUT
		self.state = crouching and MovementState.CROUCHING or MovementState.AIRBORNE
	else
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
	self.velocity = velocity
	return jump
end

-- Cette méthode permet d'appliquer la physique en l'air lorsque le tick est en état air (hors échelle) : premier
-- demi-pas de gravité, air accelerate Source (friction de surf sur une rampe), saut de coyote.
function CharacterMotor.airPhysics(self: CharacterMotor, wishdir: Vector3, wishspeed: number, dt: number, jump: boolean)
	-- StartGravity : demi-pas avant déplacement (schéma leapfrog Source)
	local velocity = self.velocity + Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
	-- AirAccelerate Source (velocity 3D, surfaceFriction selon contact rampe)
	local surfFric = self.surfNormal and Config.SURF_FRICTION or 1.0
	velocity = PhysicsStepAir.step(velocity, wishdir, wishspeed, surfFric, dt)
	if jump then
		velocity = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
		self.jumpLockout = CharacterMotor.JUMP_LOCKOUT
		self.surfNormal = nil
	end
	self.velocity = velocity
end

-- Cette méthode permet de déplacer le personnage au sol lorsque la vitesse du tick est connue : marches, pentes,
-- murs, recollage au sol à la destination, tête.
local function moveGrounded(
	self: CharacterMotor,
	gnd: GroundDetection.GroundInfo,
	dt: number,
	ci: CrouchInfo,
	targetRot: CFrame,
	willJump: boolean
)
	local velocity = self.velocity
	local pos = self.cframe.Position
	local snapY = gnd.hitPosition.Y + ci.rootToBottom
	local moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)

	local stepYOffset, wallNormal, slideNormal = self.stepup:tryStepup(pos, moveVec)

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

	local targetY = stepYOffset and (pos.Y + stepYOffset) or snapY
	local newPos = Vector3.new(pos.X + moveVec.X, targetY, pos.Z + moveVec.Z)

	-- Re-snap Y au sol à la DESTINATION : suit la rampe à la jointure plat→pente.
	-- Sans ça, à grande vitesse le déplacement XZ dépasse là où la rampe monte alors que
	-- le Y reste au niveau du sol actuel → on s'enfonce dans la pente → blocage/rollback
	-- en bhop. On ne fait MONTER que vers une surface marchable (jamais tomber dans un trou).
	if not stepYOffset and moveVec.Magnitude > 1e-3 then
		local up = Config.STEPUP_HEIGHT
		local org = Vector3.new(newPos.X, pos.Y + up, newPos.Z)
		local down = Vector3.new(0, -(up + ci.rootToBottom + 0.6), 0)
		local destHit = workspace:Spherecast(org, ci.radius * 0.9, down, self.slideParams)
		if destHit and destHit.Normal.Y >= Config.SURF_NORMAL_Y then
			local destSnapY = destHit.Position.Y + ci.rootToBottom
			if destSnapY > targetY then
				targetY = destSnapY
				newPos = Vector3.new(newPos.X, targetY, newPos.Z)
			end
		end
	end

	local headMoveVec = Vector3.new(newPos.X - pos.X, newPos.Y - pos.Y, newPos.Z - pos.Z)
	local clippedHead, headBlocked = self.head:resolve(headMoveVec, pos, ci)
	if headBlocked then
		newPos = pos + clippedHead
		if math.abs(clippedHead.Y - headMoveVec.Y) > 1e-3 then
			velocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
	end

	-- StepupSystem gère déjà la détection de murs (wallNormal) en grounded.
	-- commitMove causerait des faux positifs sur les pentes (hull cast diagonal → slope face).
	self.velocity = velocity
	self:_place(CFrame.new(newPos) * targetRot)
	if not self.wallSlide:penInfo(newPos, ci) then
		self.lastSafePos = newPos
	end
end

-- Cette méthode permet de déplacer le personnage en l'air lorsque la vitesse du tick est connue : glissement sur les
-- murs et rampes (ClipVelocity), second demi-pas de gravité, vitesse de chute bornée hors surf, rampe en contact.
local function moveAirborne(self: CharacterMotor, dt: number, ci: CrouchInfo, targetRot: CFrame, onLadder: boolean)
	local pos = self.cframe.Position
	-- Wallslide + surf via ClipVelocity (multi-pass + probe maintien de contact)
	local sBefore = PhysicsUtils.getXZ(self.velocity).Magnitude
	local velocity, moveVec, hitNormal, stepped = self.wallSlide:resolve(pos, self.velocity, dt, self.surfNormal, ci)
	local sResolve = PhysicsUtils.getXZ(velocity).Magnitude
	local candidate = pos + moveVec
	if stepped then
		-- Rebord enjambé en l'air : commitMove re-clipperait la face verticale, on l'évite.
		candidate = self.wallSlide:ejectUp(candidate, self.lastSafePos, ci)
	else
		candidate, velocity = self.wallSlide:commitMove(self.lastSafePos, candidate, velocity, ci)
	end
	if Config.MOVE_DEBUG then
		local sCommit = PhysicsUtils.getXZ(velocity).Magnitude
		local pen = self.wallSlide:penInfo(candidate, ci) ~= nil
		print(
			string.format(
				"[AIR] pos=%s velY=%.0f xz: before=%.0f afterResolve=%.0f afterCommit=%.0f disp=%.2f stepped=%s surf=%s pen=%s",
				tostring(pos),
				velocity.Y,
				sBefore,
				sResolve,
				sCommit,
				moveVec.Magnitude,
				tostring(stepped),
				self.surfNormal and ("Y" .. string.format("%.2f", (self.surfNormal :: Vector3).Y)) or "nil",
				tostring(pen)
			)
		)
	end
	self:_place(CFrame.new(candidate) * targetRot)
	if not self.wallSlide:penInfo(candidate, ci) then
		self.lastSafePos = candidate
	end

	-- FinishGravity : demi-pas après déplacement (schéma leapfrog Source), sauf sur une échelle
	if not onLadder then
		velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
	end
	-- Clamp fall speed uniquement hors surf
	if not self.surfNormal and velocity.Y < -Config.MAX_FALL_SPEED then
		velocity = Vector3.new(velocity.X, -Config.MAX_FALL_SPEED, velocity.Z)
	end
	self.velocity = velocity

	-- Mise à jour de la surf normale persistante : UNIQUEMENT les vraies rampes surf
	-- (SURF_NORMAL_MIN <= Y < SURF_NORMAL_Y). Une face quasi verticale (Y < MIN) est un MUR,
	-- pas du surf : la stocker désactiverait à tort le clamp de chute et changerait la friction.
	if not onLadder and hitNormal and hitNormal.Y >= Config.SURF_NORMAL_MIN and hitNormal.Y < Config.SURF_NORMAL_Y then
		self.surfNormal = hitNormal
	else
		self.surfNormal = nil
	end
end

-- Cette méthode permet de déplacer le personnage d'un tick lorsque sa vitesse est calculée, selon l'état du tick
-- (sol ou air) ; targetRot est l'orientation à donner à la racine.
function CharacterMotor.move(
	self: CharacterMotor,
	gnd: GroundDetection.GroundInfo,
	dt: number,
	ci: CrouchInfo,
	targetRot: CFrame,
	isGroundedState: boolean,
	isAirborneState: boolean,
	willJump: boolean,
	onLadder: boolean
)
	if isGroundedState then
		moveGrounded(self, gnd, dt, ci, targetRot, willJump)
	elseif isAirborneState then
		moveAirborne(self, dt, ci, targetRot, onLadder)
	end
end

-- Cette méthode permet de clore un tick lorsque le déplacement est fait (hystérésis du sol au tick suivant).
function CharacterMotor.endTick(self: CharacterMotor, isGroundedState: boolean)
	self.wasGrounded = isGroundedState
end

return CharacterMotor

-- Mouvement d'un bot côté serveur (#139) : même physique que le joueur (CharacterMotor), en ticks fixes de 64 Hz
-- (StepTiming), animations 3e personne jouées sur son Animator (répliquées par Roblox), position publiée aux clients à
-- la cadence réseau d'un joueur (CharacterSync.relayBot) pour être interpolée comme la sienne.
-- L'intention (direction, saut, grimpe, bhop) vient du suivi de chemin (BotNavigator, #140, #151), le regard imposé
-- (cible, angle tenu) du comportement (BotBrain, #141) ; sur une échelle,
-- la vitesse est celle du joueur (LadderRules), en poussant vers le mur ; en bhop, air strafe (BotRules).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local BotRules = require(ReplicatedStorage.Shared.BotRules)
local CharacterAnimator = require(ReplicatedStorage.Shared.CharacterAnimator)
local CharacterMotor = require(ReplicatedStorage.Shared.movement.CharacterMotor)
local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local LadderRules = require(ReplicatedStorage.Shared.LadderRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)
local StepTiming = require(ReplicatedStorage.Shared.StepTiming)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local BotNavigator = require(script.Parent.BotNavigator)
local NavPlan = require(script.Parent.NavPlan)

local BotMotion = {}
BotMotion.__index = BotMotion

type Relay = (Model, BasePart, CFrame) -> ()

-- Regard imposé par le comportement (BotBrain, #141) : point regardé (cible en combat, angle tenu), nil pour regarder
-- où il va ; aiming : il vise une cible (rotation rapide, et pas de gain d'air strafe pendant la visée)
export type Gaze = { lookAt: Vector3?, aiming: boolean }

export type BotMotion = typeof(setmetatable(
	{} :: {
		char: Model,
		root: BasePart,
		motor: CharacterMotor.CharacterMotor,
		animator: any,
		relay: Relay,
		rng: Random,
		navigator: BotNavigator.BotNavigator,
		yaw: number,
		tickAccumulator: number,
		sendAccumulator: number,
		frozen: boolean,
		wishSpeed: number,
		gaze: Gaze,
	},
	BotMotion
))

-- Cette méthode permet de lire la vitesse de course d'un bot selon l'arme qu'il tient lorsqu'il apparaît (comme
-- WeaponSystem pour le joueur : RUN_SPEED × RunSpeedMultiplier de l'arme).
local function runSpeedFor(weaponName: string?): number
	local cfg = weaponName and WeaponConfig.Weapons[weaponName]
	local multiplier = if cfg and type(cfg.RunSpeedMultiplier) == "number" then cfg.RunSpeedMultiplier else 1
	return Config.RUN_SPEED * multiplier
end

-- Cette méthode permet de démarrer le mouvement d'un bot lorsqu'il apparaît ; launchVelocity est la vitesse de son
-- lancement depuis le soleil (nil pour une apparition au sol), weaponName l'arme qu'il tient.
function BotMotion.new(
	char: Model,
	root: BasePart,
	humanoid: Humanoid,
	launchVelocity: Vector3?,
	weaponName: string?,
	relay: Relay
): BotMotion
	local rng = Random.new()
	local runSpeed = runSpeedFor(weaponName)
	local self = setmetatable({
		char = char,
		root = root,
		motor = CharacterMotor.new(char, root, false),
		animator = CharacterAnimator.new(humanoid),
		relay = relay,
		rng = rng,
		navigator = BotNavigator.new(rng, runSpeed),
		yaw = rng:NextNumber(0, 360),
		tickAccumulator = 0,
		sendAccumulator = 0,
		frozen = false,
		wishSpeed = runSpeed,
		gaze = { lookAt = nil, aiming = false },
	}, BotMotion)
	if launchVelocity then
		self.motor.velocity = launchVelocity
		self.motor:setAirborne()
		local flat = Vector3.new(launchVelocity.X, 0, launchVelocity.Z)
		if flat.Magnitude > 1e-3 then
			-- Cap = direction du lancement : le bot regarde vers la ville, comme la caméra du joueur lancé
			self.yaw = MathRules.headingDeg(flat.X, flat.Z) % 360
		end
	end
	return self
end

-- Cette méthode permet de régler la vitesse de course lorsque le bot change d'arme (couteau plus rapide que l'AWP).
function BotMotion.setWeapon(self: BotMotion, weaponName: string?)
	local runSpeed = runSpeedFor(weaponName)
	self.wishSpeed = runSpeed
	self.navigator.runSpeed = runSpeed
end

-- Cette méthode permet de figer ou relâcher un bot lorsqu'un outil de debug le demande : figé, il ne veut plus avancer
-- ni sauter, mais la gravité et les collisions continuent.
function BotMotion.setFrozen(self: BotMotion, frozen: boolean)
	self.frozen = frozen
end

-- Cette méthode permet d'avancer le bot d'un tick fixe lorsque la boucle serveur en joue un : intention du suivi de
-- chemin, échelle si le bot est dans son volume, puis le même pas que le joueur (sol, transitions, physique,
-- collisions), puis le regard et l'animation.
function BotMotion._tick(self: BotMotion, dt: number)
	local motor = self.motor
	local gnd = motor:beginTick(dt)
	local _, isGroundedState, isAirborneState = motor:updateState(gnd, false)
	local ci = motor:standInfo()
	local pos = motor.cframe.Position
	local foot = pos - Vector3.new(0, ci.rootToBottom, 0)
	local speedBefore = PhysicsUtils.getXZ(motor.velocity).Magnitude

	local intent = self.navigator:update(NavPlan.get(), foot, isGroundedState, speedBefore, motor.velocity.Y, dt)
	local frozen = self.frozen
	local wishdir = if frozen then Vector3.zero else intent.wishdir
	local wishspeed = if frozen or wishdir.Magnitude < 1e-3 then 0 else self.wishSpeed
	local jump = not frozen and intent.jump

	-- Échelle (comme MovementController) : pousser vers le mur fait monter ; ni friction, ni gravité, ni saut normal
	local onLadder = false
	local plan = NavPlan.get()
	if not frozen and intent.climb and plan then
		local normal = NavPlan.ladderAt(plan, pos)
		if normal then
			motor.velocity = LadderRules.climbVelocity(-normal, normal, Config.LADDER_CLIMB_SPEED, gnd.onGround)
			motor:setAirborne()
			onLadder, isGroundedState, isAirborneState = true, false, true
			wishdir = -normal
		end
	end

	local bhop = not frozen and intent.bhop
	local gaze = self.gaze
	local aiming = gaze.aiming and gaze.lookAt ~= nil
	local willJump = false
	if isGroundedState then
		-- Bhop (#151) : ressaut à l'atterrissage sans friction, la vitesse gagnée en l'air est gardée
		willJump = motor:groundPhysics(gnd, wishdir, wishspeed, dt, jump, bhop and jump, false)
	elseif isAirborneState and not onLadder then
		if bhop and not aiming then
			-- Air strafe vers le cap visé : gain sous la vitesse visée, freinage au-dessus, sinon plane ou tourne
			wishdir, wishspeed =
				BotRules.airStrafe(motor.velocity, wishdir, intent.targetSpeed, wishspeed, dt, intent.strafeNoise)
		elseif bhop or not intent.airControl then
			-- Hors bhop, pas d'air strafe (seul un saut sur un rebord vise sa cible) ; en bhop pendant une visée (#141),
			-- comme un joueur qui arrête de strafer pour tirer, il glisse et garde sa vitesse
			wishdir = Vector3.zero
		end
		motor:airPhysics(wishdir, wishspeed, dt, false)
	end

	-- Regard : vers le point imposé par le comportement (cible, angle tenu) ; sinon en bhop il suit la vitesse (comme
	-- la caméra d'un joueur qui strafe), sinon la direction voulue
	local lookAt = gaze.lookAt
	local wantedYaw = if lookAt
		then BotRules.yawOf(lookAt - pos)
		else BotRules.yawOf(if bhop then motor.velocity else wishdir)
	if wantedYaw then
		local rate = if aiming then BotConfig.COMBAT_TURN_RATE else BotConfig.NAV_TURN_RATE
		self.yaw = BotRules.turnToward(self.yaw, wantedYaw, rate, dt)
	end
	motor:move(gnd, dt, ci, BotRules.headingRotation(self.yaw), isGroundedState, isAirborneState, willJump, onLadder)

	local speed = PhysicsUtils.getXZ(motor.velocity).Magnitude
	self.animator:update({
		onGround = isGroundedState,
		crouching = false,
		surfing = isAirborneState and motor.surfNormal ~= nil,
		speed = speed,
		verticalSpeed = motor.velocity.Y,
	})
	motor:endTick(isGroundedState)
end

-- Cette méthode permet d'avancer le bot du temps serveur écoulé (dt) lorsque Heartbeat passe : ticks fixes joués,
-- puis position publiée au plus NET_SYNC_RATE fois par seconde.
function BotMotion.update(self: BotMotion, dt: number)
	local ticks
	ticks, self.tickAccumulator = StepTiming.advance(self.tickAccumulator, dt)
	for _ = 1, ticks do
		self:_tick(StepTiming.TICK)
	end
	self.sendAccumulator += dt
	if self.sendAccumulator >= CharacterSyncRules.SEND_INTERVAL then
		self.sendAccumulator =
			math.min(self.sendAccumulator - CharacterSyncRules.SEND_INTERVAL, CharacterSyncRules.SEND_INTERVAL)
		self.relay(self.char, self.root, self.motor.cframe)
	end
end

-- Cette méthode permet de lire la position simulée du bot lorsqu'un outil de debug ou la population la demande.
function BotMotion.position(self: BotMotion): Vector3
	return self.motor.cframe.Position
end

return BotMotion

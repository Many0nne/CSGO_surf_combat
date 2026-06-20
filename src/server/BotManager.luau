-- BotManager.luau
-- Server-controlled AI bots (Phase 1: roam + fight). Bots fill empty combatant
-- slots so a lone player always has opponents. They spawn as real R15 avatar
-- rigs (the same kind of character LoadCharacter gives players) so they are
-- visually identical to players — note that in this game the weapon is a
-- first-person viewmodel (camera-only), so even real players show no weapon in
-- third person; nothing extra is needed on the bot for visual parity.
--
-- Bots use a standard enabled Humanoid for locomotion (unlike players, whose
-- Humanoid is disabled in favour of the custom client CFrame movement) —
-- surf/air-strafe is a Phase 2 follow-up.
--
-- A bot is identified by a synthetic NEGATIVE id (real players use positive
-- UserIds), tagged with the IsBot attribute so Validator accepts it as a target
-- and so server code can tell players and bots apart. Each bot keeps a stable
-- identity (id + name + leaderboard score) across respawns.

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ServerStorage      = game:GetService("ServerStorage")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local BotConfig     = require(Shared:WaitForChild("BotConfig"))
local WeaponConfig  = require(Shared:WaitForChild("WeaponConfig"))

-- Bots fire the exact same weapon as players (damage + fire rate from config).
local WEAPON = WeaponConfig.Weapons[BotConfig.WEAPON] or WeaponConfig.Weapons.AWP

local BotManager = {}

type Bot = {
	id: number,
	name: string,
	model: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	head: BasePart?,
	alive: boolean,
	nextShot: number,
	nextThink: number,
	-- AI memory
	hasTarget: boolean,        -- was engaging on the previous tick
	reactionReadyAt: number,   -- earliest os.clock() a freshly spotted enemy may be shot
	lastSeenPos: Vector3?,     -- last position an enemy was seen at
	lastSeenAt: number,        -- os.clock() of last sighting
	lastTargetId: number?,     -- id of the target tracked last tick (for speed estimate)
	targetSpeed: number,       -- estimated horizontal speed of the current target
	strafeDir: number,         -- +1 / -1 committed circle-strafe direction
	strafeFlipAt: number,      -- os.clock() when strafeDir may flip
	wanderTarget: Vector3?,
	nextWander: number,
	-- Pathfinding (navigation around obstacles for hunt/search/wander)
	pathWaypoints: { PathWaypoint }?,
	pathIdx: number,
	pathGoal: Vector3?,
	pathComputing: boolean,
	nextRepath: number,
}

local bots: { [number]: Bot } = {}
local nextBotId    = -1
local nameCursor   = 0

local RoundManager   -- injected via init
local SpawnManager   -- injected via init
local heartbeatConn: RBXScriptConnection?

-- ── helpers ─────────────────────────────────────────────────────────────────

local function realPlayerCount(): number
	return #Players:GetPlayers()
end

local function pickName(): string
	nameCursor += 1
	local names = BotConfig.NAMES
	local base  = names[((nameCursor - 1) % #names) + 1]
	local cycle = math.floor((nameCursor - 1) / #names)
	return cycle == 0 and base or (base .. " (" .. (cycle + 1) .. ")")
end

-- Build a simple block rig when no ServerStorage template is provided.
local function buildBlockRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local hrp = Instance.new("Part")
	hrp.Name         = "HumanoidRootPart"
	hrp.Size         = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide   = false
	hrp.CFrame       = CFrame.new(0, 0, 0)
	hrp.Parent       = model

	local torso = Instance.new("Part")
	torso.Name       = "Torso"
	torso.Size       = Vector3.new(2, 2, 1)
	torso.BrickColor = BrickColor.new("Bright red")
	torso.CFrame     = hrp.CFrame
	torso.Parent     = model

	local head = Instance.new("Part")
	head.Name       = "Head"
	head.Size       = Vector3.new(1.4, 1.2, 1.4)
	head.BrickColor = BrickColor.new("Bright yellow")
	head.CFrame     = hrp.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent     = model

	local function weld(a: BasePart, b: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0  = a
		w.Part1  = b
		w.Parent = a
	end
	weld(hrp, torso)
	weld(hrp, head)

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = hrp
	return model
end

-- Default Roblox avatar grey + standard proportions, so a generated rig looks
-- like a normal player rather than a tiny black blank.
local DEFAULT_GREY = Color3.fromRGB(163, 162, 165)

local function makeDefaultDescription(): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor     = DEFAULT_GREY
	desc.TorsoColor    = DEFAULT_GREY
	desc.LeftArmColor  = DEFAULT_GREY
	desc.RightArmColor = DEFAULT_GREY
	desc.LeftLegColor  = DEFAULT_GREY
	desc.RightLegColor = DEFAULT_GREY
	desc.HeightScale     = 1
	desc.WidthScale      = 1
	desc.DepthScale      = 1
	desc.HeadScale       = 1
	desc.BodyTypeScale   = 0
	desc.ProportionScale = 0
	return desc
end

-- One cached rig template, cloned for every bot. Building it once guarantees all
-- bots are the SAME size (calling CreateHumanoidModelFromDescription per spawn
-- could intermittently fail and fall back to a differently-sized rig).
local rigTemplate: Model? = nil

local function getRigTemplate(): Model?
	if rigTemplate then return rigTemplate end
	-- A hand-authored template in ServerStorage wins, if present.
	local provided = ServerStorage:FindFirstChild(BotConfig.TEMPLATE_NAME)
	if provided and provided:IsA("Model") then
		rigTemplate = provided
		return rigTemplate
	end
	-- Otherwise build one real R15 avatar rig (same kind LoadCharacter gives
	-- players) and keep it detached as the clone source.
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(makeDefaultDescription(), Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		model.Name = "__BotRigTemplate"
		rigTemplate = model
		return rigTemplate
	end
	warn("[BotManager] CreateHumanoidModelFromDescription failed")
	return nil
end

local function buildRig(name: string): Model
	local tmpl = getRigTemplate()
	local model: Model = tmpl and tmpl:Clone() or buildBlockRig(name)
	model.Name = name
	return model
end

-- Attach a visible third-person weapon to the bot's hand by cloning the gun
-- parts out of the first-person viewmodel (ReplicatedStorage.ViewModels.<name>)
-- and welding them to the rig's hand. The viewmodel's arms / fake camera /
-- humanoid are stripped so only the gun shows.
local VIEWMODEL_EXCLUDE = {
	LeftArm = true, RightArm = true, Humanoid = true, HumanoidRootPart = true,
	FakeCamera = true, Animations = true, AnimSaves = true, Sounds = true,
}

local function attachWeapon(model: Model)
	local container = ReplicatedStorage:FindFirstChild("ViewModels")
	local template  = container and container:FindFirstChild(BotConfig.WEAPON)
	if not (template and template:IsA("Model")) then return end

	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then return end

	local handleSrc = template:FindFirstChild("Handle")
	if not (handleSrc and handleSrc:IsA("BasePart")) then return end

	-- Container model holds the gun parts so it's easy to clean up.
	local gun = Instance.new("Model")
	gun.Name = "BotWeapon"

	-- Clone every gun BasePart (skip arms / camera / humanoid / folders).
	local handle: BasePart?
	for _, child in template:GetChildren() do
		if not VIEWMODEL_EXCLUDE[child.Name] then
			local clone = child:Clone()
			if clone:IsA("BasePart") then
				clone.CanCollide = false
				clone.Massless   = true
				clone.Anchored   = false
				clone.Parent     = gun
				if clone.Name == "Handle" then handle = clone end
			end
		end
	end
	if not handle then gun:Destroy(); return end

	-- Rebuild the gun's internal layout relative to its handle (full scale).
	local handleOffset = handleSrc.CFrame:Inverse()
	for _, part in gun:GetChildren() do
		if part:IsA("BasePart") and part ~= handle then
			local src = template:FindFirstChild(part.Name)
			if src and src:IsA("BasePart") then
				local weld = Instance.new("Weld")
				weld.Part0  = handle
				weld.Part1  = part
				weld.C0     = handleOffset * src.CFrame
				weld.Parent = handle
			end
		end
	end

	-- Copy the weapon's sounds onto the handle so shots are audible to everyone
	-- (positional 3D sound from the gun). The viewmodel keeps these in a Sounds
	-- folder; players hear them via the client viewmodel, bots play them here.
	local soundsFolder = template:FindFirstChild("Sounds")
	if soundsFolder then
		for _, s in soundsFolder:GetChildren() do
			if s:IsA("Sound") then
				s:Clone().Parent = handle
			end
		end
	end

	-- Viewmodel guns are oversized for the camera — shrink to character scale.
	gun.PrimaryPart = handle
	gun.Parent      = model
	gun:ScaleTo(BotConfig.WEAPON_SCALE)

	-- Grip: orient the handle in world space so the barrel (handle local +X)
	-- points where the rig faces (-Z) and the scope (local +Y) points up, then
	-- weld it to the hand at that relative offset.
	local desiredPos   = hand.Position + BotConfig.WEAPON_GRIP_OFFSET
	local desiredWorld = CFrame.fromMatrix(desiredPos, Vector3.new(0, 0, -1), Vector3.new(0, 1, 0))
	handle.CFrame = desiredWorld
	local handWeld = Instance.new("Weld")
	handWeld.Part0  = hand
	handWeld.Part1  = handle
	handWeld.C0     = hand.CFrame:Inverse() * desiredWorld
	handWeld.Parent = hand
end

-- ── combatant queries ───────────────────────────────────────────────────────

type Combatant = { id: number, char: Model, hum: Humanoid, root: BasePart }

local function gatherCombatants(excludeModel: Model?): { Combatant }
	local list: { Combatant } = {}
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		if ch and ch ~= excludeModel then
			local hum  = ch:FindFirstChildWhichIsA("Humanoid")
			local root = ch:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root then
				table.insert(list, { id = p.UserId, char = ch, hum = hum, root = root :: BasePart })
			end
		end
	end
	for _, bot in pairs(bots) do
		if bot.alive and bot.model and bot.model ~= excludeModel and bot.humanoid and bot.humanoid.Health > 0 and bot.root then
			table.insert(list, { id = bot.id, char = bot.model, hum = bot.humanoid, root = bot.root })
		end
	end
	return list
end

-- True if the bot has clear line of sight to the target character.
local function hasLineOfSight(bot: Bot, targetRoot: BasePart, targetChar: Model): boolean
	local head = bot.head or bot.root
	if not head then return false end
	local origin = head.Position
	local dir    = targetRoot.Position - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.model :: Instance }
	local result = workspace:Raycast(origin, dir, params)
	if not result then return true end -- nothing in between
	return result.Instance:IsDescendantOf(targetChar)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

local function spawnRig(bot: Bot)
	if not RoundManager.isActive() then return end

	local model    = buildRig(bot.name)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid") :: Humanoid
	local root     = model:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid or not root then
		model:Destroy()
		return
	end

	humanoid.MaxHealth  = BotConfig.HEALTH
	humanoid.Health     = BotConfig.HEALTH
	humanoid.WalkSpeed  = BotConfig.WALK_SPEED
	model:SetAttribute("IsBot", true)
	model:SetAttribute("BotId", bot.id)

	attachWeapon(model)

	local cf = SpawnManager.getRandomSpawnCFrame()
	model:PivotTo(cf)
	model.Parent = workspace

	bot.model     = model
	bot.humanoid  = humanoid
	bot.root      = root
	bot.head      = model:FindFirstChild("Head") :: BasePart? or root
	bot.alive     = true
	bot.nextShot  = 0
	bot.nextThink = 0
	bot.hasTarget = false
	bot.reactionReadyAt = 0
	bot.lastSeenPos = nil
	bot.lastSeenAt  = 0
	bot.lastTargetId = nil
	bot.targetSpeed = 0
	bot.strafeDir   = math.random() < 0.5 and 1 or -1
	bot.strafeFlipAt = 0
	bot.nextWander = 0
	bot.wanderTarget = nil
	bot.pathWaypoints = nil
	bot.pathIdx = 1
	bot.pathGoal = nil
	bot.pathComputing = false
	bot.nextRepath = 0

	humanoid.Died:Connect(function()
		BotManager.onBotDied(bot.id)
	end)
end

local function createBot()
	local id   = nextBotId
	nextBotId -= 1
	local name = pickName()

	local bot: Bot = {
		id = id, name = name, model = nil, humanoid = nil, root = nil, head = nil,
		alive = false, nextShot = 0, nextThink = 0,
		hasTarget = false, reactionReadyAt = 0, lastSeenPos = nil, lastSeenAt = 0,
		lastTargetId = nil, targetSpeed = 0,
		strafeDir = 1, strafeFlipAt = 0, wanderTarget = nil, nextWander = 0,
		pathWaypoints = nil, pathIdx = 1, pathGoal = nil, pathComputing = false, nextRepath = 0,
	}
	bots[id] = bot
	RoundManager.ensureScoreById(id, name)
	spawnRig(bot)
end

local function destroyBot(id: number)
	local bot = bots[id]
	if not bot then return end
	if bot.model then bot.model:Destroy() end
	bots[id] = nil
	RoundManager.removeScoreById(id)
end

function BotManager.onBotDied(id: number)
	local bot = bots[id]
	if not bot or not bot.alive then return end
	bot.alive = false

	RoundManager.onCombatantDied(id, nil)

	if bot.model then bot.model:Destroy() end
	bot.model, bot.humanoid, bot.root, bot.head = nil, nil, nil, nil

	task.delay(BotConfig.RESPAWN_DELAY, function()
		-- Respawn only if this identity still exists and a slot is still wanted.
		if bots[id] and RoundManager.isActive() then
			spawnRig(bot)
		end
	end)
end

local function liveBotCount(): number
	local n = 0
	for _ in pairs(bots) do n += 1 end
	return n
end

function BotManager.despawnAll()
	for id in pairs(bots) do
		destroyBot(id)
	end
end

-- Spawn/despawn bots so total combatants approach TARGET_POPULATION.
function BotManager.maintainPopulation()
	if not RoundManager.isActive() or realPlayerCount() == 0 then
		BotManager.despawnAll()
		return
	end

	local desired = math.clamp(
		BotConfig.TARGET_POPULATION - realPlayerCount(),
		0,
		BotConfig.MAX_BOTS
	)
	local current = liveBotCount()

	while current < desired do
		createBot()
		current += 1
	end
	while current > desired do
		local anyId = next(bots)
		if not anyId then break end
		destroyBot(anyId)
		current -= 1
	end
end

-- ── AI ────────────────────────────────────────────────────────────────────

local function playShootSound(bot: Bot)
	local model  = bot.model
	local gun    = model and model:FindFirstChild("BotWeapon")
	local handle = gun and gun:FindFirstChild("Handle")
	local s      = handle and handle:FindFirstChild("Shoot")
	if s and s:IsA("Sound") then s:Play() end
end

local function fireAt(bot: Bot, target: Combatant)
	local root = bot.root
	if not root then return end
	bot.nextShot = os.clock() + (WEAPON.FireDelay or 1)
	playShootSound(bot)

	-- Real hitscan from the bot's head toward the target, with aim error that
	-- grows with the target's speed (fast movement = harder to hit). Cover
	-- blocks the ray, so a bot can NEVER damage through a wall.
	local origin   = (bot.head or root).Position
	local toTarget = target.root.Position - origin
	local spreadDeg = math.min(
		BotConfig.AIM_SPREAD + (bot.targetSpeed or 0) * BotConfig.AIM_SPREAD_PER_SPEED,
		BotConfig.AIM_SPREAD_MAX
	)
	local spread   = math.rad(spreadDeg)
	local aimCF    = CFrame.lookAt(origin, target.root.Position)
		* CFrame.Angles((math.random() - 0.5) * spread, (math.random() - 0.5) * spread, 0)
	local dir = aimCF.LookVector * toTarget.Magnitude

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.model :: Instance }
	local result = workspace:Raycast(origin, dir, params)
	if result and result.Instance:IsDescendantOf(target.char) then
		RoundManager.recordDamageById(bot.id, target.id)
		target.hum:TakeDamage(WEAPON.Damage)
	end
end

-- Walk toward a world position, navigating around obstacles with a computed
-- path (recomputed when the goal shifts or the repath timer elapses). The path
-- is computed off-thread so the AI tick never yields.
local function navigateTo(bot: Bot, goal: Vector3)
	local hum, root = bot.humanoid, bot.root
	if not hum or not root then return end
	local now = os.clock()

	if not bot.pathComputing then
		local goalMoved = not bot.pathGoal or (bot.pathGoal - goal).Magnitude > 10
		if not bot.pathWaypoints or goalMoved or now >= bot.nextRepath then
			bot.pathComputing = true
			bot.pathGoal      = goal
			bot.nextRepath    = now + BotConfig.REPATH_INTERVAL
			local startPos = root.Position
			task.spawn(function()
				local path = PathfindingService:CreatePath({
					AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
				})
				local ok = pcall(function() path:ComputeAsync(startPos, goal) end)
				if ok and path.Status == Enum.PathStatus.Success then
					bot.pathWaypoints = path:GetWaypoints()
					bot.pathIdx       = 1
				else
					bot.pathWaypoints = nil  -- fall back to a straight move
				end
				bot.pathComputing = false
			end)
		end
	end

	local wps = bot.pathWaypoints
	if wps and bot.pathIdx <= #wps then
		local wp = wps[bot.pathIdx]
		if wp.Action == Enum.PathWaypointAction.Jump then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		hum:MoveTo(wp.Position)
		local flat = Vector3.new(root.Position.X - wp.Position.X, 0, root.Position.Z - wp.Position.Z)
		if flat.Magnitude < 4 then
			bot.pathIdx += 1
		end
	else
		hum:MoveTo(goal)
	end
end

-- Nearest player (regardless of line-of-sight) within a range — used to hunt.
local function nearestPlayerPos(root: BasePart, range: number): Vector3?
	local best: Vector3?
	local bestDist = range
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local r  = ch and ch:FindFirstChild("HumanoidRootPart")
		local h  = ch and ch:FindFirstChildWhichIsA("Humanoid")
		if r and h and h.Health > 0 then
			local d = ((r :: BasePart).Position - root.Position).Magnitude
			if d < bestDist then
				best = (r :: BasePart).Position
				bestDist = d
			end
		end
	end
	return best
end

local function thinkBot(bot: Bot)
	local humanoid, root = bot.humanoid, bot.root
	if not humanoid or not root then return end
	local now = os.clock()

	-- Acquire the nearest visible combatant within detection range.
	local best: Combatant?
	local bestDist = BotConfig.DETECT_RANGE
	for _, c in gatherCombatants(bot.model) do
		local d = (c.root.Position - root.Position).Magnitude
		if d < bestDist and hasLineOfSight(bot, c.root, c.char) then
			best     = c
			bestDist = d
		end
	end

	if best then
		-- ── Engage ──────────────────────────────────────────────────────────
		-- Estimate the target's horizontal speed (used to widen aim error vs
		-- fast-moving / surfing players).
		local targetPos = best.root.Position
		local tspeed = 0
		if bot.hasTarget and bot.lastTargetId == best.id and bot.lastSeenPos then
			local dt = now - bot.lastSeenAt
			if dt > 1e-3 then
				local a = Vector3.new(targetPos.X, 0, targetPos.Z)
				local b = Vector3.new(bot.lastSeenPos.X, 0, bot.lastSeenPos.Z)
				tspeed = (a - b).Magnitude / dt
			end
		end
		bot.targetSpeed  = tspeed
		bot.lastTargetId = best.id
		bot.lastSeenPos  = targetPos
		bot.lastSeenAt   = now
		-- Reaction delay on a fresh acquisition gives the player a beat to react.
		if not bot.hasTarget then
			bot.reactionReadyAt = now + BotConfig.REACTION_TIME
		end
		bot.hasTarget = true
		-- Drop any travel path so leaving combat recomputes a fresh one.
		bot.pathWaypoints = nil

		-- Circle-strafe around the target. AutoRotate keeps the bot facing its
		-- movement direction (Humanoid:Move would otherwise fight a manual CFrame
		-- and freeze the rig).
		humanoid.AutoRotate = true
		local flat = Vector3.new(best.root.Position.X - root.Position.X, 0, best.root.Position.Z - root.Position.Z)
		local fwd  = flat.Magnitude > 0.1 and flat.Unit or Vector3.zero

		-- Commit a strafe direction for a while to avoid jittery back-and-forth.
		if now >= bot.strafeFlipAt then
			bot.strafeDir   = math.random() < 0.5 and 1 or -1
			bot.strafeFlipAt = now + BotConfig.STRAFE_FLIP_INTERVAL
		end

		local side = Vector3.new(-fwd.Z, 0, fwd.X) * bot.strafeDir
		local radial = 0
		if bestDist > BotConfig.PREFERRED_RANGE + BotConfig.RANGE_DEADZONE then
			radial = 1                                   -- approach
		elseif bestDist < BotConfig.PREFERRED_RANGE - BotConfig.RANGE_DEADZONE then
			radial = -1                                  -- back off
		end
		local move = fwd * radial + side * 0.8
		if move.Magnitude > 0.05 then
			humanoid:Move(move.Unit, false)
		else
			humanoid:Move(side, false)                   -- keep strafing in the band
		end

		if now >= bot.nextShot and now >= bot.reactionReadyAt then
			fireAt(bot, best)
		end
		return
	end

	-- ── No visible enemy ──────────────────────────────────────────────────────
	bot.hasTarget = false
	humanoid.AutoRotate = true

	-- Search: navigate to the last place an enemy was seen.
	if bot.lastSeenPos and (now - bot.lastSeenAt) < BotConfig.SEARCH_MEMORY then
		navigateTo(bot, bot.lastSeenPos)
		if (root.Position - bot.lastSeenPos).Magnitude < 8 then
			bot.lastSeenPos = nil                        -- arrived, give up the trail
		end
		return
	end

	-- Hunt: actively navigate toward the nearest player even without sight.
	local hunt = nearestPlayerPos(root, BotConfig.PATROL_RANGE)
	if hunt then
		navigateTo(bot, hunt)
		return
	end

	-- Wander: nobody around — drift to a random nearby point.
	if not bot.wanderTarget or now >= bot.nextWander
		or (root.Position - bot.wanderTarget).Magnitude < 6 then
		local angle = math.random() * math.pi * 2
		local r     = math.random() * BotConfig.WANDER_RADIUS
		bot.wanderTarget = root.Position + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		bot.nextWander   = now + BotConfig.REPATH_INTERVAL
	end
	navigateTo(bot, bot.wanderTarget)
end

local function onHeartbeat()
	if not RoundManager.isActive() then
		if liveBotCount() > 0 then
			BotManager.despawnAll()
		end
		return
	end
	local now = os.clock()
	for _, bot in pairs(bots) do
		if bot.alive and now >= bot.nextThink then
			bot.nextThink = now + BotConfig.THINK_INTERVAL
			thinkBot(bot)
		end
	end
end

-- ── init ────────────────────────────────────────────────────────────────────

function BotManager.init(deps: {
	roundManager: any,
	spawnManager: any,
})
	RoundManager = deps.roundManager
	SpawnManager = deps.spawnManager

	if heartbeatConn then heartbeatConn:Disconnect() end
	heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
end

-- Returns the bot id for a character, or nil if it is not a bot.
function BotManager.getBotId(character: Instance): number?
	local id = character:GetAttribute("BotId")
	if typeof(id) == "number" and bots[id] then
		return id
	end
	return nil
end

return BotManager

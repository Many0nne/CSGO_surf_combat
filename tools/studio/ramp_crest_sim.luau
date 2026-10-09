-- Harnais de repro de l'issue #7 (perte de vitesse a la jonction rampe montante -> sol).
-- A executer en mode Edit dans Studio (barre de commande ou MCP `execute_luau`), sources synchro par Rojo.
-- Rejoue la boucle de MovementController (modules reels, clones pour contourner le cache de require)
-- avec les dimensions du StarterCharacter, sur les deux rampes 30° de la map, en bhop et en course,
-- et compte les "cognements" : perte > 15 % de la vitesse XZ en une frame a moins de 4 studs de l'arete.
-- Attendu apres le correctif : crestHits=0 et notCrossed=0 pour chaque rampe.

local DT = 1 / 60
-- require() garde en cache les modules deja charges dans la session Edit : on echange Shared contre une copie
-- fraiche le temps du run (restaure a la fin) pour toujours tester les sources synchronisees par Rojo.
local realShared = game.ReplicatedStorage.Shared
local freshShared = realShared:Clone()
realShared.Name = "Shared__simReal"
freshShared.Parent = game.ReplicatedStorage

local out = {}
local tmp, char
-- Tout le setup est dans le pcall : Shared est restaure meme si un require echoue.
local ok, err = pcall(function()
	local Config = require(freshShared.MovementConfig)
	local PhysicsUtils = require(freshShared.PhysicsUtils)
	tmp = Instance.new("Folder")
	tmp.Name = "SimTmp"
	local mv = game.StarterPlayer.StarterPlayerScripts.Client.systems.movement:Clone()
	mv.Parent = tmp
	tmp.Parent = game.ServerStorage
	local CharacterDimensions = require(mv.CharacterDimensions)
	local GroundDetection = require(mv.GroundDetection)
	local StepupSystem = require(mv.StepupSystem)
	local WallSlide = require(mv.WallSlide)
	local HeadCollisionResolver = require(mv.HeadCollisionResolver)
	local PhysicsStepAir = require(mv.PhysicsStepAir)
	local SlopeSystem = require(mv.SlopeSystem)

	local rig = game.StarterPlayer.StarterCharacter:Clone()
	rig.Parent = workspace
	CharacterDimensions.init(rig, rig.HumanoidRootPart)
	rig:Destroy()

	char = Instance.new("Model")
	char.Name = "SimChar"
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.CanQuery = false
	hrp.Parent = char
	char.Parent = workspace
	local slideParams = RaycastParams.new()
	slideParams.FilterType = Enum.RaycastFilterType.Exclude
	slideParams.FilterDescendantsInstances = { char, workspace.CurrentCamera }
	GroundDetection.init(char)
	StepupSystem.init(char)
	WallSlide.init(char)
	HeadCollisionResolver.init(char)
	local dims = CharacterDimensions.getStand()
	local ci = {
		isCrouching = false,
		halfHeight = dims.halfHeight,
		rootToBottom = dims.rootToBottom,
		rootToTop = dims.rootToTop,
		centerOffset = dims.centerOffset,
		radius = dims.radius,
	}

	-- Rampes 30° de Maps.Map : 1 = Reflected (monte vers +X), 2 = Map (monte vers -X). crest = X de l'arete.
	local RAMPS = {
		{ z = 0.73, dir = 1, startBase = 660, crest = 733.5, lowY = -208.486 },
		{ z = -84.27, dir = -1, startBase = 877, crest = 803.5, lowY = -208.492 },
	}

	-- Cette méthode permet de simuler un passage de rampe (copie de la boucle Heartbeat de MovementController).
	-- Renvoie la plus grosse perte de vitesse XZ en une frame, sa position X et si l'arete a ete franchie.
	local function run(ramp, mode, speed, startX, zOff)
		hrp.CFrame = CFrame.new(Vector3.new(startX, ramp.lowY + ci.rootToBottom + 0.01, ramp.z + zOff))
		local wishdir = Vector3.new(ramp.dir, 0, 0)
		local velocity = wishdir * speed
		local state, jumpLockout, surfNormal, lastSafePos, wasGrounded = "G", 0, nil, hrp.Position, true
		local maxDrop, dropX, prevSpd = 0, 0, speed
		for _ = 1, 400 do
			local dt = DT
			jumpLockout = math.max(0, jumpLockout - dt)
			local gnd = GroundDetection.getGroundInfo(hrp, velocity.Y, wasGrounded)
			local isOnGround = gnd.onGround and jumpLockout <= 0
			if isOnGround then
				if state == "A" then
					velocity = Vector3.new(velocity.X, 0, velocity.Z)
					surfNormal = nil
				end
				state = "G"
			elseif not gnd.onGround then
				state = "A"
			end
			local isG, isA = state == "G", state == "A"
			local velXZ = PhysicsUtils.getXZ(velocity)
			local willJump = false
			if isG then
				local proj = gnd.slopeAngle > 1 and SlopeSystem.projectWishDir(wishdir, gnd.normal) or wishdir
				willJump = mode == "bhop"
				-- mode "run" : pas de friction, pour isoler l'effet de la jonction
				if willJump then
					velXZ = PhysicsUtils.accelerate(velXZ, proj, Config.RUN_SPEED, Config.GROUND_ACCEL, dt)
				end
				velocity = PhysicsUtils.setXZ(velocity, velXZ)
				if willJump then
					velocity = Vector3.new(velocity.X, Config.JUMP_VELOCITY, velocity.Z)
					jumpLockout = 0.15
					state = "A"
				else
					velocity = Vector3.new(velocity.X, 0, velocity.Z)
				end
			elseif isA then
				velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
				local surfFric = surfNormal and Config.SURF_FRICTION or 1
				velocity = PhysicsStepAir.step(velocity, wishdir, Config.RUN_SPEED, surfFric, dt)
			end
			if isG then
				local snapY = gnd.hitPosition.Y + ci.rootToBottom
				local moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
				local stepYOffset, wallNormal, slideNormal = StepupSystem.tryStepup(hrp, moveVec)
				if slideNormal then
					local isCurrentGround = gnd.normal and slideNormal:Dot(gnd.normal) > 0.9
					if not isCurrentGround and not willJump then
						local d = velocity:Dot(slideNormal)
						if d < 0 then
							velocity = velocity - slideNormal * d
						end
						moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
					end
				elseif wallNormal and not stepYOffset then
					local v2 = PhysicsUtils.projectOnPlane(PhysicsUtils.getXZ(velocity), wallNormal)
					velocity = PhysicsUtils.setXZ(velocity, v2)
					moveVec = Vector3.new(velocity.X * dt, 0, velocity.Z * dt)
				end
				local targetY = stepYOffset and (hrp.Position.Y + stepYOffset) or snapY
				local newPos = Vector3.new(hrp.Position.X + moveVec.X, targetY, hrp.Position.Z + moveVec.Z)
				if not stepYOffset and moveVec.Magnitude > 1e-3 then
					local up = Config.STEPUP_HEIGHT
					local org = Vector3.new(newPos.X, hrp.Position.Y + up, newPos.Z)
					local down = Vector3.new(0, -(up + ci.rootToBottom + 0.6), 0)
					local destHit = workspace:Spherecast(org, ci.radius * 0.9, down, slideParams)
					if destHit and destHit.Normal.Y >= Config.SURF_NORMAL_Y then
						local destSnapY = destHit.Position.Y + ci.rootToBottom
						if destSnapY > targetY then
							newPos = Vector3.new(newPos.X, destSnapY, newPos.Z)
						end
					end
				end
				local clipped, blocked = HeadCollisionResolver.resolve(newPos - hrp.Position, hrp.Position, ci)
				if blocked then
					newPos = hrp.Position + clipped
				end
				hrp.CFrame = CFrame.new(newPos)
				if not WallSlide.penInfo(newPos, ci) then
					lastSafePos = newPos
				end
			elseif isA then
				local newVel, moveVec, hitNormal, stepped = WallSlide.resolve(hrp, velocity, dt, surfNormal, ci)
				velocity = newVel
				local cand = hrp.Position + moveVec
				if stepped then
					cand = WallSlide.ejectUp(cand, lastSafePos, ci)
				else
					cand, velocity = WallSlide.commitMove(lastSafePos, cand, velocity, ci)
				end
				hrp.CFrame = CFrame.new(cand)
				if not WallSlide.penInfo(cand, ci) then
					lastSafePos = cand
				end
				velocity += Vector3.new(0, Config.GRAVITY * 0.5 * dt, 0)
				if not surfNormal and velocity.Y < -Config.MAX_FALL_SPEED then
					velocity = Vector3.new(velocity.X, -Config.MAX_FALL_SPEED, velocity.Z)
				end
				local isSurf = hitNormal
					and hitNormal.Y >= Config.SURF_NORMAL_MIN
					and hitNormal.Y < Config.SURF_NORMAL_Y
				surfNormal = isSurf and hitNormal or nil
			end
			wasGrounded = isG
			local spd = PhysicsUtils.getXZ(velocity).Magnitude
			if prevSpd - spd > maxDrop then
				maxDrop = prevSpd - spd
				dropX = hrp.Position.X
			end
			prevSpd = spd
			if (hrp.Position.X - ramp.crest) * ramp.dir > 15 or hrp.Position.Y < -260 then
				break
			end
		end
		return maxDrop, dropX, (hrp.Position.X - ramp.crest) * ramp.dir > 15
	end

	for ri, ramp in RAMPS do
		local total, bad, notCrossed = 0, 0, 0
		for _, mode in { "bhop", "run" } do
			for speed = 40, 150, 10 do
				for k = 0, 11 do
					for _, zOff in { -4, 0, 4 } do
						local drop, dx, crossed = run(ramp, mode, speed, ramp.startBase - ramp.dir * k * 0.85, zOff)
						total += 1
						if not crossed then
							notCrossed += 1
						end
						if drop > speed * 0.15 and math.abs(dx - ramp.crest) < 4 then
							bad += 1
						end
					end
				end
			end
			task.wait()
		end
		table.insert(out, string.format("ramp%d runs=%d crestHits=%d notCrossed=%d", ri, total, bad, notCrossed))
	end
end)
if not ok then
	table.insert(out, "ERR " .. tostring(err))
end
if char then
	char:Destroy()
end
if tmp then
	tmp:Destroy()
end
freshShared:Destroy()
realShared.Name = "Shared"
local probe = workspace:FindFirstChild("PenProbe")
if probe then
	probe:Destroy()
end
return table.concat(out, "\n")

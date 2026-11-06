-- Scène 3D du menu principal (direction « Ligne de mire ») : canyon de rampes face au soleil couchant, AWP en
-- contre-jour qui suit le curseur, surfeurs qui filent et peuvent être abattus. Tout est local au client et l'éclairage
-- de la place est rétabli à la sortie du menu.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Rules = require(script.Parent.MenuSceneRules)

local MenuScene = {}

local ORIGIN = Vector3.new(0, 900, 0) -- très au-dessus de la map : le canyon et la brume la cachent
local CAMERA_HEIGHT = 6
local CAMERA_FOV = 90
local FIRE_COOLDOWN = 0.7
local SURFER_COUNT = 6
-- Décor au tiers de sa taille apparente : Roblox réduit la distance d'affichage selon la charge, tout doit rester proche
local CANYON_END = 1000
local SEGMENT_LENGTH = 300
local RAMP_WIDTH = 140
local RAMP_HEIGHT = 210
local SURFER_SCALE = 1 / 3
local FLYBY_TIME = 1.15
local RESPAWN_DELAY = 2

local INK = Color3.fromRGB(26, 26, 32)
local RAMP_COLOR = Color3.fromRGB(150, 124, 118)
local RIB_COLOR = Color3.fromRGB(38, 38, 46)
local GLOW = Color3.fromRGB(255, 170, 110)
local TRACER = Color3.fromRGB(255, 220, 170)
local HIT_TRAIL = ColorSequence.new(Color3.fromRGB(226, 58, 40))
local TRAIL = ColorSequence.new(Color3.fromRGB(255, 200, 150), Color3.fromRGB(255, 110, 60))

-- Éclairage du menu : valeurs appliquées à Lighting et à son Atmosphere le temps du menu
local LIGHTING = {
	ClockTime = 17.9,
	GeographicLatitude = 0,
	Brightness = 3.6,
	Ambient = Color3.fromRGB(74, 69, 88),
	OutdoorAmbient = Color3.fromRGB(122, 110, 130),
	ExposureCompensation = 0.35,
}
local ATMOSPHERE = {
	Density = 0.33,
	Offset = 0.05,
	Color = Color3.fromRGB(255, 170, 120),
	Decay = Color3.fromRGB(215, 105, 80),
	Glare = 1,
	Haze = 1.2,
}

local stage: Folder?
local grade: ColorCorrectionEffect?
local viewmodel: Model?
local tracks: { [string]: AnimationTrack } = {}
local sounds: { [string]: Sound } = {}
local surfers: { any } = {}
local flyby: any
local surfaces: { [number]: { point: Vector3, normal: Vector3, up: Vector3 } } = {}
local forward: Vector3
local right: Vector3
local baseCFrame: CFrame
local running = false
local connection: RBXScriptConnection?
local saved: { [Instance]: { [string]: any } } = {}
local savedFov = 70
local aimX, aimY = 0, 0
local kick = 0
local fovKick = 0
local lastShot = 0
local diving = false
local diveTweens: { Tween } = {}

-- Cette méthode permet de mémoriser puis remplacer des propriétés lorsque le menu impose son éclairage.
local function override(instance: Instance?, props: { [string]: any })
	if not instance then
		return
	end
	local previous = saved[instance] or {}
	for name, value in props do
		if previous[name] == nil then
			previous[name] = (instance :: any)[name]
		end
		(instance :: any)[name] = value
	end
	saved[instance] = previous
end

-- Cette méthode permet de rendre à la place son éclairage d'origine lorsque le menu se ferme.
local function restoreOverrides()
	for instance, props in saved do
		for name, value in props do
			(instance :: any)[name] = value
		end
	end
	saved = {}
end

-- Cette méthode permet de créer une pièce de décor sans physique lorsque la scène est construite.
local function makePart(className: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new(className) :: any
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = stage
	return part
end

-- Cette méthode permet de tendre une poutre entre deux points lorsque le canyon reçoit ses lignes et ses nervures.
local function makeBeam(
	from: Vector3,
	to: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return makePart(
		"Part",
		Vector3.new(thickness, thickness, (to - from).Magnitude),
		CFrame.lookAt((from + to) / 2, to),
		color,
		material or Enum.Material.SmoothPlastic
	)
end

-- Cette méthode permet de construire les rampes, leurs lignes lumineuses et leurs nervures lorsque la scène est créée ;
-- elle relève aussi la surface de chaque rampe, sur laquelle roulent les surfeurs.
local function buildCanyon()
	local walls = {}
	for _, side in { -1, 1 } do
		for i = 0, 3 do
			local center = ORIGIN + forward * (85 + i * SEGMENT_LENGTH) + right * side * 40 - Vector3.yAxis * 80
			local base = CFrame.fromMatrix(center, forward, Vector3.yAxis, forward:Cross(Vector3.yAxis))
			local wall = makePart(
				"WedgePart",
				Vector3.new(SEGMENT_LENGTH, RAMP_HEIGHT, RAMP_WIDTH),
				base
					* CFrame.new(0, RAMP_HEIGHT / 2, side * RAMP_WIDTH / 2)
					* CFrame.Angles(0, side == 1 and 0 or math.pi, 0),
				RAMP_COLOR
			)
			wall.CanQuery = true
			table.insert(walls, wall)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = walls
	local function surfaceAt(side: number, distance: number, height: number): (Vector3?, Vector3?)
		local hit = workspace:Raycast(ORIGIN + forward * distance + Vector3.yAxis * height, right * side * 400, params)
		return hit and hit.Position, hit and hit.Normal
	end

	for _, side in { -1, 1 } do
		for _, height in { -20, 20, 63 } do
			for distance = -60, CANYON_END - 60, 340 do
				local from, normal = surfaceAt(side, distance, height)
				local to = surfaceAt(side, distance + 340, height)
				if from and to and normal then
					local isMain = height == 20
					local line = makeBeam(
						from + normal * 0.2,
						to + normal * 0.2,
						isMain and 0.5 or 0.25,
						GLOW,
						Enum.Material.Neon
					)
					line.Transparency = isMain and 0 or 0.35
				end
			end
		end
		for distance = -40, CANYON_END, 40 do
			local from, normal = surfaceAt(side, distance, -57)
			local to = surfaceAt(side, distance, 113)
			if from and to and normal then
				makeBeam(from + normal * 0.15, to + normal * 0.15, 1.2, RIB_COLOR)
			end
		end
		local low, normal = surfaceAt(side, 100, 13)
		local high = surfaceAt(side, 100, 37)
		if low and high and normal then
			surfaces[side] = { point = low, normal = normal, up = (high - low).Unit }
		end
	end
	for _, wall in walls do
		wall.CanQuery = false
	end
end

-- Cette méthode permet de cloner l'AWP du joueur (bras en silhouette) lorsque la scène est créée.
local function buildViewmodel()
	local source = ReplicatedStorage:WaitForChild("ViewModels"):WaitForChild("AWP")
	local model = source:Clone() :: Model
	model.Name = "MenuViewmodel"
	model.Parent = stage
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	for _, armName in { "LeftArm", "RightArm" } do
		local arm = model:FindFirstChild(armName)
		for _, descendant in arm and arm:GetDescendants() or {} do
			if descendant:IsA("BasePart") then
				descendant.Color = INK
			end
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if humanoid and not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animations = model:FindFirstChild("Animations")
	for _, animation in animations and animations:GetChildren() or {} do
		if animator and animation:IsA("Animation") then
			tracks[animation.Name] = animator:LoadAnimation(animation)
		end
	end
	local soundFolder = model:FindFirstChild("Sounds")
	for _, sound in soundFolder and soundFolder:GetChildren() or {} do
		if sound:IsA("Sound") then
			sounds[sound.Name] = sound
		end
	end
	viewmodel = model
end

-- Cette méthode permet de créer un surfeur en silhouette avec sa traînée lorsque la scène est créée ;
-- `scale` réduit les surfeurs du canyon ; renvoie nil si la place n'a pas de StarterCharacter.
local function makeSurfer(scale: number): any
	local template = StarterPlayer:FindFirstChild("StarterCharacter")
	if not template then
		return nil
	end
	local model = template:Clone() :: Model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.Color = INK
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.PlatformStand = true
	end
	model:ScaleTo(scale)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1.4, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -1.6, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = TRAIL
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Parent = root
	model.Parent = stage
	return { model = model, root = root, trail = trail, dead = false, time = 0 }
end

-- Cette méthode permet de renvoyer un surfeur au début du canyon lorsqu'il en sort ou après sa chute.
local function resetSurfer(surfer: any, distance: number?)
	surfer.dead = false
	surfer.trail.Color = TRAIL
	surfer.side = math.random() < 0.5 and -1 or 1
	surfer.distance = distance or (-87 - math.random() * 167)
	surfer.speed = 140 + math.random() * 120
	surfer.height = math.random(-13, 57)
	surfer.phase = math.random() * math.pi * 2
	surfer.time = 0
end

-- Cette méthode permet de construire toute la scène une seule fois lorsque le menu s'ouvre pour la première fois.
local function build()
	local folder = Instance.new("Folder")
	folder.Name = "MenuStage"
	folder.Parent = workspace
	stage = folder

	local sun = Lighting:GetSunDirection()
	forward = Vector3.new(sun.X, 0, sun.Z).Unit
	right = forward:Cross(Vector3.yAxis)
	local camPos = ORIGIN + Vector3.yAxis * CAMERA_HEIGHT
	baseCFrame = CFrame.lookAt(camPos, camPos + forward + Vector3.yAxis * 0.05)

	buildCanyon()
	buildViewmodel()
	for i = 1, SURFER_COUNT do
		local surfer = makeSurfer(SURFER_SCALE)
		if surfer then
			resetSurfer(surfer, -87 + i * 80)
			table.insert(surfers, surfer)
		end
	end
	flyby = makeSurfer(1)
	if flyby then
		flyby.time = -2
		flyby.trail.Lifetime = 0.3
	end
end

-- Cette méthode permet de faire chuter en vrille un surfeur abattu lorsque le tir l'a touché.
local function updateFall(surfer: any, dt: number)
	surfer.velocity += Vector3.new(0, -100 * dt, 0)
	local spin = surfer.spin * dt
	local position = surfer.pose.Position + surfer.velocity * dt
	surfer.pose = CFrame.new(position) * surfer.pose.Rotation * CFrame.Angles(spin.X, spin.Y, spin.Z)
	surfer.model:PivotTo(surfer.pose)
end

-- Cette méthode permet de faire avancer les surfeurs sur leur rampe et le passage rapproché lorsqu'une image est rendue.
local function updateSurfers(dt: number, now: number)
	for _, surfer in surfers do
		if surfer.dead then
			updateFall(surfer, dt)
			if now - surfer.deadAt > RESPAWN_DELAY then
				resetSurfer(surfer)
			end
		else
			surfer.distance += surfer.speed * dt
			surfer.time += dt
			local surface = surfaces[surfer.side]
			if surface then
				local offset = (surfer.height - 13) + math.sin(surfer.time * 1.1 + surfer.phase) * 11
				local position = surface.point
					+ forward * (surfer.distance - 100)
					+ surface.up * offset
					+ surface.normal * 1.15
				surfer.model:PivotTo(
					CFrame.fromMatrix(position, forward:Cross(surface.normal), surface.normal, -forward)
				)
			end
			if surfer.distance > CANYON_END then
				resetSurfer(surfer)
			end
		end
	end

	if not flyby then
		return
	end
	flyby.time += dt
	if flyby.dead then
		updateFall(flyby, dt)
		if now - flyby.deadAt > RESPAWN_DELAY then
			flyby.dead = false
			flyby.time = -4
			flyby.trail.Color = TRAIL
		end
		return
	end
	local camPos = baseCFrame.Position
	local a = camPos - forward * 70 - right * 46 - Vector3.yAxis * 16
	local b = camPos + forward * 16 - right * 17 + Vector3.yAxis * 7
	local c = camPos + forward * 420 + right * 90 + Vector3.yAxis * 40
	local t = math.clamp(flyby.time / FLYBY_TIME, 0, 1)
	local position = Rules.bezier(a, b, c, t)
	local direction = ((b - a) * (1 - t) + (c - b) * t).Unit
	flyby.model:PivotTo(CFrame.lookAt(position, position + direction) * CFrame.Angles(0, 0, math.rad(-55)))
	if flyby.time > FLYBY_TIME then
		flyby.time = -(3.5 + math.random() * 3)
	end
end

-- Cette méthode permet de placer la caméra et l'arme selon le curseur et le recul lorsqu'une image est rendue.
local function updateView(dt: number)
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local viewport = camera.ViewportSize
	aimX = Rules.damp(aimX, (mouse.X / viewport.X - 0.5) * 2, dt, 9)
	aimY = Rules.damp(aimY, (mouse.Y / viewport.Y - 0.5) * 2, dt, 9)
	kick = Rules.decayKick(kick, dt)
	fovKick = math.max(0, fovKick - dt * 12)

	local angles = Rules.aimAngles(aimX, aimY, kick)
	local camCFrame = baseCFrame * CFrame.Angles(math.rad(angles.camPitch), math.rad(angles.camYaw), 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camCFrame
	if not diving then
		camera.FieldOfView = CAMERA_FOV - fovKick
	end
	if viewmodel then
		viewmodel:PivotTo(
			camCFrame
				* CFrame.Angles(math.rad(angles.gunPitch - angles.camPitch), math.rad(angles.gunYaw - angles.camYaw), 0)
				* CFrame.new(0.25, -0.2, kick * 0.35)
		)
	end
end

-- Cette méthode permet de dessiner la flamme et le traceur lorsque l'arme tire vers la direction visée.
local function spawnShotEffects(direction: Vector3, origin: Vector3)
	local barrel = viewmodel and viewmodel:FindFirstChild("Barrel") :: BasePart?
	local tip = (barrel and barrel.Position or origin) + direction * 4
	local tracer = makeBeam(tip, origin + direction * 900, 0.22, TRACER, Enum.Material.Neon)
	TweenService:Create(tracer, TweenInfo.new(0.16), { Transparency = 1 }):Play()
	task.delay(0.2, tracer.Destroy, tracer)

	local flash = makePart("Part", Vector3.one * 1.6, CFrame.new(tip), TRACER, Enum.Material.Neon)
	flash.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 6
	light.Color = GLOW
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.07), { Size = Vector3.one * 0.2, Transparency = 1 }):Play()
	task.delay(0.1, flash.Destroy, flash)
end

-- Cette méthode permet d'abattre le premier surfeur visible sous le tir lorsque l'arme fait feu ; renvoie true s'il y en a un.
local function resolveHit(x: number, y: number, camera: Camera): boolean
	local candidates = table.clone(surfers)
	if flyby then
		table.insert(candidates, flyby)
	end
	for _, surfer in candidates do
		if not surfer.dead then
			local point = camera:WorldToViewportPoint(surfer.root.Position)
			if Rules.isHit(x, y, point.X, point.Y, point.Z) then
				surfer.dead = true
				surfer.deadAt = os.clock()
				surfer.velocity = forward * (surfer.speed or 200) * 0.5 + Vector3.yAxis * 25
				surfer.spin = Vector3.new(math.random() * 9, math.random() * 9, math.random() * 9)
				surfer.pose = surfer.root.CFrame
				surfer.trail.Color = HIT_TRAIL
				return true
			end
		end
	end
	return false
end

-- Cette méthode permet de tirer vers un point de l'écran (coordonnées viewport) lorsque le joueur clique dans le menu ;
-- `force` ignore la cadence, pour qu'un bouton du menu réponde toujours. Renvoie hasFired, hasHit.
function MenuScene.shoot(x: number, y: number, force: boolean?): (boolean, boolean)
	local now = os.clock()
	if not running or not viewmodel or (not force and now - lastShot < FIRE_COOLDOWN) then
		return false, false
	end
	lastShot = now
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(x, y)
	local shootTrack = tracks.Shoot
	if shootTrack then
		shootTrack:Stop(0)
		shootTrack:Play(0)
	end
	if sounds.Shoot then
		sounds.Shoot.TimePosition = 0
		sounds.Shoot:Play()
	end
	if sounds.Bolt then
		task.delay(0.55, function()
			if running then
				sounds.Bolt.TimePosition = 0
				sounds.Bolt:Play()
			end
		end)
	end
	kick = 1
	fovKick = 4
	spawnShotEffects(ray.Direction, ray.Origin)
	return true, resolveHit(x, y, camera)
end

-- Cette méthode permet de plonger vers le soleil (zoom et surexposition) lorsque le joueur lance une partie.
function MenuScene.dive()
	if not running then
		return
	end
	diving = true
	local info = TweenInfo.new(1.7, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	diveTweens = {
		TweenService:Create(workspace.CurrentCamera, info, { FieldOfView = 22 }),
		TweenService:Create(Lighting, info, { ExposureCompensation = 3 }),
	}
	for _, tween in diveTweens do
		tween:Play()
	end
end

-- Cette méthode permet de lancer la scène (éclairage, caméra, boucle d'animation) lorsque le menu s'affiche.
function MenuScene.start()
	if running then
		return
	end
	running = true
	diving = false
	savedFov = workspace.CurrentCamera.FieldOfView
	override(Lighting, LIGHTING)
	override(Lighting:FindFirstChildOfClass("Atmosphere"), ATMOSPHERE)
	override(Lighting:FindFirstChildOfClass("DepthOfFieldEffect"), { Enabled = false })
	override(
		Lighting:FindFirstChildOfClass("BloomEffect"),
		{ Enabled = true, Intensity = 0.7, Size = 30, Threshold = 1.4 }
	)
	override(Lighting:FindFirstChildOfClass("SunRaysEffect"), { Enabled = false })
	grade = Instance.new("ColorCorrectionEffect")
	local effect = grade :: ColorCorrectionEffect
	effect.Name = "MenuSceneGrade"
	effect.Contrast = 0.12
	effect.Saturation = -0.08
	effect.Parent = Lighting

	if stage then
		stage.Parent = workspace
	else
		build()
	end
	if not running then -- le menu s'est refermé pendant la construction (attente de ViewModels)
		return
	end
	if tracks.Idle then
		tracks.Idle.Looped = true
		tracks.Idle:Play(0)
	end
	connection = RunService.RenderStepped:Connect(function(dt: number)
		updateView(dt)
		updateSurfers(dt, os.clock())
	end)
end

-- Cette méthode permet d'arrêter la scène et de rendre l'éclairage et le champ de vision à la place lorsque le menu se ferme.
function MenuScene.stop()
	if not running then
		return
	end
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if grade then
		grade:Destroy()
		grade = nil
	end
	for _, track in tracks do
		track:Stop(0)
	end
	if stage then
		stage.Parent = nil
	end
	-- Une plongée encore en cours écraserait les valeurs rétablies ci-dessous
	for _, tween in diveTweens do
		tween:Cancel()
	end
	diveTweens = {}
	restoreOverrides()
	workspace.CurrentCamera.FieldOfView = savedFov
	diving = false
end

return MenuScene

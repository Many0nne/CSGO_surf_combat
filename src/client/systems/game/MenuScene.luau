-- Scène 3D du menu principal : la salle des miroirs (#112, docs/ui.md). Des éclats de verre pendus à des fils dans une
-- salle de béton portent chacun un morceau de l'image de l'arme choisie ; face à la caméra, ils la reconstituent. Au
-- changement d'arme, le jeu d'éclats se disperse et celui de la nouvelle arme se pose en vague de gauche à droite.
-- Les jeux d'éclats texturés viennent de ReplicatedStorage.MenuMirrors (assets/rbx/Menu), leurs données (fils,
-- retards) de MenuMirrorsData (généré par tools/menu). Tout est local au client ; l'éclairage est rendu à la sortie.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Data = require(script.Parent.MenuMirrorsData)
local Rules = require(script.Parent.MenuSceneRules)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local MenuScene = {}

local ORIGIN = Vector3.new(0, 900, 0) -- très au-dessus de la map : la salle fermée la cache
local CEILING = 30 -- hauteur du plafond (studs), où s'accrochent les fils
local FIRE_COOLDOWN = 0.7
local FADE_START = 0.45 -- pendant la dispersion, la nouvelle arme apparaît (fondu) puis se pose
local FADE_TIME = 0.3

local CONCRETE = Color3.fromRGB(48, 51, 60)
local FLOOR = Color3.fromRGB(18, 20, 25)
local JOINT = Color3.fromRGB(21, 23, 28)
local WIRE = Color3.fromRGB(139, 143, 154)

-- Lumières de la salle (cf. tools/menu/mirrors.py) : douche froide zénithale, rasante sur le mur du fond, appoint au sol
local LIGHT_SETTINGS = {
	Douche = { range = 34, angle = 110, brightness = 3 },
	Rasante = { range = 30, angle = 75, brightness = 2.2 },
	Sol = { range = 14, angle = 120, brightness = 0.6 },
}

-- Éclairage du menu : la salle est fermée, seule la lumière de ses projecteurs compte
local LIGHTING = {
	ClockTime = 0,
	Brightness = 0,
	Ambient = Color3.fromRGB(26, 28, 36),
	OutdoorAmbient = Color3.fromRGB(26, 28, 36),
	ExposureCompensation = 0,
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0.4,
}
local ATMOSPHERE = { Density = 0, Haze = 0, Glare = 0 }

type Shard = {
	part: BasePart,
	rest: CFrame, -- pose reconstituée (monde)
	pivot: Vector3, -- point d'attache du fil (monde)
	delay: number, -- retard dans la vague de gauche à droite (s)
	scatterAngle: number,
	scatterTilt: number,
	angle: number, -- pose courante autour du fil
	tilt: number,
	fromAngle: number, -- pose au début de la dispersion
	fromTilt: number,
	beam: Beam,
}
type ShardSet = {
	name: string,
	shards: { Shard },
	mode: "rest" | "settle" | "scatter" | "hidden",
	clock: number, -- temps écoulé dans le mode courant
	fade: number, -- 0 = visible, 1 = invisible
}

local stage: Folder?
local sets: { [string]: ShardSet } = {}
local vides: ShardSet?
local current = Data.weapons[1]
local running = false
local connection: RBXScriptConnection?
local saved: { [Instance]: { [string]: any } } = {}
local savedFov = 70
local baseCFrame = CFrame.new()
local aimX, aimY = 0, 0
local kick = 0
local lastShot = 0
local diving = false
local diveTweens: { Tween } = {}
local shotSound: Sound?
local spinTime = 0

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

-- Cette méthode permet de créer une pièce de décor sans physique lorsque la salle est construite.
local function makePart(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = stage
	return part
end

-- Cette méthode permet de construire la salle de béton (murs, sol, joints de banches) puis de la fermer (plafond,
-- murs hors champ) lorsque la scène est créée : ni le ciel ni le soleil de la map n'y entrent.
local function buildRoom()
	for _, wall in Data.room do
		local material = if wall.name == "Sol"
			then Enum.Material.SmoothPlastic
			elseif wall.name == "Joint" then Enum.Material.Plastic
			else Enum.Material.Concrete
		local color = if wall.name == "Sol" then FLOOR elseif wall.name == "Joint" then JOINT else CONCRETE
		makePart(
			wall.size,
			CFrame.new(ORIGIN + wall.position) * CFrame.Angles(0, math.rad(wall.yaw), 0),
			color,
			material
		)
	end
	makePart(
		Vector3.new(80, 0.5, 60),
		CFrame.new(ORIGIN + Vector3.new(0, CEILING + 0.25, -10)),
		FLOOR,
		Enum.Material.Concrete
	)
	makePart(Vector3.new(0.5, 31, 60), CFrame.new(ORIGIN + Vector3.new(-40, 15, -10)), CONCRETE, Enum.Material.Concrete)
	makePart(Vector3.new(80, 31, 0.5), CFrame.new(ORIGIN + Vector3.new(0, 15, 20)), CONCRETE, Enum.Material.Concrete)
end

-- Cette méthode permet de poser les projecteurs de la salle (SpotLight orientés vers leur cible) lorsque la scène est créée.
local function buildLights()
	for _, info in Data.lights do
		local settings = LIGHT_SETTINGS[info.name]
		local holder = makePart(
			Vector3.one * 0.2,
			CFrame.lookAt(ORIGIN + info.position, ORIGIN + info.target),
			Color3.new(),
			Enum.Material.SmoothPlastic
		)
		holder.Transparency = 1
		holder.CastShadow = false
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Color = info.color
		light.Range = settings.range
		light.Angle = settings.angle
		light.Brightness = settings.brightness
		light.Shadows = info.shadow
		light.Parent = holder
	end
end

-- Cette méthode permet de tendre le fil d'un éclat jusqu'au plafond (Beam entre une attache sur l'éclat et une attache
-- fixe) lorsque son jeu est construit.
local function makeWire(part: BasePart, pivot: Vector3, anchor: BasePart): Beam
	local bottom = Instance.new("Attachment")
	bottom.Position = part.CFrame:PointToObjectSpace(pivot)
	bottom.Parent = part
	local top = Instance.new("Attachment")
	top.Position = anchor.CFrame:PointToObjectSpace(Vector3.new(pivot.X, ORIGIN.Y + CEILING, pivot.Z))
	top.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Width0 = 0.018
	beam.Width1 = 0.018
	beam.Segments = 1
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(WIRE)
	beam.LightInfluence = 1
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = part
	return beam
end

-- Cette méthode permet de cloner un jeu d'éclats dans la salle et de préparer la pose de chaque éclat (repos, fil,
-- dispersion propre à l'éclat) lorsque la scène est créée.
local function buildSet(name: string, anchor: BasePart): ShardSet
	local source = ReplicatedStorage:WaitForChild("MenuMirrors"):WaitForChild(name)
	local model = source:Clone() :: Model
	model.Parent = stage
	local data = Data.sets[name]
	local random = Random.new(#name * 7919)
	local set: ShardSet = { name = name, shards = {}, mode = "hidden", clock = 0, fade = 1 }
	for _, part in model:GetChildren() do
		local info = data[part.Name]
		if part:IsA("BasePart") and info then
			part.CFrame = CFrame.new(ORIGIN) * part.CFrame
			local pivot = ORIGIN + info.pivot
			local sign = if random:NextNumber() < 0.5 then -1 else 1
			table.insert(set.shards, {
				part = part,
				rest = part.CFrame,
				pivot = pivot,
				delay = info.delay,
				scatterAngle = sign * math.rad(random:NextNumber(70, 280)),
				scatterTilt = math.rad(random:NextNumber(-8, 8)),
				angle = 0,
				tilt = 0,
				fromAngle = 0,
				fromTilt = 0,
				beam = makeWire(part, pivot, anchor),
			})
		end
	end
	return set
end

-- Cette méthode permet d'appliquer la pose courante (rotation autour du fil, balancement) et la transparence d'un jeu
-- d'éclats lorsqu'il a bougé ; un seul déplacement groupé pour tout le jeu.
local function applySet(set: ShardSet)
	local parts = table.create(#set.shards)
	local frames = table.create(#set.shards)
	local alpha = set.fade
	for i, shard in set.shards do
		local rotation = CFrame.fromAxisAngle(Vector3.yAxis, shard.angle)
			* CFrame.fromAxisAngle(Vector3.xAxis, shard.tilt)
		local offset = shard.rest.Position - shard.pivot
		parts[i] = shard.part
		frames[i] = CFrame.new(shard.pivot + rotation:VectorToWorldSpace(offset)) * rotation
		if shard.part.Transparency ~= alpha then
			shard.part.Transparency = alpha
			shard.beam.Transparency = NumberSequence.new(0.15 + 0.85 * alpha)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Cette méthode permet d'avancer un jeu d'éclats d'une image selon son mode (dispersion, reconstitution, repos) ;
-- renvoie true si le jeu a bougé et doit être réappliqué.
local function updateSet(set: ShardSet, dt: number): boolean
	if set.mode == "rest" or set.mode == "hidden" then
		return false
	end
	set.clock += dt
	if set.mode == "scatter" then
		local p = Rules.scatterProgress(set.clock)
		for _, shard in set.shards do
			shard.angle = shard.fromAngle + (shard.scatterAngle - shard.fromAngle) * p
			shard.tilt = shard.fromTilt + (shard.scatterTilt - shard.fromTilt) * p
		end
		set.fade = math.clamp((set.clock - FADE_START) / FADE_TIME, 0, 1)
		if set.clock >= FADE_START + FADE_TIME then
			set.mode = "hidden"
			set.fade = 1
		end
	else
		local done = true
		for _, shard in set.shards do
			local lt = set.clock - shard.delay
			shard.angle, shard.tilt = Rules.settle(shard.scatterAngle, shard.scatterTilt, lt)
			done = done and lt >= Rules.SETTLE_TIME
		end
		set.fade = 1 - math.clamp(set.clock / FADE_TIME, 0, 1)
		if done then
			set.mode = "rest"
			for _, shard in set.shards do
				shard.angle, shard.tilt = 0, 0
			end
		end
	end
	return true
end

-- Cette méthode permet de faire tourner lentement les éclats vides du fond lorsqu'une image est rendue.
local function updateVides(dt: number)
	if not vides then
		return
	end
	spinTime += dt
	for _, shard in vides.shards do
		shard.angle = shard.scatterAngle + Rules.IDLE_SPIN * spinTime
	end
	applySet(vides)
end

-- Cette méthode permet de placer la caméra (léger suivi du curseur, recul, FOV adapté au format) lorsqu'une image est rendue.
local function updateView(dt: number)
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local viewport = camera.ViewportSize
	aimX = Rules.damp(aimX, (mouse.X / viewport.X - 0.5) * 2, dt, 4)
	aimY = Rules.damp(aimY, (mouse.Y / viewport.Y - 0.5) * 2, dt, 4)
	kick = Rules.decayKick(kick, dt)
	local angles = Rules.aimAngles(aimX, aimY, kick)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = baseCFrame * CFrame.Angles(math.rad(angles.camPitch), math.rad(angles.camYaw), 0)
	if not diving and viewport.Y > 0 then
		camera.FieldOfView = Rules.fitFov(Data.camera.verticalFov, Data.camera.aspectRef, viewport.X / viewport.Y)
	end
end

-- Cette méthode permet de construire toute la scène une seule fois lorsque le menu s'ouvre pour la première fois.
local function build()
	local folder = Instance.new("Folder")
	folder.Name = "MenuStage"
	folder.Parent = workspace
	stage = folder
	baseCFrame = CFrame.lookAt(ORIGIN + Data.camera.position, ORIGIN + Data.camera.target)

	buildRoom()
	buildLights()
	local anchor = makePart(Vector3.one * 0.2, CFrame.new(ORIGIN), Color3.new(), Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	anchor.CastShadow = false
	for _, name in Data.weapons do
		local set = buildSet(name, anchor)
		sets[name] = set
		applySet(set)
	end
	vides = buildSet("Vides", anchor)
	local emptySet = vides :: ShardSet
	emptySet.fade = 0
	for _, shard in emptySet.shards do
		shard.scatterAngle = 0
	end
	applySet(emptySet)

	local viewModels = ReplicatedStorage:FindFirstChild("ViewModels")
	local awp = viewModels and viewModels:FindFirstChild("AWP")
	local sounds = awp and awp:FindFirstChild("Sounds")
	local shoot = sounds and sounds:FindFirstChild("Shoot")
	if shoot and shoot:IsA("Sound") then
		local sound = shoot:Clone()
		sound.Parent = stage
		shotSound = sound
	end
end

-- Cette méthode permet de montrer une arme reconstituée d'emblée (sans vague) lorsque le menu s'ouvre.
local function showAtRest(name: string)
	for setName, set in sets do
		set.mode = if setName == name then "rest" else "hidden"
		set.fade = if setName == name then 0 else 1
		for _, shard in set.shards do
			shard.angle, shard.tilt = 0, 0
		end
		applySet(set)
	end
end

-- Cette méthode permet de changer l'arme montrée lorsque le joueur la choisit dans le menu : le jeu courant se
-- disperse, celui de l'arme choisie apparaît pendant la dispersion puis se pose en vague de gauche à droite.
function MenuScene.setWeapon(name: string)
	local target = sets[name]
	if not target or name == current then
		return
	end
	local previous = sets[current]
	current = name
	if previous and previous.mode ~= "hidden" then
		previous.mode = "scatter"
		previous.clock = 0
		for _, shard in previous.shards do
			shard.fromAngle, shard.fromTilt = shard.angle, shard.tilt
		end
	end
	-- la nouvelle arme part de sa pose dispersée et commence sa vague quand la précédente s'efface
	target.mode = "settle"
	target.clock = -FADE_START
	target.fade = 1
end

-- Cette méthode permet de passer à l'arme suivante ou précédente (molette) lorsque le joueur la fait défiler.
function MenuScene.cycleWeapon(step: number)
	local index = table.find(Data.weapons, current) or 1
	local count = #Data.weapons
	MenuScene.setWeapon(Data.weapons[(index - 1 + step) % count + 1])
end

-- Cette méthode permet de choisir une arme par son rang (touches 1-9) lorsque le joueur la tape.
function MenuScene.selectWeapon(index: number)
	local name = Data.weapons[index]
	if name then
		MenuScene.setWeapon(name)
	end
end

-- Cette méthode permet de lire l'arme montrée lorsque l'interface affiche sa fiche.
function MenuScene.getWeapon(): string
	return current
end

-- Cette méthode permet de tirer vers un point de l'écran (coordonnées viewport) lorsque le joueur clique dans le menu ;
-- `force` ignore la cadence, pour qu'un bouton du menu réponde toujours. Renvoie hasFired, hasHit (la réaction des
-- éclats touchés vient avec l'interface, #112 étape 4).
function MenuScene.shoot(_x: number, _y: number, force: boolean?): (boolean, boolean)
	local now = os.clock()
	if not running or (not force and now - lastShot < FIRE_COOLDOWN) then
		return false, false
	end
	lastShot = now
	if shotSound then
		shotSound.TimePosition = 0
		shotSound:Play()
	end
	kick = 1
	return true, false
end

-- Cette méthode permet de plonger vers l'arme (zoom et surexposition) lorsque le joueur lance une partie.
function MenuScene.dive()
	if not running then
		return
	end
	diving = true
	local info = TweenInfo.new(1.7, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	diveTweens = {
		TweenService:Create(workspace.CurrentCamera, info, { FieldOfView = 14 }),
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
		{ Enabled = true, Intensity = 0.5, Size = 24, Threshold = 1.6 }
	)
	override(Lighting:FindFirstChildOfClass("SunRaysEffect"), { Enabled = false })

	if stage then
		stage.Parent = workspace
	else
		build()
	end
	if not running then -- le menu s'est refermé pendant la construction (attente de MenuMirrors)
		return
	end
	showAtRest(current)
	connection = RunService.RenderStepped:Connect(PerfMarkers.wrap("menu 3D", function(dt: number)
		updateView(dt)
		for _, set in sets do
			if updateSet(set, dt) then
				applySet(set)
			end
		end
		updateVides(dt)
	end))
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

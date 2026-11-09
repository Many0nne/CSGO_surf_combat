-- Scène 3D du menu principal : la salle des miroirs (#112, docs/ui.md). Des éclats de verre pendus à des fils dans une
-- salle de béton portent chacun un morceau de l'image de l'arme choisie ; face à la caméra, ils la reconstituent. Au
-- changement d'arme, le jeu d'éclats se disperse et celui de la nouvelle arme se pose en vague de gauche à droite. Un
-- tir fait pivoter les éclats touchés (ressort amorti) ; JOUER fait exploser la vitrine vers la caméra. Les jeux d'éclats texturés viennent de ReplicatedStorage.MenuMirrors (assets/rbx/Menu), leurs données (fils,
-- retards) de MenuMirrorsData (généré par tools/menu). Tout est local au client ; l'éclairage est rendu à la sortie.
local ContentProvider = game:GetService("ContentProvider")
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
local SHOT_RANGE = 120 -- studs : toute la salle
local SETTLED = 1e-3 -- écart (rad) et vitesse (rad/s) sous lesquels un éclat touché est revenu au repos
-- Explosion de la vitrine (JOUER) : vitesse vers la caméra, vers l'extérieur et vers le haut (studs/s), gravité,
-- rotation propre (rad/s), puis surexposition jusqu'au blanc des volets
local BURST_TOWARD = NumberRange.new(9, 22)
local BURST_OUTWARD = NumberRange.new(3, 9)
local BURST_UP = NumberRange.new(1, 6)
local BURST_GRAVITY = 26
local BURST_SPIN = 10
local BURST_FLASH = TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

local CONCRETE = Color3.fromRGB(48, 51, 60)
local FLOOR = Color3.fromRGB(18, 20, 25)
local JOINT = Color3.fromRGB(21, 23, 28)
local WIRE = Color3.fromRGB(139, 143, 154)

-- Lumières de la salle (cf. tools/menu/mirrors.py) : douche froide zénithale, rasante sur le mur du fond, appoint au
-- sol. Valeurs réglées dans Studio contre docs/ui/menu-miroirs/reconstituee.jpg.
local LIGHT_SETTINGS = {
	Douche = { range = 40, angle = 110, brightness = 6 },
	Rasante = { range = 34, angle = 90, brightness = 8 },
	Sol = { range = 14, angle = 120, brightness = 1.5 },
}

-- Éclairage du menu : la salle est fermée, seule la lumière de ses projecteurs compte
local LIGHTING = {
	ClockTime = 0,
	Brightness = 0,
	Ambient = Color3.fromRGB(44, 47, 58),
	OutdoorAmbient = Color3.fromRGB(44, 47, 58),
	ExposureCompensation = 0,
	EnvironmentDiffuseScale = 0.3,
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
	hitOffset: number, -- écart d'angle dû aux tirs (ressort amorti, MenuSceneRules.springStep)
	hitVelocity: number,
	hitActive: boolean,
	burstVelocity: Vector3, -- explosion de la vitrine
	spinAxis: Vector3,
	spinRate: number,
}
type ShardSet = {
	name: string,
	model: Model,
	shards: { Shard },
	mode: "rest" | "settle" | "scatter" | "hidden",
	clock: number, -- temps écoulé dans le mode courant
	fade: number, -- 0 = visible, 1 = invisible
	hits: number, -- éclats encore en mouvement après un tir
	burst: number?, -- temps écoulé depuis l'explosion, nil hors explosion
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
local bursting = false
local burstTweens: { Tween } = {}
local shotSound: Sound?
local spinTime = 0
local random = Random.new()
local weaponChanged: ((string) -> ())?

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
	local seeded = Random.new(#name * 7919)
	local set: ShardSet = {
		name = name,
		model = model,
		shards = {},
		mode = "hidden",
		clock = 0,
		fade = 1,
		hits = 0,
		burst = nil,
	}
	for _, part in model:GetChildren() do
		local info = data[part.Name]
		if part:IsA("BasePart") and info then
			part.CFrame = CFrame.new(ORIGIN) * part.CFrame
			-- Seuls les éclats reçoivent les tirs du menu (le décor a CanQuery coupé)
			part.CanQuery = true
			part.CanCollide = false
			part.CanTouch = false
			local pivot = ORIGIN + info.pivot
			local sign = if seeded:NextNumber() < 0.5 then -1 else 1
			table.insert(set.shards, {
				part = part,
				rest = part.CFrame,
				pivot = pivot,
				delay = info.delay,
				scatterAngle = sign * math.rad(seeded:NextNumber(70, 280)),
				scatterTilt = math.rad(seeded:NextNumber(-8, 8)),
				angle = 0,
				tilt = 0,
				fromAngle = 0,
				fromTilt = 0,
				beam = makeWire(part, pivot, anchor),
				hitOffset = 0,
				hitVelocity = 0,
				hitActive = false,
				burstVelocity = Vector3.zero,
				spinAxis = Vector3.yAxis,
				spinRate = 0,
			})
		end
	end
	return set
end

-- Cette méthode permet d'appliquer la pose courante (rotation autour du fil, balancement, réaction aux tirs, explosion)
-- et la transparence d'un jeu d'éclats lorsqu'il a bougé ; un seul déplacement groupé pour tout le jeu.
local function applySet(set: ShardSet)
	local parts = table.create(#set.shards)
	local frames = table.create(#set.shards)
	local alpha = set.fade
	local t = set.burst
	for i, shard in set.shards do
		local rotation = CFrame.fromAxisAngle(Vector3.yAxis, shard.angle + shard.hitOffset)
			* CFrame.fromAxisAngle(Vector3.xAxis, shard.tilt)
		local offset = shard.rest.Position - shard.pivot
		local frame = CFrame.new(shard.pivot + rotation:VectorToWorldSpace(offset)) * rotation
		if t then
			local position = frame.Position + shard.burstVelocity * t - Vector3.yAxis * (BURST_GRAVITY * t * t / 2)
			frame = CFrame.new(position) * CFrame.fromAxisAngle(shard.spinAxis, shard.spinRate * t) * rotation
		end
		parts[i] = shard.part
		frames[i] = frame
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

-- Cette méthode permet d'avancer les éclats encore secoués par un tir et l'explosion d'un jeu lorsqu'une image passe ;
-- renvoie true si le jeu a bougé et doit être réappliqué.
local function updateMotion(set: ShardSet, dt: number): boolean
	local moved = false
	if set.hits > 0 then
		local active = 0
		for _, shard in set.shards do
			if shard.hitActive then
				shard.hitOffset, shard.hitVelocity = Rules.springStep(shard.hitOffset, shard.hitVelocity, dt)
				if math.abs(shard.hitOffset) < SETTLED and math.abs(shard.hitVelocity) < SETTLED then
					shard.hitOffset, shard.hitVelocity, shard.hitActive = 0, 0, false
				else
					active += 1
				end
			end
		end
		set.hits = active
		moved = true
	end
	if set.burst then
		set.burst += dt
		moved = true
	end
	return moved
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
	updateMotion(vides, dt)
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
	if viewport.Y > 0 then
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
	-- Textures des armes chargées d'avance : sinon une arme encore jamais montrée apparaît en éclats blancs opaques
	-- pendant sa première vague (Roblox ne télécharge une texture qu'une fois la pièce visible).
	task.spawn(function()
		local looks = {}
		for _, set in sets do
			local first = set.shards[1]
			local look = first and first.part:FindFirstChildOfClass("SurfaceAppearance")
			if look then
				table.insert(looks, look)
			end
		end
		ContentProvider:PreloadAsync(looks)
	end)
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

-- Cette méthode permet de remettre un jeu d'éclats sur ses fils (fin d'explosion, tirs oubliés) lorsque le menu se rouvre.
local function resetMotion(set: ShardSet)
	set.burst = nil
	set.hits = 0
	for _, shard in set.shards do
		shard.hitOffset, shard.hitVelocity, shard.hitActive = 0, 0, false
		shard.beam.Enabled = true
	end
end

-- Cette méthode permet de montrer une arme reconstituée d'emblée (sans vague) lorsque le menu s'ouvre.
local function showAtRest(name: string)
	for setName, set in sets do
		resetMotion(set)
		set.mode = if setName == name then "rest" else "hidden"
		set.fade = if setName == name then 0 else 1
		for _, shard in set.shards do
			shard.angle, shard.tilt = 0, 0
		end
		applySet(set)
	end
	if vides then
		resetMotion(vides)
		applySet(vides)
	end
end

-- Cette méthode permet de lister les jeux d'éclats visibles (arme montrée, éclats vides) lorsqu'un tir ou l'explosion
-- les cherche.
local function visibleSets(): { ShardSet }
	local list = {}
	for _, set in sets do
		if set.fade < 0.5 then
			table.insert(list, set)
		end
	end
	if vides then
		table.insert(list, vides)
	end
	return list
end

-- Cette méthode permet de lancer un rayon depuis un point de l'écran sur les éclats visibles lorsque le joueur vise
-- ou tire dans la vitrine ; seuls les éclats de l'arme comptent (pas les éclats vides du fond). Renvoie le résultat
-- (nil hors de l'arme) et les jeux visibles, que la balle fait aussi pivoter.
local function raycastShards(x: number, y: number): (RaycastResult?, { ShardSet })
	local targets = visibleSets()
	local models = {}
	for _, set in targets do
		if set ~= vides then
			table.insert(models, set.model)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = models
	local ray = workspace.CurrentCamera:ViewportPointToRay(x, y)
	return workspace:Raycast(ray.Origin, ray.Direction * SHOT_RANGE, params), targets
end

-- Cette méthode permet de faire pivoter les éclats touchés par un tir (et leurs voisins, moins fort) lorsque la balle
-- traverse la salle à l'endroit donné par `raycastShards`.
local function hitShards(result: RaycastResult, targets: { ShardSet })
	local point = result.Position
	for _, set in targets do
		for _, shard in set.shards do
			local distance = if shard.part == result.Instance then 0 else (shard.part.Position - point).Magnitude
			local velocity = Rules.hitVelocity(distance)
			if velocity > 0 then
				-- La balle pousse le côté touché loin de la caméra : à droite du fil, l'éclat tourne en sens positif
				local side = if point.X >= shard.pivot.X then 1 else -1
				shard.hitVelocity += side * velocity
				if not shard.hitActive then
					shard.hitActive = true
					set.hits += 1
				end
			end
		end
	end
end

-- Cette méthode permet de changer l'arme montrée lorsque le joueur la choisit dans le menu : le jeu courant se
-- disperse, celui de l'arme choisie apparaît pendant la dispersion puis se pose en vague de gauche à droite.
function MenuScene.setWeapon(name: string)
	local target = sets[name]
	if not target or name == current or bursting then
		return
	end
	local previous = sets[current]
	current = name
	if weaponChanged then
		weaponChanged(name)
	end
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

-- Cette méthode permet de lire les armes de la vitrine, dans l'ordre des touches 1-9, lorsque l'interface les compte.
function MenuScene.getWeapons(): { string }
	return Data.weapons
end

-- Cette méthode permet d'enregistrer le rappel appelé à chaque changement d'arme lorsque la fiche doit suivre la vitrine.
function MenuScene.onWeaponChanged(callback: (string) -> ())
	weaponChanged = callback
end

-- Cette méthode permet de savoir si un point de l'écran (coordonnées viewport) vise l'arme de la vitrine lorsque le
-- curseur du menu choisit entre souris système et hitmarker.
function MenuScene.isAimingWeapon(x: number, y: number): boolean
	if not running or bursting then
		return false
	end
	return raycastShards(x, y) ~= nil
end

-- Cette méthode permet de tirer vers un point de l'écran (coordonnées viewport) lorsque le joueur clique sur l'accueil ;
-- seul un clic sur l'arme fait feu (#130). Renvoie true si le tir est parti (et a donc touché un éclat).
function MenuScene.shoot(x: number, y: number): boolean
	local now = os.clock()
	if not running or bursting or now - lastShot < FIRE_COOLDOWN then
		return false
	end
	local result, targets = raycastShards(x, y)
	if not result then
		return false
	end
	lastShot = now
	if shotSound then
		shotSound.TimePosition = 0
		shotSound:Play()
	end
	kick = 1
	hitShards(result, targets)
	return true
end

-- Cette méthode permet de faire exploser la vitrine (éclats arrachés à leurs fils, projetés vers la caméra en
-- tournoyant, surexposition jusqu'au blanc) lorsque le joueur tire sur JOUER ; les volets suivent.
function MenuScene.burst()
	if not running or bursting then
		return
	end
	bursting = true
	kick = 1
	local camera = baseCFrame.Position
	local center = ORIGIN + Data.camera.target
	for _, set in visibleSets() do
		set.burst = 0
		for _, shard in set.shards do
			local position = shard.part.Position
			local outward = position - center
			outward = if outward.Magnitude > 1e-3 then outward.Unit else Vector3.xAxis
			shard.burstVelocity = (camera - position).Unit * random:NextNumber(BURST_TOWARD.Min, BURST_TOWARD.Max)
				+ outward * random:NextNumber(BURST_OUTWARD.Min, BURST_OUTWARD.Max)
				+ Vector3.yAxis * random:NextNumber(BURST_UP.Min, BURST_UP.Max)
			shard.spinAxis = random:NextUnitVector()
			shard.spinRate = random:NextNumber(-BURST_SPIN, BURST_SPIN)
			shard.beam.Enabled = false
		end
	end
	burstTweens = { TweenService:Create(Lighting, BURST_FLASH, { ExposureCompensation = 3 }) }
	for _, tween in burstTweens do
		tween:Play()
	end
end

-- Cette méthode permet de lancer la scène (éclairage, caméra, boucle d'animation) lorsque le menu s'affiche.
function MenuScene.start()
	if running then
		return
	end
	running = true
	bursting = false
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
			local moved = updateSet(set, dt)
			if updateMotion(set, dt) or moved then
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
	-- Une surexposition encore en cours écraserait les valeurs rétablies ci-dessous
	for _, tween in burstTweens do
		tween:Cancel()
	end
	burstTweens = {}
	restoreOverrides()
	workspace.CurrentCamera.FieldOfView = savedFov
	bursting = false
end

return MenuScene

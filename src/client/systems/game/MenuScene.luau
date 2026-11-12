-- Scène 3D de l'accueil du menu (#253, docs/ui.md) : le personnage du jeu, de face et en pose, tient l'arme choisie
-- dans le menu, sur une copie de la map jouée. La copie ne garde que les pièces vues par la caméra et se pose loin de la
-- vraie map : aucun joueur ni bot n'y passe. Caméra fixe qui suit à peine le curseur, flou léger sur le fond,
-- respiration du personnage. Tout est local au client ; l'éclairage reste celui du jeu.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterAppearance = require(Shared:WaitForChild("CharacterAppearance"))
local MapSelection = require(Shared:WaitForChild("MapSelection"))
local PerfMarkers = require(Shared:WaitForChild("PerfMarkers"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))
local LocalInventory = require(script.Parent.Parent.inventory.LocalInventory)
local MenuPoses = require(script.Parent.MenuPoses)
local Rules = require(script.Parent.MenuSceneRules)

local MenuScene = {}

-- La copie est posée à ce décalage de la vraie map, hors de toute vue de jeu
local OFFSET = Vector3.new(0, 0, 5000)
-- FOV vertical au format de référence (16:9), ouvert sur un écran plus étroit pour garder le personnage entier
local VERTICAL_FOV = 40
local ASPECT_REF = 16 / 9
-- Pièces copiées : cône de la caméra (tangente du demi-angle, large pour le 21:9 et le suivi du curseur), distance
-- maximale, voisinage de la caméra gardé en entier (studs)
local COPY_TAN_HALF = 1.0
local COPY_DISTANCE = 700
local COPY_NEAR = 40
local MAP_WAIT = 15 -- s d'attente de la map jouée
-- Flou du fond : netteté autour du personnage (studs), intensité du flou lointain
local FOCUS_RADIUS = 6
local FAR_BLUR = 0.35
-- Lumière de portrait : le soleil couchant (1,4° au-dessus de l'horizon) laisse le personnage dans l'ombre des bords du
-- toit. Projecteur chaud devant lui, du côté du soleil : position dans son repère (droite, haut, avant, studs)
local KEY_OFFSET = Vector3.new(6, 4, 12)
local KEY_AIM_HEIGHT = 1 -- studs au-dessus du centre du personnage
local KEY_ANGLE = 50
local KEY_RANGE = 30
local KEY_BRIGHTNESS = 3
local KEY_COLOR = Color3.fromRGB(255, 214, 170)

-- Plan de l'accueil par map (coordonnées de la map telle qu'elle est posée) : pieds du personnage (y relevé au sol,
-- recalé par un rayon), direction de son regard, puis caméra devant lui à `distance`, à `eyeHeight` au-dessus des pieds,
-- visant `lookHeight` ; `shift` décale caméra et visée sur le côté (studs, vers la droite de l'image).
type Shot = {
	feet: Vector3,
	facing: Vector3,
	distance: number,
	eyeHeight: number,
	lookHeight: number,
	shift: number,
}
local SHOTS: { [string]: Shot } = {
	-- Couloir du toit haut entre le grillage et le mur à bande bleue, au-dessus de la rampe ouest ; regard vers le
	-- soleil couchant (le personnage est éclairé de face), le couloir fuit derrière lui.
	Dizzy = {
		feet = Vector3.new(1768, 104.65, -375),
		facing = Vector3.new(-1, 0, 0),
		distance = 17,
		eyeHeight = 3.15,
		lookHeight = 3.95,
		shift = 0,
	},
}

type Weapon = { key: string, viewmodel: string, tool: string }

local stage: Folder?
local character: Model?
local motors: { [string]: Motor6D } = {}
local baseC0: { [string]: CFrame } = {}
local pose: { [string]: CFrame } = {}
local weapons: { Weapon }? = nil
local current: string? = nil
local running = false
local building = false
local connection: RBXScriptConnection?
local blur: DepthOfFieldEffect?
local savedFov = 70
local baseCFrame = CFrame.new()
local focusDistance = 17
local aimX, aimY = 0, 0
local clock = 0
local weaponChanged: ((string) -> ())?

-- Cette méthode permet de lister les armes du menu (Tools possédés de ReplicatedStorage.Tools connus de WeaponConfig,
-- par attribut WeaponName ou à défaut par nom, triés par nom de Tool, #267) lorsque la scène ou
-- la fiche en a besoin ; repli sur les armes possédées de WeaponConfig, sans la retenir, si le dossier des Tools n'est pas
-- encore répliqué.
local function listWeapons(): { Weapon }
	if weapons then
		return weapons
	end
	local list: { Weapon } = {}
	local tools = {}
	local folder = ReplicatedStorage:FindFirstChild("Tools")
	for _, tool in if folder then folder:GetChildren() else {} do
		if tool:IsA("Tool") and LocalInventory.ownsTool(tool.Name) then
			table.insert(tools, tool)
		end
	end
	table.sort(tools, function(a, b)
		return a.Name < b.Name
	end)
	for _, tool in tools do
		local key = tool:GetAttribute("WeaponName")
		key = if type(key) == "string" then key else tool.Name
		local viewmodel = tool:GetAttribute("ViewmodelName")
		if WeaponConfig.Weapons[key] then
			table.insert(list, {
				key = key,
				viewmodel = if type(viewmodel) == "string" then viewmodel else tool.Name,
				tool = tool.Name,
			})
		end
	end
	if #list == 0 then
		for key in WeaponConfig.Weapons do
			if LocalInventory.ownsTool(key) then
				table.insert(list, { key = key, viewmodel = key, tool = key })
			end
		end
		table.sort(list, function(a, b)
			return a.key < b.key
		end)
	end
	-- Liste de repli (Tools pas encore répliqués) non retenue : la suivante relira le dossier
	if folder then
		weapons = list
	end
	return list
end

-- Cette méthode permet de donner le plan de l'accueil d'une map lorsque la scène se construit : celui de SHOTS, sinon
-- devant le premier point d'apparition au sol (map sans plan réglé).
local function shotFor(map: Instance): Shot?
	local shot = SHOTS[map.Name]
	if shot then
		return shot
	end
	local spawns = map:FindFirstChild("GroundSpawns")
	local spawn = spawns and spawns:FindFirstChildWhichIsA("BasePart", true)
	if not spawn then
		return nil
	end
	local look = Vector3.new(spawn.CFrame.LookVector.X, 0, spawn.CFrame.LookVector.Z)
	return {
		feet = spawn.Position,
		facing = if look.Magnitude > 1e-3 then look.Unit else Vector3.xAxis,
		distance = 17,
		eyeHeight = 3.15,
		lookHeight = 3.95,
		shift = 0,
	}
end

-- Cette méthode permet de copier dans `folder`, décalées de OFFSET et sans physique, les pièces visibles de la map vues
-- depuis `eye` dans la direction `forward` lorsque la scène se construit ; les pièces invisibles (murs d'air, volumes)
-- sont ignorées. Les pièces enfants d'une autre pièce sont copiées pour elles-mêmes, pas avec leur parent.
local function copyMap(map: Instance, eye: Vector3, forward: Vector3, folder: Folder)
	for i, part in map:GetDescendants() do
		if i % 4000 == 0 then
			task.wait() -- la map compte plusieurs dizaines de milliers d'instances
		end
		if
			part:IsA("BasePart")
			and part.Transparency < 1
			and Rules.inView(
				part.Position,
				part.Size.Magnitude / 2,
				eye,
				forward,
				COPY_TAN_HALF,
				COPY_DISTANCE,
				COPY_NEAR
			)
		then
			local copy = part:Clone()
			for _, child in copy:GetDescendants() do
				if
					child:IsA("BasePart")
					or child:IsA("JointInstance")
					or child:IsA("Constraint")
					or child:IsA("LuaSourceContainer")
				then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CFrame = part.CFrame + OFFSET
			copy.Parent = folder
		end
	end
end

-- Cette méthode permet de trouver le sol de la copie sous les pieds du personnage lorsque la scène se construit ; garde
-- la hauteur du plan si le rayon ne touche rien.
local function groundUnder(feet: Vector3, folder: Folder): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	-- Les copies ont CanQuery coupé : on le rend le temps du rayon aux seules pièces sous les pieds
	local under = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and (part.Position - feet).Magnitude < part.Size.Magnitude / 2 + 2 then
			part.CanQuery = true
			table.insert(under, part)
		end
	end
	local hit = workspace:Raycast(feet + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
	for _, part in under do
		part.CanQuery = false
	end
	return if hit then hit.Position else feet
end

-- Cette méthode permet de créer le personnage du jeu (StarterCharacter, skin commun) sans script ni physique, debout
-- sur `ground`, tourné vers `facing` et éclairé par sa lumière de portrait, lorsque la scène se construit ; nil si la
-- place n'a pas de StarterCharacter.
local function buildCharacter(ground: Vector3, facing: Vector3, parent: Instance): Model?
	local template = CharacterAppearance.getTemplate()
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = "MenuCharacter"
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	CharacterAppearance.apply(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.EvaluateStateMachine = false
	root.Anchored = true
	local center = ground + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local frame = CFrame.lookAt(center, center + facing)
	model:PivotTo(frame)
	model.Parent = parent

	local holder = Instance.new("Part")
	holder.Name = "KeyLight"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	local aim = center + Vector3.new(0, KEY_AIM_HEIGHT, 0)
	local offset = frame.RightVector * KEY_OFFSET.X + Vector3.yAxis * KEY_OFFSET.Y + frame.LookVector * KEY_OFFSET.Z
	holder.CFrame = CFrame.lookAt(aim + offset, aim)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = KEY_ANGLE
	light.Range = KEY_RANGE
	light.Brightness = KEY_BRIGHTNESS
	light.Color = KEY_COLOR
	light.Parent = holder
	holder.Parent = parent

	motors = {}
	baseC0 = {}
	for _, name in WeaponThirdPerson.HOLD_JOINTS do
		local motor = model:FindFirstChild(name, true)
		if motor and motor:IsA("Motor6D") then
			motors[name] = motor
			baseC0[name] = motor.C0
		end
	end
	return model
end

-- Cette méthode permet de poser les articulations du personnage (tenue de l'arme montrée, respiration de la taille)
-- lorsque l'arme change ou qu'une image passe.
local function applyPose()
	for name, motor in motors do
		local joint = pose[name] or CFrame.identity
		if name == "Waist" then
			joint *= CFrame.Angles(Rules.breathAngle(clock), 0, 0)
		end
		motor.C0 = baseC0[name] * joint
	end
end

-- Cette méthode permet de mettre l'arme `key` dans les mains du personnage, dans sa tenue du menu (fusil en travers du
-- torse, couteau le long du corps), lorsque le joueur la choisit ou que la scène se construit.
local function holdWeapon(key: string)
	local model = character
	if not model then
		return
	end
	local entry
	for _, weapon in listWeapons() do
		if weapon.key == key then
			entry = weapon
		end
	end
	if not entry then
		return
	end
	local settings = WeaponThirdPerson.getSettings(key)
	local gun = WeaponThirdPerson.attach(model, key, entry.viewmodel)
	-- Hors du rendu des armes 3P (WeaponThirdPersonView) : la tenue et la prise sont celles du menu
	model:SetAttribute(WeaponThirdPerson.ACTION_ATTR, nil)
	model:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, nil)
	if gun then
		gun:RemoveTag(WeaponThirdPerson.TAG)
		if not settings.IsMelee then
			local handle = gun.PrimaryPart
			local weld = handle and handle:FindFirstChild(WeaponThirdPerson.WELD_NAME)
			if weld and weld:IsA("Weld") then
				weld.C0 = MenuPoses.Rifle.Grip
			end
		end
	end
	pose = if settings.IsMelee then MenuPoses.Melee.Joints else MenuPoses.Rifle.Joints
	applyPose()
end

-- Cette méthode permet de construire la scène une seule fois (copie de la map, personnage, arme) lorsque le menu
-- s'ouvre pour la première fois ; la construction attend la map jouée.
local function build()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local map = MapSelection.waitForActive(MAP_WAIT)
	local shot = map and shotFor(map)
	if not (map and shot) then
		return
	end
	local side = shot.facing:Cross(Vector3.yAxis).Unit * shot.shift
	local up = Vector3.yAxis
	local eye = shot.feet + shot.facing * shot.distance + up * shot.eyeHeight + side
	local target = shot.feet + up * shot.lookHeight + side
	focusDistance = (target - eye).Magnitude

	local folder = Instance.new("Folder")
	folder.Name = "MenuStage"
	local mapCopy = Instance.new("Folder")
	mapCopy.Name = "Map"
	copyMap(map, eye, (target - eye).Unit, mapCopy)
	mapCopy.Parent = folder
	folder.Parent = workspace
	stage = folder

	baseCFrame = CFrame.lookAt(eye + OFFSET, target + OFFSET)
	local ground = groundUnder(shot.feet + OFFSET, mapCopy)
	character = buildCharacter(ground, shot.facing, folder)
end

-- Cette méthode permet de placer la caméra (léger suivi du curseur, FOV adapté au format) et de faire respirer le
-- personnage lorsqu'une image est rendue.
local function update(dt: number)
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local viewport = camera.ViewportSize
	aimX = Rules.damp(aimX, (mouse.X / viewport.X - 0.5) * 2, dt, 4)
	aimY = Rules.damp(aimY, (mouse.Y / viewport.Y - 0.5) * 2, dt, 4)
	local angles = Rules.aimAngles(aimX, aimY)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = baseCFrame * CFrame.Angles(math.rad(angles.camPitch), math.rad(angles.camYaw), 0)
	if viewport.Y > 0 then
		camera.FieldOfView = Rules.fitFov(VERTICAL_FOV, ASPECT_REF, viewport.X / viewport.Y)
	end
	clock += dt
	applyPose()
end

-- Cette méthode permet de changer l'arme tenue (clé de WeaponConfig) lorsque l'accueil montre une autre arme.
function MenuScene.setWeapon(key: string)
	if key == current then
		return
	end
	local known = false
	for _, weapon in listWeapons() do
		known = known or weapon.key == key
	end
	if not known then
		return
	end
	current = key
	holdWeapon(key)
	if weaponChanged then
		weaponChanged(key)
	end
end

-- Cette méthode permet de mettre dans les mains du personnage l'arme dont le Tool porte ce nom lorsque l'écran
-- d'équipement (#280) montre une arme équipée ou survolée ; sans effet si elle n'est pas possédée.
function MenuScene.holdTool(toolName: string)
	-- Deux passes : la liste retenue peut dater d'avant un changement d'inventaire pas encore vu ici
	for pass = 1, 2 do
		for _, weapon in listWeapons() do
			if weapon.tool == toolName then
				MenuScene.setWeapon(weapon.key)
				return
			end
		end
		if pass == 1 then
			weapons = nil
		end
	end
end

-- Cette méthode permet de lire l'arme tenue (clé de WeaponConfig) lorsque l'interface affiche sa fiche.
function MenuScene.getWeapon(): string
	if not current then
		local first = listWeapons()[1]
		current = if first then first.key else ""
	end
	return current :: string
end

-- Cette méthode permet de lire les armes possédées du menu (clés de WeaponConfig) lorsque la fiche rapporte ses stats
-- à la meilleure d'entre elles.
function MenuScene.getWeapons(): { string }
	local keys = {}
	for _, weapon in listWeapons() do
		table.insert(keys, weapon.key)
	end
	return keys
end

-- Cette méthode permet d'enregistrer le rappel appelé à chaque changement d'arme lorsque la fiche doit suivre la scène.
function MenuScene.onWeaponChanged(callback: (string) -> ())
	weaponChanged = callback
end

-- Cette méthode permet de suivre l'inventaire lorsqu'il change (#267, chargement ou debug Studio) : liste refaite, arme
-- tenue remplacée par la première possédée si elle ne l'est plus, fiche remise à jour (rang et nombre d'armes).
local function onInventoryChanged()
	weapons = nil
	if current == nil then
		return -- rien d'affiché encore : la liste sera lue à la première demande
	end
	local list = listWeapons()
	local kept = false
	for _, weapon in list do
		kept = kept or weapon.key == current
	end
	if not kept then
		local first = list[1]
		current = if first then first.key else ""
		if first then
			holdWeapon(first.key)
		end
	end
	if weaponChanged then
		weaponChanged(current :: string)
	end
end
LocalInventory.onChanged(onInventoryChanged)

-- Cette méthode permet de lancer la scène (construction au premier appel, flou du fond, caméra, boucle) lorsque le
-- menu s'affiche.
function MenuScene.start()
	if running then
		return
	end
	running = true
	savedFov = workspace.CurrentCamera.FieldOfView
	if not stage and not building then
		building = true
		build()
		building = false
		if character then
			holdWeapon(MenuScene.getWeapon())
		end
	end
	if not running or not stage then -- menu refermé pendant la construction, ou map introuvable
		return
	end
	stage.Parent = workspace
	local effect = Instance.new("DepthOfFieldEffect")
	effect.Name = "MenuBlur"
	effect.FocusDistance = focusDistance
	effect.InFocusRadius = FOCUS_RADIUS
	effect.FarIntensity = FAR_BLUR
	effect.NearIntensity = 0
	effect.Parent = workspace.CurrentCamera
	blur = effect
	connection = RunService.RenderStepped:Connect(PerfMarkers.wrap("menu 3D", update))
end

-- Cette méthode permet d'arrêter la scène et de rendre le champ de vision lorsque le menu se ferme ; la copie de la map
-- est gardée hors du workspace pour le prochain retour au menu.
function MenuScene.stop()
	if not running then
		return
	end
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if blur then
		blur:Destroy()
		blur = nil
	end
	if stage then
		stage.Parent = nil
	end
	workspace.CurrentCamera.FieldOfView = savedFov
end

return MenuScene

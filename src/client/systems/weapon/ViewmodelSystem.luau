local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ViewmodelAnimator = require(script.Parent.ViewmodelAnimator)
local ViewmodelMotion = require(script.Parent.ViewmodelMotion)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

-- Viewmodel FPS (#19) : le modèle de ReplicatedStorage.ViewModels est cloné dans la caméra et animé en code.
-- Les clips (clips/<Viewmodel>.luau) pilotent les Motor6D via ViewmodelAnimator ; ViewmodelMotion ajoute
-- sway, bob, inclinaison et atterrissage sur le pivot du modèle. Les marqueurs des clips jouent les sons.
local ViewmodelSystem = {}

type MarkerHandler = () -> string?
type Rig = {
	model: Model,
	parts: { BasePart },
	motors: { [string]: { motor: Motor6D, c0: CFrame } },
	set: any,
	animator: any,
}

local boundStepName = "ViewmodelUpdate"
local rigCache = {} :: { [string]: Rig }
local active = nil :: Rig?
local currentOffset = CFrame.new()
local markerHandlers = {} :: { [string]: MarkerHandler }
local motion = ViewmodelMotion.new()
local motionInput = { speed = 0, lateral = 0, onGround = true, verticalSpeed = 0 }
local worldVelocity = Vector3.zero
-- Garde : un outil passe Backpack → Character à l'équipement, ce qui redéclenche ChildAdded
local hookedTools = {} :: { [Tool]: boolean }

local clipsFolder = script.Parent:FindFirstChild("clips")

-- Cette méthode permet de rendre visible ou invisible tout le viewmodel lorsqu'il est équipé, rangé ou masqué
-- par la lunette, sans toucher à la Transparency d'origine des pièces.
local function setRigVisible(rig: Rig, visible: boolean)
	local modifier = visible and 0 or 1
	for _, part in rig.parts do
		part.LocalTransparencyModifier = modifier
	end
end

-- Cette méthode permet de couper les sons du viewmodel lorsqu'on range l'arme (pas de recharge entendue après).
local function stopRigSounds(rig: Rig)
	local sounds = rig.model:FindFirstChild("Sounds")
	if not sounds then
		return
	end
	for _, s in sounds:GetChildren() do
		if s:IsA("Sound") and s.IsPlaying then
			s:Stop()
		end
	end
end

-- Cette méthode permet de jouer un son du dossier Sounds d'un viewmodel lorsqu'un marqueur ou la lunette le demande.
local function playRigSound(rig: Rig, name: string)
	local sounds = rig.model:FindFirstChild("Sounds")
	local s = sounds and sounds:FindFirstChild(name)
	if s and s:IsA("Sound") then
		s:Play()
	end
end

-- Cette méthode permet de remettre toutes les articulations au repos lorsqu'un viewmodel est rangé.
local function resetMotors(rig: Rig)
	for _, entry in rig.motors do
		entry.motor.Transform = CFrame.new()
	end
end

-- Cette méthode permet de ranger le viewmodel actif sans fondu lorsqu'on change d'arme ou qu'on meurt.
local function clearViewmodel()
	if active then
		active.animator:reset()
		resetMotors(active)
		stopRigSounds(active)
		setRigVisible(active, false)
	end
	active = nil
	markerHandlers = {}
	currentOffset = CFrame.new()
	motion:reset()
end

-- Cette méthode permet de retrouver le modèle source d'un viewmodel dans ReplicatedStorage.ViewModels.
local function getViewmodelTemplate(name: string): Model?
	local container = ReplicatedStorage:FindFirstChild("ViewModels")
	local template = container and container:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- Cette méthode permet de charger le set de clips d'un viewmodel lorsqu'il est préparé (nil si aucun fichier).
local function loadClipSet(name: string)
	local module = clipsFolder and clipsFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn("[ViewmodelSystem] aucun clip pour le viewmodel " .. name)
		return ViewmodelAnimator.compileSet({ Clips = {} })
	end
	return ViewmodelAnimator.compileSet(require(module) :: any)
end

-- Cette méthode permet de cloner un viewmodel dans la caméra et de préparer ses articulations à l'avance
-- lorsqu'un outil arrive dans le sac, pour qu'il n'y ait aucun coût au moment de l'equip.
local function prewarmViewmodel(tool: Instance)
	if not tool:IsA("Tool") then
		return
	end
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" or rigCache[viewmodelName] then
		return
	end
	local template = getViewmodelTemplate(viewmodelName)
	local cam = workspace.CurrentCamera
	if not template or not cam then
		return
	end

	local model = template:Clone()
	-- Plus d'animations Roblox : les anciens assets sont retirés pour qu'aucun Animator ne touche aux Motor6D
	for _, name in { "Animations", "AnimSaves" } do
		local folder = model:FindFirstChild(name)
		if folder then
			folder:Destroy()
		end
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	local parts: { BasePart } = {}
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("Motor6D") and d.Part1 then
			motors[d.Part1.Name] = { motor = d, c0 = d.C0 }
		end
	end

	local set = loadClipSet(viewmodelName)
	local rig: Rig = {
		model = model,
		parts = parts,
		motors = motors,
		set = set,
		animator = ViewmodelAnimator.new(set.clips),
	}
	setRigVisible(rig, false)
	model.Parent = cam
	rigCache[viewmodelName] = rig
end

-- Cette méthode permet d'afficher le viewmodel d'un outil et de lancer son animation d'equip lorsqu'il est équipé ;
-- l'equip dure exactement EquipTime (WeaponConfig).
local function equipTool(tool: Tool)
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" then
		return
	end
	clearViewmodel()
	prewarmViewmodel(tool)
	local rig = rigCache[viewmodelName]
	if not rig or not rig.model.PrimaryPart then
		return
	end

	local offset = tool:GetAttribute("ViewmodelOffset")
	currentOffset = (typeof(offset) == "CFrame") and offset or CFrame.new()
	active = rig

	local weaponName = tool:GetAttribute("WeaponName") or tool.Name
	local cfg = WeaponConfig.Weapons[weaponName]
	rig.animator:play("Equip", cfg and cfg.EquipTime)
	-- Première pose calculée avant d'afficher, pour éviter une frame dans la pose de repos du rig
	local cam = workspace.CurrentCamera
	if cam then
		rig.model:PivotTo(cam.CFrame * currentOffset)
	end
	setRigVisible(rig, true)
end

-- Cette méthode permet de brancher l'equip/unequip d'un outil sur le viewmodel lorsqu'il apparaît.
local function hookTool(tool: Instance)
	if not tool:IsA("Tool") or hookedTools[tool] then
		return
	end
	hookedTools[tool] = true
	prewarmViewmodel(tool)
	tool.Equipped:Connect(function()
		equipTool(tool)
	end)
	tool.Unequipped:Connect(clearViewmodel)
	tool.Destroying:Connect(function()
		hookedTools[tool] = nil
	end)
end

-- Cette méthode permet de suivre les outils du personnage lorsqu'il (ré)apparaît.
local function onCharacter(char: Model)
	clearViewmodel()
	for _, child in char:GetChildren() do
		hookTool(child)
	end
	char.ChildAdded:Connect(hookTool)
end

-- Cette méthode permet d'appliquer les marqueurs franchis pendant la frame lorsqu'un clip avance :
-- un gestionnaire dynamique (ex. Stab) choisit le son, sinon le son porte le nom du marqueur.
local function fireMarkers(rig: Rig, fired: { string })
	for _, name in fired do
		local handler = markerHandlers[name]
		if handler then
			local soundName = handler()
			if soundName then
				playRigSound(rig, soundName)
			end
		else
			playRigSound(rig, name)
		end
	end
end

-- Cette méthode permet de calculer et d'appliquer la frame du viewmodel lorsqu'elle est rendue :
-- pose des clips sur les Motor6D, puis décalage procédural sur le pivot du modèle.
local function renderStep(dt: number)
	local rig = active
	local cam = workspace.CurrentCamera
	if not rig or not cam then
		return
	end
	local pose, fired = rig.animator:step(dt)
	local deltas = ViewmodelAnimator.resolveDeltas(pose, rig.set.rig)
	for joint, entry in rig.motors do
		local delta = deltas[joint]
		entry.motor.Transform = delta and ViewmodelAnimator.toTransform(delta, entry.c0) or CFrame.new()
	end
	fireMarkers(rig, fired)

	motionInput.lateral = worldVelocity:Dot(cam.CFrame.RightVector)
	local proc = motion:update(dt, cam.CFrame, motionInput)
	rig.model:PivotTo(cam.CFrame * currentOffset * proc)
end

-- Cette méthode permet de lancer une animation du viewmodel actif lorsqu'une action d'arme démarre ;
-- duration étire le clip (ReloadTime…), handlers associe un marqueur à une fonction qui renvoie le son à jouer.
function ViewmodelSystem.play(name: string, duration: number?, handlers: { [string]: MarkerHandler }?): boolean
	if not active then
		return false
	end
	markerHandlers = handlers or {}
	return active.animator:play(name, duration)
end

-- Cette méthode permet d'interrompre l'action en cours (ex. inspect coupé par la lunette) avec un fondu.
function ViewmodelSystem.stopAction()
	if active then
		active.animator:stop()
	end
end

-- Cette méthode permet de savoir quelle animation d'action joue sur le viewmodel actif (nil si idle).
function ViewmodelSystem.getAction(): string?
	return active and active.animator:getAction() or nil
end

-- Cette méthode permet de transmettre l'état du mouvement du joueur lorsqu'il est calculé (bob, strafe, atterrissage).
function ViewmodelSystem.setMotion(speed: number, velocity: Vector3, onGround: boolean)
	motionInput.speed = speed
	motionInput.onGround = onGround
	motionInput.verticalSpeed = velocity.Y
	worldVelocity = Vector3.new(velocity.X, 0, velocity.Z)
end

function ViewmodelSystem.setVisible(visible: boolean)
	if active then
		setRigVisible(active, visible)
	end
end

function ViewmodelSystem.playSound(name: string)
	if active then
		playRigSound(active, name)
	end
end

function ViewmodelSystem.getActiveViewmodel(): Model?
	return active and active.model or nil
end

-- Cette méthode permet de piloter le viewmodel depuis la barre de commande de Studio lorsqu'on règle une
-- animation : play/seek/resume/setClips via le BindableFunction LocalPlayer.ViewmodelDebug (Studio uniquement).
local function createStudioDebug(player: Player)
	local fn = Instance.new("BindableFunction")
	fn.Name = "ViewmodelDebug"
	fn.OnInvoke = function(command: string, clip: any, value: number?)
		if not active then
			return "aucun viewmodel actif"
		end
		if command == "play" and clip then
			return ViewmodelSystem.play(clip, value)
		elseif command == "seek" and clip then
			return active.animator:seek(clip, value or 0)
		elseif command == "resume" then
			active.animator:resume()
			return true
		elseif command == "setClips" and type(clip) == "table" then
			-- Rechargement à chaud d'un set de clips (table du module clips/<Viewmodel>) pendant le réglage
			local set = ViewmodelAnimator.compileSet(clip :: any)
			active.set = set
			active.animator = ViewmodelAnimator.new(set.clips)
			return true
		end
		return "commande inconnue : " .. tostring(command)
	end
	fn.Parent = player
end

function ViewmodelSystem.init(player: Player?)
	local localPlayer = player or Players.LocalPlayer
	if not localPlayer then
		return
	end

	-- Un seul RenderStep pour toute la session, après la mise à jour de la caméra
	RunService:BindToRenderStep(boundStepName, Enum.RenderPriority.Camera.Value + 1, renderStep)

	if RunService:IsStudio() then
		createStudioDebug(localPlayer)
	end

	local backpack = localPlayer:WaitForChild("Backpack", 5)
	if backpack then
		for _, child in backpack:GetChildren() do
			hookTool(child)
		end
		backpack.ChildAdded:Connect(hookTool)
	end

	if localPlayer.Character then
		onCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return ViewmodelSystem

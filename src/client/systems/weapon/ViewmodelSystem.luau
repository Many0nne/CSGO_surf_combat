local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationSoundSystem = require(script.Parent.AnimationSoundSystem)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local ViewmodelSystem = {}

local activeViewmodel = nil :: Model?
local currentAnimSounds = nil :: { [string]: { string } }?
local preloadedTracks = {} :: { [string]: AnimationTrack }
local markerConns = {} :: { RBXScriptConnection }
local boundStepName = "ViewmodelUpdate"
local actionTrack = nil :: AnimationTrack? -- Equip / Shoot / Reload / Inspect : une seule piste d'action à la fois
local idleTrack = nil :: AnimationTrack? -- piste "Idle" bouclée sous les actions, si l'asset existe
local currentWeaponCfg = nil
local lastCamCFrame = nil :: CFrame?
local swayPos = Vector3.zero
local swayVel = Vector3.zero
local currentOffset = CFrame.new()

-- Pre-built caches: cloned models (always in camera, invisible until equip) + loaded tracks
local viewmodelCache = {} :: { [string]: Model }
local tracksCache = {} :: { [string]: { [string]: AnimationTrack } }
local partsCache = {} :: { [string]: { BasePart } }
-- Guard: prevents double-hooking when a tool moves Backpack → Character
local hookedTools = {} :: { [Tool]: boolean }

local SWAY_STRENGTH = 3.5
local SWAY_MAX = math.rad(6)
local SWAY_SPEED = 18
local SWAY_DAMPING = 1

-- Réglages de lecture des pistes du viewmodel (fondus en secondes).
local ANIM_FADE_IN = 0.08 -- entrée d'une action (tir, recharge, equip) : court pour rester réactif
local ANIM_FADE_OUT = 0.15 -- sortie d'une action interrompue par une autre : évite le "snap" de pose
local IDLE_FADE_IN = 0.2 -- retour progressif vers l'idle bouclé
local MATCH_RELOAD_TIME = true -- cale la vitesse de l'anim Reload sur WeaponConfig.ReloadTime
local RELOAD_SPEED_MIN = 0.75
local RELOAD_SPEED_MAX = 1.5
local IDLE_ANIMATION_NAME = "Idle"

-- Cette méthode permet d'arrêter une piste avec un fondu explicite lorsqu'elle existe.
local function stopTrack(track: AnimationTrack?, fade: number?)
	if track then
		track:Stop(fade or ANIM_FADE_OUT)
	end
end

-- Cette méthode permet de fixer priorité et bouclage d'une piste lorsqu'elle entre dans le cache :
-- l'idle reste sous les actions (priorité Idle, bouclé), toute autre piste passe en Action non bouclée.
local function configureTrack(name: string, track: AnimationTrack)
	if name == IDLE_ANIMATION_NAME then
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true
	else
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
	end
end

local function setModelVisibility(viewmodelName: string, visible: boolean)
	local parts = partsCache[viewmodelName]
	if not parts then
		return
	end
	local modifier = visible and 0 or 1
	for _, part in parts do
		part.LocalTransparencyModifier = modifier
	end
end

local activeViewmodelName = "" -- tracks which cache key is active for fast visibility toggle

local function clearViewmodel()
	-- Fondu 0 : le modèle est masqué tout de suite, il ne doit pas réapparaître au prochain equip en fin de fondu.
	stopTrack(actionTrack, 0)
	actionTrack = nil
	stopTrack(idleTrack, 0)
	idleTrack = nil
	currentWeaponCfg = nil
	if activeViewmodel then
		-- Coupe les sons encore en cours (ex. ClipIn d'une recharge annulée) : sinon ils continuent après le switch.
		-- Seuls les bruitages mécaniques (Equip/Reload) sont coupés ; le coup de feu garde sa traîne.
		local foley = {}
		for _, list in { currentAnimSounds and currentAnimSounds.Equip, currentAnimSounds and currentAnimSounds.Reload } do
			for _, n in list or {} do
				table.insert(foley, n)
			end
		end
		AnimationSoundSystem.stopSounds(activeViewmodel, foley)
		setModelVisibility(activeViewmodelName, false)
		activeViewmodel = nil
		activeViewmodelName = ""
	end
	lastCamCFrame = nil
	swayPos = Vector3.zero
	swayVel = Vector3.zero
	currentAnimSounds = nil
	preloadedTracks = {}
	currentOffset = CFrame.new()
	AnimationSoundSystem.disconnectAll(markerConns)
end

local function springUpdate(
	pos: Vector3,
	vel: Vector3,
	target: Vector3,
	speed: number,
	damping: number,
	dt: number
): (Vector3, Vector3)
	local displacement = target - pos
	local accel = displacement * (speed * speed) - vel * (2 * damping * speed)
	vel = vel + accel * dt
	pos = pos + vel * dt
	return pos, vel
end

local function getViewmodelTemplate(name: string): Model?
	local container = ReplicatedStorage:FindFirstChild("ViewModels")
	if not container then
		return nil
	end
	local template = container:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function ensurePrimaryPart(model: Model)
	if model.PrimaryPart then
		return
	end
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		model.PrimaryPart = firstPart
	end
end

-- Clones the viewmodel and pre-loads all animations ahead of equip time.
-- The clone stays parented to the camera (invisible) so no re-registration overhead at equip.
local function prewarmViewmodel(tool: Instance)
	if not tool:IsA("Tool") then
		return
	end
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" then
		return
	end
	if viewmodelCache[viewmodelName] then
		return
	end

	local template = getViewmodelTemplate(viewmodelName)
	if not template then
		return
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local model = template:Clone()
	model.Parent = cam
	ensurePrimaryPart(model)

	-- Disable Humanoid state machine — viewmodels don't need character AI/physics simulation
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.HealthDisplayDistance = 0
		humanoid.NameDisplayDistance = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Pre-cache BaseParts list so visibility toggle never calls GetDescendants()
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d :: BasePart)
		end
	end
	partsCache[viewmodelName] = parts

	-- Hide before storing
	local modifier = 1
	for _, part in parts do
		part.LocalTransparencyModifier = modifier
	end

	local tracks = {}
	local animator = AnimationSoundSystem.getAnimator(model)
	if animator then
		local folder = model:FindFirstChild("Animations") or model:FindFirstChild("AnimSaves")
		if folder and folder:IsA("Folder") then
			for _, obj in folder:GetChildren() do
				if obj:IsA("Animation") then
					local t = animator:LoadAnimation(obj)
					configureTrack(obj.Name, t)
					tracks[obj.Name] = t
				end
			end
		end
	end

	viewmodelCache[viewmodelName] = model
	tracksCache[viewmodelName] = tracks
end

-- Cette méthode permet de récupérer (ou charger puis mettre en cache) la piste `name` du viewmodel actif
-- lorsqu'une animation est demandée ; évite de recharger une piste à chaque tir quand le prewarm l'a ratée.
local function getTrack(name: string): AnimationTrack?
	local cached = preloadedTracks[name]
	if cached then
		return cached
	end
	if not activeViewmodel then
		return nil
	end
	local folder = activeViewmodel:FindFirstChild("Animations") or activeViewmodel:FindFirstChild("AnimSaves")
	local anim = folder and folder:FindFirstChild(name)
	if not anim or not anim:IsA("Animation") then
		return nil
	end
	local animator = AnimationSoundSystem.getAnimator(activeViewmodel)
	if not animator then
		return nil
	end
	local track = animator:LoadAnimation(anim)
	configureTrack(name, track)
	preloadedTracks[name] = track
	return track
end

-- Cette méthode permet de lancer l'idle bouclé sous les actions lorsque le viewmodel en possède un,
-- pour que la fin d'une action se fonde dans une pose vivante au lieu de retomber sur la pose du rig.
local function ensureIdle(fade: number)
	local track = getTrack(IDLE_ANIMATION_NAME)
	if track and not track.IsPlaying then
		track:Play(fade)
	end
	idleTrack = track
end

-- Cette méthode permet de démarrer une piste d'action en remplaçant la précédente (fondu croisé) lorsque
-- l'arme tire, recharge ou s'équipe ; les connexions de marqueurs de l'ancienne piste sont coupées.
local function startAction(name: string, speed: number?): AnimationTrack?
	local track = getTrack(name)
	if not track then
		return nil
	end
	AnimationSoundSystem.disconnectAll(markerConns)
	-- Même piste relancée (tir répété) : Stop sans fondu pour repartir proprement de 0.
	stopTrack(actionTrack, if actionTrack == track then 0 else ANIM_FADE_OUT)
	track:Play(ANIM_FADE_IN, 1, speed or 1)
	actionTrack = track
	ensureIdle(IDLE_FADE_IN)
	return track
end

-- Cette méthode permet de brancher les sons de WeaponConfig.AnimationSounds[name] sur une piste lorsque
-- celle-ci vient d'être lancée ; les marqueurs déjà pris par `overrides` sont ignorés pour ne pas jouer deux sons.
local function connectConfiguredSounds(track: AnimationTrack, name: string, overrides: { [string]: any }?)
	if not activeViewmodel then
		return
	end
	local sounds = AnimationSoundSystem.withoutOverridden(currentAnimSounds and currentAnimSounds[name], overrides)
	for _, c in AnimationSoundSystem.connectSoundMarkers(track, activeViewmodel, sounds) do
		table.insert(markerConns, c)
	end
end

local function equipTool(tool: Tool)
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" then
		return
	end

	clearViewmodel()

	local weaponName = tool:GetAttribute("WeaponName") or tool.Name
	local cfg = WeaponConfig.Weapons and WeaponConfig.Weapons[weaponName]
	currentWeaponCfg = cfg
	currentAnimSounds = cfg and cfg.AnimationSounds or nil

	if not viewmodelCache[viewmodelName] then
		prewarmViewmodel(tool)
	end

	activeViewmodel = viewmodelCache[viewmodelName]
	if not activeViewmodel or not activeViewmodel.PrimaryPart then
		activeViewmodel = nil
		return
	end

	local offset = tool:GetAttribute("ViewmodelOffset")
	currentOffset = (typeof(offset) == "CFrame") and offset or CFrame.new()

	preloadedTracks = tracksCache[viewmodelName] or {}
	activeViewmodelName = viewmodelName

	-- Pre-position before revealing to avoid a 1-frame pop at world origin
	local cam = workspace.CurrentCamera
	if cam then
		activeViewmodel:PivotTo(cam.CFrame * currentOffset)
	end
	setModelVisibility(viewmodelName, true)

	ensureIdle(0)
	local track = startAction("Equip")
	if track then
		connectConfiguredSounds(track, "Equip")
	end
end

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") then
		return
	end
	-- Guard: a tool moves Backpack → Character on equip, which fires ChildAdded again.
	-- Without this, Equipped/Unequipped get double-connected causing two equipTool calls.
	if hookedTools[tool :: Tool] then
		return
	end
	hookedTools[tool :: Tool] = true
	-- Libère la garde quand l'outil est détruit (respawn) : sinon la table grossit à chaque vie.
	tool.Destroying:Connect(function()
		hookedTools[tool :: Tool] = nil
	end)

	prewarmViewmodel(tool)

	tool.Equipped:Connect(function()
		equipTool(tool :: Tool)
	end)
	tool.Unequipped:Connect(function()
		clearViewmodel()
	end)
end

local function onCharacter(char: Model)
	clearViewmodel()
	for _, child in char:GetChildren() do
		hookTool(child)
	end
	char.ChildAdded:Connect(function(child)
		hookTool(child)
	end)
end

function ViewmodelSystem.playAnimation(name: string, markerOverrides: { [string]: string | () -> string }?)
	if not activeViewmodel then
		return
	end
	local track = startAction(name)
	if not track then
		return
	end
	if markerOverrides then
		for markerName, value in markerOverrides do
			local c
			if type(value) == "function" then
				c = AnimationSoundSystem.connectDynamicMarker(track, activeViewmodel, markerName, value)
			else
				c = AnimationSoundSystem.connectSoundMarker(track, activeViewmodel, markerName, value)
			end
			if c then
				table.insert(markerConns, c)
			end
		end
	end
	-- Les overrides complètent les sons de WeaponConfig au lieu de les remplacer entièrement.
	connectConfiguredSounds(track, name, markerOverrides)
end

function ViewmodelSystem.setVisible(visible: boolean)
	if not activeViewmodel then
		return
	end
	setModelVisibility(activeViewmodelName, visible)
end

function ViewmodelSystem.playSound(name: string)
	if not activeViewmodel then
		return
	end
	local sounds = activeViewmodel:FindFirstChild("Sounds")
	if not sounds then
		return
	end
	local s = sounds:FindFirstChild(name)
	if s and s:IsA("Sound") then
		s:Play()
	end
end

function ViewmodelSystem.getActiveViewmodel()
	return activeViewmodel
end

function ViewmodelSystem.getPreloadedTrackLength(name: string): number
	local t = preloadedTracks[name]
	return t and t.Length or 0
end

function ViewmodelSystem.playReload(_model: Model?)
	if not activeViewmodel then
		return
	end
	local speed = 1
	local reloadTrack = getTrack("Reload")
	if MATCH_RELOAD_TIME and reloadTrack and currentWeaponCfg then
		speed = AnimationSoundSystem.computePlaybackSpeed(
			reloadTrack.Length,
			currentWeaponCfg.ReloadTime,
			RELOAD_SPEED_MIN,
			RELOAD_SPEED_MAX
		)
	end
	local track = startAction("Reload", speed)
	if track then
		connectConfiguredSounds(track, "Reload")
	end
end

function ViewmodelSystem.init(player: Player?)
	local localPlayer = player or Players.LocalPlayer
	if not localPlayer then
		return
	end

	-- Single RenderStep for the session lifetime — no bind/unbind per equip
	RunService:BindToRenderStep(boundStepName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not activeViewmodel then
			lastCamCFrame = nil
			swayPos = Vector3.zero
			swayVel = Vector3.zero
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		dt = dt or (1 / 60)
		if not lastCamCFrame then
			lastCamCFrame = cam.CFrame
		end
		local delta = lastCamCFrame:ToObjectSpace(cam.CFrame)
		local dx, dy = delta:ToOrientation()
		lastCamCFrame = cam.CFrame

		local targetVec = Vector3.new(-dx, -dy, 0) * SWAY_STRENGTH
		local clamped = Vector3.new(
			math.clamp(targetVec.X, -SWAY_MAX, SWAY_MAX),
			math.clamp(targetVec.Y, -SWAY_MAX, SWAY_MAX),
			math.clamp(targetVec.Z, -SWAY_MAX, SWAY_MAX)
		)
		swayPos, swayVel = springUpdate(swayPos, swayVel, clamped, SWAY_SPEED, SWAY_DAMPING, dt)
		local sway = CFrame.Angles(swayPos.X, swayPos.Y, swayPos.Z)
		activeViewmodel:PivotTo(cam.CFrame * currentOffset * sway)
	end)

	local backpack = localPlayer:WaitForChild("Backpack", 5)
	if backpack then
		for _, child in backpack:GetChildren() do
			hookTool(child)
		end
		backpack.ChildAdded:Connect(function(child)
			hookTool(child)
		end)
	end

	if localPlayer.Character then
		onCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return ViewmodelSystem

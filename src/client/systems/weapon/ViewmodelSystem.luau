local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationSoundSystem = require(script.Parent.AnimationSoundSystem)
local WeaponConfig        = require(ReplicatedStorage.Shared.WeaponConfig)

local ViewmodelSystem = {}

local activeViewmodel    = nil :: Model?
local currentAnimSounds  = nil :: {[string]: {string}}?
local preloadedTracks    = {} :: {[string]: AnimationTrack}
local markerConns        = {} :: {RBXScriptConnection}
local boundStepName = "ViewmodelUpdate"
local equipTrack  = nil :: AnimationTrack?
local shootTrack  = nil :: AnimationTrack?
local actionTrack = nil :: AnimationTrack?
local lastCamCFrame = nil :: CFrame?
local swayPos = Vector3.zero
local swayVel = Vector3.zero
local currentOffset = CFrame.new()

-- Pre-built caches: cloned models (always in camera, invisible until equip) + loaded tracks
local viewmodelCache = {} :: {[string]: Model}
local tracksCache    = {} :: {[string]: {[string]: AnimationTrack}}
local partsCache     = {} :: {[string]: {BasePart}}
-- Guard: prevents double-hooking when a tool moves Backpack → Character
local hookedTools = {} :: {[Tool]: boolean}

local SWAY_STRENGTH = 3.5
local SWAY_MAX = math.rad(6)
local SWAY_SPEED = 18
local SWAY_DAMPING = 1

local function stopTrack(track: AnimationTrack?)
	if track then
		track:Stop()
	end
end

local function setModelVisibility(viewmodelName: string, visible: boolean)
	local parts = partsCache[viewmodelName]
	if not parts then return end
	local modifier = visible and 0 or 1
	for _, part in parts do
		part.LocalTransparencyModifier = modifier
	end
end

local activeViewmodelName = "" -- tracks which cache key is active for fast visibility toggle

local function clearViewmodel()
	stopTrack(equipTrack);  equipTrack  = nil
	stopTrack(shootTrack);  shootTrack  = nil
	stopTrack(actionTrack); actionTrack = nil
	if activeViewmodel then
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
	for _, c in markerConns do c:Disconnect() end
	markerConns = {}
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
	if not container then return nil end
	local template = container:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function ensurePrimaryPart(model: Model)
	if model.PrimaryPart then return end
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		model.PrimaryPart = firstPart
	end
end

-- Clones the viewmodel and pre-loads all animations ahead of equip time.
-- The clone stays parented to the camera (invisible) so no re-registration overhead at equip.
local function prewarmViewmodel(tool: Instance)
	if not tool:IsA("Tool") then return end
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" then return end
	if viewmodelCache[viewmodelName] then return end

	local template = getViewmodelTemplate(viewmodelName)
	if not template then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

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
	local parts: {BasePart} = {}
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
					t.Looped = false
					tracks[obj.Name] = t
				end
			end
		end
	end

	viewmodelCache[viewmodelName] = model
	tracksCache[viewmodelName] = tracks
end

local function playEquipAnimation(model: Model)
	local track = preloadedTracks["Equip"]
	if not track then return end

	equipTrack = track
	equipTrack:Play()

	local sounds = currentAnimSounds and currentAnimSounds["Equip"] or {}
	local newConns = AnimationSoundSystem.connectSoundMarkers(equipTrack, model, sounds)
	for _, c in newConns do table.insert(markerConns, c) end
end

local function equipTool(tool: Tool)
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" then return end

	clearViewmodel()

	local weaponName = tool:GetAttribute("WeaponName") or tool.Name
	local cfg = WeaponConfig.Weapons and WeaponConfig.Weapons[weaponName]
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

	playEquipAnimation(activeViewmodel)
end

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") then return end
	-- Guard: a tool moves Backpack → Character on equip, which fires ChildAdded again.
	-- Without this, Equipped/Unequipped get double-connected causing two equipTool calls.
	if hookedTools[tool :: Tool] then return end
	hookedTools[tool :: Tool] = true

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

function ViewmodelSystem.playAnimation(name: string, markerOverrides: {[string]: string}?)
	if not activeViewmodel then return end
	local animations = activeViewmodel:FindFirstChild("Animations")
		or activeViewmodel:FindFirstChild("AnimSaves")
	if not animations then return end
	local anim = animations:FindFirstChild(name)
	if not anim or not anim:IsA("Animation") then return end
	local animator = AnimationSoundSystem.getAnimator(activeViewmodel)
	if not animator then return end

	stopTrack(equipTrack);  equipTrack  = nil
	stopTrack(actionTrack); actionTrack = nil

	local track = preloadedTracks[name] or animator:LoadAnimation(anim)
	track.Looped = false
	track:Play()
	actionTrack = track
	for _, c in markerConns do c:Disconnect() end
	markerConns = {}
	if markerOverrides then
		for markerName, value in markerOverrides do
			local c
			if type(value) == "function" then
				c = AnimationSoundSystem.connectDynamicMarker(track, activeViewmodel, markerName, value)
			else
				c = AnimationSoundSystem.connectSoundMarker(track, activeViewmodel, markerName, value)
			end
			if c then table.insert(markerConns, c) end
		end
	else
		local sounds = currentAnimSounds and currentAnimSounds[name] or {}
		local newConns = AnimationSoundSystem.connectSoundMarkers(track, activeViewmodel, sounds)
		for _, c in newConns do table.insert(markerConns, c) end
	end
end

function ViewmodelSystem.setVisible(visible: boolean)
	if not activeViewmodel then return end
	setModelVisibility(activeViewmodelName, visible)
end

function ViewmodelSystem.playSound(name: string)
	if not activeViewmodel then return end
	local sounds = activeViewmodel:FindFirstChild("Sounds")
	if not sounds then return end
	local s = sounds:FindFirstChild(name)
	if s and s:IsA("Sound") then s:Play() end
end

function ViewmodelSystem.getActiveViewmodel()
	return activeViewmodel
end

function ViewmodelSystem.getPreloadedTrackLength(name: string): number
	local t = preloadedTracks[name]
	return t and t.Length or 0
end

function ViewmodelSystem.playReload(model: Model?)
	local m = model or activeViewmodel
	if not m then return end
	local animations = m:FindFirstChild("Animations") or m:FindFirstChild("AnimSaves")
	if not animations then return end
	local reloadAnim = animations:FindFirstChild("Reload")
	if not reloadAnim or not reloadAnim:IsA("Animation") then return end
	local animator = AnimationSoundSystem.getAnimator(m)
	if not animator then return end
	stopTrack(equipTrack);  equipTrack  = nil
	stopTrack(actionTrack); actionTrack = nil
	local track = preloadedTracks["Reload"] or animator:LoadAnimation(reloadAnim)
	track.Looped = false
	track:Play()
	actionTrack = track
	local sounds = currentAnimSounds and currentAnimSounds["Reload"] or {}
	local newConns = AnimationSoundSystem.connectSoundMarkers(track, m, sounds)
	for _, c in newConns do table.insert(markerConns, c) end
end

function ViewmodelSystem.init(player: Player?)
	local localPlayer = player or Players.LocalPlayer
	if not localPlayer then return end

	-- Single RenderStep for the session lifetime — no bind/unbind per equip
	RunService:BindToRenderStep(boundStepName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not activeViewmodel then
			lastCamCFrame = nil
			swayPos = Vector3.zero
			swayVel = Vector3.zero
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then return end
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

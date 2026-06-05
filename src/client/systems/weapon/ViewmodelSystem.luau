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
local renderConn = nil :: RBXScriptConnection?
local boundStepName = "ViewmodelUpdate"
local equipTrack  = nil :: AnimationTrack?
local shootTrack  = nil :: AnimationTrack?
local actionTrack = nil :: AnimationTrack?
local lastCamCFrame = nil :: CFrame?
local swayPos = Vector3.zero
local swayVel = Vector3.zero

local SWAY_STRENGTH = 3.5
local SWAY_MAX = math.rad(6)
local SWAY_SPEED = 18
local SWAY_DAMPING = 1

local function stopTrack(track: AnimationTrack?)
	if track then
		track:Stop()
	end
end

local function clearViewmodel()
	stopTrack(equipTrack)
	equipTrack = nil
	stopTrack(shootTrack)
	shootTrack = nil
	stopTrack(actionTrack)
	actionTrack = nil
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	RunService:UnbindFromRenderStep(boundStepName)
	if activeViewmodel then
		activeViewmodel:Destroy()
		activeViewmodel = nil
	end
	lastCamCFrame = nil
	swayPos = Vector3.zero
	swayVel = Vector3.zero
	currentAnimSounds = nil
	preloadedTracks = {}
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



local function preloadAnimations(model: Model, animator: Animator)
	preloadedTracks = {}
	local folder = model:FindFirstChild("Animations") or model:FindFirstChild("AnimSaves")
	if not folder then return end
	for _, obj in folder:GetChildren() do
		if obj:IsA("Animation") then
			local t = animator:LoadAnimation(obj)
			t.Looped = false
			preloadedTracks[obj.Name] = t
		end
	end
end

local function playEquipAnimation(model: Model)
	local animator = AnimationSoundSystem.getAnimator(model)
	if not animator then return end

	local track = preloadedTracks["Equip"]
	if not track then
		local animations = model:FindFirstChild("Animations") or model:FindFirstChild("AnimSaves")
		if not animations then return end
		local equip = animations:FindFirstChild("Equip")
		if not equip or not equip:IsA("Animation") then return end
		track = animator:LoadAnimation(equip)
		track.Looped = false
	end

	equipTrack = track
	equipTrack:Play()

	local sounds = currentAnimSounds and currentAnimSounds["Equip"] or {}
	local newConns = AnimationSoundSystem.connectSoundMarkers(equipTrack, model, sounds)
	for _, c in newConns do table.insert(markerConns, c) end


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


local function equipTool(tool: Tool)
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	if type(viewmodelName) ~= "string" or viewmodelName == "" then return end

	local template = getViewmodelTemplate(viewmodelName)
	if not template then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

	clearViewmodel()

	local weaponName = tool:GetAttribute("WeaponName") or tool.Name
	local cfg = WeaponConfig.Weapons and WeaponConfig.Weapons[weaponName]
	currentAnimSounds = cfg and cfg.AnimationSounds or nil
	activeViewmodel = template:Clone()
	activeViewmodel.Parent = cam
	ensurePrimaryPart(activeViewmodel)
	if not activeViewmodel.PrimaryPart then
		clearViewmodel()
		return
	end

	local animator = AnimationSoundSystem.getAnimator(activeViewmodel)
	if animator then
		preloadAnimations(activeViewmodel, animator)
	end

	local offset = tool:GetAttribute("ViewmodelOffset")
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.new()
	end

	RunService:BindToRenderStep(boundStepName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not activeViewmodel or not cam then return end
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
		activeViewmodel:PivotTo(cam.CFrame * offset * sway)
	end)

	playEquipAnimation(activeViewmodel)
end

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") then return end

	tool.Equipped:Connect(function()
		equipTool(tool)
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

	stopTrack(equipTrack)
	equipTrack = nil
	stopTrack(actionTrack)
	actionTrack = nil

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
	local modifier = visible and 0 or 1
	for _, obj in activeViewmodel:GetDescendants() do
		if obj:IsA("BasePart") then
			(obj :: BasePart).LocalTransparencyModifier = modifier
		end
	end
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
	stopTrack(equipTrack)
	equipTrack = nil
	stopTrack(actionTrack)
	actionTrack = nil
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

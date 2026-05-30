local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ViewmodelSystem = {}

local activeViewmodel = nil :: Model?
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


local function getAnimator(model: Model): Animator?
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if controller then
		local animator = controller:FindFirstChildWhichIsA("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = controller
		end
		return animator
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		local animator = humanoid:FindFirstChildWhichIsA("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator
	end

	return nil
end


local function connectSoundMarkers(track: AnimationTrack, model: Model, mapping: {[string]: string})
	local sounds = model:FindFirstChild("Sounds")
	if not sounds then return end
	for marker, soundName in mapping do
		local s = sounds:FindFirstChild(soundName)
		if s and s:IsA("Sound") then
			track:GetMarkerReachedSignal(marker):Connect(function()
				s:Play()
			end)
		end
	end
end

local function playEquipAnimation(model: Model)
	local animations = model:FindFirstChild("Animations") or model:FindFirstChild("AnimSaves")
	if not animations then return end

	local equip = animations:FindFirstChild("Equip")
	if not equip or not equip:IsA("Animation") then return end

	local animator = getAnimator(model)
	if not animator then return end

	equipTrack = animator:LoadAnimation(equip)
	equipTrack.Looped = false
	equipTrack:Play()

	connectSoundMarkers(equipTrack, model, {
		["Bolt Sound"] = "Bolt",
		["Draw Sound"] = "Draw",
	})


end

local function getViewmodelTemplate(name: string): Model?
	local container = ReplicatedStorage:FindFirstChild("Viewmodels")
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
	activeViewmodel = template:Clone()
	activeViewmodel.Parent = cam
	ensurePrimaryPart(activeViewmodel)
	if not activeViewmodel.PrimaryPart then
		clearViewmodel()
		return
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

function ViewmodelSystem.playAnimation(name: string)
	if not activeViewmodel then return end
	local animations = activeViewmodel:FindFirstChild("Animations")
		or activeViewmodel:FindFirstChild("AnimSaves")
	if not animations then return end
	local anim = animations:FindFirstChild(name)
	if not anim or not anim:IsA("Animation") then return end
	local animator = getAnimator(activeViewmodel)
	if not animator then return end

	stopTrack(equipTrack)
	equipTrack = nil
	stopTrack(actionTrack)
	actionTrack = nil

	local track = animator:LoadAnimation(anim)
	track.Looped = false
	track:Play()
	actionTrack = track
	if name == "Shoot" then
		connectSoundMarkers(track, activeViewmodel, {
			["Shoot Sound"] = "Shoot",
			["Bolt Sound"]  = "Bolt",
		})
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

function ViewmodelSystem.playReload(model: Model?)
	local m = model or activeViewmodel
	if not m then return end
	local animations = m:FindFirstChild("Animations") or m:FindFirstChild("AnimSaves")
	if not animations then return end
	local reloadAnim = animations:FindFirstChild("Reload")
	if not reloadAnim or not reloadAnim:IsA("Animation") then return end
	local animator = getAnimator(m)
	if not animator then return end
	stopTrack(equipTrack)
	equipTrack = nil
	stopTrack(actionTrack)
	actionTrack = nil
	local track = animator:LoadAnimation(reloadAnim)
	track.Looped = false
	track:Play()
	actionTrack = track
	connectSoundMarkers(track, m, {
		["Bolt Sound"]    = "Bolt",
		["ClipHit Sound"] = "ClipHit",
		["ClipIn Sound"]  = "ClipIn",
		["ClipOut Sound"] = "ClipOut",
	})
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

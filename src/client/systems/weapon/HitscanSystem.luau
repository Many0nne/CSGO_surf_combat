local Players  = game:GetService("Players")
local Debris   = game:GetService("Debris")

local HitscanSystem = {}

local hitscanEvent: RemoteEvent? = nil

local TRACER_LIFETIME = 0.1
local TRACER_WIDTH    = 0.05
local TRACER_COLOR    = Color3.fromRGB(255, 240, 180)

local function spawnTracer(origin: Vector3, endpoint: Vector3)
	local length = (endpoint - origin).Magnitude
	local mid    = (origin + endpoint) / 2
	local p = Instance.new("Part")
	p.Anchored      = true
	p.CanCollide    = false
	p.CastShadow    = false
	p.Size          = Vector3.new(TRACER_WIDTH, TRACER_WIDTH, length)
	p.CFrame        = CFrame.lookAt(mid, endpoint)
	p.Color         = TRACER_COLOR
	p.Material      = Enum.Material.Neon
	p.Parent        = workspace
	Debris:AddItem(p, TRACER_LIFETIME)
end

function HitscanSystem.init(event: RemoteEvent?)
	hitscanEvent = event
end

function HitscanSystem.resolveHit(cfg, activeViewmodel: Model?): string
	local cam = workspace.CurrentCamera
	if not cam then return "Shoot_void" end

	local params = RaycastParams.new()
	local filtered = { Players.LocalPlayer.Character }
	if activeViewmodel then table.insert(filtered, activeViewmodel) end
	params.FilterDescendantsInstances = filtered
	params.FilterType = Enum.RaycastFilterType.Exclude

	local origin  = cam.CFrame.Position
	local ray_dir = cam.CFrame.LookVector * 2048
	local result  = workspace:Raycast(origin, ray_dir, params)
	local endpoint = result and result.Position or (origin + ray_dir)
	spawnTracer(origin, endpoint)
	if not result then return "Shoot_void" end

	local hit = result.Instance
	local targetChar = hit.Parent
	local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		targetChar = targetChar.Parent
		humanoid = targetChar and targetChar:FindFirstChildWhichIsA("Humanoid")
	end
	if not humanoid then return "Shoot_wall" end

	local damage = cfg and cfg.Damage or 0
	if hitscanEvent and targetChar then
		hitscanEvent:FireServer(targetChar, damage)
	end
	return "Shoot_human"
end

return HitscanSystem

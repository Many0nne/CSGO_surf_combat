local Players = game:GetService("Players")

local MeleeHitDetection = {}

local meleeEvent: RemoteEvent? = nil

function MeleeHitDetection.init(event: RemoteEvent?)
	meleeEvent = event
end

local function isBackstab(hitInstance: Instance): boolean
	local char = hitInstance.Parent
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		char = char.Parent
		if not char then return false end
		hrp = char:FindFirstChild("HumanoidRootPart")
	end
	if not hrp then return false end
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local toAttacker = cam.CFrame.Position - (hrp :: BasePart).Position
	return toAttacker:Dot((hrp :: BasePart).CFrame.LookVector) < 0
end

-- Retourne le nom du son à jouer ("Shoot_void", "Shoot_human", "Shoot_wall")
-- et applique les dégâts via RemoteEvent si cible humaine.
function MeleeHitDetection.resolveHit(cfg, activeViewmodel: Model?): string
	local range = cfg and cfg.MeleeRange or 80
	local cam = workspace.CurrentCamera
	if not cam then return "Shoot_void" end

	local params = RaycastParams.new()
	local filtered = { Players.LocalPlayer.Character }
	if activeViewmodel then table.insert(filtered, activeViewmodel) end
	params.FilterDescendantsInstances = filtered
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * range, params)
	if not result then return "Shoot_void" end

	local hit = result.Instance
	local isHuman = hit.Parent:FindFirstChildWhichIsA("Humanoid")
		or (hit.Parent.Parent and hit.Parent.Parent:FindFirstChildWhichIsA("Humanoid"))
	if not isHuman then return "Shoot_wall" end

	local backstabMult = isBackstab(hit) and (cfg and cfg.BackstabMultiplier or 2) or 1
	local damage = (cfg and cfg.Damage or 50) * backstabMult
	local targetChar = hit.Parent
	if not targetChar:FindFirstChildWhichIsA("Humanoid") then
		targetChar = targetChar.Parent
	end
	if meleeEvent and targetChar then
		meleeEvent:FireServer(targetChar, damage)
	end
	return "Shoot_human"
end

return MeleeHitDetection

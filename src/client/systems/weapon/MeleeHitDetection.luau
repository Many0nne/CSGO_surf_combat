local Players = game:GetService("Players")

local MeleeHitDetection = {}

local meleeEvent: RemoteEvent? = nil

function MeleeHitDetection.init(event: RemoteEvent?)
	meleeEvent = event
end

-- Retourne le nom du son à jouer ("Shoot_void", "Shoot_human", "Shoot_wall")
-- et signale la touche au serveur si cible humaine : il calcule lui-même les dégâts d'après attackKind.
function MeleeHitDetection.resolveHit(cfg, activeViewmodel: Model?, attackKind: string): string
	local range = cfg and cfg.MeleeRange or 80
	local cam = workspace.CurrentCamera
	if not cam then
		return "Shoot_void"
	end

	local params = RaycastParams.new()
	local filtered = { Players.LocalPlayer.Character }
	if activeViewmodel then
		table.insert(filtered, activeViewmodel)
	end
	params.FilterDescendantsInstances = filtered
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * range, params)
	if not result then
		return "Shoot_void"
	end

	local hit = result.Instance
	local isHuman = hit.Parent:FindFirstChildWhichIsA("Humanoid")
		or (hit.Parent.Parent and hit.Parent.Parent:FindFirstChildWhichIsA("Humanoid"))
	if not isHuman then
		return "Shoot_wall"
	end

	local targetChar = hit.Parent
	if not targetChar:FindFirstChildWhichIsA("Humanoid") then
		targetChar = targetChar.Parent
	end
	if meleeEvent and targetChar then
		meleeEvent:FireServer(targetChar, attackKind)
	end
	return "Shoot_human"
end

return MeleeHitDetection

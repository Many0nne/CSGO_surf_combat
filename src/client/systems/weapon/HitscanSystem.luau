local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponConfig"))
local ShotEffects = require(script.Parent.ShotEffects)

local HitscanSystem = {}

local hitscanEvent: RemoteEvent? = nil
local shotFiredEvent: RemoteEvent? = nil

-- Cette méthode permet de brancher les remotes du tir lorsque le système d'armes démarre : touche (HitscanDamage) et
-- tir parti, entendu par les autres joueurs (ShotFired, #156).
function HitscanSystem.init(event: RemoteEvent?, shotEvent: RemoteEvent?)
	hitscanEvent = event
	shotFiredEvent = shotEvent
end

function HitscanSystem.resolveHit(activeViewmodel: Model?): string
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

	local origin = cam.CFrame.Position
	local direction = cam.CFrame.LookVector
	-- Instant du tir sur l'horloge serveur : le serveur y rembobine la cible (#174)
	local shotTime = workspace:GetServerTimeNow()
	-- Tir parti, touché ou manqué : le serveur le compte dans le chargeur (#215) et le relaie aux autres clients, qui
	-- jouent son son et le recul de l'arme 3P (#156). Avant la touche, avec le même shotTime, auquel le serveur la
	-- rattache (#216) : deux RemoteEvent d'un même client arrivent dans l'ordre d'envoi.
	if shotFiredEvent then
		shotFiredEvent:FireServer(origin, direction, shotTime)
	end
	local ray_dir = direction * WeaponConfig.HITSCAN_RANGE
	local result = workspace:Raycast(origin, ray_dir, params)
	local endpoint = result and result.Position or (origin + ray_dir)
	-- Flamme du viewmodel et rayon de son canon jusqu'à l'impact (#54)
	ShotEffects.playLocal(activeViewmodel, origin, endpoint)
	if not result then
		return "Shoot_void"
	end

	local hit = result.Instance
	local targetChar = hit.Parent
	local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		targetChar = targetChar.Parent
		humanoid = targetChar and targetChar:FindFirstChildWhichIsA("Humanoid")
	end
	if not humanoid then
		return "Shoot_wall"
	end

	if hitscanEvent and targetChar then
		-- Ce que le tir a réellement fait, vérifié par le serveur (origine, visée, ligne de vue, portée : #174)
		hitscanEvent:FireServer(targetChar, hit, origin, direction, result.Position, shotTime)
	end
	return "Shoot_human"
end

return HitscanSystem

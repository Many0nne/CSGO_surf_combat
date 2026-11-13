local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapGeometry"))
local MapSelection = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapSelection"))
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

-- Cette méthode permet de lister ce que le tir traverse dans la map jouée lorsqu'un tir part : murs d'air et grillages
-- (#292, même règle que la ligne de vue du serveur) ; vide tant que la map n'est pas choisie.
local function seeThrough(): { Instance }
	local maps = workspace:FindFirstChild("Maps")
	local name = maps and maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	local map = if maps and type(name) == "string" then maps:FindFirstChild(name) else nil
	return if map then MapGeometry.bulletTransparent(map) else {}
end

-- Cette méthode permet de résoudre un tir du joueur lorsqu'il tire : rayon de la caméra (personnage, viewmodel, murs
-- d'air et grillages traversés), effets locaux, puis touche envoyée au serveur.
function HitscanSystem.resolveHit(activeViewmodel: Model?): string
	local cam = workspace.CurrentCamera
	if not cam then
		return "Shoot_void"
	end

	local params = RaycastParams.new()
	local filtered = table.clone(seeThrough())
	table.insert(filtered, Players.LocalPlayer.Character)
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
	-- Flamme du viewmodel et rayon de son canon jusqu'à l'impact (#54) ; dans son propre fil : une erreur des effets
	-- n'empêche pas d'envoyer la touche
	task.spawn(ShotEffects.playLocal, activeViewmodel, origin, endpoint)
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

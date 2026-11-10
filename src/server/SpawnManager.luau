local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local BotCombatRules = require(ReplicatedStorage.Shared.BotCombatRules)
local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local SpawnLaunch = require(ReplicatedStorage.Shared.SpawnLaunch)

local SpawnManager = {}

local mapModel: Instance?

-- Cette méthode permet de trouver la map jouée (GameConfig.ACTIVE_MAP dans Workspace.Maps) lorsqu'un joueur demande à
-- apparaître.
local function getMap(): Instance?
	if mapModel and mapModel.Parent then
		return mapModel
	end
	mapModel = MapSelection.waitForActive(10)
	return mapModel
end

-- Cette méthode permet de tirer un enfant au hasard d'un dossier de la map lorsqu'on choisit un point d'apparition.
local function pickPoint(folderName: string): BasePart?
	local map = getMap()
	local folder = map and map:FindFirstChild(folderName)
	local points = folder and folder:GetChildren() or {}
	if #points == 0 then
		return nil
	end
	return points[math.random(1, #points)] :: BasePart
end

-- Cette méthode permet de rendre le joueur invulnérable pendant le lancement lorsqu'il sort du soleil
-- (ForceField invisible : Humanoid:TakeDamage l'ignore, cf. Validator.hitOutcome).
local function protect(char: Model)
	local field = Instance.new("ForceField")
	field.Visible = false
	field.Parent = char
	Debris:AddItem(field, GameConfig.SPAWN_PROTECTION)
end

-- Cette méthode permet de placer un personnage qui vient d'apparaître (joueur ou bot, #139) : lancé depuis le soleil
-- (#69) si la map a des points Maps.Map.SunLaunch, sinon posé sur un point au sol. Lancement : ForceField de protection,
-- origine puis vitesse posées en attributs (lues par MovementController, ou BotMotion pour un bot) ; renvoie la vitesse
-- du lancement (nil pour une apparition au sol).
function SpawnManager.place(char: Model): Vector3?
	local launch = pickPoint("SunLaunch")
	local ground = if launch then nil else pickPoint("GroundSpawns")
	if not launch and not ground then
		warn("[SpawnManager] aucun point dans Maps.Map.SunLaunch ni Maps.Map.GroundSpawns")
	end
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	-- Délai de grâce : un bot ne tire pas sur un participant qui vient d'apparaître (#143)
	char:SetAttribute(BotCombatRules.SPAWNED_AT_ATTRIBUTE, os.clock())
	if launch then
		local origin = launch.Position
		local speed = launch:GetAttribute("Speed")
		local velocity = SpawnLaunch.velocity(launch.CFrame.LookVector, if type(speed) == "number" then speed else 0)
		protect(char)
		if root then
			root.CFrame = CFrame.new(origin)
		end
		-- Origine d'abord : le client applique le lancement quand la vitesse arrive (MovementController)
		char:SetAttribute(SpawnLaunch.ORIGIN_ATTRIBUTE, origin)
		char:SetAttribute(SpawnLaunch.VELOCITY_ATTRIBUTE, velocity)
		return velocity
	elseif root then
		root.CFrame = CFrame.new((if ground then ground.Position else Vector3.new(0, 5, 0)) + Vector3.new(0, 5, 0))
	end
	return nil
end

function SpawnManager.spawnPlayer(player: Player)
	-- Connexion avant LoadCharacter pour ne pas manquer CharacterAdded
	local conn: RBXScriptConnection
	conn = player.CharacterAdded:Connect(function(char)
		conn:Disconnect()
		CharacterAppearance.apply(char)
		SpawnManager.place(char)
	end)
	-- Rig = StarterCharacter, skin appliqué dans CharacterAdded (#1).
	player:LoadCharacterAsync()
end

function SpawnManager.init(requestSpawnRemote: RemoteEvent, canSpawn: (Player) -> boolean)
	requestSpawnRemote.OnServerEvent:Connect(function(player)
		if canSpawn(player) then
			SpawnManager.spawnPlayer(player)
		end
	end)
end

return SpawnManager

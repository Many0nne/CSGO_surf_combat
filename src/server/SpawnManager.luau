local SpawnManager = {}

local groundSpawnsFolder: Folder?

local function getGroundSpawns(): Folder?
	if groundSpawnsFolder then return groundSpawnsFolder end
	local maps = workspace:WaitForChild("Maps", 10)
	if not maps then return nil end
	local map = maps:WaitForChild("Map", 10)
	if not map then return nil end
	groundSpawnsFolder = map:WaitForChild("GroundSpawns", 10) :: Folder?
	return groundSpawnsFolder
end

local function getSpawnCFrame(): CFrame
	local folder = getGroundSpawns()
	local points = folder and folder:GetChildren() or {}
	if #points == 0 then
		warn("[SpawnManager] aucun point de spawn trouvé dans Maps.Map.GroundSpawns")
		return CFrame.new(0, 10, 0)
	end
	local pt = points[math.random(1, #points)] :: BasePart
	return CFrame.new(pt.Position + Vector3.new(0, 5, 0))
end

-- Exposed so bots can reuse the same spawn points as players.
function SpawnManager.getRandomSpawnCFrame(): CFrame
	return getSpawnCFrame()
end

function SpawnManager.spawnPlayer(player: Player)
	local cf = getSpawnCFrame()
	-- Connexion avant LoadCharacter pour ne pas manquer CharacterAdded
	local conn: RBXScriptConnection
	conn = player.CharacterAdded:Connect(function(char)
		conn:Disconnect()
		local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root then
			root.CFrame = cf
		end
	end)
	player:LoadCharacter()
end

function SpawnManager.init(requestSpawnRemote: RemoteEvent, canSpawn: (Player) -> boolean)
	requestSpawnRemote.OnServerEvent:Connect(function(player)
		if canSpawn(player) then
			SpawnManager.spawnPlayer(player)
		end
	end)
end

return SpawnManager

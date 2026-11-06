-- Échelles de la map : volumes invisibles de Maps.Map.Ladders (LookVector = normale sortante), testés à chaque frame
-- par MovementController. Vitesses de grimpe : LadderRules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LadderRules = require(ReplicatedStorage.Shared.LadderRules)
local MapRules = require(ReplicatedStorage.Shared.MapRules)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local Config = require(ReplicatedStorage.Shared.MovementConfig)

local LadderSystem = {}

local ladders: { BasePart } = {}
local watching = false

-- Cette méthode permet d'enregistrer un volume d'échelle lorsqu'il apparaît dans le dossier de la map.
local function register(inst: Instance)
	if inst:IsA("BasePart") then
		table.insert(ladders, inst)
	end
end

-- Cette méthode permet de trouver les échelles de la map une seule fois lorsque le premier personnage apparaît
-- (la map peut arriver après le script client : attente en tâche de fond ; une map sans échelle n'a pas le dossier).
function LadderSystem.init()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		local map = MapSelection.waitForActive(30)
		local folder = map and map:WaitForChild(LadderRules.LADDERS_FOLDER, 30)
		if not folder then
			return
		end
		for _, child in folder:GetChildren() do
			register(child)
		end
		folder.ChildAdded:Connect(register)
	end)
end

-- Cette méthode permet de savoir si le joueur est sur une échelle lorsque le mouvement prépare sa frame : renvoie la
-- normale sortante de l'échelle (horizontale), ou nil.
function LadderSystem.find(pos: Vector3): Vector3?
	for _, part in ladders do
		if part.Parent and MapRules.contains(part.CFrame, part.Size, pos, Config.CHAR_RADIUS) then
			local look = part.CFrame.LookVector
			return Vector3.new(look.X, 0, look.Z).Unit
		end
	end
	return nil
end

return LadderSystem

-- Boosts de vitesse de la map (geysers, lanceurs, portiques) : volumes invisibles de Maps.Map.Boosts,
-- détectés à chaque frame par MovementController. Règles (contenance, vitesse, recharge) : MapRules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapRules = require(ReplicatedStorage.Shared.MapRules)
local Config = require(ReplicatedStorage.Shared.MovementConfig)

type Boost = { part: BasePart, kind: string, cooldown: number }

local BoostSystem = {}

local boosts: { Boost } = {}
local lastUse: { [BasePart]: number } = {}
local watching = false
local mapModel: Instance? = nil

-- Cette méthode permet d'enregistrer un volume de boost lorsqu'il apparaît dans le dossier de la map.
local function register(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local kind = inst:GetAttribute(MapRules.KIND_ATTRIBUTE)
	if type(kind) ~= "string" then
		return
	end
	local cooldown = inst:GetAttribute(MapRules.COOLDOWN_ATTRIBUTE)
	table.insert(boosts, {
		part = inst,
		kind = kind,
		cooldown = if type(cooldown) == "number" then cooldown else (MapRules.DEFAULT_COOLDOWN[kind] or 1),
	})
end

-- Cette méthode permet de trouver les boosts de la map une seule fois lorsque le premier personnage apparaît
-- (la map peut arriver après le script client : attente en tâche de fond).
function BoostSystem.init()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		local maps = workspace:WaitForChild("Maps", 30)
		local map = maps and maps:WaitForChild("Map", 30)
		mapModel = map
		local folder = map and map:WaitForChild(MapRules.BOOSTS_FOLDER, 30)
		if not folder then
			return
		end
		for _, child in folder:GetChildren() do
			register(child)
		end
		folder.ChildAdded:Connect(register)
	end)
end

-- Cette méthode permet de déclencher le boost dans lequel se trouve le joueur lorsqu'il n'est pas en recharge :
-- renvoie la nouvelle vitesse et le type de boost, ou nil.
function BoostSystem.check(pos: Vector3, velocity: Vector3, now: number): (Vector3?, string?)
	for _, b in boosts do
		local part = b.part
		if part.Parent and MapRules.contains(part.CFrame, part.Size, pos, Config.CHAR_RADIUS) then
			if now - (lastUse[part] or -math.huge) >= b.cooldown then
				local newVelocity = MapRules.velocityAfter(
					b.kind,
					velocity,
					part:GetAttribute(MapRules.VELOCITY_ATTRIBUTE),
					part:GetAttribute(MapRules.BOOST_ATTRIBUTE),
					part.CFrame.LookVector,
					Config.MAX_SPEED_SERVER
				)
				if newVelocity then
					lastUse[part] = now
					return newVelocity, b.kind
				end
			end
		end
	end
	return nil, nil
end

-- Cette méthode permet de lire la hauteur de mort de la map (attribut KillHeight) lorsque le mouvement vérifie
-- une chute hors de l'île ; nil tant que la map n'est pas trouvée ou si elle n'en déclare pas.
function BoostSystem.killHeight(): any
	return mapModel and mapModel:GetAttribute(MapRules.KILL_HEIGHT_ATTRIBUTE)
end

return BoostSystem

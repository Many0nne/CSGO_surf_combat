-- Mort par chute : la map est une île au-dessus du vide. Le serveur tue le joueur dont la position validée
-- (CharacterSync, #75) passe sous Maps.Map.KillHeight ou entre dans un volume de Maps.Map.KillVolumes (la mer de
-- Radoub, #593) (mort sans tueur, comptée via Humanoid.Died), ou qui tombe dans le vide sans plus envoyer de position
-- (CharacterSync, règle du vide #177).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapRules = require(ReplicatedStorage.Shared.MapRules)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)

local KillZone = {}

local mapModel: Instance? = nil
local volumes: { { cf: CFrame, size: Vector3 } } = {}

-- Cette méthode permet de retrouver la map jouée en arrière-plan lorsque le serveur démarre, pour lire sa hauteur
-- de mort ensuite sans attendre, et de relever une fois ses volumes de mort (ancrés, la map est statique).
function KillZone.init()
	task.spawn(function()
		mapModel = MapSelection.waitForActive(30)
		local folder = mapModel and mapModel:FindFirstChild(MapRules.KILL_VOLUMES_FOLDER)
		for _, part in if folder then folder:GetDescendants() else {} do
			if part:IsA("BasePart") then
				table.insert(volumes, { cf = part.CFrame, size = part.Size })
			end
		end
	end)
end

-- Cette méthode permet de lire la hauteur de mort de la map jouée lorsqu'une règle la compare à une position ; nil tant
-- que la map n'est pas trouvée ou si elle n'en déclare pas.
function KillZone.height(): number?
	local killHeight = mapModel and mapModel:GetAttribute(MapRules.KILL_HEIGHT_ATTRIBUTE)
	return if type(killHeight) == "number" then killHeight else nil
end

-- Cette méthode permet de tuer un personnage vivant lorsqu'il est tombé de l'île ; Health = 0 passe outre la
-- protection d'apparition (ForceField), voulu : on ne survit pas au vide.
function KillZone.kill(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = 0
	end
end

-- Cette méthode permet de tuer un personnage vivant lorsque sa position validée passe sous la hauteur de mort ou
-- entre dans un volume de mort.
function KillZone.check(char: Model, position: Vector3)
	if MapRules.isBelowKillHeight(position.Y, KillZone.height()) or MapRules.isInKillVolume(volumes, position) then
		KillZone.kill(char)
	end
end

return KillZone

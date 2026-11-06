-- Mort par chute : la map est une île au-dessus du vide. Le serveur tue le joueur dont la position validée
-- (CharacterSync, #75) passe sous Maps.Map.KillHeight (mort sans tueur, comptée via Humanoid.Died).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapRules = require(ReplicatedStorage.Shared.MapRules)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)

local KillZone = {}

local mapModel: Instance? = nil

-- Cette méthode permet de retrouver la map jouée en arrière-plan lorsque le serveur démarre, pour lire sa hauteur
-- de mort ensuite sans attendre.
function KillZone.init()
	task.spawn(function()
		mapModel = MapSelection.waitForActive(30)
	end)
end

-- Cette méthode permet de tuer un personnage vivant lorsque sa position validée passe sous la hauteur de mort ;
-- Health = 0 passe outre la protection d'apparition (ForceField), voulu : on ne survit pas au vide.
function KillZone.check(char: Model, position: Vector3)
	local killHeight = mapModel and mapModel:GetAttribute(MapRules.KILL_HEIGHT_ATTRIBUTE)
	if not MapRules.isBelowKillHeight(position.Y, killHeight) then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = 0
	end
end

return KillZone

-- Personnage de décor des scènes du menu (accueil MenuScene, démonstration des effets EffectStage #575) : clone du
-- StarterCharacter sans script ni physique, racine ancrée, debout sur un sol donné.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAppearance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterAppearance"))

local SceneFigure = {}

-- Cette méthode permet de créer un personnage du jeu (StarterCharacter, tenue `outfitId`, nil : d'origine) sans script ni
-- physique, debout sur `ground` et tourné vers `facing`, lorsqu'une scène du menu se construit ; nil si la place n'a pas
-- de StarterCharacter.
function SceneFigure.build(ground: Vector3, facing: Vector3, parent: Instance, name: string, outfitId: string?): Model?
	local template = CharacterAppearance.getTemplate()
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = name
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	CharacterAppearance.apply(model, outfitId)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.EvaluateStateMachine = false
	root.Anchored = true
	local center = ground + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	model:PivotTo(CFrame.lookAt(center, center + facing))
	model.Parent = parent
	return model
end

return SceneFigure

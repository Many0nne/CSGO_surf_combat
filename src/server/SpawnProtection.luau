-- Protection d'apparition (#288) : ForceField visible posé sur tout personnage qui apparaît (joueur ou bot), retiré au
-- bout de GameConfig.SPAWN_PROTECTION ou dès son premier tir accepté par le serveur. Humanoid:TakeDamage l'ignore
-- (cf. Validator.hitOutcome) ; une touche reçue sous protection désigne le tueur sans instant (RoundManager, #217).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local SpawnProtection = {}

-- Nom du ForceField de protection : seul celui-ci est retiré au premier tir
SpawnProtection.NAME = "SpawnProtection"

-- Cette méthode permet de protéger un personnage lorsqu'il apparaît : ForceField visible des autres joueurs, détruit
-- au bout de SPAWN_PROTECTION secondes.
function SpawnProtection.protect(char: Model)
	local field = Instance.new("ForceField")
	field.Name = SpawnProtection.NAME
	field.Visible = true
	field.Parent = char
	task.delay(GameConfig.SPAWN_PROTECTION, function()
		field:Destroy()
	end)
end

-- Cette méthode permet de retirer la protection d'un personnage lorsqu'il tire (tir accepté par le serveur) ; renvoie
-- true si une protection était encore là.
function SpawnProtection.drop(char: Instance?): boolean
	if not char then
		return false
	end
	local dropped = false
	for _, child in char:GetChildren() do
		if child.Name == SpawnProtection.NAME then
			child:Destroy()
			dropped = true
		end
	end
	return dropped
end

return SpawnProtection

-- head_hitbox_probe.luau (#539)
-- Mesure, dans Studio en playtest (contexte Server, via execute_luau), ce que touche un tir à la hauteur de la tête d'un
-- personnage du jeu : copie du StarterCharacter habillée comme en jeu (CharacterAppearance.apply), posée loin de la map,
-- puis rayons tirés de face et de profil, horizontalement et verticalement, tous les 0,1 stud depuis l'axe de la tête.
-- Affiche une ligne par série : décalage → pièce touchée (H = Head, R = HumanoidRootPart, - = rien, autre = initiale).
-- Repère : la tête affichée fait 1,91 (largeur) × 1,93 (hauteur) × 1,91 stud (mesuré le 18/11/2026, tête de 1,25).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)

local rig = (CharacterAppearance.getTemplate() :: Model):Clone()
for _, d in rig:GetDescendants() do
	if d:IsA("BaseScript") then
		d:Destroy()
	end
end
local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
root.Anchored = true
rig:PivotTo(CFrame.new(0, 2000, 0))
rig.Parent = workspace
CharacterAppearance.apply(rig)

local head = rig:FindFirstChild("Head") :: BasePart
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { rig }

-- Cette méthode permet de tirer une série de rayons parallèles lorsqu'on balaie un axe de la tête : origine décalée de
-- 0,1 stud × i le long de `side`, direction `dir` ; renvoie la ligne de résultats.
local function sweep(label: string, from: Vector3, dir: Vector3, side: Vector3): string
	local cells = {}
	for i = 0, 16 do
		local hit = workspace:Raycast(from + side * (i / 10), dir, params)
		local name = hit and hit.Instance.Name or nil
		local mark = if name == nil
			then "-"
			elseif name == "Head" then "H"
			elseif name == "HumanoidRootPart" then "R"
			else string.sub(name, 1, 1)
		table.insert(cells, string.format("%.1f:%s", i / 10, mark))
	end
	return label .. "  " .. table.concat(cells, " ")
end

local c = head.Position
local out = {
	string.format(
		"[HeadProbe] Head %s, mesh %s",
		tostring(head.Size),
		tostring(head:FindFirstChildOfClass("SpecialMesh") and head:FindFirstChildOfClass("SpecialMesh").Scale)
	),
	sweep("[HeadProbe] face, vers la droite ", c + Vector3.new(0, 0, -20), Vector3.new(0, 0, 40), Vector3.new(1, 0, 0)),
	sweep("[HeadProbe] face, vers le haut   ", c + Vector3.new(0, 0, -20), Vector3.new(0, 0, 40), Vector3.new(0, 1, 0)),
	sweep(
		"[HeadProbe] profil, vers l'avant ",
		c + Vector3.new(20, 0, 0),
		Vector3.new(-40, 0, 0),
		Vector3.new(0, 0, -1)
	),
	sweep(
		"[HeadProbe] face, vers le bas    ",
		c + Vector3.new(0, 0, -20),
		Vector3.new(0, 0, 40),
		Vector3.new(0, -1, 0)
	),
}
rig:Destroy()
print(table.concat(out, "\n"))

-- HeadHitbox.luau
-- Hitbox de la tête (#539). La tête du rig est une pièce à SpecialMesh de type Head : le raycast d'un tir touche la boîte
-- de la pièce, pas le mesh affiché. Sur le StarterCharacter, la boîte (3,18 × 1,59 × 1,59) débordait la tête visible
-- sur les côtés (headshot dans le vide jusqu'à 1,5 stud de l'axe) et ne couvrait pas le haut, l'avant ni l'arrière.
-- À l'apparition, `fit` donne à la pièce la taille de la tête affichée, et compense l'échelle du mesh pour que
-- l'affichage ne change pas : un mesh Head est mis à l'échelle de la plus petite dimension de sa pièce, uniformément
-- (vérifié dans Studio le 18/11/2026).

local HeadHitbox = {}

-- Taille (cube, studs) de la tête affichée par le StarterCharacter : 1,91 × 1,93 × 1,91 mesuré dans Studio le 18/11/2026
-- (pièce de 1,588, SpecialMesh d'échelle 1,25)
HeadHitbox.SIZE = 1.92
-- Attribut posé sur la tête ajustée : un second appel (réapparition, copie d'un personnage déjà ajusté) n'y touche plus
HeadHitbox.FITTED_ATTRIBUTE = "HeadHitboxFitted"

-- Cette méthode permet de calculer la taille de pièce et l'échelle de mesh qui gardent la tête affichée telle quelle
-- lorsque la boîte passe au cube `side` : la tête affichée vaut (plus petite dimension de la pièce) × échelle.
function HeadHitbox.fitted(size: Vector3, scale: Vector3, side: number): (Vector3, Vector3)
	local shown = math.min(size.X, size.Y, size.Z)
	return Vector3.new(side, side, side), scale * (shown / side)
end

-- Cette méthode permet d'ajuster la hitbox de la tête d'un personnage lorsqu'il est préparé (skin commun) ; sans effet
-- sur une tête sans SpecialMesh de type Head (MeshPart, rig généré d'une autre forme) ou déjà ajustée.
function HeadHitbox.fit(model: Model)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) or head:GetAttribute(HeadHitbox.FITTED_ATTRIBUTE) then
		return
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if not mesh or mesh.MeshType ~= Enum.MeshType.Head then
		return
	end
	local size, scale = HeadHitbox.fitted(head.Size, mesh.Scale, HeadHitbox.SIZE)
	head.Size = size
	mesh.Scale = scale
	head:SetAttribute(HeadHitbox.FITTED_ATTRIBUTE, true)
end

return HeadHitbox

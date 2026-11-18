-- OutfitMaps.luau
-- Correspondances partagées entre les cartes cuites d'une tenue de personnage (#521) et ses SurfaceAppearance : atlas
-- (groupe de tools/outfits/r15_bake.py, clé de ids.json) d'une pièce du rig, et propriété de chaque carte. Utilisé par
-- tools/outfits/make_rbxm.luau (pose les ids) et tools/rbxm/verify_place.luau (les compare à ids.json).

local OutfitMaps = {}

-- Propriété d'une SurfaceAppearance -> nom de la carte dans ids.json (tools/skins/publish_skin.py)
OutfitMaps.KINDS = {
	ColorMapContent = "Color",
	NormalMapContent = "Normal",
	MetalnessMapContent = "Metal",
	RoughnessMapContent = "Rough",
}

-- Pièce du rig -> atlas (groupe de r15_bake.PARTS)
local GROUPS = {
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	LeftUpperArm = "LeftArm",
	LeftLowerArm = "LeftArm",
	LeftHand = "LeftArm",
	RightUpperArm = "RightArm",
	RightLowerArm = "RightArm",
	RightHand = "RightArm",
	LeftUpperLeg = "LeftLeg",
	LeftLowerLeg = "LeftLeg",
	LeftFoot = "LeftLeg",
	RightUpperLeg = "RightLeg",
	RightLowerLeg = "RightLeg",
	RightFoot = "RightLeg",
}

-- Cette méthode permet de donner l'atlas (groupe de r15_bake) d'une pièce du rig lorsqu'on pose ou vérifie ses cartes ;
-- nil pour un nom qui n'est pas une pièce du rig.
function OutfitMaps.groupOf(part: string): string?
	return GROUPS[part]
end

return OutfitMaps

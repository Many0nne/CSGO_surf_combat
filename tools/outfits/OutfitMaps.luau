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

-- Cette méthode permet de donner l'atlas (groupe de r15_bake) d'une pièce du rig lorsqu'on pose ou vérifie ses cartes.
function OutfitMaps.groupOf(part: string): string
	if string.find(part, "Torso") then
		return "Torso"
	end
	local side = if string.sub(part, 1, 4) == "Left" then "Left" else "Right"
	local limb = if string.find(part, "Arm") or string.find(part, "Hand") then "Arm" else "Leg"
	return side .. limb
end

return OutfitMaps

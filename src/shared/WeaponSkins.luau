-- Rendu des skins d'arme (#268) : pose sur les pièces d'une arme clonée (viewmodel 1re personne, modèle 3P, accueil,
-- vignettes de l'écran d'équipement) les SurfaceAppearance de son skin, ou celles d'origine du viewmodel.
--
-- Les SurfaceAppearance d'un skin sont toutes faites dans ReplicatedStorage.Skins.<viewmodel>.<appearance> (une par
-- pièce, nommée comme elle ; fichiers assets/rbx/Skins/<viewmodel>/<appearance>.model.json écrits par
-- tools/skins/make_rbx.py) : un script de jeu ne peut pas écrire les cartes d'une SurfaceAppearance, il ne peut que
-- copier une SurfaceAppearance existante. Le nom `appearance` vient du catalogue (InventoryRules.ITEMS).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)

local WeaponSkins = {}

-- Attribut posé sur le modèle habillé : id du skin posé ("" : d'origine), pour ne pas refaire un habillage identique
WeaponSkins.ATTRIBUTE = "SkinId"

-- Cette méthode permet de trouver le dossier des SurfaceAppearance d'un skin pour un viewmodel lorsqu'une arme est
-- habillée ; nil pour le skin d'origine, un id inconnu ou un skin sans dossier (asset pas encore synchronisé).
function WeaponSkins.folder(viewmodelName: string, skinId: string?): Instance?
	local item = skinId and InventoryRules.item(skinId)
	if not (item and item.type == InventoryRules.Type.SKIN and item.appearance) then
		return nil
	end
	local skins = ReplicatedStorage:FindFirstChild("Skins")
	local byWeapon = skins and skins:FindFirstChild(viewmodelName)
	return byWeapon and byWeapon:FindFirstChild(item.appearance)
end

-- Cette méthode permet d'habiller les pièces d'une arme clonée (enfants directs de `model` nommés comme les pièces du
-- viewmodel) lorsqu'elle est construite ou que le skin équipé change : SurfaceAppearance du skin pour chaque pièce
-- qu'il couvre, celle d'origine du viewmodel pour les autres (et pour tout le skin d'origine). Renvoie le nombre de
-- pièces habillées.
function WeaponSkins.apply(model: Instance, viewmodelName: string, skinId: string?): number
	local container = ReplicatedStorage:FindFirstChild("ViewModels")
	local template = container and container:FindFirstChild(viewmodelName)
	if not template then
		return 0
	end
	local folder = WeaponSkins.folder(viewmodelName, skinId)
	local count = 0
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local source = folder and folder:FindFirstChild(part.Name)
		if not (source and source:IsA("SurfaceAppearance")) then
			local original = template:FindFirstChild(part.Name)
			source = original and original:FindFirstChildOfClass("SurfaceAppearance")
		end
		if source then
			for _, child in part:GetChildren() do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			source:Clone().Parent = part
			count += 1
		end
	end
	model:SetAttribute(WeaponSkins.ATTRIBUTE, if folder then skinId else "")
	return count
end

-- Cartes d'une SurfaceAppearance, lues pour les précharger (#333)
local MAP_PROPERTIES = { "ColorMapContent", "MetalnessMapContent", "NormalMapContent", "RoughnessMapContent" }

-- Cette méthode permet de lister sans doublon les ids des cartes d'un dossier de skin (WeaponSkins.folder) lorsqu'on
-- veut les précharger ; une pièce peut réutiliser les cartes d'une autre, une carte vide est ignorée.
function WeaponSkins.mapUris(folder: Instance): { string }
	local uris: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, appearance in folder:GetChildren() do
		if not appearance:IsA("SurfaceAppearance") then
			continue
		end
		for _, property in MAP_PROPERTIES do
			local content = (appearance :: any)[property]
			local uri = content and content.Uri
			if type(uri) == "string" and uri ~= "" and not seen[uri] then
				seen[uri] = true
				table.insert(uris, uri)
			end
		end
	end
	return uris
end

-- Cette méthode permet de savoir si un modèle porte déjà ce skin (nil ou "" : d'origine) lorsqu'on veut éviter de
-- l'habiller à nouveau.
function WeaponSkins.isApplied(model: Instance, viewmodelName: string, skinId: string?): boolean
	local wanted = if WeaponSkins.folder(viewmodelName, skinId) then skinId else ""
	return model:GetAttribute(WeaponSkins.ATTRIBUTE) == wanted
end

return WeaponSkins

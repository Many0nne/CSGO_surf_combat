-- Pose de profil d'une arme (#429) : repère commun aux rendus qui montrent une arme à plat, vignettes et cartes
-- (UIKit.weaponSilhouette) comme aperçu et révélation du shop (ShopScene). Repère rendu : X vers la pointe (à droite
-- de l'image), Y vers le haut de l'arme, Z vers celui qui regarde (face montrée). Avant, chaque rendu orientait l'arme
-- par les axes de sa boîte sans fixer le sens : l'aperçu tournait l'arme de 180° par rapport à la vignette (M9 pointe
-- à droite en vignette, à gauche en aperçu ; AWP l'inverse), mesuré dans Studio.
local WeaponProfile = {}

-- Référence par viewmodel : pièce dont les axes suivent ceux de l'arme, et, dans le repère de cette pièce, direction
-- de la pointe (ou de la bouche) et du haut (lunette, dos de lame). Vecteurs d'axe unitaires, perpendiculaires.
-- Choix de l'utilisateur (#429) : pointe à droite partout. Le M9 garde la face de ses vignettes d'avant ; l'AWP garde
-- celle de l'aperçu (marquages des skins lisibles), ses vignettes ont changé de flanc. Une arme montrée par le shop
-- doit avoir sa référence : sans elle, le sens dépend des axes de la première pièce clonée.
export type Reference = { part: string, tip: Vector3, up: Vector3 }
WeaponProfile.REFERENCES = {
	AWP = { part = "Barrel", tip = Vector3.new(1, 0, 0), up = Vector3.new(0, 1, 0) },
	M9Bayonet = { part = "Handle", tip = Vector3.new(0, 0, 1), up = Vector3.new(1, 0, 0) },
} :: { [string]: Reference }

-- Cette méthode permet de donner le repère de profil (centre de la boîte) et l'étendue de l'arme le long de ses axes
-- (X longueur, Y hauteur, Z épaisseur) lorsqu'un rendu pose une arme de boîte `box`, `size` ; avec `reference`, la boîte
-- doit suivre les axes de la pièce de référence. Sans référence : axe le plus long en X, moyen en Y, plus mince en Z,
-- sens de X fixé par Y × Z (repère direct), ce que montraient les vignettes avant #429.
function WeaponProfile.frame(box: CFrame, size: Vector3, reference: Reference?): (CFrame, Vector3)
	if reference then
		local face = reference.tip:Cross(reference.up)
		local extents =
			Vector3.new(math.abs(reference.tip:Dot(size)), math.abs(reference.up:Dot(size)), math.abs(face:Dot(size)))
		local tip = box:VectorToWorldSpace(reference.tip)
		local up = box:VectorToWorldSpace(reference.up)
		return CFrame.fromMatrix(box.Position, tip, up, tip:Cross(up)), extents
	end
	local axes = {
		{ length = size.X, dir = box.RightVector },
		{ length = size.Y, dir = box.UpVector },
		{ length = size.Z, dir = box.LookVector },
	}
	table.sort(axes, function(a, b)
		return a.length > b.length
	end)
	local up, face = axes[2].dir, axes[3].dir
	return CFrame.fromMatrix(box.Position, up:Cross(face), up, face),
		Vector3.new(axes[1].length, axes[2].length, axes[3].length)
end

-- Cette méthode permet de mesurer une arme reconstruite (pièces du viewmodel `viewmodelName` dans `model`) et de
-- donner son repère de profil, sa boîte et son étendue lorsqu'un rendu la pose ; la boîte suit la pièce de référence
-- de l'arme (PrimaryPart prêtée le temps de la mesure), sinon les axes que Roblox lui donne.
function WeaponProfile.of(model: Model, viewmodelName: string): (CFrame, CFrame, Vector3)
	local reference = WeaponProfile.REFERENCES[viewmodelName]
	local part = reference and model:FindFirstChild(reference.part)
	local measured = if part and part:IsA("BasePart") then reference else nil
	if measured then
		model.PrimaryPart = part :: BasePart
	end
	local box, size = model:GetBoundingBox()
	if measured then
		model.PrimaryPart = nil
	end
	local profile, extents = WeaponProfile.frame(box, size, measured)
	return profile, box, extents
end

return WeaponProfile

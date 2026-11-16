-- Place du pochoir sur le couvercle de la caisse du shop (#434, #456) : source unique des cotes, lue par ShopScene (pose),
-- par tools/shop/crate_model.py (le générateur refuse une caisse dont une pièce masquerait le texte, il relit les lignes
-- `AT`/`SIZE`/`INK_HEIGHT` ci-dessous : garder ce format) et par tools/rbxm/verify_place.luau (boîtes des pièces de
-- Crate.rbxm). Module sans dépendance ni type Roblox (chargé tel quel par Lune). Repère : pivot de la caisse (centre du
-- dessous), x vers la droite, y en haut, z vers l'avant ; en studs, pour la caisse de 4 studs de large.
local CrateStencil = {}

export type Vec = { number }
export type Box = { min: Vec, max: Vec }

-- Centre de la pièce invisible « LidStencil », à droite de la bande sur la face avant ; remonté de 0,046 stud depuis la
-- place de l'ancien pochoir modelé : le moraillon du couvercle (LidSteel, haut à 1,64) cachait le bas des lettres
CrateStencil.AT = { 1.0, 1.72, 1.208 }
-- Zone libre entre la bande et la cornière d'acier du couvercle ; épaisseur 0,01 (la SurfaceGui est sur la face avant)
CrateStencil.SIZE = { 1.16, 0.3, 0.01 }
-- Hauteur des capitales peintes (Oswald à 52 px pour 200 px par stud, mesurée dans Studio), centrées sur AT
CrateStencil.INK_HEIGHT = 0.136
-- Écart maximal entre le dos de la pièce et la face des planches : au-delà, le texte flotte devant le bois
CrateStencil.MAX_GAP = 0.03

-- Cette méthode permet d'obtenir le rectangle peint (x et y, en studs) et la face arrière de la pièce du pochoir lorsque
-- le générateur ou la vérification de la place le comparent aux pièces de la caisse.
function CrateStencil.inkRect(): (Box, number)
	local at, size = CrateStencil.AT, CrateStencil.SIZE
	local rect = {
		min = { at[1] - size[1] / 2, at[2] - CrateStencil.INK_HEIGHT / 2 },
		max = { at[1] + size[1] / 2, at[2] + CrateStencil.INK_HEIGHT / 2 },
	}
	return rect, at[3] - size[3] / 2
end

-- Cette méthode permet de lister ce qui cloche entre le pochoir et les boîtes englobantes des pièces de la caisse
-- (`boxes` : nom → {min, max} dans le repère du pivot) lorsque verify_place relit Crate.rbxm ; liste vide si tout va.
function CrateStencil.problems(boxes: { [string]: Box }): { string }
	local found = {}
	local rect, back = CrateStencil.inkRect()
	local planks = boxes.LidPlanks
	if not planks then
		table.insert(found, "LidPlanks absent : pas de face où peindre le pochoir")
	else
		local face = planks.max[3]
		if back < face - 0.001 then
			table.insert(
				found,
				string.format("pochoir enfoncé dans le bois (dos %.3f, face des planches %.3f)", back, face)
			)
		elseif back > face + CrateStencil.MAX_GAP then
			table.insert(
				found,
				string.format("pochoir flottant devant le bois (dos %.3f, face des planches %.3f)", back, face)
			)
		end
		for axis = 1, 2 do
			if rect.min[axis] < planks.min[axis] or rect.max[axis] > planks.max[axis] then
				table.insert(
					found,
					"pochoir hors du couvercle (LidPlanks) sur l'axe " .. (if axis == 1 then "x" else "y")
				)
			end
		end
	end
	local stripe = boxes.LidStripe
	if stripe and rect.min[1] < stripe.max[1] then
		table.insert(
			found,
			string.format("pochoir sous la bande (bord gauche %.3f, bande jusqu'à %.3f)", rect.min[1], stripe.max[1])
		)
	end
	return found
end

return CrateStencil

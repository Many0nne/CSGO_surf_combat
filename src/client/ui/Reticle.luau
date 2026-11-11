-- Tracé commun des quatre branches d'un réticule (#222), utilisé par le crosshair de la visée simplifiée (Crosshair) et le
-- réticule de la lunette (ScopeOverlay). Chaque branche part de `gap` px du centre du parent ; le contour est une couche
-- sombre dessous, plus épaisse de `outline.width` px de chaque côté, et aussi plus longue si `outline.caps` (bouts fermés).
-- `dot` ajoute un point central carré de `thickness` px (viseur personnalisé, #251), contour compris.
-- Pas de CanvasGroup (cf. docs/ui.md) : de simples Frame.
local UIKit = require(script.Parent.UIKit)

local Reticle = {}

export type Outline = {
	color: Color3,
	width: number, -- px ajoutés de chaque côté du trait
	transparency: number?,
	caps: boolean?, -- le contour ferme aussi les deux bouts de la branche (crosshair) ; sinon seulement les côtés (lunette)
}

export type Spec = {
	length: UDim, -- longueur d'une branche : px fixes, ou part du parent (lunette : jusqu'au bord du cercle)
	thickness: number, -- px
	gap: number, -- px entre le centre et le début de chaque branche
	color: Color3,
	transparency: number?,
	outline: Outline?,
	fade: NumberSequence?, -- estompe le long de la branche, de l'extérieur (0) vers le centre (1)
	dot: boolean?, -- point central carré, de la couleur et de l'épaisseur des branches
}

-- `rotation` oriente l'estompe (fin du dégradé) vers le centre ; `sign` : côté du centre où part la branche.
local ARMS = {
	{ name = "Left", anchor = Vector2.new(1, 0.5), horizontal = true, sign = -1, rotation = 0 },
	{ name = "Right", anchor = Vector2.new(0, 0.5), horizontal = true, sign = 1, rotation = 180 },
	{ name = "Top", anchor = Vector2.new(0.5, 1), horizontal = false, sign = -1, rotation = 90 },
	{ name = "Bottom", anchor = Vector2.new(0.5, 0), horizontal = false, sign = 1, rotation = 270 },
}

-- Cette méthode permet de tracer une couche (trait ou contour) des quatre branches lorsque le réticule est construit ;
-- `grow` élargit chaque branche de part et d'autre, `growLength` l'allonge aussi aux deux bouts.
local function drawLayer(
	parent: GuiObject,
	spec: Spec,
	suffix: string,
	color: Color3,
	transparency: number,
	grow: number,
	growLength: number,
	zIndex: number
)
	local thick = spec.thickness + grow * 2
	local length = UDim.new(spec.length.Scale, spec.length.Offset + growLength * 2)
	local offset = spec.gap - growLength
	for _, arm in ARMS do
		local layer = UIKit.frame({
			Name = arm.name .. suffix,
			AnchorPoint = arm.anchor,
			Position = if arm.horizontal
				then UDim2.new(0.5, arm.sign * offset, 0.5, 0)
				else UDim2.new(0.5, 0, 0.5, arm.sign * offset),
			Size = if arm.horizontal
				then UDim2.new(length.Scale, length.Offset, 0, thick)
				else UDim2.new(0, thick, length.Scale, length.Offset),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = zIndex,
			Parent = parent,
		})
		if spec.fade then
			UIKit.create("UIGradient", { Rotation = arm.rotation, Transparency = spec.fade, Parent = layer })
		end
	end
end

-- Cette méthode permet de tracer le point central (carré de `size` px centré sur le parent) lorsque le réticule en a un.
local function drawDot(
	parent: GuiObject,
	name: string,
	size: number,
	color: Color3,
	transparency: number,
	zIndex: number
)
	UIKit.frame({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		ZIndex = zIndex,
		Parent = parent,
	})
end

-- Cette méthode permet de tracer les quatre branches d'un réticule (contour dessous, ZIndex 1, puis trait, ZIndex 2)
-- centrées sur `parent` lorsqu'un réticule est construit, avec le point central si `spec.dot`.
function Reticle.drawArms(parent: GuiObject, spec: Spec)
	local outline = spec.outline
	if outline then
		local growLength = if outline.caps then outline.width else 0
		local outlineTransparency = outline.transparency or 0
		drawLayer(parent, spec, "Outline", outline.color, outlineTransparency, outline.width, growLength, 1)
		if spec.dot then
			local size = spec.thickness + outline.width * 2
			drawDot(parent, "DotOutline", size, outline.color, outlineTransparency, 1)
		end
	end
	drawLayer(parent, spec, "", spec.color, spec.transparency or 0, 0, 0, 2)
	if spec.dot then
		drawDot(parent, "Dot", spec.thickness, spec.color, spec.transparency or 0, 2)
	end
end

return Reticle

-- Tracé commun des quatre branches d'un réticule (#222), utilisé par le crosshair de la visée simplifiée (Crosshair) et le
-- réticule de la lunette (ScopeOverlay). Chaque branche part de `gap` px du centre du parent ; le contour déborde de
-- `outline.width` px de chaque côté : couche sombre dessous (lunette, bouts ouverts), ou cadre autour du trait qui ferme
-- aussi les bouts si `outline.caps` (crosshair : rien sous le trait, son opacité reste juste, #251). `dot` ajoute un point
-- central carré de `thickness` px (viseur personnalisé, #251), contour compris.
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

-- Cette méthode permet de tracer une couche (trait ou contour posé dessous) des quatre branches lorsque le réticule est
-- construit ; `grow` élargit chaque branche de part et d'autre.
local function drawLayer(
	parent: GuiObject,
	spec: Spec,
	suffix: string,
	color: Color3,
	transparency: number,
	grow: number,
	zIndex: number
)
	local thick = spec.thickness + grow * 2
	local length = spec.length
	local offset = spec.gap
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

-- Cette méthode permet de poser une bande d'une branche, repérée le long de la branche (`start` px depuis le centre,
-- longueur `along`) et en travers (`across` px de l'axe, côté donné par `acrossAnchor`), lorsque le contour est cadré.
local function drawPiece(
	parent: GuiObject,
	arm: typeof(ARMS[1]),
	name: string,
	start: number,
	along: UDim,
	across: number,
	acrossAnchor: number,
	acrossSize: number,
	color: Color3,
	transparency: number
)
	local alongAnchor = if arm.sign > 0 then 0 else 1
	UIKit.frame({
		Name = name,
		AnchorPoint = if arm.horizontal
			then Vector2.new(alongAnchor, acrossAnchor)
			else Vector2.new(acrossAnchor, alongAnchor),
		Position = if arm.horizontal
			then UDim2.new(0.5, arm.sign * start, 0.5, across)
			else UDim2.new(0.5, across, 0.5, arm.sign * start),
		Size = if arm.horizontal
			then UDim2.new(along.Scale, along.Offset, 0, acrossSize)
			else UDim2.new(0, acrossSize, along.Scale, along.Offset),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		ZIndex = 1,
		Parent = parent,
	})
end

-- Cette méthode permet de cadrer chaque branche d'un contour (deux bandes sur les côtés, deux bouts) sans rien poser sous
-- le trait lorsque le contour ferme les bouts (crosshair) : un trait translucide ne s'assombrit pas sur le contour.
local function drawFramedOutline(parent: GuiObject, spec: Spec, outline: Outline)
	local w, half = outline.width, spec.thickness / 2
	local color, transparency = outline.color, outline.transparency or 0
	local length = spec.length
	local framed = UDim.new(length.Scale, length.Offset + w * 2)
	for _, arm in ARMS do
		local name = arm.name .. "Outline"
		drawPiece(parent, arm, name .. "Side1", spec.gap - w, framed, -half, 1, w, color, transparency)
		drawPiece(parent, arm, name .. "Side2", spec.gap - w, framed, half, 0, w, color, transparency)
		drawPiece(
			parent,
			arm,
			name .. "Inner",
			spec.gap - w,
			UDim.new(0, w),
			0,
			0.5,
			spec.thickness,
			color,
			transparency
		)
		-- Bout extérieur : la longueur est en px (crosshair), seul cas où les bouts sont fermés
		local outer = spec.gap + length.Offset
		drawPiece(parent, arm, name .. "Outer", outer, UDim.new(0, w), 0, 0.5, spec.thickness, color, transparency)
	end
end

-- Cette méthode permet de tracer le point central (carré de `thickness` px), et son contour en cadre s'il y en a un,
-- lorsque le réticule a un point.
local function drawDot(parent: GuiObject, spec: Spec)
	local size = spec.thickness
	UIKit.frame({
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = spec.color,
		BackgroundTransparency = spec.transparency or 0,
		ZIndex = 2,
		Parent = parent,
	})
	local outline = spec.outline
	if not outline then
		return
	end
	local w, half = outline.width, size / 2
	-- Haut et bas sur toute la largeur du cadre, gauche et droite entre les deux
	for _, band in
		{
			{
				name = "Top",
				anchor = Vector2.new(0.5, 1),
				offset = Vector2.new(0, -half),
				size = Vector2.new(size + w * 2, w),
			},
			{
				name = "Bottom",
				anchor = Vector2.new(0.5, 0),
				offset = Vector2.new(0, half),
				size = Vector2.new(size + w * 2, w),
			},
			{
				name = "Left",
				anchor = Vector2.new(1, 0.5),
				offset = Vector2.new(-half, 0),
				size = Vector2.new(w, size),
			},
			{
				name = "Right",
				anchor = Vector2.new(0, 0.5),
				offset = Vector2.new(half, 0),
				size = Vector2.new(w, size),
			},
		}
	do
		UIKit.frame({
			Name = "DotOutline" .. band.name,
			AnchorPoint = band.anchor,
			Position = UDim2.new(0.5, band.offset.X, 0.5, band.offset.Y),
			Size = UDim2.fromOffset(band.size.X, band.size.Y),
			BackgroundColor3 = outline.color,
			BackgroundTransparency = outline.transparency or 0,
			ZIndex = 1,
			Parent = parent,
		})
	end
end

-- Cette méthode permet de tracer les quatre branches d'un réticule (contour, ZIndex 1, puis trait, ZIndex 2) centrées sur
-- `parent` lorsqu'un réticule est construit, avec le point central si `spec.dot`. Bouts fermés (`caps`) : contour en
-- cadre autour du trait ; sinon (lunette) couche plus large posée dessous, sur laquelle joue l'estompe.
function Reticle.drawArms(parent: GuiObject, spec: Spec)
	local outline = spec.outline
	if outline and outline.caps then
		drawFramedOutline(parent, spec, outline)
	elseif outline then
		drawLayer(parent, spec, "Outline", outline.color, outline.transparency or 0, outline.width, 1)
	end
	drawLayer(parent, spec, "", spec.color, spec.transparency or 0, 0, 2)
	if spec.dot then
		drawDot(parent, spec)
	end
end

return Reticle

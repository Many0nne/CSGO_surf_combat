-- Tracé commun des quatre branches d'un réticule (#222), utilisé par le crosshair de la visée simplifiée (Crosshair) et le
-- réticule de la lunette (ScopeOverlay). Chaque branche part de `gap` px du centre du parent ; le contour déborde de
-- `outline.width` px de chaque côté. Lunette : branches centrées, contour en couche sombre dessous, bouts ouverts.
-- Crosshair (`pixelAligned`, #251) : branches sur des px entiers, contour en cadre qui ferme aussi les bouts, rien sous le
-- trait (son opacité reste juste), point central `dot` en option.
-- Pas de CanvasGroup (cf. docs/ui.md) : de simples Frame.
local UIKit = require(script.Parent.UIKit)

local Reticle = {}

export type Outline = {
	color: Color3,
	width: number, -- px ajoutés de chaque côté du trait
	transparency: number?,
}

export type Spec = {
	length: UDim, -- longueur d'une branche : px fixes, ou part du parent (lunette : jusqu'au bord du cercle)
	thickness: number, -- px
	gap: number, -- px entre le centre et le début de chaque branche
	color: Color3,
	transparency: number?,
	outline: Outline?,
	fade: NumberSequence?, -- estompe le long de la branche, de l'extérieur (0) vers le centre (1)
	pixelAligned: boolean?, -- px entiers, contour en cadre bouts fermés (crosshair) ; longueur en px seulement
	dot: boolean?, -- point central carré, de la couleur et de l'épaisseur des branches (avec pixelAligned)
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

-- Bande d'une branche alignée sur les px : `start` px depuis le centre le long de la branche, sur `along` ; en travers,
-- bord `acrossAnchor` (0 : haut ou gauche, 1 : bas ou droite) posé à `across` px de l'axe, sur `acrossSize` px
type Band = {
	name: string,
	start: number,
	along: UDim,
	across: number,
	acrossAnchor: number,
	acrossSize: number,
	color: Color3,
	transparency: number,
	zIndex: number,
}

-- Cette méthode permet de poser une bande d'une branche (trait ou morceau du contour en cadre) lorsque le réticule est
-- aligné sur les px (crosshair).
local function drawBand(parent: GuiObject, arm: typeof(ARMS[1]), band: Band)
	local alongAnchor = if arm.sign > 0 then 0 else 1
	UIKit.frame({
		Name = band.name,
		AnchorPoint = if arm.horizontal
			then Vector2.new(alongAnchor, band.acrossAnchor)
			else Vector2.new(band.acrossAnchor, alongAnchor),
		Position = if arm.horizontal
			then UDim2.new(0.5, arm.sign * band.start, 0.5, band.across)
			else UDim2.new(0.5, band.across, 0.5, arm.sign * band.start),
		Size = if arm.horizontal
			then UDim2.new(band.along.Scale, band.along.Offset, 0, band.acrossSize)
			else UDim2.new(0, band.acrossSize, band.along.Scale, band.along.Offset),
		BackgroundColor3 = band.color,
		BackgroundTransparency = band.transparency,
		ZIndex = band.zIndex,
		Parent = parent,
	})
end

-- Cette méthode permet de poser un rectangle aligné sur les px, coin haut gauche à (`x`, `y`) px du centre, lorsque le
-- point central ou son contour est tracé.
local function drawRect(
	parent: GuiObject,
	name: string,
	x: number,
	y: number,
	size: Vector2,
	color: Color3,
	transparency: number,
	zIndex: number
)
	UIKit.frame({
		Name = name,
		Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		ZIndex = zIndex,
		Parent = parent,
	})
end

-- Cette méthode permet de tracer un réticule aligné sur les px entiers, contour en cadre autour de chaque trait, lorsque le
-- crosshair est construit (#251).
local function drawAligned(parent: GuiObject, spec: Spec)
	local t, length = spec.thickness, spec.length
	assert(length.Scale == 0, "Reticle : un réticule aligné sur les px a une longueur en px")
	-- Pas de demi-px, que Roblox arrondirait frame par frame (contour décollé ou mordant le trait) : une épaisseur impaire a
	-- un px de plus en bas ou à droite de l'axe, le centre est le milieu du px [0, 1], et les branches droite et basse
	-- partent d'un px plus loin pour garder le même écart des deux côtés. Rien sous le trait : un trait translucide ne
	-- s'assombrit pas sur le contour.
	local lo = -math.floor(t / 2) -- bord haut ou gauche du trait, en px depuis l'axe
	local hi = lo + t
	local color, transparency = spec.color, spec.transparency or 0
	local outline = spec.outline
	for _, arm in ARMS do
		local gap = spec.gap + (if arm.sign > 0 then t % 2 else 0)
		drawBand(parent, arm, {
			name = arm.name,
			start = gap,
			along = length,
			across = lo,
			acrossAnchor = 0,
			acrossSize = t,
			color = color,
			transparency = transparency,
			zIndex = 2,
		})
		if outline then
			local w = outline.width
			local oColor, oTransparency = outline.color, outline.transparency or 0
			local name = arm.name .. "Outline"
			-- Côtés sur toute la longueur du cadre, bouts entre les deux (longueur en px : crosshair)
			local framed = UDim.new(length.Scale, length.Offset + w * 2)
			for _, band in
				{
					{ suffix = "Side1", start = gap - w, along = framed, across = lo, anchor = 1, size = w },
					{ suffix = "Side2", start = gap - w, along = framed, across = hi, anchor = 0, size = w },
					{ suffix = "Inner", start = gap - w, along = UDim.new(0, w), across = lo, anchor = 0, size = t },
					{
						suffix = "Outer",
						start = gap + length.Offset,
						along = UDim.new(0, w),
						across = lo,
						anchor = 0,
						size = t,
					},
				}
			do
				drawBand(parent, arm, {
					name = name .. band.suffix,
					start = band.start,
					along = band.along,
					across = band.across,
					acrossAnchor = band.anchor,
					acrossSize = band.size,
					color = oColor,
					transparency = oTransparency,
					zIndex = 1,
				})
			end
		end
	end
	if not spec.dot then
		return
	end
	drawRect(parent, "Dot", lo, lo, Vector2.new(t, t), color, transparency, 2)
	if outline then
		local w = outline.width
		local oColor, oTransparency = outline.color, outline.transparency or 0
		-- Haut et bas sur toute la largeur du cadre, gauche et droite entre les deux
		drawRect(parent, "DotOutlineTop", lo - w, lo - w, Vector2.new(t + w * 2, w), oColor, oTransparency, 1)
		drawRect(parent, "DotOutlineBottom", lo - w, hi, Vector2.new(t + w * 2, w), oColor, oTransparency, 1)
		drawRect(parent, "DotOutlineLeft", lo - w, lo, Vector2.new(w, t), oColor, oTransparency, 1)
		drawRect(parent, "DotOutlineRight", hi, lo, Vector2.new(w, t), oColor, oTransparency, 1)
	end
end

-- Cette méthode permet de tracer les quatre branches d'un réticule (contour en ZIndex 1, trait en ZIndex 2) centrées sur
-- `parent` lorsqu'un réticule est construit (crosshair ou lunette).
function Reticle.drawArms(parent: GuiObject, spec: Spec)
	-- Crosshair : aligné sur les px, contour en cadre, point en option ; lunette : centré, contour en couche dessous (estompe)
	if spec.pixelAligned then
		drawAligned(parent, spec)
		return
	end
	local outline = spec.outline
	if outline then
		drawLayer(parent, spec, "Outline", outline.color, outline.transparency or 0, outline.width, 1)
	end
	drawLayer(parent, spec, "", spec.color, spec.transparency or 0, 0, 2)
end

return Reticle

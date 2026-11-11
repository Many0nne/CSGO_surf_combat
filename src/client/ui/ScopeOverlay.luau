-- Lunette des armes à scope, dessinée sans image pour rester nette à toutes les résolutions :
-- un cercle transparent dont le contour noir couvre le reste de l'écran, et un réticule en Frames.
local Players = game:GetService("Players")

local HUDState = require(script.Parent.HUDState)
local Reticle = require(script.Parent.Reticle)
local UIKit = require(script.Parent.UIKit)

local MASK_COLOR = Color3.new(0, 0, 0)
local LINE_COLOR = Color3.new(1, 1, 1)
local OUTLINE_COLOR = Color3.new(0, 0, 0)

-- Le contour part du bord du cercle : 4096 px couvrent aussi les coins d'un écran 8K ultra-large.
local MASK_THICKNESS = 4096
local LINE_THICKNESS = 1
local OUTLINE_THICKNESS = 3
local DOT_SIZE = 2
local CENTER_GAP = 6

-- Les branches s'estompent sur leur dernier quart, côté centre, pour dégager la cible.
local ARM_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.75, 0),
	NumberSequenceKeypoint.new(1, 0.65),
})

local ScopeOverlay = {}

local gui: ScreenGui?

-- Cette méthode permet de construire la lunette une seule fois lorsqu'elle est affichée pour la première fois.
local function build(): ScreenGui
	local screenGui = UIKit.create("ScreenGui", {
		Name = "ScopeOverlay",
		Enabled = false,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None, -- centre exact de l'écran, celui de la caméra
		DisplayOrder = -1, -- sous le HUD et les menus
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	local lens = UIKit.frame({
		Name = "Lens",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})
	UIKit.create("UIAspectRatioConstraint", {
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Height,
		Parent = lens,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = lens })
	UIKit.stroke(lens, MASK_COLOR, MASK_THICKNESS)

	-- Branches jusqu'au bord du cercle, contour sur les côtés seulement (bouts ouverts, estompés vers le centre)
	Reticle.drawArms(lens, {
		length = UDim.new(0.5, -CENTER_GAP),
		thickness = LINE_THICKNESS,
		gap = CENTER_GAP,
		color = LINE_COLOR,
		outline = { color = OUTLINE_COLOR, width = (OUTLINE_THICKNESS - LINE_THICKNESS) / 2 },
		fade = ARM_FADE,
	})
	UIKit.frame({
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
		BackgroundColor3 = LINE_COLOR,
		ZIndex = 2,
		Parent = lens,
	})
	return screenGui
end

-- Cette méthode permet d'afficher ou de masquer la lunette lorsque le joueur change de niveau de zoom.
function ScopeOverlay.setVisible(visible: boolean)
	HUDState.setScoped(visible) -- la lunette a son propre réticule : le crosshair de la visée simplifiée s'efface
	if not gui then
		if not visible then
			return
		end
		gui = build()
	end
	(gui :: ScreenGui).Enabled = visible
end

return ScopeOverlay

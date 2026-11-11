-- Crosshair de la « visée simplifiée » (#195, direction « Ligne de mire ») : quatre traits fins os autour d'un espace
-- central, doublés d'un contour noir pour rester lisibles sur ciel clair comme sur mur sombre. Taille fixe en pixels,
-- sans mise à l'échelle selon la résolution. Affiché selon HUDRules.crosshairVisible : réglage actif, HUD de jeu visible
-- (donc ni menu ni mort), ni lunette ni écran Réglages ouvert. Pas de CanvasGroup (cf. docs/ui.md) : de simples Frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors

local ARM_LENGTH = 9 -- px, longueur de chaque trait
local ARM_THICKNESS = 2 -- px
local CENTER_GAP = 5 -- px entre le centre et le début des traits
local OUTLINE = 1 -- px de contour noir autour des traits
local OUTLINE_TRANSPARENCY = 0.1 -- presque opaque : sur fond blanc, seul le contour se lit

local Crosshair = {}

local gui: ScreenGui?
local hudVisible = false -- règle « HUD de jeu visible » (HUDRules), posée par GameStateController
local scoped = false -- lunette affichée (ScopeOverlay)
local menuOpen = false -- menu en partie ouvert, Réglages compris (InGameMenu)

-- Cette méthode permet d'afficher ou de masquer le crosshair lorsque le réglage, le HUD, la lunette ou Réglages changent.
local function update()
	if gui then
		gui.Enabled = HUDRules.crosshairVisible(LocalSettings.get().simpleAim, hudVisible, scoped, menuOpen)
	end
end

-- Cette méthode permet de tracer une couche (contour noir ou trait os) des quatre branches lorsque le crosshair est
-- construit ; `grow` élargit chaque branche de part et d'autre (contour).
local function drawArms(parent: GuiObject, color: Color3, transparency: number, grow: number, zIndex: number)
	local long = ARM_LENGTH + grow * 2
	local thick = ARM_THICKNESS + grow * 2
	local arms = {
		{ name = "Left", anchor = Vector2.new(1, 0.5), offset = Vector2.new(-CENTER_GAP + grow, 0), horizontal = true },
		{ name = "Right", anchor = Vector2.new(0, 0.5), offset = Vector2.new(CENTER_GAP - grow, 0), horizontal = true },
		{ name = "Top", anchor = Vector2.new(0.5, 1), offset = Vector2.new(0, -CENTER_GAP + grow), horizontal = false },
		{
			name = "Bottom",
			anchor = Vector2.new(0.5, 0),
			offset = Vector2.new(0, CENTER_GAP - grow),
			horizontal = false,
		},
	}
	for _, arm in arms do
		UIKit.frame({
			Name = arm.name .. (if grow > 0 then "Outline" else ""),
			AnchorPoint = arm.anchor,
			Position = UDim2.new(0.5, arm.offset.X, 0.5, arm.offset.Y),
			Size = if arm.horizontal then UDim2.fromOffset(long, thick) else UDim2.fromOffset(thick, long),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = zIndex,
			Parent = parent,
		})
	end
end

-- Cette méthode permet de savoir si le HUD de jeu est affiché lorsque l'état client change (règle HUDRules.gameHudVisible).
function Crosshair.setHudVisible(show: boolean)
	hudVisible = show
	update()
end

-- Cette méthode permet de masquer le crosshair lorsque la lunette est affichée ou refermée (ScopeOverlay).
function Crosshair.setScoped(isScoped: boolean)
	scoped = isScoped
	update()
end

-- Cette méthode permet de masquer le crosshair lorsque le menu en partie s'ouvre ou se ferme (InGameMenu).
function Crosshair.setMenuOpen(isOpen: boolean)
	menuOpen = isOpen
	update()
end

-- Cette méthode permet de construire le crosshair et de suivre le réglage lorsque le client démarre ; le réglage sauvegardé
-- s'applique dès son arrivée du serveur, sans relancer.
function Crosshair.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "Crosshair",
		Enabled = false,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None, -- centre exact de l'écran, celui de la caméra
		DisplayOrder = 0,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local root = UIKit.frame({
		Name = "Root",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		Parent = screenGui,
	})
	drawArms(root, C.Black, OUTLINE_TRANSPARENCY, OUTLINE, 1)
	drawArms(root, C.Bone, 0, 0, 2)

	LocalSettings.onChanged(update)
	update()
end

return Crosshair

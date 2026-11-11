-- Crosshair de la « visée simplifiée » (#195, direction « Ligne de mire ») : quatre traits fins os autour d'un espace
-- central, doublés d'un contour noir pour rester lisibles sur ciel clair comme sur mur sombre. Taille fixe en pixels,
-- sans mise à l'échelle selon la résolution. Affiché selon HUDRules.crosshairVisible appliquée à HUDState (#223) : réglage
-- actif, HUD de jeu visible (donc ni menu ni mort), ni lunette ni menu en partie ouvert. Pas de CanvasGroup (cf.
-- docs/ui.md) : de simples Frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local HUDState = require(script.Parent.HUDState)
local Reticle = require(script.Parent.Reticle)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors

local ARM_LENGTH = 9 -- px, longueur de chaque trait
local ARM_THICKNESS = 2 -- px
local CENTER_GAP = 5 -- px entre le centre et le début des traits
local OUTLINE = 1 -- px de contour noir autour des traits
local OUTLINE_TRANSPARENCY = 0.1 -- presque opaque : sur fond blanc, seul le contour se lit

local Crosshair = {}

local gui: ScreenGui?

-- Cette méthode permet d'afficher ou de masquer le crosshair lorsque le réglage ou l'état du HUD (HUDState) changent.
local function update()
	if gui then
		gui.Enabled = HUDRules.crosshairVisible(HUDState.get(), LocalSettings.get().simpleAim)
	end
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
	Reticle.drawArms(root, {
		length = UDim.new(0, ARM_LENGTH),
		thickness = ARM_THICKNESS,
		gap = CENTER_GAP,
		color = C.Bone,
		outline = { color = C.Black, width = OUTLINE, transparency = OUTLINE_TRANSPARENCY, caps = true },
	})

	LocalSettings.onChanged(update)
	HUDState.onChanged(update)
	update()
end

return Crosshair

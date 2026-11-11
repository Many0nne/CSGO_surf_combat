-- Crosshair de la « visée simplifiée » (#195, direction « Ligne de mire ») : quatre traits fins os autour d'un espace
-- central, doublés d'un contour noir pour rester lisibles sur ciel clair comme sur mur sombre. Style réglable par le joueur
-- (#251 : couleur de la palette, longueur, épaisseur, écart, point, contour, opacité), redessiné dès qu'il change ; le
-- tracé (`Crosshair.draw`) sert aussi à l'aperçu des Réglages. Taille fixe en pixels,
-- sans mise à l'échelle selon la résolution. Affiché selon HUDRules.crosshairVisible appliquée à HUDState (#223) : réglage
-- actif, HUD de jeu visible (donc ni menu ni mort), ni lunette ni menu en partie ouvert. Pas de CanvasGroup (cf.
-- docs/ui.md) : de simples Frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local HUDState = require(script.Parent.HUDState)
local Reticle = require(script.Parent.Reticle)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors

local OUTLINE = 1 -- px de contour noir autour des traits
local OUTLINE_TRANSPARENCY = 0.1 -- presque opaque : sur fond blanc, seul le contour se lit

local Crosshair = {}

local gui: ScreenGui?
local root: Frame?
local drawnKey: string? -- réglages du dernier tracé : on ne redessine qu'au changement du style

-- Cette méthode permet de retrouver la couleur d'un id de la palette du viseur lorsque le crosshair est tracé (os si
-- l'id est inconnu).
function Crosshair.color(id: string): Color3
	for _, entry in UITheme.CrosshairPalette do
		if entry.id == id then
			return entry.color
		end
	end
	return C.Bone
end

-- Cette méthode permet de résumer le style du viseur en une clé lorsque les réglages changent : une clé identique
-- n'oblige pas à redessiner (changement d'un autre réglage).
function Crosshair.styleKey(settings: PlayerSettings.Settings): string
	return table.concat({
		settings.crosshairColor,
		tostring(settings.crosshairLength),
		tostring(settings.crosshairThickness),
		tostring(settings.crosshairGap),
		tostring(settings.crosshairDot),
		tostring(settings.crosshairOutline),
		tostring(settings.crosshairOpacity),
	}, "|")
end

-- Cette méthode permet de tracer le viseur réglé par le joueur, centré sur `parent` (de taille quelconque), lorsque le
-- crosshair est construit ou redessiné, en jeu comme dans l'aperçu des Réglages ; l'opacité vaut pour trait et contour.
function Crosshair.draw(parent: GuiObject, settings: PlayerSettings.Settings)
	local opacity = settings.crosshairOpacity
	Reticle.drawArms(parent, {
		length = UDim.new(0, settings.crosshairLength),
		thickness = settings.crosshairThickness,
		gap = settings.crosshairGap,
		color = Crosshair.color(settings.crosshairColor),
		transparency = 1 - opacity,
		dot = settings.crosshairDot,
		outline = if settings.crosshairOutline
			then {
				color = C.Black,
				width = OUTLINE,
				transparency = 1 - (1 - OUTLINE_TRANSPARENCY) * opacity,
				caps = true,
			}
			else nil,
	})
end

-- Cette méthode permet de redessiner le crosshair en jeu lorsque le joueur change son style (aperçu en direct, sans
-- respawn) ou que ses réglages sauvegardés arrivent.
local function redraw(settings: PlayerSettings.Settings)
	local key = Crosshair.styleKey(settings)
	if not root or key == drawnKey then
		return
	end
	drawnKey = key
	root:ClearAllChildren()
	Crosshair.draw(root, settings)
end

-- Cette méthode permet d'afficher ou de masquer le crosshair, et de suivre son style, lorsque les réglages ou l'état du
-- HUD (HUDState) changent.
local function update()
	if gui then
		local settings = LocalSettings.get()
		redraw(settings)
		gui.Enabled = HUDRules.crosshairVisible(HUDState.get(), settings.simpleAim)
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
	root = UIKit.frame({
		Name = "Root",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		Parent = screenGui,
	})

	LocalSettings.onChanged(update)
	HUDState.onChanged(update)
	update()
end

return Crosshair

-- Speedometer : vitesse horizontale en studs/s, en bas à gauche, en miroir du compteur de munitions (#308 : droit, plus
-- de chiffres penchés). Chiffres os à ombre décalée, nom du palier et unité ambrés à droite, bande ambrée horizontale
-- crantée aux seuils de palier ; au dernier palier, chiffres, palier et bande passent au rouge d'impact. Règles pures
-- dans HUDRules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local NUMBER_SIZE = 72
local NUMBER_WIDTH = 150 -- chiffres alignés à droite : le palier et l'unité ne bougent pas quand la vitesse change
local SHADOW_OFFSET = Vector2.new(4, 4)
local SHADOW_TRANSPARENCY = 0.35
local BAND_SIZE = Vector2.new(276, 9)
local BAND_HOT_WIDTH = 34 -- zone rouge au bout de la bande, au-delà du remplissage plein
local TRACK_TRANSPARENCY = 0.7
local HOT_ZONE_TRANSPARENCY = 0.6
local NOTCH_WIDTH = 3
local SCRIM_SIZE = Vector2.new(560, 260)
local SCRIM_TRANSPARENCY = 0.15

local Speedometer = {}

local gui: ScreenGui?
local speedLabel: TextLabel
local shadowLabel: TextLabel
local tierLabel: TextLabel
local fill: Frame
local hotZone: Frame
local currentTier = 0
local lastShown = -1
local visible = false -- piloté par GameStateController ; init() peut arriver après le premier setVisible

-- Cette méthode permet de créer un texte du compteur lorsque le speedometer est construit.
local function hudText(parent: GuiObject, props: { [string]: any }): TextLabel
	props.Parent = parent
	return UIKit.text(props)
end

-- Cette méthode permet d'appliquer l'aspect d'un palier (nom, couleurs) lorsque la vitesse en change.
local function applyTier(tier: number)
	currentTier = tier
	local hot = tier == #HUDRules.SPEED_TIERS
	tierLabel.Text = HUDRules.SPEED_TIERS[tier].name
	UIKit.tween(speedLabel, Motion.Color, { TextColor3 = hot and C.HitRed or C.Bone })
	UIKit.tween(tierLabel, Motion.Color, { TextColor3 = hot and C.HitRed or C.Accent })
	UIKit.tween(fill, Motion.Color, { BackgroundColor3 = hot and C.HitRed or C.Accent })
	UIKit.tween(hotZone, Motion.Color, { BackgroundTransparency = hot and 0 or HOT_ZONE_TRANSPARENCY })
end

function Speedometer.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "Speedometer",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = visible,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local root = UIKit.scaledRoot(screenGui, true)
	UIKit.cornerScrim(root, "BottomLeft", SCRIM_SIZE, SCRIM_TRANSPARENCY)

	local holder = UIKit.frame({
		Name = "Holder",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 44, 1, -44),
		Size = UDim2.fromOffset(BAND_SIZE.X + BAND_HOT_WIDTH, 104),
		BackgroundTransparency = 1,
		Parent = root,
	})

	shadowLabel = hudText(holder, {
		Name = "SpeedShadow",
		Text = "0",
		FontFace = F.Display,
		TextSize = NUMBER_SIZE,
		TextColor3 = C.Black,
		TextTransparency = SHADOW_TRANSPARENCY,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(SHADOW_OFFSET.X, SHADOW_OFFSET.Y),
		Size = UDim2.fromOffset(NUMBER_WIDTH, NUMBER_SIZE),
	})
	speedLabel = hudText(holder, {
		Name = "SpeedValue",
		Text = "0",
		FontFace = F.Display,
		TextSize = NUMBER_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(NUMBER_WIDTH, NUMBER_SIZE),
	})
	tierLabel = hudText(holder, {
		Name = "Tier",
		Text = HUDRules.SPEED_TIERS[1].name,
		FontFace = F.Display,
		TextSize = 22,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(NUMBER_WIDTH + 10, 16),
		Size = UDim2.fromOffset(130, 26),
	})
	hudText(holder, {
		Name = "Unit",
		Text = "U/S",
		FontFace = F.DisplayMedium,
		TextSize = 17,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(NUMBER_WIDTH + 10, 42),
		Size = UDim2.fromOffset(60, 18),
	})

	local band = UIKit.frame({
		Name = "Band",
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.fromOffset(BAND_SIZE.X, BAND_SIZE.Y),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = TRACK_TRANSPARENCY,
		Parent = holder,
	})
	fill = UIKit.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = band })
	for i = 2, #HUDRules.SPEED_TIERS - 1 do
		UIKit.frame({
			Name = "Notch" .. i,
			Position = UDim2.fromScale(HUDRules.speedFill(HUDRules.SPEED_TIERS[i].min), 0),
			Size = UDim2.new(0, NOTCH_WIDTH, 1, 0),
			BackgroundColor3 = C.Black,
			ZIndex = 2,
			Parent = band,
		})
	end
	hotZone = UIKit.frame({
		Name = "HotZone",
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, BAND_HOT_WIDTH, 1, 0),
		BackgroundColor3 = C.HitRed,
		BackgroundTransparency = HOT_ZONE_TRANSPARENCY,
		Parent = band,
	})

	applyTier(1)

	Players.LocalPlayer.CharacterRemoving:Connect(function()
		Speedometer.update(0)
	end)
end

-- Cette méthode permet d'afficher ou de masquer le compteur lorsque le HUD de jeu change de visibilité ;
-- la valeur est mémorisée pour le ScreenGui créé plus tard au premier spawn.
function Speedometer.setVisible(show: boolean)
	visible = show
	if gui then
		gui.Enabled = show
	end
end

function Speedometer.update(speed: number)
	if not gui then
		return
	end
	local shown = math.floor(speed)
	if shown == lastShown then
		return
	end
	lastShown = shown
	local text = string.format("%d", shown)
	speedLabel.Text = text
	shadowLabel.Text = text
	fill.Size = UDim2.fromScale(HUDRules.speedFill(speed), 1)
	local tier = HUDRules.speedTier(speed)
	if tier ~= currentTier then
		applyTier(tier)
	end
end

return Speedometer

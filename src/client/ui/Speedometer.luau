-- Speedometer (direction « Tactical ») : vitesse horizontale en studs/s, 5 segments et nom du palier.
-- À chaque changement de palier : couleur animée et pulsation du nombre (UIScale).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion

local SEGMENT_SIZE = Vector2.new(20, 7)
local SEGMENT_GAP = 3
local SEGMENT_OFF_TRANSPARENCY = 0.86

local Speedometer = {}

local gui: ScreenGui?
local speedLabel: TextLabel
local speedScale: UIScale
local tierLabel: TextLabel
local segments: { Frame } = {}
local currentTier = 0
local lastShown = -1

-- Cette méthode permet d'appliquer l'aspect d'un palier (couleurs, segments allumés, pulsation) lorsque la vitesse en change.
local function applyTier(tier: number, speed: number)
	currentTier = tier
	local color = UITheme.SpeedTierColors[tier]
	UIKit.tween(speedLabel, Motion.Color, { TextColor3 = color })
	UIKit.tween(tierLabel, Motion.Color, { TextColor3 = color })
	tierLabel.Text = HUDRules.SPEED_TIERS[tier].name
	for i, seg in segments do
		local lit = i <= tier and speed > 0
		UIKit.tween(seg, Motion.Color, {
			BackgroundColor3 = lit and color or C.Text,
			BackgroundTransparency = lit and 0 or SEGMENT_OFF_TRANSPARENCY,
		})
	end
	UIKit.tween(speedScale, Motion.Pop, { Scale = UITheme.SpeedTierScales[tier] })
end

function Speedometer.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "Speedometer",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local root = UIKit.scaledRoot(screenGui)

	local panel = UIKit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96), -- au-dessus de la hotbar d'armes Roblox
		Size = UDim2.fromOffset(250, 46),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.18,
		Parent = root,
	})
	UIKit.stroke(panel, C.Border)

	speedLabel = UIKit.text({
		Name = "SpeedValue",
		Text = "0",
		FontFace = F.MonoBold,
		TextSize = T.Speed,
		TextColor3 = UITheme.SpeedTierColors[1],
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, 84, 0.5, 0),
		Size = UDim2.fromOffset(72, 32),
		Parent = panel,
	})
	speedScale = UIKit.create("UIScale", { Parent = speedLabel })
	UIKit.text({
		Text = "U/S",
		FontFace = F.DisplayMedium,
		TextSize = T.Micro,
		TextColor3 = C.Muted,
		Position = UDim2.new(0, 88, 0.5, 1),
		Size = UDim2.fromOffset(26, 14),
		Parent = panel,
	})

	for i = 1, #HUDRules.SPEED_TIERS do
		segments[i] = UIKit.frame({
			Name = "Segment" .. i,
			Position = UDim2.fromOffset(124 + (i - 1) * (SEGMENT_SIZE.X + SEGMENT_GAP), 12),
			Size = UDim2.fromOffset(SEGMENT_SIZE.X, SEGMENT_SIZE.Y),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = SEGMENT_OFF_TRANSPARENCY,
			Parent = panel,
		})
	end
	tierLabel = UIKit.text({
		Name = "Tier",
		Text = HUDRules.SPEED_TIERS[1].name,
		FontFace = F.Display,
		TextSize = T.Micro,
		TextColor3 = UITheme.SpeedTierColors[1],
		Position = UDim2.fromOffset(124, 23),
		Size = UDim2.fromOffset(112, 14),
		Parent = panel,
	})

	applyTier(1, 0)

	Players.LocalPlayer.CharacterRemoving:Connect(function()
		Speedometer.update(0)
	end)
end

function Speedometer.update(speed: number)
	if not gui then
		return
	end
	local shown = math.floor(speed)
	if shown == lastShown then
		return
	end
	-- Le premier segment s'éteint à l'arrêt : passer de 0 à > 0 réapplique aussi le palier
	local stoppedChanged = (shown == 0) ~= (lastShown == 0)
	lastShown = shown
	speedLabel.Text = string.format("%d", shown)
	local tier = HUDRules.speedTier(speed)
	if tier ~= currentTier or stoppedChanged then
		applyTier(tier, speed)
	end
end

return Speedometer

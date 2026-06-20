local Players = game:GetService("Players")

local Speedometer = {}

local ACCENT = Color3.fromRGB(205, 38, 38)
local MUTED  = Color3.fromRGB(72, 92, 120)

local speedLabel: TextLabel?

function Speedometer.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("Speedometer")
	if existing then
		speedLabel = existing:FindFirstChild("SpeedValue", true)
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "Speedometer"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.Parent         = playerGui

	local container = Instance.new("Frame")
	container.Size                   = UDim2.fromOffset(110, 52)
	container.AnchorPoint            = Vector2.new(0.5, 1)
	container.Position               = UDim2.new(0.5, 0, 1, -104)
	container.BackgroundTransparency = 1
	container.Parent                 = gui

	local tag = Instance.new("TextLabel")
	tag.Size                   = UDim2.new(1, 0, 0, 14)
	tag.Position               = UDim2.fromOffset(0, 0)
	tag.BackgroundTransparency = 1
	tag.Text                   = "SPD"
	tag.TextColor3             = MUTED
	tag.Font                   = Enum.Font.GothamBold
	tag.TextSize               = 10
	tag.TextXAlignment         = Enum.TextXAlignment.Center
	tag.Parent                 = container

	local numLbl = Instance.new("TextLabel")
	numLbl.Name = "SpeedValue"
	numLbl.Size                   = UDim2.new(1, -26, 0, 34)
	numLbl.Position               = UDim2.fromOffset(0, 14)
	numLbl.BackgroundTransparency = 1
	numLbl.Text                   = "0"
	numLbl.TextColor3             = ACCENT
	numLbl.Font                   = Enum.Font.Code
	numLbl.TextSize               = 28
	numLbl.TextXAlignment         = Enum.TextXAlignment.Right
	numLbl.Parent                 = container

	local unitLbl = Instance.new("TextLabel")
	unitLbl.Size                   = UDim2.fromOffset(24, 16)
	unitLbl.AnchorPoint            = Vector2.new(1, 1)
	unitLbl.Position               = UDim2.new(1, 0, 1, -2)
	unitLbl.BackgroundTransparency = 1
	unitLbl.Text                   = "u/s"
	unitLbl.TextColor3             = MUTED
	unitLbl.Font                   = Enum.Font.GothamBold
	unitLbl.TextSize               = 10
	unitLbl.TextXAlignment         = Enum.TextXAlignment.Left
	unitLbl.Parent                 = container

	speedLabel = numLbl

	Players.LocalPlayer.CharacterRemoving:Connect(function()
		if speedLabel then speedLabel.Text = "0" end
	end)
end

function Speedometer.update(speed: number)
	if speedLabel then
		speedLabel.Text = string.format("%d", math.floor(speed))
	end
end

return Speedometer

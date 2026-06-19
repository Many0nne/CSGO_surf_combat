local Players = game:GetService("Players")

local Speedometer = {}
local label: TextLabel?

function Speedometer.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("Speedometer")
	if existing then
		label = existing:FindFirstChildWhichIsA("TextLabel")
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name              = "Speedometer"
	gui.ResetOnSpawn      = false
	gui.IgnoreGuiInset    = true
	gui.Parent            = playerGui

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(0, 160, 0, 36)
	lbl.Position               = UDim2.new(0.5, -80, 1, -120)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0.5
	lbl.Font                   = Enum.Font.Code
	lbl.TextSize               = 26
	lbl.Text                   = "0 u/s"
	lbl.Parent                 = gui

	label = lbl
end

function Speedometer.update(speed: number)
	if label then
		label.Text = string.format("%d u/s", math.floor(speed))
	end
end

return Speedometer

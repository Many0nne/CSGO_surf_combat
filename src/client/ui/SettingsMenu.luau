local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)

local SettingsMenu = {}

local gui: ScreenGui?
local open = false
local fpsCamRef: {
	setSensitivity: (number) -> (),
	getSensitivity: () -> number,
	setScopeMultiplier: (number) -> (),
	getScopeMultiplier: () -> number,
}?

local function makeSlider(
	parent: GuiBase2d,
	labelText: string,
	yOffset: number,
	minVal: number,
	maxVal: number,
	initVal: number,
	decimals: number,
	onChange: (number) -> ()
): (number) -> ()

	local fmt = "%." .. decimals .. "f"
	local currentVal = initVal

	local row = Instance.new("Frame")
	row.Size                   = UDim2.new(1, -40, 0, 36)
	row.Position               = UDim2.new(0, 20, 0, yOffset)
	row.BackgroundTransparency = 1
	row.Parent                 = parent

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(0, 110, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = Color3.new(1, 1, 1)
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextSize               = 14
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.Text                   = labelText
	lbl.Parent                 = row

	-- TextBox pour saisie directe
	local valBox = Instance.new("TextBox")
	valBox.Size                   = UDim2.new(0, 54, 0, 26)
	valBox.Position               = UDim2.new(1, -54, 0.5, -13)
	valBox.BackgroundColor3       = Color3.fromRGB(35, 35, 38)
	valBox.BorderSizePixel        = 0
	valBox.TextColor3             = Color3.fromRGB(220, 220, 220)
	valBox.Font                   = Enum.Font.Code
	valBox.TextSize               = 13
	valBox.TextXAlignment         = Enum.TextXAlignment.Center
	valBox.ClearTextOnFocus       = false
	valBox.Text                   = string.format(fmt, initVal)
	valBox.ZIndex                 = 12
	valBox.Parent                 = row
	local vbc = Instance.new("UICorner")
	vbc.CornerRadius = UDim.new(0, 4)
	vbc.Parent = valBox

	local track = Instance.new("Frame")
	track.Size             = UDim2.new(1, -178, 0, 6)
	track.Position         = UDim2.new(0, 115, 0.5, -3)
	track.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	track.BorderSizePixel  = 0
	track.Parent           = row
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill

	local handle = Instance.new("TextButton")
	handle.Size             = UDim2.new(0, 16, 0, 16)
	handle.BackgroundColor3 = Color3.new(1, 1, 1)
	handle.BorderSizePixel  = 0
	handle.Text             = ""
	handle.ZIndex           = 10
	handle.Parent           = track
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = handle

	local function applyValue(v: number)
		v = math.clamp(v, minVal, maxVal)
		currentVal = v
		local t = (v - minVal) / (maxVal - minVal)
		fill.Size       = UDim2.new(t, 0, 1, 0)
		handle.Position = UDim2.new(t, -8, 0.5, -8)
		valBox.Text     = string.format(fmt, v)
		onChange(v)
	end

	-- Saisie directe : appliquer sur Enter ou perte de focus
	valBox.FocusLost:Connect(function()
		local num = tonumber(valBox.Text)
		if num then
			applyValue(num)
		else
			valBox.Text = string.format(fmt, currentVal)
		end
	end)

	applyValue(initVal)

	local function valueFromMouse(inputPos: Vector2): number
		local absPos  = track.AbsolutePosition
		local absSize = track.AbsoluteSize
		local t = math.clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		return minVal + (maxVal - minVal) * t
	end

	local dragging = false
	handle.MouseButton1Down:Connect(function() dragging = true end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
			applyValue(valueFromMouse(inp.Position))
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	track.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			applyValue(valueFromMouse(inp.Position))
		end
	end)

	return applyValue
end

local function setOpen(state: boolean)
	open = state
	if gui then gui.Enabled = state end
	if state then
		UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

function SettingsMenu.init(fpsCam: typeof(fpsCamRef))
	if gui then return end
	fpsCamRef = fpsCam

	gui = Instance.new("ScreenGui")
	gui.Name           = "SettingsMenu"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.Enabled        = false
	gui.Parent         = Players.LocalPlayer:WaitForChild("PlayerGui")

	local backdrop = Instance.new("TextButton")
	backdrop.Size                   = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3       = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel        = 0
	backdrop.Text                   = ""
	backdrop.AutoButtonColor        = false
	backdrop.Parent                 = gui
	backdrop.MouseButton1Click:Connect(function() setOpen(false) end)

	local panel = Instance.new("TextButton")
	panel.Size             = UDim2.new(0, 380, 0, 210)
	panel.Position         = UDim2.new(0.5, -190, 0.5, -105)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	panel.BorderSizePixel  = 0
	panel.Text             = ""
	panel.AutoButtonColor  = false
	panel.Parent           = backdrop
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 8)
	pc.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, 0, 0, 44)
	title.BackgroundTransparency = 1
	title.TextColor3             = Color3.new(1, 1, 1)
	title.Font                   = Enum.Font.GothamBold
	title.TextSize               = 18
	title.Text                   = "SETTINGS"
	title.Parent                 = panel

	local div = Instance.new("Frame")
	div.Size             = UDim2.new(1, -40, 0, 1)
	div.Position         = UDim2.new(0, 20, 0, 44)
	div.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	div.BorderSizePixel  = 0
	div.Parent           = panel

	makeSlider(panel, "Sensitivity", 60, 0.1, 5.0, CameraConfig.DEFAULT_SENS, 2,
		function(v) if fpsCamRef then fpsCamRef.setSensitivity(v) end end
	)

	makeSlider(panel, "Scope Sens", 110, 0.1, 1.0, CameraConfig.SCOPE_SENS_MULT, 2,
		function(v) if fpsCamRef then fpsCamRef.setScopeMultiplier(v) end end
	)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(0, 100, 0, 32)
	closeBtn.Position         = UDim2.new(0.5, -50, 1, -52)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	closeBtn.BorderSizePixel  = 0
	closeBtn.TextColor3       = Color3.new(1, 1, 1)
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = 14
	closeBtn.Text             = "CLOSE"
	closeBtn.Parent           = panel
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 6)
	cc.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

	UserInputService.InputBegan:Connect(function(inp, gameProcessed)
		if gameProcessed then return end
		if inp.KeyCode == Enum.KeyCode.P then
			setOpen(not open)
		end
	end)
end

function SettingsMenu.isOpen(): boolean
	return open
end

return SettingsMenu

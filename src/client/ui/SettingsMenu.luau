local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)

local SettingsMenu = {}

local SURFACE  = Color3.fromRGB(14, 20, 32)
local PANEL    = Color3.fromRGB(18, 26, 40)
local BORDER   = Color3.fromRGB(28, 42, 62)
local ACCENT   = Color3.fromRGB(205, 38, 38)
local TRACK_BG = Color3.fromRGB(22, 32, 50)
local TEXT     = Color3.fromRGB(220, 230, 245)
local MUTED    = Color3.fromRGB(72, 92, 120)
local BTN_BG   = Color3.fromRGB(18, 28, 44)

local FONT_BLK = Enum.Font.GothamBlack
local FONT_BD  = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

local TWEEN_FAST = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui: ScreenGui?
local open = false
local fpsCamRef: {
	setSensitivity:    (number) -> (),
	getSensitivity:    () -> number,
	setScopeMultiplier: (number) -> (),
	getScopeMultiplier: () -> number,
}?

local function addCorner(parent: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thick: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

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
	row.Size                   = UDim2.new(1, 0, 0, 48)
	row.Position               = UDim2.fromOffset(0, yOffset)
	row.BackgroundTransparency = 1
	row.Parent                 = parent

	-- Label
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(0, 110, 0, 18)
	lbl.Position               = UDim2.fromOffset(0, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = MUTED
	lbl.Font                   = FONT_BD
	lbl.TextSize               = 11
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.Text                   = labelText
	lbl.Parent                 = row

	-- Value TextBox
	local valBox = Instance.new("TextBox")
	valBox.Size                   = UDim2.fromOffset(52, 26)
	valBox.AnchorPoint            = Vector2.new(1, 1)
	valBox.Position               = UDim2.new(1, 0, 1, 0)
	valBox.BackgroundColor3       = PANEL
	valBox.BorderSizePixel        = 0
	valBox.TextColor3             = TEXT
	valBox.Font                   = Enum.Font.Code
	valBox.TextSize               = 13
	valBox.TextXAlignment         = Enum.TextXAlignment.Center
	valBox.ClearTextOnFocus       = false
	valBox.Text                   = string.format(fmt, initVal)
	valBox.ZIndex                 = 12
	valBox.Parent                 = row
	addCorner(valBox, 3)
	addStroke(valBox, BORDER, 1)

	-- Track
	local track = Instance.new("Frame")
	track.Size             = UDim2.new(1, -170, 0, 4)
	track.Position         = UDim2.new(0, 116, 1, -14)
	track.BackgroundColor3 = TRACK_BG
	track.BorderSizePixel  = 0
	track.Parent           = row
	addCorner(track, 2)
	addStroke(track, BORDER, 1)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	addCorner(fill, 2)

	local handle = Instance.new("TextButton")
	handle.Size             = UDim2.fromOffset(14, 14)
	handle.AnchorPoint      = Vector2.new(0.5, 0.5)
	handle.BackgroundColor3 = Color3.new(1, 1, 1)
	handle.BorderSizePixel  = 0
	handle.Text             = ""
	handle.ZIndex           = 10
	handle.Parent           = track
	addCorner(handle, 7)

	local function applyValue(v: number)
		v = math.clamp(v, minVal, maxVal)
		currentVal = v
		local t = (v - minVal) / (maxVal - minVal)
		fill.Size       = UDim2.new(t, 0, 1, 0)
		handle.Position = UDim2.new(t, 0, 0.5, 0)
		valBox.Text     = string.format(fmt, v)
		onChange(v)
	end

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
	backdrop.Size                   = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel        = 0
	backdrop.Text                   = ""
	backdrop.AutoButtonColor        = false
	backdrop.Parent                 = gui
	backdrop.MouseButton1Click:Connect(function() setOpen(false) end)

	-- Panel
	local panel = Instance.new("TextButton")
	panel.Size             = UDim2.fromOffset(420, 256)
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.Position         = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = SURFACE
	panel.BorderSizePixel  = 0
	panel.Text             = ""
	panel.AutoButtonColor  = false
	panel.Parent           = backdrop
	addCorner(panel, 6)
	addStroke(panel, BORDER, 1)

	-- Left accent stripe
	local stripe = Instance.new("Frame")
	stripe.Size             = UDim2.new(0, 3, 0.65, 0)
	stripe.AnchorPoint      = Vector2.new(0, 0.5)
	stripe.Position         = UDim2.new(0, 0, 0.5, 0)
	stripe.BackgroundColor3 = ACCENT
	stripe.BorderSizePixel  = 0
	stripe.Parent           = panel
	addCorner(stripe, 2)

	-- Content frame (padded)
	local content = Instance.new("Frame")
	content.Size                   = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel        = 0
	content.Parent                 = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 32)
	pad.PaddingRight  = UDim.new(0, 24)
	pad.PaddingTop    = UDim.new(0, 26)
	pad.PaddingBottom = UDim.new(0, 24)
	pad.Parent        = content

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, 0, 0, 22)
	title.Position               = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3             = TEXT
	title.Font                   = FONT_BLK
	title.TextSize               = 18
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.Text                   = "SETTINGS"
	title.Parent                 = content

	local div = Instance.new("Frame")
	div.Size             = UDim2.new(1, 0, 0, 1)
	div.Position         = UDim2.fromOffset(0, 32)
	div.BackgroundColor3 = BORDER
	div.BorderSizePixel  = 0
	div.Parent           = content

	makeSlider(content, "Sensitivity", 44, 0.1, 5.0, CameraConfig.DEFAULT_SENS, 2,
		function(v) if fpsCamRef then fpsCamRef.setSensitivity(v) end end
	)
	makeSlider(content, "Scope Sens",  102, 0.1, 1.0, CameraConfig.SCOPE_SENS_MULT, 2,
		function(v) if fpsCamRef then fpsCamRef.setScopeMultiplier(v) end end
	)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(0, 100, 0, 36)
	closeBtn.AnchorPoint      = Vector2.new(1, 1)
	closeBtn.Position         = UDim2.new(1, 0, 1, 0)
	closeBtn.BackgroundColor3 = BTN_BG
	closeBtn.BorderSizePixel  = 0
	closeBtn.TextColor3       = MUTED
	closeBtn.Font             = FONT_BD
	closeBtn.TextSize         = 13
	closeBtn.Text             = "CLOSE"
	closeBtn.AutoButtonColor  = false
	closeBtn.Parent           = content
	addCorner(closeBtn, 3)
	addStroke(closeBtn, BORDER, 1)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, TWEEN_FAST, { TextColor3 = TEXT, BackgroundColor3 = Color3.fromRGB(24, 36, 56) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, TWEEN_FAST, { TextColor3 = MUTED, BackgroundColor3 = BTN_BG }):Play()
	end)
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

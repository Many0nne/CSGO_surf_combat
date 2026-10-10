local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local SettingsMenu = {}

local C = UITheme.Color
local F = UITheme.Font
local TS = UITheme.TextSize
local R = UITheme.Radius
local THIN = UITheme.Stroke.THIN

local TWEEN_FAST = TweenInfo.new(UITheme.Motion.FAST, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui: ScreenGui?
local open = false
local fpsCamRef: {
	setSensitivity: (number) -> (),
	getSensitivity: () -> number,
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
	row.Size = UDim2.new(1, 0, 0, 48)
	row.Position = UDim2.fromOffset(0, yOffset)
	row.BackgroundTransparency = 1
	row.Parent = parent

	-- Label
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromOffset(110, 18)
	lbl.Position = UDim2.fromOffset(0, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = C.TEXT_DIM
	lbl.Font = F.LABEL
	lbl.TextSize = TS.LABEL
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = labelText
	lbl.Parent = row

	-- Value TextBox
	local valBox = Instance.new("TextBox")
	valBox.Size = UDim2.fromOffset(52, 26)
	valBox.AnchorPoint = Vector2.new(1, 1)
	valBox.Position = UDim2.fromScale(1, 1)
	valBox.BackgroundColor3 = C.SURFACE_RAISED
	valBox.BorderSizePixel = 0
	valBox.TextColor3 = C.TEXT
	valBox.Font = F.MONO
	valBox.TextSize = TS.BODY
	valBox.TextXAlignment = Enum.TextXAlignment.Center
	valBox.ClearTextOnFocus = false
	valBox.Text = string.format(fmt, initVal)
	valBox.ZIndex = 12
	valBox.Parent = row
	addCorner(valBox, R.MD)
	addStroke(valBox, C.BORDER, THIN)

	-- Track
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -170, 0, 4)
	track.Position = UDim2.new(0, 116, 1, -14)
	track.BackgroundColor3 = C.TRACK
	track.BorderSizePixel = 0
	track.Parent = row
	addCorner(track, R.SM)
	addStroke(track, C.BORDER, THIN)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = C.ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, R.SM)

	local handle = Instance.new("TextButton")
	handle.Size = UDim2.fromOffset(14, 14)
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.BackgroundColor3 = C.HANDLE
	handle.BorderSizePixel = 0
	handle.Text = ""
	handle.ZIndex = 10
	handle.Parent = track
	addCorner(handle, R.PILL)

	local function applyValue(v: number)
		v = math.clamp(v, minVal, maxVal)
		currentVal = v
		local t = (v - minVal) / (maxVal - minVal)
		fill.Size = UDim2.fromScale(t, 1)
		handle.Position = UDim2.fromScale(t, 0.5)
		valBox.Text = string.format(fmt, v)
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
		local absPos = track.AbsolutePosition
		local absSize = track.AbsoluteSize
		local t = math.clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		return minVal + (maxVal - minVal) * t
	end

	local dragging = false
	handle.MouseButton1Down:Connect(function()
		dragging = true
	end)
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
	if gui then
		gui.Enabled = state
	end
	if state then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

function SettingsMenu.init(fpsCam: typeof(fpsCamRef))
	if gui then
		return
	end
	fpsCamRef = fpsCam

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsMenu"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = C.BACKDROP
	backdrop.BackgroundTransparency = UITheme.Transparency.BACKDROP
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = gui
	backdrop.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	-- Panel
	local panel = Instance.new("TextButton")
	panel.Size = UDim2.fromOffset(420, 256)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = C.SURFACE
	panel.BorderSizePixel = 0
	panel.Text = ""
	panel.AutoButtonColor = false
	panel.Parent = backdrop
	addCorner(panel, R.LG)
	addStroke(panel, C.BORDER, THIN)

	-- Left accent stripe
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, UITheme.Stroke.STRIPE, 0.65, 0)
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.fromScale(0, 0.5)
	stripe.BackgroundColor3 = C.ACCENT
	stripe.BorderSizePixel = 0
	stripe.Parent = panel
	addCorner(stripe, R.SM)

	-- Content frame (padded)
	local content = Instance.new("Frame")
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UITheme.Space.XL)
	pad.PaddingRight = UDim.new(0, UITheme.Space.LG)
	pad.PaddingTop = UDim.new(0, 26)
	pad.PaddingBottom = UDim.new(0, UITheme.Space.LG)
	pad.Parent = content

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Position = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = C.TEXT
	title.Font = F.DISPLAY
	title.TextSize = TS.TITLE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "SETTINGS"
	title.Parent = content

	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.fromOffset(0, 32)
	div.BackgroundColor3 = C.BORDER
	div.BorderSizePixel = 0
	div.Parent = content

	makeSlider(content, "Sensitivity", 44, 0.1, 5.0, CameraConfig.DEFAULT_SENS, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setSensitivity(v)
		end
	end)
	makeSlider(content, "Scope Sens", 102, 0.1, 1.0, CameraConfig.SCOPE_SENS_MULT, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setScopeMultiplier(v)
		end
	end)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(100, 36)
	closeBtn.AnchorPoint = Vector2.new(1, 1)
	closeBtn.Position = UDim2.fromScale(1, 1)
	closeBtn.BackgroundColor3 = C.SURFACE_RAISED
	closeBtn.BorderSizePixel = 0
	closeBtn.TextColor3 = C.TEXT_DIM
	closeBtn.Font = F.LABEL
	closeBtn.TextSize = TS.BODY
	closeBtn.Text = "CLOSE"
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = content
	addCorner(closeBtn, R.MD)
	addStroke(closeBtn, C.BORDER, THIN)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, TWEEN_FAST, { TextColor3 = C.TEXT, BackgroundColor3 = C.SURFACE_HOVER }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, TWEEN_FAST, { TextColor3 = C.TEXT_DIM, BackgroundColor3 = C.SURFACE_RAISED })
			:Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	UserInputService.InputBegan:Connect(function(inp, gameProcessed)
		if gameProcessed then
			return
		end
		if inp.KeyCode == Enum.KeyCode.P then
			setOpen(not open)
		end
	end)
end

function SettingsMenu.isOpen(): boolean
	return open
end

return SettingsMenu

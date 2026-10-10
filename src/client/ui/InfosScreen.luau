local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.UITheme)

local InfosScreen = {}

local C = UITheme.Color
local F = UITheme.Font
local TS = UITheme.TextSize
local R = UITheme.Radius
local THIN = UITheme.Stroke.THIN
local STRIPE = UITheme.Stroke.STRIPE

local gui: ScreenGui
local onCloseCallback: (() -> ())?

local SECTIONS = {
	{
		title = "HOW TO SURF",
		lines = {
			"Approach a ramp and align yourself PARALLEL to its surface.",
			"Hold A or D to press into the ramp — never use W while surfing.",
			"Steer along the ramp's direction with your mouse to gain speed.",
			"Stay on the ramp's sweet spot: not too high, not too low.",
			"Chain ramps smoothly — use air strafes (A/D + mouse) between them.",
			"Never jump onto a ramp — let gravity carry you onto it.",
		},
	},
	{
		title = "CONTROLS",
		lines = {
			"W A S D    Movement",
			"Space      Jump / Bhop (hold for long jumps)",
			"Ctrl       Crouch",
			"Left Click Fire",
			"R          Reload",
			"Tab        Leaderboard",
			"P          Settings",
		},
	},
	{
		title = "CREDITS",
		lines = {
			"Physics inspired by the Source SDK (CS:GO surf).",
		},
	},
	{
		title = "ABOUT",
		lines = {
			"This game is a solo passion project by a web developer learning 3D and animation on the go.",
			"The goal isn't to clone CS:GO — it's to take what makes surf feel great and build something original on top of it.",
			"New weapons, skins, and animations are planned, all made from scratch with originality in mind.",
			"Thanks for playing while it's still rough around the edges.",
			"Want to give feedback or help out? Join the Discord: discord.gg/QK66g32mbB",
		},
	},
}

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

local function addSection(
	scroll: ScrollingFrame,
	yOffset: number,
	section: { title: string, lines: { string } }
): number
	local headerRow = Instance.new("Frame")
	headerRow.Size = UDim2.new(1, 0, 0, 26)
	headerRow.Position = UDim2.fromOffset(0, yOffset)
	headerRow.BackgroundTransparency = 1
	headerRow.Parent = scroll

	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(STRIPE, 14)
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromScale(0, 0.5)
	dot.BackgroundColor3 = C.ACCENT
	dot.BorderSizePixel = 0
	dot.Parent = headerRow
	addCorner(dot, R.SM)

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -10, 1, 0)
	header.Position = UDim2.fromOffset(10, 0)
	header.BackgroundTransparency = 1
	header.Text = section.title
	header.TextColor3 = C.ACCENT
	header.Font = F.LABEL
	header.TextSize = TS.LABEL
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = headerRow

	yOffset += 30

	for _, line in section.lines do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 20)
		lbl.Position = UDim2.fromOffset(0, yOffset)
		lbl.BackgroundTransparency = 1
		lbl.Text = line
		lbl.TextColor3 = C.TEXT_DIM
		lbl.Font = F.BODY
		lbl.TextSize = TS.BODY
		lbl.TextWrapped = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = scroll
		yOffset += 22
	end

	return yOffset + 18
end

function InfosScreen.init(onClose: () -> ())
	onCloseCallback = onClose

	gui = Instance.new("ScreenGui")
	gui.Name = "InfosScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = C.BG
	overlay.BackgroundTransparency = UITheme.Transparency.OVERLAY
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 480, 0.88, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = C.SURFACE
	panel.BorderSizePixel = 0
	panel.Parent = overlay
	addCorner(panel, R.LG)
	addStroke(panel, C.BORDER, THIN)

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, STRIPE, 0.8, 0)
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.fromScale(0, 0.5)
	stripe.BackgroundColor3 = C.ACCENT
	stripe.BorderSizePixel = 0
	stripe.Parent = panel
	addCorner(stripe, R.SM)

	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundTransparency = 1
	titleBar.Parent = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -56, 1, 0)
	titleLbl.Position = UDim2.fromOffset(UITheme.Space.LG, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "INFOS"
	titleLbl.TextColor3 = C.TEXT
	titleLbl.Font = F.DISPLAY
	titleLbl.TextSize = TS.TITLE
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(32, 32)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.BackgroundColor3 = C.SURFACE_RAISED
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = C.MUTED
	closeBtn.Font = F.LABEL
	closeBtn.TextSize = TS.BODY
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = titleBar
	addCorner(closeBtn, R.MD)
	addStroke(closeBtn, C.BORDER, THIN)

	closeBtn.MouseEnter:Connect(function()
		closeBtn.TextColor3 = C.TEXT
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.TextColor3 = C.MUTED
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if onCloseCallback then
			onCloseCallback()
		end
	end)

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -40, 0, 1)
	sep.Position = UDim2.fromOffset(20, 50)
	sep.BackgroundColor3 = C.BORDER
	sep.BorderSizePixel = 0
	sep.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -48, 1, -68)
	scroll.Position = UDim2.fromOffset(24, 60)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = STRIPE
	scroll.ScrollBarImageColor3 = C.ACCENT
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.Parent = panel

	local yOff = 8
	for _, section in SECTIONS do
		yOff = addSection(scroll, yOff, section)
	end
	scroll.CanvasSize = UDim2.fromOffset(0, yOff)
end

function InfosScreen.show()
	if gui then
		gui.Enabled = true
	end
end

function InfosScreen.hide()
	if gui then
		gui.Enabled = false
	end
end

return InfosScreen

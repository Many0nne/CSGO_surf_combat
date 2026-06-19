local InfosScreen = {}

local BG_COLOR   = Color3.fromRGB(12, 14, 20)
local TEXT_COLOR = Color3.fromRGB(210, 215, 225)
local MUTED      = Color3.fromRGB(120, 130, 150)
local ACCENT     = Color3.fromRGB(55, 85, 140)
local FONT       = Enum.Font.GothamBold
local FONT_L     = Enum.Font.Gotham

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
			"P     Settings",
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
			"Want to give feedback or help out? Join the Discord: https://discord.gg/QK66g32mbB",
		},
	},
}

local function addSection(scroll: ScrollingFrame, yOffset: number, section: { title: string, lines: { string } }): number
	local header = Instance.new("TextLabel")
	header.Size              = UDim2.new(1, 0, 0, 24)
	header.Position          = UDim2.fromOffset(0, yOffset)
	header.BackgroundTransparency = 1
	header.Text              = section.title
	header.TextColor3        = ACCENT
	header.Font              = FONT
	header.TextSize          = 13
	header.TextXAlignment    = Enum.TextXAlignment.Left
	header.Parent            = scroll
	yOffset += 28

	for _, line in section.lines do
		local lbl = Instance.new("TextLabel")
		lbl.Size              = UDim2.new(1, 0, 0, 18)
		lbl.Position          = UDim2.fromOffset(0, yOffset)
		lbl.BackgroundTransparency = 1
		lbl.Text              = "· " .. line
		lbl.TextColor3        = TEXT_COLOR
		lbl.Font              = FONT_L
		lbl.TextSize          = 13
		lbl.TextWrapped       = true
		lbl.TextXAlignment    = Enum.TextXAlignment.Left
		lbl.Parent            = scroll
		yOffset += 22
	end
	return yOffset + 16
end

function InfosScreen.init(onClose: () -> ())
	onCloseCallback = onClose

	gui = Instance.new("ScreenGui")
	gui.Name           = "InfosScreen"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled        = false
	gui.Parent         = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	-- Fond semi-transparent
	local overlay = Instance.new("Frame")
	overlay.Size             = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = BG_COLOR
	overlay.BackgroundTransparency = 0.1
	overlay.BorderSizePixel  = 0
	overlay.Parent           = gui

	-- Panneau
	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0, 460, 0.85, 0)
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.Position         = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	panel.BorderSizePixel  = 0
	panel.Parent           = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = panel

	-- En-tête
	local titleBar = Instance.new("Frame")
	titleBar.Size             = UDim2.new(1, 0, 0, 48)
	titleBar.BackgroundTransparency = 1
	titleBar.Parent           = panel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size             = UDim2.new(1, -48, 1, 0)
	titleLbl.Position         = UDim2.fromOffset(20, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text             = "INFOS"
	titleLbl.TextColor3       = TEXT_COLOR
	titleLbl.Font             = FONT
	titleLbl.TextSize         = 18
	titleLbl.TextXAlignment   = Enum.TextXAlignment.Left
	titleLbl.Parent           = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(0, 32, 0, 32)
	closeBtn.AnchorPoint      = Vector2.new(1, 0.5)
	closeBtn.Position         = UDim2.new(1, -12, 0.5, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
	closeBtn.BorderSizePixel  = 0
	closeBtn.Text             = "✕"
	closeBtn.TextColor3       = MUTED
	closeBtn.Font             = FONT
	closeBtn.TextSize         = 16
	closeBtn.AutoButtonColor  = true
	closeBtn.Parent           = titleBar
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 4)
	cc.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		if onCloseCallback then onCloseCallback() end
	end)

	-- Séparateur
	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, -40, 0, 1)
	sep.Position         = UDim2.new(0, 20, 0, 48)
	sep.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
	sep.BorderSizePixel  = 0
	sep.Parent           = panel

	-- Contenu scrollable
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size                   = UDim2.new(1, -40, 1, -68)
	scroll.Position               = UDim2.new(0, 20, 0, 58)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 4
	scroll.ScrollBarImageColor3   = Color3.fromRGB(55, 85, 140)
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.Parent                 = panel

	local yOff = 8
	for _, section in SECTIONS do
		yOff = addSection(scroll, yOff, section)
	end
	scroll.CanvasSize = UDim2.new(0, 0, 0, yOff)
end

function InfosScreen.show()
	if gui then gui.Enabled = true end
end

function InfosScreen.hide()
	if gui then gui.Enabled = false end
end

return InfosScreen

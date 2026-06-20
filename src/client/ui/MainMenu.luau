local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")

local MainMenu = {}

local BG         = Color3.fromRGB(9, 13, 20)
local SURFACE    = Color3.fromRGB(14, 20, 32)
local BORDER     = Color3.fromRGB(28, 42, 62)
local ACCENT     = Color3.fromRGB(205, 38, 38)
local ACCENT_HOV = Color3.fromRGB(228, 68, 68)
local TEXT       = Color3.fromRGB(220, 230, 245)
local MUTED      = Color3.fromRGB(72, 92, 120)
local BTN_BG     = Color3.fromRGB(18, 28, 44)

local FONT_BLK = Enum.Font.GothamBlack
local FONT_BD  = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

local TWEEN_FAST = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui: ScreenGui
local onPlayCallback:     (() -> ())?
local onInfosCallback:    (() -> ())?
local onFeedbackCallback: (() -> ())?

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

local function makeGhostButton(parent: Instance, text: string, yOff: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(1, 0, 0, 40)
	btn.Position         = UDim2.fromOffset(0, yOff)
	btn.BackgroundColor3 = BTN_BG
	btn.BorderSizePixel  = 0
	btn.Text             = text
	btn.TextColor3       = MUTED
	btn.Font             = FONT_BD
	btn.TextSize         = 13
	btn.AutoButtonColor  = false
	btn.Parent           = parent
	addCorner(btn, 3)
	addStroke(btn, BORDER, 1)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TWEEN_FAST, { TextColor3 = TEXT, BackgroundColor3 = Color3.fromRGB(24, 36, 56) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TWEEN_FAST, { TextColor3 = MUTED, BackgroundColor3 = BTN_BG }):Play()
	end)
	return btn
end

function MainMenu.init(onPlay: () -> (), onInfos: () -> (), onFeedback: () -> ())
	onPlayCallback     = onPlay
	onInfosCallback    = onInfos
	onFeedbackCallback = onFeedback

	gui = Instance.new("ScreenGui")
	gui.Name           = "MainMenu"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent         = Players.LocalPlayer:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG
	bg.BorderSizePixel  = 0
	bg.Parent           = gui

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 18, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 9, 15)),
	})
	bgGrad.Rotation = 135
	bgGrad.Parent   = bg

	local card = Instance.new("Frame")
	card.Size             = UDim2.fromOffset(300, 318)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.Position         = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = SURFACE
	card.BorderSizePixel  = 0
	card.Parent           = bg
	addCorner(card, 6)
	addStroke(card, BORDER, 1)

	-- Left accent stripe (signature element)
	local stripe = Instance.new("Frame")
	stripe.Size             = UDim2.new(0, 3, 0.64, 0)
	stripe.AnchorPoint      = Vector2.new(0, 0.5)
	stripe.Position         = UDim2.new(0, 0, 0.5, 0)
	stripe.BackgroundColor3 = ACCENT
	stripe.BorderSizePixel  = 0
	stripe.Parent           = card
	addCorner(stripe, 2)

	local content = Instance.new("Frame")
	content.Size                   = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel        = 0
	content.Parent                 = card

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 32)
	pad.PaddingRight  = UDim.new(0, 24)
	pad.PaddingTop    = UDim.new(0, 30)
	pad.PaddingBottom = UDim.new(0, 24)
	pad.Parent        = content

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Size              = UDim2.new(1, 0, 0, 14)
	eyebrow.Position          = UDim2.fromOffset(0, 0)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Text              = "SURF · FFA"
	eyebrow.TextColor3        = ACCENT
	eyebrow.Font              = FONT_BD
	eyebrow.TextSize          = 11
	eyebrow.TextXAlignment    = Enum.TextXAlignment.Left
	eyebrow.Parent            = content

	local title = Instance.new("TextLabel")
	title.Size              = UDim2.new(1, 0, 0, 50)
	title.Position          = UDim2.fromOffset(0, 18)
	title.BackgroundTransparency = 1
	title.Text              = "SURF FFA"
	title.TextColor3        = TEXT
	title.Font              = FONT_BLK
	title.TextSize          = 38
	title.TextXAlignment    = Enum.TextXAlignment.Left
	title.Parent            = content

	local div = Instance.new("Frame")
	div.Size             = UDim2.new(1, 0, 0, 1)
	div.Position         = UDim2.fromOffset(0, 76)
	div.BackgroundColor3 = BORDER
	div.BorderSizePixel  = 0
	div.Parent           = content

	local playBtn = Instance.new("TextButton")
	playBtn.Size             = UDim2.new(1, 0, 0, 46)
	playBtn.Position         = UDim2.fromOffset(0, 94)
	playBtn.BackgroundColor3 = ACCENT
	playBtn.BorderSizePixel  = 0
	playBtn.Text             = "PLAY"
	playBtn.TextColor3       = Color3.fromRGB(240, 230, 230)
	playBtn.Font             = FONT_BLK
	playBtn.TextSize         = 16
	playBtn.AutoButtonColor  = false
	playBtn.Parent           = content
	addCorner(playBtn, 3)

	playBtn.MouseEnter:Connect(function()
		TweenService:Create(playBtn, TWEEN_FAST, { BackgroundColor3 = ACCENT_HOV }):Play()
	end)
	playBtn.MouseLeave:Connect(function()
		TweenService:Create(playBtn, TWEEN_FAST, { BackgroundColor3 = ACCENT }):Play()
	end)

	local infosBtn    = makeGhostButton(content, "INFOS",    150)
	local feedbackBtn = makeGhostButton(content, "FEEDBACK", 198)

	playBtn.MouseButton1Click:Connect(function()
		if onPlayCallback then onPlayCallback() end
	end)
	infosBtn.MouseButton1Click:Connect(function()
		if onInfosCallback then onInfosCallback() end
	end)
	feedbackBtn.MouseButton1Click:Connect(function()
		if onFeedbackCallback then onFeedbackCallback() end
	end)

	local ver = Instance.new("TextLabel")
	ver.Size              = UDim2.fromOffset(50, 14)
	ver.AnchorPoint       = Vector2.new(1, 1)
	ver.Position          = UDim2.new(1, -10, 1, -8)
	ver.BackgroundTransparency = 1
	ver.Text              = "v0.1"
	ver.TextColor3        = Color3.fromRGB(32, 48, 68)
	ver.Font              = FONT_REG
	ver.TextSize          = 11
	ver.TextXAlignment    = Enum.TextXAlignment.Right
	ver.Parent            = bg
end

function MainMenu.show()
	if gui then gui.Enabled = true end
end

function MainMenu.hide()
	if gui then gui.Enabled = false end
end

return MainMenu

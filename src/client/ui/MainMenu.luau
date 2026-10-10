local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.UITheme)

local MainMenu = {}

local C = UITheme.Color
local F = UITheme.Font
local TS = UITheme.TextSize
local R = UITheme.Radius

local TWEEN_FAST = TweenInfo.new(UITheme.Motion.FAST, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui: ScreenGui
local onPlayCallback: (() -> ())?
local onInfosCallback: (() -> ())?
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
	btn.Size = UDim2.new(1, 0, 0, 40)
	btn.Position = UDim2.fromOffset(0, yOff)
	btn.BackgroundColor3 = C.SURFACE_RAISED
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = C.TEXT_DIM
	btn.Font = F.LABEL
	btn.TextSize = TS.BODY
	btn.AutoButtonColor = false
	btn.Parent = parent
	addCorner(btn, R.MD)
	addStroke(btn, C.BORDER, UITheme.Stroke.THIN)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TWEEN_FAST, { TextColor3 = C.TEXT, BackgroundColor3 = C.SURFACE_HOVER }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TWEEN_FAST, { TextColor3 = C.TEXT_DIM, BackgroundColor3 = C.SURFACE_RAISED }):Play()
	end)
	return btn
end

function MainMenu.init(onPlay: () -> (), onInfos: () -> (), onFeedback: () -> ())
	onPlayCallback = onPlay
	onInfosCallback = onInfos
	onFeedbackCallback = onFeedback

	gui = Instance.new("ScreenGui")
	gui.Name = "MainMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.BG
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.BG_GRAD_TOP),
		ColorSequenceKeypoint.new(1, C.BG_GRAD_BOTTOM),
	})
	bgGrad.Rotation = 135
	bgGrad.Parent = bg

	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(300, 318)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = C.SURFACE
	card.BorderSizePixel = 0
	card.Parent = bg
	addCorner(card, R.LG)
	addStroke(card, C.BORDER, UITheme.Stroke.THIN)

	-- Left accent stripe (signature element)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, UITheme.Stroke.STRIPE, 0.64, 0)
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.fromScale(0, 0.5)
	stripe.BackgroundColor3 = C.ACCENT
	stripe.BorderSizePixel = 0
	stripe.Parent = card
	addCorner(stripe, R.SM)

	local content = Instance.new("Frame")
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UITheme.Space.XL)
	pad.PaddingRight = UDim.new(0, UITheme.Space.LG)
	pad.PaddingTop = UDim.new(0, 30)
	pad.PaddingBottom = UDim.new(0, UITheme.Space.LG)
	pad.Parent = content

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Size = UDim2.new(1, 0, 0, 14)
	eyebrow.Position = UDim2.fromOffset(0, 0)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Text = UITheme.Brand.TAGLINE
	eyebrow.TextColor3 = C.ACCENT
	eyebrow.Font = F.LABEL
	eyebrow.TextSize = TS.LABEL
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.Parent = content

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 50)
	title.Position = UDim2.fromOffset(0, 18)
	title.BackgroundTransparency = 1
	title.Text = UITheme.Brand.NAME
	title.TextColor3 = C.TEXT
	title.Font = F.DISPLAY
	title.TextSize = TS.LOGO
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = content

	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.fromOffset(0, 76)
	div.BackgroundColor3 = C.BORDER
	div.BorderSizePixel = 0
	div.Parent = content

	local playBtn = Instance.new("TextButton")
	playBtn.Size = UDim2.new(1, 0, 0, 46)
	playBtn.Position = UDim2.fromOffset(0, 94)
	playBtn.BackgroundColor3 = C.ACCENT
	playBtn.BorderSizePixel = 0
	playBtn.Text = "PLAY"
	playBtn.TextColor3 = C.ON_ACCENT
	playBtn.Font = F.HEADING
	playBtn.TextSize = TS.BUTTON
	playBtn.AutoButtonColor = false
	playBtn.Parent = content
	addCorner(playBtn, R.MD)

	playBtn.MouseEnter:Connect(function()
		TweenService:Create(playBtn, TWEEN_FAST, { BackgroundColor3 = C.ACCENT_HOVER }):Play()
	end)
	playBtn.MouseLeave:Connect(function()
		TweenService:Create(playBtn, TWEEN_FAST, { BackgroundColor3 = C.ACCENT }):Play()
	end)

	local infosBtn = makeGhostButton(content, "INFOS", 150)
	local feedbackBtn = makeGhostButton(content, "FEEDBACK", 198)

	playBtn.MouseButton1Click:Connect(function()
		if onPlayCallback then
			onPlayCallback()
		end
	end)
	infosBtn.MouseButton1Click:Connect(function()
		if onInfosCallback then
			onInfosCallback()
		end
	end)
	feedbackBtn.MouseButton1Click:Connect(function()
		if onFeedbackCallback then
			onFeedbackCallback()
		end
	end)

	local ver = Instance.new("TextLabel")
	ver.Size = UDim2.fromOffset(50, 14)
	ver.AnchorPoint = Vector2.new(1, 1)
	ver.Position = UDim2.new(1, -10, 1, -8)
	ver.BackgroundTransparency = 1
	ver.Text = UITheme.Brand.VERSION
	ver.TextColor3 = C.FAINT
	ver.Font = F.BODY
	ver.TextSize = TS.LABEL
	ver.TextXAlignment = Enum.TextXAlignment.Right
	ver.Parent = bg
end

function MainMenu.show()
	if gui then
		gui.Enabled = true
	end
end

function MainMenu.hide()
	if gui then
		gui.Enabled = false
	end
end

return MainMenu

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Shared          = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))

local FeedbackModal = {}

local SURFACE    = Color3.fromRGB(14, 20, 32)
local PANEL      = Color3.fromRGB(18, 26, 40)
local BORDER     = Color3.fromRGB(28, 42, 62)
local ACCENT     = Color3.fromRGB(205, 38, 38)
local ACCENT_HOV = Color3.fromRGB(228, 68, 68)
local OK_COLOR   = Color3.fromRGB(60, 200, 100)
local ERR_COLOR  = Color3.fromRGB(235, 80, 60)
local TEXT       = Color3.fromRGB(220, 230, 245)
local MUTED      = Color3.fromRGB(72, 92, 120)
local BTN_BG     = Color3.fromRGB(18, 28, 44)

local FONT_BLK = Enum.Font.GothamBlack
local FONT_BD  = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

local TWEEN_FAST = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local MIN_CHARS = 10
local MAX_CHARS = 500

local gui:            ScreenGui
local textBox:        TextBox
local sendBtn:        TextButton
local statusLabel:    TextLabel
local charCountLabel: TextLabel
local sending = false

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

local function setStatus(msg: string, color: Color3?)
	statusLabel.Text       = msg
	statusLabel.TextColor3 = color or MUTED
	statusLabel.Visible    = msg ~= ""
end

local function resetState()
	sending             = false
	sendBtn.Text        = "ENVOYER"
	sendBtn.Active      = true
	textBox.Text        = ""
	charCountLabel.Text = "0 / " .. MAX_CHARS
	setStatus("")
end

function FeedbackModal.init()
	local N       = NetworkProtocol.Names
	local sendRmt = NetworkProtocol.getRemote(N.SEND_FEEDBACK)
	local ackRmt  = NetworkProtocol.getRemote(N.FEEDBACK_ACK)

	gui = Instance.new("ScreenGui")
	gui.Name           = "FeedbackModal"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 10
	gui.Enabled        = false
	gui.Parent         = Players.LocalPlayer:WaitForChild("PlayerGui")

	local overlay = Instance.new("Frame")
	overlay.Size                   = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.55
	overlay.BorderSizePixel        = 0
	overlay.Parent                 = gui

	-- Card
	local card = Instance.new("Frame")
	card.Size             = UDim2.fromOffset(340, 318)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.Position         = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = SURFACE
	card.BorderSizePixel  = 0
	card.Parent           = overlay
	addCorner(card, 6)
	addStroke(card, BORDER, 1)

	-- Left accent stripe
	local stripe = Instance.new("Frame")
	stripe.Size             = UDim2.new(0, 3, 0.65, 0)
	stripe.AnchorPoint      = Vector2.new(0, 0.5)
	stripe.Position         = UDim2.new(0, 0, 0.5, 0)
	stripe.BackgroundColor3 = ACCENT
	stripe.BorderSizePixel  = 0
	stripe.Parent           = card
	addCorner(stripe, 2)

	-- Content (padded)
	local content = Instance.new("Frame")
	content.Size                   = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel        = 0
	content.Parent                 = card

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft   = UDim.new(0, 28)
	pad.PaddingRight  = UDim.new(0, 24)
	pad.PaddingTop    = UDim.new(0, 26)
	pad.PaddingBottom = UDim.new(0, 24)
	pad.Parent        = content

	-- Title
	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, 0, 0, 24)
	title.Position               = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.Text                   = "FEEDBACK"
	title.TextColor3             = TEXT
	title.Font                   = FONT_BLK
	title.TextSize               = 20
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.Parent                 = content

	local sub = Instance.new("TextLabel")
	sub.Size                   = UDim2.new(1, 0, 0, 16)
	sub.Position               = UDim2.fromOffset(0, 28)
	sub.BackgroundTransparency = 1
	sub.Text                   = "Signale un bug ou partage une idée"
	sub.TextColor3             = MUTED
	sub.Font                   = FONT_REG
	sub.TextSize               = 12
	sub.TextXAlignment         = Enum.TextXAlignment.Left
	sub.Parent                 = content

	-- TextBox frame
	local tbFrame = Instance.new("Frame")
	tbFrame.Size             = UDim2.new(1, 0, 0, 118)
	tbFrame.Position         = UDim2.fromOffset(0, 56)
	tbFrame.BackgroundColor3 = PANEL
	tbFrame.BorderSizePixel  = 0
	tbFrame.Parent           = content
	addCorner(tbFrame, 4)
	addStroke(tbFrame, BORDER, 1)

	textBox = Instance.new("TextBox")
	textBox.Size                = UDim2.new(1, -16, 1, -16)
	textBox.Position            = UDim2.fromOffset(8, 8)
	textBox.BackgroundTransparency = 1
	textBox.Text                = ""
	textBox.PlaceholderText     = "Ton message (10 à 500 caractères)..."
	textBox.TextColor3          = TEXT
	textBox.PlaceholderColor3   = MUTED
	textBox.Font                = FONT_REG
	textBox.TextSize            = 13
	textBox.TextWrapped         = true
	textBox.MultiLine           = true
	textBox.ClearTextOnFocus    = false
	textBox.TextXAlignment      = Enum.TextXAlignment.Left
	textBox.TextYAlignment      = Enum.TextYAlignment.Top
	textBox.Parent              = tbFrame

	-- Char count + status row
	charCountLabel = Instance.new("TextLabel")
	charCountLabel.Size                   = UDim2.new(0.5, 0, 0, 16)
	charCountLabel.AnchorPoint            = Vector2.new(1, 0)
	charCountLabel.Position               = UDim2.new(1, 0, 0, 184)
	charCountLabel.BackgroundTransparency = 1
	charCountLabel.Text                   = "0 / " .. MAX_CHARS
	charCountLabel.TextColor3             = MUTED
	charCountLabel.Font                   = FONT_REG
	charCountLabel.TextSize               = 11
	charCountLabel.TextXAlignment         = Enum.TextXAlignment.Right
	charCountLabel.Parent                 = content

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size                   = UDim2.new(0.55, 0, 0, 16)
	statusLabel.Position               = UDim2.fromOffset(0, 184)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text                   = ""
	statusLabel.TextColor3             = MUTED
	statusLabel.Font                   = FONT_REG
	statusLabel.TextSize               = 11
	statusLabel.TextXAlignment         = Enum.TextXAlignment.Left
	statusLabel.Visible                = false
	statusLabel.Parent                 = content

	-- Cancel button (ghost)
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Size             = UDim2.new(0.46, 0, 0, 40)
	cancelBtn.Position         = UDim2.fromOffset(0, 210)
	cancelBtn.BackgroundColor3 = BTN_BG
	cancelBtn.BorderSizePixel  = 0
	cancelBtn.Text             = "ANNULER"
	cancelBtn.TextColor3       = MUTED
	cancelBtn.Font             = FONT_BD
	cancelBtn.TextSize         = 13
	cancelBtn.AutoButtonColor  = false
	cancelBtn.Parent           = content
	addCorner(cancelBtn, 3)
	addStroke(cancelBtn, BORDER, 1)

	cancelBtn.MouseEnter:Connect(function()
		TweenService:Create(cancelBtn, TWEEN_FAST, { TextColor3 = TEXT, BackgroundColor3 = Color3.fromRGB(24, 36, 56) }):Play()
	end)
	cancelBtn.MouseLeave:Connect(function()
		TweenService:Create(cancelBtn, TWEEN_FAST, { TextColor3 = MUTED, BackgroundColor3 = BTN_BG }):Play()
	end)

	-- Send button (filled red)
	sendBtn = Instance.new("TextButton")
	sendBtn.Size             = UDim2.new(0.46, 0, 0, 40)
	sendBtn.AnchorPoint      = Vector2.new(1, 0)
	sendBtn.Position         = UDim2.new(1, 0, 0, 210)
	sendBtn.BackgroundColor3 = ACCENT
	sendBtn.BorderSizePixel  = 0
	sendBtn.Text             = "ENVOYER"
	sendBtn.TextColor3       = Color3.fromRGB(240, 230, 230)
	sendBtn.Font             = FONT_BLK
	sendBtn.TextSize         = 14
	sendBtn.AutoButtonColor  = false
	sendBtn.Parent           = content
	addCorner(sendBtn, 3)

	sendBtn.MouseEnter:Connect(function()
		if sendBtn.Active then
			TweenService:Create(sendBtn, TWEEN_FAST, { BackgroundColor3 = ACCENT_HOV }):Play()
		end
	end)
	sendBtn.MouseLeave:Connect(function()
		TweenService:Create(sendBtn, TWEEN_FAST, { BackgroundColor3 = ACCENT }):Play()
	end)

	-- Connections
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local len = #textBox.Text
		if len > MAX_CHARS then
			textBox.Text = textBox.Text:sub(1, MAX_CHARS)
			len = MAX_CHARS
		end
		charCountLabel.Text       = len .. " / " .. MAX_CHARS
		charCountLabel.TextColor3 = len >= MIN_CHARS and TEXT or MUTED
	end)

	cancelBtn.MouseButton1Click:Connect(function()
		FeedbackModal.hide()
	end)

	sendBtn.MouseButton1Click:Connect(function()
		if sending then return end
		local text = textBox.Text:match("^%s*(.-)%s*$")
		if #text < MIN_CHARS then
			setStatus("Message trop court (min. " .. MIN_CHARS .. " car.).", ERR_COLOR)
			return
		end
		sending        = true
		sendBtn.Text   = "ENVOI..."
		sendBtn.Active = false
		setStatus("")
		sendRmt:FireServer(textBox.Text)
	end)

	ackRmt.OnClientEvent:Connect(function(success: boolean, message: string)
		if success then
			setStatus(message, OK_COLOR)
			textBox.Text = ""
			task.delay(2, function()
				if gui and gui.Enabled then
					FeedbackModal.hide()
				end
			end)
		else
			setStatus(message, ERR_COLOR)
		end
		sending        = false
		sendBtn.Text   = "ENVOYER"
		sendBtn.Active = true
	end)
end

function FeedbackModal.show()
	if gui then
		resetState()
		gui.Enabled = true
		task.defer(function()
			if textBox then textBox:CaptureFocus() end
		end)
	end
end

function FeedbackModal.hide()
	if gui then gui.Enabled = false end
end

return FeedbackModal

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared          = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))

local FeedbackModal = {}

local BG_COLOR     = Color3.fromRGB(12, 14, 20)
local CARD_COLOR   = Color3.fromRGB(20, 24, 34)
local TEXT_COLOR   = Color3.fromRGB(210, 215, 225)
local ACCENT_COLOR = Color3.fromRGB(55, 85, 140)
local MUTED_COLOR  = Color3.fromRGB(100, 110, 130)
local ERROR_COLOR  = Color3.fromRGB(200, 80, 80)
local OK_COLOR     = Color3.fromRGB(80, 200, 100)
local FONT         = Enum.Font.GothamBold
local FONT_LIGHT   = Enum.Font.Gotham

local MIN_CHARS = 10
local MAX_CHARS = 500

local gui:           ScreenGui
local textBox:       TextBox
local sendBtn:       TextButton
local statusLabel:   TextLabel
local charCountLabel: TextLabel
local sending = false

local function setStatus(msg: string, color: Color3?)
	statusLabel.Text       = msg
	statusLabel.TextColor3 = color or MUTED_COLOR
	statusLabel.Visible    = msg ~= ""
end

local function resetState()
	sending          = false
	sendBtn.Text     = "ENVOYER"
	sendBtn.Active   = true
	textBox.Text     = ""
	charCountLabel.Text = "0 / " .. MAX_CHARS
	setStatus("")
end

function FeedbackModal.init()
	local N    = NetworkProtocol.Names
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

	-- Overlay semi-transparent
	local overlay = Instance.new("Frame")
	overlay.Size                  = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel       = 0
	overlay.Parent                = gui

	-- Carte modale
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 320, 0, 300)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.Position         = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = CARD_COLOR
	card.BorderSizePixel  = 0
	card.Parent           = overlay
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent       = card

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0, 24)
	padding.PaddingRight  = UDim.new(0, 24)
	padding.PaddingTop    = UDim.new(0, 24)
	padding.PaddingBottom = UDim.new(0, 24)
	padding.Parent        = card

	-- Titre
	local title = Instance.new("TextLabel")
	title.Size                 = UDim2.new(1, 0, 0, 32)
	title.Position             = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.Text                 = "FEEDBACK"
	title.TextColor3           = TEXT_COLOR
	title.Font                 = FONT
	title.TextSize             = 20
	title.TextXAlignment       = Enum.TextXAlignment.Left
	title.Parent               = card

	-- Sous-titre
	local sub = Instance.new("TextLabel")
	sub.Size                 = UDim2.new(1, 0, 0, 18)
	sub.Position             = UDim2.fromOffset(0, 36)
	sub.BackgroundTransparency = 1
	sub.Text                 = "Signale un bug ou partage une idée"
	sub.TextColor3           = MUTED_COLOR
	sub.Font                 = FONT_LIGHT
	sub.TextSize             = 12
	sub.TextXAlignment       = Enum.TextXAlignment.Left
	sub.Parent               = card

	-- Cadre TextBox
	local tbFrame = Instance.new("Frame")
	tbFrame.Size             = UDim2.new(1, 0, 0, 110)
	tbFrame.Position         = UDim2.fromOffset(0, 66)
	tbFrame.BackgroundColor3 = BG_COLOR
	tbFrame.BorderSizePixel  = 0
	tbFrame.Parent           = card
	local tbCorner = Instance.new("UICorner")
	tbCorner.CornerRadius = UDim.new(0, 6)
	tbCorner.Parent       = tbFrame

	textBox = Instance.new("TextBox")
	textBox.Size                = UDim2.new(1, -16, 1, -16)
	textBox.Position            = UDim2.fromOffset(8, 8)
	textBox.BackgroundTransparency = 1
	textBox.Text                = ""
	textBox.PlaceholderText     = "Ton message (10 à 500 caractères)..."
	textBox.TextColor3          = TEXT_COLOR
	textBox.PlaceholderColor3   = MUTED_COLOR
	textBox.Font                = FONT_LIGHT
	textBox.TextSize            = 13
	textBox.TextWrapped         = true
	textBox.MultiLine           = true
	textBox.ClearTextOnFocus    = false
	textBox.TextXAlignment      = Enum.TextXAlignment.Left
	textBox.TextYAlignment      = Enum.TextYAlignment.Top
	textBox.Parent              = tbFrame

	-- Compteur de caractères
	charCountLabel = Instance.new("TextLabel")
	charCountLabel.Size                 = UDim2.new(1, 0, 0, 16)
	charCountLabel.Position             = UDim2.fromOffset(0, 182)
	charCountLabel.BackgroundTransparency = 1
	charCountLabel.Text                 = "0 / " .. MAX_CHARS
	charCountLabel.TextColor3           = MUTED_COLOR
	charCountLabel.Font                 = FONT_LIGHT
	charCountLabel.TextSize             = 11
	charCountLabel.TextXAlignment       = Enum.TextXAlignment.Right
	charCountLabel.Parent               = card

	-- Message de statut (succès / erreur)
	statusLabel = Instance.new("TextLabel")
	statusLabel.Size                 = UDim2.new(1, 0, 0, 16)
	statusLabel.Position             = UDim2.fromOffset(0, 182)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text                 = ""
	statusLabel.TextColor3           = MUTED_COLOR
	statusLabel.Font                 = FONT_LIGHT
	statusLabel.TextSize             = 11
	statusLabel.TextXAlignment       = Enum.TextXAlignment.Left
	statusLabel.Visible              = false
	statusLabel.Parent               = card

	-- Bouton Annuler
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Size             = UDim2.new(0.45, 0, 0, 40)
	cancelBtn.Position         = UDim2.fromOffset(0, 206)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
	cancelBtn.BorderSizePixel  = 0
	cancelBtn.Text             = "ANNULER"
	cancelBtn.TextColor3       = TEXT_COLOR
	cancelBtn.Font             = FONT
	cancelBtn.TextSize         = 14
	cancelBtn.AutoButtonColor  = true
	cancelBtn.Parent           = card
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 4)
	cancelCorner.Parent       = cancelBtn

	-- Bouton Envoyer
	sendBtn = Instance.new("TextButton")
	sendBtn.Size             = UDim2.new(0.45, 0, 0, 40)
	sendBtn.AnchorPoint      = Vector2.new(1, 0)
	sendBtn.Position         = UDim2.new(1, 0, 0, 206)
	sendBtn.BackgroundColor3 = ACCENT_COLOR
	sendBtn.BorderSizePixel  = 0
	sendBtn.Text             = "ENVOYER"
	sendBtn.TextColor3       = TEXT_COLOR
	sendBtn.Font             = FONT
	sendBtn.TextSize         = 14
	sendBtn.AutoButtonColor  = true
	sendBtn.Parent           = card
	local sendCorner = Instance.new("UICorner")
	sendCorner.CornerRadius = UDim.new(0, 4)
	sendCorner.Parent       = sendBtn

	-- Connexions
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local len = #textBox.Text
		if len > MAX_CHARS then
			textBox.Text = textBox.Text:sub(1, MAX_CHARS)
			len = MAX_CHARS
		end
		charCountLabel.Text      = len .. " / " .. MAX_CHARS
		charCountLabel.TextColor3 = len >= MIN_CHARS and TEXT_COLOR or MUTED_COLOR
	end)

	cancelBtn.MouseButton1Click:Connect(function()
		FeedbackModal.hide()
	end)

	sendBtn.MouseButton1Click:Connect(function()
		if sending then return end
		local text = textBox.Text:match("^%s*(.-)%s*$")
		if #text < MIN_CHARS then
			setStatus("Message trop court (min. " .. MIN_CHARS .. " car.).", ERROR_COLOR)
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
			setStatus(message, ERROR_COLOR)
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

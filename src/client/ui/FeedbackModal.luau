-- Modale Feedback (direction « Tactical ») : message de 10 à 500 caractères envoyé au serveur.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion

local FeedbackModal = {}

local MIN_CHARS = 10
local MAX_CHARS = 500
local PANEL_SIZE = Vector2.new(540, 336)

local gui: ScreenGui
local overlay: Frame
local card: CanvasGroup
local textBox: TextBox
local sendBtn: TextButton
local statusLabel: TextLabel
local charCountLabel: TextLabel
local sending = false

-- Cette méthode permet d'afficher un message d'état sous les boutons lorsque l'envoi échoue ou réussit.
local function setStatus(msg: string, color: Color3?)
	statusLabel.Text = msg
	statusLabel.TextColor3 = color or C.Muted
	statusLabel.Visible = msg ~= ""
end

-- Cette méthode permet de mettre à jour le compteur et l'état du bouton Envoyer lorsque le texte change.
local function refreshCount()
	local len = #textBox.Text
	charCountLabel.Text = len .. " / " .. MAX_CHARS
	local valid = len >= MIN_CHARS
	charCountLabel.TextColor3 = valid and C.Accent or C.Muted
	if not sending then
		UIKit.setAccentEnabled(sendBtn, valid)
	end
end

-- Cette méthode permet de remettre la modale à zéro (texte, bouton, statut) lorsqu'elle s'ouvre.
local function resetState()
	sending = false
	sendBtn.Text = "ENVOYER"
	textBox.Text = ""
	setStatus("")
	refreshCount()
end

function FeedbackModal.init()
	local N = NetworkProtocol.Names
	local sendRmt = NetworkProtocol.getRemote(N.SEND_FEEDBACK)
	local ackRmt = NetworkProtocol.getRemote(N.FEEDBACK_ACK)

	gui = UIKit.create("ScreenGui", {
		Name = "FeedbackModal",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = UIKit.scaledRoot(gui)

	overlay = UIKit.frame({
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 12, 14),
		BackgroundTransparency = 0.28,
		Parent = root,
	})

	card = UIKit.create("CanvasGroup", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Parent = root,
	})
	UIKit.stroke(card, C.BorderStrong)
	UIKit.frame({ Name = "TopLine", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C.Accent, Parent = card })

	UIKit.text({
		Text = "FEEDBACK",
		FontFace = F.Display,
		TextSize = T.H2,
		Position = UDim2.fromOffset(26, 22),
		Size = UDim2.new(1, -110, 0, 36),
		Parent = card,
	})
	UIKit.text({
		Text = "Signale un bug ou partage une idée",
		TextSize = 15,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(26, 58),
		Size = UDim2.new(1, -110, 0, 20),
		Parent = card,
	})
	local close = UIKit.closeButton(card)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -26, 0, 22)
	close.MouseButton1Click:Connect(function()
		FeedbackModal.hide()
	end)

	local tbFrame = UIKit.frame({
		Name = "Message",
		Position = UDim2.fromOffset(26, 94),
		Size = UDim2.new(1, -52, 0, 150),
		BackgroundColor3 = C.Ground,
		Parent = card,
	})
	local tbStroke = UIKit.stroke(tbFrame, C.BorderStrong)
	textBox = UIKit.create("TextBox", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 1, -20),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Ton message (10 à 500 caractères)…",
		PlaceholderColor3 = C.Muted,
		TextColor3 = C.Text,
		FontFace = F.Body,
		TextSize = 15,
		TextWrapped = true,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = tbFrame,
	})
	textBox.Focused:Connect(function()
		UIKit.tween(tbStroke, Motion.Hover, { Color = C.Accent })
	end)
	textBox.FocusLost:Connect(function()
		UIKit.tween(tbStroke, Motion.Hover, { Color = C.BorderStrong })
	end)

	charCountLabel = UIKit.text({
		Text = "0 / " .. MAX_CHARS,
		FontFace = F.Mono,
		TextSize = T.Caption,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(26, 258),
		Size = UDim2.fromOffset(120, 44),
		Parent = card,
	})
	sendBtn = UIKit.accentButton(card, "ENVOYER", UDim2.fromOffset(120, 44))
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, -26, 0, 258)
	local cancelBtn = UIKit.ghostButton(card, "ANNULER", UDim2.fromOffset(120, 44))
	cancelBtn.AnchorPoint = Vector2.new(1, 0)
	cancelBtn.Position = UDim2.new(1, -156, 0, 258)

	statusLabel = UIKit.text({
		Text = "",
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(26, 308),
		Size = UDim2.new(1, -52, 0, 18),
		Visible = false,
		Parent = card,
	})

	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #textBox.Text > MAX_CHARS then
			textBox.Text = textBox.Text:sub(1, MAX_CHARS)
			return
		end
		refreshCount()
	end)

	cancelBtn.MouseButton1Click:Connect(function()
		FeedbackModal.hide()
	end)

	sendBtn.MouseButton1Click:Connect(function()
		if sending then
			return
		end
		local text = textBox.Text:match("^%s*(.-)%s*$")
		if #text < MIN_CHARS then
			setStatus("Message trop court (min. " .. MIN_CHARS .. " car.).", C.Alert)
			return
		end
		sending = true
		sendBtn.Text = "ENVOI..."
		UIKit.setAccentEnabled(sendBtn, false)
		setStatus("")
		sendRmt:FireServer(textBox.Text)
	end)

	ackRmt.OnClientEvent:Connect(function(success: boolean, message: string)
		sending = false
		sendBtn.Text = "ENVOYER"
		if success then
			setStatus(message, C.Success)
			textBox.Text = ""
			task.delay(2, function()
				if gui and gui.Enabled then
					FeedbackModal.hide()
				end
			end)
		else
			setStatus(message, C.Alert)
		end
		refreshCount()
	end)

	resetState()
end

function FeedbackModal.show()
	if not gui then
		return
	end
	resetState()
	gui.Enabled = true
	overlay.BackgroundTransparency = 1
	UIKit.tween(overlay, Motion.Enter, { BackgroundTransparency = 0.28 })
	UIKit.reveal(card, 0, 24)
	task.defer(function()
		if textBox then
			textBox:CaptureFocus()
		end
	end)
end

function FeedbackModal.hide()
	if gui then
		gui.Enabled = false
	end
end

return FeedbackModal

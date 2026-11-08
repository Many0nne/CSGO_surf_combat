-- Écran Feedback (direction « Ligne de mire ») : message de 10 à 500 caractères envoyé au serveur, ENVOYER se tire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local MenuPage = require(script.Parent.MenuPage)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion

local FeedbackScreen = {}

local MIN_CHARS = 10
local MAX_CHARS = 500
local FIELD_WIDTH = 640
local FIELD_TOP = MenuPage.ContentTop + 34
local FIELD_HEIGHT = 270
local ACTION_SIZE = 30
local ACTION_GAP = 46
local CLOSE_DELAY = 2 -- le message de réussite reste lisible avant le retour à l'accueil

local page: MenuPage.Page
local textBox: TextBox
local sendChoice
local statusLabel: TextLabel
local charCountLabel: TextLabel
local onCloseCallback: (() -> ())?
local sending = false
local openCount = 0

-- Cette méthode permet d'afficher un message d'état sous le champ lorsque l'envoi échoue ou réussit.
local function setStatus(msg: string, color: Color3?)
	statusLabel.Text = msg
	statusLabel.TextColor3 = color or C.Bone
end

-- Cette méthode permet de mettre à jour le compteur et l'état d'ENVOYER lorsque le texte change.
local function refreshCount()
	local len = #textBox.Text
	charCountLabel.Text = len .. " / " .. MAX_CHARS
	local valid = len >= MIN_CHARS
	charCountLabel.TextColor3 = valid and C.Bone or C.Muted
	sendChoice.setEnabled(valid and not sending)
end

-- Cette méthode permet de remettre l'écran à zéro (texte, envoi, statut) lorsqu'il s'ouvre.
local function resetState()
	sending = false
	textBox.Text = ""
	setStatus("")
	refreshCount()
end

-- Cette méthode permet de quitter l'écran et de revenir à l'accueil lorsque le joueur annule ou que l'envoi a réussi.
local function leave()
	FeedbackScreen.hide()
	if onCloseCallback then
		onCloseCallback()
	end
end

-- Cette méthode permet d'envoyer le message au serveur lorsque le joueur tire sur ENVOYER.
local function send(sendRmt: RemoteEvent)
	if sending then
		return
	end
	local text = textBox.Text:match("^%s*(.-)%s*$")
	if #text < MIN_CHARS then
		setStatus("Message trop court (min. " .. MIN_CHARS .. " car.).", C.Alert)
		return
	end
	sending = true
	refreshCount()
	setStatus("Envoi…")
	sendRmt:FireServer(textBox.Text)
end

-- Cette méthode permet de construire le champ de saisie, posé sur un fond sombre et souligné, lorsque l'écran est initialisé.
local function buildField(parent: Instance)
	local field = UIKit.frame({
		Name = "Message",
		Position = UDim2.fromOffset(0, FIELD_TOP),
		Size = UDim2.fromOffset(FIELD_WIDTH, FIELD_HEIGHT),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.55,
		Parent = parent,
	})
	local underline = UIKit.frame({
		Name = "Underline",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = C.Muted,
		Parent = field,
	})
	textBox = UIKit.create("TextBox", {
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 1, -24),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Ton message (10 à 500 caractères)…",
		PlaceholderColor3 = C.Muted,
		TextColor3 = C.Bone,
		FontFace = F.Body,
		TextSize = 19,
		TextWrapped = true,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = field,
	})
	textBox.Focused:Connect(function()
		UIKit.tween(underline, Motion.Hover, { BackgroundColor3 = C.Accent })
	end)
	textBox.FocusLost:Connect(function()
		UIKit.tween(underline, Motion.Hover, { BackgroundColor3 = C.Muted })
	end)
	textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #textBox.Text > MAX_CHARS then
			textBox.Text = textBox.Text:sub(1, MAX_CHARS)
			return
		end
		refreshCount()
	end)
end

-- Cette méthode permet de construire l'écran et de le relier au serveur lorsque le client démarre.
function FeedbackScreen.init(onClose: () -> ())
	onCloseCallback = onClose
	local N = NetworkProtocol.Names
	local sendRmt = NetworkProtocol.getRemote(N.SEND_FEEDBACK)
	local ackRmt = NetworkProtocol.getRemote(N.FEEDBACK_ACK)

	page = MenuPage.new("FeedbackScreen", 2, "FEEDBACK")
	-- Colonne centrée : toutes les positions ci-dessous sont relatives à elle
	local column = UIKit.frame({
		Name = "Column",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, FIELD_WIDTH, 1, 0),
		Parent = page.group,
	})
	UIKit.text({
		Text = "SIGNALE UN BUG OU PARTAGE UNE IDÉE",
		FontFace = F.DisplayMedium,
		TextSize = 15,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, MenuPage.ContentTop + 8),
		Size = UDim2.fromOffset(FIELD_WIDTH, 18),
		Parent = column,
	})
	buildField(column)

	local belowField = FIELD_TOP + FIELD_HEIGHT + 8
	charCountLabel = UIKit.text({
		Text = "0 / " .. MAX_CHARS,
		FontFace = F.Mono,
		TextSize = T.Caption,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(0, belowField),
		Size = UDim2.fromOffset(120, 20),
		Parent = column,
	})
	statusLabel = UIKit.text({
		Text = "",
		TextSize = T.Small,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(130, belowField),
		Size = UDim2.fromOffset(FIELD_WIDTH - 130, 20),
		Parent = column,
	})
	-- Actions côte à côte sous le champ : ANNULER, puis ENVOYER (action principale, en os vif)
	local actions = UIKit.frame({
		Name = "Actions",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, belowField + 34),
		Size = UDim2.fromOffset(FIELD_WIDTH, 44),
		Parent = column,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ACTION_GAP),
		Parent = actions,
	})
	page.choice({ text = "ANNULER", size = ACTION_SIZE, layoutOrder = 1, parent = actions, action = leave })
	sendChoice = page.choice({
		text = "ENVOYER",
		size = ACTION_SIZE,
		layoutOrder = 2,
		parent = actions,
		action = function()
			send(sendRmt)
		end,
	})
	sendChoice.setSelected(true)

	ackRmt.OnClientEvent:Connect(function(success: boolean, message: string)
		sending = false
		if success then
			setStatus(message, C.Success)
			textBox.Text = ""
			local session = openCount
			task.delay(CLOSE_DELAY, function()
				if page.gui.Enabled and session == openCount then
					leave()
				end
			end)
		else
			setStatus(message, C.Alert)
		end
		refreshCount()
	end)

	resetState()
end

-- Cette méthode permet d'ouvrir l'écran vierge, le curseur dans le champ, lorsque le joueur tire sur FEEDBACK.
function FeedbackScreen.show()
	if not page then
		return
	end
	openCount += 1
	resetState()
	page.show()
	task.defer(function()
		textBox:CaptureFocus()
	end)
end

-- Cette méthode permet de masquer l'écran lorsque le joueur le quitte ou que la partie démarre.
function FeedbackScreen.hide()
	if page then
		page.hide()
	end
end

return FeedbackScreen

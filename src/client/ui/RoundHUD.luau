-- HUD de round (direction « Tactical ») : timer et rang en haut, classement (Tab maintenu),
-- overlay de réapparition (décor désaturé) et bandeau ambre de fin de round.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion

local RoundHUD = {}

-- Colonnes du classement : largeur fixe (px), alignement ; JOUEUR prend la place restante
local LB_WIDTH = 700
local LB_PAD = 22
local LB_HEADER = 52
local LB_COLUMNS = 34
local LB_ROW = 42
local COL_RANK = 56
local COL_STAT = 80

local gui: ScreenGui
local timerLabel: TextLabel
local timerBar: Frame
local blinkTween: Tween?
local lowTime = false
local rankLabel: TextLabel
local leaderboard: CanvasGroup
local leaderboardTimer: TextLabel
local leaderboardList: Frame
local respawnRoot: Frame
local respawnDim: Frame
local respawnPanel: CanvasGroup
local respawnCount: TextLabel
local respawnCountScale: UIScale
local respawnLabel: TextLabel
local deathGrade: ColorCorrectionEffect
local resultRoot: Frame
local resultDim: Frame
local resultBand: Frame
local resultContent: CanvasGroup
local resultLabel: TextLabel

local tabConn: RBXScriptConnection?
local tabEndConn: RBXScriptConnection?
local respawnTask: thread?

-- ── Timer et rang ──────────────────────────────────────────────────────────────

-- Cette méthode permet de construire le bloc timer + rang collé en haut de l'écran lorsque le HUD est initialisé.
local function buildTimer(root: Frame)
	local block = UIKit.frame({
		Name = "TimerBlock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -1),
		Size = UDim2.fromOffset(222, 59),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.12,
		Parent = root,
	})
	UIKit.stroke(block, C.Border)

	timerLabel = UIKit.text({
		Name = "Timer",
		Text = "5:00",
		FontFace = F.MonoBold,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromOffset(150, 30),
		Parent = block,
	})
	UIKit.text({
		Text = "FREE FOR ALL",
		FontFace = F.DisplayMedium,
		TextSize = T.Micro,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 37),
		Size = UDim2.fromOffset(150, 14),
		Parent = block,
	})
	timerBar = UIKit.frame({
		Name = "TimerBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(150, 3),
		BackgroundColor3 = C.Text,
		Parent = block,
	})
	UIKit.frame({
		Name = "Divider",
		Position = UDim2.fromOffset(150, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = C.Border,
		Parent = block,
	})
	rankLabel = UIKit.text({
		Name = "Rank",
		Text = "—",
		RichText = true,
		FontFace = F.Display,
		TextSize = T.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(151, 9),
		Size = UDim2.fromOffset(71, 28),
		Parent = block,
	})
	UIKit.text({
		Text = "RANG",
		FontFace = F.DisplayMedium,
		TextSize = 10,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(151, 37),
		Size = UDim2.fromOffset(71, 14),
		Parent = block,
	})
end

-- Cette méthode permet de passer le timer en alerte (rouge + clignotement) ou de l'en sortir lorsque le seuil des 30 s est franchi.
local function setLowTime(low: boolean)
	if low == lowTime then
		return
	end
	lowTime = low
	local color = low and C.Alert or C.Text
	UIKit.tween(timerLabel, Motion.Color, { TextColor3 = color })
	UIKit.tween(timerBar, Motion.Color, { BackgroundColor3 = color })
	if blinkTween then
		blinkTween:Cancel()
		blinkTween = nil
	end
	timerLabel.TextTransparency = 0
	if low then
		blinkTween = UIKit.tween(timerLabel, Motion.Blink, { TextTransparency = 0.65 })
	end
end

-- ── Classement ─────────────────────────────────────────────────────────────────

-- Cette méthode permet de poser les cinq cellules d'une ligne du classement (colonnes fixes) lorsqu'un en-tête ou un joueur est ajouté.
local function fillColumns(
	row: GuiObject,
	values: { string },
	font: Font,
	colors: { Color3 },
	size: number
): { TextLabel }
	local labels = {}
	local rightEdges = { LB_PAD + COL_STAT * 2, LB_PAD + COL_STAT, LB_PAD }
	labels[1] = UIKit.text({
		Text = values[1],
		FontFace = values[1] == "#" and font or F.MonoBold,
		TextSize = values[1] == "#" and size or T.Small,
		TextColor3 = colors[1],
		Position = UDim2.fromOffset(LB_PAD, 0),
		Size = UDim2.new(0, COL_RANK, 1, 0),
		Parent = row,
	})
	labels[2] = UIKit.text({
		Text = values[2],
		FontFace = font,
		TextSize = size,
		TextColor3 = colors[2],
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(LB_PAD + COL_RANK, 0),
		Size = UDim2.new(1, -(LB_PAD * 2 + COL_RANK + COL_STAT * 3), 1, 0),
		Parent = row,
	})
	for i = 3, 5 do
		labels[i] = UIKit.text({
			Text = values[i],
			FontFace = font,
			TextSize = size,
			TextColor3 = colors[i],
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -rightEdges[i - 2], 0, 0),
			Size = UDim2.new(0, COL_STAT, 1, 0),
			Parent = row,
		})
	end
	return labels
end

-- Cette méthode permet de construire le panneau du classement (bandeau ambre, en-têtes, liste) lorsque le HUD est initialisé.
local function buildLeaderboard(root: Frame)
	leaderboard = UIKit.create("CanvasGroup", {
		Name = "Leaderboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(LB_WIDTH, LB_HEADER + LB_COLUMNS),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	UIKit.stroke(leaderboard, C.Border)

	local band = UIKit.frame({
		Name = "Band",
		Size = UDim2.new(1, 0, 0, LB_HEADER),
		BackgroundColor3 = C.Accent,
		Parent = leaderboard,
	})
	UIKit.text({
		Text = "LEADERBOARD",
		FontFace = F.Display,
		TextSize = 20,
		TextColor3 = C.Ground,
		Position = UDim2.fromOffset(LB_PAD, 0),
		Size = UDim2.fromScale(0.6, 1),
		Parent = band,
	})
	leaderboardTimer = UIKit.text({
		Text = "5:00",
		FontFace = F.MonoBold,
		TextSize = T.Small,
		TextColor3 = C.Ground,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -LB_PAD, 0, 0),
		Size = UDim2.fromScale(0.3, 1),
		Parent = band,
	})

	local columns = UIKit.frame({
		Name = "Columns",
		Position = UDim2.fromOffset(0, LB_HEADER),
		Size = UDim2.new(1, 0, 0, LB_COLUMNS),
		BackgroundTransparency = 1,
		Parent = leaderboard,
	})
	local m = C.Muted
	fillColumns(columns, { "#", "JOUEUR", "K", "D", "K/D" }, F.DisplayMedium, { m, m, m, m, m }, T.Caption)
	UIKit.frame({
		Name = "Divider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Border,
		Parent = columns,
	})

	leaderboardList = UIKit.frame({
		Name = "Rows",
		Position = UDim2.fromOffset(0, LB_HEADER + LB_COLUMNS),
		Size = UDim2.new(1, 0, 1, -(LB_HEADER + LB_COLUMNS)),
		BackgroundTransparency = 1,
		Parent = leaderboard,
	})
end

-- Cette méthode permet d'afficher le classement en fondu et de faire glisser ses lignes une à une lorsque Tab est enfoncé.
local function openLeaderboard()
	if leaderboard.Visible then
		return
	end
	leaderboard.Visible = true
	leaderboard.GroupTransparency = 1
	UIKit.tween(leaderboard, Motion.Hover, { GroupTransparency = 0 })
	for _, row in leaderboardList:GetChildren() do
		local order = row:GetAttribute("Order")
		local content = row:FindFirstChild("Content")
		if order and content and content:IsA("GuiObject") then
			content.Position = UDim2.fromOffset(0, -6)
			task.delay(order * Motion.Stagger, function()
				UIKit.tween(content, Motion.Enter, { Position = UDim2.fromOffset(0, 0) })
			end)
		end
	end
end

-- ── Réapparition ───────────────────────────────────────────────────────────────

-- Cette méthode permet de construire l'overlay de mort (voile, bloc rouge du compte à rebours, texte) lorsque le HUD est initialisé.
local function buildRespawnOverlay(root: Frame)
	respawnRoot = UIKit.frame({
		Name = "Respawn",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	respawnDim = UIKit.frame({
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		Parent = respawnRoot,
	})
	respawnPanel = UIKit.create("CanvasGroup", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(460, 78),
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Parent = respawnRoot,
	})
	UIKit.stroke(respawnPanel, C.Border)
	local block = UIKit.frame({
		Name = "CountBlock",
		Size = UDim2.new(0, 96, 1, 0),
		BackgroundColor3 = C.Danger,
		Parent = respawnPanel,
	})
	respawnCount = UIKit.text({
		Text = "3",
		FontFace = F.Display,
		TextSize = T.Count,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = block,
	})
	respawnCountScale = UIKit.create("UIScale", { Parent = respawnCount })
	UIKit.text({
		Text = "ÉLIMINÉ",
		FontFace = F.Display,
		TextSize = T.Title,
		Position = UDim2.fromOffset(116, 12),
		Size = UDim2.new(1, -136, 0, 28),
		Parent = respawnPanel,
	})
	respawnLabel = UIKit.text({
		Text = "",
		TextSize = 15,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(116, 42),
		Size = UDim2.new(1, -136, 0, 22),
		Parent = respawnPanel,
	})
end

-- Cette méthode permet d'afficher le nouveau chiffre du compte à rebours avec une pulsation lorsqu'une seconde passe.
local function popCount(value: number)
	respawnCount.Text = tostring(value)
	respawnCount.TextTransparency = 1
	respawnCountScale.Scale = 1.4
	UIKit.tween(respawnCount, Motion.Pop, { TextTransparency = 0 })
	UIKit.tween(respawnCountScale, Motion.Pop, { Scale = 1 })
end

-- ── Fin de round ───────────────────────────────────────────────────────────────

-- Cette méthode permet de construire le bandeau ambre pleine largeur de fin de round lorsque le HUD est initialisé.
local function buildResultBanner(root: Frame)
	resultRoot = UIKit.frame({
		Name = "Result",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		Parent = root,
	})
	resultDim = UIKit.frame({
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 12, 14),
		BackgroundTransparency = 0.45,
		Parent = resultRoot,
	})
	resultBand = UIKit.frame({
		Name = "Band",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.465),
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = C.Accent,
		Parent = resultRoot,
	})
	resultContent = UIKit.create("CanvasGroup", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = resultBand,
	})
	UIKit.text({
		Text = "ROUND TERMINÉ",
		FontFace = F.DisplayMedium,
		TextSize = T.Body,
		TextColor3 = C.Ground,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = resultContent,
	})
	resultLabel = UIKit.text({
		Text = "",
		FontFace = F.Display,
		TextSize = T.Banner,
		TextColor3 = C.Ground,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(40, 56),
		Size = UDim2.new(1, -80, 0, 60),
		Parent = resultContent,
	})
end

-- ── API publique ───────────────────────────────────────────────────────────────

function RoundHUD.init()
	gui = UIKit.create("ScreenGui", {
		Name = "RoundHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	deathGrade = UIKit.create("ColorCorrectionEffect", {
		Name = "DeathGrade",
		Saturation = 0,
		Enabled = false,
		Parent = Lighting,
	})
	local root = UIKit.scaledRoot(gui)

	buildRespawnOverlay(root)
	buildTimer(root)
	buildLeaderboard(root)
	buildResultBanner(root)

	tabConn = UserInputService.InputBegan:Connect(function(input, _processed)
		if input.KeyCode == Enum.KeyCode.Tab then
			openLeaderboard()
		end
	end)
	tabEndConn = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			leaderboard.Visible = false
		end
	end)
end

function RoundHUD.show()
	if gui then
		gui.Enabled = true
	end
	if respawnRoot then
		respawnRoot.Visible = false
	end
	if resultRoot then
		resultRoot.Visible = false
	end
end

function RoundHUD.hide()
	if gui then
		gui.Enabled = false
	end
	if deathGrade then
		deathGrade.Enabled = false
	end
end

function RoundHUD.updateTimer(seconds: number)
	if not timerLabel then
		return
	end
	local text = HUDRules.formatTimer(seconds)
	timerLabel.Text = text
	leaderboardTimer.Text = text
	setLowTime(HUDRules.isLowTime(seconds))
end

type Score = HUDRules.Score

function RoundHUD.updateScores(scores: { [number]: Score })
	if not leaderboardList then
		return
	end
	for _, child in leaderboardList:GetChildren() do
		child:Destroy()
	end

	local sorted = HUDRules.sortScores(scores)
	local localName = Players.LocalPlayer.Name
	local rank = HUDRules.rankOf(sorted, localName)
	rankLabel.Text = rank and string.format('%d<font size="14" color="#9AA0A8">/%d</font>', rank, #sorted) or "—"

	for i, score in sorted do
		local isMe = score.name == localName
		local row = UIKit.frame({
			Name = "Row" .. i,
			Position = UDim2.fromOffset(0, (i - 1) * LB_ROW),
			Size = UDim2.new(1, 0, 0, LB_ROW),
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = isMe and 0.86 or 1,
			Parent = leaderboardList,
		})
		row:SetAttribute("Order", i)
		UIKit.frame({
			Name = "Divider",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = C.Raised,
			Parent = row,
		})
		if isMe then
			UIKit.frame({ Name = "MeBar", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = C.Accent, Parent = row })
		end
		local content = UIKit.frame({
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = row,
		})
		local nameColor = C.Text
		fillColumns(
			content,
			{
				tostring(i),
				isMe and (score.name .. " (toi)") or score.name,
				tostring(score.kills),
				tostring(score.deaths),
				HUDRules.formatKD(score.kills, score.deaths),
			},
			isMe and F.BodyBold or F.Body,
			{
				i == 1 and C.Accent or C.Muted,
				nameColor,
				C.Text,
				C.Muted,
				C.Muted,
			},
			T.Body
		)
	end

	leaderboard.Size = UDim2.fromOffset(LB_WIDTH, LB_HEADER + LB_COLUMNS + #sorted * LB_ROW + 6)
end

function RoundHUD.showRespawning(delaySeconds: number)
	if not respawnRoot then
		return
	end
	respawnRoot.Visible = true
	respawnDim.BackgroundTransparency = 1
	UIKit.tween(respawnDim, Motion.Enter, { BackgroundTransparency = 0.65 })
	UIKit.reveal(respawnPanel, 0, 16)
	deathGrade.Enabled = true
	deathGrade.Saturation = 0
	UIKit.tween(deathGrade, Motion.Enter, { Saturation = -1 })

	local endTime = os.clock() + delaySeconds
	local shown = -1
	if respawnTask then
		task.cancel(respawnTask)
	end
	respawnTask = task.spawn(function()
		while respawnRoot.Visible do
			local remaining = HUDRules.secondsLeft(endTime, os.clock())
			if remaining <= 0 then
				respawnLabel.Text = "Réapparition..."
				break
			end
			if remaining ~= shown then
				shown = remaining
				popCount(remaining)
				respawnLabel.Text = string.format("Réapparition dans %ds", remaining)
			end
			task.wait(0.05)
		end
	end)
end

function RoundHUD.hideRespawning()
	if respawnRoot then
		respawnRoot.Visible = false
	end
	if deathGrade then
		UIKit.tween(deathGrade, Motion.Exit, { Saturation = 0 }).Completed:Connect(function()
			if not (respawnRoot and respawnRoot.Visible) then
				deathGrade.Enabled = false
			end
		end)
	end
	if respawnTask then
		task.cancel(respawnTask)
		respawnTask = nil
	end
end

function RoundHUD.showResult(winnerName: string)
	if not resultRoot then
		return
	end
	leaderboard.Visible = false
	resultLabel.Text = string.upper(winnerName) .. " REMPORTE LE ROUND !"
	resultRoot.Visible = true
	resultDim.BackgroundTransparency = 1
	UIKit.tween(resultDim, Motion.Enter, { BackgroundTransparency = 0.45 })
	resultBand.Position = UDim2.fromScale(-1, 0.465)
	UIKit.tween(resultBand, Motion.Band, { Position = UDim2.fromScale(0, 0.465) })
	resultContent.GroupTransparency = 1
	resultContent.Position = UDim2.fromOffset(40, 0)
	task.delay(0.35, function()
		UIKit.tween(resultContent, Motion.Enter, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	end)
end

function RoundHUD.hideResult()
	if resultRoot then
		resultRoot.Visible = false
	end
end

function RoundHUD.destroy()
	if tabConn then
		tabConn:Disconnect()
		tabConn = nil
	end
	if tabEndConn then
		tabEndConn:Disconnect()
		tabEndConn = nil
	end
	if deathGrade then
		deathGrade:Destroy()
	end
	if gui then
		gui:Destroy()
	end
end

return RoundHUD

-- HUD de round : timer et rang en haut, classement (Tab maintenu) dans la direction « Ligne de mire » ;
-- overlay de réapparition (décor désaturé) et bandeau ambre de fin de round encore dans l'ancien style « Tactical ».
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

local SHADOW_TRANSPARENCY = 0.35
-- Fond du timer : deux moitiés de fondu de coin collées au milieu du haut de l'écran
local TOP_SCRIM_SIZE = Vector2.new(220, 110)
local TOP_SCRIM_TRANSPARENCY = 0.3
-- Classement : largeur fixe (px), colonnes en px ; JOUEUR prend la place restante
local LB_WIDTH = 620
local LB_TOP = 118
local LB_RULE_Y = 70
local LB_ROW = 36
local LB_VEIL_EXTRA = 420 -- largeur du voile au-delà du tableau, où il s'efface
local LB_VEIL_TRANSPARENCY = 0.3
local COL_RANK = 36
local COL_NAME = 56
local COL_STATS = { 80, 64, 64 } -- K, M, K/M

local gui: ScreenGui
local timerLabel: TextLabel
local timerShadow: TextLabel
local blinkTween: Tween?
local lowTime = false
local rankLabel: TextLabel
local rankShadow: TextLabel
local leaderboard: CanvasGroup
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

-- Cette méthode permet de poser un texte doublé d'une ombre noire décalée lorsque le titrage du HUD est construit ;
-- renvoie le texte puis son ombre, à mettre à jour ensemble.
local function shadowedText(parent: GuiObject, props: { [string]: any }, offset: number): (TextLabel, TextLabel)
	local shadowProps = table.clone(props)
	shadowProps.Name = (props.Name or "Text") .. "Shadow"
	shadowProps.TextColor3 = C.Black
	shadowProps.TextTransparency = SHADOW_TRANSPARENCY
	shadowProps.Position = (props.Position or UDim2.new()) + UDim2.fromOffset(offset, offset)
	shadowProps.Parent = parent
	local shadow = UIKit.text(shadowProps)
	props.Parent = parent
	return UIKit.text(props), shadow
end

-- Cette méthode permet de construire le timer et le rang en haut au centre (chiffres os droits sur un fondu sombre,
-- sans panneau) lorsque le HUD est initialisé.
local function buildTimer(root: Frame)
	local top = UDim2.fromScale(0.5, 0)
	UIKit.cornerScrim(root, "TopRight", TOP_SCRIM_SIZE, TOP_SCRIM_TRANSPARENCY, top)
	UIKit.cornerScrim(root, "TopLeft", TOP_SCRIM_SIZE, TOP_SCRIM_TRANSPARENCY, top)

	local block = UIKit.frame({
		Name = "TimerBlock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(240, 80),
		Parent = root,
	})
	timerLabel, timerShadow = shadowedText(block, {
		Name = "Timer",
		Text = "5:00",
		FontFace = F.Display,
		TextSize = 50,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(130, 54),
	}, 4)
	UIKit.text({
		Text = "FREE FOR ALL",
		FontFace = F.DisplayMedium,
		TextSize = 12,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.fromOffset(130, 14),
		Parent = block,
	})
	UIKit.frame({
		Name = "Divider",
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.4,
		Position = UDim2.fromOffset(142, 12),
		Size = UDim2.fromOffset(2, 50),
		Parent = block,
	})
	rankLabel, rankShadow = shadowedText(block, {
		Name = "Rank",
		Text = "—",
		RichText = true,
		FontFace = F.Display,
		TextSize = 34,
		TextColor3 = C.Bone,
		Position = UDim2.fromOffset(156, 10),
		Size = UDim2.fromOffset(84, 40),
	}, 3)
	UIKit.text({
		Text = "RANG",
		FontFace = F.DisplayMedium,
		TextSize = 12,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(156, 54),
		Size = UDim2.fromOffset(84, 14),
		Parent = block,
	})
end

-- Cette méthode permet de passer le timer en alerte (rouge d'impact + clignotement) ou de l'en sortir lorsque le seuil
-- des 30 s est franchi.
local function setLowTime(low: boolean)
	if low == lowTime then
		return
	end
	lowTime = low
	UIKit.tween(timerLabel, Motion.Color, { TextColor3 = low and C.HitRed or C.Bone })
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

-- Cette méthode permet de poser les cinq cellules d'une ligne du classement (rang, joueur, K, M, K/M) lorsqu'un en-tête
-- ou un joueur est ajouté ; `fonts` et `colors` donnent l'aspect de chaque cellule.
local function fillColumns(row: GuiObject, values: { string }, fonts: { Font }, colors: { Color3 }, size: number)
	UIKit.text({
		Text = values[1],
		FontFace = fonts[1],
		TextSize = size + 4,
		TextColor3 = colors[1],
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, COL_RANK, 1, 0),
		Parent = row,
	})
	UIKit.text({
		Text = values[2],
		FontFace = fonts[2],
		TextSize = size,
		TextColor3 = colors[2],
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(COL_NAME, 0),
		Size = UDim2.new(1, -(COL_NAME + COL_STATS[1] + COL_STATS[2] + COL_STATS[3]), 1, 0),
		Parent = row,
	})
	local right = 0
	for i = 5, 3, -1 do
		local width = COL_STATS[i - 2]
		UIKit.text({
			Text = values[i],
			FontFace = fonts[i],
			TextSize = size + 2,
			TextColor3 = colors[i],
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -right, 0, 0),
			Size = UDim2.new(0, width, 1, 0),
			Parent = row,
		})
		right += width
	end
end

-- Cette méthode permet de construire le classement (voile sombre central sans panneau, titre sur un filet ambre,
-- en-têtes, liste) lorsque le HUD est initialisé.
local function buildLeaderboard(root: Frame)
	leaderboard = UIKit.create("CanvasGroup", {
		Name = "Leaderboard",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})
	local veil = UIKit.frame({
		Name = "Veil",
		BackgroundColor3 = C.Scrim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, LB_WIDTH + LB_VEIL_EXTRA, 1, 0),
		Parent = leaderboard,
	})
	UIKit.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, LB_VEIL_TRANSPARENCY),
			NumberSequenceKeypoint.new(0.7, LB_VEIL_TRANSPARENCY),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = veil,
	})

	local holder = UIKit.frame({
		Name = "Board",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, LB_TOP),
		Size = UDim2.new(0, LB_WIDTH, 1, -LB_TOP),
		Parent = leaderboard,
	})
	local head = UIKit.frame({
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(LB_WIDTH, 60),
		Parent = holder,
	})
	shadowedText(head, {
		Name = "Title",
		Text = "CLASSEMENT",
		FontFace = F.Display,
		TextSize = 46,
		TextColor3 = C.Bone,
		Size = UDim2.fromOffset(400, 52),
	}, 5)
	UIKit.frame({
		Name = "Rule",
		BackgroundColor3 = C.Accent,
		Position = UDim2.fromOffset(0, LB_RULE_Y),
		Size = UDim2.fromOffset(LB_WIDTH, 3),
		Parent = holder,
	})

	local columns = UIKit.frame({
		Name = "Columns",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, LB_RULE_Y + 4),
		Size = UDim2.fromOffset(LB_WIDTH, LB_ROW - 2),
		Parent = holder,
	})
	local m = C.Muted
	local h = F.DisplayMedium
	fillColumns(columns, { "#", "JOUEUR", "K", "M", "K/M" }, { h, h, h, h, h }, { m, m, m, m, m }, 12)

	leaderboardList = UIKit.frame({
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, LB_RULE_Y + 4 + LB_ROW),
		Size = UDim2.new(1, 0, 1, -(LB_RULE_Y + 4 + LB_ROW)),
		Parent = holder,
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
	timerShadow.Text = text
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
	local rankText = rank and string.format('%d<font size="18" transparency="0.4">/%d</font>', rank, #sorted) or "—"
	rankLabel.Text = rankText
	rankShadow.Text = rankText

	for i, score in sorted do
		local isMe = score.name == localName
		local row = UIKit.frame({
			Name = "Row" .. i,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, (i - 1) * LB_ROW),
			Size = UDim2.new(1, 0, 0, LB_ROW),
			Parent = leaderboardList,
		})
		row:SetAttribute("Order", i)
		if isMe then
			-- Bande droite, pas penchée : une ligne en biais se lit mal en face des colonnes
			local band = UIKit.frame({
				Name = "MeBand",
				BackgroundColor3 = C.HitRed,
				BackgroundTransparency = 0.2,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, -16, 0.5, 0),
				Size = UDim2.new(1, 32, 0, LB_ROW - 6),
				Parent = row,
			})
			UIKit.create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.75, 0.35),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = band,
			})
		end
		local content = UIKit.frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = row,
		})
		local statColor = isMe and C.Bone or C.Muted
		fillColumns(content, {
			tostring(i),
			isMe and (score.name .. "  (toi)") or score.name,
			tostring(score.kills),
			tostring(score.deaths),
			HUDRules.formatKD(score.kills, score.deaths),
		}, { F.Display, isMe and F.BodyBold or F.BodySemi, F.Display, F.DisplayMedium, F.DisplayMedium }, {
			i == 1 and C.Accent or statColor,
			isMe and C.Bone or C.Text,
			C.Bone,
			statColor,
			statColor,
		}, 16)
	end
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

-- HUD de round, direction « Ligne de mire » : timer et rang en haut, classement (Tab maintenu), écran de réapparition
-- (scène désaturée, compte à rebours en bas au centre, conseil d'un débutant dessous, #291) et écran de fin de round
-- (voile central, nom du vainqueur, podium et ligne du joueur, crédits gagnés dans la manche, #394).
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local ParticipantRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParticipantRules"))
local EconomyRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyRules"))
local WalletRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WalletRules"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)
local HUDState = require(script.Parent.HUDState)
local KillStreakRules = require(script.Parent.Parent.systems.game.KillStreakRules)
local LocalWallet = require(script.Parent.Parent.systems.inventory.LocalWallet)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local RoundHUD = {}

-- Fond du timer : fondu de bord (une seule image, #247) au milieu du haut de l'écran
local TOP_SCRIM_SIZE = Vector2.new(440, 110)
local TOP_SCRIM_TRANSPARENCY = 0.3
local TIMER_TOP = 10
local TIMER_HEIGHT = 84
-- Menu en partie ouvert (#220) : le timer passe au-dessus de son voile (2) et de sa page (3), la partie continue
local TIMER_OVER_MENU_ORDER = 4
-- Série de kills (#364) : crâne éclaté et nombre, sans mot ni cercle, centrés sous le timer (KillStreakRules.view).
-- Crâne os, hachuré dès 5 kills ; nombre rouge d'impact dès 10. Pas de sang (règles Roblox sur le gore). À un palier
-- annoncé à la voix, sans changer de taille : la croix du hitmarker s'allume autour du crâne, crâne en rouge d'impact et
-- nombre en rouge (en os s'il est déjà rouge) le temps de l'annonce (STREAK_FLASH_HOLD).
-- assets/ui/hud/crane_serie.png et crane_serie_hachures.png (tools/ui/make_skull_icon.py, Decals 80650103001496 et
-- 77308507647947) ; ci-dessous les ids des images de ces Decals
local STREAK_SKULL = "rbxassetid://99336092680581"
local STREAK_SKULL_HATCHED = "rbxassetid://72136449871345"
local STREAK_TOP = TIMER_TOP + TIMER_HEIGHT + 2
local STREAK_SKULL_SIZE = 40
local STREAK_HEIGHT = STREAK_SKULL_SIZE + 4
-- Croix du hitmarker autour du crâne : du centre, début et fin de chaque diagonale (px), et épaisseur. Elle part du bord
-- du crâne : posée dessus, elle cachait les orbites
local STREAK_CROSS = { 21, 30 }
local STREAK_CROSS_THICKNESS = 2
local STREAK_CROSS_HOLD = 0.6
local STREAK_TEXT_SIZE = 30
local STREAK_GAP = 10
local STREAK_FLASH_HOLD = 1.2
-- Classement : largeur fixe (px), colonnes en px ; JOUEUR prend la place restante
local LB_WIDTH = 620
local LB_TOP = 118
local LB_RULE_Y = 70
local LB_ROW = 40
local LB_VEIL_EXTRA = 420 -- largeur du voile au-delà du tableau, où il s'efface
local LB_VEIL_TRANSPARENCY = 0.3
local COL_RANK = 36
local COL_NAME = 56
local COL_STATS = { 80, 72, 64 } -- KILLS, MORTS, K/M
-- Réapparition : bloc en bas au centre sur un fondu de bord (une seule image, #247), scène désaturée sans voile plein
local RESPAWN_SCRIM_SIZE = Vector2.new(520, 230)
local RESPAWN_SCRIM_TRANSPARENCY = 0.2
local RESPAWN_WIDTH = 400
local RESPAWN_HEIGHT = 196
local RESPAWN_BOTTOM = 40
-- Icône du tir à la tête (#365) après l'arme, sous le nom du tueur : un peu plus haute que les lettres (16 px)
local RESPAWN_HEADSHOT_SIZE = 18
-- Conseil d'un débutant (#291) sous « RÉAPPARITION » : une ligne plus large que le bloc, fondu de bord agrandi d'autant
local RESPAWN_TIP_GAP = 8
local RESPAWN_TIP_HEIGHT = 24
local RESPAWN_TIP_WIDTH = 680
local RESPAWN_TIP_SIZE = 18
local RESPAWN_TIP_SCRIM_SIZE = Vector2.new(780, 270)
-- Fin de round : même voile central que le classement, un peu plus dense ; sous le vainqueur, podium et ligne du joueur
-- hors podium (#295) en lignes du classement, à `RESULT_BOARD_TOP` px du haut, ligne du joueur après un écart
local RESULT_WIDTH = 720
local RESULT_RULE_WIDTH = 420
local RESULT_VEIL_TRANSPARENCY = 0.2
local RESULT_BOARD_TOP = 184
local RESULT_ME_GAP = 14
-- Crédits gagnés dans la manche (#394), sous la dernière ligne du classement : jeton, « +N CRÉDITS » en os, puis
-- « PLAFOND DU JOUR ATTEINT » en ambre le cas échéant (attributs RoundCredits et DailyCredits, EconomyRules.roundBanner)
local RESULT_CREDITS_GAP = 18
local RESULT_CREDITS_HEIGHT = 32
local RESULT_CREDITS_ICON = 26
local RESULT_CREDITS_SIZE = 26
local RESULT_HEIGHT = RESULT_BOARD_TOP
	+ LB_ROW * (HUDRules.PODIUM_SIZE + 2)
	+ RESULT_ME_GAP
	+ RESULT_CREDITS_GAP
	+ RESULT_CREDITS_HEIGHT

local gui: ScreenGui
local hudRoot: Frame
local timerLayer: Frame
local timerOverMenuGui: ScreenGui
local timerOverMenuRoot: Frame
local timerLabel: TextLabel
local timerShadow: TextLabel
local blinkTween: Tween?
local lowTime = false
local rankLabel: TextLabel
local rankShadow: TextLabel
-- Rang affiché (nil : « — ») et taille du total dans le texte riche, px du repère du timer
local rankShown: { rank: number, total: number }? = nil
local RANK_TOTAL_SIZE = 18
local renderRank: () -> ()
local streakRow: Frame
local streakCross: { Frame } = {}
local streakSkull: ImageLabel
local streakSkullShadow: ImageLabel
local streakCount: TextLabel
local streakCountShadow: TextLabel
local streakShown = false -- série d'au moins KillStreakRules.MIN_SHOWN kills (masquée en plus sous le menu en partie)
local streakRest: Color3 = C.Bone -- couleur de repos du nombre (rouge d'impact dès 10 kills ; le crâne reste os)
local streakPulse = 0 -- jeton du dernier flash : un retour au repos ne s'applique qu'à lui
local streakFlashing = false -- flash d'un palier en cours : la couleur de repos attend sa fin
local leaderboard: Frame
local leaderboardList: Frame
local respawnRoot: Frame
local respawnScrim: ImageLabel
local respawnTipScrim: ImageLabel
local respawnPanel: Frame
local respawnCount: TextLabel
local respawnCountShadow: TextLabel
local respawnCountScale: UIScale
local respawnLabel: TextLabel
local respawnTitle: TextLabel
local respawnTitleShadow: TextLabel
local respawnKiller: TextLabel
local respawnKillerShadow: TextLabel
local respawnDetail: TextLabel
local respawnHeadshot: Frame
local respawnTip: TextLabel
local deathGrade: ColorCorrectionEffect
local resultRoot: Frame
local resultVeil: Frame
local resultContent: Frame
local resultMeBand: Frame
local resultName: TextLabel
local resultNameShadow: TextLabel
local resultLabel: TextLabel
local resultRows: Frame
local resultCredits: Frame
local resultCreditsIcon: Frame
local resultCreditsAmountBox: Frame
local resultCreditsAmount: { TextLabel }
local resultCreditsCap: Frame
local resultShown = false -- écran de fin en cours : Tab maintenu le remplace par le classement, sans superposition
local training = false -- serveur d'entraînement (#345) : ni timer, ni rang, ni classement

local hudStateConn: (() -> ())? -- désabonnement de HUDState
local tabConn: RBXScriptConnection?
local tabEndConn: RBXScriptConnection?
local creditConns: { RBXScriptConnection } = {} -- attributs des crédits de la manche (#394)
local respawnTask: thread?

-- ── Timer et rang ──────────────────────────────────────────────────────────────

local shadowedText = UIKit.shadowedText

-- Cette méthode permet de construire l'indicateur de série de kills (#364) sous le timer lorsque le HUD est initialisé :
-- crâne teinté et nombre à ombre, centrés ensemble, masqués tant que la série n'atteint pas le double kill.
local function buildStreak(anchor: Frame)
	streakRow = UIKit.frame({
		Name = "Streak",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, STREAK_TOP + STREAK_HEIGHT / 2),
		Size = UDim2.fromOffset(0, STREAK_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = anchor,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, STREAK_GAP),
		Parent = streakRow,
	})

	local skullBox = UIKit.frame({
		Name = "SkullBox",
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(STREAK_HEIGHT, STREAK_HEIGHT),
		Parent = streakRow,
	})
	-- Centre du crâne : la croix y est posée en px depuis le centre
	local center = UIKit.frame({
		Name = "Center",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		Parent = skullBox,
	})
	-- Crâne doublé d'une ombre noire décalée de 2 px, comme le texte du HUD sur la scène
	for _, layer in { { name = "Shadow", offset = 2, z = 1 }, { name = "", offset = 0, z = 2 } } do
		local shadow = layer.name == "Shadow"
		local skull = UIKit.create("ImageLabel", {
			Name = "Skull" .. layer.name,
			Image = STREAK_SKULL,
			ImageColor3 = if shadow then C.Black else C.Bone,
			ImageTransparency = if shadow then 0.35 else 0,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(layer.offset, layer.offset),
			Size = UDim2.fromOffset(STREAK_SKULL_SIZE, STREAK_SKULL_SIZE),
			ZIndex = layer.z,
			Parent = center,
		})
		if shadow then
			streakSkullShadow = skull
		else
			streakSkull = skull
		end
	end
	-- Croix du hitmarker autour du crâne, cachée hors palier : contour noir dessous, trait rouge d'impact dessus
	local diagonal = math.sqrt(0.5)
	local inner, outer = STREAK_CROSS[1] * diagonal, STREAK_CROSS[2] * diagonal
	for _, d in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		for _, layer in
			{
				{ thickness = STREAK_CROSS_THICKNESS + 2, color = C.Black, z = 4 },
				{ thickness = STREAK_CROSS_THICKNESS, color = C.HitRed, z = 5 },
			}
		do
			local line =
				UIKit.line(center, inner * d[1], inner * d[2], outer * d[1], outer * d[2], layer.thickness, layer.color)
			line.Name = "Cross"
			line.BackgroundTransparency = 1
			line.ZIndex = layer.z
			UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = line })
			table.insert(streakCross, line)
		end
	end

	local countBox = UIKit.frame({
		Name = "CountBox",
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, STREAK_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = streakRow,
	})
	streakCount, streakCountShadow = shadowedText(countBox, {
		Name = "Count",
		Text = "",
		FontFace = F.Display,
		TextSize = STREAK_TEXT_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(0, STREAK_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
	}, 3)
end

-- Cette méthode permet d'afficher ou masquer l'indicateur de série lorsque la série ou le menu en partie change : visible
-- dès le double kill, jamais sous le menu en partie (le titre « MENU » est juste sous le timer).
local function applyStreakVisible()
	if streakRow then
		streakRow.Visible = streakShown and not HUDRules.roundTimerOverMenu(HUDState.get())
	end
end

-- Cette méthode permet de remettre le crâne (os) et le nombre à leur couleur de repos lorsque la série change hors
-- d'un flash.
local function paintStreakRest()
	streakSkull.ImageColor3 = C.Bone
	streakCount.TextColor3 = streakRest
end

-- Cette méthode permet de marquer un palier annoncé à la voix, sans changer de taille : croix du hitmarker autour du
-- crâne, crâne en rouge d'impact et nombre en rouge (en os s'il est déjà rouge) ; retour au repos après l'annonce, sauf
-- si un palier plus récent a pris la main.
local function pulseStreak()
	streakPulse += 1
	streakFlashing = true
	local token = streakPulse
	streakSkull.ImageColor3 = C.HitRed
	streakCount.TextColor3 = if streakRest == C.HitRed then C.Bone else C.HitRed
	for _, line in streakCross do
		line.BackgroundTransparency = 0
	end
	task.delay(STREAK_CROSS_HOLD, function()
		if token ~= streakPulse then
			return
		end
		for _, line in streakCross do
			UIKit.tween(line, Motion.Hit, { BackgroundTransparency = 1 })
		end
	end)
	task.delay(STREAK_FLASH_HOLD, function()
		if token ~= streakPulse then
			return
		end
		streakFlashing = false
		UIKit.tween(streakSkull, Motion.Color, { ImageColor3 = C.Bone })
		UIKit.tween(streakCount, Motion.Color, { TextColor3 = streakRest })
	end)
end

-- Cette méthode permet de construire le timer et le rang en haut au centre (chiffres os droits sur un fondu sombre,
-- sans panneau) lorsque le HUD est initialisé ; le tout dans un calque qui passe au-dessus du menu en partie (#220).
local function buildTimer(root: Frame)
	-- ZIndex 0 : sous le classement et le résultat (voiles centraux), quel que soit l'ordre des enfants après un
	-- passage au-dessus du menu
	local layer = UIKit.frame({
		Name = "TimerLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = root,
	})
	timerLayer = layer
	-- Échelle du HUD (#250) : ancre sans taille au milieu du bord haut, dont l'UIScale réduit le fondu et le bloc vers ce
	-- point (le calque plein écran, lui, ne change pas : il porte aussi le passage au-dessus du menu)
	local anchor = UIKit.frame({
		Name = "TimerAnchor",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 0),
		Parent = layer,
	})
	local anchorScale = UIKit.create("UIScale", { Parent = anchor })
	-- #282 : textes au plancher à l'échelle vue (écran du calque x HUD ; les deux calques du timer ont celle de `root`),
	-- et timer masqué tant que l'échelle sauvegardée n'est pas connue
	local floorTexts = UIKit.floorHudText(anchor, function()
		local screen = root:GetAttribute("Scale")
		return (if type(screen) == "number" then screen else 1) * anchorScale.Scale
	end)
	root:GetAttributeChangedSignal("Scale"):Connect(floorTexts)
	UIKit.hideUntilHudShown(anchor)
	UIKit.onHudScale(anchor, function(factor)
		anchorScale.Scale = factor
		floorTexts()
	end)
	UIKit.cornerScrim(anchor, "Top", TOP_SCRIM_SIZE, TOP_SCRIM_TRANSPARENCY)

	local block = UIKit.frame({
		Name = "TimerBlock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, TIMER_TOP),
		Size = UDim2.fromOffset(240, TIMER_HEIGHT),
		Parent = anchor,
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
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.fromOffset(130, 20),
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
	rankLabel:GetAttributeChangedSignal("HudTextScale"):Connect(function()
		renderRank()
	end)
	UIKit.text({
		Text = "RANG",
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(156, 54),
		Size = UDim2.fromOffset(84, 20),
		Parent = block,
	})
	buildStreak(anchor)
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
		RichText = true, -- préfixe BOT atténué devant le nom d'un bot
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

-- Cette méthode permet de poser les en-têtes de colonnes (# JOUEUR KILLS MORTS K/M, atténués, mêmes mots que la fiche
-- de statistiques, #308) lorsque le classement ou l'écran de fin est construit.
local function columnHeaders(parent: GuiObject, y: number)
	local columns = UIKit.frame({
		Name = "Columns",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, LB_ROW - 2),
		Parent = parent,
	})
	local m = C.Muted
	local h = F.DisplayMedium
	fillColumns(columns, { "#", "JOUEUR", "KILLS", "MORTS", "K/M" }, { h, h, h, h, h }, { m, m, m, m, m }, 16)
end

-- Cette méthode permet de construire le classement (voile sombre central sans panneau, titre sur un filet ambre,
-- en-têtes, liste) lorsque le HUD est initialisé.
local function buildLeaderboard(root: Frame)
	leaderboard = UIKit.create("Frame", {
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
	}, 3) -- à 5 px, l'ombre se lisait comme un second titre (#308)
	UIKit.frame({
		Name = "Rule",
		BackgroundColor3 = C.Accent,
		Position = UDim2.fromOffset(0, LB_RULE_Y),
		Size = UDim2.fromOffset(LB_WIDTH, 3),
		Parent = holder,
	})

	columnHeaders(holder, LB_RULE_Y + 4)

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
	UIKit.fadeIn(leaderboard, Motion.Hover)
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

-- Cette méthode permet de construire l'écran de mort (fondu sombre en bas au centre, « ÉLIMINÉ » en rouge d'impact,
-- compte à rebours en chiffres os à ombre, libellé ambré) lorsque le HUD est initialisé ; la scène reste visible, désaturée.
local function buildRespawnOverlay(root: Frame)
	respawnRoot = UIKit.frame({
		Name = "Respawn",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	respawnScrim = UIKit.cornerScrim(respawnRoot, "Bottom", RESPAWN_SCRIM_SIZE, 1)
	-- Fondu agrandi, montré à la place du premier quand un conseil est affiché (#291)
	respawnTipScrim = UIKit.cornerScrim(respawnRoot, "Bottom", RESPAWN_TIP_SCRIM_SIZE, 1)
	respawnTipScrim.Visible = false
	respawnPanel = UIKit.create("Frame", {
		Name = "Panel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -RESPAWN_BOTTOM),
		Size = UDim2.fromOffset(RESPAWN_WIDTH, RESPAWN_HEIGHT),
		Parent = respawnRoot,
	})
	local centered = Enum.TextXAlignment.Center
	respawnTitle, respawnTitleShadow = shadowedText(respawnPanel, {
		Name = "Eliminated",
		Text = "ÉLIMINÉ",
		FontFace = F.Display,
		TextSize = 30,
		TextColor3 = C.HitRed,
		TextXAlignment = centered,
		Size = UDim2.new(1, 0, 0, 36),
	}, 3)
	-- Qui m'a tué (#102) : nom du tueur en os, arme et tir à la tête en ambre ; « CHUTE » sans tueur
	respawnKiller, respawnKillerShadow = shadowedText(respawnPanel, {
		Name = "Killer",
		Text = "",
		FontFace = F.Display,
		TextSize = 30,
		TextColor3 = C.Bone,
		TextXAlignment = centered,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 34),
	}, 3)
	-- Arme puis icône du tir à la tête (#365, à la place du mot « TÊTE »), centrées ensemble
	local detailRow = UIKit.frame({
		Name = "Detail",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = respawnPanel,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = detailRow,
	})
	respawnDetail = UIKit.text({
		Name = "Text",
		Text = "",
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.Accent,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = detailRow,
	})
	respawnHeadshot = UIKit.headshotIcon(detailRow, RESPAWN_HEADSHOT_SIZE, 1, { LayoutOrder = 2, Visible = false })
	-- Chiffre et ombre dans un cadre commun : la pulsation les agrandit ensemble
	local count = UIKit.frame({
		Name = "Count",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 84),
		Parent = respawnPanel,
	})
	respawnCountScale = UIKit.create("UIScale", { Parent = count })
	respawnCount, respawnCountShadow = shadowedText(count, {
		Name = "Count",
		Text = "3",
		FontFace = F.Display,
		TextSize = 80,
		TextColor3 = C.Bone,
		TextXAlignment = centered,
		Size = UDim2.fromScale(1, 1),
	}, 4)
	respawnLabel = UIKit.text({
		Name = "Label",
		Text = "RÉAPPARITION",
		FontFace = F.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = C.Accent,
		TextXAlignment = centered,
		Position = UDim2.fromOffset(0, 170),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = respawnPanel,
	})
	-- Conseil d'un débutant (#291) : thème en ambre puis phrase en os, texte courant (Oswald regular) ; masqué sinon
	respawnTip = UIKit.text({
		Name = "Tip",
		Text = "",
		RichText = true,
		Visible = false,
		FontFace = F.DisplayText,
		TextSize = RESPAWN_TIP_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = centered,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, RESPAWN_HEIGHT + RESPAWN_TIP_GAP),
		Size = UDim2.fromOffset(RESPAWN_TIP_WIDTH, RESPAWN_TIP_HEIGHT),
		Parent = respawnPanel,
	})
end

-- Cette méthode permet d'écrire le titre, le nom et le détail de l'écran de mort lorsqu'ils changent (titre et nom
-- doublés de leur ombre).
local function setRespawnLines(title: string, killer: string, detail: string, headshot: boolean?)
	respawnTitle.Text = title
	respawnTitleShadow.Text = title
	respawnKiller.Text = killer
	respawnKillerShadow.Text = killer
	respawnDetail.Text = detail
	respawnHeadshot.Visible = headshot == true
end

-- Cette méthode permet d'afficher le nouveau chiffre du compte à rebours avec une pulsation lorsqu'une seconde passe.
local function popCount(value: number)
	local text = tostring(value)
	respawnCount.Text = text
	respawnCountShadow.Text = text
	respawnCount.TextTransparency = 1
	respawnCountShadow.TextTransparency = 1
	respawnCountScale.Scale = 1.4
	UIKit.tween(respawnCount, Motion.Pop, { TextTransparency = 0 })
	UIKit.tween(respawnCountShadow, Motion.Pop, { TextTransparency = 0.35 })
	UIKit.tween(respawnCountScale, Motion.Pop, { Scale = 1 })
end

-- ── Fin de round ───────────────────────────────────────────────────────────────

-- Cette méthode permet de construire l'écran de fin de round (voile central qui s'efface vers les côtés, libellé ambré,
-- nom du vainqueur en os géant sur un filet ambre, bande rouge d'impact si c'est le joueur, puis podium en lignes du
-- classement) lorsque le HUD est initialisé.
local function buildResultBanner(root: Frame)
	resultRoot = UIKit.frame({
		Name = "Result",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	resultVeil = UIKit.frame({
		Name = "Veil",
		BackgroundColor3 = C.Scrim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, RESULT_WIDTH + LB_VEIL_EXTRA, 1, 0),
		Parent = resultRoot,
	})
	UIKit.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, RESULT_VEIL_TRANSPARENCY),
			NumberSequenceKeypoint.new(0.7, RESULT_VEIL_TRANSPARENCY),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = resultVeil,
	})
	resultContent = UIKit.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RESULT_WIDTH, RESULT_HEIGHT),
		Parent = resultRoot,
	})
	local centered = Enum.TextXAlignment.Center
	UIKit.text({
		Name = "Over",
		Text = "ROUND TERMINÉ",
		FontFace = F.DisplayMedium,
		TextSize = 16,
		TextColor3 = C.Accent,
		TextXAlignment = centered,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = resultContent,
	})
	-- Bande rouge d'impact derrière le nom quand le joueur gagne, comme sa ligne du classement
	resultMeBand = UIKit.frame({
		Name = "MeBand",
		BackgroundColor3 = C.HitRed,
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 82),
		Visible = false,
		Parent = resultContent,
	})
	UIKit.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.2),
			NumberSequenceKeypoint.new(0.75, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = resultMeBand,
	})
	resultName, resultNameShadow = shadowedText(resultContent, {
		Name = "Winner",
		Text = "",
		FontFace = F.Display,
		TextSize = 72,
		TextColor3 = C.Bone,
		TextXAlignment = centered,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 84),
		ZIndex = 2,
	}, 5)
	resultNameShadow.ZIndex = 2
	UIKit.frame({
		Name = "Rule",
		BackgroundColor3 = C.Accent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(RESULT_RULE_WIDTH, 3),
		Parent = resultContent,
	})
	resultLabel = UIKit.text({
		Name = "Wins",
		Text = "",
		FontFace = F.DisplayMedium,
		TextSize = 22,
		TextColor3 = C.Bone,
		TextXAlignment = centered,
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = resultContent,
	})
	-- Podium et ligne du joueur (#295) : colonnes et lignes du classement de Tab, à sa largeur
	local board = UIKit.frame({
		Name = "Board",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, RESULT_BOARD_TOP),
		Size = UDim2.new(0, LB_WIDTH, 1, -RESULT_BOARD_TOP),
		Parent = resultContent,
	})
	columnHeaders(board, 0)
	resultRows = UIKit.frame({
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, LB_ROW),
		Size = UDim2.new(1, 0, 1, -LB_ROW),
		Parent = board,
	})
	-- Crédits de la manche (#394) : placés par showResult sous la dernière ligne
	resultCredits = UIKit.frame({
		Name = "Credits",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, RESULT_CREDITS_HEIGHT),
		Visible = false,
		Parent = resultContent,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = resultCredits,
	})
	resultCreditsIcon = UIKit.creditIcon(resultCredits, RESULT_CREDITS_ICON, 2, { LayoutOrder = 1 })
	resultCreditsAmountBox = UIKit.frame({
		Name = "Amount",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, RESULT_CREDITS_SIZE + 4),
		LayoutOrder = 2,
		Parent = resultCredits,
	})
	local amountText, amountShadow = shadowedText(resultCreditsAmountBox, {
		Name = "Value",
		FontFace = F.Display,
		TextSize = RESULT_CREDITS_SIZE,
		TextColor3 = C.Bone,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 2,
	}, 2)
	resultCreditsAmount = { amountText, amountShadow }
	-- Texte et ombre dans un cadre : posés directement dans la liste, ils seraient rangés côte à côte
	resultCreditsCap = UIKit.frame({
		Name = "Cap",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 3,
		Parent = resultCredits,
	})
	UIKit.accentLabel(resultCreditsCap, {
		Name = "Value",
		Text = "PLAFOND DU JOUR ATTEINT",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
	})
end

-- Cette méthode permet d'afficher les crédits gagnés dans la manche (« +N CRÉDITS », « PLAFOND DU JOUR ATTEINT ») lorsque
-- l'écran de fin s'affiche ou que le serveur publie ces gains (attributs arrivés après RoundResult) ; rien sinon.
local function paintCredits()
	if not resultCredits then
		return
	end
	local player = Players.LocalPlayer
	local view = EconomyRules.roundBanner(player:GetAttribute(EconomyRules.ROUND_ATTRIBUTE), LocalWallet.dailyEarned())
	resultCredits.Visible = view ~= nil
	if not view then
		return
	end
	local text = if view.amount
		then string.format("+%s %s", WalletRules.format(view.amount), WalletRules.CURRENCY)
		else ""
	for _, label in resultCreditsAmount do
		label.Text = text
	end
	resultCreditsAmountBox.Visible = view.amount ~= nil
	resultCreditsIcon.Visible = view.amount ~= nil
	resultCreditsCap.Visible = view.capReached
end

-- Cette méthode permet de poser le timer au-dessus du menu en partie, ou de le rendre au HUD, lorsque l'état du HUD
-- (HUDState) change ou que le HUD de round s'affiche ou se masque (HUDRules.roundTimerOverMenu).
local function applyTimerLayer()
	if not timerLayer then
		return
	end
	local overMenu = HUDRules.roundTimerOverMenu(HUDState.get())
	local parent = if overMenu then timerOverMenuRoot else hudRoot
	if timerLayer.Parent ~= parent then
		timerLayer.Parent = parent
	end
	timerOverMenuGui.Enabled = overMenu and gui.Enabled
	applyStreakVisible()
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
	hudRoot = root
	-- Calque du timer quand le menu en partie est ouvert : même mise à l'échelle, au-dessus du voile et de la page
	timerOverMenuGui = UIKit.create("ScreenGui", {
		Name = "RoundTimerOverMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = TIMER_OVER_MENU_ORDER,
		Enabled = false,
		Parent = gui.Parent,
	})
	timerOverMenuRoot = UIKit.scaledRoot(timerOverMenuGui)

	buildRespawnOverlay(root)
	buildTimer(root)
	-- Crânes de la série chargés d'avance : une image chargée à sa première apparition manquait au premier palier (#364)
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { STREAK_SKULL, STREAK_SKULL_HATCHED })
	end)
	buildLeaderboard(root)
	buildResultBanner(root)
	-- Gains de la manche publiés par le serveur après RoundResult (#394) : l'écran de fin se met à jour à leur arrivée
	for _, name in { EconomyRules.ROUND_ATTRIBUTE, EconomyRules.DAILY_ATTRIBUTE } do
		table.insert(
			creditConns,
			Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
				if resultShown then
					paintCredits()
				end
			end)
		)
	end
	hudStateConn = HUDState.onChanged(applyTimerLayer)
	applyTimerLayer()

	-- Pendant l'écran de fin, Tab maintenu le remplace par le classement complet, rendu au relâchement (#295)
	tabConn = UserInputService.InputBegan:Connect(function(input, _processed)
		if input.KeyCode == Enum.KeyCode.Tab and not training then
			if resultShown then
				resultRoot.Visible = false
			end
			openLeaderboard()
		end
	end)
	tabEndConn = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			leaderboard.Visible = false
			if resultShown then
				resultRoot.Visible = true
			end
		end
	end)
end

function RoundHUD.show()
	if gui then
		gui.Enabled = true
		applyTimerLayer()
	end
	if respawnRoot then
		respawnRoot.Visible = false
	end
	RoundHUD.hideResult()
end

function RoundHUD.hide()
	resultShown = false
	if gui then
		gui.Enabled = false
		applyTimerLayer()
	end
	if deathGrade then
		deathGrade.Enabled = false
	end
end

-- Cette méthode permet de retirer timer, rang et classement (Tab) lorsque le client est sur un serveur d'entraînement
-- (#345) : manche sans fin, sans score ; l'écran de mort reste.
function RoundHUD.setTraining(enabled: boolean)
	training = enabled
	if timerLayer then
		timerLayer.Visible = not enabled
	end
	if enabled and leaderboard then
		leaderboard.Visible = false
	end
end

-- Cette méthode permet de montrer la série de kills du joueur local (KillAnnouncer) lorsqu'elle change : crâne et nombre
-- dès le double kill (KillStreakRules.view), hachuré dès 5, nombre rouge dès 10, flash à un
-- palier annoncé, masqué à la mort et hors partie.
function RoundHUD.setStreak(streak: number)
	if not streakRow then
		return
	end
	local view = KillStreakRules.view(streak)
	streakShown = view.visible
	streakCount.Text = view.count
	streakCountShadow.Text = view.count
	local image = if view.hatched then STREAK_SKULL_HATCHED else STREAK_SKULL
	streakSkull.Image = image
	streakSkullShadow.Image = image
	streakRest = if view.red then C.HitRed else C.Bone
	applyStreakVisible()
	if view.visible and view.tier then
		pulseStreak()
	elseif not view.visible then
		-- série perdue : un flash en cours ne doit pas repeindre l'ancienne couleur
		streakPulse += 1
		streakFlashing = false
		paintStreakRest()
	elseif not streakFlashing then
		paintStreakRest()
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

-- Cette méthode permet de composer le nom d'une ligne du classement lorsqu'il est reconstruit : « (toi) » pour le joueur
-- local, préfixe BOT atténué pour un bot (décision 5 de #133) ; le nom est échappé pour le RichText.
local function scoreName(score: Score, isMe: boolean): string
	local name = HUDRules.escapeRichText(score.name)
	if isMe then
		return name .. "  (toi)"
	end
	if score.isBot then
		return string.format('<font color="#%s">%s</font> %s', C.Muted:ToHex(), ParticipantRules.BOT_PREFIX, name)
	end
	return name
end

-- Cette méthode permet de poser une ligne du classement (rang, nom, K, M, K/M ; bande rouge d'impact pour le joueur local,
-- rang ambré pour le premier si `leader`) lorsque le classement de Tab ou l'écran de fin est reconstruit ; `y` en px.
local function scoreRow(parent: GuiObject, rank: number, score: Score, isMe: boolean, y: number, leader: boolean): Frame
	local row = UIKit.frame({
		Name = "Row" .. rank,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, LB_ROW),
		Parent = parent,
	})
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
		tostring(rank),
		scoreName(score, isMe),
		tostring(score.kills),
		tostring(score.deaths),
		HUDRules.formatKD(score.kills, score.deaths),
	}, { F.Display, isMe and F.Display or F.DisplayMedium, F.Display, F.DisplayMedium, F.DisplayMedium }, {
		(leader and rank == 1) and C.Accent or statColor,
		isMe and C.Bone or C.Text,
		C.Bone,
		statColor,
		statColor,
	}, 20)
	return row
end

-- Cette méthode permet d'écrire le rang (« 3/12 », total en petit) lorsque les scores ou l'échelle du timer changent : la
-- taille du total, écrite dans le texte riche, suit le plancher de lisibilité du HUD réduit (#282) comme le TextSize.
function renderRank()
	local text = "—"
	if rankShown then
		local scale = rankLabel:GetAttribute("HudTextScale")
		local size = if type(scale) == "number"
			then HUDRules.flooredTextSize(RANK_TOTAL_SIZE, scale)
			else RANK_TOTAL_SIZE
		text = string.format('%d<font size="%d" transparency="0.4">/%d</font>', rankShown.rank, size, rankShown.total)
	end
	rankLabel.Text = text
	rankShadow.Text = text
end

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
	rankShown = if rank then { rank = rank, total = #sorted } else nil
	renderRank()

	for i, score in sorted do
		local isMe = not score.isBot and score.name == localName
		local row = scoreRow(leaderboardList, i, score, isMe, (i - 1) * LB_ROW, true)
		row:SetAttribute("Order", i)
	end
end

function RoundHUD.showRespawning(delaySeconds: number)
	if not respawnRoot then
		return
	end
	respawnRoot.Visible = true
	for _, scrim in { respawnScrim, respawnTipScrim } do
		scrim.ImageTransparency = 1
		UIKit.tween(scrim, Motion.Enter, { ImageTransparency = RESPAWN_SCRIM_TRANSPARENCY })
	end
	respawnLabel.Text = "RÉAPPARITION"
	setRespawnLines("ÉLIMINÉ", "", "")
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
				respawnLabel.Text = "RÉAPPARITION…"
				break
			end
			if remaining ~= shown then
				shown = remaining
				popCount(remaining)
			end
			task.wait(0.05)
		end
	end)
end

-- Cette méthode permet d'indiquer qui a tué le joueur sur l'écran de mort lorsque PlayerDied arrive (#102) :
-- « ÉLIMINÉ PAR », nom du tueur, arme et icône du tir à la tête ; sans tueur, « ÉLIMINÉ » et « CHUTE ».
function RoundHUD.setDeathInfo(killer: string?, weapon: string?, headshot: boolean)
	if not respawnTitle then
		return
	end
	if killer then
		local detail, showHeadshot = HUDRules.killDetail(killer, weapon, headshot)
		setRespawnLines("ÉLIMINÉ PAR", string.upper(killer), detail, showHeadshot)
	else
		setRespawnLines("ÉLIMINÉ", (HUDRules.killDetail(nil, weapon, headshot)), "")
	end
end

-- Cette méthode permet d'afficher ou de retirer le conseil de l'écran de mort lorsque le joueur meurt ou que son état
-- débutant, ses réglages ou ses touches changent (#291) : le bloc remonte de la hauteur du conseil, le fondu s'agrandit.
function RoundHUD.setTip(tip: { topic: string, text: string }?)
	if not respawnTip then
		return
	end
	local text = if tip
		then string.format(
			'<font color="#%s">%s :</font> %s',
			C.Accent:ToHex(),
			HUDRules.escapeRichText(tip.topic),
			HUDRules.escapeRichText(tip.text)
		)
		else ""
	-- Réglage sans rapport changé (curseur glissé) : rien à redessiner
	if text == respawnTip.Text and respawnTip.Visible == (tip ~= nil) then
		return
	end
	respawnTip.Text = text
	respawnTip.Visible = tip ~= nil
	respawnTipScrim.Visible = tip ~= nil
	respawnScrim.Visible = tip == nil
	local extra = if tip then RESPAWN_TIP_GAP + RESPAWN_TIP_HEIGHT else 0
	respawnPanel.Size = UDim2.fromOffset(RESPAWN_WIDTH, RESPAWN_HEIGHT + extra)
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

-- Cette méthode permet d'afficher l'écran de fin de manche lorsque RoundResult arrive (#295) : vainqueur (ou « ÉGALITÉ »,
-- « AUCUN VAINQUEUR »), podium et ligne du joueur hors podium ; Tab encore maintenu garde le classement jusqu'au relâchement.
function RoundHUD.showResult(data: any)
	if not resultRoot then
		return
	end
	local view = HUDRules.readRoundResult(data, Players.LocalPlayer.UserId)
	local tabHeld = UserInputService:IsKeyDown(Enum.KeyCode.Tab)
	leaderboard.Visible = tabHeld
	resultName.Text = view.title
	resultNameShadow.Text = view.title
	resultMeBand.Visible = view.meWins
	resultLabel.Text = view.subtitle

	for _, child in resultRows:GetChildren() do
		child:Destroy()
	end
	for i, row in view.podium do
		scoreRow(resultRows, row.rank, row.score, row.isMe, (i - 1) * LB_ROW, view.hasWinner)
	end
	local boardBottom = RESULT_BOARD_TOP + LB_ROW + #view.podium * LB_ROW
	if view.me then
		scoreRow(resultRows, view.me.rank, view.me.score, true, #view.podium * LB_ROW + RESULT_ME_GAP, false)
		boardBottom += RESULT_ME_GAP + LB_ROW
	end
	resultCredits.Position = UDim2.fromOffset(0, boardBottom + RESULT_CREDITS_GAP)
	paintCredits()

	resultShown = true
	resultRoot.Visible = not tabHeld
	resultVeil.BackgroundTransparency = 1
	UIKit.tween(resultVeil, Motion.Enter, { BackgroundTransparency = 0 })
	UIKit.reveal(resultContent, 0.15, 16)
end

function RoundHUD.hideResult()
	resultShown = false
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
	if hudStateConn then
		hudStateConn()
		hudStateConn = nil
	end
	for _, conn in creditConns do
		conn:Disconnect()
	end
	table.clear(creditConns)
	if deathGrade then
		deathGrade:Destroy()
	end
	timerLayer = nil :: any -- applyTimerLayer n'agit plus sur des Instances détruites
	if timerOverMenuGui then
		timerOverMenuGui:Destroy()
	end
	if gui then
		gui:Destroy()
	end
end

return RoundHUD

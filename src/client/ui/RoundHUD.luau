local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.UITheme)

local RoundHUD = {}

local C = UITheme.Color
local F = UITheme.Font
local TS = UITheme.TextSize
local R = UITheme.Radius
local THIN = UITheme.Stroke.THIN

local gui: ScreenGui
local timerLabel: TextLabel
local leaderboardFrame: Frame
local leaderboardList: Frame
local respawnFrame: Frame
local respawnLabel: TextLabel
local resultFrame: Frame
local resultLabel: TextLabel

local tabConn: RBXScriptConnection?
local respawnTask: thread?

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

local function addStripe(parent: GuiObject, color: Color3)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, UITheme.Stroke.STRIPE, 0.65, 0)
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.fromScale(0, 0.5)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = parent
	addCorner(stripe, R.SM)
end

-- ── Timer ──────────────────────────────────────────────────────────────────────

local function buildTimer(parent: Frame)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(112, 38)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 12)
	frame.BackgroundColor3 = C.SURFACE
	frame.BackgroundTransparency = UITheme.Transparency.HUD
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addCorner(frame, R.MD)
	addStroke(frame, C.BORDER, THIN)

	timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.fromScale(1, 1)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "5:00"
	timerLabel.TextColor3 = C.TEXT
	timerLabel.Font = F.MONO
	timerLabel.TextSize = TS.TIMER
	timerLabel.Parent = frame
end

-- ── Leaderboard ────────────────────────────────────────────────────────────────

local function buildLeaderboard(parent: Frame)
	leaderboardFrame = Instance.new("Frame")
	leaderboardFrame.Size = UDim2.fromOffset(400, 440)
	leaderboardFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	leaderboardFrame.Position = UDim2.fromScale(0.5, 0.46)
	leaderboardFrame.BackgroundColor3 = C.SURFACE
	leaderboardFrame.BorderSizePixel = 0
	leaderboardFrame.Visible = false
	leaderboardFrame.Parent = parent
	addCorner(leaderboardFrame, R.LG)
	addStroke(leaderboardFrame, C.BORDER, THIN)
	addStripe(leaderboardFrame, C.ACCENT)

	local titleRow = Instance.new("Frame")
	titleRow.Size = UDim2.new(1, -24, 0, 44)
	titleRow.Position = UDim2.fromOffset(12, 0)
	titleRow.BackgroundTransparency = 1
	titleRow.Parent = leaderboardFrame

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.fromScale(1, 1)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "LEADERBOARD"
	titleLbl.TextColor3 = C.TEXT
	titleLbl.Font = F.DISPLAY
	titleLbl.TextSize = TS.BUTTON
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = titleRow

	local colRow = Instance.new("Frame")
	colRow.Size = UDim2.new(1, -24, 0, 24)
	colRow.Position = UDim2.fromOffset(12, 44)
	colRow.BackgroundTransparency = 1
	colRow.Parent = leaderboardFrame

	local function colHeader(text: string, xScale: number, wScale: number, align: Enum.TextXAlignment)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(wScale, 1)
		lbl.Position = UDim2.fromScale(xScale, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = C.MUTED
		lbl.Font = F.LABEL
		lbl.TextSize = TS.LABEL
		lbl.TextXAlignment = align
		lbl.Parent = colRow
	end

	colHeader("#", 0, 0.08, Enum.TextXAlignment.Center)
	colHeader("JOUEUR", 0.08, 0.54, Enum.TextXAlignment.Left)
	colHeader("K", 0.62, 0.19, Enum.TextXAlignment.Center)
	colHeader("D", 0.81, 0.19, Enum.TextXAlignment.Center)

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -24, 0, 1)
	sep.Position = UDim2.fromOffset(12, 68)
	sep.BackgroundColor3 = C.BORDER
	sep.BorderSizePixel = 0
	sep.Parent = leaderboardFrame

	leaderboardList = Instance.new("Frame")
	leaderboardList.Size = UDim2.new(1, -24, 1, -76)
	leaderboardList.Position = UDim2.fromOffset(12, 74)
	leaderboardList.BackgroundTransparency = 1
	leaderboardList.Parent = leaderboardFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = leaderboardList
end

-- ── Respawn overlay ────────────────────────────────────────────────────────────

local function buildRespawnOverlay(parent: Frame)
	respawnFrame = Instance.new("Frame")
	respawnFrame.Size = UDim2.fromOffset(280, 56)
	respawnFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	respawnFrame.Position = UDim2.fromScale(0.5, 0.5)
	respawnFrame.BackgroundColor3 = C.SURFACE
	respawnFrame.BorderSizePixel = 0
	respawnFrame.Visible = false
	respawnFrame.Parent = parent
	addCorner(respawnFrame, R.MD)
	addStroke(respawnFrame, C.COMBAT, THIN)
	addStripe(respawnFrame, C.COMBAT)

	respawnLabel = Instance.new("TextLabel")
	respawnLabel.Size = UDim2.fromScale(1, 1)
	respawnLabel.BackgroundTransparency = 1
	respawnLabel.TextColor3 = C.TEXT
	respawnLabel.Font = F.LABEL
	respawnLabel.TextSize = TS.BUTTON
	respawnLabel.Parent = respawnFrame
end

-- ── Result banner ──────────────────────────────────────────────────────────────

local function buildResultBanner(parent: Frame)
	resultFrame = Instance.new("Frame")
	resultFrame.Size = UDim2.fromOffset(480, 84)
	resultFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	resultFrame.Position = UDim2.fromScale(0.5, 0.4)
	resultFrame.BackgroundColor3 = C.SURFACE
	resultFrame.BorderSizePixel = 0
	resultFrame.Visible = false
	resultFrame.Parent = parent
	addCorner(resultFrame, R.LG)
	addStroke(resultFrame, C.COMBAT, THIN)

	local topLine = Instance.new("Frame")
	topLine.Size = UDim2.new(0.38, 0, 0, 2)
	topLine.AnchorPoint = Vector2.new(0.5, 0)
	topLine.Position = UDim2.fromScale(0.5, 0)
	topLine.BackgroundColor3 = C.COMBAT
	topLine.BorderSizePixel = 0
	topLine.Parent = resultFrame

	resultLabel = Instance.new("TextLabel")
	resultLabel.Size = UDim2.fromScale(1, 1)
	resultLabel.BackgroundTransparency = 1
	resultLabel.TextColor3 = C.TEXT
	resultLabel.Font = F.HEADING
	resultLabel.TextSize = TS.BANNER
	resultLabel.Parent = resultFrame
end

-- ── API publique ───────────────────────────────────────────────────────────────

function RoundHUD.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "RoundHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	buildTimer(root)
	buildLeaderboard(root)
	buildRespawnOverlay(root)
	buildResultBanner(root)

	tabConn = UserInputService.InputBegan:Connect(function(input, _processed)
		if input.KeyCode == Enum.KeyCode.Tab then
			leaderboardFrame.Visible = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			leaderboardFrame.Visible = false
		end
	end)
end

function RoundHUD.show()
	if gui then
		gui.Enabled = true
	end
	if respawnFrame then
		respawnFrame.Visible = false
	end
	if resultFrame then
		resultFrame.Visible = false
	end
end

function RoundHUD.hide()
	if gui then
		gui.Enabled = false
	end
end

function RoundHUD.updateTimer(seconds: number)
	if not timerLabel then
		return
	end
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	timerLabel.Text = string.format("%d:%02d", m, s)
	timerLabel.TextColor3 = seconds <= 30 and C.WARN or C.TEXT
end

type Score = { name: string, kills: number, deaths: number }

function RoundHUD.updateScores(scores: { [number]: Score })
	if not leaderboardList then
		return
	end
	for _, child in leaderboardList:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local sorted = {}
	for _, s in pairs(scores) do
		table.insert(sorted, s)
	end
	table.sort(sorted, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.deaths < b.deaths
	end)

	for i, score in sorted do
		local isTop = i == 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = i % 2 == 0 and C.SURFACE_RAISED or C.SURFACE
		row.BackgroundTransparency = i % 2 == 0 and 0 or UITheme.Transparency.ROW_ODD
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = leaderboardList
		addCorner(row, R.SM)

		local rankLbl = Instance.new("TextLabel")
		rankLbl.Size = UDim2.fromScale(0.08, 1)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Text = tostring(i)
		rankLbl.TextColor3 = isTop and C.ACCENT or C.MUTED
		rankLbl.Font = isTop and F.HEADING or F.LABEL
		rankLbl.TextSize = TS.BODY
		rankLbl.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.fromScale(0.54, 1)
		nameLbl.Position = UDim2.fromScale(0.08, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = score.name
		nameLbl.TextColor3 = isTop and C.TEXT or C.TEXT_DIM
		nameLbl.Font = isTop and F.LABEL or F.BODY
		nameLbl.TextSize = TS.BODY
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = row

		local killLbl = Instance.new("TextLabel")
		killLbl.Size = UDim2.fromScale(0.19, 1)
		killLbl.Position = UDim2.fromScale(0.62, 0)
		killLbl.BackgroundTransparency = 1
		killLbl.Text = tostring(score.kills)
		killLbl.TextColor3 = isTop and C.ACCENT or C.TEXT
		killLbl.Font = F.MONO
		killLbl.TextSize = TS.BODY
		killLbl.Parent = row

		local deathLbl = Instance.new("TextLabel")
		deathLbl.Size = UDim2.fromScale(0.19, 1)
		deathLbl.Position = UDim2.fromScale(0.81, 0)
		deathLbl.BackgroundTransparency = 1
		deathLbl.Text = tostring(score.deaths)
		deathLbl.TextColor3 = C.MUTED
		deathLbl.Font = F.MONO
		deathLbl.TextSize = TS.BODY
		deathLbl.Parent = row
	end
end

function RoundHUD.showRespawning(delaySeconds: number)
	if not respawnFrame then
		return
	end
	respawnFrame.Visible = true
	local endTime = tick() + delaySeconds

	if respawnTask then
		task.cancel(respawnTask)
	end
	respawnTask = task.spawn(function()
		while respawnFrame.Visible do
			local remaining = math.ceil(endTime - tick())
			if remaining <= 0 then
				respawnLabel.Text = "Réapparition..."
				break
			end
			respawnLabel.Text = string.format("Réapparition dans %ds", remaining)
			task.wait(0.1)
		end
	end)
end

function RoundHUD.hideRespawning()
	if respawnFrame then
		respawnFrame.Visible = false
	end
	if respawnTask then
		task.cancel(respawnTask)
		respawnTask = nil
	end
end

function RoundHUD.showResult(winnerName: string)
	if not resultFrame then
		return
	end
	resultLabel.Text = string.format("🏆  %s  remporte le round !", winnerName)
	resultFrame.Visible = true
end

function RoundHUD.hideResult()
	if resultFrame then
		resultFrame.Visible = false
	end
end

function RoundHUD.destroy()
	if tabConn then
		tabConn:Disconnect()
		tabConn = nil
	end
	if gui then
		gui:Destroy()
	end
end

return RoundHUD

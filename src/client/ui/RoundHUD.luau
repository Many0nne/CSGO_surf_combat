local UserInputService = game:GetService("UserInputService")

local RoundHUD = {}

local TEXT_COLOR  = Color3.fromRGB(210, 215, 225)
local MUTED       = Color3.fromRGB(120, 130, 150)
local BG_COLOR    = Color3.fromRGB(12, 14, 20)
local FONT        = Enum.Font.GothamBold
local FONT_L      = Enum.Font.GothamMedium

local gui: ScreenGui
local timerLabel: TextLabel
local leaderboardFrame: Frame
local leaderboardList: Frame
local respawnFrame: Frame
local respawnLabel: TextLabel
local resultFrame: Frame
local resultLabel: TextLabel

local tabConn:    RBXScriptConnection?
local respawnTask: thread?

-- ── Construction ────────────────────────────────────────────────────────────

local function buildTimer(parent: Frame)
	timerLabel = Instance.new("TextLabel")
	timerLabel.Size              = UDim2.new(0, 120, 0, 36)
	timerLabel.AnchorPoint       = Vector2.new(0.5, 0)
	timerLabel.Position          = UDim2.new(0.5, 0, 0, 10)
	timerLabel.BackgroundColor3  = BG_COLOR
	timerLabel.BackgroundTransparency = 0.4
	timerLabel.BorderSizePixel   = 0
	timerLabel.Text              = "5:00"
	timerLabel.TextColor3        = TEXT_COLOR
	timerLabel.Font              = FONT
	timerLabel.TextSize          = 22
	timerLabel.Parent            = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = timerLabel
end

local function buildLeaderboard(parent: Frame)
	leaderboardFrame = Instance.new("Frame")
	leaderboardFrame.Size            = UDim2.new(0, 380, 0, 400)
	leaderboardFrame.AnchorPoint     = Vector2.new(0.5, 0.3)
	leaderboardFrame.Position        = UDim2.fromScale(0.5, 0.3)
	leaderboardFrame.BackgroundColor3 = BG_COLOR
	leaderboardFrame.BackgroundTransparency = 0.15
	leaderboardFrame.BorderSizePixel = 0
	leaderboardFrame.Visible         = false
	leaderboardFrame.Parent          = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = leaderboardFrame

	local headerRow = Instance.new("Frame")
	headerRow.Size             = UDim2.new(1, -24, 0, 36)
	headerRow.Position         = UDim2.fromOffset(12, 8)
	headerRow.BackgroundTransparency = 1
	headerRow.Parent           = leaderboardFrame

	local function makeHeaderLabel(text: string, xScale: number, wScale: number, align: Enum.TextXAlignment)
		local lbl = Instance.new("TextLabel")
		lbl.Size            = UDim2.new(wScale, 0, 1, 0)
		lbl.Position        = UDim2.fromScale(xScale, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text            = text
		lbl.TextColor3      = MUTED
		lbl.Font            = FONT
		lbl.TextSize        = 12
		lbl.TextXAlignment  = align
		lbl.Parent          = headerRow
	end

	makeHeaderLabel("JOUEUR", 0,   0.6, Enum.TextXAlignment.Left)
	makeHeaderLabel("KILLS",  0.6, 0.2, Enum.TextXAlignment.Left)
	makeHeaderLabel("MORTS",  0.8, 0.2, Enum.TextXAlignment.Left)

	local sep = Instance.new("Frame")
	sep.Size             = UDim2.new(1, -24, 0, 1)
	sep.Position         = UDim2.fromOffset(12, 44)
	sep.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	sep.BorderSizePixel  = 0
	sep.Parent           = leaderboardFrame

	leaderboardList = Instance.new("Frame")
	leaderboardList.Size             = UDim2.new(1, -24, 1, -56)
	leaderboardList.Position         = UDim2.fromOffset(12, 52)
	leaderboardList.BackgroundTransparency = 1
	leaderboardList.Parent           = leaderboardFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder   = Enum.SortOrder.LayoutOrder
	layout.Padding      = UDim.new(0, 2)
	layout.Parent       = leaderboardList
end

local function buildRespawnOverlay(parent: Frame)
	respawnFrame = Instance.new("Frame")
	respawnFrame.Size            = UDim2.new(0, 220, 0, 48)
	respawnFrame.AnchorPoint     = Vector2.new(0.5, 1)
	respawnFrame.Position        = UDim2.new(0.5, 0, 1, -40)
	respawnFrame.BackgroundColor3 = BG_COLOR
	respawnFrame.BackgroundTransparency = 0.3
	respawnFrame.BorderSizePixel = 0
	respawnFrame.Visible         = false
	respawnFrame.Parent          = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = respawnFrame

	respawnLabel = Instance.new("TextLabel")
	respawnLabel.Size             = UDim2.fromScale(1, 1)
	respawnLabel.BackgroundTransparency = 1
	respawnLabel.TextColor3       = TEXT_COLOR
	respawnLabel.Font             = FONT_L
	respawnLabel.TextSize         = 15
	respawnLabel.Parent           = respawnFrame
end

local function buildResultBanner(parent: Frame)
	resultFrame = Instance.new("Frame")
	resultFrame.Size            = UDim2.new(0, 460, 0, 90)
	resultFrame.AnchorPoint     = Vector2.new(0.5, 0.5)
	resultFrame.Position        = UDim2.fromScale(0.5, 0.4)
	resultFrame.BackgroundColor3 = BG_COLOR
	resultFrame.BackgroundTransparency = 0.15
	resultFrame.BorderSizePixel = 0
	resultFrame.Visible         = false
	resultFrame.Parent          = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = resultFrame

	resultLabel = Instance.new("TextLabel")
	resultLabel.Size             = UDim2.fromScale(1, 1)
	resultLabel.BackgroundTransparency = 1
	resultLabel.TextColor3       = TEXT_COLOR
	resultLabel.Font             = FONT
	resultLabel.TextSize         = 22
	resultLabel.Parent           = resultFrame
end

-- ── API publique ─────────────────────────────────────────────────────────────

function RoundHUD.init()
	gui = Instance.new("ScreenGui")
	gui.Name           = "RoundHUD"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled        = false
	gui.Parent         = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Size             = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent           = gui

	buildTimer(root)
	buildLeaderboard(root)
	buildRespawnOverlay(root)
	buildResultBanner(root)

	-- Tab leaderboard (on ignore processed : Roblox consomme Tab pour son leaderboard natif)
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
	if gui then gui.Enabled = true end
	if respawnFrame then respawnFrame.Visible = false end
	if resultFrame then resultFrame.Visible = false end
end

function RoundHUD.hide()
	if gui then gui.Enabled = false end
end

function RoundHUD.updateTimer(seconds: number)
	if not timerLabel then return end
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	timerLabel.Text = string.format("%d:%02d", m, s)
	-- Rouge dans les 30 dernières secondes
	timerLabel.TextColor3 = seconds <= 30 and Color3.fromRGB(220, 80, 80) or TEXT_COLOR
end

type Score = { name: string, kills: number, deaths: number }

function RoundHUD.updateScores(scores: { [number]: Score })
	if not leaderboardList then return end
	-- Vider
	for _, child in leaderboardList:GetChildren() do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
	-- Trier par kills desc
	local sorted = {}
	for _, s in pairs(scores) do table.insert(sorted, s) end
	table.sort(sorted, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.deaths < b.deaths
	end)

	for i, score in sorted do
		local row = Instance.new("Frame")
		row.Size             = UDim2.new(1, 0, 0, 26)
		row.BackgroundTransparency = i % 2 == 0 and 0.9 or 1
		row.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
		row.BorderSizePixel  = 0
		row.LayoutOrder      = i
		row.Parent           = leaderboardList

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size            = UDim2.new(0.6, 0, 1, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text            = score.name
		nameLbl.TextColor3      = TEXT_COLOR
		nameLbl.Font            = FONT_L
		nameLbl.TextSize        = 13
		nameLbl.TextXAlignment  = Enum.TextXAlignment.Left
		nameLbl.Parent          = row

		local killLbl = Instance.new("TextLabel")
		killLbl.Size            = UDim2.new(0.2, 0, 1, 0)
		killLbl.Position        = UDim2.fromScale(0.6, 0)
		killLbl.BackgroundTransparency = 1
		killLbl.Text            = tostring(score.kills)
		killLbl.TextColor3      = TEXT_COLOR
		killLbl.Font            = FONT
		killLbl.TextSize        = 13
		killLbl.Parent          = row

		local deathLbl = Instance.new("TextLabel")
		deathLbl.Size           = UDim2.new(0.2, 0, 1, 0)
		deathLbl.Position       = UDim2.fromScale(0.8, 0)
		deathLbl.BackgroundTransparency = 1
		deathLbl.Text           = tostring(score.deaths)
		deathLbl.TextColor3     = MUTED
		deathLbl.Font           = FONT_L
		deathLbl.TextSize       = 13
		deathLbl.Parent         = row
	end
end

function RoundHUD.showRespawning(delaySeconds: number)
	if not respawnFrame then return end
	respawnFrame.Visible = true
	local endTime = tick() + delaySeconds

	if respawnTask then task.cancel(respawnTask) end
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
	if respawnFrame then respawnFrame.Visible = false end
	if respawnTask then task.cancel(respawnTask); respawnTask = nil end
end

function RoundHUD.showResult(winnerName: string)
	if not resultFrame then return end
	resultLabel.Text    = string.format("🏆  %s  remporte le round !", winnerName)
	resultFrame.Visible = true
end

function RoundHUD.hideResult()
	if resultFrame then resultFrame.Visible = false end
end

function RoundHUD.destroy()
	if tabConn then tabConn:Disconnect(); tabConn = nil end
	if gui then gui:Destroy() end
end

return RoundHUD

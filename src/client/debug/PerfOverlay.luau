-- PerfOverlay.luau (client)
-- Overlay de mesure des performances, ouvert avec F3 (cf. docs/performance.md). Disponible dans Studio et, dans le
-- jeu publié, pour le seul créateur du jeu. Affiche le rythme des frames, le coût du rendu (CPU, GPU, draw calls,
-- triangles), la mémoire par catégorie, le réseau et le coût de nos boucles par frame (PerfMarkers). Tant qu'il est
-- ouvert, une ligne `[Perf] BILAN` est écrite dans la console (F9) toutes les 10 s pour comparer deux postes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProbeRules = require(Shared:WaitForChild("FrameProbeRules"))
local MemoryTracker = require(Shared:WaitForChild("MemoryTracker"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local PerfMarkers = require(Shared:WaitForChild("PerfMarkers"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))

local TOGGLE_KEY = Enum.KeyCode.F3
local ATTRIBUTE = "PerfOverlay" -- attribut joueur : true ouvre, false ferme (même effet que F3)
local WINDOW = 600 -- frames gardées pour la médiane, le p99 et le max (environ 10 s à 60 FPS)
local REFRESH_PERIOD = 0.5 -- secondes entre deux rafraîchissements du texte
local LOG_PERIOD = 10 -- secondes entre deux lignes BILAN dans la console
local MAX_MARKERS = 8 -- lignes de scripts affichées
local SNAPSHOT_DELAY = 3 -- secondes après un spawn ou une fin de round avant le relevé mémoire (setup terminé)

local PerfOverlay = {}

local gui: ScreenGui?
local label: TextLabel?
local renderConn: RBXScriptConnection?
local open = false
local dts: { number } = {}
local cursor = 0
local framesSinceRefresh = 0
local lastRefresh = 0
local lastLog = 0
local openedAt = 0
local logFrames = 0
local logTotals: PerfRules.MarkerTotals = {}

-- Cette méthode permet de lire le réglage graphique du joueur lorsque l'overlay compare deux postes (« auto » ou 1-10).
local function qualityText(): string
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or not level then
		return "?"
	end
	if level == Enum.SavedQualitySetting.Automatic then
		return "auto"
	end
	return tostring(level.Value) .. "/10"
end

-- Cette méthode permet d'ajouter les totaux d'un relevé de repères à ceux de la période de bilan lorsque l'overlay
-- se rafraîchit (le bilan console couvre LOG_PERIOD, l'affichage la dernière demi-seconde).
local function accumulate(into: PerfRules.MarkerTotals, from: PerfRules.MarkerTotals)
	for name, t in from do
		local acc = into[name]
		if not acc then
			into[name] = { time = t.time, calls = t.calls, max = t.max }
		else
			acc.time += t.time
			acc.calls += t.calls
			acc.max = math.max(acc.max, t.max)
		end
	end
end

-- Cette méthode permet de résumer les frames gardées (FPS médian, p99, max) lorsque l'overlay ou le bilan les affiche.
local function frameSummary(): { fps: number, p99Ms: number, maxMs: number }
	if #dts == 0 then
		return { fps = 0, p99Ms = 0, maxMs = 0 }
	end
	return FrameProbeRules.summarize(table.clone(dts))
end

-- Cette méthode permet de rédiger le texte de l'overlay lorsque la période de rafraîchissement est écoulée.
local function buildText(markers: { PerfRules.MarkerLine }): string
	local s = frameSummary()
	local tags = MemoryTracker.readTags()
	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.zero
	local lines = {
		string.format(
			"PERF (F3 pour fermer)   qualité %s   %dx%d",
			qualityText(),
			math.floor(viewport.X),
			math.floor(viewport.Y)
		),
		string.format("FPS %.0f médian   p99 %.1f ms   max %.1f ms   (%d frames)", s.fps, s.p99Ms, s.maxMs, #dts),
		string.format(
			"CPU rendu %.1f ms   GPU %.1f ms   Heartbeat %.2f ms   Physique %.2f ms",
			Stats.RenderCPUFrameTime * 1000,
			Stats.RenderGPUFrameTime * 1000,
			Stats.HeartbeatTime * 1000,
			Stats.PhysicsStepTime * 1000
		),
		string.format(
			"Draw calls scène %d   ombres %d   UI %d   triangles %.0fk (ombres %.0fk)",
			Stats.SceneDrawcallCount,
			Stats.ShadowsDrawcallCount,
			Stats.UI2DDrawcallCount + Stats.UI3DDrawcallCount,
			Stats.SceneTriangleCount / 1000,
			Stats.ShadowsTriangleCount / 1000
		),
		string.format(
			"Instances %d   pièces %d (mobiles %d)   contacts %d",
			Stats.InstanceCount,
			Stats.PrimitivesCount,
			Stats.MovingPrimitivesCount,
			Stats.ContactsCount
		),
		string.format(
			"Mémoire %.0f Mo   tas Lua %.1f Mo   réseau ↓ %.1f ↑ %.1f kB/s",
			Stats:GetTotalMemoryUsageMb(),
			gcinfo() / 1024,
			Stats.DataReceiveKbps,
			Stats.DataSendKbps
		),
	}
	local mem = {}
	for _, entry in PerfRules.OVERLAY_TAGS do
		table.insert(mem, string.format("%s %.0f", entry.label, tags[entry.tag] or 0))
	end
	table.insert(lines, "  " .. table.concat(mem, "  ", 1, 7))
	table.insert(lines, "  " .. table.concat(mem, "  ", 8))
	table.insert(lines, "Scripts           ms/frame  appels/frame  max ms")
	for i, m in markers do
		if i > MAX_MARKERS then
			break
		end
		table.insert(
			lines,
			string.format("  %-16s %6.2f %10.1f %9.2f", m.label, m.msPerFrame, m.callsPerFrame, m.maxMs)
		)
	end
	return table.concat(lines, "\n")
end

-- Cette méthode permet d'écrire dans la console le bilan de la période écoulée lorsque l'overlay est ouvert depuis
-- LOG_PERIOD secondes ou se ferme.
local function logSummary()
	if logFrames == 0 then
		return
	end
	local s = frameSummary()
	local scripts = {}
	for i, m in PerfRules.markerReport(logTotals, logFrames) do
		if i > MAX_MARKERS then
			break
		end
		table.insert(scripts, string.format("%s %.2fms×%.1f", m.label, m.msPerFrame, m.callsPerFrame))
	end
	print(
		string.format(
			"[Perf] BILAN t=%.0fs FPS %.0f p99 %.1fms max %.1fms | CPU %.1fms GPU %.1fms | draw %d+%d ombres, tri %.0fk"
				.. " | mém %.0f Mo, Lua %.1f Mo | qualité %s | scripts : %s",
			os.clock() - openedAt,
			s.fps,
			s.p99Ms,
			s.maxMs,
			Stats.RenderCPUFrameTime * 1000,
			Stats.RenderGPUFrameTime * 1000,
			Stats.SceneDrawcallCount,
			Stats.ShadowsDrawcallCount,
			Stats.SceneTriangleCount / 1000,
			Stats:GetTotalMemoryUsageMb(),
			gcinfo() / 1024,
			qualityText(),
			table.concat(scripts, ", ")
		)
	)
	logFrames = 0
	logTotals = {}
	lastLog = os.clock()
end

-- Cette méthode permet de relever chaque frame rendue puis de rafraîchir l'affichage lorsque la période est écoulée.
local function onRender(dt: number)
	cursor = cursor % WINDOW + 1
	dts[cursor] = dt
	framesSinceRefresh += 1
	logFrames += 1
	local now = os.clock()
	if now - lastRefresh >= REFRESH_PERIOD then
		local totals = PerfMarkers.collect()
		accumulate(logTotals, totals)
		if label then
			label.Text = buildText(PerfRules.markerReport(totals, framesSinceRefresh))
		end
		framesSinceRefresh = 0
		lastRefresh = now
	end
	if now - lastLog >= LOG_PERIOD then
		logSummary()
	end
end

-- Cette méthode permet de créer l'interface de l'overlay lorsqu'il s'ouvre pour la première fois.
local function buildGui(player: Player)
	local screen = Instance.new("ScreenGui")
	screen.Name = "PerfOverlay"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1000
	screen.Enabled = false

	local text = Instance.new("TextLabel")
	text.Name = "Stats"
	text.AutomaticSize = Enum.AutomaticSize.XY
	text.Position = UDim2.fromOffset(8, 64)
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.BackgroundTransparency = 0.35
	text.BorderSizePixel = 0
	text.Font = Enum.Font.Code
	text.TextSize = 14
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = "PERF : mesure en cours…"
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = text
	text.Parent = screen

	screen.Parent = player:WaitForChild("PlayerGui")
	gui, label = screen, text
end

-- Cette méthode permet d'ouvrir ou de fermer l'overlay lorsque le joueur appuie sur F3 ou que l'attribut `PerfOverlay`
-- change (mesure remise à zéro à l'ouverture, dernier bilan à la fermeture ; rien si l'état demandé est déjà le bon).
local function setOpen(player: Player, wanted: boolean)
	if wanted == open then
		return
	end
	if not gui then
		buildGui(player)
	end
	open = wanted
	if open then
		dts, cursor, framesSinceRefresh, logFrames, logTotals = {}, 0, 0, 0, {}
		openedAt = os.clock()
		lastRefresh, lastLog = openedAt, openedAt
		PerfMarkers.collect()
		PerfMarkers.timing = true
		renderConn = RunService.RenderStepped:Connect(onRender)
		print("[Perf] overlay ouvert : une ligne BILAN toutes les " .. LOG_PERIOD .. " s")
		MemoryTracker.snapshot("ouverture overlay")
	else
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		logSummary()
		PerfMarkers.timing = false
		print("[Perf] overlay fermé")
	end
	if gui then
		gui.Enabled = open
	end
end

-- Cette méthode permet de vérifier le droit de mesurer lorsque le client démarre (Studio, ou créateur du jeu publié).
local function isAllowed(player: Player): boolean
	local ownedByUser = game.CreatorType == Enum.CreatorType.User
	return PerfRules.canUse(RunService:IsStudio(), player.UserId, game.CreatorId, ownedByUser)
end

-- Cette méthode permet de brancher la touche F3 et les relevés mémoire lorsque le joueur a le droit de mesurer
-- (ne fait rien pour les autres joueurs du jeu publié).
function PerfOverlay.init(player: Player?)
	local localPlayer = player or Players.LocalPlayer
	if not isAllowed(localPlayer) then
		return
	end
	task.spawn(function()
		MemoryTracker.enable()
		MemoryTracker.snapshot("démarrage")
		-- Relevés du cycle de vie : une hausse qui s'accumule de spawn en spawn signale une fuite (#77).
		localPlayer.CharacterAdded:Connect(function()
			task.delay(SNAPSHOT_DELAY, MemoryTracker.snapshot, "spawn")
		end)
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.KeyCode ~= TOGGLE_KEY then
				return
			end
			setOpen(localPlayer, not open)
		end)
		-- Même effet que F3 par attribut, pour une mesure pilotée par script (MCP Studio, cf. docs/performance.md).
		localPlayer:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			setOpen(localPlayer, localPlayer:GetAttribute(ATTRIBUTE) == true)
		end)
		local roundResult = NetworkProtocol.getRemote(NetworkProtocol.Names.ROUND_RESULT)
		if roundResult then
			roundResult.OnClientEvent:Connect(function()
				task.delay(SNAPSHOT_DELAY, MemoryTracker.snapshot, "fin de round")
			end)
		end
	end)
end

return PerfOverlay

-- PerfBench.luau (client)
-- Banc de rendu lancé avec F4 (cf. docs/performance.md, « Banc F4 ») : dans Studio et, dans le jeu publié, pour le seul
-- créateur du jeu. Coupe les leviers de rendu l'un après l'autre (ombres, Atmosphere, effets, translucides de chaque
-- dossier de la map), relève le temps GPU et CPU du rendu à chaque phase et écrit une ligne `[Perf] BANC` par phase.
-- Tout est rétabli à la fin, ou si on rappuie sur F4. Seul le poste qui lance le banc est touché.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))

local TOGGLE_KEY = Enum.KeyCode.F4
local ATTRIBUTE = "PerfBench" -- attribut joueur : true lance (ou annule) le banc, comme F4
local SETTLE = 2 -- secondes laissées au moteur après un changement avant de mesurer
local MEASURE = 6 -- secondes mesurées par phase

type Lever = { name: string, apply: () -> (), restore: () -> () }

local PerfBench = {}

local running = false
local cancelled = false
local status: TextLabel?

-- Cette méthode permet d'afficher l'avancement du banc à l'écran lorsqu'une phase commence ou que le banc s'arrête
-- (le texte reste aussi dans la console via print).
local function setStatus(player: Player, text: string?)
	if not status then
		local screen = Instance.new("ScreenGui")
		screen.Name = "PerfBench"
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = 1001
		local label = Instance.new("TextLabel")
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 72)
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.BackgroundTransparency = 0.3
		label.BorderSizePixel = 0
		label.Font = Enum.Font.Code
		label.TextSize = 16
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = screen
		screen.Parent = player:WaitForChild("PlayerGui")
		status = label
	end
	local label = status :: TextLabel
	label.Visible = text ~= nil
	label.Text = text or ""
end

-- Cette méthode permet de trouver la map jouée lorsque le banc liste les dossiers à tester (map active, sinon la
-- première du dossier Maps).
local function activeMap(): Instance?
	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		return nil
	end
	return maps:FindFirstChild(GameConfig.ACTIVE_MAP) or maps:GetChildren()[1]
end

-- Cette méthode permet de construire un levier qui masque localement les pièces translucides d'un dossier lorsque
-- ce dossier en contient (LocalTransparencyModifier : rien n'est répliqué ni modifié pour les autres joueurs).
local function translucentLever(folder: Instance): Lever?
	local parts: { BasePart } = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency > 0 and d.Transparency < 1 then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return nil
	end
	return {
		name = string.format("sans translucides %s (%d)", folder.Name, #parts),
		apply = function()
			for _, p in parts do
				p.LocalTransparencyModifier = 1
			end
		end,
		restore = function()
			for _, p in parts do
				p.LocalTransparencyModifier = 0
			end
		end,
	}
end

-- Cette méthode permet de lister les leviers de rendu présents dans la scène lorsque le banc démarre (chaque levier
-- sait se rétablir dans son état d'origine).
local function buildLevers(): { Lever }
	local levers: { Lever } = {}
	local shadows = Lighting.GlobalShadows
	table.insert(levers, {
		name = "sans ombres",
		apply = function()
			Lighting.GlobalShadows = false
		end,
		restore = function()
			Lighting.GlobalShadows = shadows
		end,
	})
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		table.insert(levers, {
			name = "sans Atmosphere",
			apply = function()
				atmosphere.Parent = nil
			end,
			restore = function()
				atmosphere.Parent = Lighting
			end,
		})
	end
	local effects: { { effect: PostEffect, enabled: boolean } } = {}
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") and child.Enabled then
			table.insert(effects, { effect = child, enabled = true })
		end
	end
	if #effects > 0 then
		local names = {}
		for _, e in effects do
			table.insert(names, (e.effect.ClassName:gsub("Effect$", "")))
		end
		table.insert(levers, {
			name = "sans effets (" .. table.concat(names, "+") .. ")",
			apply = function()
				for _, e in effects do
					e.effect.Enabled = false
				end
			end,
			restore = function()
				for _, e in effects do
					e.effect.Enabled = e.enabled
				end
			end,
		})
	end
	local map = activeMap()
	local mapLevers = 0
	if map then
		for _, folder in map:GetChildren() do
			local lever = translucentLever(folder)
			if lever then
				table.insert(levers, lever)
				mapLevers += 1
			end
		end
	end
	if mapLevers == 0 then
		-- Si StreamingEnabled était réactivé, la map ne serait chargée qu'autour du personnage : rien au menu.
		print("[Perf] BANC : aucun translucide de map chargé sur ce client, lancer le banc en jeu (pas au menu)")
	end
	return levers
end

-- Cette méthode permet de mesurer une phase lorsque ses réglages sont posés : attend SETTLE s, relève MEASURE s, et
-- signale si la fenêtre a perdu le focus pendant la phase (mesure faussée).
local function measure(): (PerfRules.BenchSummary, boolean)
	task.wait(SETTLE)
	local gpu, cpu, frames = {}, {}, {}
	local focusLost = false
	local focusConn = UserInputService.WindowFocusReleased:Connect(function()
		focusLost = true
	end)
	local renderConn = RunService.RenderStepped:Connect(function(dt)
		table.insert(gpu, Stats.RenderGPUFrameTime * 1000)
		table.insert(cpu, Stats.RenderCPUFrameTime * 1000)
		table.insert(frames, dt * 1000)
	end)
	task.wait(MEASURE)
	renderConn:Disconnect()
	focusConn:Disconnect()
	return PerfRules.benchSummary(gpu, cpu, frames), focusLost
end

-- Cette méthode permet de dérouler le banc lorsque le joueur appuie sur F4 : référence, chaque levier seul, tout
-- coupé, puis référence de contrôle ; tout est rétabli à la fin ou à l'annulation.
local function run(player: Player)
	running, cancelled = true, false
	local levers = buildLevers()
	local function restoreAll()
		for _, lever in levers do
			lever.restore()
		end
	end
	local phases: { { name: string, apply: () -> () } } = { { name = "référence", apply = function() end } }
	for _, lever in levers do
		table.insert(phases, { name = lever.name, apply = lever.apply })
	end
	table.insert(phases, {
		name = "tout coupé",
		apply = function()
			for _, lever in levers do
				lever.apply()
			end
		end,
	})
	table.insert(phases, { name = "référence (contrôle)", apply = function() end })

	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.zero
	local okQuality, quality = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	print(
		string.format(
			"[Perf] BANC départ : %d phases de %d s, fenêtre %dx%d, qualité %s. Ne pas quitter la fenêtre ni bouger.",
			#phases,
			SETTLE + MEASURE,
			math.floor(viewport.X),
			math.floor(viewport.Y),
			okQuality and tostring(quality) or "?"
		)
	)
	local refGpu: number? = nil
	for i, phase in phases do
		if cancelled then
			break
		end
		setStatus(player, string.format("BANC %d/%d : %s (F4 pour annuler, ne pas bouger)", i, #phases, phase.name))
		restoreAll()
		phase.apply()
		local summary, focusLost = measure()
		local valid = PerfRules.benchPhaseValid(summary, focusLost)
		if i == 1 and valid then
			refGpu = summary.gpuMeanMs
		end
		print("[Perf] " .. PerfRules.formatBenchLine(phase.name, summary, valid, if i == 1 then nil else refGpu))
	end
	restoreAll()
	print(cancelled and "[Perf] BANC annulé, réglages rétablis" or "[Perf] BANC terminé, réglages rétablis")
	setStatus(player, nil)
	running = false
end

-- Cette méthode permet de lancer le banc, ou de l'annuler s'il tourne, lorsque le joueur appuie sur F4 ou que
-- l'attribut `PerfBench` passe à true.
local function toggle(player: Player)
	if running then
		cancelled = true
		setStatus(player, "BANC : annulation à la fin de la phase en cours…")
	else
		task.spawn(run, player)
	end
end

-- Cette méthode permet de brancher la touche F4 lorsque le joueur a le droit de mesurer (Studio, ou créateur du jeu
-- publié). Même effet par l'attribut joueur `PerfBench` = true, pour un banc piloté par le MCP Studio.
function PerfBench.init(player: Player?)
	local localPlayer = player or Players.LocalPlayer
	local ownedByUser = game.CreatorType == Enum.CreatorType.User
	if not PerfRules.canUse(RunService:IsStudio(), localPlayer.UserId, game.CreatorId, ownedByUser) then
		return
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= TOGGLE_KEY then
			return
		end
		toggle(localPlayer)
	end)
	localPlayer:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		if localPlayer:GetAttribute(ATTRIBUTE) == true then
			localPlayer:SetAttribute(ATTRIBUTE, nil)
			toggle(localPlayer)
		end
	end)
end

return PerfBench

-- Enregistreur de partie (#582), côté client : F8 lance puis arrête l'enregistrement de toute la partie (Studio, ou
-- créateur du jeu publié : PerfRules.canUse), pour la rejouer dans Studio et la filmer sans lag (docs/promo.md,
-- « Enregistreur de partie »). Le serveur (server/MatchRecorder) note tous les participants et envoie un morceau toutes
-- les MatchRecordRules.CHUNK_SECONDS ; ce client y ajoute sa caméra (position, yeux, lacet, tangage, champ de vision,
-- lunette, à POV_HZ) et ses inspections, puis recopie le morceau dans la console (lignes `[MatchRec …]`, journal
-- Roblox du poste qui joue) et le range dans Player.MatchRecordings (lu par le MCP dans Studio). Dans Studio, F8 est un
-- raccourci de l'éditeur : l'attribut joueur `MatchRecord` (true / false) fait la même chose.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HighlightClipRules = require(Shared:WaitForChild("HighlightClipRules"))
local MatchRecordRules = require(Shared:WaitForChild("MatchRecordRules"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local PerfMarkers = require(Shared:WaitForChild("PerfMarkers"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local ScopeSystem = require(script.Parent.Parent.systems.weapon.ScopeSystem)

local TOGGLE_KEY = Enum.KeyCode.F8
local ATTRIBUTE = "MatchRecord"
local FOLDER_NAME = "MatchRecordings"
-- Après la caméra FPS (Camera) et le viewmodel (Camera + 1) : la caméra de l'image est posée
local BIND_NAME = "MatchRecorder"
-- Durée (s) du bandeau de fin d'enregistrement
local DONE_BANNER = 6

type Deps = {
	player: Player,
	fpsCamera: any, -- FPSCamera (getCameraYaw, getCameraPitch)
	input: any, -- InputModule (snapshot)
}

local MatchRecorder = {}

local deps: Deps
local remote: RemoteEvent? = nil
local recording = false
local pending = false -- demande envoyée, réponse du serveur attendue
local rec: string? = nil
local startedAt = 0 -- horloge serveur
-- Caméra relevée depuis le dernier morceau : une ligne { t absolu, x, y, z, yeux, lacet, tangage, champ, drapeaux }
local povRows: { { number } } = {}
local lastPov = -math.huge
local inspects: { MatchRecordRules.Event } = {}
local lastInspect = 0
local status: TextLabel? = nil
local doneToken = 0

-- Cette méthode permet d'écrire une ligne préfixée lorsque l'enregistrement change d'état.
local function log(text: string)
	print("[MatchRecord] " .. text)
end

-- Cette méthode permet d'afficher l'état de l'enregistrement en haut de l'écran (nil : caché) ; `live` en rouge.
local function showStatus(text: string?, live: boolean?)
	if not status then
		if not text then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "MatchRecorder"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Parent = deps.player:WaitForChild("PlayerGui")
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 40)
		label.Size = UDim2.fromOffset(420, 24)
		label.BackgroundColor3 = UITheme.Colors.Black
		label.BackgroundTransparency = 0.35
		label.FontFace = UITheme.Fonts.Display
		label.TextSize = 16
		label.Parent = gui
		status = label
	end
	local label = status :: TextLabel
	label.Visible = text ~= nil
	label.Text = text or ""
	label.TextColor3 = if live then UITheme.Colors.HitRed else UITheme.Colors.Bone
end

-- Cette méthode permet de formater une durée en minutes et secondes lorsqu'elle s'affiche dans le bandeau.
local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Cette méthode permet de relever la caméra du joueur lorsqu'une image est rendue pendant l'enregistrement : à POV_HZ,
-- seulement personnage en vie ; inspections notées à leur appui.
local function step()
	if not recording then
		return
	end
	local _, counts = deps.input.snapshot()
	if counts.inspect > lastInspect then
		lastInspect = counts.inspect
		table.insert(
			inspects,
			{ t = workspace:GetServerTimeNow(), k = MatchRecordRules.Event.INSPECT, id = deps.player.UserId }
		)
	end
	local t = workspace:GetServerTimeNow()
	if t - lastPov < MatchRecordRules.POV_SPACING then
		return
	end
	local char = deps.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and camera) then
		return
	end
	lastPov = t
	local pos = root.Position
	local flags = if ScopeSystem.getLevel() > 0 then MatchRecordRules.FLAG_SCOPED else 0
	table.insert(povRows, {
		t,
		pos.X,
		pos.Y,
		pos.Z,
		camera.CFrame.Position.Y - pos.Y,
		deps.fpsCamera.getCameraYaw(),
		deps.fpsCamera.getCameraPitch(),
		camera.FieldOfView,
		flags,
	})
end

-- Cette méthode permet de ranger un morceau dans Player.MatchRecordings lorsqu'il est recopié (extraction par le MCP,
-- contexte Client, dans Studio).
local function store(seq: number, text: string)
	local folder = deps.player:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = deps.player
	end
	local value = Instance.new("StringValue")
	value.Name = string.format("%s_%04d", rec or "?", seq)
	value.Value = text
	value.Parent = folder
end

-- Cette méthode permet de compléter un morceau du serveur avec la caméra et les inspections de [t0, t1[ lorsqu'il
-- arrive, puis de le recopier dans la console et de le ranger.
local function onChunk(seq: number, t0: number, t1: number, text: string)
	local ok, chunk = pcall(HttpService.JSONDecode, HttpService, text)
	if not ok or type(chunk) ~= "table" then
		warn("[MatchRecord] morceau " .. seq .. " illisible")
		return
	end
	local rows: { HighlightClipRules.Row } = {}
	local kept: { { number } } = {}
	for _, row in povRows do
		if row[1] < t0 then
			continue
		elseif row[1] >= t1 and not chunk.last then
			table.insert(kept, row)
		else
			local relative = table.clone(row)
			relative[1] -= t0
			table.insert(rows, relative)
		end
	end
	povRows = kept
	chunk.pov = HighlightClipRules.encodeSeries(rows, MatchRecordRules.POV_SCALES)
	local keptInspects = {}
	for _, event in inspects do
		if event.t >= t1 and not chunk.last then
			table.insert(keptInspects, event)
		elseif event.t >= t0 then
			table.insert(chunk.events, { t = MatchRecordRules.milli(event.t - t0), k = event.k, id = event.id })
		end
	end
	inspects = keptInspects
	local encoded = HttpService:JSONEncode(chunk)
	for _, line in MatchRecordRules.toLogLines(chunk.rec, seq, encoded) do
		print(line)
	end
	store(seq, encoded)
end

-- Cette méthode permet de demander au serveur de lancer ou d'arrêter l'enregistrement lorsque F8 est pressé ou que
-- l'attribut change ; `want` nil bascule.
local function request(want: boolean?)
	local r = remote
	if not r or pending then
		return
	end
	local target = if want == nil then not recording else want
	if target == recording then
		return
	end
	pending = true
	r:FireServer(if target then "start" else "stop")
	task.delay(3, function()
		pending = false
	end)
end

-- Cette méthode permet de suivre les réponses du serveur lorsqu'elles arrivent : début, morceau, fin, refus.
local function onServer(kind: any, a: any, b: any, c: any, d: any)
	if kind == "started" and type(a) == "string" and type(b) == "number" then
		pending = false
		recording = true
		rec = a
		startedAt = b
		povRows = {}
		inspects = {}
		lastPov = -math.huge
		local _, counts = deps.input.snapshot()
		lastInspect = counts.inspect
		log("REC " .. a)
		showStatus("● REC 0:00 · F8 POUR ARRÊTER", true)
	elseif
		kind == "chunk"
		and type(a) == "number"
		and type(b) == "number"
		and type(c) == "number"
		and type(d) == "string"
	then
		onChunk(a, b, c, d)
	elseif kind == "stopped" and type(a) == "string" then
		pending = false
		recording = false
		log(string.format("STOP %s : %s, %d morceau(x)", a, clock(tonumber(c) or 0), tonumber(b) or 0))
		showStatus(
			string.format("ENREGISTREMENT %s · %s · %d MORCEAUX", a, clock(tonumber(c) or 0), tonumber(b) or 0)
		)
		doneToken += 1
		local token = doneToken
		task.delay(DONE_BANNER, function()
			if token == doneToken and not recording then
				showStatus(nil)
			end
		end)
	elseif kind == "refused" then
		pending = false
		log("refusé : " .. tostring(a))
		showStatus("ENREGISTREMENT REFUSÉ : " .. string.upper(tostring(a)))
	end
end

-- Cette méthode permet de brancher l'enregistreur lorsque le client démarre, pour Studio ou le créateur du jeu publié
-- seulement.
function MatchRecorder.init(dependencies: Deps)
	local ownedByUser = game.CreatorType == Enum.CreatorType.User
	if not PerfRules.canUse(RunService:IsStudio(), dependencies.player.UserId, game.CreatorId, ownedByUser) then
		return
	end
	deps = dependencies
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, PerfMarkers.wrap("enregistreur", step))
	-- Pas de filtre sur `gameProcessed` (même règle que PerfRecorder) ; seule la saisie de texte est écartée
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == TOGGLE_KEY and not UserInputService:GetFocusedTextBox() then
			request(nil)
		end
	end)
	deps.player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		local value = deps.player:GetAttribute(ATTRIBUTE)
		if type(value) == "boolean" then
			request(value)
		end
	end)
	-- Durée affichée une fois par seconde pendant l'enregistrement
	task.spawn(function()
		while true do
			task.wait(1)
			if recording then
				showStatus(
					string.format("● REC %s · F8 POUR ARRÊTER", clock(workspace:GetServerTimeNow() - startedAt)),
					true
				)
			end
		end
	end)
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.MATCH_RECORD, 15)
		if not found or not found:IsA("RemoteEvent") then
			warn("[MatchRecord] remote " .. NetworkProtocol.Names.MATCH_RECORD .. " introuvable")
			return
		end
		remote = found
		found.OnClientEvent:Connect(onServer)
	end)
end

return MatchRecorder

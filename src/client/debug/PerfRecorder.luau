-- PerfRecorder.luau (client)
-- Enregistreur des parcours rejoués pour mesurer les performances en mouvement (#379, cf. docs/performance.md,
-- « Parcours rejoué »). Mêmes droits que l'overlay F3 : Studio, ou créateur du jeu publié. L'attribut joueur
-- `PerfRecord` (nom de la piste, ex. "dizzy") l'arme ; F7 lance puis arrête la prise. À chaque tick fixe du mouvement
-- (MovementController.setTickHook), il note les touches tenues et les appuis (InputModule.snapshot), les angles de la
-- caméra, les tirs (Tool.Activated), le tir et la visée tenus (InputModule.isPointerHeld), l'arme tenue, et un point de contrôle (position, vitesse) par seconde et à chaque
-- réapparition. Il ne fait que lire. À l'arrêt, la piste est rangée dans `Player.PerfRoutes.<nom>` (StringValue
-- locale) et recopiée dans la console (lignes `[PerfRoute …]`), puis écrite dans le dépôt par
-- tools/perf/write_route.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))
local Rules = require(Shared:WaitForChild("PerfRouteRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local ATTRIBUTE = "PerfRecord"
local TOGGLE_KEY = Enum.KeyCode.F7
local FOLDER_NAME = "PerfRoutes"

type Deps = {
	player: Player,
	fpsCamera: any, -- FPSCamera (getCameraYaw, getCameraPitch)
	movement: any, -- MovementController (setTickHook, getVelocity)
	input: any, -- InputModule (snapshot)
}

local PerfRecorder = {}

local deps: Deps
local armedName: string?
local recording = false
local ticks: { Rules.Tick } = {}
local lastCounts = { jump = 0, reload = 0, inspect = 0 }
local lastChar: Instance? = nil
local lastPos: Vector3? = nil -- position au tick précédent (détection des téléportations)
local pendingFires = 0
local watched: { [Tool]: RBXScriptConnection } = {}
local charConn: RBXScriptConnection? = nil
local status: TextLabel?

-- Cette méthode permet d'écrire une ligne préfixée lorsque l'enregistreur change d'état.
local function log(text: string)
	print("[PerfRecord] " .. text)
end

-- Cette méthode permet d'afficher l'état de l'enregistreur en haut de l'écran lorsqu'il est armé ou enregistre.
local function showStatus(text: string?, live: boolean?)
	if not status then
		if not text then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "PerfRecorder"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Parent = deps.player:WaitForChild("PlayerGui")
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 70)
		label.Size = UDim2.fromOffset(560, 28)
		label.BackgroundColor3 = UITheme.Colors.Black
		label.BackgroundTransparency = 0.3
		label.FontFace = UITheme.Fonts.Display
		label.TextSize = 18
		label.Parent = gui
		status = label
	end
	local label = status :: TextLabel
	label.Visible = text ~= nil
	label.Text = text or ""
	label.TextColor3 = if live then UITheme.Colors.HitRed else UITheme.Colors.Bone
end

-- Cette méthode permet de composer le bandeau de l'enregistreur armé lorsqu'il attend une prise.
local function readyText(): string?
	return if armedName then string.format("PARCOURS %s PRÊT · F7 ENREGISTRER", armedName) else nil
end

-- Cette méthode permet de compter les tirs d'un Tool lorsqu'il entre dans le personnage pendant une prise (une seule
-- connexion par Tool, même s'il est rangé puis repris).
local function watchTool(child: Instance)
	if not child:IsA("Tool") or watched[child] then
		return
	end
	watched[child] = child.Activated:Connect(function()
		pendingFires += 1
	end)
end

-- Cette méthode permet de suivre les Tools d'un nouveau personnage lorsque la prise le rencontre (début, réapparition).
local function watchCharacter(char: Instance)
	if charConn then
		charConn:Disconnect()
	end
	for _, child in char:GetChildren() do
		watchTool(child)
	end
	charConn = char.ChildAdded:Connect(watchTool)
end

-- Cette méthode permet de noter le tick qui commence lorsque la prise tourne (MovementController, avant toute lecture
-- des entrées) : touches, appuis depuis le tick précédent, angles, tirs, arme, et un point de contrôle si besoin.
local function onTick(hrp: BasePart)
	local char = hrp.Parent :: Instance
	local held, counts = deps.input.snapshot()
	-- Tir et visée tenus (#485) : WeaponSystem répète le tir au maintien sans Tool.Activated, le rejeu doit les tenir
	held.fire = deps.input.isPointerHeld("fire")
	held.aim = deps.input.isPointerHeld("aim")
	local presses = {
		jump = counts.jump > lastCounts.jump,
		reload = counts.reload > lastCounts.reload,
		inspect = counts.inspect > lastCounts.inspect,
	}
	lastCounts = counts
	local check: Rules.Check? = nil
	local p = hrp.Position
	local respawned = char ~= lastChar
	local teleported = lastPos ~= nil and (p - lastPos :: Vector3).Magnitude > Rules.TELEPORT_JUMP
	if respawned or teleported or #ticks % Rules.CHECK_EVERY == 0 then
		if respawned then
			lastChar = char
			watchCharacter(char)
		end
		-- Au premier tick d'un nouveau personnage, getVelocity rend encore celle du précédent : le rejeu repartirait
		-- de la réapparition avec la vitesse d'avant la mort
		local v = if respawned then Vector3.zero else deps.movement.getVelocity()
		check = Rules.check(p.X, p.Y, p.Z, v.X, v.Y, v.Z)
	end
	lastPos = p
	local tool = char:FindFirstChildOfClass("Tool")
	table.insert(ticks, {
		keys = Rules.keysFrom(held, presses),
		yaw = Rules.milli(deps.fpsCamera.getCameraYaw()),
		pitch = Rules.milli(deps.fpsCamera.getCameraPitch()),
		fire = pendingFires,
		tool = if tool then tool.Name else "",
		check = check,
	})
	pendingFires = 0
	if #ticks % 32 == 0 then
		showStatus(string.format("● REC %s  %.1f s · F7 POUR ARRÊTER", armedName or "?", #ticks / 64), true)
	end
	if #ticks >= Rules.MAX_TICKS then
		task.defer(PerfRecorder.stop)
	end
end

-- Cette méthode permet de ranger la piste encodée dans Player.PerfRoutes lorsque la prise s'arrête, pour l'extraction
-- par le MCP (contexte Client).
local function store(name: string, text: string)
	local folder = deps.player:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = deps.player
	end
	local value = folder:FindFirstChild(name) :: StringValue?
	if not value then
		local created = Instance.new("StringValue")
		created.Name = name
		created.Parent = folder
		value = created
	end
	(value :: StringValue).Value = text
end

-- Cette méthode permet d'arrêter la prise, de la ranger et de la recopier dans la console lorsque F7 est pressé, que
-- l'attribut change ou que la durée maximale est atteinte.
function PerfRecorder.stop()
	if not recording then
		return
	end
	recording = false
	deps.movement.setTickHook(nil)
	for _, conn in watched do
		conn:Disconnect()
	end
	watched = {}
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	local name = string.lower(armedName or "parcours")
	if #ticks < Rules.CHECK_EVERY then
		log("STOP " .. name .. " : prise de moins d'une seconde, rien de rangé")
	else
		local route = { version = Rules.VERSION, map = GameConfig.ACTIVE_MAP, ticks = ticks }
		local text = Rules.encode(route)
		store(name, text)
		-- Numéro de prise : l'heure en ms, unique d'un playtest à l'autre ; la plus récente l'emporte au recollage
		for _, line in Rules.toLogLines(name, DateTime.now().UnixTimestampMillis, text) do
			print(line)
		end
		log(
			string.format(
				"STOP %s : %.1f s, %d ticks, %d octets, map %s, rangé dans Player.%s.%s",
				name,
				Rules.duration(route),
				#ticks,
				#text,
				route.map,
				FOLDER_NAME,
				name
			)
		)
	end
	ticks = {}
	showStatus(readyText())
end

-- Cette méthode permet de lancer une prise lorsque F7 est pressé avec l'enregistreur armé (refusée pendant un rejeu,
-- qui occupe le même branchement du mouvement).
local function start()
	if recording or not armedName then
		return
	end
	if not deps.movement.setTickHook(onTick) then
		log("un rejeu de parcours est en cours : prise refusée")
		return
	end
	recording = true
	ticks = {}
	lastChar = nil
	lastPos = nil
	pendingFires = 0
	local _, counts = deps.input.snapshot()
	lastCounts = counts
	log("REC " .. (armedName :: string))
	showStatus(string.format("● REC %s  0.0 s · F7 POUR ARRÊTER", armedName :: string), true)
end

-- Cette méthode permet d'armer ou de désarmer l'enregistreur lorsque l'attribut PerfRecord change.
local function onAttribute()
	local value = deps.player:GetAttribute(ATTRIBUTE)
	PerfRecorder.stop()
	armedName = if type(value) == "string" and value ~= "" then value else nil
	showStatus(readyText())
end

-- Cette méthode permet de brancher l'enregistreur lorsque le client démarre, pour Studio ou le créateur du jeu publié
-- seulement.
function PerfRecorder.init(dependencies: Deps)
	local ownedByUser = game.CreatorType == Enum.CreatorType.User
	if not PerfRules.canUse(RunService:IsStudio(), dependencies.player.UserId, game.CreatorId, ownedByUser) then
		return
	end
	deps = dependencies
	deps.player:GetAttributeChangedSignal(ATTRIBUTE):Connect(onAttribute)
	-- Pas de filtre sur `gameProcessed` : le moteur marque F7 comme traitée (raccourci interne), même sans action du jeu
	-- liée ; seule la saisie de texte est écartée.
	UserInputService.InputBegan:Connect(function(input)
		if not armedName or input.KeyCode ~= TOGGLE_KEY or UserInputService:GetFocusedTextBox() then
			return
		end
		if recording then
			PerfRecorder.stop()
		else
			start()
		end
	end)
	onAttribute()
end

return PerfRecorder

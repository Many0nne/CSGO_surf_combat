-- PerfReplay.luau (client)
-- Rejeu d'un parcours enregistré (debug/PerfRecorder) pour mesurer les performances en mouvement (#379, cf.
-- docs/performance.md, « Parcours rejoué »). Mêmes droits que l'overlay F3 : Studio, ou créateur du jeu publié.
-- L'attribut joueur `PerfRun` (nom d'une piste de debug/routes, ex. "Dizzy" ; le premier mot seulement, pour relancer
-- en changeant la suite : "Dizzy 2") lance le rejeu ; nil l'interrompt. Le joueur est amené en partie, replacé par le
-- serveur au début de la piste (remote PerfRouteTeleport), puis chaque tick du mouvement reçoit les entrées
-- enregistrées : touches et appuis (InputModule, clavier ignoré), angles de la caméra (souris ignorée), arme tenue,
-- tirs (Tool:Activate). À chaque point de contrôle, l'écart avec la piste est mesuré ; au-delà de DRIFT_MAX, ou après
-- une réapparition, le joueur est replacé. Overlay F3 ouvert pendant le rejeu (lignes BILAN), puis une ligne
-- `[Perf] RUN` résume le rythme, la fidélité à la piste et la mémoire.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local PerfRules = require(Shared:WaitForChild("PerfRules"))
local FrameProbeRules = require(Shared:WaitForChild("FrameProbeRules"))
local Rules = require(Shared:WaitForChild("PerfRouteRules"))

local ATTRIBUTE = "PerfRun"
local OVERLAY_ATTRIBUTE = "PerfOverlay"
local SPAWN_TIMEOUT = 15 -- s pour arriver en partie
local TELEPORT_RESEND = 1 -- s avant de redemander une téléportation restée sans réponse
local TELEPORT_GIVE_UP = 8 -- s avant d'abandonner le rejeu
local STALL_TIMEOUT = 20 -- s sans tick (plus de personnage) avant d'arrêter le rejeu
local ARRIVED_DISTANCE = 0.5 -- studs : la correction a posé le personnage sur le point demandé

type Deps = {
	player: Player,
	fpsCamera: any, -- FPSCamera (setAngles, setScripted)
	movement: any, -- MovementController (setTickHook, setVelocity, getCorrectionCount)
	input: any, -- InputModule (setVirtual, applyVirtual)
	gameState: any, -- GameStateController (getState, requestPlay)
}

type Pending = { pos: Vector3, velocity: Vector3, corrections: number, sentAt: number, firstAt: number }

local PerfReplay = {}

local deps: Deps
local remote: RemoteEvent? = nil
local running = false
local route: Rules.Route
local routeName = ""
local index = 1 -- prochain tick de la piste à jouer
local placedAt = 0 -- index du point de contrôle où le joueur vient d'être replacé (pas d'écart mesuré dessus)
local currentChar: Instance? = nil
local appliedTool: string? = nil
local pending: Pending? = nil
local measuring = false
local dts: { number } = {}
local renderConn: RBXScriptConnection? = nil
local lastTickAt = 0
local stats: Rules.RunStats
local driftSum = 0
local missingTools: { [string]: boolean } = {}

local NO_KEYS: { [string]: boolean } = {}

-- Cette méthode permet d'écrire une ligne préfixée lorsque le rejeu change d'état.
local function log(text: string)
	print("[PerfRun] " .. text)
end

-- Cette méthode permet de rendre clavier, souris et mouvement au joueur et d'écrire le bilan lorsque le rejeu
-- s'arrête (fin de piste, interruption ou échec).
local function finish(status: string)
	if not running then
		return
	end
	running = false
	pending = nil
	deps.movement.setTickHook(nil)
	deps.input.setVirtual(false)
	deps.fpsCamera.setScripted(false)
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if not measuring then
		log("arrêt avant le début de la mesure : " .. status)
		return
	end
	local summary = if #dts > 0 then FrameProbeRules.summarize(table.clone(dts)) else { fps = 0, p99Ms = 0, maxMs = 0 }
	local hitches = 0
	for _, dt in dts do
		if dt * 1000 > Rules.HITCH_MS then
			hitches += 1
		end
	end
	stats.status = status
	stats.fps, stats.p99Ms, stats.maxMs, stats.hitches = summary.fps, summary.p99Ms, summary.maxMs, hitches
	stats.driftMean = if stats.checks > 0 then driftSum / stats.checks else 0
	stats.memEndMb = Stats:GetTotalMemoryUsageMb()
	-- Overlay fermé : il écrit son dernier BILAN (à la frame suivante, signaux différés)
	deps.player:SetAttribute(OVERLAY_ATTRIBUTE, false)
	print(Rules.runLine(stats))
	measuring = false
end

-- Cette méthode permet de demander au serveur de replacer le joueur sur un point de contrôle lorsque le rejeu
-- démarre, s'écarte trop de la piste ou reprend après une réapparition ; le tick attend ensuite la correction.
local function requestTeleport(check: Rules.Check)
	local now = os.clock()
	pending = {
		pos = Vector3.new(check.x, check.y, check.z) / 100,
		velocity = Vector3.new(check.vx, check.vy, check.vz) / 100,
		corrections = deps.movement.getCorrectionCount(),
		sentAt = now,
		firstAt = now,
	}
	placedAt = index;
	(remote :: RemoteEvent):FireServer((pending :: Pending).pos)
end

-- Cette méthode permet de démarrer la mesure (frames, mémoire, overlay F3) lorsque le joueur est posé au début de la
-- piste.
local function startMeasure()
	measuring = true
	dts = {}
	stats.memStartMb = Stats:GetTotalMemoryUsageMb()
	deps.player:SetAttribute(OVERLAY_ATTRIBUTE, true)
	log(string.format("départ : %s, %.0f s", routeName, Rules.duration(route)))
end

-- Cette méthode permet de tenir l'arme de la piste lorsqu'elle change ; une arme absente de l'inventaire est
-- signalée une fois et ignorée.
local function holdTool(char: Instance, name: string)
	if name == appliedTool then
		return
	end
	appliedTool = name
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if name == "" then
		humanoid:UnequipTools()
		return
	end
	local current = char:FindFirstChildOfClass("Tool")
	if current and current.Name == name then
		return
	end
	local backpack = deps.player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(name)
	if tool and tool:IsA("Tool") then
		humanoid:EquipTool(tool)
	elseif not missingTools[name] then
		missingTools[name] = true
		log("arme absente de l'inventaire, ignorée : " .. name)
	end
end

-- Cette méthode permet d'attendre la téléportation demandée lorsque le tick commence : vrai si le joueur est posé
-- (vitesse du point de contrôle rendue), faux s'il faut encore attendre (entrées neutres, demande renvoyée).
local function awaitTeleport(hrp: BasePart, wait: Pending): boolean
	if
		deps.movement.getCorrectionCount() > wait.corrections
		and (hrp.Position - wait.pos).Magnitude < ARRIVED_DISTANCE
	then
		deps.movement.setVelocity(wait.velocity)
		pending = nil
		if not measuring then
			startMeasure()
		end
		return true
	end
	deps.input.applyVirtual(NO_KEYS, NO_KEYS)
	local now = os.clock()
	if now - wait.firstAt > TELEPORT_GIVE_UP then
		task.defer(finish, "téléportation sans réponse")
	elseif now - wait.sentAt > TELEPORT_RESEND then
		wait.sentAt = now;
		(remote :: RemoteEvent):FireServer(wait.pos)
	end
	return false
end

-- Cette méthode permet de jouer le tick suivant de la piste lorsque le mouvement commence un tick (avant toute lecture
-- des entrées) : replacement si besoin, écart au point de contrôle, puis arme, angles, touches et tirs du tick.
local function onTick(hrp: BasePart)
	-- Piste finie : l'arrêt est différé (le dernier tick garde ses entrées), les ticks suivants de la même frame
	-- n'ont plus rien à jouer
	if not running or index > #route.ticks then
		return
	end
	lastTickAt = os.clock()
	local char = hrp.Parent :: Instance
	if char ~= currentChar then
		if currentChar ~= nil then
			stats.respawns += 1
			index = Rules.nextCheck(route, index) or #route.ticks + 1
		end
		currentChar = char
		appliedTool = nil
		if index > #route.ticks then
			task.defer(finish, "fini")
			return
		end
		requestTeleport(route.ticks[index].check :: Rules.Check)
	end
	local wait = pending
	if wait and not awaitTeleport(hrp, wait) then
		return
	end
	local t = route.ticks[index]
	if t.check and index ~= placedAt then
		local p = hrp.Position
		local drift = Rules.drift(t.check, p.X, p.Y, p.Z)
		stats.checks += 1
		driftSum += drift
		stats.driftMax = math.max(stats.driftMax, drift)
		if drift > Rules.DRIFT_MAX then
			stats.recalages += 1
			requestTeleport(t.check)
			deps.input.applyVirtual(NO_KEYS, NO_KEYS)
			return
		end
	end
	holdTool(char, t.tool)
	deps.fpsCamera.setAngles(t.yaw / 1000, t.pitch / 1000)
	local held, presses = Rules.split(t.keys)
	deps.input.applyVirtual(held, presses)
	local tool = if t.fire > 0 then char:FindFirstChildOfClass("Tool") else nil
	if tool then
		for _ = 1, t.fire do
			tool:Activate()
		end
	end
	index += 1
	stats.ticks += 1
	if index > #route.ticks then
		task.defer(finish, "fini")
	end
end

-- Cette méthode permet de lire une piste de debug/routes lorsque le rejeu est demandé ; nil et la raison si elle est
-- absente, illisible ou d'une autre map.
local function loadRoute(name: string): (Rules.Route?, string?)
	local folder = script.Parent:FindFirstChild("routes")
	local module = folder and folder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil, "piste introuvable : debug/routes/" .. name
	end
	local ok, text = pcall(require, module)
	if not ok or type(text) ~= "string" then
		return nil, "piste illisible : " .. tostring(text)
	end
	local decoded, why = Rules.decode(text)
	if not decoded then
		return nil, "piste illisible : " .. tostring(why)
	end
	if decoded.map ~= GameConfig.ACTIVE_MAP then
		return nil, string.format("piste enregistrée sur %s, map jouée %s", decoded.map, GameConfig.ACTIVE_MAP)
	end
	return decoded, nil
end

-- Cette méthode permet d'amener le joueur en partie par le chemin du bouton JOUER lorsqu'il est au menu ; vrai une
-- fois vivant et en round.
local function reachRound(): boolean
	local function inRound(): boolean
		local char = deps.player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		return hum ~= nil and hum.Health > 0 and deps.gameState.getState() == "IN_ROUND"
	end
	if inRound() then
		return true
	end
	deps.gameState.requestPlay()
	local deadline = os.clock() + SPAWN_TIMEOUT
	while not inRound() do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	-- Laisse la caméra FPS et le mouvement finir leur init
	task.wait(0.5)
	return true
end

-- Cette méthode permet de lancer le rejeu d'une piste lorsque l'attribut PerfRun reçoit son nom.
local function start(name: string)
	local loaded, why = loadRoute(name)
	if not loaded then
		log("refusé : " .. tostring(why))
		return
	end
	if not reachRound() then
		log("refusé : pas en partie après " .. SPAWN_TIMEOUT .. " s")
		return
	end
	if not deps.movement.setTickHook(onTick) then
		log("refusé : un enregistrement de parcours est en cours")
		return
	end
	route, routeName = loaded :: Rules.Route, name
	running, measuring, pending = true, false, nil
	index, placedAt, currentChar, appliedTool, driftSum = 1, 0, nil, nil, 0
	stats = {
		name = name,
		status = "",
		ticks = 0,
		total = #route.ticks,
		fps = 0,
		p99Ms = 0,
		maxMs = 0,
		hitches = 0,
		checks = 0,
		driftMean = 0,
		driftMax = 0,
		recalages = 0,
		respawns = 0,
		memStartMb = 0,
		memEndMb = 0,
	}
	deps.input.setVirtual(true)
	deps.fpsCamera.setScripted(true)
	lastTickAt = os.clock()
	renderConn = RunService.RenderStepped:Connect(function(dt: number)
		if measuring then
			table.insert(dts, dt)
		end
		if os.clock() - lastTickAt > STALL_TIMEOUT then
			finish("plus de personnage depuis " .. STALL_TIMEOUT .. " s")
		end
	end)
	log(string.format("piste %s chargée : %.0f s, %d ticks", name, Rules.duration(route), #route.ticks))
end

-- Cette méthode permet de lancer ou d'interrompre le rejeu lorsque l'attribut PerfRun change.
local function onAttribute()
	local value = deps.player:GetAttribute(ATTRIBUTE)
	local name = if type(value) == "string" then string.match(value, "^%s*(%S+)") else nil
	if not name then
		finish("interrompu")
		return
	end
	if running then
		finish("interrompu")
	end
	task.spawn(start, name)
end

-- Cette méthode permet de brancher le rejeu lorsque le client démarre, pour Studio ou le créateur du jeu publié
-- seulement.
function PerfReplay.init(dependencies: Deps)
	local ownedByUser = game.CreatorType == Enum.CreatorType.User
	if not PerfRules.canUse(RunService:IsStudio(), dependencies.player.UserId, game.CreatorId, ownedByUser) then
		return
	end
	deps = dependencies
	task.spawn(function()
		remote = NetworkProtocol.getRemote(NetworkProtocol.Names.PERF_ROUTE_TELEPORT)
		deps.player:GetAttributeChangedSignal(ATTRIBUTE):Connect(onAttribute)
	end)
end

return PerfReplay

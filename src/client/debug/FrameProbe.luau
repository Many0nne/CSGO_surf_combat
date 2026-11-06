-- FrameProbe.luau (client)
-- Sonde de saccades, active uniquement dans Studio quand l'attribut joueur `FrameProbe` vaut true. Mesure chaque
-- frame rendue (dt, pas de mouvement simulés, déplacement de la racine, vitesse simulée, rotation, mémoire Lua) et n'écrit
-- une ligne `[FrameProbe]` que pour une frame anormale (règles : shared/FrameProbeRules), plus un bilan toutes les 10 s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProbeRules"))

local ATTRIBUTE = "FrameProbe"
local BIND_NAME = "FrameProbeSample"
local WINDOW = 120 -- frames gardées pour la médiane du dt
local WARMUP = 30 -- frames ignorées après l'activation
local SUMMARY_PERIOD = 10 -- secondes entre deux bilans
local LOG_COOLDOWN = 0.25 -- secondes minimum entre deux lignes d'un même type

type Deps = {
	player: Player?,
	fpsCamera: any, -- FPSCamera (getCameraYaw)
	movement: any, -- MovementController (getVelocity, getStepStats)
}

type Probe = Rules.Sample & { gcDeltaKb: number, fpsMs: number? }

local FrameProbe = {}

local deps: Deps
local active = false
local waiting = false -- true tant que le joueur n'a pas de personnage (menu, mort)
local startClock = 0
local lastStepCount, lastSimTime = 0, 0 -- compteurs du MovementController au rendu précédent
local lastPos: Vector3?
local lastYaw = 0
local lastGc = 0
local dtWindow: { number } = {}
local summaryDts: { number } = {}
local summaryCounts: { [string]: number } = {}
local lastSummary = 0
local prevSample: Probe?, curSample: Probe?
local lastLogAt: { [string]: number } = {}
local suppressed: { [string]: number } = {}

-- Cette méthode permet d'écrire une ligne préfixée lorsque la sonde signale une anomalie ou un bilan.
local function log(text: string)
	print(string.format("[FrameProbe] t=%.2fs %s", os.clock() - startClock, text))
end

-- Cette méthode permet de nommer l'arme tenue lorsque la ligne d'anomalie donne le contexte de jeu.
local function equippedName(): string
	local char = deps.player and deps.player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	return tool and tool.Name or "aucune"
end

-- Cette méthode permet d'écrire le bilan de la fenêtre écoulée puis de la vider lorsque la période est atteinte
-- ou que la sonde s'arrête.
local function flushSummary()
	if #summaryDts == 0 then
		return
	end
	local s = Rules.summarize(summaryDts)
	log(
		string.format(
			"BILAN %d frames : %.0f FPS médian, p99 %.1f ms, max %.1f ms, HITCH=%d STUTTER=%d ROTATION=%d TELEPORT=%d",
			#summaryDts,
			s.fps,
			s.p99Ms,
			s.maxMs,
			summaryCounts.HITCH or 0,
			summaryCounts.STUTTER or 0,
			summaryCounts.ROTATION or 0,
			summaryCounts.TELEPORT or 0
		)
	)
	summaryDts = {}
	summaryCounts = {}
	lastSummary = os.clock()
end

-- Cette méthode permet de signaler une frame anormale lorsque le type n'a pas déjà été signalé il y a moins de
-- LOG_COOLDOWN secondes (sinon elle est comptée et annoncée avec la ligne suivante).
local function report(kinds: { string }, source: string?, s: Probe, medianDt: number)
	local now = os.clock()
	local label = table.concat(kinds, "+")
	for _, kind in kinds do
		summaryCounts[kind] = (summaryCounts[kind] or 0) + 1
	end
	if now - (lastLogAt[label] or -math.huge) < LOG_COOLDOWN then
		suppressed[label] = (suppressed[label] or 0) + 1
		return
	end
	lastLogAt[label] = now
	local extra = suppressed[label] and string.format(" (+%d non affichées)", suppressed[label]) or ""
	suppressed[label] = nil
	log(
		string.format(
			"%s dt=%.1fms (médiane %.1fms) steps=%d simDt=%.1fms disp=%.3f vRendue=%.1f vSim=%.1f yaw=%.0f°/s gcΔ=%+dKB arme=%s%s%s",
			label,
			s.dt * 1000,
			medianDt * 1000,
			s.steps,
			s.simDt * 1000,
			s.disp,
			s.dt > 0 and s.disp / s.dt or 0,
			s.simSpeed,
			s.yawRate,
			s.gcDeltaKb,
			equippedName(),
			source and (" source=" .. source) or "",
			extra
		)
	)
end

-- Cette méthode permet de mesurer une frame rendue lorsque la caméra et le viewmodel ont été posés, puis de classer
-- la frame précédente (il faut sa voisine suivante pour distinguer un pic isolé d'une accélération).
local function onRender(dt: number)
	local char = deps.player and deps.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		if not waiting then
			waiting = true
			log("en attente du personnage (menu ou mort) : la mesure reprend au spawn")
		end
		lastPos, prevSample, curSample = nil, nil, nil
		return
	end
	if waiting then
		waiting = false
		log("personnage trouvé : mesure en cours")
	end
	local pos = root.Position
	local yaw = deps.fpsCamera.getCameraYaw()
	local gc = gcinfo()
	local stepCount, simTime = deps.movement.getStepStats()
	local steps, simDt = stepCount - lastStepCount, simTime - lastSimTime
	lastStepCount, lastSimTime = stepCount, simTime
	if not lastPos or dt <= 0 then
		lastPos, lastYaw, lastGc = pos, yaw, gc
		return
	end

	local sample: Probe = {
		dt = dt,
		simDt = simDt,
		steps = steps,
		disp = (pos - lastPos).Magnitude,
		simSpeed = deps.movement.getVelocity().Magnitude,
		yawRate = math.abs(yaw - lastYaw) / dt,
		gcDeltaKb = gc - lastGc,
	}
	lastPos, lastYaw, lastGc = pos, yaw, gc

	table.insert(dtWindow, dt)
	if #dtWindow > WINDOW then
		table.remove(dtWindow, 1)
	end
	table.insert(summaryDts, dt)

	if prevSample and curSample and #dtWindow >= WARMUP then
		local medianDt = Rules.median(dtWindow)
		local kinds, source = Rules.classify(prevSample, curSample, sample, medianDt)
		if #kinds > 0 then
			report(kinds, source, curSample, medianDt)
		end
	end
	prevSample, curSample = curSample, sample

	if os.clock() - lastSummary >= SUMMARY_PERIOD then
		flushSummary()
	end
end

-- Cette méthode permet de démarrer la mesure lorsque l'attribut passe à true (état remis à zéro).
local function start()
	if active then
		return
	end
	active = true
	startClock = os.clock()
	lastSummary = startClock
	lastStepCount, lastSimTime = deps.movement.getStepStats()
	lastPos, waiting = nil, false
	dtWindow, summaryDts, summaryCounts = {}, {}, {}
	prevSample, curSample = nil, nil
	lastLogAt, suppressed = {}, {}
	-- Après le mouvement (Camera - 1), la caméra (Camera) et le viewmodel (Camera + 1) : on mesure ce qui sera affiché.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, onRender)
	log("ON : une ligne par frame anormale, un BILAN toutes les " .. SUMMARY_PERIOD .. " s")
end

-- Cette méthode permet d'arrêter la mesure lorsque l'attribut repasse à false/nil, avec un dernier bilan.
local function stop()
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	flushSummary()
	log("OFF")
end

-- Cette méthode permet de brancher la sonde sur l'attribut `FrameProbe` du joueur lorsque le jeu tourne dans Studio.
function FrameProbe.init(dependencies: Deps)
	if not RunService:IsStudio() then
		return
	end
	deps = dependencies
	local player = deps.player or Players.LocalPlayer
	deps.player = player
	local function sync()
		if player:GetAttribute(ATTRIBUTE) == true then
			start()
		else
			stop()
		end
	end
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(sync)
	sync()
end

return FrameProbe

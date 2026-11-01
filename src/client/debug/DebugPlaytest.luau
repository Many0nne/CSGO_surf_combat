-- DebugPlaytest.luau (client)
-- Moitié client du helper de playtest debug (#30), active uniquement dans Studio. Exécute les commandes du
-- serveur (server/DebugPlaytest) par le remote `DebugPlaytest` et observe ce que le serveur ne voit pas :
-- pistes d'animation du viewmodel, marqueurs atteints, sons joués. Chaque commande renvoie (ok, détail, données).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local CameraConfig = require(Shared:WaitForChild("CameraConfig"))
local Rules = require(Shared:WaitForChild("DebugPlaytestRules"))
local AnimationSoundSystem = require(script.Parent.Parent.systems.weapon.AnimationSoundSystem)

local SPAWN_TIMEOUT = 10
local EQUIP_TIMEOUT = 6
local IDLE_TIMEOUT = 3
local ATTACK_SETTLE = 0.5 -- secondes observées après la fin théorique de l'animation de tir

type Deps = {
	player: Player,
	gameState: any, -- GameStateController
	weaponSystem: any,
	viewmodelSystem: any,
	fpsCamera: any,
}

local DebugPlaytest = {}

local deps: Deps
local conns: { RBXScriptConnection } = {}
local events = { anims = {} :: { string }, markers = {} :: { string }, sounds = {} :: { string } }

-- Cette méthode permet d'écrire une ligne préfixée côté client lorsque le helper observe un événement.
local function log(text: string)
	print(Rules.line("client : " .. text))
end

-- Cette méthode permet d'attendre qu'une condition devienne vraie lorsque l'état dépend d'une réplication
-- ou d'une animation ; renvoie false au bout du délai.
local function waitFor(predicate: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not predicate() do
		if os.clock() >= deadline then
			return false
		end
		task.wait(0.05)
	end
	return true
end

-- Cette méthode permet de retrouver la config d'arme d'un outil lorsque le helper doit connaître ses sons/délais.
local function getConfig(tool: Instance?): any
	if not tool then
		return nil
	end
	return WeaponConfig.Weapons[tool:GetAttribute("WeaponName") or tool.Name]
end

-- Cette méthode permet de retrouver l'outil par son nom dans le sac ou le personnage lorsque le serveur le désigne.
local function findTool(name: string): Tool?
	for _, container in { deps.player.Character, deps.player:FindFirstChildOfClass("Backpack") } do
		local tool = container and container:FindFirstChild(name)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end
	return nil
end

-- Cette méthode permet de couper les observateurs et de vider les observations lorsqu'un run se termine.
local function clearWatch()
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	events = { anims = {}, markers = {}, sounds = {} }
end

-- Cette méthode permet de brancher les observateurs (pistes, marqueurs, sons) sur le viewmodel de l'outil
-- lorsque le serveur s'apprête à l'équiper ; le viewmodel est préchargé sous la caméra par ViewmodelSystem.
local function watch(payload: any): (boolean, string)
	clearWatch()
	local tool = findTool(payload.tool)
	if not tool then
		return false, "outil introuvable : " .. tostring(payload.tool)
	end
	local cfg = getConfig(tool)
	local viewmodelName = tool:GetAttribute("ViewmodelName")
	-- Le viewmodel n'est parfois créé qu'au premier équipement : on le précharge pour observer la piste Equip.
	deps.viewmodelSystem.prewarm(tool)
	local cam = workspace.CurrentCamera
	local model = cam and type(viewmodelName) == "string" and cam:FindFirstChild(viewmodelName)
	if not model or not model:IsA("Model") then
		return false, "viewmodel « " .. tostring(viewmodelName) .. " » absent de la caméra"
	end
	local animator = AnimationSoundSystem.getAnimator(model)
	if animator then
		table.insert(
			conns,
			animator.AnimationPlayed:Connect(function(track: AnimationTrack)
				local animName = track.Animation and track.Animation.Name or track.Name
				table.insert(events.anims, animName)
				log("piste jouée " .. animName)
				for _, marker in Rules.markersFor(cfg, animName) do
					table.insert(
						conns,
						track:GetMarkerReachedSignal(marker):Connect(function()
							table.insert(events.markers, marker)
							log("marqueur atteint « " .. marker .. " » (" .. animName .. ")")
						end)
					)
				end
			end)
		)
	end
	local sounds = model:FindFirstChild("Sounds")
	if sounds then
		for _, s in sounds:GetChildren() do
			if s:IsA("Sound") then
				table.insert(
					conns,
					s.Played:Connect(function()
						table.insert(events.sounds, s.Name)
						log("son joué " .. s.Name)
					end)
				)
			end
		end
	end
	return true, "observateurs branchés sur " .. model.Name
end

-- Cette méthode permet d'amener le joueur en round par le chemin du bouton Play lorsqu'il est au menu ;
-- attend un personnage vivant et l'état client IN_ROUND.
local function spawnInRound(): (boolean, string)
	local function inRound(): boolean
		local char = deps.player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		return hum ~= nil and hum.Health > 0 and deps.gameState.getState() == "IN_ROUND"
	end
	if inRound() then
		return true, "déjà en round (état client IN_ROUND)"
	end
	if not deps.gameState.requestPlay() then
		log("requestPlay refusé (état " .. deps.gameState.getState() .. "), attente d'un respawn")
	end
	local ok = waitFor(inRound, SPAWN_TIMEOUT)
	-- Laisse setupCharacter (caméra FPS, mouvement) finir son init avant d'équiper.
	task.wait(0.5)
	return ok, "état client " .. deps.gameState.getState()
end

-- Cette méthode permet de vérifier l'équipement côté client lorsque le serveur a équipé l'outil :
-- outil en main, viewmodel actif, état d'arme revenu à IDLE et piste Equip jouée (si l'arme en a une).
local function checkEquipped(payload: any): (boolean, string)
	local ready = waitFor(function()
		local tool = findTool(payload.tool)
		return tool ~= nil
			and tool.Parent == deps.player.Character
			and deps.viewmodelSystem.getActiveViewmodel() ~= nil
			and deps.weaponSystem.getState() == "IDLE"
	end, EQUIP_TIMEOUT)
	local vm = deps.viewmodelSystem.getActiveViewmodel()
	local hasEquipAnim = vm ~= nil
		and (vm:FindFirstChild("Animations") or vm:FindFirstChild("AnimSaves") or vm):FindFirstChild("Equip") ~= nil
	local equipPlayed = table.find(events.anims, "Equip") ~= nil
	local detail = string.format(
		"viewmodel=%s ; état arme=%s ; pistes : %s",
		vm and vm.Name or "aucun",
		deps.weaponSystem.getState(),
		table.concat(events.anims, ", ")
	)
	return ready and (equipPlayed or not hasEquipAnim), detail
end

-- Cette méthode permet de viser un point monde avec la caméra FPS lorsque la cible vient d'être placée ;
-- vérifie après deux frames que la caméra pointe bien dessus.
local function aim(payload: any): (boolean, string)
	local target = payload.target
	if typeof(target) ~= "Vector3" then
		return false, "cible invalide"
	end
	local cam = workspace.CurrentCamera
	local yaw, pitch = Rules.yawPitchToward(cam.CFrame.Position, target, CameraConfig.PITCH_MIN, CameraConfig.PITCH_MAX)
	deps.fpsCamera.setAngles(yaw, pitch)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	local dot = cam.CFrame.LookVector:Dot((target - cam.CFrame.Position).Unit)
	return dot > 0.995, string.format("yaw=%.1f pitch=%.1f, alignement=%.3f", yaw, pitch, dot)
end

-- Cette méthode permet de simuler un clic d'attaque par le chemin réel (Tool:Activate → WeaponSystem) lorsque
-- l'arme est prête ; renvoie les pistes, marqueurs et sons observés pendant l'attaque.
local function attack(payload: any): (boolean, string, any)
	local tool = findTool(payload.tool)
	if not tool or tool.Parent ~= deps.player.Character then
		return false, "outil pas en main", nil
	end
	waitFor(function()
		return deps.weaponSystem.getState() == "IDLE"
	end, IDLE_TIMEOUT)
	events = { anims = {}, markers = {}, sounds = {} }
	local before = deps.weaponSystem.getState()
	tool:Activate()
	local cfg = getConfig(tool)
	task.wait((cfg and cfg.ShootAnimTime or 1) + ATTACK_SETTLE)
	local fired = table.find(events.anims, "Shoot") ~= nil
	return fired,
		"état arme avant tir=" .. before,
		{
			anims = table.clone(events.anims),
			markers = table.clone(events.markers),
			sounds = table.clone(events.sounds),
		}
end

local handlers: { [string]: (any) -> (boolean, string, any) } = {
	spawn = spawnInRound,
	watch = watch,
	equipped = checkEquipped,
	aim = aim,
	attack = attack,
	finish = function()
		clearWatch()
		return true, "observateurs retirés"
	end,
}

-- Cette méthode permet d'écouter les commandes du helper serveur lorsque le client tourne dans Studio ;
-- hors Studio elle ne crée aucun listener.
function DebugPlaytest.init(dependencies: Deps)
	if not RunService:IsStudio() then
		return
	end
	deps = dependencies
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.DEBUG_PLAYTEST, 15) :: RemoteEvent?
		if not remote then
			return
		end
		remote.OnClientEvent:Connect(function(id: number, cmd: string, payload: any)
			task.spawn(function()
				local handler = handlers[cmd]
				if not handler then
					remote:FireServer(id, false, "commande inconnue : " .. tostring(cmd))
					return
				end
				local ok, success, detail, data = pcall(handler, payload or {})
				if not ok then
					remote:FireServer(id, false, "erreur client : " .. tostring(success))
					return
				end
				remote:FireServer(id, success, detail, data)
			end)
		end)
	end)
end

return DebugPlaytest

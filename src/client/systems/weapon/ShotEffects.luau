-- ShotEffects.luau
-- Effets visuels du tir (#54) : flamme de bouche et rayon de la balle, réglages et règles dans ShotEffectRules.
--   • Tir du joueur local (HitscanSystem.resolveHit → playLocal) : flamme sur le canon du viewmodel, rayon de la bouche
--     du canon au point touché par le raycast de visée (ou à la portée maximale).
--   • Tirs des autres joueurs et des bots : le serveur relaie chaque tir à distance accepté (remote ShotFired :
--     personnage du tireur, nom de l'arme, origine, direction ; #156, #215) à tous les clients sauf le tireur. Ici, la
--     flamme part du canon de l'arme 3P du tireur et le rayon va de ce canon au point que touche, chez nous, le rayon
--     origine + direction. Rien n'est envoyé au serveur.
-- La flamme est un Emit du ParticleEmitter du modèle de l'arme (aucune Instance créée, elle suit le recul). Le rayon
-- (deux Attachment du Terrain et un Beam, nommés ShotEffectRules.INSTANCE_NAME) s'efface à chaque frame puis est
-- détruit, au plus tard par Debris si la boucle s'arrête.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

local ShotEffects = {}

-- Rayon en cours : ses deux extrémités (le Beam est enfant de la première) et son instant de création (os.clock).
type Tracer = { a0: Attachment, a1: Attachment, beam: Beam, born: number }

local tracers: { Tracer } = {}
local stepConn: RBXScriptConnection? = nil
local connection: RBXScriptConnection? = nil
local getState: () -> string? = function()
	return nil
end
local terrain = workspace:WaitForChild("Terrain")
local TRACER_COLOR = ColorSequence.new(Color3.fromRGB(table.unpack(ShotEffectRules.TRACER_RGB)))
local remoteRayParams = RaycastParams.new()
remoteRayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Cette méthode permet de trouver la bouche du canon d'un modèle d'arme (viewmodel ou 3P) lorsqu'un tir part ;
-- nil si le modèle n'a pas l'Attachment de ShotEffectRules.MUZZLE_PATH.
local function muzzleOf(model: Instance?): Attachment?
	local node = model
	for _, name in ShotEffectRules.MUZZLE_PATH do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("Attachment") then
		return node
	end
	return nil
end

-- Cette méthode permet d'allumer la flamme de bouche lorsqu'un tir part : quelques particules de l'effet du canon
-- (désactivé en continu dans le modèle), qui suivent le canon pendant leur courte vie.
local function flash(muzzle: Attachment)
	local effect = muzzle:FindFirstChild(ShotEffectRules.MUZZLE_EFFECT)
	if effect and effect:IsA("ParticleEmitter") then
		effect:Emit(ShotEffectRules.MUZZLE_EMIT_COUNT)
	end
end

-- Cette méthode permet d'effacer les rayons en cours lorsqu'une frame passe, et de détruire ceux dont la vie est
-- finie (ou déjà détruits par le filet Debris) ; la boucle s'arrête quand il n'en reste plus.
local function step()
	local now = os.clock()
	for i = #tracers, 1, -1 do
		local tracer = tracers[i]
		local elapsed = now - tracer.born
		if elapsed >= ShotEffectRules.TRACER_LIFETIME or not tracer.a0.Parent then
			tracer.a0:Destroy()
			tracer.a1:Destroy()
			table.remove(tracers, i)
		else
			tracer.beam.Transparency = NumberSequence.new(ShotEffectRules.tracerTransparency(elapsed))
		end
	end
	if #tracers == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end
local timedStep = PerfMarkers.wrap("effets de tir", step)

-- Cette méthode permet de créer un rayon entre deux points du monde lorsqu'un tir est montré ; il s'efface ensuite
-- de lui-même (step) et Debris le détruit au plus tard après sa durée de vie et une marge.
local function spawnTracer(start: Vector3, finish: Vector3)
	local a0 = Instance.new("Attachment")
	a0.Name = ShotEffectRules.INSTANCE_NAME
	a0.WorldPosition = start
	local a1 = Instance.new("Attachment")
	a1.Name = ShotEffectRules.INSTANCE_NAME
	a1.WorldPosition = finish

	local beam = Instance.new("Beam")
	beam.Name = ShotEffectRules.INSTANCE_NAME
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = ShotEffectRules.TRACER_WIDTH
	beam.Width1 = ShotEffectRules.TRACER_WIDTH
	beam.Color = TRACER_COLOR
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = a0

	a0.Parent = terrain
	a1.Parent = terrain
	table.insert(tracers, { a0 = a0, a1 = a1, beam = beam, born = os.clock() })
	local maxLife = ShotEffectRules.TRACER_LIFETIME + ShotEffectRules.LIFETIME_MARGIN
	Debris:AddItem(a0, maxLife)
	Debris:AddItem(a1, maxLife)
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
end

-- Cette méthode permet de montrer la flamme et le rayon d'une arme lorsqu'un tir en part : rayon de la bouche du
-- canon (repli : l'origine du tir) jusqu'à endpoint, s'il n'est pas trop court ; camera : arrêté avant elle (autres).
local function show(muzzle: Attachment?, origin: Vector3, endpoint: Vector3, camera: Vector3?)
	if muzzle then
		flash(muzzle)
	end
	local start = ShotEffectRules.tracerStart(origin, muzzle and muzzle.WorldPosition, endpoint)
	local finish: Vector3? = endpoint
	if start and camera then
		finish = ShotEffectRules.clipNearCamera(start, endpoint, camera)
	end
	if start and finish then
		spawnTracer(start, finish)
	end
end

-- Cette méthode permet de montrer les effets du tir du joueur local lorsqu'il tire (HitscanSystem) : flamme sur le
-- viewmodel, rayon de son canon jusqu'au point visé (origin : la caméra, endpoint : impact ou portée maximale).
function ShotEffects.playLocal(viewmodel: Model?, origin: Vector3, endpoint: Vector3)
	show(muzzleOf(viewmodel), origin, endpoint)
end

-- Cette méthode permet de montrer les effets d'un tir relayé par le serveur lorsqu'il arrive : flamme sur l'arme 3P
-- du tireur, et rayon jusqu'au point que touche chez nous son tir (dans la limite des rayons en cours).
local function onShotFired(shooter: any, weaponName: any, origin: any, direction: any)
	if typeof(shooter) ~= "Instance" or not shooter:IsA("Model") then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude == 0 then
		return
	end
	local cfg = type(weaponName) == "string" and WeaponConfig.Weapons[weaponName]
	if not cfg or cfg.IsMelee then
		return
	end
	local localPlayer = Players.LocalPlayer
	if not ShotEffectRules.shouldShow(shooter, localPlayer and localPlayer.Character, getState()) then
		return
	end
	local muzzle = muzzleOf(shooter:FindFirstChild(WeaponThirdPerson.MODEL_NAME))
	if not ShotEffectRules.hasRoom(#tracers) then
		if muzzle then
			flash(muzzle)
		end
		return
	end
	-- Point d'impact vu chez nous : le tireur et notre viewmodel (sous la caméra) ne l'arrêtent pas
	remoteRayParams.FilterDescendantsInstances = { shooter, workspace.CurrentCamera :: Instance }
	local range = WeaponConfig.HITSCAN_RANGE
	local result = workspace:Raycast(origin, direction.Unit * range, remoteRayParams)
	local endpoint = ShotEffectRules.endpoint(origin, direction, result and result.Position, range)
	local camera = workspace.CurrentCamera
	show(muzzle, origin, endpoint, camera and camera.CFrame.Position)
end

-- Cette méthode permet d'écouter les tirs relayés par le serveur lorsque le client démarre ; stateOf lit l'état du
-- client (GameStateController.getState) : pas d'effets des autres dans les écrans du menu.
function ShotEffects.init(stateOf: () -> string?)
	getState = stateOf
	if connection then
		return
	end
	-- Attente hors du fil de démarrage du client (init.client continue sans elle)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.SHOT_FIRED, 15)
		if not (remote and remote:IsA("RemoteEvent")) then
			warn(
				"[ShotEffects] remote "
					.. NetworkProtocol.Names.SHOT_FIRED
					.. " introuvable : tirs des autres sans effets"
			)
			return
		end
		if not connection then
			connection = remote.OnClientEvent:Connect(onShotFired)
		end
	end)
end

return ShotEffects

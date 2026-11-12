-- CasingEjection.luau
-- Douille éjectée à l'ouverture de la culasse (#237), réglages et règles dans CasingRules.
--   • Tir du joueur local : le marqueur CasingRules.MARKER de la piste Shoot du viewmodel (ViewmodelSystem.playAnimation
--     → connectMarker) éjecte une douille de l'EjectPort du viewmodel ; elle hérite de la vitesse du joueur.
--   • Tirs des autres joueurs et des bots : chaque ShotFired relayé par le serveur (comme la flamme, ShotEffects)
--     éjecte une douille de l'EjectPort de l'arme 3P du tireur, CasingEjectDelay (WeaponConfig) plus tard (l'arme 3P ne
--     joue pas la piste Shoot) ; elle hérite du déplacement de l'arme pendant ce délai.
-- Les douilles sont des Parts d'un pool (au plus CasingRules.POOL_SIZE, créées au premier besoin, jamais détruites) :
-- dans workspace pendant leur vol, hors du DataModel (Parent = nil) le reste du temps. Leur vol est calculé, pas
-- simulé par le moteur (pièces ancrées, sans collision ni requête).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CasingRules = require(ReplicatedStorage.Shared.CasingRules)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

local CasingEjection = {}

-- Emplacement du pool : sa pièce et son vol en cours (son instant d'éjection est dans born, nil s'il est libre).
type Slot = { part: BasePart, flight: CasingRules.Flight? }

local slots: { Slot } = {}
local born: { [number]: number? } = {}
local stepConn: RBXScriptConnection? = nil
local connection: RBXScriptConnection? = nil
local random = Random.new()
local getState: () -> string? = function()
	return nil
end
local getVelocity: () -> Vector3 = function()
	return Vector3.zero
end
local CASING_COLOR = Color3.fromRGB(table.unpack(CasingRules.COLOR_RGB))

-- Cette méthode permet de trouver la fenêtre d'éjection d'un modèle d'arme (viewmodel ou 3P) lorsqu'une douille
-- doit partir ; nil si le modèle n'a pas l'Attachment de CasingRules.PORT_PATH.
local function portOf(model: Instance?): Attachment?
	local node = model
	for _, name in CasingRules.PORT_PATH do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("Attachment") then
		return node
	end
	return nil
end

-- Cette méthode permet de créer la pièce d'un emplacement du pool lorsqu'il sert pour la première fois.
local function newCasing(): BasePart
	local part = Instance.new("Part")
	part.Name = CasingRules.INSTANCE_NAME
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Metal
	part.Color = CASING_COLOR
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	return part
end

-- Cette méthode permet de rendre une douille au pool lorsque sa vie est finie : la pièce sort du DataModel.
local function release(index: number)
	local slot = slots[index]
	slot.part.Parent = nil
	slot.flight = nil
	born[index] = nil
end

-- Cette méthode permet de déplacer les douilles en vol lorsqu'une frame passe, et de rendre au pool celles dont la vie
-- est finie ; la boucle s'arrête quand plus aucune ne vole.
local function step()
	local now = os.clock()
	local active = 0
	for index, slot in slots do
		local flight, t0 = slot.flight, born[index]
		if flight and t0 then
			local t = now - t0
			if CasingRules.isExpired(t) then
				release(index)
			else
				slot.part.CFrame = CasingRules.cframeAt(flight, t)
				active += 1
			end
		end
	end
	if active == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local timedStep = PerfMarkers.wrap("douilles", step)

-- Cette méthode permet d'éjecter une douille d'une fenêtre d'éjection lorsque la culasse s'ouvre (scale : échelle de
-- l'arme, inherited : vitesse du tireur) ; evict faux : rien si le pool est plein (tirs des autres).
local function eject(port: Attachment, scale: number, inherited: Vector3, evict: boolean)
	local index = CasingRules.pickSlot(born, CasingRules.POOL_SIZE, evict)
	if not index then
		return
	end
	local slot = slots[index]
	if not slot then
		slot = { part = newCasing() }
		slots[index] = slot
	end
	local rolls = { random:NextNumber(), random:NextNumber(), random:NextNumber(), random:NextNumber() }
	local flight = CasingRules.launch(port.WorldCFrame, scale, inherited, rolls)
	slot.flight = flight
	born[index] = os.clock()
	slot.part.Size = Vector3.new(CasingRules.LENGTH, CasingRules.DIAMETER, CasingRules.DIAMETER) * scale
	slot.part.CFrame = flight.start
	-- dans workspace, pas sous la caméra : une caméra remplacée détruirait la pièce et bloquerait son emplacement
	slot.part.Parent = workspace
	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(timedStep)
	end
end

-- Cette méthode permet de brancher l'éjection sur le marqueur de la piste lorsqu'elle démarre (ViewmodelSystem) ; nil
-- sans fenêtre d'éjection, et rien ne part si le viewmodel est masqué (lunette) au moment du marqueur.
function CasingEjection.connectMarker(track: AnimationTrack, viewmodel: Model): RBXScriptConnection?
	if not portOf(viewmodel) then
		return nil
	end
	return track:GetMarkerReachedSignal(CasingRules.MARKER):Connect(function()
		local port = portOf(viewmodel)
		local body = port and port.Parent
		if not port or not (body and body:IsA("BasePart")) or body.LocalTransparencyModifier >= 1 then
			return
		end
		-- Échelle 1 : le viewmodel est un clone tel quel du modèle source, dont GetScale() vaut 0,517 (mis à l'échelle à
		-- sa création) alors que les réglages de CasingRules sont pris dans ce repère.
		eject(port, 1, getVelocity(), true)
	end)
end

-- Cette méthode permet de savoir si un tir relayé a droit à ses effets lorsqu'il arrive puis quand sa douille part :
-- tir d'un autre, hors écrans du menu (mêmes conditions que la flamme).
local function shouldShow(shooter: Model): boolean
	local localPlayer = Players.LocalPlayer
	return ShotEffectRules.shouldShow(shooter, localPlayer and localPlayer.Character, getState())
end

-- Cette méthode permet d'éjecter la douille d'un tir relayé lorsque sa culasse s'ouvre : depuis l'arme 3P du tireur si
-- le tireur vit encore, a toujours la même arme près de notre caméra ; vitesse : celle de l'arme pendant le délai.
local function ejectRemote(shooter: Model, weaponName: string, gun: Model, from: Vector3, delay: number)
	if gun.Parent ~= shooter or not shooter:IsDescendantOf(workspace) or not shouldShow(shooter) then
		return
	end
	local humanoid = shooter:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return
	end
	local port = gun:GetAttribute("WeaponName") == weaponName and portOf(gun)
	local camera = workspace.CurrentCamera
	if not (port and camera and CasingRules.isNearCamera(port.WorldPosition, camera.CFrame.Position)) then
		return
	end
	local inherited = CasingRules.inheritedVelocity(from, port.WorldPosition, delay)
	eject(port, gun:GetScale(), inherited, false)
end

-- Cette méthode permet de programmer la douille d'un tir relayé par le serveur lorsqu'il arrive (armes à distance qui
-- ont un CasingEjectDelay et une fenêtre d'éjection sur leur arme 3P).
local function onShotFired(shooter: any, weaponName: any)
	if typeof(shooter) ~= "Instance" or not shooter:IsA("Model") or type(weaponName) ~= "string" then
		return
	end
	local cfg = WeaponConfig.Weapons[weaponName]
	local delay = cfg and cfg.CasingEjectDelay
	if type(delay) ~= "number" or not shouldShow(shooter) then
		return
	end
	local gun = shooter:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	local port = gun and gun:IsA("Model") and portOf(gun)
	if not (gun and gun:IsA("Model") and port) then
		return
	end
	task.delay(delay, ejectRemote, shooter, weaponName, gun, port.WorldPosition, delay)
end

-- Cette méthode permet d'écouter les tirs relayés lorsque le client démarre : stateOf lit l'état du client (pas de
-- douilles des autres au menu), velocityOf la vitesse du joueur local, dont héritent ses douilles.
function CasingEjection.init(stateOf: () -> string?, velocityOf: () -> Vector3)
	getState = stateOf
	getVelocity = velocityOf
	if connection then
		return
	end
	-- Attente hors du fil de démarrage du client (init.client continue sans elle)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.SHOT_FIRED, 15)
		if not (remote and remote:IsA("RemoteEvent")) then
			warn(
				"[CasingEjection] remote "
					.. NetworkProtocol.Names.SHOT_FIRED
					.. " introuvable : pas de douilles des autres"
			)
			return
		end
		if not connection then
			connection = remote.OnClientEvent:Connect(onShotFired)
		end
	end)
end

return CasingEjection

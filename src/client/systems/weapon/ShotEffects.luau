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

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)
local BaliseMarks = require(script.Parent.BaliseMarks)
local LightningBolt = require(script.Parent.LightningBolt)
local PanBurst = require(script.Parent.PanBurst)
local TemperFlakes = require(script.Parent.TemperFlakes)
local ScopeSystem = require(script.Parent.ScopeSystem)
local LocalInventory = require(script.Parent.Parent.inventory.LocalInventory)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

local ShotEffects = {}

-- Rayon en cours : ses deux extrémités (le Beam est enfant de la première) et leurs positions, son instant de
-- création (os.clock), son palier de fondu courant, sa durée de vie, pour TREMPE (#566) le tirage de ses franges
-- (nil : couleur fixe), et pour BALISE (#567) le ruban qui se déroule puis se rétracte (extrémités déplacées).
type Tracer = {
	a0: Attachment,
	a1: Attachment,
	beam: Beam,
	start: Vector3,
	finish: Vector3,
	born: number,
	fade: number,
	life: number,
	temperSeed: number?,
	balise: boolean?,
}

local tracers: { Tracer } = {}
local stepConn: RBXScriptConnection? = nil
local connection: RBXScriptConnection? = nil
local getState: () -> string? = function()
	return nil
end
local terrain = workspace:WaitForChild("Terrain")
local TRACER_COLOR = ColorSequence.new(Color3.fromRGB(table.unpack(ShotEffectRules.TRACER_RGB)))
-- Transparence de chaque palier du fondu, précalculée : pas de NumberSequence créée à chaque frame.
local FADE: { NumberSequence } = {}
for i = 0, ShotEffectRules.FADE_STEPS do
	FADE[i + 1] = NumberSequence.new(i / ShotEffectRules.FADE_STEPS)
end
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

-- Cette méthode permet de composer les couleurs d'un rayon TREMPE (#566) à un instant de sa vie lorsqu'il est créé puis
-- à chaque frame (ShotEffectRules.temperKeypoints).
local function temperColor(elapsed: number, seed: number): ColorSequence
	local keypoints = {}
	for i, point in ShotEffectRules.temperKeypoints(elapsed, seed) do
		keypoints[i] = ColorSequenceKeypoint.new(point[1], Color3.fromRGB(point[2], point[3], point[4]))
	end
	return ColorSequence.new(keypoints)
end

-- Cette méthode permet d'effacer les rayons en cours lorsqu'une frame passe (masqués si la caméra les traverse ; les
-- franges de TREMPE défilent), et de détruire ceux dont la vie est finie (ou déjà détruits par Debris) ; la boucle
-- s'arrête quand il n'en reste plus.
local function step()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	for i = #tracers, 1, -1 do
		local tracer = tracers[i]
		local elapsed = now - tracer.born
		if elapsed >= tracer.life or not tracer.a0.Parent then
			tracer.a0:Destroy()
			tracer.a1:Destroy()
			table.remove(tracers, i)
		else
			local hidden = eye ~= nil and ShotEffectRules.isTooClose(tracer.start, tracer.finish, eye)
			local fade = ShotEffectRules.fadeStep(elapsed, hidden, tracer.life)
			if tracer.balise then
				-- BALISE : opaque, il disparaît en se rétractant, pas en s'effaçant
				fade = if hidden then ShotEffectRules.FADE_STEPS else 0
				local tail, head = ShotEffectRules.baliseSpan(elapsed)
				local path = tracer.finish - tracer.start
				tracer.a0.WorldPosition = tracer.start + path * tail
				tracer.a1.WorldPosition = tracer.start + path * head
			end
			if fade ~= tracer.fade then
				tracer.fade = fade
				tracer.beam.Transparency = FADE[fade + 1]
			end
			if tracer.temperSeed and not hidden then
				tracer.beam.Color = temperColor(elapsed, tracer.temperSeed)
			end
		end
	end
	if #tracers == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local timedStep = PerfMarkers.wrap("effets de tir", step)

-- Cette méthode permet de créer un rayon entre deux points du monde lorsqu'un tir est montré (`style` "temper" : rayon
-- TREMPE, #566 ; "balise" : ruban BALISE, #567) ; il s'efface ensuite de lui-même (step) et Debris le détruit au plus
-- tard après sa durée de vie et une marge.
local function spawnTracer(start: Vector3, finish: Vector3, style: string?)
	local balise = style == "balise"
	local a0 = Instance.new("Attachment")
	a0.Name = ShotEffectRules.INSTANCE_NAME
	a0.WorldPosition = start
	local a1 = Instance.new("Attachment")
	a1.Name = ShotEffectRules.INSTANCE_NAME
	-- BALISE : le ruban part de la bouche du canon et se déroule (step)
	a1.WorldPosition = if balise then start else finish

	local temperSeed = if style == "temper" then math.random() else nil
	local width = if temperSeed
		then ShotEffectRules.TEMPER_WIDTH
		elseif balise then ShotEffectRules.BALISE_WIDTH
		else ShotEffectRules.TRACER_WIDTH
	local beam = Instance.new("Beam")
	beam.Name = ShotEffectRules.INSTANCE_NAME
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width
	beam.Color = if temperSeed then temperColor(0, temperSeed) else TRACER_COLOR
	beam.Transparency = FADE[1]
	-- TREMPE : couleurs sombres (bleu, violet) qu'une lumière additive pleine laverait, dégradé découpé en segments
	beam.LightEmission = if temperSeed then ShotEffectRules.TEMPER_LIGHT_EMISSION else 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = if temperSeed then ShotEffectRules.TEMPER_SEGMENTS else 1
	if temperSeed then
		-- TREMPE : ruban torsadé (texture répétée qui défile) et écailles d'oxyde semées le long du rayon
		beam.Texture = ShotEffectRules.TEMPER_RIBBON_IMAGE
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = ShotEffectRules.TEMPER_TWIST_LENGTH
		beam.TextureSpeed = ShotEffectRules.TEMPER_TWIST_SPEED
		TemperFlakes.spawn(start, finish)
	elseif balise then
		-- BALISE : ruban de chantier aux couleurs de l'image (blanc : pas de teinte, pas de lumière additive qui
		-- rendrait le noir transparent), chevrons qui défilent vers la cible
		beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		beam.LightEmission = 0
		beam.Texture = ShotEffectRules.BALISE_TAPE_IMAGE
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = ShotEffectRules.BALISE_TAPE_LENGTH
		beam.TextureSpeed = ShotEffectRules.BALISE_TAPE_SPEED
	end
	beam.Parent = a0

	a0.Parent = terrain
	a1.Parent = terrain
	local life = ShotEffectRules.tracerLifetime(style)
	table.insert(tracers, {
		a0 = a0,
		a1 = a1,
		beam = beam,
		start = start,
		finish = finish,
		born = os.clock(),
		fade = 0,
		life = life,
		temperSeed = temperSeed,
		balise = balise,
	})
	local maxLife = life + ShotEffectRules.LIFETIME_MARGIN
	Debris:AddItem(a0, maxLife)
	Debris:AddItem(a1, maxLife)
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
end

-- Cette méthode permet de lire le style de tir équipé par le joueur local (#566) lorsqu'il tire ou que l'aperçu le
-- montre ; nil : rayon de balle ordinaire.
function ShotEffects.localStyle(): string?
	return ShotEffectRules.styleOf(InventoryRules.effectOf(LocalInventory.equipped()))
end

-- Cette méthode permet de lire le style de tir d'un tireur relayé (#566) lorsque son tir arrive : celui du joueur dont
-- c'est le personnage (ses attributs informatifs), nil pour un bot.
local function styleOfShooter(shooter: Model): string?
	local player = Players:GetPlayerFromCharacter(shooter)
	if not player then
		return nil
	end
	return ShotEffectRules.styleOfPlayer(
		player:GetAttribute(InventoryRules.EQUIPPED_ATTRIBUTE),
		player:GetAttribute(InventoryRules.ATTRIBUTE)
	)
end

-- Cette méthode permet de montrer la flamme et le rayon d'une arme lorsqu'un tir en part : rayon de la bouche du
-- canon (repli : l'origine du tir) jusqu'à endpoint, s'il n'est pas trop court ; camera : arrêté avant elle (autres) ;
-- style : effet de tir équipé (#566 : éclair à la place du rayon s'il reste de la place, rayon TREMPE, ou explosion
-- PAN ! en plus du rayon ; `isLocal` : tir du joueur local, explosion réduite et absente à la lunette ; `panAhead`,
-- `panWidth` : avance et largeur de l'explosion, pour une démonstration).
local function show(
	muzzle: Attachment?,
	origin: Vector3,
	endpoint: Vector3,
	camera: Vector3?,
	style: string?,
	isLocal: boolean?,
	panAhead: number?,
	panWidth: number?
)
	if muzzle then
		flash(muzzle)
	end
	local start = ShotEffectRules.tracerStart(origin, muzzle and muzzle.WorldPosition, endpoint)
	local finish: Vector3? = endpoint
	if start and camera then
		start, finish = ShotEffectRules.clipNearCamera(start, endpoint, camera)
	end
	if start and finish then
		if style == "pan" and not (isLocal and ScopeSystem.getLevel() > 0) then
			-- Le rayon sort du bord de l'explosion : tracé par-dessus, il barrerait l'onomatopée
			local center, width = PanBurst.spawn(start, finish, isLocal == true, panAhead, panWidth)
			if center then
				start = ShotEffectRules.panTracerStart(start, finish, center, width)
			end
		end
		if style == "lightning" and LightningBolt.spawn(start, finish) then
			return
		end
		if style == "balise" then
			-- Boucle au canon (pas à la lunette : elle serait dans l'œil du tireur) et chevrons à l'impact
			BaliseMarks.spawn(start, finish, isLocal == true, not (isLocal and ScopeSystem.getLevel() > 0))
		end
		spawnTracer(start, finish, style)
	end
end

-- Cette méthode permet de montrer les effets du tir du joueur local lorsqu'il tire (HitscanSystem) : flamme sur le
-- viewmodel, rayon de son canon jusqu'au point visé (origin : la caméra, endpoint : impact ou portée maximale).
function ShotEffects.playLocal(viewmodel: Model?, origin: Vector3, endpoint: Vector3)
	show(muzzleOf(viewmodel), origin, endpoint, nil, ShotEffects.localStyle(), true)
end

-- Cette méthode permet de montrer un tir de démonstration d'un style (#566) lorsque l'écran d'équipement ou la
-- révélation d'une caisse d'effets l'affiche : effet (et rayon) de la bouche du canon `start` jusqu'à `endpoint`, sans
-- flamme (l'arme montrée n'a pas toujours son émetteur) ; l'explosion PAN ! y est placée pour rester dans le cadre
-- (`panAhead`, `panWidth` ; par défaut PAN_AHEAD_DEMO et la largeur ordinaire, aperçu du menu).
function ShotEffects.playDemo(start: Vector3, endpoint: Vector3, style: string?, panAhead: number?, panWidth: number?)
	show(nil, start, endpoint, nil, style, false, panAhead or ShotEffectRules.PAN_AHEAD_DEMO, panWidth)
end

-- Cette méthode permet de montrer un tir mis en scène par la démonstration d'un effet (#575, EffectStage) lorsqu'il part,
-- rendu comme en partie : `firstPerson`, tir du joueur vu par lui (viewmodel) ; sinon tir d'un autre vu de `camera`.
function ShotEffects.playStaged(
	weapon: Instance?,
	origin: Vector3,
	endpoint: Vector3,
	style: string?,
	firstPerson: boolean,
	camera: Vector3?
)
	show(muzzleOf(weapon), origin, endpoint, if firstPerson then nil else camera, style, firstPerson)
end

-- Cette méthode permet de trouver la bouche du canon d'un modèle d'arme (#566) lorsque l'aperçu vise devant elle ;
-- nil sans canon.
function ShotEffects.muzzleOf(weapon: Instance?): Attachment?
	return muzzleOf(weapon)
end

-- Cette méthode permet de montrer la flamme et le rayon d'un tir rejoué par le clip de la partie (#499) lorsqu'il y
-- arrive : canon de `weapon` (viewmodel ou arme 3P d'un figurant), rayon jusqu'au point que touche origin + direction
-- dans la map (`ignore` écarté) ; `camera` : arrêté avant elle (tirs des figurants).
function ShotEffects.playReplay(
	weapon: Instance?,
	origin: Vector3,
	direction: Vector3,
	ignore: { Instance },
	camera: Vector3?
)
	if direction.Magnitude < 1e-6 then
		return
	end
	local muzzle = muzzleOf(weapon)
	if not ShotEffectRules.hasRoom(#tracers) then
		if muzzle then
			flash(muzzle)
		end
		return
	end
	remoteRayParams.FilterDescendantsInstances = ignore
	local range = WeaponConfig.HITSCAN_RANGE
	local result = workspace:Raycast(origin, direction.Unit * range, remoteRayParams)
	local endpoint = ShotEffectRules.endpoint(origin, direction, result and result.Position, range)
	-- Le clip ne garde pas l'effet de tir de ses tireurs : rayon ordinaire
	show(muzzle, origin, endpoint, camera, nil)
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
	local gun = shooter:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	local muzzle = muzzleOf(gun)
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
	show(muzzle, origin, endpoint, camera and camera.CFrame.Position, styleOfShooter(shooter))
end

-- Cette méthode permet d'écouter les tirs relayés par le serveur lorsque le client démarre ; stateOf lit l'état du
-- client (GameStateController.getState) : pas d'effets des autres dans les écrans du menu.
function ShotEffects.init(stateOf: () -> string?)
	getState = stateOf
	if connection then
		return
	end
	-- Réserve d'un éclair (#520, effet ÉCLAIR #566) remplie en tâche de fond, si le style est activé : le premier tir ne
	-- crée rien
	if ShotEffectRules.isEnabled("lightning") then
		LightningBolt.prewarm()
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

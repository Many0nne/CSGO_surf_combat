-- Démonstration d'un effet de tir (#575, docs/ui.md « Aperçu d'un effet de tir ») : au survol d'un effet dans le shop ou
-- dans l'onglet EFFET de l'équipement, une courte scène jouée en boucle sur la map, avec les vrais effets (ShotEffects).
-- Deux plans montés cut (EffectStageRules) : le tir vu par le tireur, viewmodel de l'AWP dans son skin équipé, puis le
-- même tir vu de côté, tel que le voient les autres joueurs. Le tireur (tenue équipée) vise une cible debout sur le
-- toit d'en face. Décor : copie locale du morceau de map vu par les deux plans (MapCopy), posée loin de la vraie map et
-- des autres scènes. Pas de ViewportFrame : il n'affiche ni Beams ni particules, la scène prend donc la caméra ; les
-- scènes du menu (MenuScene, ShopScene) lâchent la leur tant que `EffectStage.isShowing()`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared:WaitForChild("CameraConfig"))
local CharacterAppearance = require(Shared:WaitForChild("CharacterAppearance"))
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local MapSelection = require(Shared:WaitForChild("MapSelection"))
local PerfMarkers = require(Shared:WaitForChild("PerfMarkers"))
local WeaponThirdPerson = require(Shared:WaitForChild("WeaponThirdPerson"))
local LocalInventory = require(script.Parent.Parent.inventory.LocalInventory)
local ShotEffects = require(script.Parent.Parent.weapon.ShotEffects)
local ViewmodelClone = require(script.Parent.Parent.weapon.ViewmodelClone)
local MapCopy = require(script.Parent.MapCopy)
local MenuSceneRules = require(script.Parent.MenuSceneRules)
local Rules = require(script.Parent.EffectStageRules)
local SceneFigure = require(script.Parent.SceneFigure)

local EffectStage = {}

-- Copie posée à ce décalage de la vraie map : loin d'elle, de l'accueil (+5 000 en Z) et de la salle du shop
local OFFSET = Vector3.new(0, 0, -5000)
local MAP_WAIT = 15 -- s d'attente de la map jouée
local COPY_CONE: MapCopy.Cone = { tanHalf = 1.0, distance = 600, near = 40 }
-- Arme des effets : la seule arme à distance (cartes de l'onglet EFFET, caisse d'effets)
local TOOL = "AWP"
-- Plan de côté : FOV vertical au format de référence (16:9), ouvert sur un écran plus étroit
local THIRD_FOV = 40
local ASPECT_REF = 16 / 9

-- Stand de tir par map (coordonnées de la map telle qu'elle est posée) : pieds du tireur (y relevé au sol, recalé par un
-- rayon), direction du tir, distance de la cible ; plan de côté : place de la caméra et point visé, dans le repère du
-- tireur (X à droite de son tir, Y en haut, Z vers la cible, studs depuis ses pieds). Le plan de côté montre le tir de
-- gauche à droite, tireur et cible dans la moitié droite de l'image (la colonne de l'interface tient la gauche).
type Stand = {
	feet: Vector3,
	facing: Vector3,
	range: number,
	camera: Vector3,
	lookAt: Vector3,
}
local STANDS: { [string]: Stand } = {
	-- Toit au-dessus de la cour des rampes : le tir file vers le nord entre les deux hangars, grue et couchant au fond ;
	-- plan de côté depuis l'ouest du toit, hangar et bâtiment du sud en fond (cadrés dans Studio le 18/11/2026)
	Dizzy = {
		feet = Vector3.new(2000, 70.5, -395),
		facing = Vector3.new(0, 0, 1),
		range = 35,
		camera = Vector3.new(68, 11.5, -4),
		lookAt = Vector3.new(0, 2.5, -2),
	},
}

-- Géométrie de la scène construite (décalée de OFFSET) : œil du tireur, point visé sur la cible, plan de côté
type Layout = { eye: Vector3, aim: Vector3, first: CFrame, third: CFrame, shooterAt: CFrame }

local stage: Folder? = nil
local building = false
local layout: Layout? = nil
local shooter: Model? = nil
local shooterSkin: string? = nil -- skin de l'AWP tenue par le tireur
local shooterOutfit: string? = nil
local held: ViewmodelClone.Held? = nil
local style: string? = nil -- effet montré (nil : rayon de balle ordinaire)
local wanted = false -- une démonstration est demandée (elle commence dès la scène construite)
local showing = false
local clock = 0
local connection: RBXScriptConnection? = nil

-- Cette méthode permet de donner le stand de tir d'une map lorsque la scène se construit : celui de STANDS, sinon devant
-- le premier point d'apparition au sol (map sans stand réglé).
local function standFor(map: Instance): Stand?
	local stand = STANDS[map.Name]
	if stand then
		return stand
	end
	local spawns = map:FindFirstChild("GroundSpawns")
	local spawn = spawns and spawns:FindFirstChildWhichIsA("BasePart", true)
	if not spawn then
		return nil
	end
	local look = Vector3.new(spawn.CFrame.LookVector.X, 0, spawn.CFrame.LookVector.Z)
	return {
		feet = spawn.Position,
		facing = if look.Magnitude > 1e-3 then look.Unit else Vector3.xAxis,
		range = 35,
		camera = Vector3.new(68, 11.5, -4),
		lookAt = Vector3.new(0, 2.5, -2),
	}
end

-- Cette méthode permet de lire l'arme et la tenue équipées (#268, #521) lorsque la démonstration commence : c'est avec
-- elles que le joueur verra l'effet.
local function equippedLook(): (string?, string?)
	local equipped = LocalInventory.equipped()
	return InventoryRules.skinOfTool(equipped, TOOL), InventoryRules.outfitOf(equipped)
end

-- Cette méthode permet de mettre l'AWP dans les mains du tireur, habillée du skin `skinId`, lorsque la scène se
-- construit ou que le skin équipé a changé ; le modèle garde son tag : WeaponThirdPersonView pose la tenue de tir et le
-- recul, comme pour un autre joueur.
local function arm(model: Model, skinId: string?)
	local tool = ViewmodelClone.tool(TOOL)
	local viewmodelName = tool and tool:GetAttribute("ViewmodelName")
	local weapon = tool and tool:GetAttribute("WeaponName")
	WeaponThirdPerson.attach(
		model,
		if type(weapon) == "string" then weapon else TOOL,
		if type(viewmodelName) == "string" then viewmodelName else nil,
		skinId
	)
	shooterSkin = skinId
end

-- Cette méthode permet de construire la scène une seule fois (copie de la map, tireur, cible) lorsqu'une démonstration
-- est demandée pour la première fois ou qu'un écran la prépare ; elle attend la map jouée et commence la démonstration
-- si elle est toujours demandée.
local function build()
	if stage or building then
		return
	end
	building = true
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local map = MapSelection.waitForActive(MAP_WAIT)
	local stand = map and standFor(map)
	if not (map and stand) then
		building = false
		return
	end
	local facing = stand.facing.Unit
	local right = facing:Cross(Vector3.yAxis).Unit
	local up = Vector3.yAxis
	local targetFeet = stand.feet + facing * stand.range
	local thirdEye = stand.feet + right * stand.camera.X + up * stand.camera.Y + facing * stand.camera.Z
	local thirdLook = stand.feet + right * stand.lookAt.X + up * stand.lookAt.Y + facing * stand.lookAt.Z

	local folder = Instance.new("Folder")
	folder.Name = "EffectStage"
	local mapCopy = Instance.new("Folder")
	mapCopy.Name = "Map"
	MapCopy.copy(map, {
		{ eye = stand.feet + up * 5, forward = facing },
		{ eye = thirdEye, forward = (thirdLook - thirdEye).Unit },
	}, COPY_CONE, OFFSET, mapCopy)
	mapCopy.Parent = folder
	folder.Parent = workspace -- le temps de poser les personnages au sol (rayons)

	local shooterGround = MapCopy.groundUnder(stand.feet + OFFSET, mapCopy)
	local targetGround = MapCopy.groundUnder(targetFeet + OFFSET, mapCopy)
	local skin, outfit = equippedLook()
	local model = SceneFigure.build(shooterGround, facing, folder, "EffectShooter", outfit)
	local target = SceneFigure.build(targetGround, -facing, folder, "EffectTarget", nil)
	local shooterRoot = model and model:FindFirstChild("HumanoidRootPart")
	local targetChest = target and (target:FindFirstChild("UpperTorso") or target:FindFirstChild("HumanoidRootPart"))
	if not (model and shooterRoot and shooterRoot:IsA("BasePart") and targetChest and targetChest:IsA("BasePart")) then
		folder:Destroy()
		building = false
		return
	end
	arm(model, skin)
	shooterOutfit = outfit
	shooter = model

	local eye = shooterRoot.Position + up * CameraConfig.CAM_HEIGHT_STAND
	local aim = targetChest.Position
	layout = {
		eye = eye,
		aim = aim,
		first = CFrame.lookAt(eye, aim),
		third = CFrame.lookAt(thirdEye + OFFSET, thirdLook + OFFSET),
		shooterAt = model:GetPivot(),
	}
	stage = folder
	folder.Parent = if showing then workspace else nil
	building = false
	if wanted then
		EffectStage.play(style)
	end
end

-- Cette méthode permet de faire partir le tir du plan courant lorsque son instant est franchi : viewmodel (piste Shoot)
-- et effet vu du tireur, ou recul de l'arme 3P et effet vu de côté.
local function fire(view: Rules.View, camera: Camera)
	local current = layout
	if not current then
		return
	end
	if view == "first" then
		local vm = held
		if not vm then
			return
		end
		local track = vm.tracks.Shoot
		if track then
			track.Looped = false
			track:Stop(0)
			track:Play()
		end
		ShotEffects.playStaged(vm.model, current.eye, current.aim, style, true)
	else
		local model = shooter
		if not model then
			return
		end
		WeaponThirdPerson.setAction(model, "Shoot")
		local gun = model:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
		ShotEffects.playStaged(gun, current.eye, current.aim, style, false, camera.CFrame.Position)
	end
end

-- Cette méthode permet de placer la caméra du plan courant (et le viewmodel devant elle) et de faire partir les tirs
-- lorsqu'une image est rendue ; le tireur n'est dans la scène que dans le plan de côté (en 1re personne, la caméra est
-- dans sa tête).
local function update(dt: number)
	local current = layout
	local camera = workspace.CurrentCamera
	if not (current and camera) then
		return
	end
	local before = clock
	clock += math.min(dt, 0.1)
	local view = Rules.viewAt(clock)
	camera.CameraType = Enum.CameraType.Scriptable
	local vm = held
	if view == "first" then
		camera.CFrame = current.first
		camera.FieldOfView = CameraConfig.DEFAULT_FOV
		if vm then
			ViewmodelClone.setVisible(vm, true)
			vm.model:PivotTo(camera.CFrame * vm.offset)
		end
	else
		camera.CFrame = current.third
		local viewport = camera.ViewportSize
		if viewport.Y > 0 then
			camera.FieldOfView = MenuSceneRules.fitFov(THIRD_FOV, ASPECT_REF, viewport.X / viewport.Y)
		end
		if vm then
			ViewmodelClone.setVisible(vm, false)
		end
	end
	local model = shooter
	if model then
		-- Hors du plan de côté, le tireur est rangé sous la scène : son arme et son corps ne passent pas devant la caméra
		local at = if view == "third" then current.shooterAt else current.shooterAt - Vector3.new(0, 500, 0)
		if model:GetPivot() ~= at then
			model:PivotTo(at)
		end
	end
	local shot = Rules.shotBetween(before, clock)
	if shot then
		fire(shot, camera)
	end
end

local timedUpdate = PerfMarkers.wrap("démo d'effet", update)

-- Cette méthode permet de commencer à montrer la scène construite lorsque la démonstration démarre : arme et tenue
-- équipées remises à jour, viewmodel préparé devant la caméra, boucle de rendu.
local function begin()
	local folder = stage
	local camera = workspace.CurrentCamera
	if showing or not (folder and camera) then
		return
	end
	showing = true
	local skin, outfit = equippedLook()
	local model = shooter
	if model and skin ~= shooterSkin then
		arm(model, skin)
	end
	if model and outfit ~= shooterOutfit then
		CharacterAppearance.dress(model, outfit)
		shooterOutfit = outfit
	end
	folder.Parent = workspace
	local vm = ViewmodelClone.build(camera, TOOL, skin)
	if vm then
		CharacterAppearance.dressArms(vm.model, outfit)
		local idle = vm.tracks.Idle
		if idle then
			idle:Play(0)
		end
	end
	held = vm
	connection = RunService.RenderStepped:Connect(timedUpdate)
end

-- Cette méthode permet de construire la scène en tâche de fond lorsqu'un écran qui la montrera s'ouvre (shop, onglet
-- EFFET) : le premier survol n'attend pas la copie de la map.
function EffectStage.prepare()
	if not stage and not building then
		task.spawn(build)
	end
end

-- Cette méthode permet de montrer l'effet `newStyle` (ShotEffectRules.styleOf ; nil : rayon ordinaire) lorsqu'un écran
-- en demande l'aperçu : la démonstration commence (dès la scène construite) ou repart du premier plan avec le nouvel
-- effet ; sans effet si c'est déjà lui qui est montré.
function EffectStage.play(newStyle: string?)
	if wanted and showing and newStyle == style then
		return
	end
	if newStyle ~= style or not showing then
		clock = 0
	end
	style = newStyle
	wanted = true
	if not stage then
		EffectStage.prepare()
		return
	end
	begin()
end

-- Cette méthode permet d'arrêter la démonstration (scène retirée du workspace mais gardée, viewmodel détruit) lorsque
-- l'aperçu se retire ; l'écran reprend sa caméra.
function EffectStage.stop()
	wanted = false
	if not showing then
		return
	end
	showing = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if held then
		held.model:Destroy()
		held = nil
	end
	if stage then
		stage.Parent = nil
	end
end

-- Cette méthode permet de savoir si la démonstration tient la caméra lorsqu'une autre scène du menu s'apprête à poser
-- la sienne.
function EffectStage.isShowing(): boolean
	return showing
end

return EffectStage

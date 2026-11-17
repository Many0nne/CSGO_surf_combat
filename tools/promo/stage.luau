-- stage.luau : mises en scène des miniatures de la page du jeu (#524, docs/promo.md).
-- Studio en mode Edit, contexte Edit, Studio réservé. Le script définit `_G.Promo` (chargement : docs/promo.md) ; ensuite :
--   _G.Promo.shot("surf")              construit la scène nommée (voir SHOTS) et pose la caméra
--   _G.Promo.shot("surf", { fov = 60 }) idem, en remplaçant des réglages de la scène
--   _G.Promo.clear()                   retire la scène et rend la caméra de l'éditeur
-- Décor construit exprès (choix de l'utilisateur, 17/11/2026) : deux rampes de surf isolées au-dessus de la mer de
-- nuages de Dizzy, face au soleil couchant, faites de l'acier des rampes du jeu. Personnage, armes, skins, tenues, rayon
-- de la balle, nuages et lumière sont ceux du jeu.
-- Tout est construit sous Workspace.__PromoStage, non archivable : rien n'est enregistré avec la place ni exporté.

local RS = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Lighting = game:GetService("Lighting")

local WeaponSkins = require(RS.Shared.WeaponSkins)
local WeaponThirdPerson = require(RS.Shared.WeaponThirdPerson)
local CharacterAppearance = require(RS.Shared.CharacterAppearance)
local CharacterConfig = require(RS.Shared.CharacterConfig)
local ShotEffectRules = require(RS.Shared.ShotEffectRules)

local STAGE_NAME = "__PromoStage"
local RAMP_SKIN = "peau d'acier continue de la rampe" -- attribut RampEdge posé par tools/map/RampEdges.luau
local ROOT_TO_FEET = 4.765 -- tools/map/SpawnCheck.luau
local EYE = 2.1 -- CameraConfig.CAM_HEIGHT_STAND - 0.4, hauteur de la caméra FPS au-dessus de la racine
local BODY_HALF = 1.1 -- demi-largeur du corps : le flanc côté pente touche la rampe, comme la boîte de collision

-- Décor : deux rampes parallèles, axe vers le soleil (projeté à l'horizontale). Les nappes de nuages de Dizzy couvrent
-- X 500..3500, Z -1760..1240 vers Y -83 (tools/map/build_dizzy.luau) : le décor est posé au-dessus, hors de la map.
local SPACE = {
	origin = Vector3.new(1300, -20, -1000), -- milieu de l'espace entre les rampes, à hauteur des crêtes
	length = 600, -- longueur d'une rampe
	height = 34, -- hauteur d'une rampe (crête au-dessus de la base)
	angle = 55, -- pente des flancs (degrés)
	gap = 32, -- distance entre les deux crêtes / 2
	shift = 0, -- décalage des rampes le long de l'axe (studs)
	offsetB = 40, -- avance de la rampe B sur la rampe A (studs) : son bout entre dans le champ
}

-- Réglages par scène. Personnages (`actors`) : `ramp` "A" (flanc intérieur de la rampe de gauche, face au soleil) ou
-- "B" (celle de droite), `a` le long (-1..1 de la demi-longueur, +1 vers le soleil), `b` dans la pente (-1 bas, 1 crête),
-- `face` "sun" (glisse vers le soleil), "back" (vers la caméra) ou un angle en degrés autour de la verticale.
-- Caméra (`cam`) : `eye` = yeux d'un surfeur (même repère), `air` = point en l'air (`a`, `x` de -1 rampe A à 1 rampe B,
-- `y` en fraction de la hauteur), `look` = "sun" ou n° d'acteur, puis `yaw`/`pitch` en degrés. `fov` vertical (90 en jeu).
local SHOTS = {
	-- Surf : 3e personne au-dessus du départ des rampes ; les deux rampes se lisent en entier (crêtes, flancs, bout en
	-- triangle) et filent vers le soleil ; un surfeur tire sur un adversaire qui saute sur la rampe d'en face.
	surf = {
		actors = {
			{ ramp = "A", a = -0.93, b = 0.35, face = "sun", weapon = "AWP", skin = "skin.awp.ciselure" },
			{ air = { a = -0.86, x = 0.35, y = 1.05 }, face = "back", weapon = "AWP" },
		},
		shot3p = { from = 1, to = 2 },
		cam = { air = { a = -1.04, x = -0.55, y = 1.35 }, look = "sun", yaw = -6, pitch = -10 },
		fov = 60,
	},
	-- 2 · Le tir : vue subjective en l'air entre les deux rampes, AWP CISELURE qui tire sur un surfeur d'en face.
	-- L'adversaire saute d'une rampe à l'autre, on le touche en plein vol depuis le flanc de la rampe A.
	tir = {
		actors = { { air = { a = -0.82, x = -0.25, y = 1.0 }, face = "back", weapon = "AWP" } },
		cam = { eye = { ramp = "A", a = -0.88, b = 0.3 }, look = 1, yaw = -8, pitch = -4 },
		viewmodel = { name = "AWP", skin = "skin.awp.ciselure" },
		tracer = 1,
		fov = 80,
	},
	-- 3 · Le légendaire AWP : inspection, arme de profil sur le ciel et la mer de nuages, soleil derrière la lunette.
	ciselure = {
		cam = { air = { a = 0.5, x = 8, y = 3 }, look = "sun", yaw = -12, pitch = 6 }, -- hors des rampes : ciel et nuages

		viewmodel = {
			name = "AWP",
			skin = "skin.awp.ciselure",
			raise = { x = 0.9, y = -0.35, z = -0.9, pitch = 10, roll = -10, yaw = 62 },
		},
		fov = 70,
	},
	-- 4 · La lame : M9 CUIR DE CORDOUE levée, lame vers le ciel, une seule main.
	cordoue = {
		cam = { air = { a = 0.5, x = 8, y = 3 }, look = "sun", yaw = -12, pitch = 8 },
		viewmodel = {
			name = "M9Bayonet",
			skin = "skin.m9bayonet.cordoue",
			raise = { x = -0.15, y = 0.3, z = 1.25, pitch = 18, roll = -15, yaw = 0 },
			hide = { "LeftArm" },
		},
		fov = 70,
	},
	-- 5 · Au couteau : vue subjective sur le flanc, on rattrape un surfeur et on lève la M9 CUIR DE CORDOUE.
	lame = {
		actors = { { ramp = "A", a = -0.845, b = 0.36, face = 165, weapon = "AWP" } },
		cam = { eye = { ramp = "A", a = -0.885, b = 0.26 }, look = 1, yaw = 4, pitch = -3 },
		viewmodel = {
			name = "M9Bayonet",
			skin = "skin.m9bayonet.cordoue",
			raise = { x = 0.3, y = 0.15, z = 0.3, pitch = 12, roll = -8, yaw = 0 },
		},
		fov = 90,
	},
}

local Promo = {}

-- Cette méthode permet de retrouver le dossier de la scène lorsqu'on la construit ou la retire ; le crée si demandé.
function Promo.stageFolder(create: boolean): Folder?
	local folder = workspace:FindFirstChild(STAGE_NAME)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = STAGE_NAME
		folder.Archivable = false
		folder.Parent = workspace
	end
	return folder :: Folder?
end

-- Cette méthode permet de retrouver une peau de rampe de Dizzy lorsqu'on veut habiller les rampes du décor de la même
-- matière (Material, MaterialVariant, couleur).
function Promo.rampLook(): BasePart?
	for _, d in workspace:WaitForChild("Maps"):GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RampEdge") == RAMP_SKIN then
			return d
		end
	end
	return nil
end

-- Cette méthode permet de construire une rampe de surf (deux flancs et une crête) lorsqu'on monte le décor, et de
-- décrire son flanc tourné vers `inward` (centre de la surface, axes, demi-dimensions) pour y placer les scènes.
function Promo.buildRamp(parent: Instance, crest: Vector3, along: Vector3, inward: Vector3)
	local h = SPACE.height
	local w = h / math.tan(math.rad(SPACE.angle))
	local slope = math.sqrt(w * w + h * h)
	local look = Promo.rampLook()
	local flanks = {}
	for _, side in { inward, -inward } do
		local up = (Vector3.yAxis * h - side * w).Unit -- du pied vers la crête
		local normal = (side * h + Vector3.yAxis * w).Unit -- vers l'extérieur et le haut
		local center = crest + (side * w - Vector3.yAxis * h) / 2
		local p = Instance.new("Part")
		p.Name = "PromoRamp"
		p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, true
		p.Size = Vector3.new(SPACE.length, 0.6, slope)
		p.CFrame = CFrame.fromMatrix(center - normal * 0.3, along, normal, along:Cross(normal))
		if look then
			p.Material, p.MaterialVariant, p.Color = look.Material, look.MaterialVariant, look.Color
		end
		p.Parent = parent
		-- Bout de la rampe tourné vers la caméra : triangle plein (deux coins), pour que la section se lise.
		local endPoint = crest - along * (SPACE.length / 2)
		local cap = Instance.new("WedgePart")
		cap.Name = "PromoRampEnd"
		cap.Anchored, cap.CanCollide, cap.CanQuery = true, false, false
		cap.Size = Vector3.new(0.6, h, w)
		cap.CFrame = CFrame.fromMatrix(endPoint + side * (w / 2) - Vector3.yAxis * (h / 2), along, Vector3.yAxis, -side)
		if look then
			cap.Material, cap.MaterialVariant, cap.Color = look.Material, look.MaterialVariant, look.Color
		end
		cap.Parent = parent
		flanks[side] = {
			center = center,
			along = along,
			up = up,
			normal = normal,
			halfLen = SPACE.length / 2,
			halfSlope = slope / 2,
		}
	end
	-- Crête en béton clair, comme la bande au sommet des rampes de Dizzy : elle dessine l'arête de la rampe sur le ciel.
	local ridge = Instance.new("Part")
	ridge.Name = "PromoRampCrest"
	ridge.Anchored, ridge.CanCollide, ridge.CanQuery = true, false, false
	ridge.Size = Vector3.new(SPACE.length, 1.2, 2.4)
	ridge.CFrame = CFrame.fromMatrix(crest, along, Vector3.yAxis, along:Cross(Vector3.yAxis))
	ridge.Material, ridge.Color = Enum.Material.Concrete, Color3.fromRGB(214, 206, 198)
	ridge.Parent = parent
	return flanks[inward]
end

-- Cette méthode permet de monter le décor (deux rampes de part et d'autre de l'origine, axe vers le soleil) lorsqu'une
-- scène le demande ; renvoie les flancs intérieurs A et B et les axes du décor.
function Promo.buildSpace(parent: Instance)
	local sun = Lighting:GetSunDirection()
	local along = Vector3.new(sun.X, 0, sun.Z).Unit
	local side = along:Cross(Vector3.yAxis).Unit -- à droite quand on regarde le soleil
	local o = SPACE.origin + along * SPACE.shift
	return {
		A = Promo.buildRamp(parent, o - side * SPACE.gap, along, side),
		B = Promo.buildRamp(parent, o + side * SPACE.gap + along * SPACE.offsetB, along, -side),
		along = along,
		side = side,
		origin = o,
	}
end

-- Cette méthode permet de donner un point de la surface d'une rampe lorsqu'on y place un personnage ou la caméra.
function Promo.rampPoint(r, a: number, b: number, h: number?): Vector3
	return r.center + r.along * (a * r.halfLen) + r.up * (b * r.halfSlope) + r.normal * (h or 0)
end

-- Cette méthode permet de placer la racine d'un personnage debout sur la pente lorsqu'il surfe : pieds sur la surface,
-- corps décalé vers le vide pour que son flanc touche la rampe sans la traverser.
function Promo.surferRoot(r, a: number, b: number): Vector3
	local feet = Promo.rampPoint(r, a, b)
	local outward = Vector3.new(r.normal.X, 0, r.normal.Z).Unit
	return feet + outward * BODY_HALF + Vector3.new(0, ROOT_TO_FEET, 0)
end

-- Cette méthode permet de poser le personnage du jeu en surf (jambes de la piste de chute, tenue de l'arme en l'air)
-- lorsqu'une scène montre un adversaire ou le joueur en 3e personne.
function Promo.buildSurfer(parent: Instance, rootPos: Vector3, look: Vector3, weapon: string?, skinId: string?): Model
	local char = (StarterPlayer:FindFirstChild("StarterCharacter") :: Model):Clone()
	for _, d in char:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	CharacterAppearance.apply(char)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
		end
	end
	char.PrimaryPart = root
	char.Parent = parent
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	char:PivotTo(CFrame.lookAt(rootPos, rootPos + flat))

	-- Jambes : piste de surf du jeu (repli FALL, CharacterConfig.FALLBACK), figée à 0,2 s.
	local humanoid = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.AnimationId = CharacterConfig.ANIMATIONS.FALL
	local track = (animator :: Animator):LoadAnimation(anim)
	track:Play(0);
	(animator :: Animator):StepAnimations(0.2)
	-- Figer la pose dans les C0 : en mode Edit, un Transform posé à la main n'est pas rendu de façon fiable (vérifié :
	-- les bras restaient dans la pose de la chute), alors qu'un C0 l'est. Les C0 du rig n'ont aucune rotation, donc
	-- C0 * Transform donne la même pose qu'en jeu.
	local baseC0, frozen = {}, {}
	for _, motor in char:GetDescendants() do
		if motor:IsA("Motor6D") then
			baseC0[motor.Name] = motor.C0
			frozen[motor] = motor.Transform
		end
	end
	track:Stop(0)
	animator:Destroy()
	for motor, transform in frozen do
		motor.Transform = CFrame.identity
		motor.C0 = motor.C0 * transform
	end

	-- Haut du corps : tenue de l'arme, en l'air (AirJoints à plein poids).
	if weapon then
		local settings = WeaponThirdPerson.getSettings(weapon)
		for _, joint in WeaponThirdPerson.HOLD_JOINTS do
			local motor = char:FindFirstChild(joint, true)
			local target, weight = WeaponThirdPerson.holdTarget(settings.Pose, joint, 1)
			if motor and motor:IsA("Motor6D") and target and weight > 0 then
				motor.C0 = baseC0[joint] * target
			end
		end
		WeaponThirdPerson.attach(char, weapon, weapon, skinId)
	end
	return char
end

-- Cette méthode permet de poser un viewmodel habillé devant la caméra, dans sa pose Idle, lorsqu'une scène est en vue
-- subjective ; `raise` décale et tourne tout le rig (bras compris) pour lever l'arme dans le cadre.
function Promo.buildViewmodel(parent: Instance, camCF: CFrame, spec): Model
	local model = RS.ViewModels[spec.name]:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	WeaponSkins.apply(model, spec.name, spec.skin)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
			d.CastShadow = true
		end
	end
	model.PrimaryPart = root :: BasePart
	-- Pièces à cacher pour le cadrage (ex. le bras gauche qui barre le ciel quand l'arme est levée).
	for _, name in spec.hide or {} do
		local part = model:FindFirstChild(name, true)
		for _, d in if part then { part, table.unpack(part:GetDescendants()) } else {} do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
	model.Parent = parent

	local tool = RS.Tools:FindFirstChild(spec.name)
	local offset = tool and tool:GetAttribute("ViewmodelOffset")
	offset = if typeof(offset) == "CFrame" then offset else CFrame.new()
	local raise = spec.raise or {}
	local extra = CFrame.new(raise.x or 0, raise.y or 0, raise.z or 0)
		* CFrame.Angles(math.rad(raise.pitch or 0), math.rad(raise.yaw or 0), math.rad(raise.roll or 0))
	model:PivotTo(camCF * offset * extra)

	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	local host = controller or model:FindFirstChildWhichIsA("Humanoid", true)
	local folder = model:FindFirstChild("Animations") or model:FindFirstChild("AnimSaves")
	local idle = folder and folder:FindFirstChild("Idle")
	if host and idle then
		local animator = host:FindFirstChildOfClass("Animator") or Instance.new("Animator", host)
		local track = (animator :: Animator):LoadAnimation(idle :: Animation)
		track:Play(0);
		(animator :: Animator):StepAnimations(0.05)
		-- Même gel que pour le personnage : la pose Idle passe dans les C0.
		local frozen = {}
		for _, motor in model:GetDescendants() do
			if motor:IsA("Motor6D") then
				frozen[motor] = motor.Transform
			end
		end
		track:Stop(0)
		animator:Destroy()
		for motor, transform in frozen do
			motor.Transform = CFrame.identity
			motor.C0 = motor.C0 * transform
		end
	end
	return model
end

-- Cette méthode permet de tracer le rayon de la balle tel qu'en jeu (couleur, largeur, émission) lorsqu'une scène montre
-- un tir, de la bouche du canon du viewmodel au point touché.
function Promo.buildTracer(parent: Instance, from: Vector3, to: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "Tracer"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.Transparency = true, false, false, 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(from)
	anchor.Parent = parent
	local a0 = Instance.new("Attachment", anchor)
	local a1 = Instance.new("Attachment", anchor)
	a1.WorldPosition = to
	local beam = Instance.new("Beam")
	local rgb = ShotEffectRules.TRACER_RGB
	beam.Color = ColorSequence.new(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	beam.Width0, beam.Width1 = ShotEffectRules.TRACER_WIDTH, ShotEffectRules.TRACER_WIDTH
	beam.LightEmission, beam.FaceCamera, beam.Segments = 1, true, 1
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Parent = anchor
end

-- Cette méthode permet de trouver la bouche du canon d'un viewmodel (Barrel.ShootPart) lorsqu'on trace le rayon du tir,
-- et d'y faire partir la flamme de bouche du jeu (ParticleEmitter MuzzleEffect).
function Promo.muzzleOf(model: Model): Vector3?
	local barrel = model:FindFirstChild(ShotEffectRules.MUZZLE_PATH[1], true)
	local att = barrel and barrel:FindFirstChild(ShotEffectRules.MUZZLE_PATH[2])
	if att and att:IsA("Attachment") then
		local flame = att:FindFirstChild(ShotEffectRules.MUZZLE_EFFECT)
		if flame and flame:IsA("ParticleEmitter") then
			flame:Emit(ShotEffectRules.MUZZLE_EMIT_COUNT)
		end
		return att.WorldPosition
	end
	return nil
end

-- Cette méthode permet de calculer l'orientation de la caméra (lacet autour de la verticale, puis tangage) lorsqu'une
-- scène part d'une direction de base.
function Promo.aim(eye: Vector3, dir: Vector3, yaw: number, pitch: number): CFrame
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	return CFrame.lookAt(eye, eye + flat) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
end

-- Cette méthode permet de retirer la scène et de rendre la caméra de l'éditeur lorsqu'on a fini de capturer.
function Promo.clear()
	local folder = Promo.stageFolder(false)
	if folder then
		folder:Destroy()
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Fixed
	cam.FieldOfView = 70
	return "[promo] scène retirée"
end

-- Cette méthode permet de construire une scène de SHOTS (réglages remplacés par `overrides`) et de poser la caméra
-- lorsqu'on veut la capturer ; renvoie un résumé (positions) pour régler le cadrage.
function Promo.shot(name: string, overrides: { [string]: any }?)
	local spec = table.clone(assert(SHOTS[name], "[promo] scène inconnue : " .. name))
	for k, v in overrides or {} do
		spec[k] = v
	end
	local old = Promo.stageFolder(false)
	if old then
		old:Destroy()
	end
	local folder = Promo.stageFolder(true) :: Folder
	local space = Promo.buildSpace(folder)
	local cam = workspace.CurrentCamera

	-- Cette méthode permet de donner un point en l'air du décor (`a` le long, `x` de -1 crête A à 1 crête B, `y` en
	-- fraction de la hauteur des rampes) lorsqu'une caméra ou un personnage saute d'une rampe à l'autre.
	local function airPoint(p): Vector3
		return space.origin
			+ space.along * (p.a * SPACE.length / 2)
			+ space.side * (p.x * SPACE.gap)
			+ Vector3.yAxis * ((p.y - 1) * SPACE.height)
	end

	-- Personnages
	local roots, models = {}, {}
	for i, actor in spec.actors or {} do
		local root = if actor.air then airPoint(actor.air) else Promo.surferRoot(space[actor.ramp], actor.a, actor.b)
		local look = space.along
		if actor.face == "back" then
			look = -space.along
		elseif type(actor.face) == "number" then
			look = CFrame.Angles(0, math.rad(actor.face), 0):VectorToWorldSpace(space.along)
		end
		models[i] = Promo.buildSurfer(folder, root, look, actor.weapon, actor.skin)
		roots[i] = root
	end
	-- Tir en 3e personne : rayon de la bouche du canon de l'arme 3P d'un personnage vers un autre.
	if spec.shot3p then
		local muzzle = Promo.muzzleOf(models[spec.shot3p.from] :: Model)
		if muzzle then
			Promo.buildTracer(folder, muzzle, roots[spec.shot3p.to] + Vector3.new(0, 1.2, 0))
		end
	end

	-- Caméra
	local c = spec.cam
	local eye
	if c.eye then
		eye = Promo.surferRoot(space[c.eye.ramp], c.eye.a, c.eye.b) + Vector3.new(0, EYE, 0)
	else
		eye = airPoint(c.air)
	end
	local camCF
	if type(c.look) == "number" and roots[c.look] then
		camCF = CFrame.lookAt(eye, roots[c.look] + Vector3.new(0, 1, 0))
			* CFrame.Angles(0, math.rad(c.yaw or 0), 0)
			* CFrame.Angles(math.rad(c.pitch or 0), 0, 0)
	else
		camCF = Promo.aim(eye, space.along, c.yaw or 0, c.pitch or 0)
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = spec.fov or 90
	cam.CFrame = camCF

	-- Viewmodel et tir
	if spec.viewmodel then
		local vm = Promo.buildViewmodel(folder, camCF, spec.viewmodel)
		local target = spec.tracer and roots[spec.tracer]
		if target then
			local muzzle = Promo.muzzleOf(vm)
			if muzzle then
				Promo.buildTracer(folder, muzzle, target + Vector3.new(0, 1.2, 0))
			end
		end
	end

	return string.format(
		"[promo] %s : cam (%.1f, %.1f, %.1f) regard (%.2f, %.2f, %.2f), %d personnage(s), viewport %s",
		name,
		camCF.Position.X,
		camCF.Position.Y,
		camCF.Position.Z,
		camCF.LookVector.X,
		camCF.LookVector.Y,
		camCF.LookVector.Z,
		#roots,
		tostring(cam.ViewportSize)
	)
end

Promo.SHOTS = SHOTS
Promo.SPACE = SPACE
_G.Promo = Promo
return "[promo] prêt : surf, tir, ciselure, cordoue, lame"

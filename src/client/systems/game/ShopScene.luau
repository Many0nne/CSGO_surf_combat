-- Scène 3D du shop (#347, docs/ui.md « Shop ») : salle de présentation dédiée, hors de la map, construite d'après les
-- cotes de la planche validée (tools/shop/board.py, scène B, en studs). Deux plans de caméra : la vue d'ensemble, face
-- à la vitrine du mur de droite (une caisse par arme, étiquette avec nom et prix, survol en rouge d'impact), et la vue
-- détail, la caisse choisie seule sur son socle, sous la suspension (#424 : son contenu est dans la colonne de
-- l'interface, plus au mur). La caméra glisse de l'une à l'autre. Tout est local au client ; pendant le shop, la scène
-- de l'accueil est suspendue (MenuScene.setPaused) et l'ambiance du jeu est assombrie (salle fermée).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local IS_STUDIO = RunService:IsStudio()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CrateOpeningRules = require(Shared:WaitForChild("CrateOpeningRules"))
local CrateStencil = require(Shared:WaitForChild("CrateStencil"))
local GamepadRules = require(Shared:WaitForChild("GamepadRules"))
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local PerfMarkers = require(Shared:WaitForChild("PerfMarkers"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WalletRules = require(Shared:WaitForChild("WalletRules"))
local WeaponProfile = require(Shared:WaitForChild("WeaponProfile"))
local WeaponSkins = require(Shared:WaitForChild("WeaponSkins"))
local CrateOpening = require(script.Parent.CrateOpening)
local MenuScene = require(script.Parent.MenuScene)
local Rules = require(script.Parent.MenuSceneRules)

local ShopScene = {}

-- La salle est posée loin de la map et de la copie de l'accueil (MenuScene, décalée de 5 000 studs en Z)
local ORIGIN = Vector3.new(0, 600, 12000)
local VERTICAL_FOV = 40 -- comme l'accueil
local ASPECT_REF = 16 / 9
local GLIDE_TIME = 0.9 -- s du glissement entre la vitrine et le socle
-- Aperçu d'un skin (#424, ligne survolée ou retenue dans la colonne) : l'arme habillée flotte au-dessus de la caisse,
-- la caméra s'avance (sans tourner) pour qu'elle couvre PREVIEW_FILL de la largeur, centrée à PREVIEW_SCREEN_X (la
-- colonne de l'interface reste à gauche). Balancement lent de part et d'autre du profil, tant que le joueur ne la
-- tourne pas à la souris ; un tour complet montrait l'arme par la tranche, une ligne sans intérêt
-- Centre de l'arme au-dessus du dessus du socle : à 3,6, le couvercle de la caisse, éclairé de près, prenait le tiers
-- bas du gros plan ; plus haut, elle sort du cadre
local PREVIEW_HEIGHT = 4.8
local PREVIEW_GLIDE_TIME = 0.5
local PREVIEW_FILL = 0.45
local PREVIEW_SCREEN_X = 0.66
local PREVIEW_SWAY = math.rad(30)
local PREVIEW_SWAY_PERIOD = 8 -- s par aller-retour
local PREVIEW_SETTLE_RATE = 2 -- retour au balancement après un glissement (Rules.damp)
local DRAG_RATE = math.rad(0.5) -- par pixel de souris
local DRAG_PITCH = math.rad(35) -- inclinaison au plus, vers la caméra ou à l'opposé
local STICK_TURN_RATE = 2 * math.pi / 1.5 -- rad/s du stick droit à fond (#469) : un tour complet en 1,5 s
local DRAG_IDLE = 2 -- s sans glisser avant que le balancement reprenne
-- Lampe de face pendant l'aperçu : les skins métalliques reflètent la pièce sombre et ne prennent que la lumière venue
-- presque de face (#358 : sans elle, l'AWP Couchant restait presque noire en gros plan)
local PREVIEW_LIGHT_BRIGHTNESS = 1.2
local PREVIEW_LIGHT_RATE = 6 -- vitesse du fondu (Rules.damp), environ le temps du glissement
-- Ambiance de la salle fermée (Lighting.Ambient pendant le shop) : celle du crépuscule baignait toute la pièce et
-- écrasait les lampes (planche : DIZZY_AMBIENT = 0,12)
local ROOM_AMBIENT = Color3.fromRGB(24, 23, 29)
-- Lampes réglées dans Studio pour l'éclairage Future (LightingStyle Realistic, #362) : chaque SpotLight éclaire en
-- cône et peut projeter des ombres. Les intensités sont absolues (plus de gain commun : sous le Voxel, chaque lampe
-- s'étalait sur toute la pièce et toutes étaient baissées à 0,6 fois la planche)
local LIGHT_RANGE = 30
-- Suspension à l'aplomb de la caisse du socle (#424 : plus de tableau au mur, la caisse est le seul sujet ; repère :
-- centre de la suspension au sol, mêmes hauteurs que sur la planche + LAMP_LIFT). Assez basse pour rester sous les
-- onglets du menu dans la vue détail, assez haute pour sortir du cadre de l'ouverture : à -1, l'ampoule restait en
-- haut de l'image pendant l'ouverture et son éclat passait sous les onglets
local LAMP_LIFT = 0.7
local CEILING_Y = 17.75 -- dessous du plafond, dans la salle
-- Lampe de la suspension, à l'ampoule et à ombres, tournée vers le bas : sa tache couvre la caisse et le haut du socle
local SUSPENSION_ANGLE = 70
local SUSPENSION_BRIGHTNESS = 5
local SUSPENSION_RANGE = 14
-- Faisceau : Future ne dessine pas la lumière dans l'air, on simule le cône sous l'ampoule par un dégradé blanc teinté
-- (tools/shop/make_light_textures.py ; des calques translucides empilés laissaient des traits). Deux rubans Beam
-- tournés vers la caméra, un halo et un cœur pas plus larges que la cloche en haut, texture du profil en travers
-- (largeur en haut, en bas, transparence au départ de l'ampoule), court : il s'efface au-dessus de la caisse
local BEAM_TEXTURE = "rbxassetid://86578020001310" -- beam_profile.png (Decal 123228552734348)
local BEAM_COLOR = Color3.fromRGB(255, 222, 176)
local BEAM_LENGTH = 1.6 -- depuis l'ampoule
local BEAM_LAYERS = { { 2.0, 3.6, 0.5 }, { 1.2, 2.2, 0.6 } }

-- Couleurs de la planche
local BONE = UITheme.Colors.Bone
local AMBER = Color3.fromRGB(242, 169, 0)
local GLOW = Color3.fromRGB(215, 85, 20) -- liseré lumineux du socle : l'ambre de l'interface sort jaune vif en Neon
local HIT_RED = UITheme.Colors.HitRed
local INK = UITheme.Colors.Ground
local WOOD = Color3.fromRGB(128, 94, 64)
local WOOD_LIGHT = Color3.fromRGB(150, 112, 76)
local STEEL_DARK = Color3.fromRGB(70, 74, 80)

-- Caisse d'armes en bois (#332, tools/shop/crate_model.py) : une MeshPart par matière, couvercle en « Lid* » pour
-- l'ouverture ; couleur et matière posées ici, la bande LidStripe prend la couleur de la collection
local CRATE = ReplicatedStorage:WaitForChild("Props"):WaitForChild("Crate") :: Model
local CRATE_WIDTH = 4.0 -- largeur du modèle, en studs
-- largeur des caisses rangées (vitrine, racks) : poignées en corde comprises, elles tiennent dans 3,7 studs (pas de 4,3)
local SHELF_CRATE_WIDTH = 3.4
local CRATE_PLANKS = { Color3.fromRGB(150, 104, 62), Enum.Material.Wood }
local CRATE_FRAME = { Color3.fromRGB(128, 90, 56), Enum.Material.Wood }
local CRATE_STEEL = { Color3.fromRGB(62, 64, 68), Enum.Material.Metal }
local CRATE_LOOK: { [string]: { any } } = {
	Interior = { Color3.fromRGB(34, 26, 18), Enum.Material.SmoothPlastic },
	BodyPlanks = CRATE_PLANKS,
	LidPlanks = CRATE_PLANKS,
	BodyFrame = CRATE_FRAME,
	LidFrame = CRATE_FRAME,
	BodySteel = CRATE_STEEL,
	LidSteel = CRATE_STEEL,
	Rope = { Color3.fromRGB(176, 156, 116), Enum.Material.Fabric },
	LidStripe = { Color3.fromRGB(226, 58, 40), Enum.Material.SmoothPlastic },
}
-- Pochoir du couvercle (#434) : texte propre à la caisse (ShopCatalog.stencil), peint par une SurfaceGui sur une pièce
-- invisible « LidStencil » (préfixe Lid : il s'ouvre avec le couvercle) ; hauteur des capitales et encre de l'ancien
-- pochoir « S1-0332 » modelé dans le mesh. Place et taille : CrateStencil (#456), source unique relue par le générateur
-- de la caisse et par verify_place
local STENCIL_AT = Vector3.new(table.unpack(CrateStencil.AT)) -- centre, par rapport au pivot de la caisse
local STENCIL_SIZE = Vector3.new(table.unpack(CrateStencil.SIZE))
local STENCIL_INK = Color3.fromRGB(24, 22, 20)
local STENCIL_PIXELS = 200 -- pixels par stud
local STENCIL_TEXT = 52 -- px : capitales d'Oswald à la hauteur de l'ancien pochoir (comparé dans Studio, même cadrage)

-- Vitrine (repère local : x le long de la vitrine, y en haut, z vers la pièce)
local VITRINE_W, VITRINE_H, VITRINE_D = 13.2, 8.4, 3.0
local VITRINE_LEVELS = { 4.95, 1.45 } -- rangée 1 (hauteur d'œil) puis rangée 2
local SLOT = 4.3
local TAG_SIZE = Vector2.new(3.4, 0.62)
local TAG_PIXELS = 100 -- pixels par stud du texte des étiquettes

-- Arme révélée par une ouverture : viewmodel et longueur de profil (studs), par id d'arme
local REVEAL_WEAPONS = {
	["weapon.awp"] = { viewmodel = "AWP", length = 4.4 },
	["weapon.m9bayonet"] = { viewmodel = "M9Bayonet", length = 2.7 },
}

type Frame = CFrame
type SaleCrate = { model: Model, tag: BasePart, name: TextLabel, price: TextLabel }

local room = CFrame.new(ORIGIN)
local vitrineFrame = room * CFrame.new(14.2, 0, 7.3) * CFrame.Angles(0, math.rad(-90), 0)
local lampFrame = room * CFrame.new(0, LAMP_LIFT, 0) -- à l'aplomb de la caisse du socle
local podiumFrame = room * CFrame.new(0, 1.34, 0) * CFrame.Angles(0, math.rad(-14), 0) -- caisse sur le socle
local previewCenter = room * CFrame.new(0, 1.34 + PREVIEW_HEIGHT, 0) -- arme de l'aperçu, de profil face à la caméra
-- Ouverture (#332) : la caméra avance vers la caisse (×1,8, la référence Apex avance de ×2,5) ; décalée, pas tournée,
-- pour poser la caisse et l'arme au tiers droit (colonne de l'interface à gauche), de la caisse à l'arme au-dessus
local CAMERAS = {
	detail = CFrame.lookAt(room * Vector3.new(4, 5.2, 20), room * Vector3.new(-4.5, 4.5, 0)),
	overview = CFrame.lookAt(vitrineFrame * Vector3.new(-2.8, 5.2, 17), vitrineFrame * Vector3.new(-2.8, 3.6, 0)),
	opening = CFrame.lookAt(room * Vector3.new(-2.4, 4.9, 13), room * Vector3.new(-2.4, 3.3, 0)),
}
local OPENING_SHAKE = 0.04 -- secousse de la caméra à pleine charge, en studs
-- Part de l'éclairage de la salle gardée pendant l'ouverture : salle éclairée, le décor concurrençait l'arme révélée
-- (la référence se joue sur fond sombre, la lumière vient de l'objet)
local OPENING_ROOM_LIGHT = 0.15
local roomLights: { [SpotLight]: number } = {} -- intensité d'origine des lampes de la salle, pendant l'ouverture

local stage: Folder?
local podium: Folder? -- caisse du socle, refaite à chaque caisse montrée
local sale: { SaleCrate } = {}
local vitrineLights: { SpotLight } = {} -- allumées dans la vue d'ensemble seulement
local detailLights: { SpotLight } = {} -- allumées dans la vue détail seulement
local running = false
local connection: RBXScriptConnection?
local inputConnection: RBXScriptConnection?
local mode: "overview" | "detail" | "opening" = "overview"
local podiumCrate: Model?
-- Ouverture en cours (#332) : effets, rareté tirée, départ (os.clock), rappels de l'interface
type Opening = {
	fx: any,
	rarity: string,
	start: number,
	revealed: boolean,
	onRevealed: () -> (),
	onFinished: () -> (),
}
local opening: Opening?
local shownCrate = 0
local hovered = 0
local glideFrom = CAMERAS.overview
local glideStart = -math.huge
local glideTime = GLIDE_TIME
local aimX, aimY = 0, 0
local savedAmbient: Color3?
local savedFov = 70
local onCrateClicked: ((number) -> ())?
local interactive = true -- survol et clic de la vitrine (coupés sous la fenêtre des packs, #395)
-- Aperçu d'un skin (#424) : arme montrée, pivot d'origine (profil), longueur ; orientation et glissement à la souris
type Preview = { skin: string, model: Model, base: CFrame, length: number }
local preview: Preview?
local previewLight: SpotLight?
local yaw, pitch = 0, 0
local swayClock = 0
local dragging = false
local dragFrom = Vector2.zero
local dragInput: InputObject? -- toucher qui tient le glisser en cours (nil : souris)
local stickPos = Vector2.zero -- stick droit (#469), x à droite, y vers le haut
local stickSpun = false -- le stick a tourné l'arme depuis son dernier retour au repos
local lastDrag = -math.huge
local dragConnections: { RBXScriptConnection } = {}

-- Cette méthode permet de poser une pièce ancrée sans collision dans un repère (centre local, taille) lorsque la salle
-- ou un prop est construit ; `shape` Cylinder couché sur l'axe Y du repère si `upright`.
local function box(
	parent: Instance,
	frame: Frame,
	position: Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	upright: boolean?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = shape or Enum.PartType.Block
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	local cf = frame * CFrame.new(position)
	if upright then -- l'axe des cylindres Roblox est X : on le dresse sur Y
		cf *= CFrame.Angles(0, 0, math.pi / 2)
		size = Vector3.new(size.Y, size.X, size.Z)
	end
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
	return part
end

-- Cette méthode permet de poser une caisse d'armes (modèle `Props.Crate`, origine au centre du dessous, face avant vers
-- +z) aux couleurs d'une collection lorsque la vitrine, un rack ou le socle se construit ; `width` l'étire en largeur,
-- sans `stripe` la caisse n'a pas de bande (stock sans marque), sans `stencil` pas de pochoir.
local function crate(parent: Instance, frame: Frame, stripe: Color3?, width: number?, stencil: string?): Model
	local model = CRATE:Clone()
	local pivot = CRATE:GetPivot()
	if stencil and stencil ~= "" then
		local plate = Instance.new("Part")
		plate.Name = "LidStencil"
		plate.Transparency = 1
		plate.CastShadow = false
		plate.Size = STENCIL_SIZE
		plate.CFrame = pivot * CFrame.new(STENCIL_AT)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back -- +z : face avant de la caisse
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = STENCIL_PIXELS
		gui.LightInfluence = 1 -- peinture : éclairée comme le bois
		gui.Parent = plate
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.FontFace = UITheme.Fonts.Display
		-- Taille du pochoir d'origine, réduite pour un texte trop long (arme sans nom court) au lieu d'être coupé
		text.TextScaled = true
		local maxSize = Instance.new("UITextSizeConstraint")
		maxSize.MaxTextSize = STENCIL_TEXT
		maxSize.Parent = text
		text.TextColor3 = STENCIL_INK
		text.Text = stencil
		text.Parent = gui
		plate.Parent = model
	end
	local k = (width or CRATE_WIDTH) / CRATE_WIDTH
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local look = CRATE_LOOK[part.Name]
			if look then
				part.Color, part.Material = look[1], look[2]
			end
			if part.Name == "LidStripe" then
				if stripe then
					part.Color = stripe
				else
					part:Destroy()
					continue
				end
			end
			local rel = pivot:ToObjectSpace(part.CFrame)
			part.Size = Vector3.new(part.Size.X * k, part.Size.Y, part.Size.Z)
			part.CFrame = frame * CFrame.new(rel.X * k, rel.Y, rel.Z) * rel.Rotation
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.WorldPivot = frame
	model.Parent = parent
	return model
end

-- Cette méthode permet de construire un rack de stockage (montants, plateaux d'acier larmé, longerons ambrés) lorsque la
-- salle se construit.
local function rack(parent: Instance, frame: Frame, width: number)
	local D, H = 3.0, 8.2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				parent,
				frame,
				Vector3.new(sx * (width / 2 - 0.15), H / 2, sz * (D / 2 - 0.15)),
				Vector3.new(0.3, H, 0.3),
				STEEL_DARK,
				Enum.Material.Metal
			)
		end
	end
	for _, y in { 0.25, 2.95, 5.65 } do
		box(
			parent,
			frame,
			Vector3.new(0, y, 0),
			Vector3.new(width, 0.16, D),
			Color3.fromRGB(88, 92, 98),
			Enum.Material.DiamondPlate
		)
		box(
			parent,
			frame,
			Vector3.new(0, y + 0.02, D / 2 - 0.08),
			Vector3.new(width, 0.3, 0.12),
			AMBER,
			Enum.Material.Metal
		)
	end
	box(parent, frame, Vector3.new(0, H - 0.1, 0), Vector3.new(width, 0.2, D), STEEL_DARK, Enum.Material.Metal)
end

-- Cette méthode permet de garnir un rack de stockage de six caisses (deux par plateau) aux couleurs données lorsque la
-- salle se construit.
local function fillRack(parent: Instance, frame: Frame, colors: { { number } }, twist: number)
	for level, y in { 0.33, 3.03, 5.73 } do
		for k, x in { -2.05, 2.05 } do
			local c = colors[(level - 1) * 2 + k]
			crate(
				parent,
				frame * CFrame.new(x, y, 0.05) * CFrame.Angles(0, math.rad((x * twist) % 5 - 2.5), 0),
				Color3.fromRGB(c[1], c[2], c[3]),
				SHELF_CRATE_WIDTH
			)
		end
	end
end

-- Cette méthode permet de poser un projecteur (SpotLight sur une pièce invisible) lorsque la salle s'éclaire ; portée
-- `range` (LIGHT_RANGE par défaut), ombres projetées si `shadows`.
local function spot(
	parent: Instance,
	position: Vector3,
	direction: Vector3,
	angle: number,
	brightness: number,
	color: Color3,
	range: number?,
	shadows: boolean?
): SpotLight
	local holder = Instance.new("Part")
	holder.Name = "Lamp"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.lookAt(position, position + direction)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = angle
	light.Range = range or LIGHT_RANGE
	light.Brightness = brightness
	light.Color = color
	light.Shadows = shadows == true
	light.Parent = holder
	holder.Parent = parent
	return light
end

-- Cette méthode permet de rendre visible la lumière de la suspension dans l'air (cône court sous l'ampoule) lorsque la
-- salle s'éclaire ; le moteur ne dessine que la tache sur le mur.
local function lightBeam(parent: Instance)
	local holder = Instance.new("Part")
	holder.Name = "LampBeam"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = lampFrame * CFrame.new(0, 9.3, 0)
	local top = Instance.new("Attachment")
	top.Parent = holder
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -BEAM_LENGTH, 0)
	bottom.Parent = holder
	for _, layer in BEAM_LAYERS do
		local beam = Instance.new("Beam")
		beam.Attachment0 = top
		beam.Attachment1 = bottom
		beam.Width0 = layer[1]
		beam.Width1 = layer[2]
		beam.Texture = BEAM_TEXTURE
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.Color = ColorSequence.new(BEAM_COLOR)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, layer[3]),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 8
		beam.Parent = holder
	end
	holder.Parent = parent
end

-- Cette méthode permet de construire la pièce (sol, murs en tôle, plafond, poutres), le socle et la suspension lorsque
-- le shop s'ouvre pour la première fois. Salle fermée : murs et plafond prolongés derrière la caméra de la vue détail.
local function buildRoom(parent: Instance)
	local metal = Enum.Material.Metal
	box(
		parent,
		room,
		Vector3.new(0, -0.5, 4),
		Vector3.new(40, 1, 48),
		Color3.fromRGB(58, 56, 54),
		Enum.Material.Concrete
	)
	for i = -9, 9 do -- joints du sol
		box(parent, room, Vector3.new(i * 2, 0.005, 4), Vector3.new(0.06, 0.02, 48), Color3.fromRGB(40, 39, 38))
	end
	-- mur du fond en tôle nervurée, bande basse ocre
	box(parent, room, Vector3.new(0, 9, -9), Vector3.new(40, 18, 0.5), Color3.fromRGB(150, 154, 156), metal)
	for i = -25, 25 do
		box(
			parent,
			room,
			Vector3.new(i * 0.8, 9, -8.7),
			Vector3.new(0.25, 18, 0.25),
			Color3.fromRGB(172, 176, 178),
			metal
		)
	end
	box(parent, room, Vector3.new(0, 1.6, -8.55), Vector3.new(40, 3.2, 0.12), Color3.fromRGB(200, 156, 72), metal)
	for _, sx in { -1, 1 } do -- murs latéraux
		box(parent, room, Vector3.new(sx * 16, 9, 7), Vector3.new(0.5, 18, 34), Color3.fromRGB(128, 132, 134), metal)
	end
	for i = -12, 29 do -- nervures du mur de droite, derrière la vitrine
		box(
			parent,
			room,
			Vector3.new(15.7, 9, i * 0.8),
			Vector3.new(0.25, 18, 0.25),
			Color3.fromRGB(150, 154, 156),
			metal
		)
	end
	box(parent, room, Vector3.new(0, 9, 24.25), Vector3.new(40, 18, 0.5), Color3.fromRGB(128, 132, 134), metal) -- devant
	box(parent, room, Vector3.new(0, 18, 7), Vector3.new(40, 0.5, 34), Color3.fromRGB(40, 42, 46), metal)
	for _, x in { -8, 0, 8 } do -- poutres du plafond
		box(parent, room, Vector3.new(x, 17, 7), Vector3.new(0.8, 1.2, 34), WOOD, Enum.Material.WoodPlanks)
	end
	-- socle : plateau d'acier sur deux palettes, liseré ambre
	for _, y in { 0.25, 0.85 } do
		for _, z in { -1.6, 0, 1.6 } do
			box(
				parent,
				room,
				Vector3.new(0, y + 0.1, z),
				Vector3.new(5.2, 0.2, 0.9),
				WOOD_LIGHT,
				Enum.Material.WoodPlanks
			)
		end
		for _, x in { -2.2, 0, 2.2 } do
			box(parent, room, Vector3.new(x, y - 0.12, 0), Vector3.new(0.6, 0.26, 4.2), WOOD, Enum.Material.WoodPlanks)
		end
	end
	box(parent, room, Vector3.new(0, 1.25, 0), Vector3.new(5.4, 0.18, 4.4), STEEL_DARK, Enum.Material.DiamondPlate)
	box(parent, room, Vector3.new(0, 1.25, 2.21), Vector3.new(5.4, 0.2, 0.04), AMBER, metal)
	-- liseré lumineux au sol autour du socle (plateau de jeu télévisé)
	for _, sx in { -1, 1 } do
		box(parent, room, Vector3.new(sx * 4, 0.03, 0), Vector3.new(0.14, 0.04, 7), GLOW, Enum.Material.Neon)
		box(parent, room, Vector3.new(0, 0.03, sx * 3.5), Vector3.new(8.14, 0.04, 0.14), GLOW, Enum.Material.Neon)
	end
	-- racks de stock : contre le mur du fond à droite, et contre le mur de gauche (pénombre sous l'interface)
	local backRack = room * CFrame.new(9.8, 0, -6.9)
	rack(parent, backRack, 8.4)
	fillRack(
		parent,
		backRack,
		{ { 40, 150, 160 }, { 150, 70, 170 }, { 190, 140, 60 }, { 226, 58, 40 }, { 90, 120, 200 }, { 40, 150, 160 } },
		1.7
	)
	local leftRack = room * CFrame.new(-14.3, 0, -2.6) * CFrame.Angles(0, math.rad(90), 0)
	rack(parent, leftRack, 8.4)
	fillRack(
		parent,
		leftRack,
		{ { 226, 58, 40 }, { 90, 120, 200 }, { 40, 150, 160 }, { 190, 140, 60 }, { 150, 70, 170 }, { 226, 58, 40 } },
		1.3
	)
	-- suspension industrielle au-dessus de la caisse : câble (jusqu'au plafond), douille, cloche émaillée, ampoule
	local enamel = Color3.fromRGB(52, 58, 54)
	local cyl = Enum.PartType.Cylinder
	local cableTop = CEILING_Y - LAMP_LIFT
	box(
		parent,
		lampFrame,
		Vector3.new(0, (cableTop + 10.35) / 2, 0),
		Vector3.new(0.06, cableTop - 10.35, 0.06),
		Color3.fromRGB(20, 20, 20)
	)
	box(
		parent,
		lampFrame,
		Vector3.new(0, 10.15, 0),
		Vector3.new(0.45, 0.4, 0.45),
		Color3.fromRGB(30, 32, 34),
		metal,
		cyl,
		true
	)
	box(parent, lampFrame, Vector3.new(0, 9.85, 0), Vector3.new(1, 0.3, 1), enamel, metal, cyl, true)
	box(parent, lampFrame, Vector3.new(0, 9.6, 0), Vector3.new(1.9, 0.25, 1.9), enamel, metal, cyl, true)
	box(parent, lampFrame, Vector3.new(0, 9.42, 0), Vector3.new(2.4, 0.14, 2.4), enamel, metal, cyl, true)
	box(parent, lampFrame, Vector3.new(0, 9.36, 0), Vector3.new(2.2, 0.04, 2.2), BONE, nil, cyl, true)
	local bulb = box(
		parent,
		lampFrame,
		Vector3.new(0, 9.3, 0),
		Vector3.new(0.6, 0.6, 0.6),
		Color3.fromRGB(255, 241, 224),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	bulb.CastShadow = false -- la lampe à ombres est en son centre : sinon l'ampoule masquerait toute sa lumière
end

-- Cette méthode permet d'éclairer la salle (suspension sur la caisse, rack de droite, appoint de face) et de poser les
-- deux lampes de la vitrine, allumées dans la vue d'ensemble seulement, lorsque la salle se construit.
local function buildLights(parent: Instance)
	local function at(v: Vector3): Vector3
		return room * v
	end
	local function dir(v: Vector3): Vector3
		return room:VectorToWorldSpace(v.Unit)
	end
	-- Suspension, à l'ampoule, tournée vers la caisse
	local bulb = lampFrame * Vector3.new(0, 9.3, 0)
	spot(
		parent,
		bulb,
		dir(Vector3.new(0, -1, 0)),
		SUSPENSION_ANGLE,
		SUSPENSION_BRIGHTNESS,
		Color3.fromRGB(255, 228, 190),
		SUSPENSION_RANGE,
		true
	)
	lightBeam(parent)
	-- Lampe de face de l'aperçu d'un skin, un peu au-dessus de l'arme : éteinte (intensité 0) hors aperçu
	local previewFrom = previewCenter * Vector3.new(0, 1.5, 6)
	previewLight =
		spot(parent, previewFrom, previewCenter.Position - previewFrom, 40, 0, Color3.fromRGB(255, 228, 190), 14)
	-- Rack du fond, lumière froide d'en haut vers le milieu du rack (plus bas et plus rasante, elle brûlait le bord d'un
	-- plateau d'acier) ; éteinte face à la vitrine, où ce rack passe sous le texte
	local coldFrom = Vector3.new(8.5, 10, 3)
	local cold = spot(
		parent,
		at(coldFrom),
		dir(Vector3.new(9.8, 3, -6.9) - coldFrom),
		50,
		0.8,
		Color3.fromRGB(200, 214, 255),
		20
	)
	table.insert(detailLights, cold)
	-- Appoint de face sur la caisse du socle, cône serré et portée courte : plus ouvert, il éclairait aussi le mur du
	-- fond et effaçait la tache de la suspension (pour la même raison, plus d'appoint au plafond)
	for _, sx in { -1, 1 } do
		local from = Vector3.new(sx * 6.5, 4.3, 3.5)
		spot(parent, at(from), dir(Vector3.new(0, 2.5, 0) - from), 35, 1.4, Color3.fromRGB(255, 220, 170), 11)
	end
	for _, sx in { -1, 1 } do
		local from = vitrineFrame * Vector3.new(sx * 4.3, 15.5, 5.5)
		local to = vitrineFrame * Vector3.new(sx * 3.6, 2.6, 0.5)
		-- Portée courte : à 30 studs, elles éclairaient aussi le rack du fond, sous le texte de la vue d'ensemble. Ombres :
		-- l'étage du haut ombre celui du bas, comme sur la planche
		table.insert(vitrineLights, spot(parent, from, to - from, 60, 1.3, Color3.fromRGB(255, 226, 186), 22, true))
	end
end

-- Cette méthode permet d'écrire le nom et le prix d'une caisse sur son étiquette (SurfaceGui sur la face tournée vers la
-- pièce) lorsque la vitrine se construit ; le prix est le jeton du crédit suivi du montant (#391 : le mot CRÉDITS ne
-- tiendrait plus à côté du jeton sur 3,4 studs).
local function tagText(tag: BasePart, crateDef: ShopCatalog.Crate): (TextLabel, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z du repère de la vitrine : vers la pièce
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = TAG_PIXELS
	gui.LightInfluence = 0.5 -- texte un peu moins assombri que l'étiquette : à 1, l'os sur rouge restait terne
	gui.Parent = tag
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	-- Tri par LayoutOrder : celui par défaut d'Instance.new est le nom, qui mettait le cadre « Price » avant le nom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 22)
	layout.Parent = row
	local function label(text: string, font: Font, size: number, order: number, parent: Instance): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromScale(0, 1)
		t.FontFace = font
		t.TextSize = size
		t.TextColor3 = INK
		t.Text = text
		t.LayoutOrder = order
		t.Parent = parent
		return t
	end
	local name = label(crateDef.name, UITheme.Fonts.Display, 36, 1, row)
	-- Prix : jeton collé au montant, dans son propre cadre (l'écart de 22 px sépare le nom du prix)
	local priceGroup = Instance.new("Frame")
	priceGroup.Name = "Price"
	priceGroup.BackgroundTransparency = 1
	priceGroup.AutomaticSize = Enum.AutomaticSize.X
	priceGroup.Size = UDim2.fromScale(0, 1)
	priceGroup.LayoutOrder = 2
	priceGroup.Parent = row
	local priceLayout = Instance.new("UIListLayout")
	priceLayout.FillDirection = Enum.FillDirection.Horizontal
	priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	priceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	priceLayout.Padding = UDim.new(0, 6)
	priceLayout.Parent = priceGroup
	local coin = Instance.new("ImageLabel")
	coin.Name = "Credit"
	coin.BackgroundTransparency = 1
	coin.Size = UDim2.fromOffset(32, 32)
	coin.Image = WalletRules.ICON
	coin.LayoutOrder = 1
	coin.Parent = priceGroup
	local price = label(ShopCatalog.priceLabel(crateDef), UITheme.Fonts.DisplayText, 30, 2, priceGroup)
	return name, price
end

-- Cette méthode permet de construire la vitrine (rack à deux étages), d'y ranger les caisses en vente avec leur
-- étiquette, et de garnir l'étage vide de caisses sans marque, lorsque la salle se construit.
local function buildVitrine(parent: Instance)
	local f = vitrineFrame
	local metal = Enum.Material.Metal
	for _, sx in { -1, 0, 1 } do
		for _, sz in { -1, 1 } do
			if sx ~= 0 or sz < 0 then -- montant central à l'arrière seulement, pour ne pas couper la rangée de face
				local post = Vector3.new(sx * (VITRINE_W / 2 - 0.15), VITRINE_H / 2, sz * (VITRINE_D / 2 - 0.15))
				box(parent, f, post, Vector3.new(0.3, VITRINE_H, 0.3), STEEL_DARK, metal)
			end
		end
	end
	for _, y in VITRINE_LEVELS do
		box(
			parent,
			f,
			Vector3.new(0, y, 0),
			Vector3.new(VITRINE_W, 0.16, VITRINE_D),
			Color3.fromRGB(88, 92, 98),
			Enum.Material.DiamondPlate
		)
		box(parent, f, Vector3.new(0, y + 0.02, VITRINE_D / 2 - 0.08), Vector3.new(VITRINE_W, 0.3, 0.12), AMBER, metal)
	end
	box(parent, f, Vector3.new(0, VITRINE_H - 0.1, 0), Vector3.new(VITRINE_W, 0.2, VITRINE_D), STEEL_DARK, metal)
	for _, slot in ShopCatalog.slots(#ShopCatalog.CRATES) do
		local def = ShopCatalog.CRATES[slot.index]
		local level = VITRINE_LEVELS[slot.row]
		local x = slot.column * SLOT
		local twist = ((slot.index * 7) % 5) - 2
		local stripe = Color3.fromRGB(def.stripe[1], def.stripe[2], def.stripe[3])
		local model = crate(
			parent,
			f * CFrame.new(x, level + 0.08, -0.1) * CFrame.Angles(0, math.rad(twist), 0),
			stripe,
			SHELF_CRATE_WIDTH,
			ShopCatalog.stencil(def)
		)
		local tag = box(
			model,
			f,
			Vector3.new(x, level - 0.12, VITRINE_D / 2 + 0.03),
			Vector3.new(TAG_SIZE.X, TAG_SIZE.Y, 0.05),
			BONE
		)
		tag.Name = "Tag"
		model.Name = def.id
		model:SetAttribute("ShopCrate", slot.index)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				-- survol et clic par rayon depuis la souris ; pas la plaque invisible du pochoir, juste devant le bois
				part.CanQuery = part.Name ~= "LidStencil"
			end
		end
		local name, price = tagText(tag, def)
		sale[slot.index] = { model = model, tag = tag, name = name, price = price }
	end
	for _, row in ShopCatalog.emptyRows(#ShopCatalog.CRATES) do
		for k = -1, 1 do
			local x = k * SLOT
			crate(
				parent,
				f
					* CFrame.new(x, VITRINE_LEVELS[row] + 0.08, -0.15)
					* CFrame.Angles(0, math.rad((x * 0.4) % 3 - 1.5), 0),
				nil,
				SHELF_CRATE_WIDTH
			)
		end
	end
end

-- Cette méthode permet de construire une arme de profil (pièces de son viewmodel, bras exclus, habillées du skin) de
-- `length` studs, centrée en `at`, projetant son ombre si `castShadow`, lorsqu'une ouverture révèle un skin ; nil si le
-- viewmodel manque.
local function revealWeapon(
	parent: Instance,
	viewmodelName: string,
	skinId: string,
	at: CFrame,
	length: number,
	castShadow: boolean
): Model?
	local viewModels = ReplicatedStorage:FindFirstChild("ViewModels")
	local source = viewModels and viewModels:FindFirstChild(viewmodelName)
	if not source then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = skinId
	for _, part in source:GetChildren() do
		if part:IsA("MeshPart") and part.Transparency < 1 then
			local copy = part:Clone()
			for _, child in copy:GetChildren() do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = castShadow -- explicite : les viewmodels diffèrent (celui du M9 n'en projette pas)
			copy.Parent = model
		end
	end
	if #model:GetChildren() == 0 then
		model:Destroy()
		return nil
	end
	WeaponSkins.apply(model, viewmodelName, skinId)
	-- Profil commun avec les vignettes (WeaponProfile, #429) : pointe vers le +X de `at`, face montrée vers son +Z
	local profile, frame, extents = WeaponProfile.of(model, viewmodelName)
	-- Pivot au centre de la boîte : celui d'un Model créé par script est à l'origine, ScaleTo y emmènerait l'arme
	model.WorldPivot = frame
	model:PivotTo(at * profile:Inverse() * frame)
	model:ScaleTo(length / extents.X)
	model.Parent = parent
	return model
end

-- Cette méthode permet de changer le skin montré en aperçu (#424, nil : aucun) lorsque l'interface le demande ou que la
-- vue change : l'arme habillée remplace la précédente au-dessus de la caisse, la caméra glisse vers elle ou en revient.
local function setPreview(skinId: string?)
	local shown = preview
	if (if shown then shown.skin else nil) == skinId then
		return
	end
	if shown then
		shown.model:Destroy()
		preview = nil
	end
	local item = if skinId and stage and mode == "detail" and not opening then InventoryRules.item(skinId) else nil
	local weapon = if item and item.weapon then REVEAL_WEAPONS[item.weapon] else nil
	if skinId and weapon and stage then
		local model = revealWeapon(stage, weapon.viewmodel, skinId, previewCenter, weapon.length, true)
		if model then
			model.Name = "SkinPreview"
			preview = { skin = skinId, model = model, base = model:GetPivot(), length = weapon.length }
			-- D'un skin à l'autre, l'arme garde son orientation ; un nouvel aperçu repart du profil
			if not shown then
				yaw, pitch, swayClock = 0, 0, 0
			end
		end
	end
	if running and (shown ~= nil) ~= (preview ~= nil) then
		glideFrom = workspace.CurrentCamera.CFrame
		glideStart = os.clock()
		glideTime = PREVIEW_GLIDE_TIME
	end
	if not preview then
		dragging = false
		dragInput = nil
	end
end

-- Cette méthode permet de tourner l'arme de l'aperçu (balancement lent, ou orientation donnée à la souris) et d'allumer
-- en fondu sa lampe de face lorsqu'une image est rendue.
local function updatePreview(dt: number)
	local shown = preview
	if shown then
		-- Stick droit : tourne l'arme en détail, la main reste au stick tant qu'il est incliné (pas de balancement)
		if mode == "detail" and interactive and not dragging then
			local rx, ry = GamepadRules.lookRate(stickPos.X, stickPos.Y)
			if rx ~= 0 or ry ~= 0 then
				-- dt borné : une image longue (premier affichage) ne fait pas sauter l'arme
				yaw, pitch = Rules.stickSpin(yaw, pitch, rx, ry, math.min(dt, 0.1), STICK_TURN_RATE, DRAG_PITCH)
				lastDrag = os.clock()
				stickSpun = true
			elseif stickSpun then
				-- Stick relâché : ramené à un demi-tour près, comme au relâchement de la souris
				stickSpun = false
				yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
			end
		end
		if not dragging and os.clock() - lastDrag > DRAG_IDLE then
			swayClock += dt
			local sway = PREVIEW_SWAY * math.sin(swayClock * 2 * math.pi / PREVIEW_SWAY_PERIOD)
			yaw = Rules.damp(yaw, sway, dt, PREVIEW_SETTLE_RATE)
			pitch = Rules.damp(pitch, 0, dt, PREVIEW_SETTLE_RATE)
		end
		local center = CFrame.new(previewCenter.Position)
		shown.model:PivotTo(center * CFrame.Angles(pitch, yaw, 0) * center:Inverse() * shown.base)
	end
	if previewLight then
		local target = if shown and mode == "detail" then PREVIEW_LIGHT_BRIGHTNESS else 0
		previewLight.Brightness = Rules.damp(previewLight.Brightness, target, dt, PREVIEW_LIGHT_RATE)
	end
end

-- Cette méthode permet de montrer une caisse dans la vue détail (sa caisse seule sur le socle, sous la suspension)
-- lorsque le joueur la choisit ; son contenu est dans la colonne de l'interface (#424).
local function dressCrate(index: number)
	local def = ShopCatalog.CRATES[index]
	if not (def and stage) then
		return
	end
	setPreview(nil)
	if podium then
		podium:Destroy()
	end
	local podiumFolder = Instance.new("Folder")
	podiumFolder.Name = "Podium"
	local stripe = Color3.fromRGB(def.stripe[1], def.stripe[2], def.stripe[3])
	podiumCrate = crate(podiumFolder, podiumFrame, stripe, nil, ShopCatalog.stencil(def))
	podiumFolder.Parent = stage
	podium = podiumFolder
end

-- Cette méthode permet de construire la salle une seule fois (pièce, lumières, vitrine) lorsque le shop s'ouvre pour la
-- première fois.
local function build()
	local folder = Instance.new("Folder")
	folder.Name = "ShopStage"
	buildRoom(folder)
	buildLights(folder)
	buildVitrine(folder)
	stage = folder
end

-- Cette méthode permet de peindre les étiquettes de la vitrine (survolée en rouge d'impact à texte os) lorsque le survol
-- change.
local function paintTags()
	for index, entry in sale do
		local hot = index == hovered
		entry.tag.Color = if hot then HIT_RED else BONE
		entry.name.TextColor3 = if hot then BONE else INK
		entry.price.TextColor3 = if hot then BONE else INK
	end
end

-- Cette méthode permet de trouver la caisse en vente sous la souris (rayon depuis la caméra) lorsque la vue d'ensemble
-- est affichée ; 0 si aucune.
local function crateUnderMouse(camera: Camera): number
	if mode ~= "overview" or not stage or not interactive then
		return 0
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local models = {}
	for _, entry in sale do
		table.insert(models, entry.model)
	end
	params.FilterDescendantsInstances = models
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
	local index = model and model:GetAttribute("ShopCrate")
	return if type(index) == "number" then index else 0
end

-- Cette méthode permet de donner le plan visé par la caméra (vitrine, socle, ouverture, ou gros plan de face de l'arme
-- de l'aperçu, décalée à droite) lorsqu'une image est rendue ; `aspect` (au moins 16:9) règle le recul du gros plan.
local function targetFrame(aspect: number): CFrame
	local shown = preview
	if mode == "detail" and shown then
		local distance, offset = Rules.closeUp(shown.length, VERTICAL_FOV, aspect, PREVIEW_FILL, PREVIEW_SCREEN_X)
		return previewCenter * CFrame.new(-offset, 0, distance)
	end
	return CAMERAS[mode]
end

-- Cette méthode permet de placer la caméra (glissement entre les plans, léger suivi du curseur, FOV adapté au format),
-- de tourner l'aperçu d'un skin et de suivre le survol des étiquettes de la vitrine lorsqu'une image est rendue.
local function update(dt: number)
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local mouse = UserInputService:GetMouseLocation()
	local aspect = ASPECT_REF
	if viewport.X > 0 and viewport.Y > 0 then
		aimX = Rules.damp(aimX, (mouse.X / viewport.X - 0.5) * 2, dt, 4)
		aimY = Rules.damp(aimY, (mouse.Y / viewport.Y - 0.5) * 2, dt, 4)
		camera.FieldOfView = Rules.fitFov(VERTICAL_FOV, ASPECT_REF, viewport.X / viewport.Y)
		aspect = math.max(ASPECT_REF, viewport.X / viewport.Y)
	end
	updatePreview(dt)
	local t = math.clamp((os.clock() - glideStart) / glideTime, 0, 1)
	local eased = t * t * (3 - 2 * t)
	local angles = Rules.aimAngles(aimX, aimY)
	local shake = CFrame.identity
	local current = opening
	if current then
		local elapsed = os.clock() - current.start
		-- Studio : temps figé par l'attribut DebugCrateOpeningTime (poses à comparer à la référence, docs/ui.md)
		local frozen = if IS_STUDIO then Players.LocalPlayer:GetAttribute("DebugCrateOpeningTime") else nil
		if type(frozen) == "number" then
			elapsed = frozen
			current.start = os.clock() - frozen
			current.fx:jump(frozen)
		end
		local state = CrateOpeningRules.sample(elapsed, current.rarity)
		current.fx:update(state, elapsed)
		for light, base in roomLights do
			light.Brightness = base * (1 - (1 - OPENING_ROOM_LIGHT) * state.push)
		end
		eased = state.push -- la caméra suit la chronologie (temps figé, clic pour passer)
		if state.shake > 0 then
			local x, y = CrateOpeningRules.jitter(elapsed * 0.7)
			shake = CFrame.new(x * OPENING_SHAKE * state.shake, y * OPENING_SHAKE * state.shake, 0)
		end
		if state.revealed and not current.revealed then
			current.revealed = true
			current.onRevealed()
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = glideFrom:Lerp(targetFrame(aspect), eased)
		* CFrame.Angles(math.rad(angles.camPitch), math.rad(angles.camYaw), 0)
		* shake
	local index = crateUnderMouse(camera)
	if index ~= hovered then
		hovered = index
		paintTags()
	end
end

-- Cette méthode permet de passer d'un plan de caméra à l'autre en glissant depuis l'image courante lorsque la vue change.
local function glideTo(newMode: "overview" | "detail")
	if newMode == mode then
		return
	end
	setPreview(nil)
	glideFrom = if running then workspace.CurrentCamera.CFrame else CAMERAS[newMode]
	glideStart = if running then os.clock() else -math.huge
	glideTime = GLIDE_TIME
	mode = newMode
	for _, light in vitrineLights do
		light.Enabled = newMode == "overview"
	end
	for _, light in detailLights do
		light.Enabled = newMode == "detail"
	end
	hovered = 0
	paintTags()
end

-- Cette méthode permet de montrer la vitrine (toutes les caisses en vente) lorsque le shop s'ouvre ou que le joueur
-- revient de la vue détail.
function ShopScene.showOverview()
	glideTo("overview")
end

-- Cette méthode permet de montrer la caisse `index` du catalogue sur le socle lorsque le joueur la choisit dans la
-- vitrine ou passe à la voisine dans la vue détail.
function ShopScene.showCrate(index: number)
	if index ~= shownCrate then
		shownCrate = index
		dressCrate(index)
	end
	glideTo("detail")
end

-- Cette méthode permet d'enregistrer le rappel appelé quand le joueur clique une caisse de la vitrine.
function ShopScene.onCrateClicked(callback: (number) -> ())
	onCrateClicked = callback
end

-- Cette méthode permet de montrer en grand, au-dessus de la caisse, l'arme habillée du skin `skinId` (#424, nil : retour
-- au plan détail) lorsque le joueur survole ou retient une ligne du contenu ; sans effet hors vue détail.
function ShopScene.preview(skinId: string?)
	setPreview(skinId)
end

-- Cette méthode permet de terminer l'ouverture (effets retirés, caisse refaite, retour au plan détail) lorsque
-- le joueur clique après la révélation ou quitte le shop ; `notify` prévient l'interface.
local function finishOpening(notify: boolean)
	local current = opening
	if not current then
		return
	end
	opening = nil
	current.fx:destroy()
	for light, base in roomLights do
		light.Brightness = base
	end
	table.clear(roomLights)
	if stage then
		dressCrate(shownCrate)
	end
	if running then
		glideTo("detail")
	else
		mode = "detail"
	end
	if notify then
		current.onFinished()
	end
end

-- Cette méthode permet de savoir si une ouverture est en cours (de la charge à la révélation tenue) lorsque
-- l'interface doit masquer ses commandes.
function ShopScene.isOpening(): boolean
	return opening ~= nil
end

-- Cette méthode permet de couper ou rendre le survol et le clic des caisses de la vitrine lorsqu'une fenêtre passe
-- devant la salle (packs de crédits, #395) : sans cela, les caisses s'éclairent et s'ouvrent sous la fenêtre.
function ShopScene.setInteractive(enabled: boolean)
	interactive = enabled
end

-- Cette méthode permet de lancer l'ouverture de la caisse du socle (#332) avec le skin tiré par le serveur (`skinId`,
-- rareté `rarityId`) lorsque la vue détail est affichée ; `onRevealed` à la révélation, `onFinished` au retour au plan
-- détail. Faux si l'ouverture ne peut pas se jouer (pas de caisse sur le socle, arme introuvable).
function ShopScene.playOpening(skinId: string, rarityId: string, onRevealed: () -> (), onFinished: () -> ()): boolean
	local item = InventoryRules.item(skinId)
	local crateModel = podiumCrate
	if opening or not (running and item and crateModel and stage) or mode ~= "detail" then
		return false
	end
	local row = item.weapon and REVEAL_WEAPONS[item.weapon]
	if not row then
		return false
	end
	-- L'ouverture se joue depuis le plan détail, sans l'arme de l'aperçu ni sa lampe de face
	setPreview(nil)
	if previewLight then
		previewLight.Brightness = 0
	end
	-- Palette de la montée de couleur : une couleur par rareté, dans l'ordre des paliers (CrateOpeningRules.TIERS)
	local colors = {}
	for _, r in ShopCatalog.RARITIES do
		table.insert(colors, Color3.fromRGB(r.color[1], r.color[2], r.color[3]))
	end
	local at = podiumFrame * CFrame.new(0, 3.7, 0)
	local weapon = revealWeapon(stage, row.viewmodel, skinId, at, row.length, true)
	if not weapon then
		return false
	end
	-- Lampes de la salle relevées avant les effets (qui ont leurs propres lumières)
	for _, light in stage:GetDescendants() do
		if light:IsA("SpotLight") and light ~= previewLight then
			roomLights[light] = light.Brightness
		end
	end
	local fx = CrateOpening.new({
		parent = stage,
		crate = crateModel,
		frame = podiumFrame,
		colors = colors,
		weapon = weapon,
		weaponAt = at,
		facing = CAMERAS.opening.Position,
		beamTexture = BEAM_TEXTURE,
	})
	opening = {
		fx = fx,
		rarity = rarityId,
		start = os.clock(),
		revealed = false,
		onRevealed = onRevealed,
		onFinished = onFinished,
	}
	-- La caméra avance vers la caisse pendant la montée de la charge (CrateOpeningRules : `push`, PUSH_TIME mesurée sur
	-- la référence), depuis le plan détail
	glideFrom = CAMERAS.detail
	mode = "opening"
	return true
end

-- Cette méthode permet de réagir à un clic dans la scène pendant l'ouverture : avant la révélation il y saute, après il
-- termine l'ouverture.
local function clickOpening()
	local current = opening
	if not current then
		return
	end
	if current.revealed then
		finishOpening(true)
		return
	end
	local elapsed = os.clock() - current.start
	local target = CrateOpeningRules.skip(elapsed, current.rarity)
	current.start = os.clock() - target
	current.fx:jump(target)
end

-- Cette méthode permet de lancer le shop (construction au premier appel, scène de l'accueil suspendue, ambiance de la
-- salle fermée, caméra et survol) lorsque l'écran Shop s'ouvre, sur la vitrine.
function ShopScene.start()
	if running then
		return
	end
	if not stage then
		build()
	end
	local folder = stage :: Folder
	running = true
	MenuScene.setPaused(true)
	savedAmbient = Lighting.Ambient
	Lighting.Ambient = ROOM_AMBIENT
	savedFov = workspace.CurrentCamera.FieldOfView
	folder.Parent = workspace
	mode = "detail" -- force la vue d'ensemble, sans glissement
	glideTo("overview")
	glideFrom = CAMERAS.overview
	glideStart = -math.huge
	if shownCrate == 0 and #ShopCatalog.CRATES > 0 then
		shownCrate = 1
		dressCrate(1)
	end
	connection = RunService.RenderStepped:Connect(PerfMarkers.wrap("shop 3D", update))
	inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		if processed or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and not isTouch) then
			return
		end
		if opening then
			clickOpening()
			return
		end
		-- Le survol suit la souris, pas le doigt : un toucher ne choisit pas de caisse sur ce survol périmé
		if not isTouch and hovered > 0 and onCrateClicked then
			onCrateClicked(hovered)
		elseif not dragging and preview and mode == "detail" and interactive then
			-- Aperçu retenu : glisser dans la salle tourne l'arme
			dragging = true
			-- Doigt : position du toucher (pas de curseur) ; on ne suit que ce toucher jusqu'à son relâchement
			dragInput = if isTouch then input else nil
			dragFrom = if isTouch
				then Vector2.new(input.Position.X, input.Position.Y)
				else UserInputService:GetMouseLocation()
			lastDrag = os.clock()
		end
	end)
	table.insert(
		dragConnections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				stickPos = Vector2.new(input.Position.X, input.Position.Y)
				return
			end
			if not dragging then
				return
			end
			local at: Vector2
			if dragInput then
				if input ~= dragInput then
					return
				end
				at = Vector2.new(input.Position.X, input.Position.Y)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				at = UserInputService:GetMouseLocation()
			else
				return
			end
			local delta = at - dragFrom
			dragFrom = at
			yaw, pitch = Rules.dragSpin(yaw, pitch, delta.X, delta.Y, DRAG_RATE, DRAG_PITCH)
			lastDrag = os.clock()
		end)
	)
	table.insert(
		dragConnections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				stickPos = Vector2.zero
				return
			end
			local ends = if dragInput
				then input == dragInput
				else input.UserInputType == Enum.UserInputType.MouseButton1
			if dragging and ends then
				dragging = false
				dragInput = nil
				-- Ramené à un demi-tour près : le balancement reprend sans dérouler les tours faits à la souris
				yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
				lastDrag = os.clock()
			end
		end)
	)
end

-- Cette méthode permet d'arrêter le shop (salle retirée du workspace mais gardée, ambiance et FOV rendus, scène de
-- l'accueil reprise) lorsque le joueur quitte l'écran ou que la partie démarre.
function ShopScene.stop()
	if not running then
		return
	end
	running = false
	finishOpening(false)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	for _, drag in dragConnections do
		drag:Disconnect()
	end
	table.clear(dragConnections)
	dragging = false
	dragInput = nil
	stickPos = Vector2.zero
	setPreview(nil)
	if previewLight then
		previewLight.Brightness = 0
	end
	if stage then
		stage.Parent = nil
	end
	if savedAmbient then
		Lighting.Ambient = savedAmbient
		savedAmbient = nil
	end
	workspace.CurrentCamera.FieldOfView = savedFov
	hovered = 0
	paintTags()
	MenuScene.setPaused(false)
end

return ShopScene

-- Scène 3D du shop (#347, docs/ui.md « Shop ») : salle de présentation dédiée, hors de la map, construite d'après les
-- cotes de la planche validée (tools/shop/board.py, scène B, en studs). Deux plans de caméra : la vue d'ensemble, face
-- à la vitrine du mur de droite (une caisse par série, étiquette avec nom et prix, survol en rouge d'impact), et la vue
-- détail, la caisse choisie sur son socle sous la suspension, son contenu sur le tableau du mur du fond (vraies armes
-- habillées de leurs skins). La caméra glisse de l'une à l'autre. Tout est local au client ; pendant le shop, la scène
-- de l'accueil est suspendue (MenuScene.setPaused) et l'ambiance du jeu est assombrie (salle fermée).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local PerfMarkers = require(Shared:WaitForChild("PerfMarkers"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WeaponSkins = require(Shared:WaitForChild("WeaponSkins"))
local MenuScene = require(script.Parent.MenuScene)
local Rules = require(script.Parent.MenuSceneRules)

local ShopScene = {}

-- La salle est posée loin de la map et de la copie de l'accueil (MenuScene, décalée de 5 000 studs en Z)
local ORIGIN = Vector3.new(0, 600, 12000)
local VERTICAL_FOV = 40 -- comme l'accueil
local ASPECT_REF = 16 / 9
local GLIDE_TIME = 0.9 -- s du glissement entre la vitrine et le socle
-- Gros plan sur une arme du tableau (#358) : survol retenu après HOVER_DELAY (un passage ne fait rien), l'arme couvre
-- FOCUS_FILL de la largeur de l'écran, centrée à FOCUS_SCREEN_X (à droite : la colonne de l'interface reste à gauche)
local FOCUS_GLIDE_TIME = 0.5
local HOVER_DELAY = 0.2
local FOCUS_FILL = 0.45
local FOCUS_SCREEN_X = 0.66
-- Zone de survol d'une arme : sa rangée du tableau (bande de rareté comprise), à peine plus longue que l'arme ; plus
-- longue, en gros plan elle sortait de l'écran et la souris ne pouvait plus la quitter par la droite
local HOVER_HEIGHT = 3.2
local HOVER_MARGIN = 0.2
-- Ambiance de la salle fermée (Lighting.Ambient pendant le shop) : celle du crépuscule baignait toute la pièce et
-- écrasait les lampes (planche : DIZZY_AMBIENT = 0,12)
local ROOM_AMBIENT = Color3.fromRGB(34, 32, 40)
-- Brightness des SpotLight = intensité de la planche x LIGHT_GAIN (réglé dans Studio : l'éclairage Voxel du jeu étale
-- chaque lampe sur toute la pièce, plus fort, il éclairait la salle à plat)
local LIGHT_GAIN = 0.6
local LIGHT_RANGE = 30

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
	LidStencil = { Color3.fromRGB(24, 22, 20), Enum.Material.SmoothPlastic },
}

-- Vitrine (repère local : x le long de la vitrine, y en haut, z vers la pièce)
local VITRINE_W, VITRINE_H, VITRINE_D = 13.2, 8.4, 3.0
local VITRINE_LEVELS = { 4.95, 1.45 } -- rangée 1 (hauteur d'œil) puis rangée 2
local SLOT = 4.3
local TAG_SIZE = Vector2.new(3.4, 0.62)
local TAG_PIXELS = 100 -- pixels par stud du texte des étiquettes

-- Tableau du contenu : armes posées de profil, longueur en studs
local BOARD_COLUMNS = { -4.9, 0, 4.9 }
local WEAPON_ROWS = {
	{ viewmodel = "AWP", item = "weapon.awp", y = 1.9, length = 4.4 },
	{ viewmodel = "M9Bayonet", item = "weapon.m9bayonet", y = -1.4, length = 2.7 },
}

type Frame = CFrame
type SaleCrate = { model: Model, tag: BasePart, name: TextLabel, price: TextLabel }
-- Arme du tableau : zone de survol invisible, ligne du contenu (rang dans ShopCatalog.contents), centre et longueur
type BoardTarget = { hitbox: BasePart, row: number, center: CFrame, length: number }

local room = CFrame.new(ORIGIN)
local vitrineFrame = room * CFrame.new(14.2, 0, 7.3) * CFrame.Angles(0, math.rad(-90), 0)
local boardFrame = room * CFrame.new(-3, 6.6, -8.3)
local CAMERAS = {
	detail = CFrame.lookAt(room * Vector3.new(4, 5.2, 20), room * Vector3.new(-4.5, 4.5, 0)),
	overview = CFrame.lookAt(vitrineFrame * Vector3.new(-2.8, 5.2, 17), vitrineFrame * Vector3.new(-2.8, 3.6, 0)),
}

local stage: Folder?
local podium: Folder? -- caisse du socle, refaite à chaque caisse montrée
local board: Folder? -- armes du tableau, refaites à chaque caisse montrée
local sale: { SaleCrate } = {}
local vitrineLights: { SpotLight } = {} -- allumées dans la vue d'ensemble seulement
local detailLights: { SpotLight } = {} -- allumées dans la vue détail seulement
local running = false
local connection: RBXScriptConnection?
local inputConnection: RBXScriptConnection?
local mode: "overview" | "detail" = "overview"
local shownCrate = 0
local hovered = 0
local glideFrom = CAMERAS.overview
local glideStart = -math.huge
local glideTime = GLIDE_TIME
local aimX, aimY = 0, 0
local savedAmbient: Color3?
local savedFov = 70
local onCrateClicked: ((number) -> ())?
local targets: { BoardTarget } = {} -- armes du tableau de la caisse montrée
local focus = 0 -- arme en gros plan (rang dans `targets`), 0 = plan détail
local hoverState: Rules.HoverState = { candidate = 0, since = 0, focused = 0 }
local onWeaponFocus: ((number?) -> ())?

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
-- sans `stripe` la caisse n'a pas de bande (stock sans marque).
local function crate(parent: Instance, frame: Frame, stripe: Color3?, width: number?): Model
	local model = CRATE:Clone()
	local pivot = CRATE:GetPivot()
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

-- Cette méthode permet de poser un projecteur (SpotLight sur une pièce invisible) lorsque la salle s'éclaire ; intensité
-- et angle de la planche, portée `range` (LIGHT_RANGE par défaut).
local function spot(
	parent: Instance,
	position: Vector3,
	direction: Vector3,
	angle: number,
	brightness: number,
	color: Color3,
	range: number?
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
	light.Brightness = brightness * LIGHT_GAIN
	light.Color = color
	light.Shadows = false
	light.Parent = holder
	holder.Parent = parent
	return light
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
	-- racks de stock : contre le mur du fond à droite du tableau, et contre le mur de gauche (pénombre sous l'interface)
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
	-- tableau du contenu : contreplaqué et clous
	box(
		parent,
		boardFrame,
		Vector3.zero,
		Vector3.new(15.5, 7.6, 0.2),
		Color3.fromRGB(206, 170, 118),
		Enum.Material.WoodPlanks
	)
	for i = -15, 15 do
		box(
			parent,
			boardFrame,
			Vector3.new(i * 0.5, 3.8, 0.12),
			Vector3.new(0.05, 0.05, 0.05),
			Color3.fromRGB(90, 70, 50)
		)
	end
	-- suspension industrielle au-dessus de la caisse : câble, douille, cloche émaillée, ampoule
	local enamel = Color3.fromRGB(52, 58, 54)
	local cyl = Enum.PartType.Cylinder
	box(parent, room, Vector3.new(0, 14, 0), Vector3.new(0.06, 8, 0.06), Color3.fromRGB(20, 20, 20))
	box(
		parent,
		room,
		Vector3.new(0, 10.15, 0),
		Vector3.new(0.45, 0.4, 0.45),
		Color3.fromRGB(30, 32, 34),
		metal,
		cyl,
		true
	)
	box(parent, room, Vector3.new(0, 9.85, 0), Vector3.new(1, 0.3, 1), enamel, metal, cyl, true)
	box(parent, room, Vector3.new(0, 9.6, 0), Vector3.new(1.9, 0.25, 1.9), enamel, metal, cyl, true)
	box(parent, room, Vector3.new(0, 9.42, 0), Vector3.new(2.4, 0.14, 2.4), enamel, metal, cyl, true)
	box(parent, room, Vector3.new(0, 9.36, 0), Vector3.new(2.2, 0.04, 2.2), BONE, nil, cyl, true)
	box(
		parent,
		room,
		Vector3.new(0, 9.3, 0),
		Vector3.new(0.6, 0.6, 0.6),
		Color3.fromRGB(255, 241, 224),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
end

-- Cette méthode permet d'éclairer la salle comme la planche (suspension, tableau, rack de droite, appoint de face) et de
-- poser les deux lampes de la vitrine, allumées dans la vue d'ensemble seulement, lorsque la salle se construit.
local function buildLights(parent: Instance)
	local function at(v: Vector3): Vector3
		return room * v
	end
	local function dir(v: Vector3): Vector3
		return room:VectorToWorldSpace(v.Unit)
	end
	-- Suspension : plus forte et plus courte que sur la planche, pour garder une flaque sur la caisse en Voxel
	spot(parent, at(Vector3.new(0, 9.2, 0)), Vector3.new(0, -1, 0), 60, 6.7, Color3.fromRGB(255, 228, 190), 16)
	-- Rack du fond, lumière froide : éteinte face à la vitrine, où ce rack passe sous le texte
	local cold = spot(
		parent,
		at(Vector3.new(8.5, 9.5, 3)),
		dir(Vector3.new(0.15, -0.45, -1)),
		55,
		0.8,
		Color3.fromRGB(200, 214, 255)
	)
	table.insert(detailLights, cold)
	spot(parent, at(Vector3.new(-3, 16, -2)), dir(Vector3.new(0, -1, -0.6)), 80, 0.9, Color3.fromRGB(255, 236, 210))
	for _, sx in { -1, 1 } do
		local from = Vector3.new(sx * 6.5, 4.3, 3.5)
		spot(parent, at(from), dir(Vector3.new(0, 2.5, 0) - from), 50, 1.6, Color3.fromRGB(255, 220, 170))
	end
	for _, sx in { -1, 1 } do
		local from = vitrineFrame * Vector3.new(sx * 4.3, 15.5, 5.5)
		local to = vitrineFrame * Vector3.new(sx * 3.6, 2.6, 0.5)
		-- Portée courte : à 30 studs, elles éclairaient aussi le rack du fond, sous le texte de la vue d'ensemble
		table.insert(vitrineLights, spot(parent, from, to - from, 44, 1.2, Color3.fromRGB(255, 226, 186), 20))
	end
end

-- Cette méthode permet d'écrire le nom et le prix d'une caisse sur son étiquette (SurfaceGui sur la face tournée vers la
-- pièce) lorsque la vitrine se construit.
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
	layout.Padding = UDim.new(0, 22)
	layout.Parent = row
	local function label(text: string, font: Font, size: number, order: number): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromScale(0, 1)
		t.FontFace = font
		t.TextSize = size
		t.TextColor3 = INK
		t.Text = text
		t.LayoutOrder = order
		t.Parent = row
		return t
	end
	local name = label(crateDef.name, UITheme.Fonts.Display, 36, 1)
	local price = label(ShopCatalog.priceLabel(crateDef), UITheme.Fonts.DisplayText, 30, 2)
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
			SHELF_CRATE_WIDTH
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
				part.CanQuery = true -- survol et clic par rayon depuis la souris
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
-- `length` studs, centrée en `at` et tournée comme le tableau, lorsque le tableau montre le contenu d'une caisse ; faux
-- si le viewmodel manque.
local function boardWeapon(parent: Instance, viewmodelName: string, skinId: string, at: CFrame, length: number): boolean
	local viewModels = ReplicatedStorage:FindFirstChild("ViewModels")
	local source = viewModels and viewModels:FindFirstChild(viewmodelName)
	if not source then
		return false
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
			copy.Parent = model
		end
	end
	if #model:GetChildren() == 0 then
		model:Destroy()
		return false
	end
	WeaponSkins.apply(model, viewmodelName, skinId)
	-- Profil : axe le plus long le long du tableau, axe le plus mince face à la pièce (comme UIKit.weaponSilhouette)
	local frame, size = model:GetBoundingBox()
	local axes = {
		{ length = size.X, dir = frame.RightVector },
		{ length = size.Y, dir = frame.UpVector },
		{ length = size.Z, dir = frame.LookVector },
	}
	table.sort(axes, function(a, b)
		return a.length > b.length
	end)
	local profile = CFrame.fromMatrix(frame.Position, axes[1].dir, axes[2].dir)
	-- Pivot au centre de la boîte : celui d'un Model créé par script est à l'origine, ScaleTo y emmènerait l'arme
	model.WorldPivot = frame
	model:PivotTo(at * profile:Inverse() * frame)
	model:ScaleTo(length / axes[1].length)
	model.Parent = parent
	return true
end

-- Cette méthode permet d'oublier le survol en cours (aucune arme candidate ni retenue) lorsque la vue change.
local function resetHover()
	hoverState.candidate, hoverState.since, hoverState.focused = 0, 0, 0
end

-- Cette méthode permet de rapprocher la caméra d'une arme du tableau (0 : retour au plan détail) en glissant depuis
-- l'image courante, et de prévenir l'interface, lorsque l'arme retenue change ; `instant` sans glissement.
local function setFocus(index: number, instant: boolean?)
	if index == focus then
		return
	end
	focus = index
	if running and not instant then
		glideFrom = workspace.CurrentCamera.CFrame
		glideStart = os.clock()
		glideTime = FOCUS_GLIDE_TIME
	end
	if onWeaponFocus then
		local target = targets[index]
		onWeaponFocus(if target then target.row else nil)
	end
end

-- Cette méthode permet de montrer une caisse dans la vue détail (sa caisse sur le socle, ses armes et la rareté de
-- chacune au tableau, une zone de survol par arme) lorsque le joueur la choisit.
local function dressCrate(index: number)
	local def = ShopCatalog.CRATES[index]
	if not (def and stage) then
		return
	end
	setFocus(0)
	resetHover()
	table.clear(targets)
	if podium then
		podium:Destroy()
	end
	if board then
		board:Destroy()
	end
	local podiumFolder = Instance.new("Folder")
	podiumFolder.Name = "Podium"
	local stripe = Color3.fromRGB(def.stripe[1], def.stripe[2], def.stripe[3])
	crate(podiumFolder, room * CFrame.new(0, 1.34, 0) * CFrame.Angles(0, math.rad(-14), 0), stripe)
	podiumFolder.Parent = stage
	podium = podiumFolder
	local boardFolder = Instance.new("Folder")
	boardFolder.Name = "Board"
	for j, row in ShopCatalog.contents(def, InventoryRules.ITEMS) do
		local x = BOARD_COLUMNS[j]
		if x then
			local c = row.rarity.color
			local color = Color3.fromRGB(c[1], c[2], c[3])
			for _, weapon in WEAPON_ROWS do
				for _, skinId in row.skins do
					local item = InventoryRules.item(skinId)
					local center = boardFrame * CFrame.new(x, weapon.y, 0.35)
					if
						item
						and item.weapon == weapon.item
						and boardWeapon(boardFolder, weapon.viewmodel, skinId, center, weapon.length)
					then
						-- Zone de survol invisible, plus large que l'arme (un profil d'AWP est trop fin à viser)
						local hitbox = box(
							boardFolder,
							boardFrame,
							Vector3.new(x, weapon.y - 0.4, 0.4),
							Vector3.new(weapon.length + HOVER_MARGIN, HOVER_HEIGHT, 0.3),
							BONE
						)
						hitbox.Name = "Hover"
						hitbox.Transparency = 1
						hitbox.CastShadow = false
						hitbox.CanQuery = true
						table.insert(targets, { hitbox = hitbox, row = j, center = center, length = weapon.length })
					end
				end
				box(boardFolder, boardFrame, Vector3.new(x, weapon.y - 1.15, 0.13), Vector3.new(3.8, 0.18, 0.06), color)
			end
		end
	end
	boardFolder.Parent = stage
	board = boardFolder
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
	if mode ~= "overview" or not stage then
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

-- Cette méthode permet de trouver l'arme du tableau sous la souris (rayon sur les zones de survol) lorsque la vue
-- détail est affichée ; 0 si aucune.
local function weaponUnderMouse(camera: Camera): number
	if mode ~= "detail" or #targets == 0 then
		return 0
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local hitboxes = {}
	for _, target in targets do
		table.insert(hitboxes, target.hitbox)
	end
	params.FilterDescendantsInstances = hitboxes
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if hit then
		for i, target in targets do
			if target.hitbox == hit.Instance then
				return i
			end
		end
	end
	return 0
end

-- Cette méthode permet de donner le plan visé par la caméra (vitrine, socle, ou gros plan de face de l'arme retenue,
-- décalée à droite) lorsqu'une image est rendue ; `aspect` (au moins 16:9, comme le FOV) règle le recul du gros plan.
local function targetFrame(aspect: number): CFrame
	local target = if mode == "detail" then targets[focus] else nil
	if not target then
		return CAMERAS[mode]
	end
	local distance, offset = Rules.closeUp(target.length, VERTICAL_FOV, aspect, FOCUS_FILL, FOCUS_SCREEN_X)
	-- face au tableau (+Z du repère vers la pièce), décalée à gauche de l'arme
	return target.center * CFrame.new(-offset, 0, distance)
end

-- Cette méthode permet de placer la caméra (glissement entre les plans, léger suivi du curseur, FOV adapté au format) et
-- de suivre le survol (étiquettes de la vitrine, gros plan d'une arme du tableau) lorsqu'une image est rendue.
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
	local t = math.clamp((os.clock() - glideStart) / glideTime, 0, 1)
	local eased = t * t * (3 - 2 * t)
	local angles = Rules.aimAngles(aimX, aimY)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = glideFrom:Lerp(targetFrame(aspect), eased)
		* CFrame.Angles(math.rad(angles.camPitch), math.rad(angles.camYaw), 0)
	local index = crateUnderMouse(camera)
	if index ~= hovered then
		hovered = index
		paintTags()
	end
	-- Pas de décision pendant un glissement : l'arme passe sous la souris ou la quitte sans que le joueur bouge
	if mode == "detail" and t >= 1 then
		setFocus(Rules.settleHover(hoverState, weaponUnderMouse(camera), os.clock(), HOVER_DELAY))
	end
end

-- Cette méthode permet de passer d'un plan de caméra à l'autre en glissant depuis l'image courante lorsque la vue change.
local function glideTo(newMode: "overview" | "detail")
	if newMode == mode then
		return
	end
	setFocus(0, true)
	resetHover()
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

-- Cette méthode permet d'enregistrer le rappel appelé quand le gros plan change (#358) : rang de la ligne du contenu
-- dont l'arme est en gros plan, nil au retour au plan détail.
function ShopScene.onWeaponFocus(callback: (number?) -> ())
	onWeaponFocus = callback
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
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if hovered > 0 and onCrateClicked then
			onCrateClicked(hovered)
		end
	end)
end

-- Cette méthode permet d'arrêter le shop (salle retirée du workspace mais gardée, ambiance et FOV rendus, scène de
-- l'accueil reprise) lorsque le joueur quitte l'écran ou que la partie démarre.
function ShopScene.stop()
	if not running then
		return
	end
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
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
	setFocus(0, true)
	resetHover()
	MenuScene.setPaused(false)
end

return ShopScene

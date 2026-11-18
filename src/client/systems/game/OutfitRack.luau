-- Portant des tenues du shop (#543, docs/ui.md « Portant des tenues », planche validée le 18/11/2026 : présentation sur
-- cintre, emplacement P1 contre le mur de gauche face à la vitrine) : cadre métallique blanc à montants perforés et deux
-- barres chromées (référence de l'utilisateur), chaque tenue en vente pendue en deux pièces, le haut (torse et bras) sur
-- la barre du haut, le bas (bassin et jambes) sur celle du bas, de trois quarts ; la tenue survolée sort du rang, de
-- face. Étiquette os sur la traverse du haut (nom, prix ou POSSÉDÉE). Construit aussi le personnage habillé montré sur le
-- socle dans la vue détail d'une tenue. Géométrie seulement : caméra, lumières et clic dans ShopScene.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterAppearance = require(Shared:WaitForChild("CharacterAppearance"))
local Locale = require(Shared:WaitForChild("Locale"))
local OutfitRackRules = require(Shared:WaitForChild("OutfitRackRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local WalletRules = require(Shared:WaitForChild("WalletRules"))
local MenuSceneRules = require(script.Parent.MenuSceneRules)

local OutfitRack = {}

-- Cotes de la planche (tools/shop/outfit_rack_board.py, rack_hangers), studs, repère du portant : x le long, y en haut,
-- z vers la pièce
OutfitRack.WIDTH = 13.2
OutfitRack.HEIGHT = 9.8
local DEPTH = 2.6
local UPPER_BAR, LOWER_BAR = 9.0, 4.75
local HOLE_STEP = 0.45 -- perforations des montants
local TAG_HEIGHT = 0.42
local TAG_PIXELS = 100 -- pixels par stud du texte des étiquettes
local OUT_RATE = 8 -- vitesse de sortie du rang (MenuSceneRules.damp)

-- Blanc en plastique lisse : en métal, sous les deux lampes du portant, il sortait gris foncé (vérifié en Studio)
local WHITE = Color3.fromRGB(236, 236, 232)
local CHROME = Color3.fromRGB(196, 200, 206)
local HOLE = Color3.fromRGB(60, 62, 66)
local FOOT = Color3.fromRGB(70, 74, 80)
local HANGER = Color3.fromRGB(176, 128, 80)
local BONE = UITheme.Colors.Bone
local INK = UITheme.Colors.Ground
local HIT_RED = UITheme.Colors.HitRed

-- Pièces du rig pendues sur chaque barre ; le reste (tête, racine) n'est pas sur le portant
local TOP = {
	UpperTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}
local BOTTOM = {
	LowerTorso = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}
-- Couleur du corps (BodyColors) de chaque pièce du rig, fixée sur la pièce : le personnage du portant n'a plus d'Humanoid
local BODY_COLOR = {
	Head = "HeadColor3",
	UpperTorso = "TorsoColor3",
	LowerTorso = "TorsoColor3",
	LeftUpperArm = "LeftArmColor3",
	LeftLowerArm = "LeftArmColor3",
	LeftHand = "LeftArmColor3",
	RightUpperArm = "RightArmColor3",
	RightLowerArm = "RightArmColor3",
	RightHand = "RightArmColor3",
	LeftUpperLeg = "LeftLegColor3",
	LeftLowerLeg = "LeftLegColor3",
	LeftFoot = "LeftLegColor3",
	RightUpperLeg = "RightLegColor3",
	RightLowerLeg = "RightLegColor3",
	RightFoot = "RightLegColor3",
}

-- Personnage habillé, figé au repos : modèle (pivot à la racine du rig, face vers -z), hauteurs par rapport à la
-- racine du haut du torse, du haut du bassin et du dessous des pieds
export type Figure = { model: Model, torsoTop: number, pelvisTop: number, feet: number }
type Hanging = { model: Model, y: number }
type Entry = {
	x: number,
	rank: number?,
	out: number,
	target: number,
	pieces: { Hanging },
	tag: BasePart?,
	name: TextLabel?,
	price: TextLabel?,
	coin: ImageLabel?,
}
export type Rack = {
	entries: { Entry },
	frame: CFrame,
	hovered: number,
}

-- Cette méthode permet de poser une pièce ancrée sans collision dans un repère (centre local, taille) lorsque le portant
-- se construit ; un cylindre `upright` est dressé sur l'axe Y du repère (l'axe des cylindres Roblox est X).
local function part(
	parent: Instance,
	frame: CFrame,
	position: Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	cylinder: boolean?,
	upright: boolean?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Shape = if cylinder then Enum.PartType.Cylinder else Enum.PartType.Block
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	local cf = frame * CFrame.new(position)
	if upright then
		cf *= CFrame.Angles(0, 0, math.pi / 2)
		size = Vector3.new(size.Y, size.X, size.Z)
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Cette méthode permet de construire le cadre du portant (quatre montants perforés sur pieds, traverses et écharpe sur
-- les côtés, lisses du haut, deux barres chromées) lorsque le shop se construit.
local function buildFrame(parent: Instance, f: CFrame)
	local W, H, D = OutfitRack.WIDTH, OutfitRack.HEIGHT, DEPTH
	local metal = Enum.Material.Metal
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - 0.15), sz * (D / 2 - 0.15)
			part(parent, f, Vector3.new(x, H / 2, z), Vector3.new(0.3, H, 0.3), WHITE)
			part(parent, f, Vector3.new(x, 0.03, z), Vector3.new(0.6, 0.06, 0.6), FOOT, metal)
			for k = 0, math.floor((H - 0.6) / HOLE_STEP) - 1 do
				part(
					parent,
					f,
					Vector3.new(x, 0.45 + k * HOLE_STEP, z + sz * 0.151),
					Vector3.new(0.1, 0.22, 0.02),
					HOLE
				)
			end
		end
		local x = sx * (W / 2 - 0.15)
		for _, y in { 0.35, H - 0.15 } do
			part(parent, f, Vector3.new(x, y, 0), Vector3.new(0.22, 0.22, D - 0.3), WHITE)
		end
		-- écharpe en diagonale sur le côté (référence)
		local spanY, spanZ = H - 0.8, D - 0.6
		local brace = f * CFrame.new(x, H / 2, 0) * CFrame.Angles(-math.atan2(spanZ, spanY), 0, 0)
		part(parent, brace, Vector3.zero, Vector3.new(0.14, math.sqrt(spanY ^ 2 + spanZ ^ 2), 0.14), WHITE)
	end
	for _, sz in { -1, 1 } do
		part(parent, f, Vector3.new(0, H - 0.15, sz * (D / 2 - 0.15)), Vector3.new(W, 0.22, 0.22), WHITE)
	end
	for _, y in { UPPER_BAR, LOWER_BAR } do
		part(parent, f, Vector3.new(0, y, 0), Vector3.new(W - 0.3, 0.16, 0.16), CHROME, metal, true)
		for _, sx in { -1, 1 } do
			part(parent, f, Vector3.new(sx * (W / 2 - 0.15), y, 0), Vector3.new(0.24, 0.24, D - 0.3), WHITE)
		end
	end
end

-- Cette méthode permet de construire le personnage du jeu habillé d'une tenue (rig de référence, cartes et pièces de la
-- tenue), figé au repos, sans script, physique ni Humanoid, lorsque le portant ou la vue détail d'une tenue le montre ;
-- nil si la place n'a pas de StarterCharacter.
function OutfitRack.figure(outfitId: string?): Figure?
	local template = CharacterAppearance.getTemplate()
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = "OutfitFigure"
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	CharacterAppearance.apply(model, outfitId)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	local colors = model:FindFirstChildOfClass("BodyColors")
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local key = BODY_COLOR[item.Name]
			if colors and key then
				item.Color = (colors :: any)[key]
			end
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	local pivot = root.CFrame
	-- Hauteur d'une face d'une pièce par rapport à la racine (rig au repos, pièces droites)
	local function edge(name: string, sign: number): number
		local p = model:FindFirstChild(name)
		if not (p and p:IsA("BasePart")) then
			return 0
		end
		return p.Position.Y + sign * p.Size.Y / 2 - pivot.Y
	end
	local figure = {
		model = model,
		torsoTop = edge("UpperTorso", 1),
		pelvisTop = edge("LowerTorso", 1),
		feet = math.min(edge("LeftFoot", -1), edge("RightFoot", -1)),
	}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	if colors then
		colors:Destroy()
	end
	root:Destroy()
	model.WorldPivot = pivot
	return figure
end

-- Cette méthode permet de garder d'un personnage habillé les seules pièces d'une moitié (`keep` : haut ou bas) et les
-- pièces de tenue soudées à l'une d'elles (épaulière, col, tablier…) lorsqu'une tenue est pendue au portant.
local function keepOnly(model: Model, keep: { [string]: boolean })
	local drop = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and not keep[child.Name] then
			local weld = child:FindFirstChildOfClass("WeldConstraint")
			local holder = weld and weld.Part0
			if not (holder and keep[holder.Name]) then
				table.insert(drop, child)
			end
		elseif child:IsA("Accessory") then
			table.insert(drop, child)
		end
	end
	for _, child in drop do
		child:Destroy()
	end
end

-- Cette méthode permet d'ajouter à une moitié pendue son cintre en bois (sur les épaules, ou pince du bas) et son crochet
-- chromé jusqu'à la barre, `top` étant le haut de la pièce portée (repère de la moitié) lorsque le portant se construit.
local function hanger(model: Model, pivot: CFrame, top: number, lift: number)
	local y = top + lift
	part(model, pivot, Vector3.new(0, y, 0), Vector3.new(3.5, 0.14, 0.3), HANGER, Enum.Material.Wood)
	part(
		model,
		pivot,
		Vector3.new(0, y + 0.24, 0),
		Vector3.new(0.06, 0.4, 0.06),
		CHROME,
		Enum.Material.Metal,
		true,
		true
	)
end

-- Cette méthode permet de construire l'étiquette d'une tenue sur la traverse du haut (nom, jeton et prix, ou POSSÉDÉE)
-- lorsque le portant se construit ; renvoie la plaque et ses textes.
local function buildTag(
	parent: Instance,
	f: CFrame,
	x: number,
	width: number,
	item: any
): (BasePart, TextLabel, TextLabel, ImageLabel)
	local plate = part(
		parent,
		f,
		Vector3.new(x, OutfitRack.HEIGHT - 0.15, DEPTH / 2 + 0.02),
		Vector3.new(width, TAG_HEIGHT, 0.04),
		BONE
	)
	plate.Name = "Tag"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +z du repère du portant : vers la pièce
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = TAG_PIXELS
	gui.LightInfluence = 0.5 -- comme les étiquettes de la vitrine : à 1, l'os sur rouge restait terne
	gui.Parent = plate
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
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
	local name = label(item.name or item.id, UITheme.Fonts.Display, 24, 1)
	local coin = Instance.new("ImageLabel")
	coin.Name = "Credit"
	coin.BackgroundTransparency = 1
	coin.Size = UDim2.fromOffset(20, 20)
	coin.Image = WalletRules.ICON
	coin.LayoutOrder = 2
	coin.Parent = row
	local price = label(WalletRules.format(item.price or 0), UITheme.Fonts.DisplayText, 22, 3)
	return plate, name, price, coin
end

-- Cette méthode permet de construire le portant dans le repère `frame` (pieds au sol, z vers la pièce), d'y pendre les
-- tenues en vente (`outfits`, dans l'ordre du catalogue) et de compléter le rang de cintres vides lorsque le shop se
-- construit. Chaque moitié pendue porte l'attribut ShopOutfit (rang de la tenue) pour le survol.
function OutfitRack.build(parent: Instance, frame: CFrame, outfits: { any }): Rack
	local folder = Instance.new("Folder")
	folder.Name = "OutfitRack"
	buildFrame(folder, frame)
	local slots = OutfitRackRules.slots(#outfits, OutfitRack.WIDTH)
	local step = if #slots > 1 then slots[2].x - slots[1].x else OutfitRack.WIDTH
	-- Hauteurs du rig, relevées une fois sur le personnage d'origine (cintres vides compris)
	local reference = OutfitRack.figure(nil)
	local torsoTop = if reference then reference.torsoTop else 1.59
	local pelvisTop = if reference then reference.pelvisTop else -0.95
	if reference then
		reference.model:Destroy()
	end
	local rack: Rack = { entries = {}, frame = frame, hovered = 0 }
	for _, slot in slots do
		local item = slot.outfit and outfits[slot.outfit]
		local entry: Entry = { x = slot.x, rank = slot.outfit, out = 0, target = 0, pieces = {} }
		local figure = if item then OutfitRack.figure(item.id) else nil
		for _, half in
			{
				{ keep = TOP, top = torsoTop, bar = UPPER_BAR - 0.55, lift = 0.08 },
				{
					keep = BOTTOM,
					top = pelvisTop,
					bar = LOWER_BAR - 0.45,
					lift = 0.06,
				},
			}
		do
			local model: Model
			if figure then
				model = figure.model:Clone()
				keepOnly(model, half.keep)
			else
				model = Instance.new("Model")
				model.WorldPivot = CFrame.identity
			end
			model.Name = if item then item.id else "EmptyHanger"
			hanger(model, model.WorldPivot, half.top, half.lift)
			if slot.outfit then
				model:SetAttribute("ShopOutfit", slot.outfit)
				for _, p in model:GetDescendants() do
					if p:IsA("BasePart") then
						p.CanQuery = true -- survol et clic par rayon depuis la souris
					end
				end
			end
			model.Parent = folder
			table.insert(entry.pieces, { model = model, y = half.bar - half.top })
		end
		if figure then
			figure.model:Destroy()
		end
		if item then
			local tag, name, price, coin = buildTag(folder, frame, slot.x, math.min(step - 0.25, 2.6), item)
			tag.CanQuery = true
			tag:SetAttribute("ShopOutfit", slot.outfit)
			entry.tag, entry.name, entry.price, entry.coin = tag, name, price, coin
		end
		table.insert(rack.entries, entry)
	end
	folder.Parent = parent
	OutfitRack.pose(rack, 0)
	return rack
end

-- Cette méthode permet de poser chaque moitié pendue à sa place (de trois quarts, ou sortie du rang de face selon sa
-- sortie) et de faire avancer la sortie de la tenue survolée lorsqu'une image est rendue ; `dt` 0 pose sans avancer.
function OutfitRack.pose(rack: Rack, dt: number)
	for _, entry in rack.entries do
		local target = if entry.rank and entry.rank == rack.hovered then 1 else 0
		local moved = dt == 0 or math.abs(entry.out - target) > 1e-3
		if not moved then
			continue
		end
		entry.out = if dt == 0 then target else MenuSceneRules.damp(entry.out, target, dt, OUT_RATE)
		local yaw, forward = OutfitRackRules.pose(entry.out)
		for _, piece in entry.pieces do
			piece.model:PivotTo(rack.frame * CFrame.new(entry.x, piece.y, forward) * CFrame.Angles(0, math.rad(yaw), 0))
		end
	end
end

-- Cette méthode permet de peindre les étiquettes (survolée en rouge d'impact à texte os ; tenue possédée : POSSÉDÉE à la
-- place du prix) lorsque le survol ou l'inventaire change ; `owns` dit si le joueur possède la tenue d'un id.
function OutfitRack.paint(rack: Rack, outfits: { any }, owns: (string) -> boolean)
	for _, entry in rack.entries do
		local item = entry.rank and outfits[entry.rank]
		if not (item and entry.tag and entry.name and entry.price and entry.coin) then
			continue
		end
		local hot = entry.rank == rack.hovered
		local owned = owns(item.id)
		entry.tag.Color = if hot then HIT_RED else BONE
		entry.name.TextColor3 = if hot then BONE else INK
		entry.price.TextColor3 = if hot then BONE else INK
		entry.coin.Visible = not owned
		if owned then
			Locale.apply(entry.price, "POSSÉDÉE")
		else
			Locale.apply(entry.price, WalletRules.format(item.price or 0))
		end
	end
end

-- Cette méthode permet de lister les moitiés pendues et les étiquettes des tenues lorsque le survol lance un rayon
-- depuis la souris.
function OutfitRack.targets(rack: Rack): { Instance }
	local list = {}
	for _, entry in rack.entries do
		if entry.rank then
			for _, piece in entry.pieces do
				table.insert(list, piece.model)
			end
			if entry.tag then
				table.insert(list, entry.tag)
			end
		end
	end
	return list
end

return OutfitRack

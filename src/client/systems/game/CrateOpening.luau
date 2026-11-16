-- Effets de l'ouverture d'une caisse sur le socle du shop (#332, docs/ui.md « Ouverture d'une caisse ») : la caisse
-- tressaute, la lueur de la rareté filtre par la fente du couvercle, bouffées et rayons, gerbes d'étincelles, explosion,
-- le couvercle saute et retombe derrière le socle, une colonne de lumière jaillit, l'arme en lumière unie (silhouette)
-- tourne au-dessus de la caisse puis apparaît habillée de son skin. La chronologie est dans CrateOpeningRules : ce
-- module ne fait qu'appliquer, à chaque image, l'état échantillonné. La caméra reste à ShopScene.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared:WaitForChild("CrateOpeningRules"))

local CrateOpening = {}
CrateOpening.__index = CrateOpening

-- Géométrie de la caisse (tools/shop/crate_model.py, origine au centre du dessous) : couvercle de 1,44 à 2,02 stud,
-- fente entre le corps (1,40) et le couvercle (1,47), dessus à 2,02
local LID_CENTER_Y = 1.73
local LID_HALF_HEIGHT = 0.29
local SEAM_Y = 1.43
local SEAM_SIZE = Vector3.new(4.0, 0.08, 2.4)
local TOP_Y = 2.02
-- Vol du couvercle : retombe à l'envers derrière le socle (repère de la caisse : plancher 1,34 stud plus bas)
local LID_LANDING = Vector3.new(0.6, -1.34 + LID_HALF_HEIGHT, -3.6)
local LID_ARC = 3.0 -- hauteur de l'arc au-dessus de la ligne départ-arrivée
local LID_YAW = 30
-- Secousses de la caisse à pleine amplitude (charge)
local SHAKE_MOVE = 0.05
local SHAKE_LIFT = 0.07
local SHAKE_TILT = 2.5
-- Tension avant l'explosion : la caisse se soulève du socle et ses secousses doublent d'amplitude
local LIFT_HEIGHT = 0.3
local TENSION_SHAKE = 1.0 -- amplitude ajoutée au plein de la tension (×2)
-- Braises qui montent de la caisse ouverte pendant la montée de la silhouette
local EMBER_RATE = 40
local EMBER_SIZE = Vector3.new(3.4, 0.1, 1.8)
-- Arme : au fond de la caisse au départ, puis au-dessus du couvercle
local WEAPON_LOW = 1.0
local WEAPON_HOVER = 3.3 -- réglée quand le tableau d'armes était au mur (retiré en #424) : à 3,7, elle le touchait
-- Intérieur en néon : couleur de la lueur à pleine intensité, assombrie (à 1, le néon saturait en bloc blanc)
local INTERIOR_NEON = 0.55
-- Caisse ouverte : le bloc `Interior` (plein jusqu'au couvercle) faisait une dalle de néon ; il disparaît au départ du
-- couvercle et un fond lumineux, au ras du dessous, montre une caisse creuse éclairée de l'intérieur
local FLOOR_Y = 0.12
local FLOOR_SIZE = Vector3.new(3.8, 0.04, 2.2)
-- Lampe de face sur l'arme révélée : sans elle, l'arme se détachait en ombre chinoise sur le mur du fond
local KEY_BRIGHTNESS = 2.5
local KEY_RANGE = 18
local KEY_ANGLE = 35
-- Lumières (Future : la lampe intérieure projette des ombres, sa lumière ne sort que par la fente tant que la caisse
-- est fermée)
local INNER_RANGE = 12
local INNER_BRIGHTNESS = 4
local FLASH_RANGE = 24
local FLASH_BRIGHTNESS = 6 -- à 10, l'explosion brûlait le mur du fond en blanc
local FLASH_EXPOSURE = 0.3 -- ColorCorrection.Brightness au plus fort de l'éclair
local COLUMN_HEIGHT = 9
local COLUMN_LAYERS = { { 2.0, 3.6, 0.35 }, { 1.0, 1.8, 0 } } -- largeur en bas, en haut, transparence de base
-- Lumière qui jaillit par la fente du couvercle (retour de l'utilisateur : par le dessus, elle traversait le
-- couvercle) : nappes à l'horizontale, fines au ras de la fente, qui s'ouvrent en s'éloignant. Départ sur le bord de
-- la caisse (repère de la fente : x le long de la caisse, z vers l'avant), direction quasi horizontale
local RAY_LENGTH = 3.5
local RAY_WIDTHS = { 0.1, 1.4 } -- au départ, au bout
local SEAM_RAYS = {
	{ from = Vector3.new(-2.02, 0, 0), dir = Vector3.new(-1, 0.06, 0.1) },
	{ from = Vector3.new(2.02, 0, 0), dir = Vector3.new(1, 0.06, 0.1) },
	{ from = Vector3.new(-1.3, 0, 1.22), dir = Vector3.new(-0.6, 0.05, 1) },
	{ from = Vector3.new(1.3, 0, 1.22), dir = Vector3.new(0.6, 0.05, 1) },
	{ from = Vector3.new(0, 0, 1.22), dir = Vector3.new(0.05, 0.04, 1) },
}
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARK_BURST = 45
local CRACKLE_RATE = 30 -- étincelles par seconde à pleine secousse

type PartPose = { part: BasePart, rel: CFrame }
export type Params = {
	parent: Instance,
	crate: Model, -- caisse du socle (modèle cloné par ShopScene)
	frame: CFrame, -- repère de la caisse : centre du dessous, face avant vers +z
	colors: { Color3 }, -- couleur de chaque palier de rareté (CrateOpeningRules.TIERS), la lumière y monte jusqu'au tiré
	weapon: Model, -- arme habillée de son skin, posée au repère `weaponAt`
	weaponAt: CFrame,
	facing: Vector3, -- point vers lequel l'arme se tourne de profil (la caméra de l'ouverture)
	beamTexture: string,
}

-- Cette méthode permet de poser une pièce invisible, ancrée et sans collision, qui porte une lumière, des attaches ou
-- un émetteur lorsque les effets se construisent.
local function holder(parent: Instance, name: string, cframe: CFrame, size: Vector3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- Cette méthode permet de créer un ruban de lumière (Beam tourné vers la caméra, texture du profil de faisceau du shop)
-- entre deux attaches lorsque la colonne ou les rayons se construisent.
local function ribbon(parent: Instance, a0: Attachment, a1: Attachment, color: Color3, texture: string): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Texture = texture
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(1)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 8
	beam.Parent = parent
	return beam
end

-- Cette méthode permet de régler l'opacité d'un ruban (plein en bas, effacé en haut) lorsque son intensité change.
local function setRibbon(beam: Beam, base: number, amount: number)
	local start = 1 - (1 - base) * math.clamp(amount, 0, 1)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, start),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Cette méthode permet de créer un émetteur d'étincelles de la couleur de la rareté (texture du moteur, gravité,
-- émission sur la surface de `parent`) lorsque les effets se construisent.
local function sparks(parent: Instance, color: Color3, speed: NumberRange, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Drag = 1.5
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

-- Cette méthode permet de transformer une copie de l'arme en silhouette de lumière unie (néon de la rareté, sans skin
-- ni texture) lorsque les effets se construisent.
local function silhouetteOf(weapon: Model, color: Color3): Model
	local copy = weapon:Clone()
	copy.Name = "Silhouette"
	for _, item in copy:GetDescendants() do
		if item:IsA("SurfaceAppearance") or item:IsA("Decal") or item:IsA("Texture") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Material = Enum.Material.Neon
			item.Color = color
			item.CastShadow = false
			item.Transparency = 1
			if item:IsA("MeshPart") then
				item.TextureID = ""
			end
		end
	end
	return copy
end

-- Cette méthode permet de construire les effets de l'ouverture autour de la caisse du socle (lampe intérieure, fente
-- lumineuse, rayons, étincelles, éclair, colonne, silhouette) lorsque le serveur a tiré le skin.
function CrateOpening.new(params: Params)
	local self = setmetatable({}, CrateOpening)
	local folder = Instance.new("Folder")
	folder.Name = "CrateOpening"
	folder.Parent = params.parent
	self.folder = folder
	self.frame = params.frame
	self.colors = params.colors
	-- Couleurs du premier palier ; recalculées par _setTier à chaque palier de la montée de couleur
	self.tier = 0
	self.light = Color3.new(1, 1, 1)
	self.neon = self.light
	self.lastT = 0

	-- Pièces de la caisse, par rapport à son repère ; le couvercle (« Lid* ») par rapport à son centre
	local lidCenter = params.frame * CFrame.new(0, LID_CENTER_Y, 0)
	self.body = {} :: { PartPose }
	self.lid = {} :: { PartPose }
	for _, part in params.crate:GetChildren() do
		if part:IsA("BasePart") then
			if string.sub(part.Name, 1, 3) == "Lid" then
				table.insert(self.lid, { part = part, rel = lidCenter:ToObjectSpace(part.CFrame) })
			else
				table.insert(self.body, { part = part, rel = params.frame:ToObjectSpace(part.CFrame) })
			end
			if part.Name == "Interior" then
				self.interior = part
				self.interiorColor = part.Color
				part.Material = Enum.Material.Neon
			end
		end
	end

	local floor = holder(folder, "GlowFloor", params.frame * CFrame.new(0, FLOOR_Y, 0), FLOOR_SIZE)
	floor.Material = Enum.Material.Neon
	floor.Color = self.neon
	self.floor = floor
	self.floorRel = params.frame:ToObjectSpace(floor.CFrame)

	-- Lampe intérieure (à ombres : la caisse fermée ne laisse passer que la fente) et éclair
	local inner = Instance.new("PointLight")
	inner.Color = self.light
	inner.Range = INNER_RANGE
	inner.Brightness = 0
	inner.Shadows = true
	inner.Parent = holder(folder, "InnerLight", params.frame * CFrame.new(0, 1.0, 0))
	self.inner = inner
	local flash = Instance.new("PointLight")
	flash.Color = self.light
	flash.Range = FLASH_RANGE
	flash.Brightness = 0
	flash.Parent = holder(folder, "FlashLight", params.frame * CFrame.new(0, TOP_Y + 1.5, 1.5))
	self.flashLight = flash
	local exposure = Instance.new("ColorCorrectionEffect")
	exposure.Name = "CrateOpeningFlash"
	exposure.Brightness = 0
	exposure.TintColor = Color3.new(1, 1, 1)
	exposure.Parent = Lighting
	self.exposure = exposure

	-- Nappes de lumière qui jaillissent par la fente du couvercle à chaque bouffée
	local rays = holder(folder, "SeamRays", params.frame * CFrame.new(0, SEAM_Y, 0))
	self.rays = {} :: { Beam }
	for _, ray in SEAM_RAYS do
		local origin = Instance.new("Attachment")
		origin.Position = ray.from
		origin.Parent = rays
		local tip = Instance.new("Attachment")
		tip.Position = ray.from + ray.dir.Unit * RAY_LENGTH
		tip.Parent = rays
		local beam = ribbon(rays, origin, tip, self.light, params.beamTexture)
		beam.Width0, beam.Width1 = RAY_WIDTHS[1], RAY_WIDTHS[2]
		table.insert(self.rays, beam)
	end

	-- Étincelles : crépitements par la fente pendant la charge, gerbes aux instants de la chronologie
	local seam = holder(folder, "Seam", params.frame * CFrame.new(0, SEAM_Y, 0), SEAM_SIZE)
	self.crackle = sparks(seam, self.light, NumberRange.new(3, 7), 0.08)
	self.burst = sparks(seam, self.light, NumberRange.new(10, 22), 0.14)
	-- Ce qui sort de la fente et la lampe intérieure suivent la caisse quand elle tremble et se soulève
	self.followers = {} :: { PartPose }
	for _, part in { rays, seam, inner.Parent :: BasePart } do
		table.insert(self.followers, { part = part, rel = params.frame:ToObjectSpace(part.CFrame) })
	end
	-- Braises : lentes, vers le haut, sans gravité, depuis l'intérieur de la caisse ouverte
	local embers = sparks(
		holder(folder, "Embers", params.frame * CFrame.new(0, TOP_Y - 0.4, 0), EMBER_SIZE),
		self.light,
		NumberRange.new(1.5, 3.5),
		0.1
	)
	embers.Acceleration = Vector3.new(0, 1.5, 0)
	embers.Lifetime = NumberRange.new(0.8, 1.6)
	embers.SpreadAngle = Vector2.new(15, 15)
	embers.Drag = 0.5
	self.embers = embers

	-- Colonne de lumière, du dessus de la caisse vers le haut ; elle grandit depuis la caisse (attache du haut)
	local column = holder(folder, "Column", params.frame * CFrame.new(0, TOP_Y - 0.3, 0))
	local base = Instance.new("Attachment")
	base.Parent = column
	local head = Instance.new("Attachment")
	head.Position = Vector3.new(0, COLUMN_HEIGHT, 0)
	head.Parent = column
	self.columnHead = head
	self.columns = {} :: { { beam: Beam, w0: number, w1: number, base: number } }
	for _, layer in COLUMN_LAYERS do
		local beam = ribbon(column, base, head, self.light, params.beamTexture)
		table.insert(self.columns, { beam = beam, w0 = layer[1], w1 = layer[2], base = layer[3] })
	end

	-- Arme et silhouette : même pose, l'une ou l'autre visible ; tournées de profil vers la caméra
	local center = params.frame.Position
	local toward = Vector3.new(params.facing.X - center.X, 0, params.facing.Z - center.Z)
	self.facing = CFrame.lookAt(Vector3.zero, if toward.Magnitude > 0.01 then toward else Vector3.zAxis).Rotation
	-- `lookAt` tourne -Z vers la cible : on veut la face du profil (+Z du repère de l'arme) vers la caméra
	self.facing *= CFrame.Angles(0, math.pi, 0)
	local weaponCenter = params.frame * Vector3.new(0, WEAPON_HOVER, 0)
	local keyFrom = weaponCenter:Lerp(params.facing, 0.6) + Vector3.new(0, 1.5, 0)
	local key = Instance.new("SpotLight")
	key.Face = Enum.NormalId.Front
	key.Color = Color3.fromRGB(255, 236, 214)
	key.Range = KEY_RANGE
	key.Angle = KEY_ANGLE
	key.Brightness = 0
	key.Parent = holder(folder, "KeyLight", CFrame.lookAt(keyFrom, weaponCenter))
	self.key = key
	self.weapon = params.weapon
	self.weaponOffset = params.weaponAt:ToObjectSpace(params.weapon:GetPivot())
	self.weaponParts = {} :: { BasePart }
	for _, part in params.weapon:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("RevealTransparency", part.Transparency)
			part.Transparency = 1
			table.insert(self.weaponParts, part)
		end
	end
	params.weapon.Parent = folder
	self.silhouette = silhouetteOf(params.weapon, Color3.new(1, 1, 1))
	self.silhouette.Parent = folder
	self.silhouetteParts = {} :: { BasePart }
	for _, part in self.silhouette:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(self.silhouetteParts, part)
		end
	end
	self.revealed = false
	self:_setTier(1)
	return self
end

-- Cette méthode permet de passer toute la lumière de l'ouverture (lampes, rubans, étincelles, néons, silhouette) à la
-- couleur du palier `tier` lorsque la montée de couleur franchit un palier.
function CrateOpening:_setTier(tier: number)
	self.tier = tier
	local color = self.colors[tier] or Color3.new(1, 1, 1)
	-- Plus claire en lumière (le gris du commun sortait terne), plus sombre en néon (sinon il sature en blanc)
	self.light = color:Lerp(Color3.new(1, 1, 1), 0.35)
	self.neon = self.light:Lerp(Color3.new(0, 0, 0), 1 - INTERIOR_NEON)
	local sequence = ColorSequence.new(self.light)
	self.inner.Color = self.light
	self.flashLight.Color = self.light
	self.floor.Color = self.neon
	-- Nappes de la fente presque dans la couleur pure : éclaircies comme la lampe, le bleu y sortait blanc
	local rays = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.1))
	for _, beam in self.rays do
		beam.Color = rays
	end
	for _, layer in self.columns do
		layer.beam.Color = sequence
	end
	self.crackle.Color = sequence
	self.burst.Color = sequence
	self.embers.Color = sequence
	-- Silhouette dans la couleur pure du palier : éclaircie, le néon saturait en blanc et la montée ne s'y voyait pas
	local glow = color
	for _, part in self.silhouetteParts do
		part.Color = glow
	end
end

-- Cette méthode permet de poser la caisse (secousses) et le couvercle (en place, ou en vol jusqu'à l'arrière du socle)
-- lorsque l'image de l'ouverture est rendue.
function CrateOpening:_poseCrate(state: Rules.State, t: number)
	local shake = CFrame.new(0, LIFT_HEIGHT * state.lift, 0)
	if state.shake > 0 then
		local x, y, r = Rules.jitter(t)
		-- secousses plus fortes pendant la tension (la caisse soulevée)
		local a = state.shake * (1 + TENSION_SHAKE * Rules.tension(t))
		shake *= CFrame.new(x * SHAKE_MOVE * a, math.abs(y) * SHAKE_LIFT * a, 0) * CFrame.Angles(
			math.rad(y * SHAKE_TILT * a),
			0,
			math.rad(r * SHAKE_TILT * a)
		)
	end
	local base = self.frame * shake
	for _, entry in self.body do
		entry.part.CFrame = base * entry.rel
	end
	self.floor.CFrame = base * self.floorRel
	for _, entry in self.followers do
		entry.part.CFrame = base * entry.rel
	end
	local lidFrame: CFrame
	if state.lid <= 0 then
		lidFrame = base * CFrame.new(0, LID_CENTER_Y, 0)
	else
		local u = state.lid
		local from = Vector3.new(0, LID_CENTER_Y, 0)
		local p = from:Lerp(LID_LANDING, u) + Vector3.new(0, 4 * LID_ARC * u * (1 - u), 0)
		lidFrame = self.frame
			* CFrame.new(p)
			* CFrame.Angles(0, math.rad(LID_YAW * u), 0)
			* CFrame.Angles(math.rad(-180 * u), 0, 0)
	end
	for _, entry in self.lid do
		entry.part.CFrame = lidFrame * entry.rel
	end
end

-- Cette méthode permet de poser l'arme et sa silhouette (montée hors de la caisse, rotation qui ralentit, profil vers
-- la caméra) et de choisir laquelle est visible lorsque l'image de l'ouverture est rendue.
function CrateOpening:_poseWeapon(state: Rules.State)
	local y = WEAPON_LOW + (WEAPON_HOVER - WEAPON_LOW) * state.rise
	local at = CFrame.new(self.frame * Vector3.new(0, y, 0)) * self.facing * CFrame.Angles(0, math.rad(state.spin), 0)
	local pose = at * self.weaponOffset
	self.weapon:PivotTo(pose)
	self.silhouette:PivotTo(pose)
	local shown = state.silhouette > 0 and 1 - state.silhouette or 1
	for _, part in self.silhouetteParts do
		part.Transparency = shown
	end
	if state.revealed ~= self.revealed then
		self.revealed = state.revealed
		for _, part in self.weaponParts do
			local rest = part:GetAttribute("RevealTransparency")
			part.Transparency = if state.revealed and type(rest) == "number" then rest else 1
		end
	end
end

-- Cette méthode permet d'appliquer l'état de l'ouverture au temps `t` (lumières, rubans, étincelles, caisse, arme)
-- lorsqu'une image est rendue.
function CrateOpening:update(state: Rules.State, t: number)
	if state.tier ~= self.tier then
		self:_setTier(state.tier)
	end
	local open = state.lid > 0
	if self.interior then
		self.interior.Color = self.interiorColor:Lerp(self.neon, state.glow)
		self.interior.Transparency = if open then 1 else 0
	end
	self.floor.Transparency = if open then 0 else 1
	self.inner.Brightness = INNER_BRIGHTNESS * state.glow
	self.flashLight.Brightness = FLASH_BRIGHTNESS * state.flash
	self.key.Brightness = if state.revealed then KEY_BRIGHTNESS else 0
	self.exposure.Brightness = FLASH_EXPOSURE * state.flash
	self.exposure.TintColor = Color3.new(1, 1, 1):Lerp(self.light, 0.3 * state.flash)
	for _, beam in self.rays do
		setRibbon(beam, 0.2, state.rays)
	end
	self.columnHead.Position = Vector3.new(0, COLUMN_HEIGHT * math.max(state.columnHeight, 0.01), 0)
	for _, layer in self.columns do
		layer.beam.Width0 = layer.w0 * state.columnWidth
		layer.beam.Width1 = layer.w1 * state.columnWidth
		setRibbon(layer.beam, layer.base, state.column)
	end
	self.crackle.Rate = CRACKLE_RATE * state.shake
	self.embers.Rate = EMBER_RATE * state.embers
	for _ in Rules.crossed(Rules.SPARKS, self.lastT, t) do
		self.burst:Emit(SPARK_BURST)
	end
	self.lastT = t
	self:_poseCrate(state, t)
	self:_poseWeapon(state)
end

-- Cette méthode permet de sauter au temps `t` sans relancer les gerbes d'étincelles franchies lorsque le joueur clique
-- pour passer à la révélation.
function CrateOpening:jump(t: number)
	self.lastT = t
	self.crackle.Rate = 0
	self.crackle:Clear()
end

-- Cette méthode permet de retirer tous les effets (dossier, correction de couleur de Lighting) lorsque le joueur quitte
-- la révélation ou le shop ; la caisse du socle est refaite par ShopScene.
function CrateOpening:destroy()
	self.exposure:Destroy()
	self.folder:Destroy()
end

return CrateOpening

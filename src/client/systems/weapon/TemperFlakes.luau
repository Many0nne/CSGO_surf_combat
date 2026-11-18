-- TemperFlakes.luau
-- Écailles d'oxyde de l'effet de tir TREMPE (#566) : à chaque tir, des écailles en losange (TEMPER_FLAKE_IMAGE) sont
-- semées le long du rayon et tombent en refroidissant. Le rayon est coupé en tronçons (TEMPER_FLAKE_SECTIONS) : une
-- écaille part de la couleur du ruban là où elle s'en détache (paille près de la bouche, pourpre plus loin) et finit
-- bleu-gris. Réglages dans ShotEffectRules (TEMPER_FLAKE*). Réserve de TEMPER_FLAKE_EMITTERS jeux d'émetteurs (une pièce
-- invisible par tronçon, ParticleEmitter en volume étiré sur le tronçon), utilisés à tour de rôle : un jeu est posé sur
-- le rayon puis émet d'un coup ; ses écailles restent dans le monde (pas LockedToPart) quand il sert au tir suivant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)

local TemperFlakes = {}

TemperFlakes.INSTANCE_NAME = "TemperFlakes"

-- Un jeu d'émetteurs : une pièce et son émetteur par tronçon du rayon
type Section = { part: BasePart, emitter: ParticleEmitter }
type Emitters = { sections: { Section } }

local pool: { Emitters } = {}
local nextIndex = 1
local folder: Folder? = nil

-- Cette méthode permet de convertir une suite d'étapes { position, { r, g, b } } en ColorSequence lorsqu'un émetteur
-- est créé.
local function colors(stops: { any }): ColorSequence
	local keypoints = {}
	for _, stop in stops do
		table.insert(keypoints, ColorSequenceKeypoint.new(stop[1], Color3.fromRGB(table.unpack(stop[2]))))
	end
	return ColorSequence.new(keypoints)
end

-- Cette méthode permet de créer la pièce invisible (ancrée, sans collision ni requête) et l'émetteur d'un tronçon, aux
-- couleurs `stops`, lorsqu'un jeu d'émetteurs est créé.
local function makeSection(stops: { any }, parent: Instance): Section
	local part = Instance.new("Part")
	part.Name = TemperFlakes.INSTANCE_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 1)
	local size, life, speed =
		ShotEffectRules.TEMPER_FLAKE_SIZE, ShotEffectRules.TEMPER_FLAKE_LIFE, ShotEffectRules.TEMPER_FLAKE_SPEED
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = TemperFlakes.INSTANCE_NAME
	emitter.Texture = ShotEffectRules.TEMPER_FLAKE_IMAGE
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Lifetime = NumberRange.new(life[1], life[2])
	emitter.Speed = NumberRange.new(speed[1], speed[2])
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -ShotEffectRules.TEMPER_FLAKE_GRAVITY, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size[2], size[2] - size[1]),
		NumberSequenceKeypoint.new(1, size[1] * 0.6, size[1] * 0.4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = colors(stops)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-400, 400)
	emitter.LightEmission = ShotEffectRules.TEMPER_LIGHT_EMISSION
	emitter.LightInfluence = 0
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Parent = part
	part.Parent = parent
	return { part = part, emitter = emitter }
end

-- Cette méthode permet de créer un jeu d'émetteurs (un par tronçon) lorsque la réserve se remplit.
local function make(): Emitters
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = TemperFlakes.INSTANCE_NAME
		created.Parent = workspace
		folder = created
	end
	local sections = {}
	for _, stops in ShotEffectRules.TEMPER_FLAKE_SECTIONS do
		table.insert(sections, makeSection(stops, folder :: Folder))
	end
	return { sections = sections }
end

-- Cette méthode permet de semer les écailles d'un tir TREMPE le long du rayon `start` → `finish` lorsqu'il est tracé :
-- le jeu d'émetteurs suivant de la réserve est posé sur le rayon, un tronçon par émetteur, puis chacun émet sa part de
-- temperFlakeCount écailles.
function TemperFlakes.spawn(start: Vector3, finish: Vector3)
	local path = finish - start
	local length = path.Magnitude
	if length < 1e-3 then
		return
	end
	if #pool < ShotEffectRules.TEMPER_FLAKE_EMITTERS then
		table.insert(pool, make())
	end
	local index = (nextIndex - 1) % #pool + 1
	nextIndex += 1
	local slot = pool[index]
	if not slot.sections[1].part.Parent then -- détruit par un tiers : le recréer
		slot = make()
		pool[index] = slot
	end
	local counts = ShotEffectRules.temperFlakeSplit(ShotEffectRules.temperFlakeCount(length))
	local sections = #slot.sections
	for i, section in slot.sections do
		local from = start + path * ((i - 1) / sections)
		local to = start + path * (i / sections)
		section.part.Size = Vector3.new(0.2, 0.2, length / sections)
		section.part.CFrame = CFrame.lookAt((from + to) / 2, to)
		if counts[i] > 0 then
			section.emitter:Emit(counts[i])
		end
	end
end

return TemperFlakes

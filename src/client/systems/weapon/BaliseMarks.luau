-- BaliseMarks.luau
-- Marques de l'effet de tir BALISE (#567) : une boucle zébrée orange et noire tourne à la bouche du canon au tir, puis
-- trois chevrons s'ouvrent autour du point d'impact quand le ruban y arrive (le ruban lui-même est le rayon, tracé par
-- ShotEffects). Réglages dans ShotEffectRules (BALISE_*). Réserve de BALISE_EMITTERS jeux (une pièce invisible et son
-- ParticleEmitter pour la boucle, idem pour la marque), créés au démarrage en tâche de fond (`prewarm`, #606), à défaut
-- au premier besoin, utilisés à tour de rôle : un tir déplace un jeu et émet une
-- particule de chaque ; les particules restent dans le monde (pas LockedToPart) quand le jeu sert au tir suivant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)
local AssetPreload = require(script.Parent.Parent.game.AssetPreload)
local EffectClock = require(script.Parent.Parent.game.EffectClock)

local BaliseMarks = {}

BaliseMarks.INSTANCE_NAME = "BaliseMarks"

type Slot = { ringPart: BasePart, ring: ParticleEmitter, markPart: BasePart, mark: ParticleEmitter }

local pool: { Slot } = {}
local nextIndex = 1
local folder: Folder? = nil

-- Cette méthode permet de créer une pièce invisible (ancrée, sans collision ni requête) et son émetteur d'une seule
-- particule à la fois, émise à la demande, lorsqu'un jeu de la réserve est créé.
local function makeEmitter(texture: string, life: number, parent: Instance): (BasePart, ParticleEmitter)
	local part = Instance.new("Part")
	part.Name = BaliseMarks.INSTANCE_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = BaliseMarks.INSTANCE_NAME
	emitter.Texture = texture
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(life)
	emitter.Speed = NumberRange.new(0)
	-- couleurs de l'image telles quelles : une lumière additive rendrait le noir transparent
	emitter.LightEmission = 0
	emitter.LightInfluence = 0
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Parent = part
	part.Parent = parent
	return part, emitter
end

-- Cette méthode permet de créer un jeu (boucle et marque) lorsque la réserve se remplit.
local function make(): Slot
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = BaliseMarks.INSTANCE_NAME
		created.Parent = workspace
		folder = created
	end
	local parent = folder :: Folder
	local ringPart, ring = makeEmitter(ShotEffectRules.BALISE_RING_IMAGE, ShotEffectRules.BALISE_RING_LIFE, parent)
	local spin = ShotEffectRules.BALISE_RING_SPIN
	ring.RotSpeed = NumberRange.new(spin)
	ring.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	local markPart, mark = makeEmitter(ShotEffectRules.BALISE_MARK_IMAGE, ShotEffectRules.BALISE_MARK_LIFE, parent)
	mark.ZOffset = ShotEffectRules.BALISE_MARK_ZOFFSET
	mark.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	return { ringPart = ringPart, ring = ring, markPart = markPart, mark = mark }
end

-- Cette méthode permet de donner une taille qui passe de `from` à `to` (studs) au fil de la vie d'une particule
-- lorsqu'elle est émise (la boucle se déplie, la marque s'ouvre).
local function grow(from: number, to: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, to) })
end

-- Cette méthode permet de prendre le jeu suivant de la réserve lorsqu'un tir BALISE part (créé au besoin, recréé s'il
-- a été détruit par un tiers).
local function nextSlot(): Slot
	if #pool < ShotEffectRules.BALISE_EMITTERS then
		table.insert(pool, make())
	end
	local index = (nextIndex - 1) % #pool + 1
	nextIndex += 1
	local slot = pool[index]
	if not (slot.ringPart.Parent and slot.markPart.Parent) then
		slot = make()
		pool[index] = slot
	end
	return slot
end

-- Cette méthode permet de remplir la réserve au démarrage du client, depuis une tâche de fond (#606) : le premier tir
-- BALISE ne crée rien ; l'ordre d'usage des jeux reste celui d'un remplissage au fil des tirs.
function BaliseMarks.prewarm()
	while #pool < ShotEffectRules.BALISE_EMITTERS do
		table.insert(pool, make())
		AssetPreload.created(4)
	end
end

-- Cette méthode permet de montrer les marques d'un tir BALISE lorsqu'il part : boucle à la bouche du canon `start`
-- (absente si `withRing` est faux : tireur à la lunette), plus petite chez le tireur (`isLocal`), puis, quand le
-- ruban arrive (BALISE_UNROLL), chevrons autour de l'impact `finish`, à une taille lisible depuis la caméra.
function BaliseMarks.spawn(start: Vector3, finish: Vector3, isLocal: boolean, withRing: boolean)
	local slot = nextSlot()
	if withRing then
		local size = if isLocal then ShotEffectRules.BALISE_RING_SIZE_LOCAL else ShotEffectRules.BALISE_RING_SIZE
		slot.ringPart.CFrame = CFrame.new(start)
		slot.ring.Size = grow(size[1], size[2])
		slot.ring.Rotation = NumberRange.new(math.random() * 360)
		slot.ring.TimeScale = EffectClock.scale()
		slot.ring:Emit(1)
	end
	EffectClock.delay(ShotEffectRules.BALISE_UNROLL, function()
		if not slot.markPart.Parent then
			return
		end
		local camera = workspace.CurrentCamera
		local distance = if camera then (camera.CFrame.Position - finish).Magnitude else 50
		local full = ShotEffectRules.baliseMarkSize(distance)
		slot.markPart.CFrame = CFrame.new(finish)
		slot.mark.Size = grow(full * ShotEffectRules.BALISE_MARK_OPEN, full)
		slot.mark.TimeScale = EffectClock.scale()
		slot.mark:Emit(1)
	end)
end

return BaliseMarks

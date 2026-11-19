-- Éclats d'impact (#467) : quatre fragments effilés sur les diagonales, pointe vers le centre, à ombre noire décalée
-- comme le texte du HUD. Ils jaillissent vers l'extérieur en s'estompant. Dessin du hitmarker, repris autour du crâne
-- de la série de kills (RoundHUD) pour garder le même langage.
-- assets/ui/hud/eclat_hitmarker.png (tools/ui/make_hit_shard.py, Decal 71617191362660) ; ci-dessous l'id de l'image.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local EffectClock = require(script.Parent.Parent.systems.game.EffectClock)

local SHARD_IMAGE = "rbxassetid://85649397588861"
local SHARD_RATIO = 48 / 128 -- hauteur / longueur de l'image
local SHADOW_OFFSET = 1
local SHADOW_TRANSPARENCY = 0.35
-- Diagonales : le réticule en croix de la lunette reste dégagé. Angle en degrés, sens des aiguilles (y vers le bas).
local ANGLES = { 45, 135, 225, 315 }

export type Shards = {
	images: { ImageLabel },
	shadows: { ImageLabel },
	inner: number,
	length: number,
	token: number,
}

local HitShards = {}

-- Cette méthode permet de placer un éclat à une distance du centre lorsqu'il est construit ou qu'il jaillit : son centre
-- est sur la diagonale, à `inner` du centre pour la pointe, ombre décalée vers le bas à droite.
local function shardPosition(angle: number, inner: number, length: number, shadow: boolean): UDim2
	local r = math.rad(angle)
	local d = inner + length / 2
	local offset = if shadow then SHADOW_OFFSET else 0
	return UDim2.fromOffset(math.cos(r) * d + offset, math.sin(r) * d + offset)
end

-- Cette méthode permet de construire les quatre éclats, cachés, autour d'un point lorsqu'un marqueur est créé : `parent`
-- est un cadre de taille nulle posé sur le centre, `inner` la distance de la pointe au centre et `length` la longueur
-- d'un éclat (px).
function HitShards.build(parent: GuiObject, inner: number, length: number, zIndex: number): Shards
	local shards: Shards = { images = {}, shadows = {}, inner = inner, length = length, token = 0 }
	for _, angle in ANGLES do
		for _, shadow in { true, false } do
			local image = UIKit.create("ImageLabel", {
				Name = if shadow then "ShardShadow" else "Shard",
				Image = SHARD_IMAGE,
				ImageColor3 = if shadow then UITheme.Colors.Black else UITheme.Colors.Bone,
				ImageTransparency = 1,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(length, length * SHARD_RATIO),
				Position = shardPosition(angle, inner, length, shadow),
				Rotation = angle, -- base cassée de l'image vers l'extérieur, pointe vers le centre
				ZIndex = if shadow then zIndex else zIndex + 1,
				Parent = parent,
			})
			table.insert(if shadow then shards.shadows else shards.images, image)
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync({ shards.images[1] })
	end)
	return shards
end

-- Cette méthode permet de faire jaillir les éclats lorsqu'une touche (ou un palier de série) est marquée : ils
-- apparaissent pleins à leur place, s'écartent de `spread` px pendant `hold` + la durée de `fade`, et s'estompent après
-- `hold` s. Un nouvel appel remplace le précédent.
function HitShards.burst(shards: Shards, color: Color3, spread: number, hold: number, fade: TweenInfo)
	shards.token += 1
	local token = shards.token
	local travel = TweenInfo.new(hold + fade.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, angle in ANGLES do
		local image, shadow = shards.images[i], shards.shadows[i]
		image.ImageColor3 = color
		image.ImageTransparency = 0
		shadow.ImageTransparency = SHADOW_TRANSPARENCY
		for _, layer in { { image, false }, { shadow, true } } do
			local label, isShadow = layer[1] :: ImageLabel, layer[2] :: boolean
			label.Position = shardPosition(angle, shards.inner, shards.length, isShadow)
			UIKit.tween(
				label,
				travel,
				{ Position = shardPosition(angle, shards.inner + spread, shards.length, isShadow) }
			)
		end
	end
	-- Cette méthode permet d'estomper les éclats lorsque le temps de tenue est écoulé, sauf si un jaillissement plus
	-- récent a pris la main.
	local function fadeOut()
		if token ~= shards.token then
			return
		end
		for i in ANGLES do
			UIKit.tween(shards.images[i], fade, { ImageTransparency = 1 })
			UIKit.tween(shards.shadows[i], fade, { ImageTransparency = 1 })
		end
	end
	if hold > 0 then
		EffectClock.delay(hold, fadeOut)
	else
		fadeOut()
	end
end

return HitShards

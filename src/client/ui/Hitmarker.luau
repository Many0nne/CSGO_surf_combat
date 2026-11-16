-- Hitmarker (#44, dessin #467) : éclats d'impact au centre de l'écran quand le serveur confirme une touche (HitShards),
-- os à ombre noire. Un tir à la tête les affiche en rouge d'impact (#60) ; un kill les fait plus grands, tenus plus
-- longtemps et jaillir plus loin. Chaque touche confirmée joue aussi un tick (HitSound, #402).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local HitSound = require(script.Parent.Parent.systems.audio.HitSound)
local HitShards = require(script.Parent.HitShards)
local UIKit = require(script.Parent.UIKit)

local HIT_COLOR = UITheme.Colors.Bone
local HEADSHOT_COLOR = UITheme.Colors.HitRed

-- px à la résolution de référence (720 px de haut), mis à l'échelle par UIKit.scaledRoot.
local SHARD_INNER = 5 -- distance de la pointe au centre : le centre reste dégagé pour la visée
local SHARD_LENGTH = 15
local HIT_SPREAD = 4
local HIT_HOLD = 0
local KILL_SCALE = 1.35
local KILL_SPREAD = 7
local KILL_HOLD = 0.2
local KILL_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local Hitmarker = {}

local scale: UIScale?
local shards: HitShards.Shards?

-- Cette méthode permet de construire le marqueur, caché, lorsque le client démarre (image préchargée pour la première
-- touche).
local function build()
	local screenGui = UIKit.create("ScreenGui", {
		Name = "Hitmarker",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None, -- centre exact de l'écran, celui de la caméra
		DisplayOrder = 0, -- au-dessus de la lunette (-1)
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local marker = UIKit.frame({
		Name = "Marker",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = UIKit.scaledRoot(screenGui),
	})
	scale = UIKit.create("UIScale", { Parent = marker })
	shards = HitShards.build(marker, SHARD_INNER, SHARD_LENGTH, 1)
end

-- Cette méthode permet de faire jaillir le marqueur lorsqu'une touche est confirmée ; une nouvelle touche relance
-- l'affichage et remplace le fondu en cours. L'annonce d'un kill à la tête vient de KillAnnouncer.
function Hitmarker.show(isKill: boolean, isHeadshot: boolean)
	if not shards then
		build()
	end
	(scale :: UIScale).Scale = if isKill then KILL_SCALE else 1
	local color = if isHeadshot then HEADSHOT_COLOR else HIT_COLOR
	if isKill then
		HitShards.burst(shards :: HitShards.Shards, color, KILL_SPREAD, KILL_HOLD, KILL_FADE)
	else
		HitShards.burst(shards :: HitShards.Shards, color, HIT_SPREAD, HIT_HOLD, UITheme.Motion.Hit)
	end
end

-- Cette méthode permet de construire le marqueur et de le brancher sur la confirmation du serveur lorsque le client
-- démarre.
function Hitmarker.init()
	HitSound.init()
	build()
	NetworkProtocol.getRemote(NetworkProtocol.Names.HIT_CONFIRM).OnClientEvent
		:Connect(function(isKill: boolean, isHeadshot: boolean)
			Hitmarker.show(isKill == true, isHeadshot == true)
			HitSound.play()
		end)
end

return Hitmarker

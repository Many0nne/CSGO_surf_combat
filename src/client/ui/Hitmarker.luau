-- Hitmarker (#44) : X au centre de l'écran quand le serveur confirme une touche, dessiné en Frames dans le style
-- du réticule de la lunette (blanc à contour noir). Un tir à la tête l'affiche en rouge (#60), un kill plus grand.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)

local HIT_COLOR = UITheme.Colors.White
local HEADSHOT_COLOR = UITheme.Colors.Alert
local OUTLINE_COLOR = Color3.new(0, 0, 0)

-- px à la résolution de référence (720 px de haut), mis à l'échelle par UIKit.scaledRoot.
local BRANCH_START = 5
local BRANCH_END = 13
local LINE_THICKNESS = 2
local OUTLINE_THICKNESS = 3
local KILL_SCALE = 1.3
local ROUNDED_ENDS = UDim.new(0.5, 0) -- rayon égal à la moitié de l'épaisseur : bouts entièrement arrondis

-- Les diagonales ne chevauchent pas le réticule en croix de la lunette.
local DIAGONALS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }

-- Ding aigu d'un tir à la tête (Headshot 2 de SilverIllusionist, freesound.org, crédité dans l'écran Infos) :
-- source versionnée dans assets/sounds/Headshot.mp3, publiée par Open Cloud.
local HEADSHOT_SOUND_ID = "rbxassetid://132843349237006"
local HEADSHOT_VOLUME = 0.7

local Hitmarker = {}

local scale: UIScale?
local headshotSound: Sound?
local outlines: { Frame } = {}
local lines: { Frame } = {}

-- Cette méthode permet de construire le marqueur une seule fois lorsque la première touche est confirmée.
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

	local diagonal = math.sqrt(0.5)
	local inner, outer = BRANCH_START * diagonal, BRANCH_END * diagonal
	for _, dir in DIAGONALS do
		local x1, y1, x2, y2 = inner * dir[1], inner * dir[2], outer * dir[1], outer * dir[2]
		local outline = UIKit.line(marker, x1, y1, x2, y2, OUTLINE_THICKNESS, OUTLINE_COLOR)
		outline.BackgroundTransparency = 1
		outline.ZIndex = 1
		UIKit.create("UICorner", { CornerRadius = ROUNDED_ENDS, Parent = outline })
		table.insert(outlines, outline)
		local line = UIKit.line(marker, x1, y1, x2, y2, LINE_THICKNESS, HIT_COLOR)
		line.BackgroundTransparency = 1
		line.ZIndex = 2
		UIKit.create("UICorner", { CornerRadius = ROUNDED_ENDS, Parent = line })
		table.insert(lines, line)
	end
end

-- Cette méthode permet de jouer le ding du tir à la tête lorsque le serveur confirme une touche à la tête ;
-- le son est créé une fois, puis rejoué depuis le début à chaque touche.
local function playHeadshotSound()
	if not headshotSound then
		headshotSound = UIKit.create("Sound", {
			Name = "HeadshotDing",
			SoundId = HEADSHOT_SOUND_ID,
			Volume = HEADSHOT_VOLUME,
			Parent = SoundService,
		}) :: Sound
	end
	local sound = headshotSound :: Sound
	sound.TimePosition = 0
	sound:Play()
end

-- Cette méthode permet d'afficher le marqueur puis de l'estomper lorsqu'une touche est confirmée ;
-- une nouvelle touche relance l'affichage et remplace le fondu en cours. Un tir à la tête joue aussi un ding.
function Hitmarker.show(isKill: boolean, isHeadshot: boolean)
	if not scale then
		build()
	end
	if isHeadshot then
		playHeadshotSound()
	end
	(scale :: UIScale).Scale = if isKill then KILL_SCALE else 1
	local color = if isHeadshot then HEADSHOT_COLOR else HIT_COLOR
	for _, layers in { outlines, lines } do
		for _, layer in layers do
			layer.BackgroundTransparency = 0
			UIKit.tween(layer, UITheme.Motion.Hit, { BackgroundTransparency = 1 })
		end
	end
	for _, line in lines do
		line.BackgroundColor3 = color
	end
end

-- Cette méthode permet de brancher le marqueur sur la confirmation du serveur lorsque le client démarre.
function Hitmarker.init()
	NetworkProtocol.getRemote(NetworkProtocol.Names.HIT_CONFIRM).OnClientEvent
		:Connect(function(isKill: boolean, isHeadshot: boolean)
			Hitmarker.show(isKill == true, isHeadshot == true)
		end)
end

return Hitmarker

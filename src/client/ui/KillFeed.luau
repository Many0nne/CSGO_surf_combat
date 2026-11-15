-- Kill feed (#102) en haut à droite : une ligne par mort (tueur en os, arme en ambre suivie de l'icône du tir à la tête
-- s'il y a lieu, victime en os), la plus récente
-- en haut, HUDRules.KILL_FEED_MAX lignes pendant HUDRules.KILL_FEED_DURATION s. Les lignes où le joueur local est tueur
-- ou victime sont posées sur une bande rouge d'impact droite, comme sa ligne au classement.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local ParticipantRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParticipantRules"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)

local C = UITheme.Colors
local F = UITheme.Fonts

local ROW_HEIGHT = 28
local MARGIN_TOP = 64 -- sous la barre Roblox
local MARGIN_RIGHT = 20
local WIDTH = 420
local NAME_SIZE = 18
local DETAIL_SIZE = 16 -- plancher des textes (UITheme.TextSize.Min, #308)
local SHADOW = 2 -- décalage de l'ombre des textes et de l'icône
local PART_GAP = 10 -- entre tueur, arme et victime (les trois espaces de l'ancienne ligne d'un seul texte)
-- Icône du tir à la tête (#365) après le libellé de l'arme : un peu plus haute que ses lettres, la tête reste lisible
local ICON_SIZE = 20
local ICON_GAP = 4

local KillFeed = {}

local gui: ScreenGui? = nil
local root: Frame? = nil
local list: Frame? = nil
local entries: { HUDRules.KillFeedEntry } = {}

local escape = HUDRules.escapeRichText

-- Cette méthode permet d'écrire un texte en couleur RichText (ou brut, pour l'ombre) lorsqu'un nom est composé.
local function paint(text: string, color: Color3, colored: boolean): string
	if not colored then
		return text
	end
	return string.format('<font color="#%s">%s</font>', color:ToHex(), text)
end

-- Cette méthode permet de composer le nom d'un tueur ou d'une victime lorsqu'une ligne est construite : préfixe BOT
-- atténué devant le nom d'un bot, il se lit sans prendre le pas sur le nom (décision 5 de #133).
local function nameText(text: string, isBot: boolean?, colored: boolean): string
	local painted = paint(escape(text), C.Bone, colored)
	return if isBot then paint(ParticipantRules.BOT_PREFIX, C.Muted, colored) .. " " .. painted else painted
end

-- Cette méthode permet de poser un morceau de ligne (texte à ombre noire, largeur selon le texte) lorsqu'une ligne est
-- construite ; `raw` est le même texte sans couleurs, pour l'ombre que les couleurs RichText écraseraient.
local function linePart(parent: GuiObject, name: string, order: number, text: string, raw: string, size: number)
	local holder = UIKit.frame({
		Name = name,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	})
	local _, shadow = UIKit.shadowedText(holder, {
		Name = "Text",
		RichText = true,
		Text = text,
		FontFace = F.Display,
		TextSize = size,
		TextColor3 = C.Bone,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_HEIGHT),
		ZIndex = 2,
	}, SHADOW)
	shadow.Text = raw
	shadow.ZIndex = 1
end

-- Cette méthode permet de poser les morceaux d'une ligne de droite à gauche (tueur, arme et icône du tir à la tête,
-- victime) lorsqu'elle est affichée ; l'icône remplace le mot « TÊTE » (#365), elle ne passe pas dans un texte RichText.
local function buildLine(line: Frame, entry: HUDRules.KillFeedEntry)
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, PART_GAP),
		Parent = line,
	})
	if entry.killer then
		linePart(
			line,
			"Killer",
			1,
			nameText(entry.killer, entry.killerIsBot, true),
			nameText(entry.killer, entry.killerIsBot, false),
			NAME_SIZE
		)
	end
	local detail, headshot = HUDRules.killDetail(entry.killer, entry.weapon, entry.headshot)
	local weapon = UIKit.frame({
		Name = "Weapon",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_HEIGHT),
		LayoutOrder = 2,
		Parent = line,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ICON_GAP),
		Parent = weapon,
	})
	if detail ~= "" then
		linePart(weapon, "Label", 1, paint(detail, C.Accent, true), detail, DETAIL_SIZE)
	end
	if headshot then
		UIKit.headshotIcon(weapon, ICON_SIZE, SHADOW, { LayoutOrder = 2 })
	end
	linePart(
		line,
		"Victim",
		3,
		nameText(entry.victim, entry.victimIsBot, true),
		nameText(entry.victim, entry.victimIsBot, false),
		NAME_SIZE
	)
end

-- Cette méthode permet de construire une ligne du feed (morceaux à ombre, bande rouge si elle concerne le joueur)
-- lorsque le feed est redessiné.
local function buildRow(parent: Frame, entry: HUDRules.KillFeedEntry, index: number)
	local row = UIKit.frame({
		Name = "Row" .. index,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, (index - 1) * ROW_HEIGHT),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Parent = parent,
	})
	local band = nil
	if entry.mine then
		band = UIKit.frame({
			Name = "MeBand",
			BackgroundColor3 = C.HitRed,
			BackgroundTransparency = 0.2,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 8, 0.5, 0),
			Size = UDim2.fromOffset(0, ROW_HEIGHT - 4),
			Parent = row,
		})
		UIKit.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = band,
		})
	end
	local line = UIKit.frame({
		Name = "Line",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_HEIGHT),
		Parent = row,
	})
	buildLine(line, entry)
	if band then
		-- La largeur de la ligne n'est connue qu'une fois les textes mesurés ; AbsoluteSize compte l'échelle du HUD
		local function fitBand()
			local scale = if root then root:GetAttribute("Scale") or 1 else 1
			band.Size = UDim2.fromOffset(line.AbsoluteSize.X / scale + 40, ROW_HEIGHT - 4)
		end
		fitBand()
		line:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBand)
	end
end

-- Cette méthode permet de redessiner le feed d'après les lignes encore valides lorsqu'une mort arrive ou qu'une ligne
-- expire.
local function render()
	if not list then
		return
	end
	entries = HUDRules.pruneKillFeed(entries, os.clock())
	for _, child in list:GetChildren() do
		child:Destroy()
	end
	for i, entry in entries do
		buildRow(list, entry, i)
	end
end

-- Cette méthode permet de créer le feed (masqué) lorsque le client démarre.
function KillFeed.init()
	local screen = UIKit.create("ScreenGui", {
		Name = "KillFeed",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local scaled = UIKit.scaledRoot(screen, true)
	list = UIKit.frame({
		Name = "List",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN_RIGHT, 0, MARGIN_TOP),
		Size = UDim2.fromOffset(WIDTH, ROW_HEIGHT * HUDRules.KILL_FEED_MAX),
		Parent = scaled,
	})
	root = scaled
	gui = screen
	-- Icône de tête chargée d'avance : chargée à sa première apparition, elle manquerait à la première ligne (#364)
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { UIKit.HEADSHOT_IMAGE })
	end)
end

-- Cette méthode permet d'ajouter une mort au feed lorsque PlayerDied arrive ; la ligne disparaît d'elle-même après
-- KILL_FEED_DURATION.
function KillFeed.add(death: HUDRules.Death)
	local now = os.clock()
	entries = HUDRules.pushKillFeed(entries, {
		killer = death.killer,
		killerIsBot = death.killerIsBot,
		victim = death.victim,
		victimIsBot = death.victimIsBot,
		weapon = death.weapon,
		headshot = death.headshot,
		mine = death.mine,
		at = now,
	}, now)
	render()
	task.delay(HUDRules.KILL_FEED_DURATION + 0.05, render)
end

-- Cette méthode permet d'afficher ou masquer le feed lorsque l'état client change (HUDRules.killFeedVisible) ; masqué,
-- il est vidé pour ne pas montrer d'anciennes morts à la partie suivante.
function KillFeed.setVisible(show: boolean)
	if not gui then
		return
	end
	gui.Enabled = show
	if not show and #entries > 0 then
		entries = {}
		render()
	end
end

return KillFeed

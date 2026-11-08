-- Kill feed (#102) en haut à droite : une ligne par mort (tueur en os, arme en ambre, victime en os), la plus récente
-- en haut, HUDRules.KILL_FEED_MAX lignes pendant HUDRules.KILL_FEED_DURATION s. Les lignes où le joueur local est tueur
-- ou victime sont posées sur une bande rouge d'impact droite, comme sa ligne au classement.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)

local C = UITheme.Colors
local F = UITheme.Fonts

local ROW_HEIGHT = 28
local MARGIN_TOP = 64 -- sous la barre Roblox
local MARGIN_RIGHT = 20
local WIDTH = 420
local NAME_SIZE = 18
local DETAIL_SIZE = 13

local KillFeed = {}

local gui: ScreenGui? = nil
local list: Frame? = nil
local entries: { HUDRules.KillFeedEntry } = {}

-- Cette méthode permet d'échapper un nom de joueur avant de l'insérer dans un texte RichText.
local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Cette méthode permet de composer le texte d'une ligne (en couleurs, ou brut pour l'ombre) lorsqu'elle est affichée.
local function lineText(entry: HUDRules.KillFeedEntry, colored: boolean): string
	local detail = HUDRules.killDetail(entry.killer, entry.weapon, entry.headshot)
	local function paint(text: string, color: Color3, size: number?): string
		local attrs = if colored then string.format(' color="#%s"', color:ToHex()) else ""
		if size then
			attrs ..= string.format(' size="%d"', size)
		end
		return string.format("<font%s>%s</font>", attrs, text)
	end
	local parts = {}
	if entry.killer then
		table.insert(parts, paint(escape(entry.killer), C.Bone))
	end
	table.insert(parts, paint(detail, C.Accent, DETAIL_SIZE))
	table.insert(parts, paint(escape(entry.victim), C.Bone))
	return table.concat(parts, "   ")
end

-- Cette méthode permet de construire une ligne du feed (texte à ombre, bande rouge si elle concerne le joueur) lorsque
-- le feed est redessiné.
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
	local label, shadow = UIKit.shadowedText(row, {
		Name = "Line",
		RichText = true,
		Text = lineText(entry, true),
		FontFace = F.Display,
		TextSize = NAME_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(1, 1),
	}, 2)
	-- Ombre en texte brut : les couleurs RichText écraseraient son noir
	shadow.Text = lineText(entry, false)
	if band then
		-- La largeur du texte n'est connue qu'une fois le texte mesuré
		local function fitBand()
			band.Size = UDim2.fromOffset(label.TextBounds.X + 40, ROW_HEIGHT - 4)
		end
		fitBand()
		label:GetPropertyChangedSignal("TextBounds"):Connect(fitBand)
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
	local root = UIKit.scaledRoot(screen)
	list = UIKit.frame({
		Name = "List",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN_RIGHT, 0, MARGIN_TOP),
		Size = UDim2.fromOffset(WIDTH, ROW_HEIGHT * HUDRules.KILL_FEED_MAX),
		Parent = root,
	})
	gui = screen
end

-- Cette méthode permet d'ajouter une mort au feed lorsque PlayerDied arrive ; la ligne disparaît d'elle-même après
-- KILL_FEED_DURATION.
function KillFeed.add(killer: string?, victim: string, weapon: string?, headshot: boolean, mine: boolean)
	local now = os.clock()
	entries = HUDRules.pushKillFeed(entries, {
		killer = killer,
		victim = victim,
		weapon = weapon,
		headshot = headshot,
		mine = mine,
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

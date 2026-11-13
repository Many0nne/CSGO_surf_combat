-- Fiche de statistiques de l'accueil (#301, docs/ui.md) : bloc discret en bas au centre, sous les pieds du personnage,
-- sur un fondu de bord. Une colonne par chiffre (os à ombre) avec son libellé ambré dessous : KILLS, MORTS, K/M, ROUNDS,
-- VICTOIRES. Lit l'attribut informatif `PlayerStats` du Player (StatsStore) : absent (chargement en cours ou en échec),
-- « — » partout plutôt que des zéros. Les kills sur bots ne comptent pas (ParticipantRules.killCountsInStats).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatsRules = require(Shared:WaitForChild("StatsRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local HUDRules = require(script.Parent.HUDRules)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local StatsCard = {}

-- Mise en page (px à 720 de haut)
-- Marge sous la fiche : au-dessus de l'aide en bas à droite de l'écran d'équipement, que la fiche chevaucherait en
-- largeur sur un écran plus étroit que 16:9
local BOTTOM = 48
local COLUMN_WIDTH = 84
local COLUMN_GAP = 18
local VALUE_SIZE = 28
local LABEL_Y = 32
local HEIGHT = 52
-- Fondu de bord sous la fiche (sol clair possible selon la map) ; il s'arrête sous les barres de la fiche d'arme
local SCRIM_SIZE = Vector2.new(620, 110)
local SCRIM_TRANSPARENCY = 0.45
-- Colonnes, de gauche à droite : champ de HUDRules.StatsView et libellé
local COLUMNS = {
	{ key = "kills", label = "KILLS" },
	{ key = "deaths", label = "MORTS" },
	{ key = "ratio", label = "K/M" },
	{ key = "roundsPlayed", label = "ROUNDS" },
	{ key = "roundsWon", label = "VICTOIRES" },
}

-- Chiffre et ombre de chaque colonne, par champ de la vue
local values: { [string]: { TextLabel } } = {}

-- Cette méthode permet de remplir les colonnes avec l'attribut du joueur lorsque la fiche est construite ou que le
-- serveur republie ses statistiques.
local function refresh()
	local view = HUDRules.statsView(StatsRules.decode(Players.LocalPlayer:GetAttribute(StatsRules.ATTRIBUTE)))
	for key, labels in values do
		local text = (view :: any)[key]
		for _, label in labels do
			label.Text = text
		end
	end
end

-- Cette méthode permet de construire une colonne (chiffre os à ombre, libellé ambré dessous) lorsque la fiche est
-- construite.
local function buildColumn(parent: GuiObject, key: string, label: string, order: number)
	local column = UIKit.frame({
		Name = key,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN_WIDTH, HEIGHT),
		Parent = parent,
	})
	local centered = Enum.TextXAlignment.Center
	local value, shadow = UIKit.shadowedText(column, {
		Name = "Value",
		Text = HUDRules.STATS_UNKNOWN,
		FontFace = F.Display,
		TextSize = VALUE_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = centered,
		Size = UDim2.fromOffset(COLUMN_WIDTH, VALUE_SIZE + 2),
		ZIndex = 2,
	}, 2)
	values[key] = { value, shadow }
	UIKit.accentLabel(column, {
		Name = "Label",
		Text = label,
		TextXAlignment = centered,
		Position = UDim2.fromOffset(0, LABEL_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 18),
	})
end

-- Cette méthode permet de construire la fiche en bas au centre de l'accueil lorsque le menu est initialisé, puis de la
-- tenir à jour à chaque changement de l'attribut `PlayerStats`.
function StatsCard.build(parent: GuiObject)
	UIKit.cornerScrim(parent, "Bottom", SCRIM_SIZE, SCRIM_TRANSPARENCY)
	local card = UIKit.frame({
		Name = "StatsCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, HEIGHT),
		Parent = parent,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, COLUMN_GAP),
		Parent = card,
	})
	for i, column in COLUMNS do
		if i > 1 then
			-- Filet entre deux colonnes, comme entre les onglets
			UIKit.frame({
				Name = "Separator",
				LayoutOrder = 2 * i - 1,
				Size = UDim2.fromOffset(1, 30),
				BackgroundColor3 = C.TextSoft,
				BackgroundTransparency = 0.7,
				Parent = card,
			})
		end
		buildColumn(card, column.key, column.label, 2 * i)
	end
	refresh()
	Players.LocalPlayer:GetAttributeChangedSignal(StatsRules.ATTRIBUTE):Connect(refresh)
end

return StatsCard

-- Fiche de statistiques de l'accueil (#301, docs/ui.md) : bloc discret en bas à droite (#308), sous les pieds du
-- personnage, sur un fond de coin. Une colonne par chiffre (os à ombre) avec son libellé ambré dessous : KILLS, MORTS, K/M, ROUNDS,
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
-- En bas à droite depuis #308, sous les pieds du personnage (la grille d'équipement occupe la gauche)
local BOTTOM = 28
local RIGHT = 28
local COLUMN_WIDTH = 84
local COLUMN_GAP = 18
local VALUE_SIZE = 28
local LABEL_Y = 32
local HEIGHT = 52
-- Fond de coin sous la fiche (sol clair possible selon la map)
local SCRIM_SIZE = Vector2.new(640, 150)
local SCRIM_TRANSPARENCY = 0.45
-- Colonnes, de gauche à droite : nom de l'instance, libellé, et texte lu dans la vue (HUDRules.StatsView)
type Column = { name: string, label: string, text: (HUDRules.StatsView) -> string }
local COLUMNS: { Column } = {
	{
		name = "Kills",
		label = "KILLS",
		text = function(v)
			return v.kills
		end,
	},
	{
		name = "Deaths",
		label = "MORTS",
		text = function(v)
			return v.deaths
		end,
	},
	{
		name = "Ratio",
		label = "K/M",
		text = function(v)
			return v.ratio
		end,
	},
	{
		name = "RoundsPlayed",
		label = "ROUNDS",
		text = function(v)
			return v.roundsPlayed
		end,
	},
	{
		name = "RoundsWon",
		label = "VICTOIRES",
		text = function(v)
			return v.roundsWon
		end,
	},
}

-- Chiffre et ombre de chaque colonne, dans l'ordre de COLUMNS
local values: { { TextLabel } } = {}

-- Cette méthode permet de remplir les colonnes avec l'attribut du joueur lorsque la fiche est construite ou que le
-- serveur republie ses statistiques.
local function refresh()
	local view = HUDRules.statsView(StatsRules.decode(Players.LocalPlayer:GetAttribute(StatsRules.ATTRIBUTE)))
	for i, column in COLUMNS do
		local text = column.text(view)
		for _, label in values[i] do
			label.Text = text
		end
	end
end

-- Cette méthode permet de construire une colonne (chiffre os à ombre, libellé ambré dessous) lorsque la fiche est
-- construite.
local function buildColumn(parent: GuiObject, index: number, spec: Column)
	local column = UIKit.frame({
		Name = spec.name,
		LayoutOrder = 2 * index,
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
	values[index] = { value, shadow }
	UIKit.accentLabel(column, {
		Name = "Label",
		Text = spec.label,
		TextXAlignment = centered,
		Position = UDim2.fromOffset(0, LABEL_Y),
		Size = UDim2.fromOffset(COLUMN_WIDTH, 18),
	})
end

-- Cette méthode permet de construire la fiche en bas à droite de l'accueil lorsque le menu est initialisé, puis de la
-- tenir à jour à chaque changement de l'attribut `PlayerStats`.
function StatsCard.build(parent: GuiObject)
	UIKit.cornerScrim(parent, "BottomRight", SCRIM_SIZE, SCRIM_TRANSPARENCY)
	local card = UIKit.frame({
		Name = "StatsCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -RIGHT, 1, -BOTTOM),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, HEIGHT),
		Parent = parent,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
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
		buildColumn(card, i, column)
	end
	refresh()
	Players.LocalPlayer:GetAttributeChangedSignal(StatsRules.ATTRIBUTE):Connect(refresh)
end

return StatsCard

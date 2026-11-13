-- Gabarit des écrans secondaires du menu (Réglages, Infos, Feedback, menu en partie) : pas de panneau, le contenu est un
-- bloc centré posé à même la scène sur un voile qui s'efface vers les côtés. De haut en bas : titre, onglets en boîte
-- (`page.tabs`, #308), contenu, puis les actions en texte à ombre décalée en bas au centre (`page.action`). Seul l'écran
-- d'équipement tient à gauche (le personnage y tient l'arme choisie) : essayé ici en #308, refusé, la droite restait vide.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local Rules = require(script.Parent.Parent.systems.game.MenuSceneRules)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local MenuPage = {}

-- Cotes de la colonne de gauche de l'accueil (px à la hauteur de référence de 720), reprises par l'écran d'équipement
MenuPage.Edge = 28 -- marge gauche
MenuPage.GameTitleY = 46 -- titre du jeu, sous les boutons Roblox du coin haut gauche
MenuPage.TitleY = 108 -- grand titre de l'écran d'équipement
MenuPage.TitleSize = 52
-- Cotes du bloc centré des écrans secondaires
MenuPage.BlockWidth = 780
MenuPage.PageTitleY = 100 -- sous les onglets du menu, ou sous le timer du round en partie (bloc de 10 à 94 px, #220)
MenuPage.TabsY = 152 -- onglets en boîte, sous le titre
MenuPage.ContentTop = 204
MenuPage.ContentBottom = 636 -- le contenu s'arrête au-dessus des actions
MenuPage.HintBottom = 18 -- aide de touches au bas de l'écran (menu en partie)

local TOPBAR_GAP = 8 -- marge entre la barre de Roblox et le titre du jeu quand la colonne doit descendre (#306)
local PAGE_TITLE_SIZE = 40
local ACTION_SIZE = 30
local ACTION_GAP = 46
local ACTIONS_BOTTOM = 34
local VEIL_WIDTH = 1100 -- voile qui s'efface vers les côtés, comme le classement
local VEIL_TRANSPARENCY = 0.18

export type ChoiceProps = {
	text: string,
	size: number?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
	action: () -> (),
}

export type Page = {
	gui: ScreenGui,
	group: Frame,
	block: Frame,
	choice: (props: ChoiceProps) -> MenuShot.Choice,
	action: (text: string, action: () -> ()) -> MenuShot.Choice,
	tabs: (labels: { string }, onSelect: (number) -> ()) -> (number) -> (),
	show: () -> (),
	hide: () -> (),
}

-- Cette méthode permet de descendre une colonne de gauche de l'accueil (titre du jeu, écran d'équipement) sous la barre
-- de Roblox lorsque l'échelle de l'écran ou la hauteur de cette barre change (#306) : elle reste en px réels, l'interface non.
function MenuPage.followTopbar(root: Frame, column: Frame)
	local function update()
		local scale = root:GetAttribute("Scale") or 1
		local shift = Rules.topbarShift(GuiService.TopbarInset.Max.Y, scale, MenuPage.GameTitleY, TOPBAR_GAP)
		column.Position = UDim2.fromOffset(0, shift)
	end
	update()
	root:GetAttributeChangedSignal("Scale"):Connect(update)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(update)
end

-- Cette méthode permet de poser le voile central (sombre au milieu, effacé vers les côtés) d'un écran secondaire lorsqu'il
-- s'initialise.
local function buildVeil(root: Frame)
	local veil = UIKit.frame({
		Name = "Veil",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, VEIL_WIDTH, 1, 0),
		BackgroundColor3 = C.Scrim,
		ZIndex = 0,
		Parent = root,
	})
	UIKit.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.26, VEIL_TRANSPARENCY),
			NumberSequenceKeypoint.new(0.74, VEIL_TRANSPARENCY),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = veil,
	})
end

-- Cette méthode permet de construire le fond d'un écran secondaire (voile, bloc centré, titre) lorsqu'il s'initialise.
function MenuPage.new(name: string, displayOrder: number, title: string): Page
	local gui = UIKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = UIKit.scaledRoot(gui)
	buildVeil(root)
	local group = UIKit.create("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	-- Bloc centré : les positions du contenu des écrans sont relatives à lui
	local block = UIKit.frame({
		Name = "Block",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, MenuPage.BlockWidth, 1, 0),
		Parent = group,
	})
	UIKit.shadowedText(block, {
		Name = "Title",
		Text = title,
		FontFace = F.Display,
		TextSize = PAGE_TITLE_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, MenuPage.PageTitleY),
		Size = UDim2.new(1, 0, 0, PAGE_TITLE_SIZE + 6),
		ZIndex = 2,
	}, 3)
	local choices: { MenuShot.Choice } = {}
	local actions: Frame?

	local page = { gui = gui, group = group, block = block }

	-- Cette méthode permet d'ajouter un choix en texte (os au repos, os vif une fois choisi, rouge d'impact au survol) à
	-- l'écran lorsque celui-ci doit remettre son survol à zéro en changeant de page.
	function page.choice(props: ChoiceProps): MenuShot.Choice
		local created = MenuShot.textChoice({
			text = props.text,
			font = F.Display,
			size = props.size or 24,
			color = C.TextSoft,
			selectedColor = C.Bone,
			position = props.position,
			anchor = props.anchor,
			layoutOrder = props.layoutOrder,
			parent = props.parent or block,
			action = props.action,
		})
		table.insert(choices, created)
		return created
	end

	-- Cette méthode permet d'ajouter une action (RÉTABLIR, RETOUR, ENVOYER…) à la ligne du bas, au centre, lorsque
	-- l'écran est construit ; elles se suivent dans l'ordre des appels, l'action principale en dernier.
	function page.action(text: string, action: () -> ()): MenuShot.Choice
		local row = actions
		if not row then
			row = UIKit.frame({
				Name = "Actions",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -ACTIONS_BOTTOM),
				Size = UDim2.fromOffset(MenuPage.BlockWidth, ACTION_SIZE + 10),
				Parent = group,
			})
			UIKit.create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, ACTION_GAP),
				Parent = row,
			})
			actions = row
		end
		return page.choice({
			text = text,
			size = ACTION_SIZE,
			layoutOrder = #row:GetChildren(),
			parent = row,
			action = action,
		})
	end

	-- Cette méthode permet de poser les onglets en boîte, centrés sous le titre (actif en boîte ambrée, #308), lorsque
	-- l'écran a des catégories ; `onSelect(index)` est appelé au clic, la fonction renvoyée marque l'onglet actif.
	function page.tabs(labels: { string }, onSelect: (number) -> ()): (number) -> ()
		local row = UIKit.frame({
			Name = "Tabs",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, MenuPage.TabsY),
			Size = UDim2.new(1, 0, 0, 30),
			Parent = block,
		})
		UIKit.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			Parent = row,
		})
		local created: { MenuShot.Choice } = {}
		for index, label in labels do
			created[index] = MenuShot.boxChoice({
				text = label,
				layoutOrder = index,
				parent = row,
				action = function()
					onSelect(index)
				end,
			})
			table.insert(choices, created[index])
		end
		return function(active: number)
			for index, tab in created do
				tab.setSelected(index == active)
			end
		end
	end

	-- Cette méthode permet d'afficher l'écran en fondu lorsqu'il s'ouvre.
	function page.show()
		gui.Enabled = true
		UIKit.reveal(group, 0, 14)
	end

	-- Cette méthode permet de masquer l'écran et de relâcher ses survols lorsqu'il se ferme.
	function page.hide()
		gui.Enabled = false
		for _, created in choices do
			created.reset()
		end
	end

	return page :: any
end

return MenuPage

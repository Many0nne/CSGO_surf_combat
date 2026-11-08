-- Gabarit des écrans secondaires du menu (Réglages, Infos, Feedback) : pas de panneau, le contenu est posé à même la scène
-- sur un dégradé sombre à gauche, sous les onglets de l'accueil (sous un titre en image pour Réglages en partie), avec une
-- action de sortie en bas à gauche.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuCursor = require(script.Parent.MenuCursor)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local L = UITheme.Layout

local MenuPage = {}

-- Images publiées sur Roblox (sources : assets/ui/menu/)
-- stylua: ignore
MenuPage.Words = {
	Infos     = { image = "rbxassetid://132978783370855", width = 387, height = 136 },
	Reglages  = { image = "rbxassetid://134350858698628", width = 601, height = 168 },
	Feedback  = { image = "rbxassetid://114862354195227", width = 635, height = 149 },
	Surfer    = { image = "rbxassetid://84010579642000",  width = 520, height = 138 },
	Commandes = { image = "rbxassetid://77773685751565",  width = 823, height = 138 },
	Credits   = { image = "rbxassetid://100034354187500", width = 494, height = 169 },
	APropos   = { image = "rbxassetid://104908705930354", width = 578, height = 166 },
	Retour    = { image = "rbxassetid://118226314006213", width = 548, height = 136 },
	Envoyer   = { image = "rbxassetid://125140269715556", width = 517, height = 135 },
	Annuler   = { image = "rbxassetid://113586882195068", width = 560, height = 134 },
}

-- Colonne commune (px à la hauteur de référence de 720) : les images débordent à gauche à cause de leurs éclats
MenuPage.WordX = L.Margin - 26
MenuPage.TextX = L.Margin
MenuPage.ContentTop = 150

local TITLE_Y = 34
local TITLE_HEIGHT = 96
local EXIT_Y = 636
local EXIT_HEIGHT = 44
local SCRIM_WIDTH = 0.74

export type Page = {
	gui: ScreenGui,
	group: CanvasGroup,
	choice: (props: { [string]: any }) -> MenuShot.Choice,
	exit: (word: MenuShot.Word, action: () -> (), shoots: (() -> boolean)?) -> MenuShot.Choice,
	show: (withTitle: boolean?) -> (),
	hide: () -> (),
}

-- Cette méthode permet de construire le fond d'un écran secondaire (dégradé, titre, calque d'impacts) lorsqu'il s'initialise.
function MenuPage.new(name: string, displayOrder: number, title: MenuShot.Word): Page
	local gui = UIKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local scrim = UIKit.frame({
		Name = "Scrim",
		Size = UDim2.fromScale(SCRIM_WIDTH, 1),
		BackgroundColor3 = C.Scrim,
		ZIndex = 0,
		Parent = gui,
	})
	UIKit.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(0.6, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = scrim,
	})
	local group = UIKit.create("CanvasGroup", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = UIKit.scaledRoot(gui),
	})
	local titleLabel = UIKit.create("ImageLabel", {
		Name = "Title",
		Image = title.image,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(MenuPage.WordX, TITLE_Y),
		Size = UDim2.fromOffset(math.round(TITLE_HEIGHT * title.width / title.height), TITLE_HEIGHT),
		Parent = group,
	})
	local holes = MenuShot.createLayer(gui)
	local choices: { MenuShot.Choice } = {}

	local page = { gui = gui, group = group }

	-- Cette méthode permet d'ajouter un choix à l'écran lorsque celui-ci doit remettre son survol à zéro en changeant de page.
	function page.choice(props: { [string]: any }): MenuShot.Choice
		props.parent = props.parent or group
		local created = MenuShot.choice(props :: any)
		table.insert(choices, created)
		return created
	end

	-- Cette méthode permet de poser l'action de sortie (RETOUR, ANNULER) à son emplacement commun lorsque l'écran est construit.
	function page.exit(word: MenuShot.Word, action: () -> (), shoots: (() -> boolean)?): MenuShot.Choice
		return page.choice({
			word = word,
			height = EXIT_HEIGHT,
			position = UDim2.fromOffset(MenuPage.WordX, EXIT_Y),
			action = action,
			shoots = shoots,
		})
	end

	-- Cette méthode permet d'afficher l'écran en fondu et de lui rediriger les impacts lorsqu'il s'ouvre ; au menu, les
	-- onglets de l'accueil restent affichés et l'onglet actif sert de titre, `withTitle` ne sert qu'en partie (touche P).
	function page.show(withTitle: boolean?)
		titleLabel.Visible = withTitle == true
		MenuShot.useLayer(holes)
		gui.Enabled = true
		UIKit.reveal(group, 0, 14)
	end

	-- Cette méthode permet de masquer l'écran et de relâcher ses survols lorsqu'il se ferme.
	function page.hide()
		gui.Enabled = false
		for _, created in choices do
			created.reset()
		end
		MenuCursor.resetHover()
	end

	return page :: any
end

return MenuPage

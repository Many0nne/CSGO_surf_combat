-- Gabarit des écrans secondaires du menu (Réglages, Infos, Feedback) : pas de panneau, le contenu est un bloc centré posé
-- à même la scène sur un voile qui s'efface vers les côtés, sous les onglets de l'accueil (sous un titre en texte pour
-- Réglages en partie), avec les actions de sortie en bas au centre. Tous les choix sont en texte à ombre décalée
-- (`MenuShot.textChoice`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local MenuPage = {}

-- Cotes communes (px à la hauteur de référence de 720)
MenuPage.ContentTop = 150
MenuPage.ExitY = 632 -- ligne des actions de sortie (RETOUR, ANNULER…)

-- Titre montré en partie seulement (menu en partie et ses Réglages) : sous le timer du round (RoundHUD, bloc de 10 à
-- 90 px, texte jusqu'à 78), qui reste visible au-dessus du menu (#220), et au-dessus du contenu (ContentTop)
local TITLE_Y = 92
local TITLE_SIZE = 34
local EXIT_Y = MenuPage.ExitY
local EXIT_SIZE = 30
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
	choice: (props: ChoiceProps) -> MenuShot.Choice,
	exit: (text: string, action: () -> ()) -> MenuShot.Choice,
	show: (withTitle: boolean?) -> (),
	hide: () -> (),
}

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

-- Cette méthode permet de construire le fond d'un écran secondaire (voile, titre) lorsqu'il s'initialise.
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
	local titleFrame = UIKit.frame({
		Name = "Title",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TITLE_Y),
		Size = UDim2.fromOffset(400, TITLE_SIZE + 8),
		Visible = false,
		Parent = group,
	})
	UIKit.shadowedText(titleFrame, {
		Name = "Title",
		Text = title,
		FontFace = F.Display,
		TextSize = TITLE_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, 3)
	local choices: { MenuShot.Choice } = {}

	local page = { gui = gui, group = group }

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
			parent = props.parent or group,
			action = props.action,
		})
		table.insert(choices, created)
		return created
	end

	-- Cette méthode permet de poser l'action de sortie (RETOUR, ANNULER) à son emplacement commun lorsque l'écran est construit.
	function page.exit(text: string, action: () -> ()): MenuShot.Choice
		return page.choice({
			text = text,
			size = EXIT_SIZE,
			position = UDim2.new(0.5, 0, 0, EXIT_Y),
			anchor = Vector2.new(0.5, 0),
			action = action,
		})
	end

	-- Cette méthode permet d'afficher l'écran en fondu lorsqu'il s'ouvre ; au menu, les
	-- onglets de l'accueil restent affichés et l'onglet actif sert de titre, `withTitle` ne sert qu'en partie (touche P).
	function page.show(withTitle: boolean?)
		titleFrame.Visible = withTitle == true
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

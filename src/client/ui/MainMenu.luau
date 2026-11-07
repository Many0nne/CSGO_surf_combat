-- Menu principal (direction « Ligne de mire ») : on choisit en tirant. Le curseur est un hitmarker, l'AWP de MenuScene
-- le suit, et les libellés sont des images usées (tools/ui/make_menu_type.py). Infos, Réglages et Feedback sont des
-- ScreenGui à part (MenuPage), posés sur la même scène et fermés par leur propre action.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local MenuCursor = require(script.Parent.MenuCursor)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local L = UITheme.Layout

export type Page = "home" | "infos" | "settings" | "feedback"

local MainMenu = {}

-- Images publiées sur Roblox (sources : assets/ui/menu/, largeur et hauteur en px pour garder les proportions)
local TITLE = { image = "rbxassetid://118051067256604", width = 1024, height = 369 }
local TITLE_HEIGHT = 240
local ITEMS = {
	{ key = "play", image = "rbxassetid://92275875634869", width = 892, height = 277, y = 372, h = 122 },
	{ key = "infos", image = "rbxassetid://132978783370855", width = 387, height = 136, y = 504, h = 46 },
	{ key = "settings", image = "rbxassetid://134350858698628", width = 601, height = 168, y = 556, h = 50 },
	{ key = "feedback", image = "rbxassetid://114862354195227", width = 635, height = 149, y = 612, h = 44 },
}
local PLAY_DELAY = 1.3 -- la plongée vers le soleil se voit longuement avant les volets

local gui: ScreenGui
local content: Frame
local holes: Frame
local choices: { MenuShot.Choice } = {}
local callbacks: { [string]: (() -> ())? } = {}
local currentPage: Page = "home"

-- Cette méthode permet d'appeler un rappel enregistré lorsqu'un choix du menu est confirmé.
local function fire(name: string)
	local fn = callbacks[name]
	if fn then
		fn()
	end
end

-- Cette méthode permet de créer un libellé-image à tirer lorsque le menu est construit ; JOUER lance en plus la plongée.
local function buildItem(item: { key: string, image: string, width: number, height: number, y: number, h: number })
	local isPlay = item.key == "play"
	table.insert(
		choices,
		MenuShot.choice({
			word = item,
			height = item.h,
			position = UDim2.fromOffset(L.Margin - 26, item.y),
			parent = content,
			action = function()
				fire(item.key)
			end,
			onFired = isPlay and MenuScene.dive or nil,
			delay = isPlay and PLAY_DELAY or nil,
			locks = isPlay,
		})
	)
end

-- Cette méthode permet de construire le titre, les choix et la légende lorsque le menu est initialisé.
local function buildContent(root: Frame)
	content = UIKit.frame({ Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	UIKit.create("ImageLabel", {
		Name = "Title",
		Image = TITLE.image,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(L.Margin - 40, 44),
		Size = UDim2.fromOffset(math.round(TITLE_HEIGHT * TITLE.width / TITLE.height), TITLE_HEIGHT),
		Parent = content,
	})
	for _, item in ITEMS do
		buildItem(item)
	end
	UIKit.text({
		Name = "Caption",
		Text = "Free for all. Rounds de 5 minutes.   v0.1",
		FontFace = F.Body,
		TextSize = T.Body,
		TextColor3 = C.TextSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -L.Margin, 1, -24),
		Size = UDim2.fromOffset(500, 22),
		Parent = content,
	})
end

-- Cette méthode permet de tirer dans la scène lorsque le joueur clique hors des boutons, sur n'importe quel écran du menu.
local function onInputBegan(input: InputObject, processed: boolean)
	if processed or MenuShot.isBusy() then
		return
	end
	local x, y
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		x, y = mouse.X, mouse.Y
	elseif input.UserInputType == Enum.UserInputType.Touch then
		x, y = input.Position.X, input.Position.Y + GuiService:GetGuiInset().Y
	else
		return
	end
	local hasFired, hasHit = MenuScene.shoot(x, y)
	if hasFired then
		MenuCursor.kick(hasHit)
	end
end

-- Touches 1 à 9 : rang de l'arme montrée dans la salle des miroirs
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

-- Cette méthode permet de changer l'arme de la vitrine (molette, touches 1-9) lorsque le joueur est sur l'accueil.
local function onWeaponInput(input: InputObject, processed: boolean)
	if processed or currentPage ~= "home" then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		MenuScene.cycleWeapon(if input.Position.Z > 0 then -1 else 1)
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local index = table.find(NUMBER_KEYS, input.KeyCode)
		if index then
			MenuScene.selectWeapon(index)
		end
	end
end

-- Cette méthode permet d'initialiser le menu et d'enregistrer les rappels lorsque le client démarre ;
-- onSettings et onHome sont optionnels (navigation vers Settings et retour à l'accueil).
function MainMenu.init(
	onPlay: () -> (),
	onInfos: () -> (),
	onFeedback: () -> (),
	onSettings: (() -> ())?,
	onHome: (() -> ())?
)
	callbacks = { play = onPlay, infos = onInfos, feedback = onFeedback, settings = onSettings, home = onHome }

	gui = UIKit.create("ScreenGui", {
		Name = "MainMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	holes = MenuShot.createLayer(gui)
	buildContent(UIKit.scaledRoot(gui))
	MenuCursor.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onInputBegan(input, processed)
			onWeaponInput(input, processed)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onWeaponInput(input, processed)
		end
	end)
end

-- Cette méthode permet de changer la page active (choix visibles sur l'accueil seulement) lorsque l'orchestrateur
-- ouvre un écran secondaire ou revient à l'accueil.
function MainMenu.setPage(page: Page)
	if not gui then
		return
	end
	currentPage = page
	content.Visible = page == "home"
	holes.Visible = page == "home"
	if page == "home" then
		MenuShot.useLayer(holes)
	else
		for _, choice in choices do
			choice.reset()
		end
	end
end

-- Cette méthode permet de lire la page active lorsque l'orchestrateur doit décider où mène une touche.
function MainMenu.getPage(): Page
	return currentPage
end

-- Cette méthode permet d'afficher le menu et de lancer sa scène lorsque le joueur arrive au menu.
function MainMenu.show()
	if not gui then
		return
	end
	if not gui.Enabled then
		MenuShot.reset()
	end
	gui.Enabled = true
	MenuCursor.show()
	MainMenu.setPage("home")
	task.spawn(MenuScene.start)
end

-- Cette méthode permet de masquer le menu, sa scène et le hitmarker lorsque la partie démarre.
function MainMenu.hide()
	if not gui then
		return
	end
	gui.Enabled = false
	MenuCursor.hide()
	for _, choice in choices do
		choice.reset()
	end
	MenuScene.stop()
end

return MainMenu

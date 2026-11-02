-- Menu principal (direction « Ligne de mire ») : on choisit en tirant. Le curseur est un hitmarker, l'AWP de MenuScene
-- le suit, et les libellés sont des images usées (tools/ui/make_menu_type.py). Infos et Settings restent des ScreenGui
-- à part, ouverts par-dessus la scène et fermés par leur propre bouton.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion
local L = UITheme.Layout

export type Page = "home" | "infos" | "settings"

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
local ACTION_DELAY = 0.16 -- l'impact se voit avant l'ouverture de l'écran demandé
local PLAY_DELAY = 1.3 -- la plongée vers le soleil se voit longuement avant les volets
local HOVER_SHIFT = 10
local HOLE_SIZE = 13
local ARM_ANGLES = { 45, 135, 225, 315 }

local gui: ScreenGui
local content: Frame
local holes: Frame
local cursorGui: ScreenGui
local cursor: Frame
local arms: { { frame: Frame, angle: number } } = {}
local callbacks: { [string]: (() -> ())? } = {}
local currentPage: Page = "home"
local connection: RBXScriptConnection?
local hoverCount = 0
local busy = false
local gap, hitScale = 10, 1
local hitUntil = 0

-- Cette méthode permet d'appeler un rappel enregistré lorsqu'un choix du menu est confirmé.
local function fire(name: string)
	local fn = callbacks[name]
	if fn then
		fn()
	end
end

-- Cette méthode permet de savoir si un écran modal (feedback) est ouvert lorsqu'un clic pourrait déclencher un tir.
local function isModalOpen(): boolean
	local modal = Players.LocalPlayer.PlayerGui:FindFirstChild("FeedbackModal")
	return modal ~= nil and (modal :: ScreenGui).Enabled
end

-- Cette méthode permet de laisser un impact de balle à l'écran lorsqu'un tir touche le menu.
local function addHole(x: number, y: number)
	local hole = UIKit.frame({
		Name = "BulletHole",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(HOLE_SIZE, HOLE_SIZE),
		BackgroundColor3 = C.Black,
		Parent = holes,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hole })
	UIKit.create("UIStroke", { Color = C.HitRed, Thickness = 1, Transparency = 0.35, Parent = hole })
end

-- Cette méthode permet de faire réagir le hitmarker lorsqu'un tir part ; il grossit et rougit s'il a touché un surfeur.
local function kickCursor(hasHit: boolean)
	hitScale = hasHit and 2.3 or 1.5
	if hasHit then
		hitUntil = os.clock() + 0.28
	end
end

-- Cette méthode permet de tirer sur un bouton et de déclencher son action après l'impact lorsqu'il est activé.
local function activate(button: ImageButton, key: string, input: InputObject?)
	if busy or currentPage ~= "home" or isModalOpen() then
		return
	end
	local x, y
	local kind = input and input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		x, y = mouse.X, mouse.Y
	else
		-- Tactile ou manette : le tir vise le centre du bouton (AbsolutePosition exclut la barre du haut)
		local top = GuiService:GetGuiInset().Y
		x = button.AbsolutePosition.X + button.AbsoluteSize.X / 2
		y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2 + top
	end
	busy = true
	local _, hasHit = MenuScene.shoot(x, y, true)
	kickCursor(hasHit)
	addHole(x, y)
	if key == "play" then
		MenuScene.dive()
		task.delay(PLAY_DELAY, fire, key)
	else
		task.delay(ACTION_DELAY, function()
			busy = false
			fire(key)
		end)
	end
end

-- Cette méthode permet de créer un libellé-image cliquable avec sa réaction au survol lorsque le menu est construit.
local function buildItem(item: { key: string, image: string, width: number, height: number, y: number, h: number })
	local width = math.round(item.h * item.width / item.height)
	local rest = UDim2.fromOffset(L.Margin - 26, item.y)
	local button = UIKit.create("ImageButton", {
		Name = item.key,
		Image = item.image,
		ImageColor3 = C.White,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = rest,
		Size = UDim2.fromOffset(width, item.h),
		Parent = content,
	})
	button.MouseEnter:Connect(function()
		hoverCount += 1
		UIKit.tween(button, Motion.Hover, {
			ImageColor3 = C.HitRed,
			Position = rest + UDim2.fromOffset(HOVER_SHIFT, 0),
		})
	end)
	button.MouseLeave:Connect(function()
		hoverCount = math.max(0, hoverCount - 1)
		UIKit.tween(button, Motion.Hover, { ImageColor3 = C.White, Position = rest })
	end)
	button.Activated:Connect(function(input: InputObject)
		activate(button, item.key, input)
	end)
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

-- Cette méthode permet de construire le hitmarker qui remplace le curseur lorsque le menu est initialisé.
local function buildCursor()
	cursorGui = UIKit.create("ScreenGui", {
		Name = "MenuCursor",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	cursor =
		UIKit.frame({ Name = "Cursor", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = cursorGui })
	for _, angle in ARM_ANGLES do
		local arm = UIKit.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.White,
			Rotation = angle,
			Parent = cursor,
		})
		UIKit.create("UIStroke", { Color = C.Black, Thickness = 1.2, Parent = arm })
		table.insert(arms, { frame = arm, angle = math.rad(angle) })
	end
end

-- Cette méthode permet de tirer dans la scène lorsque le joueur clique hors des boutons sur la page d'accueil.
local function onInputBegan(input: InputObject, processed: boolean)
	if processed or busy or currentPage ~= "home" or isModalOpen() then
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
		kickCursor(hasHit)
	end
end

-- Cette méthode permet de faire suivre la souris au hitmarker lorsqu'une image est rendue : il se resserre et rougit
-- sur une cible, et le curseur système reste masqué même si un autre écran le réactive en se fermant.
local function updateCursor(dt: number)
	UserInputService.MouseIconEnabled = false
	local mouse = UserInputService:GetMouseLocation()
	cursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	local hover = hoverCount > 0
	gap += ((hover and 4 or 10) - gap) * math.min(1, dt * 22)
	hitScale += (1 - hitScale) * math.min(1, dt * 9)
	local color = (hover or os.clock() < hitUntil) and C.HitRed or C.White
	for _, arm in arms do
		local distance = (gap + 8) * hitScale
		arm.frame.Position = UDim2.fromOffset(math.cos(arm.angle) * distance, math.sin(arm.angle) * distance)
		arm.frame.Size = UDim2.fromOffset(16 * hitScale, 3 * math.max(1, hitScale * 0.7))
		arm.frame.BackgroundColor3 = color
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
	holes = UIKit.frame({
		Name = "Holes",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = gui,
	})
	buildContent(UIKit.scaledRoot(gui))
	buildCursor()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if gui.Enabled then
			onInputBegan(input, processed)
		end
	end)
end

-- Cette méthode permet de changer la page active (choix visibles sur l'accueil seulement) lorsque l'orchestrateur
-- ouvre Infos, Settings ou revient à l'accueil.
function MainMenu.setPage(page: Page)
	if not gui then
		return
	end
	currentPage = page
	content.Visible = page == "home"
	holes.Visible = page == "home"
	if page ~= "home" then
		hoverCount = 0
	end
end

-- Cette méthode permet d'afficher le menu et de lancer sa scène lorsque le joueur arrive au menu.
function MainMenu.show()
	if not gui then
		return
	end
	if not gui.Enabled then
		busy = false
		holes:ClearAllChildren()
	end
	gui.Enabled = true
	cursorGui.Enabled = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
	MainMenu.setPage("home")
	if not connection then
		connection = RunService.RenderStepped:Connect(updateCursor)
	end
	task.spawn(MenuScene.start)
end

-- Cette méthode permet de masquer le menu, sa scène et le hitmarker lorsque la partie démarre.
function MainMenu.hide()
	if not gui then
		return
	end
	gui.Enabled = false
	cursorGui.Enabled = false
	hoverCount = 0
	if connection then
		connection:Disconnect()
		connection = nil
	end
	MenuScene.stop()
end

return MainMenu

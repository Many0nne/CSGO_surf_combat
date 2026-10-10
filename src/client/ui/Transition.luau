-- Volets « DÉPLOIEMENT » entre le menu et le jeu : se ferment au clic sur PLAY,
-- se rouvrent quand le personnage apparaît (ou après un délai de sécurité).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local Motion = UITheme.Motion

-- Délai maximal volets fermés si le spawn n'arrive pas (évite un écran bloqué)
local SAFETY_OPEN_DELAY = 6

local Transition = {}

local gui: ScreenGui
local topPanel: Frame
local bottomPanel: Frame
local label: TextLabel
local labelScale: UIScale
local closed = false
local generation = 0

-- Cette méthode permet de créer un volet (moitié d'écran) et son liseré ambre lorsque la transition est construite.
local function makePanel(root: Frame, isTop: boolean): Frame
	local panel = UIKit.frame({
		Name = isTop and "TopPanel" or "BottomPanel",
		Size = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = C.Ground,
		Parent = root,
	})
	UIKit.frame({
		Name = "Edge",
		Size = UDim2.new(1, 0, 0, 3),
		AnchorPoint = Vector2.new(0, isTop and 1 or 0),
		Position = UDim2.fromScale(0, isTop and 1 or 0),
		BackgroundColor3 = C.Accent,
		Parent = panel,
	})
	return panel
end

-- Cette méthode permet de placer les volets hors écran lorsque la transition est ouverte ou réinitialisée.
local function restOpen()
	topPanel.Position = UDim2.fromScale(0, -0.5)
	bottomPanel.Position = UDim2.fromScale(0, 1)
end

function Transition.init()
	gui = UIKit.create("ScreenGui", {
		Name = "Transition",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = UIKit.frame({ Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	topPanel = makePanel(root, true)
	bottomPanel = makePanel(root, false)
	label = UIKit.text({
		Name = "Label",
		Text = "DÉPLOIEMENT",
		FontFace = UITheme.Fonts.Display,
		TextSize = 64,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 90),
		TextTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})
	labelScale = UIKit.create("UIScale", { Parent = label })
	restOpen()
end

-- Cette méthode permet de fermer les volets puis d'appeler `onClosed` lorsque le joueur clique sur PLAY.
function Transition.close(onClosed: (() -> ())?)
	if not gui then
		if onClosed then
			onClosed()
		end
		return
	end
	generation += 1
	local myGeneration = generation
	closed = true
	gui.Enabled = true
	restOpen()
	label.TextTransparency = 1
	labelScale.Scale = 1.6

	UIKit.tween(topPanel, Motion.Shutter, { Position = UDim2.fromScale(0, 0) })
	local tween = UIKit.tween(bottomPanel, Motion.Shutter, { Position = UDim2.fromScale(0, 0.5) })
	tween.Completed:Connect(function()
		if myGeneration ~= generation then
			return
		end
		UIKit.tween(label, Motion.Pop, { TextTransparency = 0 })
		UIKit.tween(labelScale, Motion.Pop, { Scale = 1 })
		if onClosed then
			onClosed()
		end
	end)

	task.delay(SAFETY_OPEN_DELAY, function()
		if myGeneration == generation and closed then
			Transition.open()
		end
	end)
end

-- Cette méthode permet de rouvrir les volets sur le jeu lorsque le personnage local est prêt.
function Transition.open()
	if not gui or not closed then
		return
	end
	closed = false
	generation += 1
	local myGeneration = generation
	UIKit.tween(label, Motion.Exit, { TextTransparency = 1 })
	UIKit.tween(topPanel, Motion.Shutter, { Position = UDim2.fromScale(0, -0.5) })
	local tween = UIKit.tween(bottomPanel, Motion.Shutter, { Position = UDim2.fromScale(0, 1) })
	tween.Completed:Connect(function()
		if myGeneration == generation then
			gui.Enabled = false
		end
	end)
end

-- Cette méthode permet de savoir si les volets couvrent l'écran lorsque l'orchestrateur décide de les rouvrir.
function Transition.isClosed(): boolean
	return closed
end

return Transition

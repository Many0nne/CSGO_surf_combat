-- Hitmarker qui remplace le curseur sur tous les écrans du menu : il se resserre et rougit sur une cible, grossit au tir.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors

local MenuCursor = {}

local ARM_ANGLES = { 45, 135, 225, 315 }

local gui: ScreenGui
local cursor: Frame
local arms: { { frame: Frame, angle: number } } = {}
local connection: RBXScriptConnection?
local hoverCount = 0
local gap, hitScale = 10, 1
local hitUntil = 0

-- Cette méthode permet de faire suivre la souris au hitmarker lorsqu'une image est rendue ;
-- le curseur système reste masqué même si un autre écran le réactive en se fermant.
local function update(dt: number)
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

-- Cette méthode permet de construire le hitmarker lorsque le menu est initialisé.
function MenuCursor.init()
	gui = UIKit.create("ScreenGui", {
		Name = "MenuCursor",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	cursor = UIKit.frame({ Name = "Cursor", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = gui })
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

-- Cette méthode permet d'afficher le hitmarker lorsque le menu s'ouvre (sauf sur un écran purement tactile).
function MenuCursor.show()
	gui.Enabled = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
	if not connection then
		connection = RunService.RenderStepped:Connect(update)
	end
end

-- Cette méthode permet de masquer le hitmarker lorsque la partie démarre.
function MenuCursor.hide()
	gui.Enabled = false
	hoverCount = 0
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Cette méthode permet de compter les cibles survolées lorsque la souris entre sur un élément ou le quitte.
function MenuCursor.addHover(delta: number)
	hoverCount = math.max(0, hoverCount + delta)
end

-- Cette méthode permet d'oublier les cibles survolées lorsqu'un écran se ferme sous la souris, sans MouseLeave garanti.
function MenuCursor.resetHover()
	hoverCount = 0
end

-- Cette méthode permet de faire réagir le hitmarker lorsqu'un tir part ; il grossit et rougit s'il a touché un surfeur.
function MenuCursor.kick(hasHit: boolean)
	hitScale = hasHit and 2.3 or 1.5
	if hasHit then
		hitUntil = os.clock() + 0.28
	end
end

return MenuCursor

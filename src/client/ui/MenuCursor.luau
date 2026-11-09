-- Curseur du menu : souris système partout, remplacée par un hitmarker quand elle survole l'arme de la vitrine (seule
-- chose qui se tire, #130) ; le hitmarker grossit au tir et rougit un instant.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local C = UITheme.Colors

local MenuCursor = {}

local ARM_ANGLES = { 45, 135, 225, 315 }
local GAP = 6

local gui: ScreenGui
local cursor: Frame
local arms: { { frame: Frame, angle: number } } = {}
local connection: RBXScriptConnection?
local aimCheck: ((number, number) -> boolean)?
local hitScale = 1
local hitUntil = 0

-- Cette méthode permet de choisir entre souris système et hitmarker lorsqu'une image est rendue : hitmarker sur l'arme,
-- souris système ailleurs (réimposée à chaque image, car d'autres écrans changent l'icône en s'ouvrant ou se fermant).
local function update(dt: number)
	local mouse = UserInputService:GetMouseLocation()
	local aiming = aimCheck ~= nil and aimCheck(mouse.X, mouse.Y)
	UserInputService.MouseIconEnabled = not aiming
	cursor.Visible = aiming
	if not aiming then
		return
	end
	cursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	hitScale += (1 - hitScale) * math.min(1, dt * 9)
	local color = if os.clock() < hitUntil then C.HitRed else C.White
	for _, arm in arms do
		local distance = (GAP + 8) * hitScale
		arm.frame.Position = UDim2.fromOffset(math.cos(arm.angle) * distance, math.sin(arm.angle) * distance)
		arm.frame.Size = UDim2.fromOffset(16 * hitScale, 3 * math.max(1, hitScale * 0.7))
		arm.frame.BackgroundColor3 = color
	end
end

-- Cette méthode permet de construire le hitmarker lorsque le menu est initialisé ; `isAiming(x, y)` dit si la souris
-- vise l'arme (accueil seulement).
function MenuCursor.init(isAiming: (number, number) -> boolean)
	aimCheck = isAiming
	gui = UIKit.create("ScreenGui", {
		Name = "MenuCursor",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	cursor = UIKit.frame({
		Name = "Cursor",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = gui,
	})
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

-- Cette méthode permet de suivre la souris lorsque le menu s'ouvre (hitmarker absent sur un écran purement tactile).
function MenuCursor.show()
	gui.Enabled = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
	if not connection then
		connection = RunService.RenderStepped:Connect(PerfMarkers.wrap("curseur menu", update))
	end
end

-- Cette méthode permet de masquer le hitmarker lorsque la partie démarre (la caméra FPS gère ensuite l'icône).
function MenuCursor.hide()
	gui.Enabled = false
	cursor.Visible = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Cette méthode permet de faire réagir le hitmarker lorsqu'un tir part sur l'arme : il grossit et rougit un instant.
function MenuCursor.kick()
	hitScale = 2.3
	hitUntil = os.clock() + 0.28
end

return MenuCursor

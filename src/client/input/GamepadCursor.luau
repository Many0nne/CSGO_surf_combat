-- Curseur virtuel de la manette dans les menus (#276) : les écrans ne se naviguent qu'au pointeur, le stick gauche le
-- déplace et A clique (GamepadService). Actif tant qu'un écran le demande (menu principal, menu en partie) et que la
-- manette est le dernier appareil utilisé (InputDevice) ; coupé en partie, où le stick sert au déplacement.
local GamepadService = game:GetService("GamepadService")
local Players = game:GetService("Players")

local InputDevice = require(script.Parent.InputDevice)

local GamepadCursor = {}

local requests: { [string]: true } = {}
local anchor: Frame? -- point de départ du curseur, au centre de l'écran

-- Cette méthode permet de créer le point de départ du curseur (cadre vide au centre de l'écran) lorsqu'il sert la
-- première fois.
local function getAnchor(): Frame
	if anchor then
		return anchor
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GamepadCursorAnchor"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(1, 1)
	frame.Parent = gui
	anchor = frame
	return frame
end

-- Cette méthode permet d'allumer ou d'éteindre le curseur selon les demandes et l'appareil lorsque l'un des deux change.
function GamepadCursor.refresh()
	local wanted = next(requests) ~= nil and InputDevice.get() == "gamepad"
	if wanted and not GamepadService.GamepadCursorEnabled then
		GamepadService:EnableGamepadCursor(getAnchor())
	elseif not wanted and GamepadService.GamepadCursorEnabled then
		GamepadService:DisableGamepadCursor()
	end
end

-- Cette méthode permet à un écran de demander (`on` vrai) ou de rendre le curseur lorsqu'il s'ouvre ou se ferme ;
-- `key` distingue les écrans (le curseur reste tant qu'une demande tient).
function GamepadCursor.request(key: string, on: boolean)
	(requests :: any)[key] = if on then true else nil
	GamepadCursor.refresh()
end

InputDevice.onChanged(function()
	GamepadCursor.refresh()
end)

return GamepadCursor

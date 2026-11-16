-- Dernier appareil utilisé (#276) : clavier et souris, manette ou tactile, d'après UserInputService.LastInputTypeChanged
-- (classement KeyBindings.deviceOf). L'affichage des touches et le curseur des menus le suivent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local KeyBindings = require(ReplicatedStorage.Shared.KeyBindings)

local InputDevice = {}

local current: KeyBindings.Device = KeyBindings.deviceOf(UserInputService:GetLastInputType().Name)
	or (if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "touch" else "keyboard")
local listeners: { [(KeyBindings.Device) -> ()]: true } = {}

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local device = KeyBindings.deviceOf(inputType.Name)
	if device and device ~= current then
		current = device
		for listener in listeners do
			task.spawn(listener, device)
		end
	end
end)

-- Cette méthode permet de lire le dernier appareil utilisé lorsqu'un écran choisit ses libellés ou son curseur.
function InputDevice.get(): KeyBindings.Device
	return current
end

-- Cette méthode permet d'être prévenu lorsque le joueur change d'appareil (clavier, manette, tactile).
function InputDevice.onChanged(listener: (KeyBindings.Device) -> ())
	listeners[listener] = true
end

return InputDevice

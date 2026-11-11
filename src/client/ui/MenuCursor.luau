-- Curseur du menu : souris système, réimposée à chaque image tant que le menu est ouvert, car d'autres écrans changent
-- l'icône en s'ouvrant ou se fermant et la caméra FPS la masque en partie. Rien ne se tire au menu (#130, #253).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local MenuCursor = {}

local connection: RBXScriptConnection?

-- Cette méthode permet de garder la souris système visible lorsqu'une image est rendue au menu.
local function update()
	if not UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = true
	end
end

-- Cette méthode permet d'imposer la souris système lorsque le menu s'ouvre.
function MenuCursor.show()
	if not connection then
		connection = RunService.RenderStepped:Connect(PerfMarkers.wrap("curseur menu", update))
	end
end

-- Cette méthode permet de rendre la main sur l'icône de la souris lorsque la partie démarre (la caméra FPS la gère).
function MenuCursor.hide()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return MenuCursor

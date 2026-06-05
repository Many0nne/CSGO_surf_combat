local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)

local ScopeSystem = {}

local cameraRef = nil
local viewmodelRef = nil
local level = 0

local function getScopeGui(): ScreenGui?
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local gui = pg:FindFirstChild("ScopeGUI")
	return gui and gui:IsA("ScreenGui") and gui or nil
end

local function setGuiVisible(visible: boolean)
	local gui = getScopeGui()
	if gui then gui.Enabled = visible end
end

function ScopeSystem.init(camera, viewmodel)
	cameraRef   = camera
	viewmodelRef = viewmodel
	level = 0
end

function ScopeSystem.getLevel(): number
	return level
end

function ScopeSystem.resetVisuals()
	if level ~= 0 then
		cameraRef.setFOV(CameraConfig.DEFAULT_FOV)
		cameraRef.setScoped(false)
		viewmodelRef.setVisible(true)
		setGuiVisible(false)
	end
	level = 0
end

function ScopeSystem.reset()
	ScopeSystem.resetVisuals()
end

-- Retourne le nouvel état weaponState ("IDLE" ou "SCOPED")
function ScopeSystem.toggle(cfg): string
	if not cfg or not cfg.HasScope then return "IDLE" end
	level = (level + 1) % 3
	if level == 0 then
		cameraRef.setFOV(CameraConfig.DEFAULT_FOV, cfg.ScopeTweenTime)
		cameraRef.setScoped(false)
		viewmodelRef.setVisible(true)
		setGuiVisible(false)
		viewmodelRef.playSound("ZoomOut")
		return "IDLE"
	elseif level == 1 then
		cameraRef.setFOV(cfg.ScopeFov1, cfg.ScopeTweenTime)
		cameraRef.setScoped(true)
		viewmodelRef.setVisible(false)
		setGuiVisible(true)
		viewmodelRef.playSound("ZoomIn")
		return "SCOPED"
	else
		cameraRef.setFOV(cfg.ScopeFov2, cfg.ScopeTweenTime)
		cameraRef.setScoped(true)
		setGuiVisible(true)
		viewmodelRef.playSound("ZoomIn")
		return "SCOPED"
	end
end

return ScopeSystem

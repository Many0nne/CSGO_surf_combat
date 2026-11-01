local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local ScopeOverlay = require(script.Parent.Parent.Parent.ui.ScopeOverlay)

local ScopeSystem = {}

local cameraRef = nil
local viewmodelRef = nil
local level = 0

function ScopeSystem.init(camera, viewmodel)
	cameraRef = camera
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
		ScopeOverlay.setVisible(false)
	end
	level = 0
end

function ScopeSystem.reset()
	ScopeSystem.resetVisuals()
end

-- Retourne le nouvel état weaponState ("IDLE" ou "SCOPED")
function ScopeSystem.toggle(cfg): string
	if not cfg or not cfg.HasScope then
		return "IDLE"
	end
	level = (level + 1) % 3
	if level == 0 then
		cameraRef.setFOV(CameraConfig.DEFAULT_FOV, cfg.ScopeTweenTime)
		cameraRef.setScoped(false)
		viewmodelRef.setVisible(true)
		ScopeOverlay.setVisible(false)
		viewmodelRef.playSound("ZoomOut")
		return "IDLE"
	elseif level == 1 then
		cameraRef.setFOV(cfg.ScopeFov1, cfg.ScopeTweenTime)
		cameraRef.setScoped(true)
		viewmodelRef.setVisible(false)
		ScopeOverlay.setVisible(true)
		viewmodelRef.playSound("ZoomIn")
		return "SCOPED"
	else
		cameraRef.setFOV(cfg.ScopeFov2, cfg.ScopeTweenTime)
		cameraRef.setScoped(true)
		ScopeOverlay.setVisible(true)
		viewmodelRef.playSound("ZoomIn")
		return "SCOPED"
	end
end

return ScopeSystem

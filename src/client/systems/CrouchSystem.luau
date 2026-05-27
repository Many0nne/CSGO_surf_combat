local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage.Shared.MovementConfig)
local InputModule = require(script.Parent.Parent.input.InputModule)

local STAND_HALF  = Config.CHAR_HEIGHT_STAND  / 2
local CROUCH_HALF = Config.CHAR_HEIGHT_CROUCH / 2
local UNCROUCH_CAST_DIST = STAND_HALF - CROUCH_HALF + 0.1

local hrpRef: BasePart? = nil
local crouching = false
local camHeight = Config.CAM_HEIGHT_STAND
local halfHeight = STAND_HALF

local function canUncrouch(): boolean
	if not hrpRef then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hrpRef.Parent :: Instance }
	local result = workspace:Raycast(hrpRef.Position, Vector3.new(0, UNCROUCH_CAST_DIST, 0), params)
	return result == nil
end

local CrouchSystem = {}

function CrouchSystem.init(hrp: BasePart)
	hrpRef     = hrp
	crouching  = false
	camHeight  = Config.CAM_HEIGHT_STAND
	halfHeight = STAND_HALF
end

function CrouchSystem.update(dt: number): { isCrouching: boolean, camHeight: number, halfHeight: number }
	local wantCrouch = InputModule.isCrouching()

	if wantCrouch then
		crouching = true
	elseif crouching then
		if canUncrouch() then
			crouching = false
		end
	end

	local targetCamHeight = crouching and Config.CAM_HEIGHT_CROUCH or Config.CAM_HEIGHT_STAND
	camHeight = camHeight + (targetCamHeight - camHeight) * math.min(1, Config.CAM_LERP_SPEED * dt)

	halfHeight = crouching and CROUCH_HALF or STAND_HALF

	return { isCrouching = crouching, camHeight = camHeight, halfHeight = halfHeight }
end

function CrouchSystem.getCamHeight(): number
	return camHeight
end

return CrouchSystem

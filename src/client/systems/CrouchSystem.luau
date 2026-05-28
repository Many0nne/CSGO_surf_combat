local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage.Shared.MovementConfig)
local CharacterDimensions = require(script.Parent.CharacterDimensions)
local InputModule = require(script.Parent.Parent.input.InputModule)

local STAND_HALF  = 0
local CROUCH_HALF = 0
local STAND_ROOT_TOP = 0
local CROUCH_ROOT_TOP = 0
local UNCROUCH_CAST_DIST = 0

local hrpRef: BasePart? = nil
local crouching = false
local camHeight = Config.CAM_HEIGHT_STAND
local halfHeight = STAND_HALF
local rootToBottom = 0
local rootToTop = 0
local centerOffset = 0

local function canUncrouch(): boolean
	if not hrpRef then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hrpRef.Parent :: Instance }
	local origin = hrpRef.Position + Vector3.new(0, CROUCH_ROOT_TOP, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, UNCROUCH_CAST_DIST, 0), params)
	return result == nil
end

local CrouchSystem = {}

function CrouchSystem.init(hrp: BasePart)
	hrpRef     = hrp
	crouching  = false
	camHeight  = Config.CAM_HEIGHT_STAND
	local standDims = CharacterDimensions.getStand()
	local crouchDims = CharacterDimensions.getCrouch()
	STAND_HALF = standDims.halfHeight
	CROUCH_HALF = crouchDims.halfHeight
	STAND_ROOT_TOP = standDims.rootToTop
	CROUCH_ROOT_TOP = crouchDims.rootToTop
	UNCROUCH_CAST_DIST = STAND_ROOT_TOP - CROUCH_ROOT_TOP + 0.1
	if UNCROUCH_CAST_DIST < 0 then
		UNCROUCH_CAST_DIST = 0
	end

	halfHeight = STAND_HALF
	rootToBottom = standDims.rootToBottom
	rootToTop = standDims.rootToTop
	centerOffset = standDims.centerOffset
end

function CrouchSystem.update(dt: number): { isCrouching: boolean, camHeight: number, halfHeight: number, rootToBottom: number, rootToTop: number, centerOffset: number, radius: number }
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

	local dims = crouching and CharacterDimensions.getCrouch() or CharacterDimensions.getStand()
	halfHeight = dims.halfHeight
	rootToBottom = dims.rootToBottom
	rootToTop = dims.rootToTop
	centerOffset = dims.centerOffset

	return {
		isCrouching = crouching,
		camHeight = camHeight,
		halfHeight = halfHeight,
		rootToBottom = rootToBottom,
		rootToTop = rootToTop,
		centerOffset = centerOffset,
		radius = dims.radius,
	}
end

function CrouchSystem.getCamHeight(): number
	return camHeight
end

return CrouchSystem

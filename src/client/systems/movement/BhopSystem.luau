local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config      = require(ReplicatedStorage.Shared.MovementConfig)
local InputModule = require(script.Parent.Parent.Parent.input.InputModule)

local landTimer   = math.huge  -- time since last landing; huge = airborne / never landed
local wasOnGround = false

local BhopSystem = {}

-- Appelé une fois par tick depuis MovementController, après CoyoteJump.update().
-- shouldJump : résultat de CoyoteJump (inclut buffer jump).
-- Retourne { skipFriction, forceJump }.
--   skipFriction : la friction doit être ignorée ce tick (bon timing ou AUTO_BHOP).
--   forceJump    : AUTO_BHOP déclenche un saut que CoyoteJump n'a pas déclenché.
function BhopSystem.update(onGround: boolean, shouldJump: boolean, dt: number)
	local justLanded = onGround and not wasOnGround
	if justLanded then
		landTimer = 0
	elseif onGround then
		landTimer = landTimer + dt
	else
		landTimer = math.huge
	end
	wasOnGround = onGround

	local jumpHeld   = InputModule.isJumpHeld()
	local goodTiming = onGround and (landTimer <= Config.BHOP_LAND_WINDOW)

	-- AUTO_BHOP : forcer un saut tant que Space est maintenu (si CoyoteJump n'en a pas émis)
	local forceJump    = Config.AUTO_BHOP and onGround and jumpHeld and not shouldJump

	local willJump     = shouldJump or forceJump
	local skipFriction = onGround and willJump and (goodTiming or Config.AUTO_BHOP)

	return { skipFriction = skipFriction, forceJump = forceJump }
end

return BhopSystem

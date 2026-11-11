local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.MovementConfig)

local landTimer = math.huge -- time since last landing; huge = airborne / never landed
local wasOnGround = false

export type BhopOptions = { jumpHeld: boolean, autoBhop: boolean }

local BhopSystem = {}

-- Appelé une fois par tick depuis MovementController, après CoyoteJump.update().
-- shouldJump : résultat de CoyoteJump (inclut buffer jump).
-- Retourne { skipFriction, forceJump }.
-- opts.jumpHeld : Espace est maintenu. opts.autoBhop : réglage du joueur (#255), saut automatique tant qu'Espace est maintenu.
--   skipFriction : la friction doit être ignorée ce tick (bon timing ou auto-bhop).
--   forceJump    : l'auto-bhop déclenche un saut que CoyoteJump n'a pas déclenché.
function BhopSystem.update(onGround: boolean, shouldJump: boolean, dt: number, opts: BhopOptions)
	local justLanded = onGround and not wasOnGround
	if justLanded then
		landTimer = 0
	elseif onGround then
		landTimer = landTimer + dt
	else
		landTimer = math.huge
	end
	wasOnGround = onGround

	local jumpHeld, autoBhop = opts.jumpHeld, opts.autoBhop
	local goodTiming = onGround and (landTimer <= Config.BHOP_LAND_WINDOW)

	-- Auto-bhop : forcer un saut tant que Space est maintenu (si CoyoteJump n'en a pas émis)
	local forceJump = autoBhop and onGround and jumpHeld and not shouldJump

	local willJump = shouldJump or forceJump
	local skipFriction = onGround and willJump and (goodTiming or autoBhop)

	return { skipFriction = skipFriction, forceJump = forceJump }
end

return BhopSystem

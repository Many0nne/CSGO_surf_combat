local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config      = require(ReplicatedStorage.Shared.MovementConfig)
local InputModule = require(script.Parent.Parent.Parent.input.InputModule)

local coyoteTimer    = 0
local wasOnGround    = true
local didTriggerJump = false   -- empêche le coyote de démarrer sur un saut volontaire

local CoyoteJump = {}

-- Appelé une fois par tick depuis MovementController.
-- Consomme isJumpPressed() en interne — ne pas l'appeler ailleurs ce tick.
-- Retourne true si un saut doit se déclencher (normal / coyote / buffer).
function CoyoteJump.update(onGround: boolean, dt: number): boolean
	local prevOnGround       = wasOnGround
	local prevDidTriggerJump = didTriggerJump
	didTriggerJump = false

	-- Coyote : vient de quitter le sol sans avoir sauté
	if prevOnGround and not onGround and not prevDidTriggerJump then
		coyoteTimer = Config.COYOTE_TIME
	elseif onGround then
		coyoteTimer = 0
	else
		coyoteTimer = math.max(0, coyoteTimer - dt)
	end
	wasOnGround = onGround

	local jumpPressed  = InputModule.isJumpPressed()   -- edge, consommé ici
	local jumpBuffered = (tick() - InputModule.getJumpPressTime()) <= Config.JUMP_BUFFER_TIME

	local normalJump = onGround and jumpPressed
	local coyoteJump = not onGround and coyoteTimer > 0 and jumpPressed
	local bufferJump = onGround and not prevOnGround and jumpBuffered  -- atterrissage + buffer actif

	local shouldJump = normalJump or coyoteJump or bufferJump
	if shouldJump then
		didTriggerJump = true
		coyoteTimer = 0
	end
	return shouldJump
end

return CoyoteJump

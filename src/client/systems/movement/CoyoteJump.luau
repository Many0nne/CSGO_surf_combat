local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.MovementConfig)

local coyoteTimer = 0
local wasOnGround = true
local didTriggerJump = false -- empêche le coyote de démarrer sur un saut déjà fait (volontaire ou forcé)

export type JumpInput = {
	jumpPressed: boolean, -- front montant d'Espace ce tick (déjà consommé par l'appelant)
	timeSincePress: number, -- secondes depuis le dernier appui (buffer)
}

local CoyoteJump = {}

-- Cette méthode permet de remettre à zéro l'état du module lorsque le personnage apparaît,
-- pour qu'un état de la vie précédente ne déclenche ni coyote ni buffer.
function CoyoteJump.init()
	coyoteTimer = 0
	wasOnGround = false -- apparition : jamais de coyote tant qu'on n'a pas touché le sol
	didTriggerJump = false
end

-- Cette méthode permet de déclarer qu'un saut a été forcé ce tick (auto-bhop) lorsque BhopSystem en émet un
-- que update n'a pas vu : la fenêtre coyote ne doit pas s'ouvrir après ce saut.
function CoyoteJump.notifyForcedJump()
	didTriggerJump = true
	coyoteTimer = 0
end

-- Appelé une fois par tick depuis MovementController.
-- Les entrées sont injectées (l'appelant consomme isJumpPressed() une seule fois par tick).
-- Retourne true si un saut doit se déclencher (normal / coyote / buffer).
function CoyoteJump.update(onGround: boolean, dt: number, input: JumpInput): boolean
	local prevOnGround = wasOnGround
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

	local jumpPressed = input.jumpPressed
	local jumpBuffered = input.timeSincePress <= Config.JUMP_BUFFER_TIME

	local normalJump = onGround and jumpPressed
	local coyoteJump = not onGround and coyoteTimer > 0 and jumpPressed
	local bufferJump = onGround and not prevOnGround and jumpBuffered -- atterrissage + buffer actif

	local shouldJump = normalJump or coyoteJump or bufferJump
	if shouldJump then
		didTriggerJump = true
		coyoteTimer = 0
	end
	return shouldJump
end

return CoyoteJump

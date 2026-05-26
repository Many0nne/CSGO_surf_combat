local UserInputService = game:GetService("UserInputService")

-- Map KeyCode → nom de touche interne
local KEY_MAP = {
	[Enum.KeyCode.W]            = "W",
	[Enum.KeyCode.A]            = "A",
	[Enum.KeyCode.S]            = "S",
	[Enum.KeyCode.D]            = "D",
	[Enum.KeyCode.LeftShift]    = "Shift",
	[Enum.KeyCode.RightShift]   = "Shift",
	[Enum.KeyCode.LeftControl]  = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.Space]        = "Space",
}

local held = {
	W = false, A = false, S = false, D = false,
	Shift = false, Ctrl = false, Space = false,
}

local jumpPressedEdge = false
local jumpPressTime   = -math.huge

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local key = KEY_MAP[input.KeyCode]
	if not key then return end
	-- Bloquer le saut si l'UI a capturé l'input (ex: chat ouvert), mais laisser passer
	-- les touches de mouvement même si gameProcessed (ex: Ctrl+Z intercepté comme Undo).
	if gameProcessed and key == "Space" then return end
	held[key] = true
	if key == "Space" then
		jumpPressedEdge = true
		jumpPressTime   = tick()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local key = KEY_MAP[input.KeyCode]
	if not key then return end
	-- Pour les touches doublées (L/R Shift, L/R Ctrl), ne relâcher que si aucune des deux n'est tenue
	if key == "Shift" then
		if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			and not UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
			held.Shift = false
		end
	elseif key == "Ctrl" then
		if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
			held.Ctrl = false
		end
	else
		held[key] = false
	end
end)

local InputModule = {}

-- Direction souhaitée en world-space XZ, normalisée (diagonales incluses).
-- yaw : angle horizontal de la caméra en degrés (depuis FPSCamera.getCameraYaw()).
-- Retourne Vector3.zero si aucune touche directionnelle n'est pressée.
function InputModule.getWishDir(yaw: number): Vector3
	local fwd = (held.W and 1 or 0) - (held.S and 1 or 0)
	local rgt = (held.D and 1 or 0) - (held.A and 1 or 0)
	if fwd == 0 and rgt == 0 then
		return Vector3.zero
	end
	local yr  = math.rad(yaw)
	local s, c = math.sin(yr), math.cos(yr)
	-- forward = (sin(yaw), 0, -cos(yaw))  right = (cos(yaw), 0, sin(yaw))
	local raw = Vector3.new(fwd * s + rgt * c, 0, fwd * (-c) + rgt * s)
	if raw.Magnitude > 1 then
		return raw.Unit
	end
	return raw
end

-- Shift tenu
function InputModule.isWalking(): boolean
	return held.Shift
end

-- Ctrl tenu
function InputModule.isCrouching(): boolean
	return held.Ctrl
end

-- Edge trigger : retourne true une seule fois par appui de Space (consommé à la lecture).
function InputModule.isJumpPressed(): boolean
	if jumpPressedEdge then
		jumpPressedEdge = false
		return true
	end
	return false
end

-- Level trigger : true tant que Space est tenu (pour auto-bhop).
function InputModule.isJumpHeld(): boolean
	return held.Space
end

-- Horodatage (tick()) du dernier appui Space — utilisé par le jump buffer.
function InputModule.getJumpPressTime(): number
	return jumpPressTime
end

-- True si S est le seul axe directionnel pressé (pas W/A/D) → vitesse limitée en recul.
function InputModule.isBackwardOnly(): boolean
	return held.S and not held.W and not held.A and not held.D
end

return InputModule

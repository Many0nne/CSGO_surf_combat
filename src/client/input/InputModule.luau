local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local KeyBindings = require(ReplicatedStorage.Shared.KeyBindings)

type Action = KeyBindings.Action

-- Liaisons tirées de KeyBindings (#224), source aussi de l'affichage des touches (HUDRules) : Enum.KeyCode → action et
-- touches de chaque action
local KEY_MAP: { [Enum.KeyCode]: Action } = {}
local ACTION_CODES: { [Action]: { Enum.KeyCode } } = {}
-- Actions tenues, une par action de KeyBindings.KEYS (champs nommés : une faute de frappe est relevée par luau-lsp)
local held = {
	forward = false,
	left = false,
	back = false,
	right = false,
	jump = false,
	crouch = false,
	walk = false,
	reload = false,
	inspect = false,
}
for action, keys in KeyBindings.KEYS do
	assert((held :: any)[action] == false, "action de KeyBindings absente de held : " .. action)
	ACTION_CODES[action] = {}
	for _, name in keys do
		table.insert(ACTION_CODES[action], (Enum.KeyCode :: any)[name])
	end
end
for action in held do
	assert(KeyBindings.KEYS[action :: any], "action de held absente de KeyBindings : " .. action)
end
for name, action in KeyBindings.keyMap() do
	KEY_MAP[(Enum.KeyCode :: any)[name]] = action
end

local jumpPressedEdge = false
local jumpPressTime = -math.huge
local reloadPressedEdge = false
local inspectPressedEdge = false
local lastWishdir = Vector3.zero
-- Menu en partie ouvert (#157) : touches de jeu ignorées, rien n'est tenu
local suspended = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local action = KEY_MAP[input.KeyCode]
	if not action or suspended then
		return
	end
	-- Bloquer le saut si l'UI a capturé l'input (ex: chat ouvert), mais laisser passer
	-- les touches de mouvement même si gameProcessed (ex: Ctrl+Z intercepté comme Undo).
	if gameProcessed and action == "jump" then
		return
	end
	(held :: any)[action] = true
	if action == "jump" then
		jumpPressedEdge = true
		jumpPressTime = tick()
	elseif action == "reload" then
		reloadPressedEdge = true
	elseif action == "inspect" and not gameProcessed then
		inspectPressedEdge = true
	end
end)

-- Cette méthode permet de savoir si une autre touche de la même action reste enfoncée lorsqu'une touche est relâchée
-- (Ctrl, Maj gauche et droite).
local function otherKeyDown(action: Action, released: Enum.KeyCode): boolean
	for _, code in ACTION_CODES[action] do
		if code ~= released and UserInputService:IsKeyDown(code) then
			return true
		end
	end
	return false
end

UserInputService.InputEnded:Connect(function(input)
	local action = KEY_MAP[input.KeyCode]
	if not action then
		return
	end
	-- Pour les actions à deux touches (L/R Shift, L/R Ctrl), ne relâcher que si aucune des deux n'est tenue
	if not otherKeyDown(action, input.KeyCode) then
		(held :: any)[action] = false
	end
end)

local InputModule = {}

-- Cette méthode permet de couper (plus rien de tenu ni en attente) ou rendre les touches de jeu lorsque le menu en
-- partie s'ouvre ou se ferme ; une touche restée enfoncée ne compte qu'au prochain appui.
function InputModule.setSuspended(on: boolean)
	suspended = on
	if on then
		for key in held do
			held[key] = false
		end
		jumpPressedEdge = false
		reloadPressedEdge = false
		inspectPressedEdge = false
	end
end

-- Direction souhaitée en world-space XZ, normalisée (diagonales incluses).
-- yaw : angle horizontal de la caméra en degrés (depuis FPSCamera.getCameraYaw()).
-- Retourne Vector3.zero si aucune touche directionnelle n'est pressée.
function InputModule.getWishDir(yaw: number): Vector3
	local fwd = (held.forward and 1 or 0) - (held.back and 1 or 0)
	local rgt = (held.right and 1 or 0) - (held.left and 1 or 0)
	if fwd == 0 and rgt == 0 then
		lastWishdir = Vector3.zero
		return Vector3.zero
	end

	local yr = math.rad(yaw)
	local s, c = math.sin(yr), math.cos(yr)
	local raw = Vector3.new(fwd * s + rgt * c, 0, fwd * -c + rgt * s)

	-- Supprimer le lissage pour le bhop
	lastWishdir = raw.Unit
	return lastWishdir
end

-- Variante 3D : inclut le pitch pour que viser en bas influence la wishdir (surf/air).
function InputModule.getWishDir3D(yaw: number, pitch: number): Vector3
	local fwd = (held.forward and 1 or 0) - (held.back and 1 or 0)
	local rgt = (held.right and 1 or 0) - (held.left and 1 or 0)
	if fwd == 0 and rgt == 0 then
		return Vector3.zero
	end
	local yr = math.rad(yaw)
	local pr = math.rad(pitch)
	local forward = Vector3.new(math.sin(yr) * math.cos(pr), math.sin(pr), -math.cos(yr) * math.cos(pr))
	local right = Vector3.new(math.cos(yr), 0, math.sin(yr))
	local dir = forward * fwd + right * rgt
	if dir.Magnitude > 1e-4 then
		return dir.Unit
	end
	return Vector3.zero
end

-- Shift tenu
function InputModule.isWalking(): boolean
	return held.walk
end

-- Ctrl tenu
function InputModule.isCrouching(): boolean
	return held.crouch
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
	return held.jump
end

-- Horodatage (tick()) du dernier appui Space — utilisé par le jump buffer.
function InputModule.getJumpPressTime(): number
	return jumpPressTime
end

-- True si S est le seul axe directionnel pressé (pas W/A/D) → vitesse limitée en recul.
function InputModule.isBackwardOnly(): boolean
	return held.back and not held.forward and not held.left and not held.right
end

-- Edge trigger : retourne true une seule fois par appui de R (consommé à la lecture).
-- Cette méthode permet de consommer l'appui sur la touche d'inspection lorsque le système d'arme la lit à chaque frame.
function InputModule.isInspectPressed(): boolean
	if inspectPressedEdge then
		inspectPressedEdge = false
		return true
	end
	return false
end

function InputModule.isReloadPressed(): boolean
	if reloadPressedEdge then
		reloadPressedEdge = false
		return true
	end
	return false
end

return InputModule

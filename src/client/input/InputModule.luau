local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GamepadRules = require(ReplicatedStorage.Shared.GamepadRules)
local KeyBindings = require(ReplicatedStorage.Shared.KeyBindings)

type Action = KeyBindings.Action

-- Liaisons tirées de KeyBindings (#224, #276), source aussi de l'affichage des touches (HUDRules) : Enum.KeyCode
-- (clavier ou bouton de manette) → action
local KEY_MAP: { [Enum.KeyCode]: Action } = {}
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
-- Sources qui tiennent chaque action (touche, bouton de manette, bouton tactile) : l'action reste tenue tant que l'une
-- l'est (Ctrl gauche et droit, clavier et manette en même temps)
local holders: { [Action]: { [any]: true } } = {}
for action in KeyBindings.KEYS do
	assert((held :: any)[action] == false, "action de KeyBindings absente de held : " .. action)
	holders[action] = {}
end
for action in held do
	assert(KeyBindings.KEYS[action :: any], "action de held absente de KeyBindings : " .. action)
end
for name, action in KeyBindings.keyMap() do
	KEY_MAP[(Enum.KeyCode :: any)[name]] = action
end
for name, action in KeyBindings.gamepadMap() do
	KEY_MAP[(Enum.KeyCode :: any)[name]] = action
end
local AIM_MOUSE = (Enum.UserInputType :: any)["MouseButton" .. KeyBindings.MOUSE.aim]
local AIM_BUTTON = (Enum.KeyCode :: any)[KeyBindings.GAMEPAD_BUTTONS.aim]
local FIRE_MOUSE = (Enum.UserInputType :: any)["MouseButton" .. KeyBindings.MOUSE.fire]
local FIRE_BUTTON = (Enum.KeyCode :: any)[KeyBindings.GAMEPAD_BUTTONS.fire]
-- Tir et visée tenus (#473) : sources qui les tiennent (bouton de souris, de manette, tactile). Le premier tir passe par
-- Tool.Activated ; ce maintien ne sert qu'à répéter l'action (WeaponSystem). Il vient des vraies touches, ou de la
-- source « virtuelle » posée par applyVirtual pendant un rejeu (#485) ; un Tool:Activate() ne tient rien.
local pointerHolders: { [KeyBindings.MouseAction]: { [any]: true } } = { fire = {}, aim = {} }

local jumpPressedEdge = false
local jumpPressTime = -math.huge
local reloadPressedEdge = false
local inspectPressedEdge = false
local lastWishdir = Vector3.zero
-- Menu en partie ouvert (#157) ou saisie du chat (#541) : touches de jeu ignorées, rien n'est tenu. Une raison par
-- source, les touches reviennent quand plus aucune ne suspend.
local suspended = false
local suspendedBy: { [string]: true } = {}
-- Parcours rejoué (#379, debug/PerfReplay) : le clavier est ignoré, les entrées viennent de applyVirtual
local virtual = false
-- Appuis comptés depuis le démarrage, lus par l'enregistreur de parcours (debug/PerfRecorder) sans consommer les fronts
local pressCounts = { jump = 0, reload = 0, inspect = 0 }
-- Stick gauche de la manette et joystick tactile (#276) : position brute (x à droite, y en avant)
local padStick = Vector2.zero
local touchStick = Vector2.zero
-- Rappels de l'action de visée (lunette, attaque secondaire) : clic droit, L2 ou bouton tactile
local aimListeners: { [() -> ()]: true } = {}

-- Cette méthode permet de tenir une action et de poser ses fronts lorsqu'une source (touche, bouton, tactile) s'enfonce ;
-- `gameProcessed` : l'interface a capté l'entrée (chat ouvert), le saut et l'inspection sont alors ignorés.
local function press(action: Action, source: any, gameProcessed: boolean)
	if suspended or virtual then
		return
	end
	local name: string = action
	-- Bloquer le saut si l'UI a capturé l'input (ex: chat ouvert), mais laisser passer
	-- les touches de mouvement même si gameProcessed (ex: Ctrl+Z intercepté comme Undo).
	if gameProcessed and name == "jump" then
		return
	end
	holders[action][source] = true
	(held :: any)[action] = true
	if name == "jump" then
		jumpPressedEdge = true
		jumpPressTime = tick()
		pressCounts.jump += 1
	elseif name == "reload" then
		reloadPressedEdge = true
		pressCounts.reload += 1
	elseif name == "inspect" and not gameProcessed then
		inspectPressedEdge = true
		pressCounts.inspect += 1
	end
end

-- Cette méthode permet de relâcher une source lorsqu'elle remonte ; l'action reste tenue si une autre source la tient.
local function release(action: Action, source: any)
	if virtual then
		return
	end
	holders[action][source] = nil
	if next(holders[action]) == nil then
		(held :: any)[action] = false
	end
end

-- Cette méthode permet de tout relâcher (actions, sources, sticks, fronts) lorsque le menu s'ouvre ou que la source des
-- entrées change.
local function clearAll()
	for key in held do
		held[key] = false
		table.clear(holders[key :: Action])
	end
	for _, sources in pointerHolders do
		table.clear(sources)
	end
	padStick = Vector2.zero
	touchStick = Vector2.zero
	jumpPressedEdge = false
	reloadPressedEdge = false
	inspectPressedEdge = false
end

-- Cette méthode permet de prévenir les écouteurs de la visée lorsque le joueur appuie sur clic droit, L2 ou le bouton
-- tactile de la lunette, hors menu et hors rejeu.
local function fireAim()
	if suspended or virtual then
		return
	end
	for listener in aimListeners do
		task.spawn(listener)
	end
end

-- Cette méthode permet de tenir ou relâcher le tir ou la visée pour une source (bouton de souris, de manette, tactile)
-- lorsqu'elle s'enfonce ou remonte ; rien n'est tenu menu ouvert, et pendant un rejeu seule la source virtuelle
-- (applyVirtual) tient le tir et la visée.
local function holdPointer(action: KeyBindings.MouseAction, source: any, down: boolean)
	if down and not (suspended or virtual) then
		pointerHolders[action][source] = true
	else
		pointerHolders[action][source] = nil
	end
end

-- Cette méthode permet de nommer la source d'un bouton de souris ou de manette lorsque le tir ou la visée change d'état ;
-- nil pour une autre entrée.
local function pointerOf(input: InputObject): (KeyBindings.MouseAction?, any)
	if input.UserInputType == AIM_MOUSE then
		return "aim", AIM_MOUSE
	elseif input.KeyCode == AIM_BUTTON then
		return "aim", AIM_BUTTON
	elseif input.UserInputType == FIRE_MOUSE then
		return "fire", FIRE_MOUSE
	elseif input.KeyCode == FIRE_BUTTON then
		return "fire", FIRE_BUTTON
	end
	return nil, nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local pointer, source = pointerOf(input)
	if pointer then
		-- Un clic capté par l'interface (bouton du HUD, menu) ne tient ni le tir ni la visée
		if not gameProcessed then
			if pointer == "aim" then
				fireAim()
			end
			holdPointer(pointer, source, true)
		end
		return
	end
	local action = KEY_MAP[input.KeyCode]
	if action then
		press(action, input.KeyCode, gameProcessed)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local pointer, source = pointerOf(input)
	if pointer then
		holdPointer(pointer, source, false)
		return
	end
	local action = KEY_MAP[input.KeyCode]
	if action then
		release(action, input.KeyCode)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
		padStick = Vector2.zero
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 and not suspended and not virtual then
		padStick = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

-- Cette méthode permet de lire les axes de déplacement (avant, droite) lorsque la direction souhaitée est calculée :
-- touches tenues, sinon stick gauche ou joystick tactile (GamepadRules.moveAxes).
local function moveAxes(): (number, number)
	local fwd = (held.forward and 1 or 0) - (held.back and 1 or 0)
	local rgt = (held.right and 1 or 0) - (held.left and 1 or 0)
	if fwd ~= 0 or rgt ~= 0 then
		return fwd, rgt
	end
	local stick = if touchStick.Magnitude > padStick.Magnitude then touchStick else padStick
	return GamepadRules.moveAxes(stick.X, stick.Y)
end

local InputModule = {}

-- Cette méthode permet de couper (plus rien de tenu ni en attente) ou rendre les touches de jeu lorsque le menu en
-- partie (`reason` par défaut « menu ») ou la saisie du chat (« chat ») s'ouvre ou se ferme ; les touches ne reviennent
-- qu'une fois toutes les raisons levées, et une touche restée enfoncée ne compte qu'au prochain appui.
function InputModule.setSuspended(on: boolean, reason: string?)
	local key = reason or "menu"
	if on then
		suspendedBy[key] = true
	else
		suspendedBy[key] = nil
	end
	suspended = next(suspendedBy) ~= nil
	if on then
		clearAll()
	end
end

-- Cette méthode permet de savoir si les touches de jeu sont coupées (menu en partie, saisie du chat) lorsqu'un autre
-- lecteur de touches (classement, barre d'armes) doit se taire aussi.
function InputModule.isSuspended(): boolean
	return suspended
end

-- Cette méthode permet de tenir ou relâcher une action depuis un bouton tactile (#276) lorsque le joueur le touche.
function InputModule.setTouchAction(action: Action, down: boolean)
	if down then
		press(action, "touch", false)
	else
		release(action, "touch")
	end
end

-- Cette méthode permet de poser la position du joystick tactile (x à droite, y en avant, de -1 à 1) lorsque le doigt
-- bouge ; Vector2.zero au relâchement.
function InputModule.setTouchMove(position: Vector2)
	touchStick = if suspended or virtual then Vector2.zero else position
end

-- Cette méthode permet de tenir ou relâcher le tir ou la visée depuis un bouton tactile (#473) lorsque le joueur le
-- touche ; l'appui de la visée déclenche aussi la lunette ou l'attaque secondaire, comme le clic droit.
function InputModule.setTouchPointer(action: KeyBindings.MouseAction, down: boolean)
	if down and action == "aim" then
		fireAim()
	end
	holdPointer(action, "touch", down)
end

-- Cette méthode permet de savoir si le tir ou la visée est tenu (souris, manette ou tactile) lorsque le système d'arme
-- répète l'action au maintien (#473).
function InputModule.isPointerHeld(action: KeyBindings.MouseAction): boolean
	return next(pointerHolders[action]) ~= nil
end

-- Cette méthode permet d'écouter l'action de visée (clic droit, L2, bouton tactile) lorsque l'arme en main a une lunette
-- ou une attaque secondaire ; renvoie un objet à Disconnect comme une connexion.
function InputModule.onAim(listener: () -> ()): { Disconnect: (any) -> () }
	aimListeners[listener] = true
	return {
		Disconnect = function()
			aimListeners[listener] = nil
		end,
	}
end

-- Cette méthode permet de savoir si une action de KeyBindings.KEYS est tenue (toute source) lorsque l'affichage des
-- touches suit la manette ou le tactile ; faux pour un nom inconnu.
function InputModule.isHeld(action: string): boolean
	return (held :: any)[action] == true
end

-- Cette méthode permet de lire les axes de déplacement combinés (clavier, manette, tactile) lorsque l'affichage des
-- touches allume les directions.
function InputModule.getMoveAxes(): (number, number)
	return moveAxes()
end

-- Cette méthode permet de lire les actions tenues et les appuis comptés depuis le démarrage lorsque l'enregistreur de
-- parcours note un tick (#379) ; ne consomme aucun front.
function InputModule.snapshot(): ({ [string]: boolean }, { jump: number, reload: number, inspect: number })
	return table.clone(held) :: any, table.clone(pressCounts)
end

-- Cette méthode permet de passer les entrées sur une source virtuelle (clavier ignoré) ou de rendre le clavier lorsque
-- le rejeu d'un parcours démarre ou s'arrête (#379) ; rien n'est tenu ni en attente au changement.
function InputModule.setVirtual(on: boolean)
	virtual = on
	clearAll()
end

-- Cette méthode permet de poser les actions tenues et les appuis d'un tick rejoué lorsque la source virtuelle est
-- active ; un appui pose le même front que la touche (saut horodaté pour le buffer de saut).
function InputModule.applyVirtual(state: { [string]: boolean }, presses: { [string]: boolean })
	if not virtual then
		return
	end
	for key in held do
		held[key] = state[key] == true
	end
	-- Tir et visée tenus (#485) : une source « virtuelle » pour que WeaponSystem répète le tir comme au clic tenu
	for action, sources in pointerHolders do
		sources.virtual = if state[action] == true then true else nil
	end
	if presses.jump then
		jumpPressedEdge = true
		jumpPressTime = tick()
	end
	if presses.reload then
		reloadPressedEdge = true
	end
	if presses.inspect then
		inspectPressedEdge = true
	end
end

-- Direction souhaitée en world-space XZ, normalisée (diagonales incluses).
-- yaw : angle horizontal de la caméra en degrés (depuis FPSCamera.getCameraYaw()).
-- Retourne Vector3.zero si aucune touche directionnelle n'est pressée.
function InputModule.getWishDir(yaw: number): Vector3
	local fwd, rgt = moveAxes()
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
	local fwd, rgt = moveAxes()
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

-- True si S est le seul axe directionnel pressé (pas W/A/D), ou le stick tenu droit en arrière → vitesse limitée en recul.
function InputModule.isBackwardOnly(): boolean
	if held.forward or held.back or held.left or held.right then
		return held.back and not held.forward and not held.left and not held.right
	end
	local fwd, rgt = moveAxes()
	return fwd < 0 and rgt == 0
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

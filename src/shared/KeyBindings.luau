-- Liaisons fixes des touches de jeu (#224) : source unique lue par InputModule (entrées) et HUDRules (affichage des
-- touches). Règles pures, testées (tests/specs/KeyBindings.spec.luau). Les touches des armes et la molette sont réglables
-- par le joueur (PlayerSettings) ; la touche du menu est PlayerSettings.MENU_KEY.
local KeyBindings = {}

export type Action = "forward" | "left" | "back" | "right" | "jump" | "crouch" | "walk" | "reload" | "inspect"
export type MouseAction = "fire" | "aim"

-- Action → noms d'Enum.KeyCode (position QWERTY : KeyCode.W est la touche imprimée « Z » en AZERTY, cf. docs/ui.md
-- « Libellé d'une touche ») ; une action à deux touches (Ctrl, Maj gauche et droite) reste tenue tant que l'une l'est.
-- stylua: ignore
KeyBindings.KEYS = {
	forward = { "W" },
	left    = { "A" },
	back    = { "S" },
	right   = { "D" },
	jump    = { "Space" },
	crouch  = { "LeftControl", "RightControl" },
	walk    = { "LeftShift", "RightShift" },
	reload  = { "R" },
	inspect = { "F" },
} :: { [Action]: { string } }

-- Action → bouton de souris. `aim` (lunette, attaque secondaire) est lu par WeaponSystem ; `fire` reste le clic gauche
-- de Tool.Activated, fixé par Roblox : il ne sert qu'à l'affichage des touches et ne doit pas changer.
-- stylua: ignore
KeyBindings.MOUSE = {
	fire = 1,
	aim  = 2,
} :: { [MouseAction]: number }

-- Manette (#276) : action → noms d'Enum.KeyCode des boutons. Le déplacement passe par le stick gauche (Thumbstick1,
-- GamepadRules.moveAxes), la visée par le stick droit (Thumbstick2). R1 et L1 changent d'arme (WeaponBar).
-- stylua: ignore
KeyBindings.GAMEPAD = {
	jump    = { "ButtonA" },
	crouch  = { "ButtonB" },
	walk    = { "ButtonL3" },
	reload  = { "ButtonX" },
	inspect = { "ButtonY" },
} :: { [Action]: { string } }

-- Boutons de manette des actions hors KeyBindings.KEYS. `fire` (R2) passe par Tool.Activated, fixé par Roblox : il ne
-- sert qu'à l'affichage. Start et Select sont pris par Roblox (son menu, son curseur) : menu et classement sont sur la
-- croix directionnelle.
-- stylua: ignore
KeyBindings.GAMEPAD_BUTTONS = {
	fire       = "ButtonR2",
	aim        = "ButtonL2",
	menu       = "DPadUp",
	scoreboard = "DPadDown",
	back       = "ButtonB",
}

-- Libellé affiché d'un bouton de manette (nom d'Enum.KeyCode → texte, disposition Xbox comme Roblox)
-- stylua: ignore
local GAMEPAD_TEXT = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y",
	ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT", ButtonR2 = "RT", ButtonL3 = "L3", ButtonR3 = "R3",
	DPadUp = "▲", DPadDown = "▼", DPadLeft = "◀", DPadRight = "▶",
}

-- Gelées : InputModule, HUDRules et PlayerSettings lisent les mêmes tableaux, aucun ne doit les modifier
for _, keys in KeyBindings.KEYS do
	table.freeze(keys)
end
for _, keys in KeyBindings.GAMEPAD do
	table.freeze(keys)
end
table.freeze(KeyBindings.KEYS)
table.freeze(KeyBindings.MOUSE)
table.freeze(KeyBindings.GAMEPAD)
table.freeze(KeyBindings.GAMEPAD_BUTTONS)

-- Cette méthode permet de construire la table bouton de manette → action lorsque le module d'entrées démarre.
function KeyBindings.gamepadMap(): { [string]: Action }
	local map = {}
	for action, buttons in KeyBindings.GAMEPAD do
		for _, button in buttons do
			map[button] = action
		end
	end
	return map
end

-- Cette méthode permet de donner le libellé d'un bouton de manette lorsque l'affichage des touches suit la manette.
function KeyBindings.gamepadText(buttonName: string): string
	return GAMEPAD_TEXT[buttonName] or buttonName
end

export type Device = "keyboard" | "gamepad" | "touch"

-- Cette méthode permet de classer le dernier appareil utilisé (nom d'Enum.UserInputType) lorsqu'il change : manette,
-- tactile, sinon clavier et souris ; nil pour une entrée qui ne dit rien de l'appareil (focus, capteurs).
function KeyBindings.deviceOf(inputTypeName: string): Device?
	if string.sub(inputTypeName, 1, 7) == "Gamepad" then
		return "gamepad"
	elseif inputTypeName == "Touch" then
		return "touch"
	elseif
		inputTypeName == "Keyboard"
		or inputTypeName == "TextInput"
		or string.sub(inputTypeName, 1, 5) == "Mouse"
	then
		return "keyboard"
	end
	return nil
end

-- Cette méthode permet de construire la table touche → action lorsque le module d'entrées démarre (une touche ne sert
-- qu'à une action).
function KeyBindings.keyMap(): { [string]: Action }
	local map = {}
	for action, keys in KeyBindings.KEYS do
		for _, key in keys do
			map[key] = action
		end
	end
	return map
end

return KeyBindings

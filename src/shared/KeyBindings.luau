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

-- Gelées : InputModule, HUDRules et PlayerSettings lisent les mêmes tableaux, aucun ne doit les modifier
for _, keys in KeyBindings.KEYS do
	table.freeze(keys)
end
table.freeze(KeyBindings.KEYS)
table.freeze(KeyBindings.MOUSE)

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

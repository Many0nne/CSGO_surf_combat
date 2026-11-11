-- État central du HUD (#223) : état client (GameStateController : MENU, IN_ROUND, DEAD…, d'où « HUD de jeu actif » et
-- « mort »), menu en partie ouvert (InGameMenu, Réglages compris) et lunette affichée (ScopeOverlay). Les écrans poussent
-- leur part par un setter, les éléments du HUD s'abonnent (onChanged) et appliquent leur règle de HUDRules
-- (crosshairVisible, keyDisplayVisible…). Une nouvelle condition de masquage = un champ ici et la règle des éléments
-- concernés, sans setter de plus dans chaque élément. Sans Instance ni service : testé sous Lune
-- (tests/specs/HUDState.spec.luau).
local HUDState = {}

-- Même forme que HUDRules.HUDSnapshot (HUDRules ne peut pas être requis ici : les tests Lune ne simulent pas `script`)
export type Snapshot = {
	gameState: string,
	menuOpen: boolean,
	scoped: boolean,
}

type Listener = (hud: Snapshot, previous: Snapshot) -> ()

-- Instantané courant, remplacé (jamais modifié) à chaque changement : un abonné peut garder `previous`
local current: Snapshot = table.freeze({ gameState = "MENU", menuOpen = false, scoped = false })
local listeners: { Listener } = {}

-- Cette méthode permet de prévenir les abonnés lorsqu'un champ change vraiment ; l'erreur d'un abonné est relancée à
-- part (console), les autres abonnés et l'écran qui pousse l'état continuent.
local function set(field: string, value: any)
	if (current :: any)[field] == value then
		return
	end
	local previous = current
	local nextState = table.clone(current) :: any
	nextState[field] = value
	current = table.freeze(nextState)
	for _, listener in table.clone(listeners) do
		local ok, err = xpcall(listener, debug.traceback, current, previous)
		if not ok then
			task.spawn(error, err, 0)
		end
	end
end

-- Cette méthode permet de lire l'état du HUD lorsqu'un élément se construit ou applique sa règle de visibilité.
function HUDState.get(): Snapshot
	return current
end

-- Cette méthode permet de poser l'état client lorsque GameStateController change d'état (HUD de jeu, mort, menu…).
function HUDState.setGameState(gameState: string)
	set("gameState", gameState)
end

-- Cette méthode permet de signaler l'ouverture ou la fermeture du menu en partie (Réglages compris) lorsque InGameMenu
-- pose ou retire sa surcouche.
function HUDState.setMenuOpen(isOpen: boolean)
	set("menuOpen", isOpen)
end

-- Cette méthode permet de signaler la lunette affichée ou refermée lorsque ScopeOverlay change de visibilité.
function HUDState.setScoped(isScoped: boolean)
	set("scoped", isScoped)
end

-- Cette méthode permet à un élément d'être prévenu de chaque changement d'état (nouvel et ancien instantanés) lorsqu'il
-- s'initialise ; renvoie la fonction qui le désabonne.
function HUDState.onChanged(listener: Listener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

return HUDState

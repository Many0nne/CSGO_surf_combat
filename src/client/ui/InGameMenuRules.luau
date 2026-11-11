-- Règles pures du menu en partie (#157), testées par tests/specs/InGameMenuRules.spec.luau ; InGameMenu les applique.
-- Le menu est une surcouche : la partie (FFA, multijoueur) continue dessous, seules les entrées du joueur sont coupées.
-- Vues : fermé, accueil du menu (REPRENDRE, RÉGLAGES, MENU PRINCIPAL), ou écran Réglages ouvert depuis le menu.
export type View = "closed" | "main" | "settings"
export type Choice = "resume" | "settings" | "back" | "leave"
-- Destinataire de la touche du menu : menu en partie, Réglages du menu principal, ou personne
export type KeyTarget = "inGame" | "mainMenu" | "none"

local InGameMenuRules = {}

-- Cette méthode permet de savoir si le menu en partie peut être ouvert dans un état client (GameStateController) lorsque
-- la touche est pressée ou que l'état change : en partie, vivant ou en attente de réapparition.
function InGameMenuRules.available(gameState: string): boolean
	return gameState == "IN_ROUND" or gameState == "DEAD"
end

-- Cette méthode permet de choisir qui traite la touche du menu lorsqu'elle est pressée : le menu en partie s'il est
-- ouvert ou disponible, l'écran Réglages au menu principal (accueil), personne ailleurs (Infos, spawn, résultat).
function InGameMenuRules.keyTarget(gameState: string, view: View): KeyTarget
	if view ~= "closed" or InGameMenuRules.available(gameState) then
		return "inGame"
	end
	if gameState == "MENU" then
		return "mainMenu"
	end
	return "none"
end

-- Cette méthode permet de calculer la vue après un appui sur la touche du menu en partie : elle ferme tout ce qui est
-- ouvert (Réglages compris), sinon ouvre l'accueil du menu si l'état le permet.
function InGameMenuRules.onMenuKey(view: View, gameState: string): View
	if view ~= "closed" then
		return "closed"
	end
	return if InGameMenuRules.available(gameState) then "main" else "closed"
end

-- Cette méthode permet de calculer la vue après un choix du joueur dans le menu : REPRENDRE et MENU PRINCIPAL ferment,
-- RÉGLAGES ouvre l'écran Réglages depuis l'accueil, RETOUR (des Réglages) revient à l'accueil.
function InGameMenuRules.onChoice(view: View, choice: Choice): View
	if choice == "resume" or choice == "leave" then
		return "closed"
	elseif choice == "settings" then
		return if view == "main" then "settings" else view
	elseif choice == "back" then
		return if view == "settings" then "main" else view
	end
	return view
end

-- Cette méthode permet de fermer le menu lorsque l'état client passe hors partie (menu, résultat, spawn) ; il reste
-- ouvert entre la mort et la réapparition.
function InGameMenuRules.onGameState(view: View, gameState: string): View
	return if InGameMenuRules.available(gameState) then view else "closed"
end

-- Cette méthode permet de savoir si le menu couvre la partie (souris libérée, entrées de jeu coupées, crosshair et
-- affichage des touches masqués) lorsqu'une vue est appliquée.
function InGameMenuRules.isOpen(view: View): boolean
	return view ~= "closed"
end

return InGameMenuRules

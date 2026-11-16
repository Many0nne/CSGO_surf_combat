-- Suivi pur de l'achat de pack en cours dans la fenêtre des packs (#409) : un seul prompt Robux à la fois, même s'il reste
-- ouvert plus longtemps que le délai de secours. Utilisé par CreditPackWindow, testé (tests/specs/PurchaseGuard.spec.luau).
--
-- Chaque achat porte un numéro. Le délai de secours ne le termine que si aucune fin de prompt n'est arrivée et que le
-- prompt n'est pas connu comme ouvert (le serveur a répondu `ok`) ; la fin d'un prompt ne termine l'achat en cours que
-- pour son produit, et jamais un achat lancé depuis (son numéro a changé).
local PurchaseGuard = {}

export type State = {
	current: number, -- numéro du dernier achat lancé
	active: boolean, -- un achat est en cours (prix inactifs)
	promptOpen: boolean, -- le serveur a ouvert le prompt de l'achat en cours
	productId: number?, -- produit de l'achat en cours
}

-- Cette méthode permet de créer le suivi lorsque la fenêtre est chargée : aucun achat en cours.
function PurchaseGuard.new(): State
	return { current = 0, active = false, promptOpen = false, productId = nil }
end

-- Cette méthode permet de lancer un achat lorsque le joueur clique un prix ; renvoie son numéro, ou nil si un achat
-- est déjà en cours (aucun second prompt).
function PurchaseGuard.start(state: State, productId: number): number?
	if state.active then
		return nil
	end
	state.current += 1
	state.active = true
	state.promptOpen = false
	state.productId = productId
	return state.current
end

-- Cette méthode permet de noter que le prompt de l'achat `id` est ouvert lorsque le serveur répond `ok` ; sans effet
-- pour un achat passé ou déjà terminé (prompt déjà fermé).
function PurchaseGuard.promptOpened(state: State, id: number)
	if id == state.current and state.active then
		state.promptOpen = true
	end
end

-- Cette méthode permet de terminer l'achat `id` lorsque le serveur refuse ; renvoie vrai si c'est l'achat en cours.
function PurchaseGuard.refused(state: State, id: number): boolean
	if id ~= state.current or not state.active then
		return false
	end
	state.active = false
	state.promptOpen = false
	return true
end

-- Cette méthode permet de terminer l'achat `id` lorsque le délai de secours passe ; renvoie vrai seulement si l'achat est
-- toujours le courant et que son prompt n'est pas connu comme ouvert (sinon la fin du prompt le terminera).
-- `final` (dernier délai, très long) le termine même prompt ouvert, si Roblox n'a jamais signalé sa fin.
function PurchaseGuard.timedOut(state: State, id: number, final: boolean?): boolean
	if id ~= state.current or not state.active or (state.promptOpen and not final) then
		return false
	end
	state.promptOpen = false
	state.active = false
	return true
end

-- Cette méthode permet de terminer l'achat lorsque Roblox signale la fin d'un prompt ; renvoie vrai si elle concerne
-- l'achat en cours (même produit), faux pour la fin d'un autre produit ou lorsqu'aucun achat n'est en cours.
function PurchaseGuard.finished(state: State, productId: number): boolean
	if not state.active or state.productId ~= productId then
		return false
	end
	state.active = false
	state.promptOpen = false
	return true
end

return PurchaseGuard

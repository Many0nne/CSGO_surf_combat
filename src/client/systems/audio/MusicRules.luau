-- Musique de fond (#286), règles pures (testées sous Lune) : niveau visé selon l'écran et le combat, et fondu vers ce
-- niveau. Pleine au menu, atténuée en partie, encore plus pendant un combat (tir, dégât reçu ou tir proche récent) pour
-- garder les pas et les tirs audibles. Le niveau multiplie BASE_VOLUME ; le canal « Music » (SoundChannels) applique
-- ensuite le volume de la musique, puis le général.

local MusicRules = {}

-- Piste jouée en boucle : son de la bibliothèque sous licence de Roblox (un son mis en ligne par un tiers ne joue pas
-- dans le jeu). Vide : pas de musique. « Hot For a Minute (underscore) », APM (hip-hop sourd, cuivres, 2:23), choisie
-- parmi des pistes sans synthé en avant : la synthwave faisait « néon », hors de la DA « Ligne de mire » (docs/ui.md).
MusicRules.TRACK_ID = "rbxassetid://9044591415"
-- Volume du son à niveau 1 (menu, curseurs à 100) : la piste ne doit pas couvrir les sons du jeu
MusicRules.BASE_VOLUME = 0.5

-- Niveaux (fraction de BASE_VOLUME) : écrans du menu, partie, combat
MusicRules.LEVEL = {
	menu = 1,
	round = 0.35,
	combat = 0.12,
}
-- États du client (GameStateController) où la musique joue à plein : menu et écran Infos
MusicRules.MENU_STATES = { MENU = true, INFOS = true }
-- s : le combat dure tant qu'un tir ou un dégât date de moins de COMBAT_HOLD
MusicRules.COMBAT_HOLD = 6
-- studs : un tir d'un autre dont l'origine est plus proche compte comme un combat
MusicRules.COMBAT_RADIUS = 150
-- s pour un écart de niveau de 1 : baisse rapide (le combat commence), remontée lente
MusicRules.FADE_DOWN = 0.5
MusicRules.FADE_UP = 3

-- Cette méthode permet de donner le niveau visé de la musique lorsqu'il est recalculé à chaque frame : 0 si le réglage
-- est coupé, plein au menu, atténué en partie, au plus bas si le dernier combat date de moins de COMBAT_HOLD.
function MusicRules.targetLevel(enabled: boolean, state: string?, sinceCombat: number?): number
	if not enabled then
		return 0
	end
	if state == nil or MusicRules.MENU_STATES[state] then
		return MusicRules.LEVEL.menu
	end
	if sinceCombat and sinceCombat < MusicRules.COMBAT_HOLD then
		return MusicRules.LEVEL.combat
	end
	return MusicRules.LEVEL.round
end

-- Cette méthode permet d'avancer le niveau courant vers le niveau visé lorsqu'une frame passe : la baisse prend
-- FADE_DOWN par unité de niveau, la remontée FADE_UP, sans jamais dépasser la cible.
function MusicRules.step(current: number, target: number, dt: number): number
	if current > target then
		return math.max(target, current - dt / MusicRules.FADE_DOWN)
	end
	return math.min(target, current + dt / MusicRules.FADE_UP)
end

-- Cette méthode permet de savoir si un tir d'un autre est assez proche pour compter comme un combat lorsqu'il est relayé.
function MusicRules.isNearShot(listener: Vector3?, origin: any): boolean
	if not listener or typeof(origin) ~= "Vector3" then
		return false
	end
	return (origin - listener).Magnitude <= MusicRules.COMBAT_RADIUS
end

return MusicRules

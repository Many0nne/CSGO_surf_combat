-- Musique de fond (#286), règles pures (testées sous Lune) : volume visé selon l'écran et les annonces, et fondu vers ce
-- volume. Deux réglages de volume, un pour les écrans du menu et un pour la partie ; seules les annonces vocales
-- (KillAnnouncer : « Headshot », « Double kill »…) baissent la musique le temps de la voix, pas les tirs. Le volume
-- visé multiplie BASE_VOLUME ; le canal « Music » (SoundChannels) applique ensuite le volume général.

local MusicRules = {}

-- Piste jouée en boucle : son de la bibliothèque sous licence de Roblox (un son mis en ligne par un tiers ne joue pas
-- dans le jeu). Vide : pas de musique. « Hot For a Minute (underscore) », APM (hip-hop sourd, cuivres, 2:23), choisie
-- parmi des pistes sans synthé en avant : la synthwave faisait « néon », hors de la DA « Ligne de mire » (docs/ui.md).
MusicRules.TRACK_ID = "rbxassetid://9044591415"
-- Volume du son à 100 % (curseur à 100, volume général à 100) : la piste ne doit pas couvrir les sons du jeu
MusicRules.BASE_VOLUME = 0.5

-- États du client (GameStateController) où joue le volume du menu : menu et écran Infos ; tous les autres = partie
MusicRules.MENU_STATES = { MENU = true, INFOS = true }
-- Fraction gardée pendant une annonce vocale
MusicRules.ANNOUNCE_DUCK = 0.3
-- s pour un écart de volume de 1 : baisse rapide (l'annonce part tout de suite), remontée plus lente
MusicRules.FADE_DOWN = 0.25
MusicRules.FADE_UP = 1.5

export type MusicSettings = { music: boolean, volumeMusicMenu: number, volumeMusicGame: number }

-- Cette méthode permet de savoir si la musique doit baisser lorsqu'une annonce vocale joue (#405) : pas si la voix est
-- muette, c'est-à-dire si le volume des annonces ou le volume général est à 0.
function MusicRules.isDucking(settings: { volumeMaster: number, volumeAnnouncer: number }, speaking: boolean): boolean
	return speaking and settings.volumeMaster > 0 and settings.volumeAnnouncer > 0
end

-- Cette méthode permet de donner le volume visé de la musique (0 à 1) lorsqu'il est recalculé à chaque frame : 0 si
-- le réglage est coupé, sinon le curseur du menu ou de la partie selon l'écran, baissé pendant une annonce vocale.
function MusicRules.targetVolume(settings: MusicSettings, state: string?, announcing: boolean): number
	if not settings.music then
		return 0
	end
	local inMenu = state == nil or MusicRules.MENU_STATES[state] == true
	local percent = if inMenu then settings.volumeMusicMenu else settings.volumeMusicGame
	local volume = percent / 100
	if announcing then
		volume *= MusicRules.ANNOUNCE_DUCK
	end
	return volume
end

-- Cette méthode permet d'avancer le volume courant vers le volume visé lorsqu'une frame passe : la baisse prend
-- FADE_DOWN par unité, la remontée FADE_UP, sans jamais dépasser la cible.
function MusicRules.step(current: number, target: number, dt: number): number
	if current > target then
		return math.max(target, current - dt / MusicRules.FADE_DOWN)
	end
	return math.min(target, current + dt / MusicRules.FADE_UP)
end

return MusicRules

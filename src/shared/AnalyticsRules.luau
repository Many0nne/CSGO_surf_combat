-- Règles pures des analytics (#527), partagées par le client (écrans signalés) et le serveur (server/analytics) :
-- écrans que le client peut signaler, étapes des funnels, noms des événements et des champs, valeurs bornées des champs
-- (pas d'identifiant libre ni de position brute : cardinalité limitée par AnalyticsService). Testées sous Lune
-- (tests/specs/Analytics.spec.luau). Lecture des tableaux de bord : docs/analytics.md.

local AnalyticsRules = {}

-- ── Écrans signalés par le client (remote AnalyticsScreen) ──────────────────

-- Écran où se trouve le joueur, vu par son client : chargement, en partie (le détail vivant/mort est connu du serveur),
-- onglet du menu, vues du shop. Seules ces valeurs passent la garde du remote (RemoteGuard).
AnalyticsRules.Screen = {
	LOADING = "loading",
	PLAYING = "playing",
	HOME = "menu_home",
	SHOP = "menu_shop",
	INFOS = "menu_infos",
	LEARN = "menu_learn",
	SETTINGS = "menu_settings",
	FEEDBACK = "menu_feedback",
	LOBBY = "menu_lobby", -- lobby ouvert par JOUER (#523)
	SHOP_DETAIL = "shop_detail",
	CRATE_OPENING = "crate_opening",
	CREDIT_PACKS = "credit_packs",
}

local S = AnalyticsRules.Screen

AnalyticsRules.SCREENS = {
	S.LOADING,
	S.PLAYING,
	S.HOME,
	S.SHOP,
	S.INFOS,
	S.LEARN,
	S.SETTINGS,
	S.FEEDBACK,
	S.LOBBY,
	S.SHOP_DETAIL,
	S.CRATE_OPENING,
	S.CREDIT_PACKS,
}

-- Écrans du shop (onglet, détail d'une caisse, ouverture, fenêtre des packs) : une visite du shop les enchaîne
local SHOP_SCREENS = {
	[S.SHOP] = true,
	[S.SHOP_DETAIL] = true,
	[S.CRATE_OPENING] = true,
	[S.CREDIT_PACKS] = true,
}

-- Écrans du menu principal par page de MainMenu (client/ui/MainMenu.luau, type Page)
local MENU_PAGES = {
	home = S.HOME,
	shop = S.SHOP,
	infos = S.INFOS,
	learn = S.LEARN,
	settings = S.SETTINGS,
	feedback = S.FEEDBACK,
	lobby = S.LOBBY,
}

-- Période (s) de relevé de l'écran par le client : un écran tenu moins longtemps peut ne pas être vu. Garder sous le
-- débit de la règle AnalyticsScreen de RemoteGuard (un envoi par changement au plus).
AnalyticsRules.POLL_INTERVAL = 0.5

-- Cette méthode permet de traduire une page du menu principal en écran signalé lorsque le client relève l'écran ;
-- page inconnue : accueil.
function AnalyticsRules.menuScreen(page: string): string
	return MENU_PAGES[page] or S.HOME
end

-- Cette méthode permet de savoir si un écran est un écran du menu principal (shop compris) lorsque le serveur détecte
-- l'arrivée au menu ou le clic sur JOUER.
function AnalyticsRules.isMenu(screen: string?): boolean
	return screen ~= nil and screen ~= S.LOADING and screen ~= S.PLAYING
end

-- Cette méthode permet de savoir si un écran fait partie du shop lorsque le serveur découpe les visites du shop.
function AnalyticsRules.isShop(screen: string?): boolean
	return screen ~= nil and SHOP_SCREENS[screen] == true
end

-- ── Funnels ──────────────────────────────────────────────────────────────────

export type Step = { step: number, name: string }

-- Funnel d'onboarding (LogOnboardingFunnelStepEvent) : première session, chaque étape une fois
AnalyticsRules.Onboarding = {
	LOADED = { step = 1, name = "Chargement terminé" },
	MENU = { step = 2, name = "Menu affiché" },
	PLAY = { step = 3, name = "Clic sur JOUER" },
	SPAWN = { step = 4, name = "Premier spawn" },
	SHOT = { step = 5, name = "Premier tir" },
	DAMAGE = { step = 6, name = "Premier dégât infligé" },
	KILL = { step = 7, name = "Premier kill" },
	DEATH = { step = 8, name = "Première mort" },
	ROUND_END = { step = 9, name = "Première manche finie" },
	SECOND_ROUND = { step = 10, name = "Deuxième manche commencée" },
}

-- Funnel de session (LogFunnelStepEvent, un funnelSessionId par visite)
AnalyticsRules.SESSION_FUNNEL = "Session"
AnalyticsRules.Session = {
	ARRIVAL = { step = 1, name = "Arrivée" },
	MENU = { step = 2, name = "Menu" },
	IN_GAME = { step = 3, name = "En partie" },
	ROUND_1 = { step = 4, name = "1 manche jouée" },
	ROUND_3 = { step = 5, name = "3 manches jouées" },
	BACK_TO_MENU = { step = 6, name = "Retour au menu" },
	DEPARTURE = { step = 7, name = "Départ" },
}

-- Funnel du shop : un funnelSessionId par visite du shop (entrée dans l'onglet SHOP depuis un autre écran)
AnalyticsRules.SHOP_FUNNEL = "Shop"
AnalyticsRules.Shop = {
	TAB = { step = 1, name = "Onglet SHOP" },
	DETAIL = { step = 2, name = "Détail d'une caisse" },
	BUY = { step = 3, name = "ACHETER" },
	OPENED = { step = 4, name = "Caisse ouverte" },
	EQUIPPED = { step = 5, name = "Skin équipé" },
}

-- Funnel des packs de crédits en Robux : un funnelSessionId par ouverture de la fenêtre des packs
AnalyticsRules.PACK_FUNNEL = "PacksRobux"
AnalyticsRules.Packs = {
	SHOWN = { step = 1, name = "Packs affichés" },
	PROMPT = { step = 2, name = "Prompt d'achat" },
	RECEIPT = { step = 3, name = "Reçu traité" },
}

-- ── Événements personnalisés et économie ─────────────────────────────────────

AnalyticsRules.Event = {
	-- Départ du jeu : valeur = durée de la session (s) ; champs : endroit, manches jouées, ancienneté
	DEPARTURE = "Depart",
	-- Temps passé sur un écran (s), envoyé en le quittant ; champ : écran
	SCREEN_TIME = "TempsEcran",
	-- Temps entre la première arrivée au menu et le premier clic sur JOUER (s) ; champ : ancienneté
	MENU_BEFORE_PLAY = "MenuAvantJouer",
	-- Morts d'affilée sans kill, aux paliers DEATH_STREAK_MARKS ; valeur = longueur de la série ; champ : ancienneté
	DEATH_STREAK = "MortsSansKill",
	-- Mort d'un joueur en partie ; champs : zone de la map, cause
	DEATH = "Mort",
}

-- Clés des champs personnalisés (Enum.AnalyticsCustomFieldKeys.CustomField0N.Name), trois au plus par événement
AnalyticsRules.Field = {
	ONE = "CustomField01",
	TWO = "CustomField02",
	THREE = "CustomField03",
}

-- Monnaie du jeu pour LogEconomyEvent, et types de transaction (Enum.AnalyticsEconomyTransactionType.<x>.Name)
AnalyticsRules.CURRENCY = "Credits"
AnalyticsRules.Transaction = {
	GAMEPLAY = "Gameplay",
	IAP = "IAP",
	SHOP = "Shop",
}
-- Objet d'un gain en jouant (kill, manche, victoire : non distingués par WalletStore.addPlayGain)
AnalyticsRules.PLAY_GAIN_SKU = "jeu"

-- Paliers de morts d'affilée sans kill signalés une fois chacun par série
AnalyticsRules.DEATH_STREAK_MARKS = { 3, 5, 10 }
-- Temps minimal (s) sur un écran pour envoyer TempsEcran (un passage éclair n'apprend rien et coûte un événement)
AnalyticsRules.SCREEN_TIME_MIN = 2
-- Plafond d'événements TempsEcran par session (limites de débit d'AnalyticsService)
AnalyticsRules.SCREEN_TIME_MAX_EVENTS = 100
-- Grille des zones de la map (colonnes × lignes) pour l'événement Mort : 16 valeurs au plus
AnalyticsRules.ZONE_COLUMNS = 4
AnalyticsRules.ZONE_ROWS = 4
local COLUMN_LETTERS = { "A", "B", "C", "D", "E", "F", "G", "H" }

-- Phase du joueur en partie, connue du serveur : arrivée (apparition en cours), vivant, mort, bannière de fin
export type Phase = "arrivee" | "vivant" | "mort" | "resultat"

-- Cette méthode permet de ranger un nombre de manches jouées dans une classe bornée lorsqu'il part dans un champ.
function AnalyticsRules.roundsBucket(rounds: number): string
	if rounds <= 0 then
		return "0"
	elseif rounds == 1 then
		return "1"
	elseif rounds <= 3 then
		return "2-3"
	elseif rounds <= 9 then
		return "4-9"
	end
	return "10+"
end

-- Cette méthode permet de nommer l'ancienneté d'un joueur lorsqu'elle part dans un champ : nouveau (aucune
-- statistique enregistrée), habitué, ou inconnu (statistiques pas chargées).
function AnalyticsRules.newcomerLabel(isNew: boolean?): string
	if isNew == nil then
		return "inconnu"
	end
	return if isNew then "nouveau" else "habitue"
end

-- Cette méthode permet de décrire l'endroit où se trouve un joueur lorsqu'il quitte le jeu : écran du client, précisé
-- par la phase serveur quand il est en partie.
function AnalyticsRules.location(screen: string?, phase: Phase): string
	if screen == nil then
		return "inconnu"
	end
	if screen == S.PLAYING then
		return "partie_" .. phase
	end
	return screen
end

-- Cette méthode permet de nommer la cause d'une mort lorsqu'elle est comptée : sans tueur (chute dans le vide), tuée
-- par un bot ou par un joueur.
function AnalyticsRules.deathCause(hasKiller: boolean, killerIsBot: boolean): string
	if not hasKiller then
		return "chute"
	end
	return if killerIsBot then "bot" else "joueur"
end

export type Bounds = { minX: number, minZ: number, maxX: number, maxZ: number }

-- Cette méthode permet de ranger une position (X, Z) dans la grille des zones de la map lorsqu'une mort est comptée :
-- colonne en lettre (X), ligne en chiffre (Z), hors de la boîte ramené au bord ; « ? » sans boîte connue.
function AnalyticsRules.zone(x: number, z: number, bounds: Bounds?): string
	if not bounds or bounds.maxX <= bounds.minX or bounds.maxZ <= bounds.minZ then
		return "?"
	end
	local cols, rows = AnalyticsRules.ZONE_COLUMNS, AnalyticsRules.ZONE_ROWS
	local u = (x - bounds.minX) / (bounds.maxX - bounds.minX)
	local v = (z - bounds.minZ) / (bounds.maxZ - bounds.minZ)
	local col = math.clamp(math.floor(u * cols) + 1, 1, cols)
	local row = math.clamp(math.floor(v * rows) + 1, 1, rows)
	return COLUMN_LETTERS[col] .. tostring(row)
end

-- Cette méthode permet de savoir si une longueur de série de morts est un palier à signaler lorsqu'une mort l'allonge.
function AnalyticsRules.isStreakMark(streak: number): boolean
	return table.find(AnalyticsRules.DEATH_STREAK_MARKS, streak) ~= nil
end

return AnalyticsRules

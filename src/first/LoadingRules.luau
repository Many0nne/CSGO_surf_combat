-- Règles pures de l'écran de chargement (#480), sans Instance ni service : quand lever l'écran du lancement, quel
-- libellé montrer, et apparence copiée de UITheme. Testées sous Lune (tests/specs/LoadingRules.spec.luau).
--
-- Dans ReplicatedFirst : l'écran se construit avant que ReplicatedStorage soit répliqué, il ne peut pas lire UITheme.
-- Ses couleurs et la durée des volets en sont copiées ici ; le test vérifie qu'elles le suivent.
local LoadingRules = {}

-- Libellés au centre de l'écran : lancement, départ vers l'entraînement, départ vers un serveur public
LoadingRules.INITIAL_LABEL = "CHARGEMENT"
LoadingRules.JOIN_LABEL = "ENTRAÎNEMENT"
LoadingRules.LEAVE_LABEL = "RETOUR EN PARTIE"
-- Départ vers le serveur d'un ami (REJOINDRE du lobby, #523 ; PartyService : { partyHost = id })
LoadingRules.FOLLOW_LABEL = "REJOINDRE UN AMI"

-- Traduction anglaise des libellés (#518). L'écran tourne avant que ReplicatedStorage soit répliqué : il ne peut pas
-- lire Locale, il garde sa petite table ici (les mêmes textes sont dans Locale/en/Menu : le test de LoadingRules
-- vérifie que les deux disent la même chose). Les libellés ci-dessus sont les clés françaises.
LoadingRules.EN = {
	["CHARGEMENT"] = "LOADING",
	["ENTRAÎNEMENT"] = "TRAINING",
	["RETOUR EN PARTIE"] = "BACK TO GAME",
	["REJOINDRE UN AMI"] = "JOINING A FRIEND",
} :: { [string]: string }

-- Durée (s) au plus courte de l'écran du lancement : levé plus tôt, il clignoterait (playtest Studio, jeu en cache)
LoadingRules.MIN_SHOWN = 0.8
-- Durée (s) au plus longue de l'écran du lancement : passé ce délai il se lève même si le menu n'est pas prêt, pour
-- qu'un module en échec ou une connexion lente ne laisse jamais le joueur devant un écran figé
LoadingRules.MAX_WAIT = 30
-- Délai (s) au bout duquel l'écran d'une téléportation sans suite se rouvre sur le menu (même délai que celui de
-- TrainingService pour une demande en cours)
LoadingRules.COVER_TIMEOUT = 30

-- Apparence copiée de UITheme (volets de Transition) : C.SunWhite, C.Ground, Motion.Shutter
LoadingRules.PANEL_COLOR = Color3.fromRGB(255, 241, 224)
LoadingRules.TEXT_COLOR = Color3.fromRGB(21, 24, 28)
LoadingRules.SHUTTER_TIME = 0.45
LoadingRules.FONT_FAMILY = "rbxasset://fonts/families/Oswald.json"

-- Cette méthode permet de traduire un libellé français de l'écran lorsqu'il s'affiche : anglais sauf si la langue du
-- compte Roblox (`LocalizationService.RobloxLocaleId`, « fr-fr »…) est le français, même règle que
-- `Locale.fromLocaleId` ; les réglages du joueur ne sont pas encore connus à ce moment.
function LoadingRules.translate(label: string, localeId: any): string
	if type(localeId) == "string" and string.lower(string.sub(localeId, 1, 2)) == "fr" then
		return label
	end
	return LoadingRules.EN[label] or label
end

-- Cette méthode permet de savoir si l'écran du lancement peut se lever lorsqu'il vérifie l'état du client : jeu chargé
-- et menu prêt après la durée minimale, ou délai maximal dépassé quoi qu'il arrive.
function LoadingRules.shouldRelease(elapsed: number, loaded: boolean, ready: boolean): boolean
	if elapsed >= LoadingRules.MAX_WAIT then
		return true
	end
	return loaded and ready and elapsed >= LoadingRules.MIN_SHOWN
end

-- Cette méthode permet de choisir le libellé d'une téléportation lorsque le joueur la demande : vers l'entraînement, ou
-- de l'entraînement vers un serveur public.
function LoadingRules.teleportLabel(joining: boolean): string
	return if joining then LoadingRules.JOIN_LABEL else LoadingRules.LEAVE_LABEL
end

-- Cette méthode permet de choisir le libellé de l'écran à l'arrivée sur un serveur d'après les données de téléportation
-- (TrainingService : { training = boolean } ; PartyService : { partyHost = id }, #523) ; sans données valides
-- (lancement depuis le site), celui du chargement.
function LoadingRules.arrivalLabel(data: any): string
	if type(data) == "table" and type(data.partyHost) == "number" then
		return LoadingRules.FOLLOW_LABEL
	end
	if type(data) ~= "table" or type(data.training) ~= "boolean" then
		return LoadingRules.INITIAL_LABEL
	end
	return LoadingRules.teleportLabel(data.training)
end

return LoadingRules

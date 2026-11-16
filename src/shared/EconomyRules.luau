-- Règles pures des gains de crédits en jouant (#394) : barème, manche jouée, plafond par manche puis par jour (jour
-- UTC), attributs informatifs lus par le client (bandeau de fin de manche, gains du jour au shop). Utilisées par le
-- serveur (CreditGains, InventoryStore, WalletRules.applyBatches) et le client (RoundHUD, MainMenu), testées
-- (tests/specs/EconomyRules.spec.luau).
--
-- Un kill est crédité tout de suite, la manche jouée et la victoire en fin de manche ; chaque gain passe d'abord par
-- le plafond de la manche (ce qui reste sous ROUND_CAP), puis par celui du jour (ce qui reste sous DAILY_CAP). Le
-- plafond du jour est réappliqué par la fusion de l'écriture (WalletRules.applyBatches, champs `day` et `dayEarned`
-- du portefeuille) : deux serveurs en même temps ne le dépassent pas. Hors plafond : doublons remboursés (#393) et
-- crédits achetés (#395), qui ne passent pas par ces règles.
local EconomyRules = {}

-- Barème (valeurs de départ de #394, à ajuster)
EconomyRules.ROUND_PLAYED = 15 -- manche jouée (au moins un kill, ou PLAYED_ALIVE_SECONDS en vie avec une activité réelle)
EconomyRules.PLAYER_KILL = 5 -- kill sur un joueur
EconomyRules.BOT_KILL = 1 -- kill sur un bot
EconomyRules.ROUND_WON = 25 -- victoire de manche
EconomyRules.ROUND_CAP = 60 -- plafond par manche (kills, manche jouée et victoire réunis)
EconomyRules.DAILY_CAP = 250 -- plafond par jour UTC, remis à zéro à 00:00 UTC
-- Temps en vie dans la manche (cumulé sur ses vies) qui fait compter une manche sans kill : écarte l'AFK qui ne fait
-- qu'apparaître
EconomyRules.PLAYED_ALIVE_SECONDS = 120
-- Activité réelle exigée en plus du temps en vie pour une manche sans kill (#401), mesurée par le serveur : portée
-- (studs), plus grand écart horizontal au point d'apparition en cumulant les pas acceptés sans signalement par
-- CharacterSync (un aller-retour sur place ne l'augmente pas), ou touches qui ont fait des dégâts (tir ou coup de mêlée validés). Un
-- joueur immobile reste à 0 stud, un surf de 137 s sans kill fait 538 studs (mesures du 16/11/2026, docs/economie.md).
EconomyRules.PLAYED_MIN_REACH = 150
EconomyRules.PLAYED_MIN_HITS = 1
EconomyRules.SECONDS_PER_DAY = 86400

-- Attributs informatifs du Player, posés par le serveur, jamais relus par lui : gains de la dernière manche jouée
-- (nombre, effacé à chaque apparition) et gains du jour (« jour:montant », jour UTC du serveur)
EconomyRules.ROUND_ATTRIBUTE = "RoundCredits"
EconomyRules.DAILY_ATTRIBUTE = "DailyCredits"

-- Cette méthode permet de savoir si une valeur est un entier positif ou nul fini (montant, jour, compteur) lorsqu'une
-- entrée ou un attribut est vérifié.
local function isCount(value: any): boolean
	return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

-- Cette méthode permet de calculer le jour UTC (jours depuis l'epoch Unix) d'un instant `os.time()` lorsqu'un gain est
-- daté ou que les gains du jour sont affichés.
function EconomyRules.day(unixTime: number): number
	return unixTime // EconomyRules.SECONDS_PER_DAY
end

-- Cette méthode permet de donner les secondes jusqu'au prochain minuit UTC lorsque LocalWallet.observeDaily programme le
-- repaint des gains du jour ; toujours entre 0 (exclu) et SECONDS_PER_DAY (à minuit pile, le prochain est dans un jour entier).
function EconomyRules.secondsUntilNextDay(unixTime: number): number
	return EconomyRules.SECONDS_PER_DAY - unixTime % EconomyRules.SECONDS_PER_DAY
end

-- Cette méthode permet de savoir si un jour relu (portefeuille, lot, attribut) est valide.
function EconomyRules.isDay(value: any): boolean
	return isCount(value)
end

-- Cette méthode permet de donner le gain d'un kill lorsqu'un joueur tue (joueur : PLAYER_KILL, bot : BOT_KILL).
function EconomyRules.killGain(victimIsBot: boolean): number
	return if victimIsBot then EconomyRules.BOT_KILL else EconomyRules.PLAYER_KILL
end

-- Activité d'un joueur dans une manche, mesurée par le serveur (#401) : portée (studs, plus grand écart horizontal au
-- point d'apparition de chaque vie, additionné sur ses vies) et touches qui ont fait des dégâts
export type Activity = { reach: number, hits: number }

-- Cette méthode permet de savoir si une activité mesurée par le serveur est réelle lorsqu'une manche sans kill se
-- termine : portée d'au moins PLAYED_MIN_REACH studs, ou PLAYED_MIN_HITS touches.
function EconomyRules.isActive(activity: Activity): boolean
	return activity.reach >= EconomyRules.PLAYED_MIN_REACH or activity.hits >= EconomyRules.PLAYED_MIN_HITS
end

-- Cette méthode permet de savoir si une manche compte comme jouée lorsqu'elle se termine : au moins un kill, ou
-- PLAYED_ALIVE_SECONDS cumulées en vie avec une activité réelle (#401 : un AFK que personne ne tue ne compte pas).
function EconomyRules.played(kills: number, aliveSeconds: number, activity: Activity): boolean
	return kills > 0 or (aliveSeconds >= EconomyRules.PLAYED_ALIVE_SECONDS and EconomyRules.isActive(activity))
end

-- Cette méthode permet de calculer la longueur (studs) d'un écart horizontal (dx, dz) lorsque la portée d'un joueur
-- est mesurée : la hauteur (chute, saut sur place) n'y entre pas.
function EconomyRules.horizontalLength(dx: number, dz: number): number
	return math.sqrt(dx * dx + dz * dz)
end

-- Cette méthode permet de calculer le gain de fin de manche (manche jouée, plus la victoire) avant plafonds ; 0 si la
-- manche n'est pas jouée (un vainqueur a forcément un kill, donc une manche jouée).
function EconomyRules.roundGain(kills: number, aliveSeconds: number, activity: Activity, won: boolean): number
	if not EconomyRules.played(kills, aliveSeconds, activity) then
		return 0
	end
	return EconomyRules.ROUND_PLAYED + (if won then EconomyRules.ROUND_WON else 0)
end

-- Cette méthode permet d'écrêter un gain à ce qui reste sous le plafond de la manche lorsqu'il est crédité.
function EconomyRules.capRound(amount: number, roundEarned: number): number
	return math.clamp(amount, 0, math.max(EconomyRules.ROUND_CAP - roundEarned, 0))
end

-- Cette méthode permet d'écrêter un gain à ce qui reste sous le plafond du jour lorsqu'il est crédité.
function EconomyRules.capDay(amount: number, dayEarned: number): number
	return math.clamp(amount, 0, math.max(EconomyRules.DAILY_CAP - dayEarned, 0))
end

-- Cette méthode permet de savoir si un gain en jouant est permis lorsqu'un kill ou une fin de manche arrive : jamais
-- sur un serveur d'entraînement (#345) ni hors d'une manche active.
function EconomyRules.canEarn(training: boolean, roundActive: boolean): boolean
	return not training and roundActive
end

-- Cette méthode permet d'écrire l'attribut des gains du jour (« jour:montant ») lorsque le serveur les publie.
function EconomyRules.encodeDaily(day: number, earned: number): string
	return string.format("%d:%d", day, earned)
end

-- Cette méthode permet de relire l'attribut des gains du jour pour le jour `today` du client lorsque le shop l'affiche :
-- nil (pas chargé) si absent ou illisible, 0 si l'attribut date d'un jour passé (minuit UTC passé depuis).
function EconomyRules.decodeDaily(value: any, today: number): number?
	if type(value) ~= "string" then
		return nil
	end
	local dayText, earnedText = string.match(value, "^(%d+):(%d+)$")
	local day, earned = tonumber(dayText), tonumber(earnedText)
	if not (isCount(day) and isCount(earned)) then
		return nil
	end
	-- Jour plus récent que celui du client (le client lit l'heure du serveur, `GetServerTimeNow`, mais un écart de
	-- quelques millisecondes à minuit reste possible) : celui du serveur fait foi
	return if (day :: number) < today then 0 else earned
end

-- Cette méthode permet d'écrire « N / 250 » (« — / 250 » tant que ce n'est pas chargé) lorsque le shop affiche les
-- gains du jour.
function EconomyRules.dailyLabel(earned: number?): string
	return string.format("%s / %d", if earned then tostring(earned) else "—", EconomyRules.DAILY_CAP)
end

export type RoundBanner = { amount: number?, capReached: boolean }

-- Cette méthode permet de décider ce que montre le bandeau de fin de manche (« +N CRÉDITS », « PLAFOND DU JOUR ATTEINT »)
-- lorsqu'il s'affiche ; nil s'il n'y a rien à dire (pas de gain possible, attribut absent, manche sans gain).
function EconomyRules.roundBanner(roundCredits: any, dailyEarned: number?): RoundBanner?
	if not isCount(roundCredits) then
		return nil
	end
	local capReached = dailyEarned ~= nil and dailyEarned >= EconomyRules.DAILY_CAP
	local amount = if roundCredits > 0 then roundCredits else nil
	if amount == nil and not capReached then
		return nil
	end
	return { amount = amount, capReached = capReached }
end

return EconomyRules

-- Règles pures du HUD (sans Instance ni service) : paliers de vitesse, timer, classement, barre d'armes.
-- Testées sous Lune (tests/specs/HUDRules.spec.luau).
local HUDRules = {}

-- Seuils des paliers de vitesse en studs/s horizontaux (course ≈ 30) ; le dernier passe le compteur au rouge
HUDRules.SPEED_TIERS = {
	{ min = 0, name = "—" },
	{ min = 30, name = "RUN" },
	{ min = 70, name = "FAST" },
	{ min = 120, name = "SURF" },
	{ min = 180, name = "MACH" },
}

-- Vitesse à laquelle la ligne du speedometer est pleine (entrée du dernier palier)
HUDRules.SPEED_FILL_MAX = 180

HUDRules.LOW_TIME_THRESHOLD = 30

-- Secondes sans changement d'arme avant que la barre ne garde que l'arme en main
HUDRules.WEAPON_BAR_FADE_DELAY = 2.5

export type Score = { name: string, kills: number, deaths: number }

-- Cette méthode permet de trouver l'index du palier atteint lorsque le speedometer reçoit une vitesse.
function HUDRules.speedTier(speed: number): number
	local index = 1
	for i, tier in HUDRules.SPEED_TIERS do
		if speed >= tier.min then
			index = i
		end
	end
	return index
end

-- Cette méthode permet de calculer la part remplie (0 à 1) de la ligne du speedometer lorsque la vitesse change.
function HUDRules.speedFill(speed: number): number
	return math.clamp(speed / HUDRules.SPEED_FILL_MAX, 0, 1)
end

-- Cette méthode permet de formater un nombre de secondes en « m:ss » lorsque le timer de round est mis à jour.
function HUDRules.formatTimer(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Cette méthode permet de savoir si le timer doit passer en alerte lorsque la fin du round approche.
function HUDRules.isLowTime(seconds: number): boolean
	return seconds <= HUDRules.LOW_TIME_THRESHOLD
end

-- Cette méthode permet de trier les scores du meilleur au moins bon lorsque le classement est reconstruit :
-- plus de kills d'abord, puis moins de morts, puis ordre alphabétique pour un affichage stable.
function HUDRules.sortScores(scores: { [any]: Score }): { Score }
	local sorted = {}
	for _, score in pairs(scores) do
		table.insert(sorted, score)
	end
	table.sort(sorted, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return a.name < b.name
	end)
	return sorted
end

-- Cette méthode permet de retrouver le rang d'un joueur dans un classement trié lorsque le HUD affiche « rang/total ».
function HUDRules.rankOf(sorted: { Score }, name: string): number?
	for i, score in sorted do
		if score.name == name then
			return i
		end
	end
	return nil
end

-- Cette méthode permet de formater le ratio kills/morts lorsque la colonne K/D est remplie (morts nulles = kills).
function HUDRules.formatKD(kills: number, deaths: number): string
	if deaths == 0 then
		return string.format("%.2f", kills)
	end
	return string.format("%.2f", kills / deaths)
end

-- Cette méthode permet de calculer les secondes entières restantes avant réapparition lorsque l'overlay de mort tourne.
function HUDRules.secondsLeft(endTime: number, now: number): number
	return math.max(0, math.ceil(endTime - now))
end

-- Cette méthode permet de trouver l'emplacement d'arme voisin (en bouclant) lorsque la molette ou L1/R1 change d'arme ;
-- sans arme en main, on part du premier emplacement vers l'avant et du dernier vers l'arrière.
function HUDRules.cycleSlot(current: number?, count: number, step: number): number?
	if count <= 0 then
		return nil
	end
	if not current then
		return step > 0 and 1 or count
	end
	return (current - 1 + step) % count + 1
end

-- Cette méthode permet de transformer le nom d'un outil en libellé de la barre d'armes lorsqu'un emplacement est créé :
-- espace avant une majuscule qui suit une minuscule ou un chiffre (« M9Bayonet » → « M9 BAYONET »), puis majuscules.
function HUDRules.weaponLabel(toolName: string): string
	local spaced = string.gsub(toolName, "([%l%d])(%u)", "%1 %2")
	return string.upper(spaced)
end

-- Cette méthode permet de trier les noms d'outils dans l'ordre des emplacements (alphabétique, comme le helper
-- DebugPlaytest) lorsque la barre d'armes est reconstruite.
function HUDRules.slotOrder(names: { string }): { string }
	local sorted = table.clone(names)
	table.sort(sorted)
	return sorted
end

-- Cette méthode permet de savoir si le HUD de jeu (vitesse, barre d'armes, lunette) est affiché lorsque l'état client change :
-- seulement en partie avec un personnage vivant (IN_ROUND), pas au menu, à la mort ni au résultat.
function HUDRules.gameHudVisible(state: string): boolean
	return state == "IN_ROUND"
end

return HUDRules

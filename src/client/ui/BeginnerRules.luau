-- Règles pures de l'aide de première partie (#291), sans Instance ni module requis : qui est « débutant », et choix du
-- conseil de l'écran de mort. Débutant = moins de BEGINNER_ROUNDS manches jouées, lu dans les statistiques persistantes
-- déjà publiées par le serveur (attribut `PlayerStats`, StatsRules.decode, #296) : aucun stockage propre. Statistiques
-- pas encore arrivées ou en échec de chargement : état inconnu, pas d'aide (un ancien joueur ne la revoit pas pendant
-- un chargement lent) ; seul l'attribut de debug Studio force l'un ou l'autre état. Les textes des conseils sont
-- composés par InfosRules.deathTips (touches de KeyBindings selon la disposition du clavier, aucune lettre en dur).
-- Testées sous Lune (tests/specs/BeginnerRules.spec.luau).
local BeginnerRules = {}

-- Un joueur est débutant tant qu'il a joué moins de manches que cela (choix de l'utilisateur, #291)
BeginnerRules.BEGINNER_ROUNDS = 3

-- Attribut du Player lu en Studio seulement : true force l'état débutant, false le contraire, absent = statistiques
-- (`player:SetAttribute("DebugBeginner", true)` en contexte Server)
BeginnerRules.DEBUG_ATTRIBUTE = "DebugBeginner"

-- Cette méthode permet de savoir si le joueur est débutant lorsque ses statistiques ou l'attribut de debug changent :
-- l'attribut de debug (booléen) l'emporte ; sans statistiques (nil : pas encore chargées ou en échec), pas débutant.
function BeginnerRules.isBeginner(stats: { roundsPlayed: number }?, debug: any): boolean
	if type(debug) == "boolean" then
		return debug
	end
	if not stats then
		return false
	end
	return stats.roundsPlayed < BeginnerRules.BEGINNER_ROUNDS
end

-- Cette méthode permet de choisir le conseil d'une mort lorsque l'écran de mort s'affiche : nil si le joueur n'est pas
-- débutant, a coupé les conseils ou s'il n'y en a aucun ; sinon un par mort, à tour de rôle (`index` : mort n°, dès 1).
function BeginnerRules.pickTip<T>(tips: { T }, beginner: boolean, enabled: boolean, index: number): T?
	if not (beginner and enabled) or #tips == 0 then
		return nil
	end
	return tips[(math.max(1, math.floor(index)) - 1) % #tips + 1]
end

return BeginnerRules

-- Règles pures de la population de bots (#144, décisions 2 et 7 de #133), testées
-- (tests/specs/BotPopulationRules.spec.luau) : nombre de bots voulu, bot à retirer, commande de debug Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)

local BotPopulationRules = {}

export type Candidate = {
	index: number, -- position du bot dans la liste du gestionnaire
	alive: boolean, -- personnage en jeu (faux : mort ou pas encore apparu)
	inDuel: boolean, -- en plein combat : cible vue ou contact récent
	sinceContact: number, -- secondes depuis son dernier contact avec une cible (math.huge : jamais)
}

-- Cette méthode permet de donner le nombre de bots voulu lorsque la population change : la cible moins les joueurs,
-- borné à [0, MAX_BOTS] ; 0 sans joueur (des bots seuls ne jouent pas) ou quand la population est suspendue (run de
-- DebugPlaytest).
function BotPopulationRules.wantedBots(humans: number, paused: boolean?): number
	if paused or humans <= 0 then
		return 0
	end
	return math.clamp(BotConfig.TARGET_POPULATION - math.max(humans, 0), 0, BotConfig.MAX_BOTS)
end

-- Cette méthode permet de choisir le bot à retirer lorsqu'il y en a trop : un bot hors du jeu d'abord (mort ou pas
-- encore apparu), puis le vivant le plus loin du combat (plus long sans contact). nil si tous sont en plein duel :
-- on réessaie plus tard, sauf si force est vrai (le bot le moins loin du combat part alors quand même).
function BotPopulationRules.pickRemoval(candidates: { Candidate }, force: boolean?): number?
	local best: Candidate? = nil
	local bestRank = -math.huge
	for _, candidate in candidates do
		if not candidate.alive then
			-- Hors du jeu : toujours le meilleur choix
			return candidate.index
		end
		if force or not candidate.inDuel then
			local rank = candidate.sinceContact
			if candidate.inDuel then
				rank = -1 -- forcé : un duel ne passe qu'après les bots hors combat
			end
			if rank > bestRank then
				best = candidate
				bestRank = rank
			end
		end
	end
	return if best then best.index else nil
end

-- Cette méthode permet de dire si un bot est en plein duel lorsqu'on veut le retirer : il combat, ou a vu une cible il y
-- a moins de POPULATION_DUEL_TIME secondes.
function BotPopulationRules.isInDuel(state: string, sinceContact: number): boolean
	return state == "combattre" or sinceContact < BotConfig.POPULATION_DUEL_TIME
end

-- Cette méthode permet de lire la commande de debug Studio lorsque l'attribut DebugBots change : renvoie le nombre
-- fixé de bots, ou nil pour revenir à la population automatique. Un nombre fixe (borné à [0, MAX_BOTS]), "+" ou "-"
-- (un bot de plus ou de moins que current), tout le reste (nil, "auto", texte inconnu) : automatique.
function BotPopulationRules.debugCommand(value: any, current: number): number?
	if type(value) == "number" then
		if value ~= value then
			return nil
		end
		return math.clamp(math.floor(value), 0, BotConfig.MAX_BOTS)
	end
	if value == "+" then
		return math.clamp(current + 1, 0, BotConfig.MAX_BOTS)
	elseif value == "-" then
		return math.clamp(current - 1, 0, BotConfig.MAX_BOTS)
	end
	return nil
end

return BotPopulationRules

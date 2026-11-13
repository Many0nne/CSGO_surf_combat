-- Règles pures du classement d'une manche (#295), partagées client/serveur : ordre des scores (classement de Tab, écran
-- de fin) et issue de la manche (vainqueur, égalité, aucun vainqueur). Testées (tests/specs/ScoreRules.spec.luau).
local ScoreRules = {}

-- Score d'un participant : `id` de participant (UserId, ou id négatif d'un bot), absent des anciens envois
export type Score = { id: number?, name: string, isBot: boolean?, kills: number, deaths: number }

-- Issue d'une manche : un vainqueur (son id), une égalité parfaite en tête, ou aucun vainqueur (aucun kill)
export type Outcome = "winner" | "tie" | "none"

-- Cette méthode permet de comparer deux scores lorsqu'un classement est trié ou un vainqueur cherché : négatif si `a`
-- passe devant `b` (plus de kills, puis moins de morts), positif s'il passe derrière, 0 à égalité parfaite.
function ScoreRules.compare(a: Score, b: Score): number
	if a.kills ~= b.kills then
		return b.kills - a.kills
	end
	return a.deaths - b.deaths
end

-- Cette méthode permet de désigner l'issue d'une manche parmi les scores des participants en jeu lorsqu'elle se termine :
-- aucun vainqueur sans kill, égalité si deux scores en tête sont identiques, sinon l'id du premier ; l'ordre de la liste
-- ne change rien au résultat.
function ScoreRules.outcome(scores: { Score }): (Outcome, number?)
	local best: Score? = nil
	local tied = false
	for _, score in scores do
		local diff = if best then ScoreRules.compare(score, best) else -1
		if diff < 0 then
			best = score
			tied = false
		elseif diff == 0 then
			tied = true
		end
	end
	if not best or best.kills == 0 then
		return "none", nil
	end
	if tied then
		return "tie", nil
	end
	return "winner", best.id
end

return ScoreRules

-- Notation des kills pour le clip de la partie (#499), règles pures sans Instance ni service (testées sous Lune,
-- tests/specs/HighlightRules.spec.luau). L'efficacité d'abord (FFA) : multi-kill, tir à la tête, série sans mourir ;
-- distance et flick pèsent moyennement ; vitesse, saut et arme difficile ne font que départager.
local HighlightRules = {}

-- Fenêtre (s) entre deux kills du même tireur pour qu'ils comptent dans un même multi-kill (et un même clip).
HighlightRules.MULTI_WINDOW = 4
-- Clip : secondes gardées avant le premier kill et après le dernier ; durée maximale (multi-kill compris).
HighlightRules.PRE_ROLL = 3
HighlightRules.POST_ROLL = 1
HighlightRules.MAX_DURATION = 8

-- Poids. Efficacité (forts) : multi-kill par kill supplémentaire, tir à la tête, série (par kill, plafonnée).
HighlightRules.W_MULTI = 60
HighlightRules.W_HEADSHOT = 25
HighlightRules.W_STREAK = 5
HighlightRules.STREAK_CAP = 25
-- Moyens : distance (points pour 100 studs, plafonnés) et flick.
HighlightRules.W_DISTANCE = 6
HighlightRules.DISTANCE_CAP = 15
HighlightRules.W_FLICK = 10
-- Départage (faibles) : vitesse du tireur (points à la vitesse SPEED_FULL), en l'air (tireur, victime), arme difficile.
HighlightRules.W_SPEED = 8
HighlightRules.SPEED_FULL = 100
HighlightRules.W_AIR = 4
HighlightRules.W_HARD_WEAPON = 4

export type Kill = {
	killerId: number,
	victimId: number,
	t: number, -- instant du kill (s, horloge serveur)
	headshot: boolean,
	distance: number, -- studs, tireur-victime
	flick: boolean, -- tir après un grand mouvement de la visée (AimStats)
	speed: number, -- vitesse horizontale du tireur (studs/s)
	killerAirborne: boolean,
	victimAirborne: boolean,
	hardWeapon: boolean, -- AWP sans lunette, couteau
	streak: number, -- kills du tireur depuis sa dernière mort, celui-ci compris
	fall: boolean, -- mort par chute provoquée : exclue
}

-- Cette méthode permet de compter les kills du même tireur enchaînés jusqu'à `kill` lorsqu'on note un multi-kill : chaque
-- kill précédent doit tomber dans MULTI_WINDOW du suivant. `recent` contient les kills du tireur avant celui-ci.
function HighlightRules.chain(recent: { Kill }, kill: Kill): { Kill }
	local chain = { kill }
	local next = kill.t
	for i = #recent, 1, -1 do
		local each = recent[i]
		if
			each.killerId == kill.killerId
			and not each.fall
			and each.t <= next
			and next - each.t <= HighlightRules.MULTI_WINDOW
		then
			table.insert(chain, 1, each)
			next = each.t
		end
	end
	return chain
end

-- Cette méthode permet de noter un kill lorsqu'il vient d'être compté ; nil s'il est exclu (chute provoquée). Le multi-kill
-- rapporte W_MULTI par kill de la chaîne au-delà du premier ; les autres critères sont ceux du kill lui-même.
function HighlightRules.score(kill: Kill, recent: { Kill }): number?
	if kill.fall then
		return nil
	end
	local score = (#HighlightRules.chain(recent, kill) - 1) * HighlightRules.W_MULTI
	if kill.headshot then
		score += HighlightRules.W_HEADSHOT
	end
	score += math.min(math.max(kill.streak - 1, 0) * HighlightRules.W_STREAK, HighlightRules.STREAK_CAP)
	score += math.min(kill.distance / 100 * HighlightRules.W_DISTANCE, HighlightRules.DISTANCE_CAP)
	if kill.flick then
		score += HighlightRules.W_FLICK
	end
	score += math.clamp(kill.speed / HighlightRules.SPEED_FULL, 0, 1) * HighlightRules.W_SPEED
	if kill.killerAirborne then
		score += HighlightRules.W_AIR
	end
	if kill.victimAirborne then
		score += HighlightRules.W_AIR
	end
	if kill.hardWeapon then
		score += HighlightRules.W_HARD_WEAPON
	end
	return score
end

-- Cette méthode permet de savoir si un kill devient le clip retenu lorsqu'on le compare au meilleur de la partie : strictement
-- meilleur (à égalité, le plus ancien reste) ; `best` nil = aucun clip encore.
function HighlightRules.beats(score: number?, best: number?): boolean
	if score == nil then
		return false
	end
	return best == nil or score > best
end

-- Cette méthode permet de choisir la fenêtre (début, fin, en s) du clip lorsqu'un kill bat le record : PRE_ROLL avant le
-- premier kill de la chaîne, POST_ROLL après le dernier, durée bornée à MAX_DURATION (le début est alors avancé pour garder
-- la fin du multi-kill).
function HighlightRules.window(chain: { Kill }): (number, number)
	local first, last = chain[1].t, chain[#chain].t
	local stop = last + HighlightRules.POST_ROLL
	local start = math.max(first - HighlightRules.PRE_ROLL, stop - HighlightRules.MAX_DURATION)
	return start, stop
end

return HighlightRules

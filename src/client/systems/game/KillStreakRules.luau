-- Règles pures de l'annonceur de kills : série de kills du joueur local sans mourir, et annonce vocale à jouer.
-- Paliers : 2, 3, 4 (double, triple, quadruple kill), puis 5 (Monster kill), 10 (You're dominating), 15 (Divine), chacun
-- annoncé une seule fois, au kill qui l'atteint. Un kill à la tête hors palier annonce « Headshot » ; sur un palier,
-- seule la série est annoncée (une voix à la fois).
local KillStreakRules = {}

export type Announcement =
	"Headshot"
	| "DoubleKill"
	| "TripleKill"
	| "QuadrupleKill"
	| "MonsterKill"
	| "Dominating"
	| "Divine"

-- Annonce jouée au kill qui fait atteindre ce nombre de kills
KillStreakRules.TIERS = {
	[2] = "DoubleKill",
	[3] = "TripleKill",
	[4] = "QuadrupleKill",
	[5] = "MonsterKill",
	[10] = "Dominating",
	[15] = "Divine",
} :: { [number]: Announcement }

-- Cette méthode permet de compter un kill du joueur local lorsque le serveur l'annonce : renvoie la nouvelle série et
-- l'annonce à jouer (palier atteint, sinon « Headshot » pour un kill à la tête, sinon rien).
function KillStreakRules.onKill(streak: number, headshot: boolean): (number, Announcement?)
	local count = streak + 1
	local tier = KillStreakRules.TIERS[count]
	if tier then
		return count, tier
	end
	return count, if headshot then "Headshot" else nil
end

-- Indicateur du HUD (#364) : crâne et nombre de kills, sans mot, affiché à partir du double kill
KillStreakRules.MIN_SHOWN = 2

export type View = {
	visible: boolean, -- série d'au moins MIN_SHOWN kills
	count: string, -- nombre affiché à côté du crâne
	tier: boolean, -- palier annoncé à la voix : l'icône pulse en rouge d'impact
}

-- Cette méthode permet de composer l'indicateur de série du HUD lorsque la série change : visible dès le double kill,
-- nombre de kills en chiffres, palier marqué quand ce nombre est un palier annoncé (KillStreakRules.TIERS).
function KillStreakRules.view(streak: number): View
	return {
		visible = streak >= KillStreakRules.MIN_SHOWN,
		count = tostring(streak),
		tier = KillStreakRules.TIERS[streak] ~= nil,
	}
end

return KillStreakRules

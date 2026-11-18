-- Déroulé de la démonstration d'un effet de tir (#575, EffectStage) : une boucle de deux plans montés cut, le tir vu
-- par le tireur (1re personne, viewmodel) puis le même tir vu de côté (3e personne, comme le voient les autres
-- joueurs). Un tir par plan, un peu après la coupe : l'œil a le temps de se poser. Règles pures (spec Lune).
local EffectStageRules = {}

export type View = "first" | "third"

-- Durée de chaque plan (s) et instant du tir dans le plan (s après la coupe). Les effets durent au plus 0,6 s
-- (ÉCLAIR) : un plan laisse l'effet s'éteindre avant la coupe suivante.
EffectStageRules.FIRST_LENGTH = 2.2
EffectStageRules.FIRST_SHOT = 0.45
EffectStageRules.THIRD_LENGTH = 2.4
EffectStageRules.THIRD_SHOT = 0.55
EffectStageRules.LOOP = EffectStageRules.FIRST_LENGTH + EffectStageRules.THIRD_LENGTH

-- Cette méthode permet de dire quel plan est à l'écran `t` secondes après le début de la démonstration lorsqu'une image
-- est rendue (la boucle recommence après LOOP).
function EffectStageRules.viewAt(t: number): View
	local inLoop = t % EffectStageRules.LOOP
	return if inLoop < EffectStageRules.FIRST_LENGTH then "first" else "third"
end

-- Cette méthode permet de dire si un tir part entre deux images (instants `before` exclu et `now` inclus, en s depuis
-- le début) lorsque la démonstration avance, et dans quel plan ; nil sans tir. Une image plus longue qu'un plan ne
-- rend que le dernier tir franchi.
function EffectStageRules.shotBetween(before: number, now: number): View?
	if now <= before then
		return nil
	end
	local loop = EffectStageRules.LOOP
	local found: View? = nil
	local foundAt = -math.huge
	for _, shot in
		{
			{ view = "first" :: View, at = EffectStageRules.FIRST_SHOT },
			{ view = "third" :: View, at = EffectStageRules.FIRST_LENGTH + EffectStageRules.THIRD_SHOT },
		}
	do
		-- Dernière occurrence du tir avant ou à `now`, puis : tombe-t-elle après `before` ?
		local last = shot.at + math.floor((now - shot.at) / loop) * loop
		if last > before and last <= now and last > foundAt then
			found = shot.view
			foundAt = last
		end
	end
	return found
end

return EffectStageRules

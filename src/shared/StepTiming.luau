-- StepTiming.luau
-- Tick fixe du mouvement (cf. docs/performance.md, « Rythme du mouvement », #96).
-- La physique avance par ticks de TICK secondes (64 Hz, comme Source), quel que soit le FPS : à entrées égales, la
-- trajectoire est la même pour tous les joueurs. Le temps rendu s'accumule et chaque frame joue les ticks entiers
-- qu'il contient (0, 1 ou plusieurs) ; le reste donne la fraction `alpha` qui sert à interpoler l'affichage entre
-- les deux derniers ticks. Au-delà de MAX_TICKS par frame (gel du client, fenêtre en arrière-plan), le retard est
-- abandonné.

local StepTiming = {}

StepTiming.TICK_RATE = 64 -- Hz
StepTiming.TICK = 1 / StepTiming.TICK_RATE -- secondes simulées par tick
StepTiming.MAX_TICKS = 13 -- ticks par frame au plus (≈ 0,2 s simulées)

-- Cette méthode permet de compter les ticks à jouer lorsqu'une frame de durée dt s'ajoute au temps en attente :
-- renvoie le nombre de ticks, le nouveau temps en attente (< TICK) et la fraction d'interpolation (0..1).
function StepTiming.advance(accumulator: number, dt: number): (number, number, number)
	local pending = accumulator + math.max(dt, 0)
	local ticks = math.floor(pending / StepTiming.TICK + 1e-9)
	pending = math.max(pending - ticks * StepTiming.TICK, 0)
	if ticks > StepTiming.MAX_TICKS then
		ticks = StepTiming.MAX_TICKS
		pending = 0
	end
	return ticks, pending, math.clamp(pending / StepTiming.TICK, 0, 1)
end

return StepTiming

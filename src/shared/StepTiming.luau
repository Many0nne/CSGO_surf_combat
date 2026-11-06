-- StepTiming.luau
-- Découpage du temps d'une frame rendue en pas de mouvement (cf. docs/performance.md, « Rythme du mouvement »).
-- Le mouvement avance sur le dt du rendu, pour que le déplacement affiché corresponde au temps affiché. Une frame
-- lente est découpée en pas de MAX_STEP au plus, au lieu d'être tronquée : le perso parcourt tout le temps écoulé.
-- Au-delà de MAX_STEPS pas (gel du client, fenêtre en arrière-plan), le reste est abandonné.

local StepTiming = {}

StepTiming.MAX_STEP = 1 / 30 -- secondes : plus grand pas simulé d'un coup (stabilité des collisions)
StepTiming.MAX_STEPS = 6 -- pas par frame au plus (0,2 s simulées)

-- Cette méthode permet de découper le dt d'une frame en pas égaux lorsque le mouvement avance d'une frame rendue :
-- renvoie le nombre de pas et la durée de chacun (0 pas si dt est nul ou négatif).
function StepTiming.split(dt: number): (number, number)
	if dt <= 0 then
		return 0, 0
	end
	local count = math.ceil(dt / StepTiming.MAX_STEP - 1e-9)
	if count > StepTiming.MAX_STEPS then
		return StepTiming.MAX_STEPS, StepTiming.MAX_STEP
	end
	return count, dt / count
end

return StepTiming

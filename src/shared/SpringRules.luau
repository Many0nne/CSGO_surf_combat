-- Ressort amorti du balancement du viewmodel (#304) : Euler semi-implicite en sous-pas, stable quel que soit dt.
local SpringRules = {}

-- Pas maximal d'intégration : à 60 i/s un frame = un pas (rendu inchangé), en dessous on découpe le frame.
SpringRules.MAX_STEP = 1 / 60
-- dt maximal pris en compte par frame (une saccade d'une seconde ne doit pas coûter 60 pas ni lancer l'arme).
SpringRules.MAX_DT = 0.25

-- Cette méthode permet d'avancer le ressort d'un frame lorsque dt dépasse MAX_STEP, en le découpant en pas égaux
-- ≤ MAX_STEP (stable tant que speed * MAX_STEP < 2√2 − 2 ≈ 0,83) ; un dt ≤ MAX_STEP donne exactement un seul pas.
function SpringRules.step(
	pos: Vector3,
	vel: Vector3,
	target: Vector3,
	speed: number,
	damping: number,
	dt: number
): (Vector3, Vector3)
	dt = math.min(dt, SpringRules.MAX_DT)
	if dt <= 0 then
		return pos, vel
	end
	local steps = math.ceil(dt / SpringRules.MAX_STEP - 1e-9)
	local h = dt / steps
	local stiffness = speed * speed
	local damp = 2 * damping * speed
	for _ = 1, steps do
		local accel = (target - pos) * stiffness - vel * damp
		vel = vel + accel * h
		pos = pos + vel * h
	end
	return pos, vel
end

return SpringRules

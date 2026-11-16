-- Règles pures des sticks analogiques (#276), testées (tests/specs/GamepadRules.spec.luau) : stick gauche (ou joystick
-- tactile) → axes de déplacement, stick droit → vitesse de rotation de la caméra. Aucune Instance.
local GamepadRules = {}

-- Zone morte radiale (fraction de la course) : en dessous, le stick est considéré au repos
GamepadRules.MOVE_DEADZONE = 0.25
GamepadRules.LOOK_DEADZONE = 0.15
-- Le déplacement s'aimante sur l'axe le plus proche (avant, côté, arrière) en deçà de cet angle (degrés) : tenir le côté
-- pur pour l'air strafe sans dériver vers l'avant
GamepadRules.MOVE_SNAP_DEG = 20
-- Courbe de visée : rotation ∝ inclinaison^exposant (petits gestes précis, plein stick rapide)
GamepadRules.LOOK_EXPONENT = 2

-- Cette méthode permet de convertir la position d'un stick (x à droite, y en avant, de -1 à 1) en axes de déplacement
-- lorsque le stick gauche ou le joystick tactile bouge : (avant, droite) dans {-1, 0, 1}² ou direction normalisée.
-- Hors zone morte seulement ; près d'un axe, la direction s'y aimante (le mouvement ne dépend que de la direction).
function GamepadRules.moveAxes(x: number, y: number): (number, number)
	local mag = math.sqrt(x * x + y * y)
	if mag < GamepadRules.MOVE_DEADZONE then
		return 0, 0
	end
	local angle = math.deg(math.atan2(x, y)) -- 0 = avant, 90 = droite
	local nearest = math.round(angle / 90) * 90
	if math.abs(angle - nearest) <= GamepadRules.MOVE_SNAP_DEG then
		local r = math.rad(nearest)
		return math.round(math.cos(r)), math.round(math.sin(r))
	end
	return y / mag, x / mag
end

-- Cette méthode permet de convertir la position du stick droit en vitesse de rotation relative (x à droite, y vers le
-- haut, chacun de -1 à 1) lorsque la caméra tourne au stick : zone morte radiale, puis courbe sur l'inclinaison restante.
function GamepadRules.lookRate(x: number, y: number): (number, number)
	local mag = math.sqrt(x * x + y * y)
	if mag < GamepadRules.LOOK_DEADZONE then
		return 0, 0
	end
	local t = math.min((mag - GamepadRules.LOOK_DEADZONE) / (1 - GamepadRules.LOOK_DEADZONE), 1)
	local scale = (t ^ GamepadRules.LOOK_EXPONENT) / mag
	return x * scale, y * scale
end

return GamepadRules

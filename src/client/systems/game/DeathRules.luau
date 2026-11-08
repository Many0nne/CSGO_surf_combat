-- Règles pures de la mort (#102), sans Instance ni service : poussée du ragdoll, durée de vie des corps, rotation de la
-- caméra du tué vers son tueur. Testées sous Lune (tests/specs/DeathRules.spec.luau).
local DeathRules = {}

-- Corps : visible RAGDOLL_LIFETIME s, puis estompé en RAGDOLL_FADE s ; au-delà de MAX_RAGDOLLS, le plus ancien disparaît
DeathRules.RAGDOLL_LIFETIME = 3
DeathRules.RAGDOLL_FADE = 0.5
DeathRules.MAX_RAGDOLLS = 6

-- Poussée donnée au corps dans le sens du tir (studs/s), par arme ; tir à la tête multiplié par HEADSHOT_PUSH
DeathRules.PUSH_BY_WEAPON = {
	AWP = 45,
	M9Bayonet = 14,
}
DeathRules.DEFAULT_PUSH = 20
DeathRules.HEADSHOT_PUSH = 1.4
-- Composante verticale ajoutée à la poussée : le corps décolle un peu au lieu de glisser au sol
DeathRules.PUSH_LIFT = 0.25

-- Caméra du tué : vitesse de rotation vers le tueur (1/s), hauteur des yeux au-dessus de la racine (studs)
DeathRules.CAMERA_TURN_RATE = 4
DeathRules.EYE_HEIGHT = 1.5

-- Caméra du tué reculée au-dessus de son corps, sinon il s'effondre sous l'objectif et masque l'écran de mort (studs)
DeathRules.CAMERA_BACK = 5
DeathRules.CAMERA_UP = 2.5

-- Cette méthode permet de calculer le recul de la caméra du tué depuis ses yeux lorsqu'il meurt : vers l'arrière de
-- son regard à l'horizontale (vers +Z s'il regardait à la verticale), et vers le haut.
function DeathRules.cameraOffset(look: Vector3): Vector3
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	return -forward * DeathRules.CAMERA_BACK + Vector3.new(0, DeathRules.CAMERA_UP, 0)
end

-- Conversion d'affichage : 1 stud ≈ 0,28 m (convention Roblox)
DeathRules.METERS_PER_STUD = 0.28

-- Cette méthode permet de calculer la vitesse à donner au corps lorsqu'il devient un ragdoll : vitesse du joueur au
-- moment de sa mort, plus une poussée dans le sens du tir qui dépend de l'arme et du tir à la tête.
function DeathRules.ragdollVelocity(velocity: Vector3, direction: Vector3?, weapon: string?, headshot: boolean): Vector3
	if not direction or direction.Magnitude < 1e-3 then
		return velocity
	end
	local push = (weapon and DeathRules.PUSH_BY_WEAPON[weapon]) or DeathRules.DEFAULT_PUSH
	if headshot then
		push *= DeathRules.HEADSHOT_PUSH
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local horizontal = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
	return velocity + (horizontal + Vector3.new(0, DeathRules.PUSH_LIFT, 0)) * push
end

-- Cette méthode permet de calculer la part du chemin à faire vers l'orientation visée lorsque la caméra du tué avance
-- d'une frame (dt) : lissage exponentiel indépendant du nombre d'images par seconde.
function DeathRules.turnAlpha(dt: number, rate: number?): number
	return 1 - math.exp(-(rate or DeathRules.CAMERA_TURN_RATE) * math.max(dt, 0))
end

-- Cette méthode permet de formater la distance au tueur (« 24 m ») lorsque son repère est affiché.
function DeathRules.formatDistance(studs: number): string
	return string.format("%d m", math.floor(studs * DeathRules.METERS_PER_STUD + 0.5))
end

-- Cette méthode permet de calculer l'opacité d'un corps (0 visible, 1 effacé) lorsqu'il vieillit de `age` secondes.
function DeathRules.ragdollFade(age: number): number
	if age <= DeathRules.RAGDOLL_LIFETIME then
		return 0
	end
	return math.clamp((age - DeathRules.RAGDOLL_LIFETIME) / DeathRules.RAGDOLL_FADE, 0, 1)
end

return DeathRules

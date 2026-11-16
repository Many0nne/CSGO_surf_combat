-- Bruits de pas (#146) : règles pures, testées sous Lune (tests/specs/FootstepRules.spec.luau). Comme CS : un pas
-- toutes les STRIDE studs parcourues au sol à au moins MIN_SPEED (la course, pas la marche ni l'accroupi), et un bruit
-- à l'atterrissage après au moins LAND_MIN_AIR en l'air (saut, chute, sortie de rampe). Rien en l'air ni en surf (une
-- rampe trop raide n'est pas un sol, MovementConfig.SURF_NORMAL_Y).
-- Le serveur applique ces règles aux positions acceptées de chaque joueur et bot (FootstepService) et relaie chaque
-- pas aux autres clients et à l'ouïe des bots ; le client les applique à son propre mouvement (FootstepSounds).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local FootstepRules = {}

-- Son d'un pas (Creator Store « Concrete Footstep », un seul pas), le même sur tous les sols.
FootstepRules.SOUND_ID = "rbxassetid://87061775498714"
-- Vitesse horizontale minimale d'un pas audible (studs/s) : 0,6 × la course. La marche (0,5) et l'accroupi (0,28) sont
-- silencieux ; la course avec l'AWP en main (0,75) s'entend.
FootstepRules.MIN_SPEED = 0.6 * MovementConfig.RUN_SPEED
-- Distance parcourue entre deux pas (studs) : 3 pas par seconde à la course.
FootstepRules.STRIDE = MovementConfig.RUN_SPEED / 3
-- Distance avant le premier pas quand on se met à courir (studs) : plus courte qu'une foulée, le premier pas suit
-- presque aussitôt le départ.
FootstepRules.FIRST_STEP = 3
-- Temps en l'air minimal (s) avant qu'un retour au sol fasse un bruit d'atterrissage (pas pour une marche franchie).
FootstepRules.LAND_MIN_AIR = 0.2
-- Portée (studs) : les pas d'un autre s'entendent jusqu'à RANGE (≈ 1100 unités Source × 0,12), à plein volume jusqu'à
-- ROLLOFF_MIN, puis en 1/distance ramenée à zéro à RANGE (Enum.RollOffMode.InverseTapered). Même portée pour les bots.
FootstepRules.RANGE = 140
FootstepRules.ROLLOFF_MIN = 10
-- Volumes : ses propres pas, plus bas que ceux d'un autre tout proche pour ne pas les masquer.
FootstepRules.VOLUME = 1
FootstepRules.OWN_VOLUME = 0.35
-- Variation de hauteur d'un pas à l'autre (± tant), pour qu'un seul son ne sonne pas en boucle ; atterrissage plus grave
-- et plus fort.
FootstepRules.PITCH_SPREAD = 0.08
FootstepRules.LAND_PITCH = 0.85
FootstepRules.LAND_GAIN = 1.4
-- Pas d'autres joués en même temps au plus : au-delà, un pas de plus n'est pas joué (beaucoup de bots).
FootstepRules.MAX_ACTIVE = 24
-- Durée de vie d'un son de pas (s) : filet si Ended ne vient pas.
FootstepRules.LIFETIME = 2
-- États du client (GameStateController) où l'on entend les pas des autres : pas dans les écrans du menu.
FootstepRules.AUDIBLE_STATES = {
	SPAWNING = true,
	IN_ROUND = true,
	DEAD = true,
	RESULT = true,
} :: { [string]: boolean }

export type Kind = "step" | "land"
export type State = { airTime: number, stride: number, running: boolean }

-- Cette méthode permet de créer l'état des pas d'un personnage lorsqu'il apparaît (au sol, sans pas entamé).
function FootstepRules.new(): State
	return { airTime = 0, stride = 0, running = false }
end

-- Cette méthode permet de dire si un personnage fait un bruit lorsqu'il vient d'avancer de distance studs à
-- l'horizontale en dt secondes, au sol ou non ; renvoie "land", "step" ou nil.
function FootstepRules.update(state: State, dt: number, grounded: boolean, distance: number): Kind?
	if not grounded then
		state.airTime += dt
		return nil
	end
	local airTime = state.airTime
	state.airTime = 0
	if airTime >= FootstepRules.LAND_MIN_AIR then
		-- Premier pas après l'atterrissage une foulée entière plus loin
		state.stride = 0
		return "land"
	end
	if dt <= 0 or distance / dt < FootstepRules.MIN_SPEED then
		state.running = false
		return nil
	end
	if not state.running then
		-- Départ de course : premier pas après FIRST_STEP seulement
		state.running = true
		state.stride = math.max(state.stride, FootstepRules.STRIDE - FootstepRules.FIRST_STEP)
	end
	-- Un bond (téléportation, correction) ne compte que pour une foulée
	state.stride += math.min(distance, FootstepRules.STRIDE)
	if state.stride >= FootstepRules.STRIDE then
		state.stride -= FootstepRules.STRIDE
		return "step"
	end
	return nil
end

-- Cette méthode permet de fixer la hauteur et le gain d'un pas lorsqu'il va être joué (r : tirage uniforme dans [0, 1]).
function FootstepRules.voice(kind: Kind, r: number): (number, number)
	local pitch = 1 + (2 * r - 1) * FootstepRules.PITCH_SPREAD
	if kind == "land" then
		return pitch * FootstepRules.LAND_PITCH, FootstepRules.LAND_GAIN
	end
	return pitch, 1
end

-- Cette méthode permet de décider si un pas relayé est joué lorsqu'il arrive : le pas d'un autre, dans un état où l'on
-- entend, et s'il reste de la place parmi les sons en cours.
function FootstepRules.shouldPlay(source: any, localCharacter: any, state: string?, activeCount: number): boolean
	if source == nil or source == localCharacter or state == nil then
		return false
	end
	return FootstepRules.AUDIBLE_STATES[state] == true and activeCount < FootstepRules.MAX_ACTIVE
end

return FootstepRules

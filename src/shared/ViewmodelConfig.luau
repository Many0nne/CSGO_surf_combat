-- ViewmodelConfig.luau
-- Réglages du viewmodel FPS : fondus entre animations, sway, bob, inclinaison en strafe, impact d'atterrissage.
-- Angles en degrés, distances en studs (repère caméra : X droite, Y haut, -Z avant).
-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	-- Fondus (s) : entrée d'une action, retour à l'idle en fin d'action
	BLEND_IN              = 0.08,
	BLEND_OUT             = 0.25,

	-- Sway : retard du viewmodel quand la caméra tourne (ressort amorti)
	SWAY_ROT_PER_DEG      = 0.55,  -- degrés de rotation par degré de rotation caméra dans la frame
	SWAY_POS_PER_DEG      = 0.012, -- studs de décalage par degré de rotation caméra
	SWAY_MAX_ROT          = 7,
	SWAY_MAX_POS          = 0.25,
	SWAY_ROLL_PER_YAW     = 0.6,   -- roulis ajouté proportionnel au lacet
	SWAY_SPRING_SPEED     = 16,
	SWAY_SPRING_DAMPING   = 0.75,

	-- Bob de marche/course (figure en 8), proportionnel à la vitesse au sol
	BOB_REF_SPEED         = 30,    -- vitesse (studs/s) à laquelle l'amplitude vaut 1 (RUN_SPEED)
	BOB_FREQ              = 1.6,   -- cycles par seconde à BOB_REF_SPEED
	BOB_FREQ_MIN_SCALE    = 0.6,   -- fréquence minimale relative à basse vitesse
	BOB_AMP_X             = 0.06,
	BOB_AMP_Y             = 0.045,
	BOB_ROLL              = 1.2,
	BOB_FADE_SPEED        = 8,     -- vitesse de transition marche ↔ arrêt/air

	-- Inclinaison en strafe (roulis selon la vitesse latérale)
	STRAFE_TILT_MAX       = 4,
	STRAFE_TILT_SPEED     = 8,

	-- Impact d'atterrissage (ressort sur Y et tangage)
	LAND_MIN_SPEED        = 20,    -- vitesse de chute minimale pour déclencher l'impact
	LAND_KICK_PER_SPEED   = 0.004, -- studs de descente par stud/s de chute
	LAND_KICK_MAX         = 0.35,
	LAND_SPRING_SPEED     = 14,
	LAND_SPRING_DAMPING   = 0.6,
}

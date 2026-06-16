return {
	-- Vitesses (studs/s)
	RUN_SPEED    = 16,
	WALK_SPEED   = 8,
	CROUCH_SPEED = 4.5,

	-- Accélération
	GROUND_ACCEL           = 128,
	AIR_ACCEL              = 150,
	AIR_SPEED_CAP          = 10,   -- équivalent GetAirSpeedCap() Source (hardcodé à 30 dans le SDK)
	FRICTION               = 8.0,
	STOP_SPEED             = 2,

	-- Saut / Gravité
	JUMP_VELOCITY    = 38,
	GRAVITY          = -110,     -- arc ~4.8 studs (38²/300), trajectoire plus nerveuse
	MAX_FALL_SPEED   = 130,

	-- Pentes
	SLOPE_ANGLE_MAX = 45,
	STEPUP_HEIGHT   = 1.2,
	SLOPE_FRICTION  = 0.1,   -- μ : friction proportionnelle à la force normale sur la pente
	SURF_FRICTION   = 1,   -- surfaceFriction Source sur les rampes surf (réduit l'air accel latéral)
	SURF_NORMAL_Y   = 0.7,   -- seuil unique marchable/surf (≈ cos 45.6°, comme sv_walkable_normal)
	SURF_NORMAL_MIN = 0.1,   -- borne basse surf : sous ce seuil (face quasi verticale ≥84°) = MUR, pas surf

	-- Bunny hop
	BHOP_LAND_WINDOW = 0.1,
	AUTO_BHOP        = true,

	-- Coyote time & jump buffer
	COYOTE_TIME      = 0.09,
	JUMP_BUFFER_TIME = 0.13,

	-- Strafe (tolérance angle supplémentaire vs CS:GO pur)
	-- STRAFE_ASSIST_DEG = 45,

	-- Réseau
	NET_SYNC_RATE   = 20,
	MAX_SPEED_SERVER = 300,
	MAX_DELTA_POS   = 5,

	-- Hitbox
	HITBOX_USE_RIG_BOUNDS = true,
	HITBOX_DEBUG          = true,

	-- Debug mouvement : logs verbeux par frame airborne (bhop haute vitesse, jointure rampe/élément)
	MOVE_DEBUG            = false,

	HITBOX_HEAD_BUFFER    = 0.3,
	CHAR_RADIUS        = 1.0,
	CHAR_HEIGHT_STAND  = 4.8,
	CHAR_HEIGHT_CROUCH = 2.4,
}

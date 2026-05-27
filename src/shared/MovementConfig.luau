return {
	-- Vitesses (studs/s)
	RUN_SPEED    = 16,
	WALK_SPEED   = 8,
	CROUCH_SPEED = 4.5,

	-- Accélération
	GROUND_ACCEL           = 128,
	AIR_ACCEL              = 300,
	AIR_SPEED_CAP          = 40,   -- équivalent GetAirSpeedCap() Source (élargit la fenêtre strafe)
	FRICTION               = 8.0,
	STOP_SPEED             = 2,

	-- Saut / Gravité
	JUMP_VELOCITY    = 38,
	GRAVITY          = -115,     -- arc ~4.8 studs (38²/300), trajectoire plus nerveuse
	MAX_FALL_SPEED   = 95,

	-- Pentes
	SLOPE_ANGLE_MAX = 45,
	STEPUP_HEIGHT   = 1.2,
	SLOPE_FRICTION  = 0.1,   -- μ : friction proportionnelle à la force normale sur la pente

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

	-- Caméra
	DEFAULT_FOV       = 90,
	DEFAULT_SENS      = 0.3,
	PITCH_MIN         = -89,
	PITCH_MAX         = 89,
	CAM_HEIGHT_STAND  = 2.5,
	CAM_HEIGHT_CROUCH = 1.2,
	CAM_LERP_SPEED    = 12,

	-- Hitbox
	CHAR_RADIUS        = 1.0,
	CHAR_HEIGHT_STAND  = 4.8,
	CHAR_HEIGHT_CROUCH = 2.4,
}

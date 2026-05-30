return {
	-- Vitesses (studs/s)
	RUN_SPEED    = 16,
	WALK_SPEED   = 8,
	CROUCH_SPEED = 4.5,

	-- Accélération
	GROUND_ACCEL           = 128,
	AIR_ACCEL              = 40,
	AIR_SPEED_CAP          = 40,   -- équivalent GetAirSpeedCap() Source (élargit la fenêtre strafe)
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

	-- AWP
	AWP_SCOPE_FOV1     = 40,   -- premier zoom
	AWP_SCOPE_FOV2     = 10,   -- deuxième zoom
	AWP_FOV_TWEEN_TIME = 0.1,
	AWP_DMG           = 115,
	AWP_FIRE_INTERVAL = 60 / 41,  -- ~1.463s entre les tirs (41 RPM)
	AWP_RELOAD_TIME   = 3.7,
	AWP_MAG_SIZE      = 5,
	AWP_RESERVE_SIZE  = 10,
	AWP_SPEED_MULT        = 0.85,
	AWP_SCOPE_SENS_MULT   = 0.7,   -- multiplicateur de sensibilité en mode scope
	-- TODO: AWP_PENETRATION = 250

	-- Hitbox
	HITBOX_USE_RIG_BOUNDS = true,
	HITBOX_DEBUG          = true,
	HITBOX_HEAD_BUFFER    = 0.3,
	CHAR_RADIUS        = 1.0,
	CHAR_HEIGHT_STAND  = 4.8,
	CHAR_HEIGHT_CROUCH = 2.4,
}

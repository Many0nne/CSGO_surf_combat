-- Plafonds de vitesse (studs/s), en locales pour en dériver la limite du serveur plus bas (#212).
-- Horizontal : sv_maxvelocity Source (3500 unités/s) × 0,12, le ratio unités Source → studs de RUN_SPEED.
local MAX_HORIZONTAL_SPEED = 420
local MAX_FALL_SPEED = 130
-- Serveur : cas honnête le plus rapide en 3D (plafond horizontal et chute plafonnée, √(420² + 130²) ≈ 440), plus 10
-- de marge, soit 450.
local MAX_SPEED_SERVER = math.ceil(math.sqrt(MAX_HORIZONTAL_SPEED ^ 2 + MAX_FALL_SPEED ^ 2)) + 10

-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	-- Vitesses (studs/s)
	RUN_SPEED    = 30,     -- ratio Source: AIR_SPEED_CAP / RUN_SPEED ≈ 30/250 ≈ 0.12
	WALK_SPEED   = 15,     -- 0.5 × RUN_SPEED
	CROUCH_SPEED = 8.4,    -- ≈ 0.28 × RUN_SPEED

	-- Plafond de la vitesse horizontale, au sol, en l'air et en surf (CharacterMotor.move) : 420, cf. plus haut
	MAX_HORIZONTAL_SPEED = MAX_HORIZONTAL_SPEED,

	-- Accélération
	GROUND_ACCEL           = 12,   -- sv_accelerate Source (× wishspeed) ; doit rester > FRICTION pour atteindre RUN_SPEED
	AIR_ACCEL              = 150,
	AIR_SPEED_CAP          = 6,    -- 6/30 = 0.2 (Source 30/250 ≈ 0.12, relevé pour un gain plus rapide) ; équivalent GetAirSpeedCap() Source (hardcodé à 30 dans le SDK)
	FRICTION               = 8.0,
	STOP_SPEED             = 2,

	-- Saut / Gravité
	JUMP_VELOCITY    = 38,
	GRAVITY          = -110,            -- arc ~6.6 studs (38²/220), trajectoire plus nerveuse
	MAX_FALL_SPEED   = MAX_FALL_SPEED,  -- 130 hors surf, cf. plus haut

	-- Pentes
	SLOPE_ANGLE_MAX = 45,
	STEPUP_HEIGHT   = 1.2,
	SLOPE_FRICTION  = 0.1,   -- μ : friction proportionnelle à la force normale sur la pente
	SURF_FRICTION   = 1,   -- surfaceFriction Source sur les rampes surf (réduit l'air accel latéral)
	SURF_NORMAL_Y   = 0.7,   -- seuil unique marchable/surf (≈ cos 45.6°, comme sv_walkable_normal)
	SURF_NORMAL_MIN = 0.1,   -- borne basse surf : sous ce seuil (face quasi verticale ≥84°) = MUR, pas surf

	-- Échelles (volumes Maps.Map.Ladders, LadderRules) : grimpe façon Source
	LADDER_CLIMB_SPEED = 20,    -- MAX_CLIMB_SPEED Source (200/250 × RUN_SPEED ≈ 24), un peu plus lent
	LADDER_JUMP_OFF    = 30,    -- saut depuis l'échelle : poussée le long de sa normale (Source 270 u/s)
	LADDER_REGRAB      = 0.3,   -- s avant de pouvoir reprendre l'échelle après en avoir sauté

	-- Bunny hop
	BHOP_LAND_WINDOW = 0.1,
	AUTO_BHOP        = true, -- valeur par défaut du réglage joueur PlayerSettings.autoBhop (#255)

	-- Coyote time & jump buffer
	COYOTE_TIME      = 0.09,
	JUMP_BUFFER_TIME = 0.13,

	-- Strafe (tolérance angle supplémentaire vs CS:GO pur)
	-- STRAFE_ASSIST_DEG = 45,

	-- Réseau
	NET_SYNC_RATE    = 20,
	MAX_SPEED_SERVER = MAX_SPEED_SERVER,         -- 450 studs/s soutenus au plus, remplit le seau de distance du serveur (#172)
	MAX_DELTA_POS    = MAX_SPEED_SERVER * 0.25,  -- 112,5 : plafond du seau (studs), 0,25 s à MAX_SPEED_SERVER, pour la gigue
	MAX_SILENCE      = 0.5,                      -- s de silence au plus comptées pour un paquet : au-delà, pas plus de budget

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

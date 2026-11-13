-- Réglages des bots (#133). Plan de navigation (#140 : graphe de la map, notes des points, suivi de chemin), bunny
-- hop (#151), comportement (#141 : perception, mémoire, états, note dynamique des destinations, biais vers les humains).
-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	-- Noms tirés d'une liste fixe (décision 5 de #133), affichés « BOT <nom> » dans le kill feed et le classement
	NAMES = { "Marcel", "Lucie", "Gaston", "Odette", "Raymond", "Simone", "Lucien", "Paulette" },
	MAX_BOTS            = 5,      -- plafond de bots en jeu (décision 2 de #133)
	TARGET_POPULATION   = 6,      -- joueurs + bots : les bots comblent les places vides (décision 1 de #133)
	POPULATION_DUEL_TIME = 4,     -- un bot qui a vu une cible depuis moins de tant (s) est en duel : jamais retiré
	POPULATION_INTERVAL = 1,      -- population réajustée tous les tant (s) (retrait différé tant que tous sont en duel)
	DEBUG_FREEZE_ATTRIBUTE = "DebugBotsFreeze", -- vrai : bots figés (ni mouvement ni tir)
	DEBUG_PASSIVE_ATTRIBUTE = "DebugBotsPassive", -- vrai : bots passifs (ils se déplacent mais ne tirent pas sur les humains)

	-- Gêne : au sol, sous cette part de la vitesse voulue, le bot n'avance pas comme il le veut
	STUCK_SPEED_RATIO   = 0.3,

	-- Plan de navigation (#140) : sondage de la map au démarrage du serveur (NavBuilder)
	NAV_GRID            = 4,      -- pas de la grille de sondage (studs)
	NAV_BODY_RADIUS     = 1.2,    -- demi-largeur du corps sondé (CHAR_RADIUS + marge)
	NAV_BODY_BOTTOM     = 1.3,    -- bas du corps sondé au-dessus du sol (marche franchissable)
	NAV_BODY_TOP        = 4.9,    -- haut du corps sondé au-dessus du sol (CHAR_HEIGHT_STAND + marge)
	NAV_WALK_SLOPE      = 46,     -- pente la plus raide franchie à pied entre deux cases voisines (°)
	NAV_MAX_DROP        = 60,     -- plus grande descente d'un rebord (studs)
	NAV_JUMP_UP_MAX     = 5,      -- plus haute marche montée en sautant (sommet du saut : 6,6 studs)
	NAV_WAYPOINT_SIZE   = 24,     -- côté de la zone regroupée en un point de passage (studs)
	NAV_WAYPOINT_MIN    = 4,      -- sous ce nombre de cases, une zone rejoint sa voisine
	NAV_EYE_HEIGHT      = 4.5,    -- hauteur des yeux pour la note de vue (studs au-dessus du sol)
	NAV_VIEW_RANGE      = 320,    -- distance au-delà de laquelle un point n'en voit pas un autre (studs)
	NAV_COVER_DIST      = 12,     -- un mur à moins de tant (8 directions) compte comme couvert
	NAV_NARROW_WIDTH    = 16,     -- deux murs opposés à moins de tant : couloir
	NAV_PIT_DEPTH       = 12,     -- point plus bas que ses voisins (40 studs) d'au moins tant : fosse
	NAV_RAMP_DIST       = 14,     -- rampe de surf à moins de tant : entrée de rampe
	NAV_BUILD_BUDGET    = 0.008,  -- temps de calcul par frame pendant la construction (s)

	-- Note fixe d'un point (décision 3 de #133) : vue (critère principal), hauteur, couvert, type
	NAV_SCORE_VIEW      = 1.0,
	NAV_SCORE_HEIGHT    = 0.3,
	NAV_SCORE_COVER     = 0.3,
	NAV_SCORE_KIND      = { piece = 0, couloir = 0.1, escalier = 0.1, fosse = -0.1, rampe = 0.2, echelle = 0 },

	-- Coût des arêtes pour la recherche de chemin (multiplie la longueur, plus un forfait en studs)
	NAV_COST_FACTOR     = { 1, 1.1, 1.4, 1.6, 1 }, -- marche, descente, saut, échelle, rampe (repli : coût de rampe
	NAV_COST_EXTRA      = { 0, 2, 6, 10, 20 },    -- calculé d'après la durée du trajet, NavRules.rampCost)
	NAV_PATH_WEIGHT     = 2,      -- poids de l'heuristique de l'A* (#145) : 1 = chemin optimal, plus = moins de cases vues
	NAV_SEARCH_BUDGET   = 400,    -- cases explorées par tick et par bot pendant une recherche de chemin (#145)
	NAV_BORDER_COST     = 3,    -- surcoût d'une case au bord d'un passage (moitié à un pas du bord, studs)

	-- Suivi de chemin (BotNavigator)
	NAV_REACH_RADIUS    = 1.6,    -- case atteinte à moins de tant à l'horizontale (studs)
	NAV_REACH_DY        = 3,      -- et à moins de tant en hauteur
	NAV_LOOKAHEAD       = 10,     -- cases sautées au plus quand le trajet est en ligne droite
	NAV_SHORTCUT_TOL    = 1.2,    -- écart toléré d'une case sautée à la ligne droite (studs)
	NAV_JUMP_LEAD_TIME  = 0.19,   -- saut déclenché tant de secondes avant le rebord (pieds à 5 studs)
	NAV_STUCK_TIME      = 1.5,    -- sans se rapprocher de sa cible aussi longtemps : nouveau chemin
	NAV_MAX_REPATH      = 3,      -- nouveaux chemins sans atteindre la cible : arête écartée, autre destination
	NAV_BAN_TIME        = 20,     -- durée de mise à l'écart d'une arête ratée (s)
	NAV_NEAREST_RADIUS  = 12,     -- recherche de la case la plus proche (studs)
	NAV_HOLD_MIN        = 0.5,    -- attente sur une destination atteinte (s), avant la suivante
	NAV_HOLD_MAX        = 3,
	NAV_TURN_RATE       = 540,    -- rotation du regard (°/s)

	-- Bunny hop et air strafe (#151) : sur une portion de marche du chemin, sauts enchaînés sans friction et strafe
	-- en l'air vers un point du chemin devant lui (poursuite) ; vitesse réglée en l'air (gain, plané, freinage) selon
	-- les virages devant et la marche restante ; atterrissage normal avant un saut, une échelle ou la destination
	BHOP_ENABLED        = true,
	BHOP_CHANCE         = 0.6,    -- probabilité de bhopper sur une portion de marche (tirée une fois par portion)
	BHOP_MIN_RUN        = 48,     -- marche restante minimale pour commencer (studs, le long du chemin)
	BHOP_MAX_SPEED      = 100,    -- vitesse plafond (studs/s)
	BHOP_LAND_MARGIN    = 10,     -- marche restante exigée en plus d'un saut pour ressauter (studs)
	BHOP_LOOK_TIME      = 0.15,   -- point visé à vitesse × tant devant lui sur le chemin (s)
	BHOP_LOOK_MIN       = 6,      -- et au moins à tant (studs)
	BHOP_BRAKE_TIME     = 0.5,    -- virages pris en compte à vitesse × tant devant lui (s)
	BHOP_CURVE_CELLS    = 3,      -- rayon d'un virage mesuré entre les cases à tant de part et d'autre
	BHOP_WIDTH_USE      = 0.5,    -- part de la largeur de passage ajoutée au rayon (il coupe le virage)
	BHOP_TURN_SAFETY    = 0.6,    -- part de la vitesse qui tient le virage, gardée par prudence
	BHOP_NARROW_SPEED   = 50,     -- vitesse au plus le long d'un mur ou d'un vide (case de bord, studs/s)
	BHOP_CLEARANCE_MAX  = 8,      -- largeur de passage mesurée au plus (pas de grille)
	BHOP_ADVANCE_WINDOW = 12,     -- segments du chemin examinés devant lui pour suivre son avancée en l'air
	BHOP_SPEED_TOL      = 2,      -- au-delà de la vitesse visée de tant, il freine (studs/s)
	BHOP_ALIGN_TOL      = 8,      -- à la vitesse visée, écart de cap toléré sans corriger (°)
	BHOP_ZIGZAG_ANGLE   = 6,      -- écart du cap visé au chemin, alterné d'un saut à l'autre (°)
	BHOP_ZIGZAG_FLIP    = 0.8,    -- probabilité de changer de côté à un saut
	BHOP_STRAFE_NOISE   = 0.5,    -- écart à l'angle optimal, en part de la fenêtre qui fait gagner (±asin(L/|v|)),
	                              -- tiré à chaque saut (0 = parfait, 0,5 garde au moins 75 % du gain, 1 = aucun gain)
	BHOP_MISS_CHANCE    = 0.1,    -- probabilité de rater le timing d'un saut
	BHOP_MISS_DELAY     = 0.12,   -- retard d'un saut raté, passé au sol avec friction (s)

	-- Rampes de surf (#142) : une arête du plan par rampe et par sens, de la case d'entrée à la case de sortie, trajet
	-- simulé une fois au démarrage (RampSim, même physique que le joueur) et rejoué par les bots (RampRules)
	RAMP_ENABLED        = true,   -- faux : aucune arête de rampe (les bots ne surfent jamais)
	RAMPS_FOLDER        = "Ramps", -- dossiers de la map où chercher les rampes (à toute profondeur)
	RAMP_MIN_AREA       = 1000,   -- face de surf plus petite : pas une rampe (studs²)
	RAMP_ENTRY_DIST     = 16,     -- cases d'entrée cherchées jusqu'à tant au-delà du bout de départ (studs)
	RAMP_ENTRY_INSET    = 12,     -- point visé sur la rampe à tant du bout de départ (studs)
	RAMP_ENTRY_RISE     = 2,      -- et à tant au-dessus du sol de la case d'entrée (studs, sommet du saut : 6,6)
	RAMP_EDGE_MARGIN    = 4,      -- point visé à au moins tant du haut et du bas de la face (studs)
	RAMP_APPROACH_OUT   = 4,      -- point de passage à tant au-delà du bout de départ (studs)
	RAMP_APPROACH_LIFT  = 6,      -- et à tant devant la face (studs, le long de la normale)
	RAMP_JUMP_DIST      = 8,      -- saut quand le point de passage est à moins de tant (studs, à l'horizontale)
	RAMP_TRIES          = 6,      -- cases d'entrée essayées par rampe et par sens
	RAMP_TRY_SPACING    = 6,      -- écart minimal entre deux cases d'entrée essayées (studs)
	RAMP_AIR_STEER      = 120,    -- changement de vitesse horizontale en l'air hors surf (studs/s²)
	RAMP_MAX_TIME       = 9,      -- trajet simulé au plus (s)
	RAMP_MIN_TRAVEL     = 0.6,    -- part de la longueur de la rampe parcourue au moins
	RAMP_EXIT_RADIUS    = 40,     -- case d'arrivée cherchée à moins de tant de la sortie de la rampe (studs)
	RAMP_EDGE_PENALTY   = 8,      -- case d'arrivée au bord d'un vide comptée tant plus loin du point de chute (studs)
	RAMP_LAND_RADIUS    = 3,      -- atterrissage à moins de tant d'une case (studs)
	RAMP_SETTLE_TIME    = 0.5,    -- après l'atterrissage, freinage jusqu'à la vitesse de course en tant au plus (s)
	RAMP_MAX_SPEED      = 200,    -- vitesse au plus le long du trajet (studs/s, sous MAX_SPEED_SERVER)
	RAMP_COST_EXTRA     = 20,     -- forfait ajouté au coût d'une arête de rampe (studs : risque, pas de tir sûr)
	RAMP_START_DIST     = 3,      -- trajet lancé à moins de tant de la case d'entrée (studs, à l'horizontale)
	RAMP_BLEND_TIME     = 0.25,   -- écart entre le bot et le départ du trajet résorbé en tant (s)

	-- Comportement (#141) : perception, mémoire, états (BotBrain, règles dans BotBehaviorRules)
	PERCEPTION_INTERVAL = 0.1,    -- regard autour de lui tous les tant (s)
	VIEW_FOV            = 100,    -- champ de vision, angle total autour du regard (°)
	VIEW_RANGE          = 400,    -- distance de vue au plus (studs)
	EYE_HEIGHT          = 1.5,    -- yeux au-dessus de la racine (studs)
	HEARING_RADIUS      = 200,    -- tir entendu à moins de tant (studs)
	HEARING_FUZZ        = 0.2,    -- position entendue faussée d'au plus tant × distance
	MEMORY_TIME         = 8,      -- cible oubliée après tant de secondes sans contact
	INVESTIGATE_POINTS  = 2,      -- points voisins fouillés après la dernière position connue

	-- Combat (#141, #143) : il garde sa course (jamais d'arrêt ni de poursuite), se tourne vers la cible, tire et
	-- reprend sa trajectoire. Difficulté unique : REACTION_TIME, COMBAT_AIM_TIME, COMBAT_TURN_RATE et AIM_SPREAD*
	REACTION_TIME       = 0.55,   -- avant de pouvoir tirer, depuis qu'il voit la cible ou la fin de sa grâce (s)
	COMBAT_AIM_TIME     = 0.3,    -- visée avant le tir, une fois réagi (s)
	COMBAT_COOLDOWN     = 1.5,    -- après un tir, regard rendu à la course (au moins la cadence de l'AWP, 1,46 s)
	COMBAT_TURN_RATE    = 720,    -- rotation du regard vers la cible (°/s)
	FIRE_YAW_TOLERANCE  = 2,      -- tire seulement si son cap est à moins de tant de la cible (°)
	AIM_SPREAD          = 2,      -- dispersion d'un tir sur une cible immobile (demi-angle du cône, °)
	AIM_SPREAD_SPEED    = 0.05,   -- en plus par stud/s de vitesse de la cible (° ; aucun malus selon sa propre vitesse)
	AIM_SPREAD_MAX      = 6,      -- dispersion au plus (°)
	FIRE_RANGE          = 240,    -- tir au fusil à moins de tant (studs ; le serveur refuse au-delà de 250)
	SPAWN_GRACE         = 4,      -- pas de tir sur un participant apparu depuis moins de tant (s, lancement compris)
	                              -- le temps de réaction et de visée part de sa fin (#298), le bot peut s'y tourner avant
	HUMAN_PREF_RANGE    = 100,    -- un humain hors grâce passe avant un bot plus proche à moins de tant (studs, #298)
	HUMAN_PREF_MARGIN   = 20,     -- en plus pour l'humain déjà visé (pas de va-et-vient au seuil, studs)
	KNIFE_RANGE         = 6,      -- cible à moins de tant : il sort le couteau (studs, entre les racines)
	KNIFE_DROP_RANGE    = 14,     -- cible au-delà de tant : il reprend le fusil
	KNIFE_HIT_RANGE     = 6.5,    -- coup de couteau porté à moins de tant (portée de l'arme : 7,5)
	TARGET_KEEP_TIME    = 2,      -- cible sortie du champ gardée en tête tant (s) : il se retourne vers elle
	LOST_CHASE_CHANCE   = 0.35,   -- cible perdue de vue : probabilité d'enquêter (sinon il reprend sa course)

	-- Se replacer : après un kill, ou touché sous tant de ses PV en combat (duel perdu d'avance)
	REPLACE_HEALTH      = 0.5,    -- part des PV
	REPLACE_RADIUS      = 90,     -- point de repli cherché à moins de tant (studs)
	REPLACE_MIN_DIST    = 16,     -- et à plus de tant (studs)
	REPLACE_W_COVER     = 1.0,    -- poids du couvert du point
	REPLACE_W_AWAY      = 1.0,    -- poids de l'éloignement de la menace

	-- Note dynamique d'une destination en état « chercher » (décision 3 de #133)
	DEST_WEIGHT_FIXED   = 1.0,    -- note fixe (0 à ~1,6)
	DEST_RECENT_TIME    = 60,     -- point visité par ce bot il y a moins de tant (s) : malus dégressif
	DEST_RECENT_MALUS   = 1.5,
	DEST_CLAIMED_MALUS  = 1.0,    -- par autre bot qui y va déjà
	DEST_DISTANCE_SCALE = 400,    -- malus de distance plein à tant de studs
	DEST_DISTANCE_MALUS = 0.4,
	DEST_RANDOM         = 0.6,    -- part de hasard (ajout tiré dans [0, tant[)

	-- Tenir un angle à l'arrivée sur un point (état « chercher »)
	HOLD_CHANCE         = 0.4,
	HOLD_MIN            = 2,      -- durée (s)
	HOLD_MAX            = 5,
	HOLD_LOOK_MIN       = 24,     -- regard vers un point visible à au moins tant (studs)

	-- Biais vers les humains : sans contact depuis tant (s, 0 = désactivé), il cherche du côté de l'humain le plus
	-- proche, dans une zone décalée au hasard (il ne connaît pas sa position)
	BIAS_DELAY          = 15,
	BIAS_SPREAD         = 60,     -- décalage de la zone (studs)
	BIAS_RADIUS         = 160,    -- bonus dégressif jusqu'à tant de la zone (studs)
	BIAS_BONUS          = 1.5,

	-- Outillage Studio : attributs de Workspace
	DEBUG_ATTRIBUTE     = "DebugBots", -- nombre de bots voulus (0 = aucun)
	DEBUG_NAV_ATTRIBUTE = "DebugNav",  -- vrai : affiche le plan (points et notes, arêtes, chemins des bots)
	DEBUG_GOTO_ATTRIBUTE = "DebugBotsGoto", -- Vector3 : tous les bots vont au point de passage le plus proche
}

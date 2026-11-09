-- Réglages des bots (#133). Étape 4/9 (#140) : plan de navigation (graphe de la map, notes des points, suivi de
-- chemin) ; le bot va d'un point tiré au hasard à un autre, en attendant les états (#141).
-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	-- Noms tirés d'une liste fixe (décision 5 de #133), affichés « BOT <nom> » dans le kill feed et le classement
	NAMES = { "Marcel", "Lucie", "Gaston", "Odette", "Raymond", "Simone", "Lucien", "Paulette" },
	MAX_BOTS            = 5,      -- plafond de bots en jeu (décision 2 de #133)

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
	NAV_COST_FACTOR     = { 1, 1.1, 1.4, 1.6 }, -- marche, descente, saut, échelle
	NAV_COST_EXTRA      = { 0, 2, 6, 10 },

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

	-- Outillage Studio : attributs de Workspace
	DEBUG_ATTRIBUTE     = "DebugBots", -- nombre de bots voulus (0 = aucun)
	DEBUG_NAV_ATTRIBUTE = "DebugNav",  -- vrai : affiche le plan (points et notes, arêtes, chemins des bots)
}

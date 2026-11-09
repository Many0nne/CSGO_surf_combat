-- Réglages des bots (#133). Étape 3/9 (#139) : bot sans IA, qui avance tout droit et saute de temps en temps.
-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	-- Noms tirés d'une liste fixe (décision 5 de #133), affichés « BOT <nom> » dans le kill feed et le classement
	NAMES = { "Marcel", "Lucie", "Gaston", "Odette", "Raymond", "Simone", "Lucien", "Paulette" },
	MAX_BOTS            = 5,      -- plafond de bots en jeu (décision 2 de #133)

	-- Marche d'essai (#139), remplacée par la navigation (#140)
	WANDER_JUMP_MIN     = 1.5,    -- délai minimal entre deux sauts (s)
	WANDER_JUMP_MAX     = 4,      -- délai maximal entre deux sauts (s)
	STUCK_SPEED_RATIO   = 0.3,    -- au sol, sous cette part de la vitesse voulue, le bot est gêné
	STUCK_TIME          = 0.35,   -- gêné aussi longtemps (s) : il fait demi-tour
	TURN_MIN            = 100,    -- demi-tour d'au moins tant de degrés
	TURN_MAX            = 260,    -- et d'au plus tant

	-- Outillage Studio : attribut de Workspace = nombre de bots voulus (0 = aucun)
	DEBUG_ATTRIBUTE     = "DebugBots",
}

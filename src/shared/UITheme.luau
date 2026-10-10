-- Tokens de style de l'interface (direction artistique « SLIPSTREAM », cf. DESIGN.md).
-- Seule source de couleurs, polices, tailles, rayons, espacements et transparences pour src/client/ui.
-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	Brand = {
		NAME    = "SLIPSTREAM",
		TAGLINE = "SURF · FFA",
		VERSION = "v0.1",
	},

	Color = {
		-- Fonds (nuit profonde, du plus sombre au plus élevé)
		BG             = Color3.fromRGB(7, 11, 18),
		BG_GRAD_TOP    = Color3.fromRGB(12, 20, 32),
		BG_GRAD_BOTTOM = Color3.fromRGB(4, 7, 12),
		SURFACE        = Color3.fromRGB(13, 20, 31),
		SURFACE_RAISED = Color3.fromRGB(19, 29, 44),
		SURFACE_HOVER  = Color3.fromRGB(26, 40, 60),
		TRACK          = Color3.fromRGB(24, 36, 54),
		BORDER         = Color3.fromRGB(31, 46, 68),
		BACKDROP       = Color3.fromRGB(0, 0, 0),

		-- Texte
		TEXT           = Color3.fromRGB(230, 238, 248),
		TEXT_DIM       = Color3.fromRGB(168, 182, 200),
		MUTED          = Color3.fromRGB(107, 127, 156),
		FAINT          = Color3.fromRGB(46, 62, 84),

		-- Accent mouvement (vitesse, actions principales)
		ACCENT         = Color3.fromRGB(34, 211, 238),
		ACCENT_HOVER   = Color3.fromRGB(103, 232, 249),
		ON_ACCENT      = Color3.fromRGB(4, 18, 26),

		-- Accent combat (mort, victoire, alerte)
		COMBAT         = Color3.fromRGB(244, 63, 94),
		WARN           = Color3.fromRGB(245, 158, 11),

		HANDLE         = Color3.fromRGB(255, 255, 255),
	},

	Font = {
		DISPLAY = Enum.Font.Michroma,      -- logo, titres d'écran, bannière
		HEADING = Enum.Font.GothamBlack,   -- boutons principaux, titres de bloc
		LABEL   = Enum.Font.GothamBold,    -- libellés, en-têtes de section, boutons secondaires
		BODY    = Enum.Font.Gotham,        -- texte courant
		MONO    = Enum.Font.RobotoMono,    -- chiffres : timer, vitesse, valeurs
	},

	TextSize = {
		LOGO    = 26,
		TITLE   = 18,
		BANNER  = 20,
		NUMERIC = 28,
		TIMER   = 20,
		BUTTON  = 15,
		BODY    = 13,
		LABEL   = 11,
		CAPTION = 10,
	},

	Radius = {
		SM   = 2,
		MD   = 3,
		LG   = 6,
		PILL = 7,
	},

	Space = {
		XS = 4,
		SM = 8,
		MD = 12,
		LG = 24,
		XL = 32,
	},

	Stroke = {
		THIN   = 1,
		STRIPE = 3,
	},

	Transparency = {
		OVERLAY  = 0.15,
		BACKDROP = 0.55,
		ROW_ODD  = 0.5,
		HUD      = 0.2,
	},

	Motion = {
		FAST = 0.1,
	},
}

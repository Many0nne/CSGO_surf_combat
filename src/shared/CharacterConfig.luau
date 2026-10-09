-- CharacterConfig.luau
-- Rig, skin et animations 3e personne communs aux joueurs et aux bots (#1).
-- Une seule source de vérité : joueurs et bots partagent le même rig
-- (StarterCharacter) et le même skin (CharacterAppearance), et
-- CharacterAnimator choisit les pistes depuis la même table d'animations.

-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	-- ── Rig / skin ──────────────────────────────────────────────────────────
	-- Rig : StarterPlayer.StarterCharacter (cf. CharacterAppearance). RIG_TYPE ne
	-- sert qu'au rig de secours généré quand la place n'a pas de StarterCharacter.
	RIG_TYPE = Enum.HumanoidRigType.R15,

	-- Couleurs du corps (tenue "opérateur" sobre, lisible sur fond clair/sombre).
	SKIN_COLOR  = Color3.fromRGB(204, 142, 105),
	TORSO_COLOR = Color3.fromRGB(72, 80, 58),
	ARM_COLOR   = Color3.fromRGB(72, 80, 58),
	LEG_COLOR   = Color3.fromRGB(46, 48, 52),

	-- Ids d'IMAGE (template) optionnels, 0 = aucun : Shirt.ShirtTemplate,
	-- Pants.PantsTemplate et Decal du visage.
	SHIRT_ID = 0,
	PANTS_ID = 0,
	FACE_ID  = 0,

	-- ── Animations 3e personne ──────────────────────────────────────────────
	-- Animations R15 par défaut de Roblox (utilisables dans toute expérience).
	-- Une entrée vide ("") retombe sur FALLBACK : publier une vraie animation
	-- d'accroupissement / de surf et renseigner son id ici suffit.
	ANIMATIONS = {
		IDLE        = "rbxassetid://507766666",
		WALK        = "rbxassetid://507777826",
		RUN         = "rbxassetid://507767714",
		JUMP        = "rbxassetid://507765000",
		FALL        = "rbxassetid://507767968",
		CROUCH_IDLE = "",
		CROUCH_WALK = "",
		SURF        = "",
	},
	FALLBACK = {
		CROUCH_IDLE = "IDLE",
		CROUCH_WALK = "WALK",
		SURF        = "FALL",
	},

	-- Vitesse (studs/s) à laquelle chaque cycle de marche/course joue à 1x :
	-- la vitesse de lecture suit la vitesse horizontale réelle (pas de patinage).
	REF_SPEED = {
		WALK        = 8,
		RUN         = 18,
		CROUCH_WALK = 8,
	},
	PLAYBACK_MIN = 0.5,
	PLAYBACK_MAX = 2.0,

	-- Seuils de sélection d'état (studs/s horizontaux).
	IDLE_SPEED_MAX = 0.75,  -- en dessous : idle
	WALK_SPEED_MAX = 12,    -- en dessous : marche, au-dessus : course

	FADE_TIME      = 0.15,  -- fondu entre deux pistes (s)
	LAND_HOLD_TIME = 0.08,  -- sol à tenir avant de quitter la pose aérienne (bhop)
}

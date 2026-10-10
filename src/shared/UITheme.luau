-- Tokens de style de l'interface (direction « Tactical » : ambre sur acier, issue #18).
-- Seule source des couleurs, polices, tailles, durées et courbes d'animation des écrans.
-- Alignement en colonnes conservé volontairement
-- stylua: ignore
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- stylua: ignore
local Colors = {
	Ground        = rgb(21, 24, 28),    -- fond général, texte sur ambre
	Panel         = rgb(27, 31, 36),    -- panneaux et modales
	PanelDark     = rgb(17, 20, 24),    -- barre de navigation, HUD
	Raised        = rgb(34, 39, 46),    -- survol, onglet actif
	Border        = rgb(44, 49, 56),
	BorderStrong  = rgb(58, 64, 72),
	Text          = rgb(236, 232, 222),
	TextSoft      = rgb(196, 200, 206),
	Muted         = rgb(154, 160, 168),
	Accent        = rgb(242, 169, 0),   -- ambre
	AccentHover   = rgb(255, 194, 31),
	AccentPress   = rgb(217, 150, 0),
	AccentMuted   = rgb(74, 69, 54),    -- bouton ambre désactivé
	Danger        = rgb(200, 55, 45),   -- bloc « éliminé »
	Alert         = rgb(255, 74, 61),   -- timer < 30 s, erreurs
	Success       = rgb(108, 197, 108),
	White         = rgb(255, 255, 255),
}

-- Couleur de chaque palier de vitesse (index aligné sur HUDRules.SPEED_TIERS)
-- stylua: ignore
local SpeedTierColors = {
	rgb(236, 232, 222), -- à l'arrêt
	rgb(168, 216, 110), -- RUN
	rgb(242, 169, 0),   -- FAST
	rgb(255, 122, 26),  -- SURF
	rgb(255, 74, 61),   -- MACH
}

-- Échelle du nombre du speedometer par palier (pulsation à chaque changement)
local SpeedTierScales = { 1, 1, 1.05, 1.1, 1.16 }

local OSWALD = "rbxasset://fonts/families/Oswald.json"
local TITILLIUM = "rbxasset://fonts/families/TitilliumWeb.json"
local ROBOTO_MONO = "rbxasset://fonts/families/RobotoMono.json"

-- stylua: ignore
local Fonts = {
	Display       = Font.new(OSWALD, Enum.FontWeight.Bold),
	DisplayMedium = Font.new(OSWALD, Enum.FontWeight.Medium),
	Body          = Font.new(TITILLIUM, Enum.FontWeight.Regular),
	BodyBold      = Font.new(TITILLIUM, Enum.FontWeight.Bold),
	Mono          = Font.new(ROBOTO_MONO, Enum.FontWeight.Medium),
	MonoBold      = Font.new(ROBOTO_MONO, Enum.FontWeight.Bold),
}

-- Tailles de texte (px à la résolution de référence, 100 max côté Roblox)
-- stylua: ignore
local TextSize = {
	Hero    = 96,
	Banner  = 48,
	H1      = 34,
	H2      = 30,
	Speed   = 28,
	Count   = 44,
	Title   = 22,
	Nav     = 17,
	Body    = 16,
	Small   = 14,
	Caption = 12,
	Micro   = 11,
}

local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

-- stylua: ignore
local Motion = {
	Hover   = TweenInfo.new(0.15, Style.Quad, Dir.Out),     -- survol
	Press   = TweenInfo.new(0.08, Style.Quad, Dir.Out),     -- clic
	Enter   = TweenInfo.new(0.35, Style.Quint, Dir.Out),    -- entrée d'écran
	Exit    = TweenInfo.new(0.2, Style.Quad, Dir.In),       -- sortie d'écran
	Nav     = TweenInfo.new(0.25, Style.Quint, Dir.Out),    -- soulignement de navigation
	Shutter = TweenInfo.new(0.45, Style.Quint, Dir.InOut),  -- volets menu → jeu
	Band    = TweenInfo.new(0.45, Style.Quint, Dir.InOut),  -- bandeau de fin de round
	Pop     = TweenInfo.new(0.3, Style.Back, Dir.Out),      -- compteur, palier de vitesse
	Color   = TweenInfo.new(0.2, Style.Quad, Dir.Out),      -- changement de couleur
	Blink   = TweenInfo.new(0.5, Style.Linear, Dir.InOut, -1, true), -- timer < 30 s
	Stagger = 0.035,                                        -- décalage entre lignes
}

-- stylua: ignore
local Layout = {
	ReferenceHeight = 720, -- hauteur d'écran des maquettes (UIScale part de là)
	HeaderHeight    = 64,
	Margin          = 64,
	ContentTop      = 112,
	NavItemWidth    = 140,
	TopbarSafeLeft  = 224, -- px écran occupés en haut à gauche par les boutons Roblox
}

return {
	Colors = Colors,
	SpeedTierColors = SpeedTierColors,
	SpeedTierScales = SpeedTierScales,
	Fonts = Fonts,
	TextSize = TextSize,
	Motion = Motion,
	Layout = Layout,
}

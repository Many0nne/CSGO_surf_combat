-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	ROUND_DURATION     = 300,  -- 5 minutes
	RESPAWN_DELAY      = 2.5,
	RESPAWN_MARGIN     = 3,    -- seconds past RESPAWN_DELAY before a DEAD client asks to spawn again (#245)
	RESULT_DURATION    = 6,    -- seconds result banner is shown before returning to menu
	AUTO_SAVE_INTERVAL = 120,  -- seconds between stats auto-saves, only for players with unsaved changes (StatsStore)
	SPAWN_PROTECTION   = 2.5,  -- seconds of invulnerability while launched from the sun (#69)
	LEAVE_DEATH_WINDOW = 5,    -- seconds after a hit during which MENU PRINCIPAL counts as a death (#217, LeaveRules)
	ACTIVE_MAP         = "Dizzy", -- map jouée : nom d'un .rbxm de assets/rbx/Maps ("Dizzy")
}

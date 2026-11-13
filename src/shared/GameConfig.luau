-- Alignement en colonnes conservé volontairement
-- stylua: ignore
return {
	ROUND_DURATION     = 300,  -- 5 minutes
	RESPAWN_DELAY      = 2.5,
	RESPAWN_MARGIN     = 3,    -- seconds past RESPAWN_DELAY before a DEAD client asks to spawn again (#245)
	RESULT_DURATION    = 6,    -- seconds of result banner (client) and "result" state (server) before the next round (#300)
	AUTO_SAVE_INTERVAL = 120,  -- seconds between stats auto-saves, only for players with unsaved changes (StatsStore)
	SPAWN_PROTECTION   = 2,    -- seconds of invulnerability after any spawn, dropped at the first shot (#288, SpawnProtection)
	SPAWN_SAFE_RADIUS  = 100,  -- studs : a spawn point closer than this to a living enemy is avoided (#288, SpawnPointRules)
	LEAVE_DEATH_WINDOW = 5,    -- seconds after a hit during which MENU PRINCIPAL counts as a death (#217, LeaveRules)
	ACTIVE_MAP         = "Dizzy", -- map jouée : nom d'un .rbxm de assets/rbx/Maps ("Dizzy")
}

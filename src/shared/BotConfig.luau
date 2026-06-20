-- BotConfig.luau
-- Tuning constants for server-controlled AI bots (Phase 1: roam + fight).
-- See plan: bots fill empty combatant slots so a lone player always has
-- opponents. Surf/air-strafe is a Phase 2 follow-up (STRAFE_ENABLED).

return {
	-- ── Population ──────────────────────────────────────────────────────────
	-- Target number of combatants (players + bots) the round tries to keep.
	TARGET_POPULATION = 6,
	-- Hard cap on simultaneous bots, regardless of target.
	MAX_BOTS          = 6,
	-- Seconds before a dead bot respawns.
	RESPAWN_DELAY     = 3,

	-- Display names assigned to bots (cycled, "(2)" suffix if exhausted).
	NAMES = {
		"Phoenix", "Volkov", "Ramsey", "Kobra", "Specter",
		"Dragan", "Maverick", "Slick", "Ghost", "Reaper",
	},

	-- ── Bot character ───────────────────────────────────────────────────────
	HEALTH    = 100,
	WALK_SPEED = 18,
	-- Optional template model in ServerStorage to clone (must contain a
	-- Humanoid + HumanoidRootPart). If absent, bots spawn as a real R15 avatar
	-- rig via CreateHumanoidModelFromDescription (visually identical to players).
	TEMPLATE_NAME = "BotTemplate",

	-- ── Combat ──────────────────────────────────────────────────────────────
	-- Which weapon the bots use. Damage AND fire rate are read from
	-- WeaponConfig.Weapons[WEAPON] — bots fire the exact same weapon as players
	-- (no bot-specific damage/fire-rate). The third-person weapon model is also
	-- cloned from ReplicatedStorage.ViewModels[WEAPON].
	WEAPON        = "AWP",
	-- Viewmodel guns are oversized for the camera; scale the third-person clone.
	WEAPON_SCALE  = 0.5,
	-- Fine-tune where the gun sits relative to the hand.
	WEAPON_GRIP_OFFSET = Vector3.new(0, -0.2, 0),
	-- Delay before a bot fires at a freshly spotted enemy (gives you a chance).
	REACTION_TIME = 0.45,
	-- Bot aim error in degrees (the "skill" knob — shots are real raycasts, so
	-- cover always blocks them; this just makes bots miss sometimes). Higher =
	-- less accurate.
	AIM_SPREAD          = 7,
	-- Extra aim error (degrees) per stud/s of the target's horizontal speed, so
	-- moving fast (e.g. surfing) genuinely makes you harder to hit.
	AIM_SPREAD_PER_SPEED = 0.05,
	-- Cap on total aim error so bots aren't completely blind to fast targets.
	AIM_SPREAD_MAX      = 22,
	-- Max distance (studs) at which a bot will notice and fire on a combatant.
	DETECT_RANGE  = 220,
	-- Preferred engagement distance (studs); bots circle-strafe around this.
	PREFERRED_RANGE = 55,
	-- +/- band (studs) around PREFERRED_RANGE in which the bot stops advancing
	-- or retreating (prevents oscillating "come and go" movement).
	RANGE_DEADZONE  = 12,

	-- ── Roam / search ─────────────────────────────────────────────────────────
	-- Seconds a bot keeps moving toward an enemy's last-seen position after
	-- losing sight of it.
	SEARCH_MEMORY   = 6,
	-- A bot with no target walks toward the nearest player within this range
	-- (so it actively hunts you instead of wandering aimlessly).
	PATROL_RANGE    = 600,
	-- Radius (studs) of the random wander target when nobody is around at all.
	WANDER_RADIUS   = 70,
	-- Seconds between wander re-targets.
	REPATH_INTERVAL = 4,
	-- Seconds a bot commits to one strafe direction before it may flip.
	STRAFE_FLIP_INTERVAL = 1.6,
	-- Throttle (seconds) of the per-bot AI decision tick.
	THINK_INTERVAL  = 0.12,

	-- ── Phase 2 ─────────────────────────────────────────────────────────────
	STRAFE_ENABLED = false,
}

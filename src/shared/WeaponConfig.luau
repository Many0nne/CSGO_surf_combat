-- WeaponConfig.luau
-- Shared weapon definitions and defaults

local WeaponConfig = {}

WeaponConfig.Weapons = {
	AWP = {
		Name = "AWP",
		Damage = 115,
		RPM = 41,
		FireDelay = 60 / 41, -- seconds between shots
		ReloadTime = 3.7,
		Magazine = 5,
		Reserve = 10,
		Penetration = 250, -- TODO: implement penetration handling
		-- Recommended run speed multiplier while holding this weapon (client-side).
		-- Not a fixed game-units value; movement system multiplies wishspeed by this.
		RunSpeedMultiplier = 0.75,
		HasScope       = true,
		ScopeFov1      = 40,
		ScopeFov2      = 10,
		ScopeTweenTime = 0.1,
	},
}

return WeaponConfig


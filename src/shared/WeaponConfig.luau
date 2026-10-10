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
		EquipTime = 1.58,
		ShootAnimTime = 1.63,
		HasScope = true,
		ScopeFov1 = 40,
		ScopeFov2 = 10,
		ScopeTweenTime = 0.1,
		-- Modèle 3e personne (#5) : échelle du clone du viewmodel, grip (CFrame de la poignée dans le
		-- repère de la main) et pose de tenue des épaules (cf. WeaponThirdPerson.POSES).
		ThirdPerson = {
			Scale = 0.5,
			Grip = CFrame.fromMatrix(Vector3.new(0, -0.2, 0), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1)),
			Pose = "Rifle",
		},
		AnimationSounds = {
			Equip = { "Bolt", "Draw" },
			Shoot = { "Shoot", "Bolt" },
			Reload = { "Bolt", "ClipIn", "ClipOut", "ClipHit" },
			Zoom = { "ZoomIn", "ZoomOut" },
		},
	},
	Butterfly = {
		Name = "Butterfly Knife",
		Damage = 50,
		RPM = 60,
		FireDelay = 1,
		Penetration = 0,
		RunSpeedMultiplier = 1.0,
		EquipTime = 1.0,
		ShootAnimTime = 1.0,
		IsMelee = true,
		MeleeRange = 7.5,
		BackstabMultiplier = 2,
		ThirdPerson = {
			Scale = 0.5,
			Grip = CFrame.fromMatrix(Vector3.new(0, -0.2, 0), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1)),
			Pose = "Melee",
		},
		AnimationSounds = {
			Equip = { "Equip" },
			Shoot = {},
		},
	},
}

return WeaponConfig

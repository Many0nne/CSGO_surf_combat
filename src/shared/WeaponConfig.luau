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
	M9Bayonet = {
		Name = "M9 Bayonet",
		Damage = 50,
		RPM = 150,
		FireDelay = 0.4, -- cadence CS:GO du clic gauche
		Penetration = 0,
		RunSpeedMultiplier = 1.0,
		EquipTime = 0.77,
		EquipAnimSpeed = 1.3, -- vitesse de lecture de la piste Equip (1 s) : sortie en 0,77 s
		ShootAnimTime = 0.4, -- verrou d'action : le coup suivant coupe la fin de la piste (0,7 s)
		ShootAnimations = { "Shoot", "Shoot2" }, -- slashs du clic gauche, joués en alternance
		AttackFadeTime = 0, -- les coups partent sans fondu : la piste commence sur la pose de repos
		-- Clic droit : coup d'estoc, plus lourd et plus lent (dégâts et cadence CS:GO).
		SecondaryAttack = { Animation = "Stab", Damage = 65, FireDelay = 1, AnimTime = 1 },
		InspectAnimation = "Inspect", -- touche F : purement visuel, interrompu par une attaque
		IsMelee = true,
		MeleeRange = 7.5,
		BackstabMultiplier = 2,
		-- Mesh unique dans le repère de la Handle : +Z = axe du couteau (vers la pointe), +X = tranchant.
		-- Son origine est le centre du mesh : le centre du manche est à 1,21 stud derrière (Z = -1,21 × Scale).
		-- Prise marteau : lame dressée hors du poing, tranchant vers l'avant de l'avant-bras.
		ThirdPerson = {
			Scale = 0.6,
			Grip = CFrame.fromMatrix(Vector3.new(0, -0.13, -0.726), Vector3.new(0, -1, 0), Vector3.new(-1, 0, 0)),
			Pose = "Melee",
		},
		AnimationSounds = {
			Equip = { "Equip" },
			Shoot = {},
			Shoot2 = {},
			Stab = {},
			Inspect = { "Equip" },
		},
	},
}

return WeaponConfig

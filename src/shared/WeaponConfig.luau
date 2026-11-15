-- WeaponConfig.luau
-- Shared weapon definitions and defaults

local WeaponConfig = {}

-- Portée (studs) du rayon des armes à distance, tirée par le client (HitscanSystem) et vérifiée par le serveur
-- (ShotRules.checkDistance, avec une marge) : un tir légitime n'est jamais refusé pour sa distance (#174).
WeaponConfig.HITSCAN_RANGE = 2048

-- Cadence de l'AWP (`cycletime` 1,455 s de CS:GO, items_game.txt ; 41 coups/min) : écart entre deux tirs, côté client
-- (WeaponSystem) comme côté serveur (Validator, ShotRules, ShotRelayRules), et verrou d'action du tir (#221, #404).
local AWP_FIRE_DELAY = 1.455

-- Verrous d'action (#404) : ils reprennent les valeurs de CS:GO et ne dépendent pas de la longueur des pistes. Une piste
-- plus longue que son verrou est coupée par l'action suivante (tir, lunette, rechargement), comme dans CS:GO.
--   EquipTime : arme inutilisable après la sortie (AWP : séquence draw, 1,267 s, `m_flDeployDuration` de CS2 ;
--               couteaux : 1 s codé en dur pour tous les couteaux, `hardcoded_knife_deploy_time` de weapon_knife.cpp).
--   ReloadTime : arme inutilisable pendant tout le rechargement, comme CS:GO (fin de la séquence reload, pas de tir
--                anticipé) ; AWP 3,667 s (`m_flDisallowAttackAfterReloadStartDuration` de CS2).

WeaponConfig.Weapons = {
	AWP = {
		Name = "AWP",
		-- Fiche de la vitrine du menu (#112) : catégorie en capitales (string.upper ignore les accents), et précision
		-- affichée de 0 à 1 (la dispersion n'est pas simulée)
		Category = "FUSIL DE PRÉCISION",
		Accuracy = 0.9,
		Damage = 115,
		RPM = 41,
		FireDelay = AWP_FIRE_DELAY, -- seconds between shots
		ReloadTime = 3.667, -- 110 images à 30 i/s (CS:GO)
		Magazine = 5,
		Reserve = math.huge, -- réserve illimitée (#165) : le rechargement remplit toujours le chargeur
		Penetration = 250, -- TODO: implement penetration handling
		-- Recommended run speed multiplier while holding this weapon (client-side).
		-- Not a fixed game-units value; movement system multiplies wishspeed by this.
		RunSpeedMultiplier = 0.75,
		EquipTime = 1.267, -- 38 images à 30 i/s (CS:GO) : le tir ou la lunette coupe la fin de la piste Equip (1,58 s)
		-- Verrou d'action (#221) = cadence : le tir suivant coupe la fin de la piste Shoot (1,63 s)
		ShootAnimTime = AWP_FIRE_DELAY,
		HasScope = true,
		-- Touche F : pivot de profil puis arme dressée (référence CS2, 5 s), purement visuel, interrompu par une attaque ;
		-- refusé lunette active (l'inspection exige l'état IDLE).
		InspectAnimation = "Inspect",
		ScopeFov1 = 40,
		ScopeFov2 = 10,
		ScopeTweenTime = 0.1,
		-- Modèle 3e personne (#5, #107) : échelle du clone du viewmodel, grip (CFrame de la poignée dans le
		-- repère de la main) et tenue du haut du corps (cf. WeaponThirdPerson.POSES).
		-- Tenue F1 : main droite sur la poignée pistolet (grip généré par tools/anim/poses3p/export_pose.js) ;
		-- échelle 0,7 (7,1 studs) : la crosse disparaît dans l'épaule, l'arme doit rester lisible de loin.
		-- Modèle de #403 : position recalée du déplacement du centre de la Handle (boîtier), même point de l'arme dans la
		-- main (1,38 ; -0,66 du repère de assets/awp/build_awp.py, sur la poignée à trou de pouce).
		ThirdPerson = {
			Scale = 0.7,
			Grip = CFrame.new(
				0.24144,
				-0.97118,
				-0.12468,
				0.55516,
				-0.547,
				0.62657,
				-0.80806,
				-0.53317,
				0.25051,
				0.19704,
				-0.64538,
				-0.73801
			),
			Pose = "Rifle",
		},
		-- Douille chez les autres (#237, CasingEjection) : délai (s) entre le tir relayé et l'éjection, instant du
		-- marqueur Eject de la piste Shoot (culasse en arrière, keyframe de 0,817 s). Sans ce champ : pas de douille 3P.
		CasingEjectDelay = 0.82,
		AnimationSounds = {
			Equip = { "Bolt", "Draw" },
			Shoot = { "Shoot", "Bolt" },
			Reload = { "Bolt", "ClipIn", "ClipOut", "ClipHit" },
			Zoom = { "ZoomIn", "ZoomOut" },
			Inspect = {},
		},
		-- Tir entendu par les autres joueurs (#156, ShotSoundRules) : son "Shoot" du viewmodel en 3D sur l'arme 3P du
		-- tireur, plein jusqu'à RollOffMinDistance studs puis en 1/distance, coupé à RollOffMaxDistance (portée du
		-- tir : l'AWP s'entend de loin, -20 dB à 400 studs).
		RemoteShotSound = {
			Sound = "Shoot",
			RollOffMinDistance = 40,
			RollOffMaxDistance = 2048,
		},
	},
	M9Bayonet = {
		Name = "M9 Bayonet",
		Category = "COUTEAU",
		Accuracy = 0.7,
		Damage = 50,
		RPM = 150,
		-- Cadences CS:GO du clic gauche (weapon_knife.cpp) : 0,4 s après un coup dans le vide, 0,5 s après un coup qui
		-- touche ; l'estoc attend 0,5 s après une taille, touchée ou non.
		FireDelay = 0.4,
		HitFireDelay = 0.5,
		SecondaryDelay = 0.5,
		Penetration = 0,
		RunSpeedMultiplier = 1.0,
		EquipTime = 1, -- piste Equip de 1 s, jouée à sa vitesse
		ShootAnimTime = 0.4, -- verrou d'action : le coup suivant coupe la fin de la piste (0,7 s)
		ShootAnimations = { "Shoot", "Shoot2" }, -- slashs du clic gauche, joués en alternance
		AttackFadeTime = 0, -- les coups partent sans fondu : la piste commence sur la pose de repos
		-- Clic droit : coup d'estoc, plus lourd et plus lent (dégâts et cadences CS:GO : 1 s dans le vide, 1,1 s touché,
		-- pour les deux clics).
		SecondaryAttack = { Animation = "Stab", Damage = 65, FireDelay = 1, HitFireDelay = 1.1, AnimTime = 1 },
		InspectAnimation = "Inspect", -- touche F : purement visuel, interrompu par une attaque
		IsMelee = true,
		MeleeRange = 7.5,
		BackstabMultiplier = 2,
		-- Mesh unique dans le repère de la Handle : +Z = axe du couteau (vers la pointe), +X = tranchant.
		-- Son origine est le centre du mesh : le centre du manche est à 1,21 stud derrière (Z = -1,21 × Scale).
		-- Tenue C1 (#107) : lame dans l'axe de l'avant-bras, pointe relevée de 15°, tranchant vers le bas ; échelle 1
		-- pour que la lame dépasse nettement du poing (1,59 stud). Grip généré par tools/anim/poses3p/export_pose.js.
		ThirdPerson = {
			Scale = 1,
			Grip = CFrame.new(0, -1.16877, -0.31317, 0, -1, 0, -0.25882, 0, -0.96593, 0.96593, 0, -0.25882),
			Pose = "Melee",
		},
		AnimationSounds = {
			Equip = { "Equip" },
			Shoot = {},
			Shoot2 = {},
			Stab = {},
			Inspect = {},
		},
	},
	-- Couteau de base Ka-Bar : mêmes dégâts, cadence et portée que la M9, animations propres (assets/kabar_viewmodel).
	KaBar = {
		Name = "Ka-Bar",
		Category = "COUTEAU",
		Accuracy = 0.7,
		Damage = 50,
		RPM = 150,
		FireDelay = 0.4, -- cadences du clic gauche, comme la M9
		HitFireDelay = 0.5,
		SecondaryDelay = 0.5,
		Penetration = 0,
		RunSpeedMultiplier = 1.0,
		EquipTime = 1, -- piste Equip de 0,85 s (durée du couteau CT), puis repos jusqu'au verrou, comme dans CS:GO
		ShootAnimTime = 0.4, -- verrou d'action : le coup suivant coupe la fin de la piste (1,1 s et 0,87 s)
		ShootAnimations = { "Shoot", "Shoot2" }, -- coups du clic gauche, joués en alternance
		AttackFadeTime = 0, -- les coups partent sans fondu : la piste commence sur la pose de repos
		-- Clic droit : estoc droit, plus lourd et plus lent (mêmes dégâts et cadence que l'estoc de la M9).
		SecondaryAttack = { Animation = "Stab", Damage = 65, FireDelay = 1, HitFireDelay = 1.1, AnimTime = 1 },
		InspectAnimation = "Inspect", -- touche F : purement visuel, interrompu par une attaque
		IsMelee = true,
		MeleeRange = 7.5,
		BackstabMultiplier = 2,
		-- Handle = manche en cuir, origine au centre du manche (la prise tient ici) ; +Z = pointe, +X = tranchant dans le
		-- repère de prise de build_viewmodel.py, la Handle du mesh est tournée de Q = (X local = -Y prise, Y local = -X
		-- prise, Z local = -Z prise). Grip = grip de la M9 recalé : centre du manche à l'origine, repère tourné par Q.
		ThirdPerson = {
			Scale = 1,
			Grip = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.25882, 0.96593, 0, -0.96593, 0.25882),
			Pose = "Melee",
		},
		AnimationSounds = {
			Equip = { "Equip" },
			Shoot = {},
			Shoot2 = {},
			Stab = {},
			Inspect = {},
		},
	},
}

-- Types d'attaque de mêlée envoyés par le client dans le remote MeleeDamage : le serveur en déduit dégâts et cadence.
WeaponConfig.AttackKind = {
	PRIMARY = "primary",
	SECONDARY = "secondary",
}

-- Cette méthode permet de lire les dégâts et la cadence d'une attaque de mêlée qui touche lorsque le serveur valide un
-- coup (il ne voit que les coups qui touchent) ; nil si l'arme n'est pas une arme de mêlée ou n'a pas cette attaque.
function WeaponConfig.getMeleeAttack(cfg: any, attackKind: any): (number?, number?)
	if not cfg.IsMelee then
		return nil, nil
	end
	if attackKind == WeaponConfig.AttackKind.PRIMARY then
		return cfg.Damage, cfg.HitFireDelay or cfg.FireDelay
	end
	local secondary = cfg.SecondaryAttack
	if attackKind == WeaponConfig.AttackKind.SECONDARY and secondary then
		return secondary.Damage, secondary.HitFireDelay or secondary.FireDelay
	end
	return nil, nil
end

-- Cette méthode permet de calculer, après une attaque de mêlée, les délais (s) avant le prochain clic gauche et le
-- prochain clic droit lorsque le client lance un coup (hit faux) puis apprend qu'il a touché (hit vrai), comme CS:GO.
function WeaponConfig.meleeCooldowns(cfg: any, attackKind: any, hit: boolean): (number, number)
	local secondary = cfg.SecondaryAttack
	local isSecondary = attackKind == WeaponConfig.AttackKind.SECONDARY and secondary ~= nil
	local delay = if isSecondary then secondary.FireDelay else cfg.FireDelay
	if hit then
		-- Même délai que celui du serveur, qui ne voit que les coups qui touchent
		local _, hitDelay = WeaponConfig.getMeleeAttack(cfg, attackKind)
		delay = hitDelay or delay
	end
	if isSecondary then
		return delay, delay
	end
	return delay, math.max(delay, cfg.SecondaryDelay or delay)
end

return WeaponConfig

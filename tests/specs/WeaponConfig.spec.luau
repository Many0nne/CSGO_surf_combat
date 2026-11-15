-- Cadence des armes (#221) : le verrou d'action du client (ShootAnimTime, état FIRING de WeaponSystem) ne dépasse jamais
-- la cadence (FireDelay), seule valeur lue par le serveur (Validator, ShotRules, ShotRelayRules). Sinon un clic à la
-- cadence de l'arme serait ignoré par le client, qui tirerait moins vite que ce que le serveur accepte.
return function(T, Loader)
	local WeaponConfig = Loader.new():require("src/shared/WeaponConfig")

	T.describe("WeaponConfig : cadence client et serveur", function()
		T.it("garde le verrou de tir de chaque arme sous sa cadence", function()
			for name, cfg in WeaponConfig.Weapons do
				if cfg.FireDelay and cfg.ShootAnimTime then
					T.expect(
						cfg.ShootAnimTime <= cfg.FireDelay + 1e-9,
						string.format("%s : verrou %.3f s > cadence %.3f s", name, cfg.ShootAnimTime, cfg.FireDelay)
					)
				end
				local secondary = cfg.SecondaryAttack
				if secondary and secondary.FireDelay and secondary.AnimTime then
					T.expect(
						secondary.AnimTime <= secondary.FireDelay + 1e-9,
						string.format("%s (clic droit) : verrou > cadence", name)
					)
				end
			end
		end)

		T.it("tire à l'AWP à la cadence de CS:GO (cycletime 1,455 s, 41 coups/min), verrou compris", function()
			local awp = WeaponConfig.Weapons.AWP
			T.expectNear(awp.FireDelay, 1.455)
			T.expectEqual(math.floor(60 / awp.FireDelay), awp.RPM, "RPM affiché cohérent avec FireDelay")
			T.expectNear(awp.ShootAnimTime, awp.FireDelay, 1e-9, "verrou = cadence, comme la M9")
		end)
	end)

	-- Verrous d'action (#404) : valeurs de CS:GO (weapon_knife.cpp, items_game.txt, weapons.vdata de CS2), indépendantes
	-- de la longueur des pistes, que l'action suivante coupe.
	T.describe("WeaponConfig : verrous CS:GO (#404)", function()
		T.it("reprend l'equip et le rechargement de CS:GO", function()
			local weapons = WeaponConfig.Weapons
			T.expectNear(weapons.AWP.EquipTime, 1.267, 1e-9, "AWP : séquence draw de 38 images à 30 i/s")
			T.expectNear(weapons.AWP.ReloadTime, 3.667, 1e-9, "AWP : séquence reload de 110 images à 30 i/s")
			T.expectEqual(weapons.M9Bayonet.EquipTime, 1, "couteaux : hardcoded_knife_deploy_time")
			T.expectEqual(weapons.KaBar.EquipTime, 1)
		end)

		T.it("ne règle plus la vitesse de la piste Equip : le verrou ne dépend que d'EquipTime", function()
			for name, cfg in WeaponConfig.Weapons do
				T.expectEqual(cfg.EquipAnimSpeed, nil, name)
			end
		end)

		T.it("allonge la cadence d'un coup de couteau qui touche, comme CS:GO", function()
			local PRIMARY, SECONDARY = WeaponConfig.AttackKind.PRIMARY, WeaponConfig.AttackKind.SECONDARY
			for _, name in { "M9Bayonet", "KaBar" } do
				local cfg = WeaponConfig.Weapons[name]
				-- Cette méthode permet de lire les deux délais (clic gauche, clic droit) d'un coup lorsqu'on les compare.
				local function cooldowns(kind, hit): { number }
					return { WeaponConfig.meleeCooldowns(cfg, kind, hit) }
				end
				T.expectEqual(table.concat(cooldowns(PRIMARY, false), " "), "0.4 0.5", name .. " : taille dans le vide")
				T.expectEqual(table.concat(cooldowns(PRIMARY, true), " "), "0.5 0.5", name .. " : taille qui touche")
				T.expectEqual(table.concat(cooldowns(SECONDARY, false), " "), "1 1", name .. " : estoc dans le vide")
				T.expectEqual(table.concat(cooldowns(SECONDARY, true), " "), "1.1 1.1", name .. " : estoc qui touche")
			end
		end)

		T.it("donne au serveur la cadence d'un coup qui touche (il ne voit que ceux-là)", function()
			local m9 = WeaponConfig.Weapons.M9Bayonet
			T.expectEqual(select(2, WeaponConfig.getMeleeAttack(m9, WeaponConfig.AttackKind.PRIMARY)), 0.5)
			T.expectEqual(select(2, WeaponConfig.getMeleeAttack(m9, WeaponConfig.AttackKind.SECONDARY)), 1.1)
			T.expectEqual(select(2, WeaponConfig.getMeleeAttack(WeaponConfig.Weapons.AWP, "primary")), nil)
		end)
	end)

	T.describe("WeaponConfig : couteaux", function()
		T.it("donne au Ka-Bar les mêmes dégâts, cadence et portée que la M9", function()
			local m9, kabar = WeaponConfig.Weapons.M9Bayonet, WeaponConfig.Weapons.KaBar
			T.expect(kabar ~= nil, "KaBar absent de WeaponConfig.Weapons")
			for _, key in
				{
					"Damage",
					"FireDelay",
					"HitFireDelay",
					"SecondaryDelay",
					"MeleeRange",
					"BackstabMultiplier",
					"ShootAnimTime",
				}
			do
				T.expectEqual(kabar[key], m9[key], key)
			end
			T.expectEqual(kabar.SecondaryAttack.Damage, m9.SecondaryAttack.Damage)
			T.expectEqual(kabar.SecondaryAttack.FireDelay, m9.SecondaryAttack.FireDelay)
			T.expectEqual(kabar.SecondaryAttack.HitFireDelay, m9.SecondaryAttack.HitFireDelay)
			T.expectEqual(kabar.EquipTime, m9.EquipTime)
		end)

		T.it("décrit chaque piste jouée par un couteau (coups, estoc, inspection) dans AnimationSounds", function()
			for _, name in { "M9Bayonet", "KaBar" } do
				local cfg = WeaponConfig.Weapons[name]
				local played =
					{ cfg.SecondaryAttack.Animation, cfg.InspectAnimation, table.unpack(cfg.ShootAnimations) }
				for _, animation in played do
					T.expect(
						cfg.AnimationSounds[animation] ~= nil,
						name .. " : piste " .. animation .. " sans entrée AnimationSounds"
					)
				end
				T.expect(cfg.ThirdPerson and cfg.ThirdPerson.Grip ~= nil, name .. " : tenue 3P sans Grip")
			end
		end)

		T.it("donne une inspection (touche F) à chaque arme, décrite dans AnimationSounds", function()
			for name, cfg in WeaponConfig.Weapons do
				T.expect(cfg.InspectAnimation ~= nil, name .. " : pas d'InspectAnimation, F ne fait rien")
				T.expect(
					cfg.AnimationSounds[cfg.InspectAnimation] ~= nil,
					name .. " : piste " .. tostring(cfg.InspectAnimation) .. " sans entrée AnimationSounds"
				)
			end
		end)
	end)
end

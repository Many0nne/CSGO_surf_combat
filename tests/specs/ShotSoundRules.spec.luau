-- Son des tirs des autres (#156) : réglages par arme, choix de jouer, durée de vie.
return function(T, Loader)
	local ShotSoundRules = Loader.new():require("src/shared/ShotSoundRules")
	local WeaponConfig = Loader.new():require("src/shared/WeaponConfig")

	T.describe("ShotSoundRules.settingsFor (#156)", function()
		T.it("lit le son et l'atténuation de l'AWP dans WeaponConfig", function()
			local s = ShotSoundRules.settingsFor("AWP")
			local own = WeaponConfig.Weapons.AWP.RemoteShotSound
			T.expect(s ~= nil, "AWP sans réglages")
			T.expectEqual(s.Sound, own.Sound)
			T.expectEqual(s.RollOffMinDistance, own.RollOffMinDistance)
			T.expectEqual(s.RollOffMaxDistance, own.RollOffMaxDistance)
		end)

		T.it("le son de l'AWP est celui que joue le tireur (marqueur Shoot du viewmodel)", function()
			local s = ShotSoundRules.settingsFor("AWP")
			T.expect(table.find(WeaponConfig.Weapons.AWP.AnimationSounds.Shoot, s.Sound) ~= nil, s.Sound)
		end)

		T.it("l'AWP s'entend de loin : coupée au plus tôt à la portée de son tir", function()
			local s = ShotSoundRules.settingsFor("AWP")
			T.expect(s.RollOffMaxDistance >= WeaponConfig.HITSCAN_RANGE, tostring(s.RollOffMaxDistance))
			T.expect(s.RollOffMinDistance < s.RollOffMaxDistance, "atténuation inversée")
		end)

		T.it("rien pour une arme de mêlée, inconnue ou absente", function()
			T.expectEqual(ShotSoundRules.settingsFor("M9Bayonet"), nil)
			T.expectEqual(ShotSoundRules.settingsFor("Lance-roquettes"), nil)
			T.expectEqual(ShotSoundRules.settingsFor(nil), nil)
			T.expectEqual(ShotSoundRules.settingsFor(42), nil)
		end)
	end)

	T.describe("ShotSoundRules.shouldPlay (#156)", function()
		local shooter, me = {}, {}

		T.it("joue le tir d'un autre en partie, mort ou en fin de round", function()
			for _, state in { "SPAWNING", "IN_ROUND", "DEAD", "RESULT" } do
				T.expectEqual(ShotSoundRules.shouldPlay(shooter, me, state, 0), true, state)
			end
		end)

		T.it("ne joue pas son propre tir (pas de doublon chez le tireur)", function()
			T.expectEqual(ShotSoundRules.shouldPlay(me, me, "IN_ROUND", 0), false)
		end)

		T.it("ne joue pas sans tireur connu, ni dans les écrans du menu", function()
			T.expectEqual(ShotSoundRules.shouldPlay(nil, me, "IN_ROUND", 0), false, "tireur absent")
			T.expectEqual(ShotSoundRules.shouldPlay(shooter, me, "MENU", 0), false, "menu")
			T.expectEqual(ShotSoundRules.shouldPlay(shooter, me, "INFOS", 0), false, "infos")
			T.expectEqual(ShotSoundRules.shouldPlay(shooter, me, nil, 0), false, "état inconnu")
		end)

		T.it("joue même sans personnage local (mort, avant l'apparition)", function()
			T.expectEqual(ShotSoundRules.shouldPlay(shooter, nil, "DEAD", 0), true)
		end)

		T.it("borne le nombre de sons simultanés", function()
			local max = ShotSoundRules.MAX_ACTIVE
			T.expectEqual(ShotSoundRules.shouldPlay(shooter, me, "IN_ROUND", max - 1), true)
			T.expectEqual(ShotSoundRules.shouldPlay(shooter, me, "IN_ROUND", max), false)
		end)
	end)

	T.describe("ShotSoundRules.lifetime (#156)", function()
		T.it("longueur du son à sa vitesse, plus la marge", function()
			T.expectNear(ShotSoundRules.lifetime(1.2, 1), 1.2 + ShotSoundRules.LIFETIME_MARGIN)
			T.expectNear(ShotSoundRules.lifetime(2, 2), 1 + ShotSoundRules.LIFETIME_MARGIN)
		end)

		T.it("durée maximale si la longueur est inconnue (son en chargement) ou absurde", function()
			T.expectEqual(ShotSoundRules.lifetime(0, 1), ShotSoundRules.MAX_LIFETIME)
			T.expectEqual(ShotSoundRules.lifetime(0 / 0, 1), ShotSoundRules.MAX_LIFETIME)
			T.expectEqual(ShotSoundRules.lifetime(1, 0), ShotSoundRules.MAX_LIFETIME)
			T.expectEqual(ShotSoundRules.lifetime(600, 1), ShotSoundRules.MAX_LIFETIME, "plafonnée")
		end)
	end)
end

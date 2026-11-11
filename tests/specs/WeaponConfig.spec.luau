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

		T.it("tire à l'AWP à la cadence de CS (41 coups/min), verrou compris", function()
			local awp = WeaponConfig.Weapons.AWP
			T.expectNear(awp.FireDelay, 60 / 41)
			T.expectNear(awp.FireDelay, 60 / awp.RPM, 1e-9, "RPM et FireDelay cohérents")
			T.expectNear(awp.ShootAnimTime, awp.FireDelay, 1e-9, "verrou = cadence, comme la M9")
		end)
	end)
end

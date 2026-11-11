-- Rattachement d'une touche à son tir (#215, #216) : instant à LINK_TOLERANCE près, une touche par tir, âge et taille
-- du registre bornés, touche arrivée avant son ShotFired, mode et gravité du contrôle shotLink.
return function(T, Loader)
	local ShotLinkRules = Loader.new():require("src/server/ShotLinkRules")
	local ShotRules = Loader.new():require("src/server/ShotRules")
	local WeaponConfig = Loader.new():require("src/shared/WeaponConfig")

	T.describe("ShotLinkRules : rattachement par shotTime", function()
		T.it("rattache une touche au tir du même instant, pas au tir voisin", function()
			local ledger = ShotLinkRules.new()
			local first = ShotLinkRules.record(ledger, 100, 10, true, false)
			local second = ShotLinkRules.record(ledger, 100.3, 10.3, true, false)
			T.expectEqual(
				ShotLinkRules.find(ledger, 100, 10.35, "hit"),
				first,
				"touche du premier tir arrivée en dernier"
			)
			T.expectEqual(ShotLinkRules.find(ledger, 100.3, 10.35, "hit"), second)
			T.expectEqual(ShotLinkRules.find(ledger, 100.15, 10.35, "hit"), nil, "instant entre les deux")
		end)

		T.it("tolère LINK_TOLERANCE, pas au-delà, et prend le plus proche", function()
			local ledger = ShotLinkRules.new()
			local exact = ShotLinkRules.record(ledger, 100, 10, true, false)
			local tol = ShotLinkRules.LINK_TOLERANCE
			T.expectEqual(ShotLinkRules.find(ledger, 100 + tol * 0.5, 10, "hit"), exact)
			T.expectEqual(ShotLinkRules.find(ledger, 100 + tol * 1.5, 10, "hit"), nil)
			local near = ShotLinkRules.record(ledger, 100 + tol * 0.9, 10, true, false)
			T.expectEqual(ShotLinkRules.find(ledger, 100 + tol, 10, "hit"), near, "le plus proche")
		end)

		T.it("tolérance très inférieure à l'écart entre deux tirs acceptés", function()
			local minGap = WeaponConfig.Weapons.AWP.FireDelay - ShotRules.CADENCE_TOLERANCE
			T.expect(ShotLinkRules.LINK_TOLERANCE * 2 < minGap / 100, "tolérance : " .. ShotLinkRules.LINK_TOLERANCE)
		end)

		T.it("une seule touche par tir : un tir déjà touché n'est plus libre", function()
			local ledger = ShotLinkRules.new()
			local entry = ShotLinkRules.record(ledger, 100, 10, true, false)
			T.expectEqual(ShotLinkRules.find(ledger, 100, 10, "hit"), entry)
			entry.hit = true
			T.expectEqual(ShotLinkRules.find(ledger, 100, 10.01, "hit"), nil)
		end)

		T.it("touche arrivée avant son ShotFired : le ShotFired la retrouve (champ fired)", function()
			local ledger = ShotLinkRules.new()
			local early = ShotLinkRules.record(ledger, 100, 10, false, true)
			T.expectEqual(ShotLinkRules.find(ledger, 100, 10.01, "hit"), nil, "pas un tir à toucher")
			T.expectEqual(ShotLinkRules.find(ledger, 100, 10.01, "fired"), early)
			early.fired = true
			T.expectEqual(ShotLinkRules.find(ledger, 100, 10.02, "fired"), nil, "un seul ShotFired rattaché")
			-- Un ShotFired ordinaire n'est pas une touche en attente
			ShotLinkRules.record(ledger, 101, 10.5, true, false)
			T.expectEqual(ShotLinkRules.find(ledger, 101, 10.5, "fired"), nil)
		end)

		T.it("oublie les tirs de plus de MAX_AGE, et ceux venus du futur", function()
			local ledger = ShotLinkRules.new()
			ShotLinkRules.record(ledger, 100, 10, true, false)
			T.expect(ShotLinkRules.find(ledger, 100, 10 + ShotLinkRules.MAX_AGE, "hit") ~= nil, "à MAX_AGE")
			T.expectEqual(ShotLinkRules.find(ledger, 100, 10 + ShotLinkRules.MAX_AGE + 0.01, "hit"), nil)
			T.expectEqual(#ledger, 0, "retiré du registre")
			ShotLinkRules.record(ledger, 200, 50, true, false)
			T.expectEqual(ShotLinkRules.find(ledger, 200, 40, "hit"), nil, "horloge revenue en arrière")
		end)

		T.it("borne le registre à MAX_ENTRIES, le plus ancien oublié", function()
			local ledger = ShotLinkRules.new()
			for i = 1, ShotLinkRules.MAX_ENTRIES + 5 do
				ShotLinkRules.record(ledger, i, 10, true, false)
			end
			T.expectEqual(#ledger, ShotLinkRules.MAX_ENTRIES)
			T.expectEqual(ShotLinkRules.find(ledger, 1, 10, "hit"), nil, "plus ancien oublié")
			T.expect(ShotLinkRules.find(ledger, ShotLinkRules.MAX_ENTRIES + 5, 10, "hit") ~= nil, "plus récent gardé")
		end)

		T.it("instant absent, NaN ou d'un autre type : jamais rattaché", function()
			local ledger = ShotLinkRules.new()
			ShotLinkRules.record(ledger, 100, 10, true, false)
			T.expectEqual(ShotLinkRules.find(ledger, nil, 10, "hit"), nil)
			T.expectEqual(ShotLinkRules.find(ledger, 0 / 0, 10, "hit"), nil)
			T.expectEqual(ShotLinkRules.find(ledger, "100", 10, "hit"), nil)
		end)

		T.it("contrôle shotLink livré en journal seul, gravité faible", function()
			T.expectEqual(ShotRules.Check.SHOT_LINK, "shotLink")
			T.expectEqual(ShotRules.MODES.shotLink, "log")
			T.expectEqual(ShotRules.SEVERITY.shotLink, "low")
		end)
	end)
end

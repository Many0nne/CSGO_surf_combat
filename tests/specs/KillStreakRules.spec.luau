return function(T, Loader)
	local KillStreakRules = Loader.new():require("src/client/systems/game/KillStreakRules")

	-- Cette méthode permet d'enchaîner n kills sans mourir lorsqu'un test suit une série ; renvoie les annonces par kill.
	local function series(n: number, headshotAt: { [number]: boolean }?): { [number]: string | false }
		local streak, out = 0, {}
		for i = 1, n do
			local announcement
			streak, announcement = KillStreakRules.onKill(streak, headshotAt ~= nil and headshotAt[i] == true)
			out[i] = announcement or false
		end
		return out
	end

	T.describe("KillStreakRules.onKill", function()
		T.it("annonce double, triple, quadruple kill, puis Monster kill à 5", function()
			local out = series(5)
			T.expectEqual(out[1], false)
			T.expectEqual(out[2], "DoubleKill")
			T.expectEqual(out[3], "TripleKill")
			T.expectEqual(out[4], "QuadrupleKill")
			T.expectEqual(out[5], "MonsterKill")
		end)

		T.it("n'annonce chaque palier qu'une fois : rien de 6 à 9, de 11 à 14 ni après 15", function()
			local out = series(20)
			T.expectEqual(out[10], "Dominating")
			T.expectEqual(out[15], "Divine")
			for _, i in { 6, 7, 8, 9, 11, 12, 13, 14, 16, 17, 18, 19, 20 } do
				T.expectEqual(out[i], false)
			end
		end)

		T.it("annonce Headshot sur un kill à la tête hors palier", function()
			local out = series(7, { [1] = true, [7] = true })
			T.expectEqual(out[1], "Headshot")
			T.expectEqual(out[7], "Headshot")
		end)

		T.it("donne la priorité au palier sur le Headshot", function()
			local out = series(2, { [2] = true })
			T.expectEqual(out[2], "DoubleKill")
		end)

		T.it("repart de zéro après une mort (série remise à 0) : pas de triple kill", function()
			local streak = select(1, KillStreakRules.onKill(0, false))
			streak = select(1, KillStreakRules.onKill(streak, false))
			T.expectEqual(streak, 2)
			-- mort : la série revient à 0
			local _, announcement = KillStreakRules.onKill(0, false)
			T.expectEqual(announcement, nil)
		end)
	end)

	T.describe("KillStreakRules.view", function()
		T.it("masque l'indicateur à 0 et 1 kill, l'affiche dès le double kill", function()
			T.expectEqual(KillStreakRules.view(0).visible, false)
			T.expectEqual(KillStreakRules.view(1).visible, false)
			T.expectEqual(KillStreakRules.view(2).visible, true)
			T.expectEqual(KillStreakRules.view(23).visible, true)
		end)

		T.it("affiche le nombre de kills seul, sans mot", function()
			T.expectEqual(KillStreakRules.view(3).count, "3")
			T.expectEqual(KillStreakRules.view(12).count, "12")
		end)

		T.it("marque les paliers annoncés à la voix, et eux seuls", function()
			for _, n in { 2, 3, 4, 5, 10, 15 } do
				T.expectEqual(KillStreakRules.view(n).tier, true)
			end
			for _, n in { 0, 1, 6, 9, 11, 14, 16 } do
				T.expectEqual(KillStreakRules.view(n).tier, false)
			end
		end)

		T.it("garde l'os plein jusqu'à 4 kills, hachure dès 5, passe au rouge (hachuré) dès 10", function()
			for _, n in { 2, 3, 4 } do
				T.expectEqual(KillStreakRules.view(n).hatched, false)
				T.expectEqual(KillStreakRules.view(n).red, false)
			end
			for _, n in { 5, 9 } do
				T.expectEqual(KillStreakRules.view(n).hatched, true)
				T.expectEqual(KillStreakRules.view(n).red, false)
			end
			for _, n in { 10, 15, 23 } do
				T.expectEqual(KillStreakRules.view(n).hatched, true)
				T.expectEqual(KillStreakRules.view(n).red, true)
			end
		end)

		T.it("n'affiche jamais de sang (règles Roblox sur le gore)", function()
			for _, n in { 0, 2, 5, 10, 15, 30 } do
				T.expectEqual((KillStreakRules.view(n) :: any).blood, nil)
			end
			T.expectEqual((KillStreakRules :: any).BLOOD_FROM, nil)
		end)

		T.it("revient masqué après une mort (série remise à 0)", function()
			local streak = select(1, KillStreakRules.onKill(0, false))
			streak = select(1, KillStreakRules.onKill(streak, false))
			T.expectEqual(KillStreakRules.view(streak).visible, true)
			T.expectEqual(KillStreakRules.view(0).visible, false)
		end)
	end)
end

-- Départ par MENU PRINCIPAL juste après un coup reçu (#217) : mort ou départ libre.
return function(T, Loader)
	local LeaveRules = Loader.new():require("src/server/LeaveRules")
	local WINDOW = 5

	T.describe("LeaveRules.countsAsDeath", function()
		T.it("compte comme une mort un départ 4,9 s après un coup", function()
			T.expectEqual(LeaveRules.countsAsDeath(100, 104.9, WINDOW, true), true)
		end)

		T.it("laisse partir librement 5,1 s après un coup", function()
			T.expectEqual(LeaveRules.countsAsDeath(100, 105.1, WINDOW, true), false)
		end)

		T.it("laisse partir librement à 5 s pile (moins de 5 s exigées)", function()
			T.expectEqual(LeaveRules.countsAsDeath(100, 105, WINDOW, true), false)
		end)

		T.it("laisse partir librement sans coup reçu", function()
			T.expectEqual(LeaveRules.countsAsDeath(nil, 100, WINDOW, true), false)
		end)

		T.it("laisse partir librement si l'attaquant n'est plus inscrit", function()
			T.expectEqual(LeaveRules.countsAsDeath(100, 101, WINDOW, false), false)
		end)

		T.it("suit la fenêtre de GameConfig (5 s)", function()
			local GameConfig = Loader.new():require("src/shared/GameConfig")
			T.expectEqual(GameConfig.LEAVE_DEATH_WINDOW, 5)
		end)
	end)
end

return function(T, Loader)
	local MapSelection = Loader.new():require("src/shared/MapSelection")

	T.describe("MapSelection.resolve", function()
		T.it("garde la map demandée si elle existe", function()
			T.expectEqual(MapSelection.resolve({ "Autre", "Dizzy" }, "Autre"), "Autre")
		end)

		T.it("se replie sur Dizzy quand la map demandée manque", function()
			T.expectEqual(MapSelection.resolve({ "Autre", "Dizzy" }, "Inconnue"), "Dizzy")
			T.expectEqual(MapSelection.resolve({ "Dizzy" }, nil), "Dizzy")
		end)

		T.it("prend la première par ordre alphabétique sans Dizzy, nil sans map", function()
			T.expectEqual(MapSelection.resolve({ "Zeta", "Beta" }, "Inconnue"), "Beta")
			T.expectEqual(MapSelection.resolve({}, "Dizzy"), nil)
		end)
	end)
end

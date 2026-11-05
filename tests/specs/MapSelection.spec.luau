return function(T, Loader)
	local MapSelection = Loader.new():require("src/shared/MapSelection")

	T.describe("MapSelection.resolve", function()
		T.it("garde la map demandée si elle existe", function()
			T.expectEqual(MapSelection.resolve({ "Map", "Dizzy" }, "Dizzy"), "Dizzy")
		end)

		T.it("se replie sur l'Arène quand la map demandée manque", function()
			T.expectEqual(MapSelection.resolve({ "Dizzy", "Map" }, "Inconnue"), "Map")
			T.expectEqual(MapSelection.resolve({ "Map" }, nil), "Map")
		end)

		T.it("prend la première par ordre alphabétique sans Arène, nil sans map", function()
			T.expectEqual(MapSelection.resolve({ "Zeta", "Dizzy" }, "Inconnue"), "Dizzy")
			T.expectEqual(MapSelection.resolve({}, "Dizzy"), nil)
		end)
	end)
end

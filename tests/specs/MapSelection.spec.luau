return function(T, Loader)
	local MapSelection = Loader.new({ ReplicatedStorage = {} }):require("src/shared/MapSelection")

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

	T.describe("MapSelection.nextInRotation", function()
		local rotation = { "Dizzy", "Radoub" }

		T.it("alterne les maps de la rotation, retour au début en fin de liste", function()
			T.expectEqual(MapSelection.nextInRotation(rotation, { "Radoub", "Dizzy" }, "Dizzy", nil), "Radoub")
			T.expectEqual(MapSelection.nextInRotation(rotation, { "Radoub", "Dizzy" }, "Radoub", nil), "Dizzy")
		end)

		T.it("garde la map forcée si elle existe, l'ignore sinon", function()
			T.expectEqual(MapSelection.nextInRotation(rotation, { "Radoub", "Dizzy" }, "Dizzy", "Dizzy"), "Dizzy")
			T.expectEqual(MapSelection.nextInRotation(rotation, { "Radoub", "Dizzy" }, "Dizzy", "Absente"), "Radoub")
		end)

		T.it("saute les maps absentes et reste sur la seule map présente", function()
			T.expectEqual(MapSelection.nextInRotation({ "A", "B", "C" }, { "A", "C" }, "A", nil), "C")
			T.expectEqual(MapSelection.nextInRotation(rotation, { "Dizzy" }, "Dizzy", nil), "Dizzy")
		end)

		T.it("ajoute en fin de tour les maps présentes hors rotation, par ordre alphabétique", function()
			T.expectEqual(
				MapSelection.nextInRotation(rotation, { "Dizzy", "Radoub", "Zinc", "Atoll" }, "Radoub"),
				"Atoll"
			)
			T.expectEqual(
				MapSelection.nextInRotation(rotation, { "Dizzy", "Radoub", "Zinc", "Atoll" }, "Zinc"),
				"Dizzy"
			)
		end)

		T.it("part de la première map sans map jouée connue, nil sans map", function()
			T.expectEqual(MapSelection.nextInRotation(rotation, { "Radoub", "Dizzy" }, nil, nil), "Dizzy")
			T.expectEqual(MapSelection.nextInRotation(rotation, {}, "Dizzy", nil), nil)
		end)
	end)

	T.describe("MapSelection.forced", function()
		T.it("ne force une map que dans Studio, avec un nom non vide", function()
			T.expectEqual(MapSelection.forced(true, "Radoub"), "Radoub")
			T.expectEqual(MapSelection.forced(false, "Radoub"), nil)
			T.expectEqual(MapSelection.forced(true, ""), nil)
			T.expectEqual(MapSelection.forced(true, 3), nil)
		end)
	end)
end

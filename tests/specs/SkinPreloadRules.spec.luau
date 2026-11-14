-- Règles pures du préchargement des skins (#333, #342) : skins à demander d'après les attributs d'un joueur, bornes,
-- dédoublonnage des cartes.
return function(T, Loader)
	local Rules = Loader.new({}):require("src/client/systems/inventory/SkinPreloadRules")

	-- Le viewmodel d'un Tool porte son nom, sauf le KaBar qui réutilise celui de la M9 (arbitraire, pour le test)
	local function viewmodelOf(toolName: string): string
		return if toolName == "KaBar" then "M9Bayonet" else toolName
	end

	local OWNED = "weapon.awp,weapon.kabar,weapon.m9bayonet,skin.awp.strate,skin.awp.sillage,skin.m9bayonet.strate"

	T.describe("SkinPreloadRules.skinsOf", function()
		T.it("liste le skin de chaque emplacement équipé", function()
			local list =
				Rules.skinsOf(OWNED, "weapon.awp:skin.awp.strate,weapon.m9bayonet:skin.m9bayonet.strate", viewmodelOf)
			T.expectEqual(#list, 2)
			T.expectEqual(list[1].viewmodel, "AWP")
			T.expectEqual(list[1].skin, "skin.awp.strate")
			T.expectEqual(list[2].viewmodel, "M9Bayonet")
			T.expectEqual(list[2].skin, "skin.m9bayonet.strate")
		end)

		T.it("ne demande rien pour des armes d'origine ou un attribut absent", function()
			T.expectEqual(#Rules.skinsOf(OWNED, "weapon.awp,weapon.kabar", viewmodelOf), 0)
			T.expectEqual(#Rules.skinsOf(nil, nil, viewmodelOf), 0)
			T.expectEqual(#Rules.skinsOf(OWNED, 42, viewmodelOf), 0)
		end)

		T.it("ignore un skin non possédé ou d'une autre arme", function()
			T.expectEqual(#Rules.skinsOf(OWNED, "weapon.awp:skin.awp.impact", viewmodelOf), 0)
			T.expectEqual(#Rules.skinsOf(OWNED, "weapon.awp:skin.m9bayonet.strate", viewmodelOf), 0)
		end)

		T.it("ne dépasse jamais un skin par emplacement, même avec un attribut trop long", function()
			local text = "weapon.awp:skin.awp.strate,weapon.m9bayonet:skin.m9bayonet.strate,weapon.awp:skin.awp.sillage"
			local list = Rules.skinsOf(OWNED, text, viewmodelOf)
			T.expectEqual(#list, 2)
			T.expectEqual(list[1].skin, "skin.awp.strate")
		end)

		T.it("ne demande pas le skin d'une arme sans skin équipé", function()
			local list = Rules.skinsOf(OWNED, "weapon.awp:skin.awp.strate,weapon.kabar", viewmodelOf)
			T.expectEqual(#list, 1)
		end)
	end)

	T.describe("SkinPreloadRules.fresh", function()
		T.it("renvoie les nouvelles cartes et les marque demandées", function()
			local requested = {}
			local list = Rules.fresh({ "a", "b", "a" }, requested)
			T.expectEqual(#list, 2)
			T.expect(requested.a and requested.b, "cartes marquées")
		end)

		T.it("ne redemande pas une carte déjà demandée, par ce joueur ou un autre", function()
			local requested = { a = true }
			local list = Rules.fresh({ "a", "c" }, requested)
			T.expectEqual(#list, 1)
			T.expectEqual(list[1], "c")
			T.expectEqual(#Rules.fresh({ "a", "c" }, requested), 0)
		end)
	end)
end

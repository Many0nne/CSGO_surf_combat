-- Préchargement des skins (#333) : WeaponSkins.mapUris liste sans doublon les cartes d'un dossier de skin.
return function(T, Loader)
	T.describe("WeaponSkins.mapUris", function()
		local WeaponSkins = Loader.new({}):require("src/shared/WeaponSkins")

		-- Cette méthode permet de simuler une SurfaceAppearance (ou un autre enfant) lorsqu'un test construit un dossier
		-- de skin ; `maps` donne l'id de chaque carte (Content simulé par une table à champ Uri).
		local function child(className, maps)
			local c = { ClassName = className }
			for property, uri in maps or {} do
				c[property] = { Uri = uri }
			end
			-- Cette méthode permet de répondre au test de classe lorsque le module trie les enfants.
			function c.IsA(self, name)
				return self.ClassName == name
			end
			return c
		end

		-- Cette méthode permet de simuler un dossier de skin lorsqu'un test fixe ses enfants.
		local function folder(children)
			return {
				-- Cette méthode permet de lister les enfants lorsque le module parcourt le dossier.
				GetChildren = function()
					return children
				end,
			}
		end

		T.it("liste les quatre cartes de chaque pièce, sans doublon entre pièces", function()
			local barrel = child("SurfaceAppearance", {
				ColorMapContent = "rbxassetid://1",
				MetalnessMapContent = "rbxassetid://2",
				NormalMapContent = "rbxassetid://3",
				RoughnessMapContent = "rbxassetid://4",
			})
			-- Fittings reprend les cartes de Barrel (cas réel de l'AWP), Bolt en a une à lui
			local fittings = child("SurfaceAppearance", {
				ColorMapContent = "rbxassetid://1",
				MetalnessMapContent = "rbxassetid://2",
				NormalMapContent = "rbxassetid://3",
				RoughnessMapContent = "rbxassetid://4",
			})
			local bolt = child("SurfaceAppearance", { ColorMapContent = "rbxassetid://5" })
			local uris = WeaponSkins.mapUris(folder({ barrel, fittings, bolt }))
			T.expectEqual(
				table.concat(uris, ","),
				"rbxassetid://1,rbxassetid://2,rbxassetid://3,rbxassetid://4,rbxassetid://5"
			)
		end)

		T.it("ignore les cartes vides et les enfants qui ne sont pas des SurfaceAppearance", function()
			local partial = child("SurfaceAppearance", { ColorMapContent = "rbxassetid://7", NormalMapContent = "" })
			local other = child("Folder", { ColorMapContent = "rbxassetid://8" })
			local uris = WeaponSkins.mapUris(folder({ partial, other }))
			T.expectEqual(table.concat(uris, ","), "rbxassetid://7")
		end)
	end)
end

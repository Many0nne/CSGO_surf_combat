-- Règles pures de l'inventaire (#267) : catalogue et format des items, inventaire par défaut, admin, données
-- sauvegardées assainies, repli si le DataStore est indisponible, synchronisation du sac, attribut informatif.
return function(T, Loader)
	local Rules = Loader.new({}):require("src/shared/InventoryRules")

	-- Cette méthode permet de lister les ids d'un ensemble possédé, triés, lorsqu'un test compare un inventaire.
	local function ids(owned): { string }
		local list = {}
		for id, isOwned in owned do
			if isOwned then
				table.insert(list, id)
			end
		end
		table.sort(list)
		return list
	end

	T.describe("InventoryRules : catalogue", function()
		T.it("chaque item a un id stable valide, unique, et un type connu", function()
			local seen = {}
			for _, entry in Rules.ITEMS do
				T.expect(Rules.isValidId(entry.id), "id valide : " .. tostring(entry.id))
				T.expect(not seen[entry.id], "id unique : " .. entry.id)
				seen[entry.id] = true
				T.expect(entry.type == Rules.Type.WEAPON or entry.type == Rules.Type.SKIN, "type de " .. entry.id)
				if entry.type == Rules.Type.WEAPON then
					T.expect(type(entry.tool) == "string" and entry.tool ~= "", "arme avec son Tool : " .. entry.id)
				else
					local weapon = entry.weapon and Rules.item(entry.weapon)
					T.expect(
						weapon ~= nil and weapon.type == Rules.Type.WEAPON,
						"skin rattaché à une arme : " .. entry.id
					)
				end
			end
		end)

		T.it("l'inventaire par défaut ne nomme que des items du catalogue", function()
			for _, id in Rules.DEFAULT_ITEMS do
				T.expect(Rules.item(id) ~= nil, "item par défaut connu : " .. id)
			end
		end)

		T.it("rejette les ids mal formés", function()
			T.expect(not Rules.isValidId(""), "vide")
			T.expect(not Rules.isValidId("Weapon.AWP"), "majuscules")
			T.expect(not Rules.isValidId("weapon,awp"), "virgule (séparateur de l'attribut)")
			T.expect(not Rules.isValidId(".awp"), "point en tête")
			T.expect(not Rules.isValidId(42), "nombre")
			T.expect(not Rules.isValidId(string.rep("a", Rules.MAX_ID_LENGTH + 1)), "trop long")
			T.expect(Rules.isValidId("skin.awp.dragon_lore"), "id de skin futur")
		end)
	end)

	T.describe("InventoryRules : items possédés", function()
		T.it("joueur normal et bot : Ka-Bar et AWP", function()
			local owned = Rules.resolve(nil, false)
			T.expectEqual(table.concat(ids(owned), ","), "weapon.awp,weapon.kabar")
			T.expectEqual(table.concat(Rules.ownedTools(owned), ","), "AWP,KaBar")
			T.expect(not Rules.ownsTool(owned, "M9Bayonet"), "pas de M9 Bayonet")
		end)

		T.it("admin : tous les items du catalogue", function()
			local owned = Rules.resolve(nil, true)
			T.expectEqual(#ids(owned), #Rules.ITEMS)
			T.expect(Rules.ownsTool(owned, "M9Bayonet"), "M9 Bayonet")
			T.expectEqual(table.concat(Rules.ownedTools(owned), ","), "AWP,KaBar,M9Bayonet")
		end)

		T.it("ajoute les items sauvegardés connus, ignore les inconnus", function()
			local owned = Rules.resolve({ "weapon.m9bayonet", "skin.awp.futur" }, false)
			T.expect(owned["weapon.m9bayonet"] == true, "M9 sauvegardée")
			T.expect(owned["skin.awp.futur"] == nil, "id inconnu sans effet")
			T.expect(owned["weapon.awp"] == true, "défaut toujours là")
		end)

		T.it("un Tool hors catalogue n'est jamais possédé", function()
			T.expect(not Rules.ownsTool(Rules.resolve(nil, true), "Pistolet"), "admin compris")
		end)
	end)

	T.describe("InventoryRules : chargement et sauvegarde", function()
		T.it("lecture en échec : inventaire par défaut, sauvegarde coupée", function()
			local stored, canSave = Rules.loadOutcome(false, nil)
			T.expectEqual(#stored, 0)
			T.expectEqual(canSave, false)
			T.expectEqual(table.concat(ids(Rules.resolve(stored, false)), ","), "weapon.awp,weapon.kabar")
		end)

		T.it("nouveau joueur (aucune donnée) : rien de sauvegardé, écriture permise", function()
			local stored, canSave = Rules.loadOutcome(true, nil)
			T.expectEqual(#stored, 0)
			T.expectEqual(canSave, true)
		end)

		T.it("données relues assainies : ids valides, sans doublon, triés, inconnus gardés", function()
			local stored, canSave = Rules.loadOutcome(true, {
				schemaVersion = 1,
				items = { "weapon.m9bayonet", "skin.awp.futur", "weapon.m9bayonet", 12, "Bad Id", {} },
			})
			T.expectEqual(canSave, true)
			T.expectEqual(table.concat(stored, ","), "skin.awp.futur,weapon.m9bayonet")
		end)

		T.it("données d'une forme inattendue : liste vide", function()
			T.expectEqual(#Rules.sanitizeStored("weapon.awp"), 0)
			T.expectEqual(#(Rules.loadOutcome(true, { items = "weapon.awp" })), 0)
			T.expectEqual(#(Rules.loadOutcome(true, "texte")), 0)
		end)

		T.it("borne le nombre d'ids relus", function()
			local raw = {}
			for i = 1, Rules.MAX_STORED + 10 do
				table.insert(raw, "skin.x" .. i)
			end
			T.expectEqual(#Rules.sanitizeStored(raw), Rules.MAX_STORED)
		end)

		T.it("la valeur sauvegardée porte la version du schéma et une copie des ids", function()
			local stored = { "weapon.m9bayonet" }
			local payload = Rules.payload(stored)
			T.expectEqual(payload.schemaVersion, Rules.SCHEMA_VERSION)
			T.expectEqual(payload.items[1], "weapon.m9bayonet")
			T.expect(payload.items ~= stored, "copie")
		end)

		T.it("grant : ajoute un item connu une seule fois", function()
			local stored, changed = Rules.grant({}, "weapon.m9bayonet")
			T.expectEqual(changed, true)
			T.expectEqual(table.concat(stored, ","), "weapon.m9bayonet")
			local _, again = Rules.grant(stored, "weapon.m9bayonet")
			T.expectEqual(again, false)
			local _, unknown = Rules.grant(stored, "weapon.inconnue")
			T.expectEqual(unknown, false)
		end)
	end)

	T.describe("InventoryRules : sac et attribut", function()
		T.it("donne les Tools possédés absents et retire ceux non possédés", function()
			local give, remove = Rules.toolChanges(Rules.resolve(nil, false), { "AWP", "M9Bayonet", "Inconnu" })
			T.expectEqual(table.concat(give, ","), "KaBar")
			T.expectEqual(table.concat(remove, ","), "M9Bayonet,Inconnu")
		end)

		T.it("sac vide d'un admin : toutes les armes", function()
			local give, remove = Rules.toolChanges(Rules.resolve(nil, true), {})
			T.expectEqual(table.concat(give, ","), "AWP,KaBar,M9Bayonet")
			T.expectEqual(#remove, 0)
		end)

		T.it("attribut : aller-retour, ids inconnus ignorés, défaut sans attribut", function()
			local owned = Rules.resolve(nil, true)
			local text = Rules.encode(owned)
			T.expectEqual(text, "weapon.awp,weapon.kabar,weapon.m9bayonet")
			T.expectEqual(table.concat(ids(Rules.decode(text)), ","), text)
			T.expectEqual(table.concat(ids(Rules.decode("weapon.awp,inconnu")), ","), "weapon.awp")
			T.expectEqual(table.concat(ids(Rules.decode(nil)), ","), "weapon.awp,weapon.kabar")
			T.expectEqual(#ids(Rules.decode("")), 0)
		end)
	end)
end

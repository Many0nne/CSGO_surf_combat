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

		T.it("données d'une forme inattendue : liste vide, sauvegarde coupée pour ne pas les écraser", function()
			T.expectEqual(#Rules.sanitizeStored("weapon.awp"), 0)
			local stored, canSave = Rules.loadOutcome(true, { items = "weapon.awp" })
			T.expectEqual(#stored, 0)
			T.expectEqual(canSave, false)
			stored, canSave = Rules.loadOutcome(true, "texte")
			T.expectEqual(#stored, 0)
			T.expectEqual(canSave, false)
		end)

		T.it("données d'une version plus récente : ids lisibles gardés, sauvegarde coupée", function()
			local stored, canSave =
				Rules.loadOutcome(true, { schemaVersion = Rules.SCHEMA_VERSION + 1, items = { "weapon.m9bayonet" } })
			T.expectEqual(table.concat(stored, ","), "weapon.m9bayonet")
			T.expectEqual(canSave, false)
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

		T.it("sauvegarde : réunit les ids déjà enregistrés et ceux de la session", function()
			local written = Rules.mergeForSave(
				{ schemaVersion = 1, items = { "weapon.m9bayonet", "skin.awp.futur" } },
				{ "weapon.kabar" }
			)
			T.expect(written ~= nil, "écriture")
			T.expectEqual(written.schemaVersion, Rules.SCHEMA_VERSION)
			T.expectEqual(table.concat(written.items, ","), "skin.awp.futur,weapon.kabar,weapon.m9bayonet")
		end)

		T.it("sauvegarde : une session en retard n'efface pas un item enregistré entre-temps", function()
			-- Sauvegarde de la session A ({}) arrivée après celle de B qui a écrit la M9
			local written = Rules.mergeForSave({ schemaVersion = 1, items = { "weapon.m9bayonet" } }, {})
			T.expectEqual(table.concat(written.items, ","), "weapon.m9bayonet")
		end)

		T.it("sauvegarde : aucun plafond, les ids enregistrés au-delà de MAX_STORED sont gardés", function()
			local old = {}
			for i = 1, Rules.MAX_STORED + 20 do
				table.insert(old, string.format("skin.x%04d", i))
			end
			local written = Rules.mergeForSave({ schemaVersion = 1, items = old }, { "weapon.m9bayonet" })
			T.expectEqual(#written.items, Rules.MAX_STORED + 21)
			T.expect(table.find(written.items, "weapon.m9bayonet") ~= nil, "nouvel id écrit")
		end)

		T.it("sauvegarde : premier enregistrement, et annulée sur un format inconnu ou plus récent", function()
			T.expectEqual(table.concat(Rules.mergeForSave(nil, { "weapon.kabar" }).items, ","), "weapon.kabar")
			T.expectEqual(Rules.mergeForSave({ schemaVersion = Rules.SCHEMA_VERSION + 1, items = {} }, {}), nil)
			T.expectEqual(Rules.mergeForSave("texte", { "weapon.kabar" }), nil)
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
		T.it("donne les Tools équipés absents et retire tous les autres", function()
			local wanted = Rules.equippedTools(Rules.resolveEquipped(nil, Rules.resolve(nil, false)))
			local give, remove = Rules.toolChanges(wanted, { "AWP", "M9Bayonet", "Inconnu" })
			T.expectEqual(table.concat(give, ","), "KaBar")
			T.expectEqual(table.concat(remove, ","), "M9Bayonet,Inconnu")
		end)

		T.it("sac d'un admin : un sniper et un seul couteau (#280), pas tout le catalogue", function()
			local owned = Rules.resolve(nil, true)
			local wanted = Rules.equippedTools(Rules.resolveEquipped(nil, owned))
			local give, remove = Rules.toolChanges(wanted, { "AWP", "KaBar", "M9Bayonet" })
			T.expectEqual(#give, 0)
			T.expectEqual(table.concat(remove, ","), "M9Bayonet")
			local equipped = Rules.equip({}, owned, "knife", "weapon.m9bayonet", nil)
			T.expectEqual(
				table.concat(Rules.equippedTools(Rules.resolveEquipped(equipped, owned)), ","),
				"AWP,M9Bayonet"
			)
		end)

		T.it("attribut : aller-retour, ids inconnus ignorés, défaut sans attribut", function()
			local owned = Rules.resolve(nil, true)
			local text = Rules.encode(owned)
			T.expectEqual(text, "weapon.awp,weapon.kabar,weapon.m9bayonet")
			T.expectEqual(table.concat(ids(Rules.decode(text)), ","), text)
			T.expectEqual(table.concat(ids(Rules.decode("weapon.m9bayonet,inconnu")), ","), text)
			T.expectEqual(table.concat(ids(Rules.decode(nil)), ","), "weapon.awp,weapon.kabar")
			T.expectEqual(
				table.concat(ids(Rules.decode("")), ","),
				"weapon.awp,weapon.kabar",
				"défaut toujours possédé"
			)
		end)
	end)

	T.describe("InventoryRules : équipement (#280)", function()
		-- Cette méthode permet de charger un exemplaire à part du module dont le catalogue compte deux skins de test
		-- lorsque l'étape skin doit être éprouvée (aucun skin n'existe avant #268) ; `Rules` reste intact.
		local function withSkins()
			local skinned = Loader.new({}):require("src/shared/InventoryRules")
			table.insert(skinned.ITEMS, { id = "skin.awp.test", type = "skin", weapon = "weapon.awp" })
			table.insert(skinned.ITEMS, { id = "skin.kabar.test", type = "skin", weapon = "weapon.kabar" })
			skinned.reindex()
			return skinned
		end

		T.it(
			"chaque arme a un emplacement connu, chaque emplacement une arme par défaut possédée de cet emplacement",
			function()
				for _, entry in Rules.ITEMS do
					if entry.type == Rules.Type.WEAPON then
						T.expect(Rules.slotIndex(entry.slot) ~= nil, "emplacement de " .. entry.id)
					end
				end
				local owned = Rules.resolve(nil, false)
				for _, slot in Rules.SLOTS do
					local id = Rules.DEFAULT_EQUIPPED[slot]
					local item = id and Rules.item(id)
					T.expect(item ~= nil and item.slot == slot, "défaut de " .. slot)
					T.expect(owned[id] == true, "défaut possédé : " .. slot)
				end
			end
		)

		T.it("ordre des emplacements : 1 · SNIPER, 2 · COUTEAU", function()
			T.expectEqual(Rules.slotIndex("sniper"), 1)
			T.expectEqual(Rules.slotIndex("knife"), 2)
			T.expectEqual(Rules.slotIndex("pistol"), nil)
			T.expectEqual(Rules.slotOfTool("M9Bayonet"), "knife")
			T.expectEqual(Rules.slotOfTool("Inconnu"), nil)
		end)

		T.it("rien de choisi : équipement par défaut (AWP, Ka-Bar, d'origine)", function()
			local resolved = Rules.resolveEquipped(nil, Rules.resolve(nil, true))
			T.expectEqual(resolved.sniper.weapon, "weapon.awp")
			T.expectEqual(resolved.knife.weapon, "weapon.kabar")
			T.expectEqual(resolved.knife.skin, nil)
		end)

		T.it("liste d'un emplacement : seules les armes possédées de cet emplacement", function()
			local function tools(list)
				local names = {}
				for _, item in list do
					table.insert(names, item.tool)
				end
				return table.concat(names, ",")
			end
			T.expectEqual(tools(Rules.weaponsForSlot(Rules.resolve(nil, false), "knife")), "KaBar")
			T.expectEqual(tools(Rules.weaponsForSlot(Rules.resolve(nil, true), "knife")), "KaBar,M9Bayonet")
			T.expectEqual(tools(Rules.weaponsForSlot(Rules.resolve(nil, true), "sniper")), "AWP")
			T.expectEqual(#Rules.skinsFor(Rules.resolve(nil, true), "weapon.awp"), 0)
		end)

		T.it("équipe une arme possédée de l'emplacement, sans toucher à l'autre emplacement", function()
			local owned = Rules.resolve({ "weapon.m9bayonet" }, false)
			local before = { sniper = { weapon = "weapon.awp" } }
			local equipped, reason = Rules.equip(before, owned, "knife", "weapon.m9bayonet", nil)
			T.expectEqual(reason, nil)
			assert(equipped)
			T.expectEqual(equipped.knife.weapon, "weapon.m9bayonet")
			T.expectEqual(equipped.sniper.weapon, "weapon.awp")
			T.expect(before.knife == nil, "copie : l'équipement reçu n'est pas modifié")
		end)

		T.it(
			"refuse un item non possédé, une arme d'un autre emplacement, un id inconnu ou un emplacement inconnu",
			function()
				local owned = Rules.resolve(nil, false)
				local _, notOwned = Rules.equip({}, owned, "knife", "weapon.m9bayonet", nil)
				T.expectEqual(notOwned, "not_owned")
				local _, wrongSlot = Rules.equip({}, owned, "sniper", "weapon.kabar", nil)
				T.expectEqual(wrongSlot, "wrong_slot")
				local _, unknown = Rules.equip({}, owned, "knife", "weapon.inconnue", nil)
				T.expectEqual(unknown, "unknown")
				local _, badSlot = Rules.equip({}, owned, "pistol", "weapon.awp", nil)
				T.expectEqual(badSlot, "slot")
				local _, notString = Rules.equip({}, owned, "sniper", 42, nil)
				T.expectEqual(notString, "unknown")
			end
		)

		T.it(
			"refuse le skin d'une autre arme, un skin non possédé, et accepte un skin possédé de l'arme",
			function()
				local R = withSkins()
				T.expect(Rules.item("skin.awp.test") == nil, "catalogue du module partagé intact")
				local owned = R.resolve({ "skin.awp.test", "skin.kabar.test" }, false)
				local _, wrongSkin = R.equip({}, owned, "sniper", "weapon.awp", "skin.kabar.test")
				T.expectEqual(wrongSkin, "wrong_skin")
				local _, notOwned = R.equip({}, R.resolve(nil, false), "sniper", "weapon.awp", "skin.awp.test")
				T.expectEqual(notOwned, "not_owned")
				local _, unknownSkin = R.equip({}, owned, "sniper", "weapon.awp", "skin.awp.inconnu")
				T.expectEqual(unknownSkin, "wrong_skin")
				local equipped = assert(R.equip({}, owned, "sniper", "weapon.awp", "skin.awp.test"))
				T.expectEqual(equipped.sniper.skin, "skin.awp.test")
				T.expectEqual(#R.skinsFor(owned, "weapon.awp"), 1)
				-- Skin perdu : l'arme reste, le skin revient d'origine
				local resolved = R.resolveEquipped(equipped, R.resolve(nil, false))
				T.expectEqual(resolved.sniper.weapon, "weapon.awp")
				T.expectEqual(resolved.sniper.skin, nil)
				T.expectEqual(R.resolveEquipped(equipped, owned).sniper.skin, "skin.awp.test")
			end
		)

		T.it("un choix qui n'est plus possédé laisse la place au défaut, sans être effacé", function()
			local admin = Rules.resolve(nil, true)
			local equipped = assert(Rules.equip({}, admin, "knife", "weapon.m9bayonet", nil))
			-- Rôle admin retiré : la M9 n'est plus possédée
			local resolved = Rules.resolveEquipped(equipped, Rules.resolve(nil, false))
			T.expectEqual(resolved.knife.weapon, "weapon.kabar")
			T.expectEqual(equipped.knife.weapon, "weapon.m9bayonet", "choix enregistré gardé")
			-- Rôle rendu : le choix revient
			T.expectEqual(Rules.resolveEquipped(equipped, admin).knife.weapon, "weapon.m9bayonet")
		end)

		T.it(
			"un choix enregistré incohérent (arme dans le mauvais emplacement, skin étranger) est ramené au défaut",
			function()
				local owned = Rules.resolve(nil, true)
				local resolved = Rules.resolveEquipped({
					sniper = { weapon = "weapon.kabar" },
					knife = { weapon = "weapon.m9bayonet", skin = "skin.awp.inconnu" },
				}, owned)
				T.expectEqual(resolved.sniper.weapon, "weapon.awp")
				T.expectEqual(resolved.knife.weapon, "weapon.m9bayonet")
				T.expectEqual(resolved.knife.skin, nil, "skin inconnu : d'origine")
			end
		)

		T.it("assainit l'équipement relu : formes inattendues ignorées", function()
			local equipped = Rules.sanitizeEquipped({
				sniper = { weapon = "weapon.awp", skin = 12 },
				knife = "weapon.kabar",
				pistol = { weapon = "weapon.awp" },
			})
			T.expectEqual(equipped.sniper.weapon, "weapon.awp")
			T.expectEqual(equipped.sniper.skin, nil)
			T.expectEqual(equipped.knife, nil)
			T.expectEqual(equipped.pistol, nil)
			T.expectEqual(next(Rules.sanitizeEquipped("texte")), nil)
		end)

		T.it("chargement : l'équipement enregistré est relu, absent pour un nouveau joueur", function()
			local _, canSave, equipped = Rules.loadOutcome(true, {
				schemaVersion = 1,
				items = { "weapon.m9bayonet" },
				equipped = { knife = { weapon = "weapon.m9bayonet" } },
			})
			T.expectEqual(canSave, true)
			T.expectEqual(equipped.knife.weapon, "weapon.m9bayonet")
			local _, _, fresh = Rules.loadOutcome(true, nil)
			T.expectEqual(next(fresh), nil)
			local _, failedSave, failed = Rules.loadOutcome(false, nil)
			T.expectEqual(failedSave, false)
			T.expectEqual(next(failed), nil)
		end)

		T.it("chargement : un `equipped` d'une forme inconnue coupe la sauvegarde", function()
			local _, canSave = Rules.loadOutcome(true, { schemaVersion = 1, items = {}, equipped = "knife" })
			T.expectEqual(canSave, false)
			T.expectEqual(Rules.mergeForSave({ schemaVersion = 1, equipped = "knife" }, {}, nil), nil)
		end)

		T.it("sauvegarde : écrit l'équipement de la session, sinon garde celui déjà enregistré", function()
			local old = { schemaVersion = 1, items = {}, equipped = { knife = { weapon = "weapon.m9bayonet" } } }
			local kept = Rules.mergeForSave(old, {}, nil)
			assert(kept and kept.equipped)
			T.expectEqual(kept.equipped.knife.weapon, "weapon.m9bayonet")
			local replaced = Rules.mergeForSave(old, {}, { knife = { weapon = "weapon.kabar" } })
			assert(replaced and replaced.equipped)
			T.expectEqual(replaced.equipped.knife.weapon, "weapon.kabar")
			-- Emplacement d'une version plus récente (même schéma) : recopié, pas effacé
			local future = Rules.mergeForSave(
				{ schemaVersion = 1, equipped = { pistol = { weapon = "weapon.deagle" } } },
				{},
				{ knife = { weapon = "weapon.kabar" } }
			)
			assert(future and future.equipped)
			T.expectEqual(future.equipped.pistol.weapon, "weapon.deagle")
			T.expectEqual(future.equipped.knife.weapon, "weapon.kabar")
			-- Session qui n'a choisi que le sniper : le couteau écrit par un autre serveur reste
			local partial = Rules.mergeForSave(old, {}, { sniper = { weapon = "weapon.awp" } })
			assert(partial and partial.equipped)
			T.expectEqual(partial.equipped.sniper.weapon, "weapon.awp")
			T.expectEqual(partial.equipped.knife.weapon, "weapon.m9bayonet")
			local none = Rules.mergeForSave(nil, { "weapon.kabar" }, nil)
			assert(none)
			T.expectEqual(none.equipped, nil, "rien de choisi : pas de clé `equipped`")
		end)

		T.it("attribut : aller-retour, repli sur le défaut pour un item non possédé ou un texte absent", function()
			local admin = Rules.resolve(nil, true)
			local resolved = Rules.resolveEquipped({ knife = { weapon = "weapon.m9bayonet" } }, admin)
			local text = Rules.encodeEquipped(resolved)
			T.expectEqual(text, "weapon.awp,weapon.m9bayonet")
			T.expectEqual(Rules.decodeEquipped(text, admin).knife.weapon, "weapon.m9bayonet")
			T.expectEqual(Rules.decodeEquipped(text, Rules.resolve(nil, false)).knife.weapon, "weapon.kabar")
			T.expectEqual(Rules.decodeEquipped(nil, admin).sniper.weapon, "weapon.awp")
			T.expectEqual(
				Rules.encodeEquipped({ sniper = { weapon = "weapon.awp", skin = "skin.awp.x" } }),
				"weapon.awp:skin.awp.x,"
			)
		end)
	end)
end

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

		T.it("chaque skin a un nom affiché et des SurfaceAppearance pour Rojo (#268)", function()
			local fs = require("@lune/fs")
			for _, entry in Rules.ITEMS do
				if entry.type == Rules.Type.SKIN then
					T.expect(type(entry.name) == "string" and entry.name ~= "", "nom du skin " .. entry.id)
					T.expect(type(entry.appearance) == "string" and entry.appearance ~= "", "apparence " .. entry.id)
					-- Le viewmodel des armes à skins porte le nom de leur Tool (attribut ViewmodelName des Tools)
					local weapon = Rules.item(entry.weapon :: string)
					local path =
						string.format("assets/rbx/Skins/%s/%s.model.json", weapon and weapon.tool, entry.appearance)
					T.expect(fs.isFile(path), "fichier de SurfaceAppearance " .. path)
				end
			end
		end)

		T.it("aucun skin n'est dans l'inventaire par défaut : ils viendront des caisses (#268)", function()
			for _, id in Rules.DEFAULT_ITEMS do
				local item = Rules.item(id)
				T.expect(item ~= nil and item.type ~= Rules.Type.SKIN, "item par défaut hors skin : " .. id)
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
			local owned = Rules.resolve({ "weapon.m9bayonet" }, false)
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
			T.expectEqual(Rules.slotIndex(1), nil, "valeur non textuelle")
			T.expectEqual(Rules.slotIndex(nil), nil)
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
			-- Skins (#268, #337, #417, #433, #436, communs ÉPURE, TARTAN, BANCHE) : l'admin a tous ceux de l'AWP, un
			-- joueur sans sauvegarde aucun
			T.expectEqual(#Rules.skinsFor(Rules.resolve(nil, true), "weapon.awp"), 13)
			T.expectEqual(#Rules.skinsFor(Rules.resolve(nil, false), "weapon.awp"), 0)
			-- M9 (#268, #337, #420, #433, #436, communs LEURRE, CHANTIER, TOPO, CÉRAMIQUE #476, rare GUILLOCHÉ)
			T.expectEqual(#Rules.skinsFor(Rules.resolve(nil, true), "weapon.m9bayonet"), 13)
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
			-- Attribut malformé (vide, séparateurs seuls, emplacements en trop, nombre) : défaut, sans erreur
			for _, bad in { "", ",", ":", ",weapon.m9bayonet,weapon.awp,x", "weapon.kabar,weapon.awp", 42 } do
				local decoded = Rules.decodeEquipped(bad, admin)
				T.expectEqual(decoded.sniper.weapon, "weapon.awp", "sniper : " .. tostring(bad))
			end
			T.expectEqual(Rules.decodeEquipped(",weapon.m9bayonet", admin).knife.weapon, "weapon.m9bayonet")
			T.expectEqual(
				Rules.encodeEquipped({ sniper = { weapon = "weapon.awp", skin = "skin.awp.x" } }),
				"weapon.awp:skin.awp.x,"
			)
		end)
	end)

	T.describe("InventoryRules.skinOfTool (#268)", function()
		T.it("donne le skin équipé de l'arme d'un Tool, nil pour d'origine ou une arme hors équipement", function()
			local resolved = {
				sniper = { weapon = "weapon.awp", skin = "skin.awp.balise" },
				knife = { weapon = "weapon.kabar" },
			}
			T.expectEqual(Rules.skinOfTool(resolved, "AWP"), "skin.awp.balise")
			T.expectEqual(Rules.skinOfTool(resolved, "KaBar"), nil)
			T.expectEqual(Rules.skinOfTool(resolved, "M9Bayonet"), nil)
			T.expectEqual(Rules.skinOfTool(resolved, "Inconnu"), nil)
		end)
	end)

	T.describe("InventoryRules : portefeuille et transactions (#396)", function()
		local Wallet = Loader.new({}):require("src/shared/WalletRules")

		-- Cette méthode permet de construire un enregistrement de schéma 2 lorsqu'un test part d'un solde stocké.
		local function record(earned: number, purchased: number?, items: { string }?)
			local w = Wallet.empty()
			w.earned = earned
			w.purchased = purchased or 0
			return { schemaVersion = 2, items = items or {}, wallet = w }
		end

		-- Cette méthode permet de construire l'opération d'une dépense lorsqu'un test simule un achat (#393) : débit,
		-- objet donné en option, refus avec le motif.
		local function buy(price: number, itemId: string?)
			return function(rec)
				local w, reason = Wallet.debit(rec.wallet, price)
				if not w then
					return nil, reason
				end
				rec.wallet = w
				if itemId then
					table.insert(rec.items, itemId)
				end
				return rec, "achat"
			end
		end

		T.it("enregistrement v1 sans `wallet` : portefeuille de départ, réécrivable, réécrit en v2", function()
			local v1 = {
				schemaVersion = 1,
				items = { "weapon.m9bayonet" },
				equipped = { knife = { weapon = "weapon.m9bayonet" } },
			}
			local stored, canSave, equipped, wallet = Rules.loadOutcome(true, v1)
			T.expect(canSave)
			T.expectEqual(table.concat(stored, ","), "weapon.m9bayonet")
			T.expectEqual(equipped.knife.weapon, "weapon.m9bayonet")
			T.expectEqual(Wallet.balance(wallet), Wallet.STARTING_BALANCE)
			local written, status = Rules.mergeForSave(v1, {}, nil)
			assert(written)
			T.expectEqual(status, "merged")
			T.expectEqual(written.schemaVersion, Rules.SCHEMA_VERSION)
			T.expectEqual(written.schemaVersion, 2)
			T.expectEqual(written.items[1], "weapon.m9bayonet", "items intacts")
			T.expectEqual(written.equipped.knife.weapon, "weapon.m9bayonet", "équipement intact")
			T.expectEqual(Wallet.balance(written.wallet), Wallet.STARTING_BALANCE)
		end)

		T.it("schéma plus récent ou portefeuille illisible : sauvegarde coupée, rien d'écrit", function()
			local _, canSave = Rules.loadOutcome(true, { schemaVersion = Rules.SCHEMA_VERSION + 1, items = {} })
			T.expect(not canSave)
			local bad = { schemaVersion = 2, items = {}, wallet = { earned = -4, purchased = 0 } }
			local _, badSave, _, wallet = Rules.loadOutcome(true, bad)
			T.expect(not badSave)
			T.expectEqual(Wallet.balance(wallet), Wallet.STARTING_BALANCE)
			local written, status = Rules.mergeForSave(bad, {}, nil, { session = "a", batches = {}, upTo = 1 }, buy(1))
			T.expectEqual(written, nil)
			T.expectEqual(status, "refused")
		end)

		T.it("relit le portefeuille d'un enregistrement v2", function()
			local _, canSave, _, wallet = Rules.loadOutcome(true, record(300, 200))
			T.expect(canSave)
			T.expectEqual(Wallet.balance(wallet), 500)
		end)

		T.it("fusion : lots de gains ajoutés, lot rejoué non recompté, deux serveurs additionnés", function()
			local change = { session = "a", batches = { { seq = 1, earned = 40 } }, upTo = 1 }
			local first = Rules.mergeForSave(record(100), { "weapon.m9bayonet" }, nil, change)
			assert(first)
			T.expectEqual(first.wallet.earned, 140)
			local replay = Rules.mergeForSave(first, {}, nil, change)
			assert(replay)
			T.expectEqual(replay.wallet.earned, 140, "lot rejoué")
			local other = Rules.mergeForSave(
				replay,
				{},
				nil,
				{ session = "b", batches = { { seq = 1, earned = 7 } }, upTo = 1 }
			)
			assert(other)
			T.expectEqual(other.wallet.earned, 147)
			T.expectEqual(other.items[1], "weapon.m9bayonet")
		end)

		T.it(
			"fusion (#394) : deux serveurs au plafond du jour ne le dépassent pas, remboursement hors plafond",
			function()
				local day = 20407
				local stored = record(500)
				stored.wallet.day = day
				stored.wallet.dayEarned = 210
				-- Chaque serveur a vu 210 et crédité 40 de son côté
				local function play(session: string)
					return { session = session, batches = { { seq = 1, earned = 0, capped = 40, day = day } }, upTo = 1 }
				end
				local a = Rules.mergeForSave(stored, {}, nil, play("a"))
				assert(a)
				local b = Rules.mergeForSave(a, {}, nil, play("b"))
				assert(b)
				T.expectEqual(b.wallet.dayEarned, 250)
				T.expectEqual(b.wallet.earned, 540, "le second serveur n'ajoute rien au-delà du plafond")
				-- Doublon remboursé par une transaction (#393) : `earned` seul, sans toucher `dayEarned`
				local refund = function(rec)
					rec.wallet.earned += 100
					return rec, nil
				end
				local refunded, status = Rules.mergeForSave(
					b,
					{},
					nil,
					{ session = "a", batches = {}, upTo = 2 },
					refund
				)
				assert(refunded)
				T.expectEqual(status, "applied")
				T.expectEqual(refunded.wallet.earned, 640)
				T.expectEqual(refunded.wallet.dayEarned, 250)
				T.expectEqual(refunded.wallet.day, day)
			end
		)

		T.it("fusion sans portefeuille de session : celui stocké est gardé tel quel", function()
			local written = Rules.mergeForSave(record(70, 30), {}, nil)
			assert(written)
			T.expectEqual(written.wallet.earned, 70)
			T.expectEqual(written.wallet.purchased, 30)
		end)

		T.it("transaction : débit et objet dans la même écriture, gains de la session comptés avant", function()
			local change = { session = "a", batches = { { seq = 1, earned = 20 } }, upTo = 2 }
			local written, status, result =
				Rules.mergeForSave(record(90, 0), {}, nil, change, buy(100, "skin.awp.balise"))
			assert(written)
			T.expectEqual(status, "applied")
			T.expectEqual(result, "achat")
			T.expectEqual(Wallet.balance(written.wallet), 10)
			T.expect(table.find(written.items, "skin.awp.balise") ~= nil, "objet donné")
			T.expectEqual(Wallet.appliedSeq(written.wallet, "a"), 2, "marque de l'opération")
		end)

		T.it("transaction refusée (solde stocké insuffisant) : rien à écrire", function()
			local old = record(50)
			local change = { session = "a", batches = {}, upTo = 1 }
			local written, status, result = Rules.mergeForSave(old, {}, nil, change, buy(80, "skin.awp.balise"))
			T.expectEqual(written, nil)
			T.expectEqual(status, "rejected")
			T.expectEqual(result, "insufficient")
			T.expectEqual(old.wallet.earned, 50, "stocké intact")
			T.expectEqual(#old.items, 0, "stocké intact")
		end)

		T.it("transaction déjà écrite (réponse perdue) : pas rejouée", function()
			local change = { session = "a", batches = {}, upTo = 1 }
			local first = Rules.mergeForSave(record(100), {}, nil, change, buy(30))
			assert(first)
			local again, status = Rules.mergeForSave(first, {}, nil, change, buy(30))
			assert(again)
			T.expectEqual(status, "replayed")
			T.expectEqual(Wallet.balance(again.wallet), 70)
		end)

		T.it("transaction : une opération ne retire pas d'objet et ne rend pas un solde négatif", function()
			local change = { session = "a", batches = {}, upTo = 1 }
			local kept = Rules.mergeForSave(record(10, 0, { "weapon.m9bayonet" }), {}, nil, change, function(rec)
				rec.items = {}
				return rec, nil
			end)
			assert(kept)
			T.expectEqual(kept.items[1], "weapon.m9bayonet")
			local negative, status, reason = Rules.mergeForSave(record(10), {}, nil, change, function(rec)
				rec.wallet.earned = -5
				return rec, nil
			end)
			T.expectEqual(negative, nil)
			T.expectEqual(status, "rejected")
			T.expectEqual(reason, "invalid")
		end)

		T.it("transaction : un reçu mal formé est refusé, pas retiré en silence", function()
			local change = { session = "a", batches = {}, upTo = 1 }
			local tooLong = string.rep("x", Wallet.MAX_RECEIPT_LENGTH + 1)
			for _, bad in { tooLong, "", 42 } do
				local written, status, reason = Rules.mergeForSave(record(0), {}, nil, change, function(rec)
					rec.wallet.purchased += 500
					table.insert(rec.wallet.receipts, bad)
					return rec, nil
				end)
				T.expectEqual(written, nil)
				T.expectEqual(status, "rejected")
				T.expectEqual(reason, "invalid")
			end
		end)

		T.it("transaction : l'opération reçoit une copie, la fusion est pure", function()
			local old = record(100)
			local change = { session = "a", batches = { { seq = 1, earned = 5 } }, upTo = 2 }
			local seen
			Rules.mergeForSave(old, {}, nil, change, function(rec)
				seen = rec
				rec.wallet.earned = 0
				return nil, "non"
			end)
			T.expectEqual(old.wallet.earned, 100)
			T.expectEqual(#old.wallet.writes, 0)
			T.expectEqual(seen.wallet.earned, 0, "copie modifiée par l'opération seulement")
			T.expectEqual(#change.batches, 1)
		end)
	end)
end

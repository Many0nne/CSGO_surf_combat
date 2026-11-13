return function(T, Loader)
	-- Même contexte : InfosRules, HUDRules et le test lisent la même instance de KeyBindings
	local loader = Loader.new()
	local InfosRules = loader:require("src/client/ui/InfosRules")
	local HUDRules = loader:require("src/client/ui/HUDRules")
	local KeyBindings = loader:require("src/shared/KeyBindings")

	-- Cette méthode permet de simuler LocalSettings.keyText lorsqu'un test choisit une disposition : le nom de touche
	-- QWERTY (KeyCode) est converti par `layout`, sinon gardé tel quel (AZERTY : W→Z, A→Q, Q→A).
	local function keyTextFor(layout: { [string]: string }): (string) -> string
		return function(name: string): string
			local digit = ({ One = "1", Two = "2", Three = "3" })[name]
			if digit then
				return digit
			end
			return layout[name] or string.upper(name)
		end
	end

	local AZERTY = { W = "Z", A = "Q", Q = "A", Space = "SPACE" }

	-- Cette méthode permet de composer un contexte de test lorsqu'un cas a besoin de réglages précis.
	local function context(layout: { [string]: string }, fields: { [string]: any }?): any
		local ctx = {
			entries = HUDRules.keyDisplayEntries("full"),
			keyText = keyTextFor(layout),
			menuKey = "P",
			slotKeys = { "One", "Two", "Three" },
			defaultSlotKeys = { "One", "Two", "Three" },
			wheel = "previous",
		}
		for key, value in fields or {} do
			ctx[key] = value
		end
		return ctx
	end

	-- Cette méthode permet de trouver la ligne d'une action dans les lignes de COMMANDES lorsqu'un test la vérifie.
	local function rowFor(rows: { any }, action: string): any
		for _, row in rows do
			if string.find(row.action, action, 1, true) then
				return row
			end
		end
		return nil
	end

	T.describe("InfosRules.surfLines", function()
		T.it("cite les touches du clavier du joueur : Q, D et Z en AZERTY", function()
			local text = table.concat(InfosRules.surfLines(context(AZERTY)), "\n")
			T.expectEqual(string.find(text, "Maintiens Q ou D", 1, true) ~= nil, true, "gauche et droite")
			T.expectEqual(string.find(text, "Ne touche jamais à Z", 1, true) ~= nil, true, "avant")
			T.expectEqual(string.find(text, "(Q/D + souris)", 1, true) ~= nil, true, "air strafe")
		end)

		T.it("cite A, D et W en QWERTY", function()
			local text = table.concat(InfosRules.surfLines(context({})), "\n")
			T.expectEqual(string.find(text, "Maintiens A ou D", 1, true) ~= nil, true, "gauche et droite")
			T.expectEqual(string.find(text, "Ne touche jamais à W", 1, true) ~= nil, true, "avant")
		end)

		T.it("suit KeyBindings : une touche gauche changée change le texte", function()
			local entries = HUDRules.keyDisplayEntries("full")
			for _, entry in entries do
				if entry.id == "left" then
					entry.keys = { "J" }
				end
			end
			local text = table.concat(InfosRules.surfLines(context({}, { entries = entries })), "\n")
			T.expectEqual(string.find(text, "Maintiens J ou D", 1, true) ~= nil, true)
		end)
	end)

	T.describe("InfosRules.commandRows", function()
		T.it("liste les directions telles qu'imprimées : Z Q S D en AZERTY, W A S D en QWERTY", function()
			T.expectEqual(rowFor(InfosRules.commandRows(context(AZERTY)), "déplacer").key, "Z Q S D")
			T.expectEqual(rowFor(InfosRules.commandRows(context({})), "déplacer").key, "W A S D")
		end)

		T.it("couvre chaque action de l'affichage des touches, clic droit, marche lente et armes compris", function()
			local rows = InfosRules.commandRows(context(AZERTY))
			T.expectEqual(rowFor(rows, "Tirer").key, "CLIC GAUCHE")
			T.expectEqual(rowFor(rows, "lunette").key, "CLIC DROIT")
			T.expectEqual(rowFor(rows, "Marche lente").key, "MAJ")
			T.expectEqual(rowFor(rows, "accroupir").key, "CTRL")
			T.expectEqual(rowFor(rows, "Sauter").key, "ESPACE")
			T.expectEqual(rowFor(rows, "Recharger").key, "R")
			T.expectEqual(rowFor(rows, "Inspecter").key, "F")
			T.expectEqual(rowFor(rows, "Changer d'arme").key, "1 – 3")
			T.expectEqual(rowFor(rows, "Classement").key, "TAB")
			T.expectEqual(rowFor(rows, "Menu en partie").key, "P")
		end)

		T.it("prend les touches d'actions dans HUDRules.keyDisplayEntries, sans liste parallèle", function()
			local keyMap = KeyBindings.keyMap()
			for _, entry in HUDRules.keyDisplayEntries("full") do
				if entry.keys and not entry.label then
					-- la touche d'une action lettre (R, F) doit apparaître dans une ligne sous son libellé
					local label = string.upper(entry.keys[1])
					local found = false
					for _, row in InfosRules.commandRows(context({})) do
						found = found or string.find(row.key, label, 1, true) ~= nil
					end
					T.expectEqual(found, true, entry.id .. " " .. label)
					T.expectEqual(keyMap[entry.keys[1]], entry.id)
				end
			end
		end)

		T.it("suit les touches d'armes réglées par le joueur", function()
			local custom = context({}, { slotKeys = { "Q", "E", "T" } })
			T.expectEqual(rowFor(InfosRules.commandRows(custom), "Changer d'arme").key, "Q E T")
			local azertyCustom = context(AZERTY, { slotKeys = { "Q", "E", "T" } })
			T.expectEqual(rowFor(InfosRules.commandRows(azertyCustom), "Changer d'arme").key, "A E T")
		end)

		T.it("masque la ligne molette quand elle est coupée", function()
			local on, off = InfosRules.commandRows(context({})), InfosRules.commandRows(context({}, { wheel = "off" }))
			T.expectEqual(#off + 1, #on)
			for _, row in off do
				T.expectEqual(row.key ~= "MOLETTE", true)
			end
		end)

		T.it("ne met aucune lettre de touche en dur : tout change avec la disposition", function()
			local weird = {}
			for _, name in { "W", "A", "S", "D", "R", "F", "P" } do
				weird[name] = "#" .. name
			end
			local rows = InfosRules.commandRows(context(weird))
			T.expectEqual(rowFor(rows, "déplacer").key, "#W #A #S #D")
			T.expectEqual(rowFor(rows, "Recharger").key, "#R")
			T.expectEqual(rowFor(rows, "Inspecter").key, "#F")
			T.expectEqual(rowFor(rows, "Menu en partie").key, "#P")
		end)
	end)
end

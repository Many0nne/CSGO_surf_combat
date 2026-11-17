-- Langue du jeu (#518) : choix de la langue, traduction, paramètres, bascule des textes posés, et aucun texte affiché
-- resté sans traduction anglaise dans les sources (tests/lib/LocaleScan).
local LocaleScan = require("../lib/LocaleScan")

-- Cette méthode permet de lister les paramètres `{nom}` d'un texte, triés, lorsque français et anglais sont comparés.
local function placeholders(text: string): string
	local names = {}
	for name in string.gmatch(text, "{([%w_]+)}") do
		table.insert(names, name)
	end
	table.sort(names)
	local formats = {}
	for format in string.gmatch(text, "%%[%d%.]*[sdfx]") do
		table.insert(formats, format)
	end
	return table.concat(names, ",") .. "|" .. table.concat(formats, ",")
end

return function(T, Loader)
	-- `task.spawn` immédiat : les abonnés sont prévenus pendant setLanguage
	local fakeTask = {
		spawn = function(fn, ...)
			fn(...)
		end,
	}

	-- Cette méthode permet de charger un module Locale neuf (langue par défaut) lorsqu'un cas en a besoin.
	local function load()
		return Loader.new({}, { task = fakeTask }):require("src/shared/Locale")
	end

	T.describe("Locale", function()
		T.it("prend la langue du compte : français pour un compte français, anglais sinon", function()
			local Locale = load()
			T.expectEqual(Locale.fromLocaleId("fr-fr"), "fr")
			T.expectEqual(Locale.fromLocaleId("fr-ca"), "fr")
			T.expectEqual(Locale.fromLocaleId("FR-FR"), "fr")
			T.expectEqual(Locale.fromLocaleId("en-us"), "en")
			T.expectEqual(Locale.fromLocaleId("es-es"), "en")
			T.expectEqual(Locale.fromLocaleId(nil), "en")
		end)

		T.it("le choix du joueur passe avant la langue du compte, une valeur inconnue est ignorée", function()
			local Locale = load()
			T.expectEqual(Locale.resolve("en", "fr-fr"), "en")
			T.expectEqual(Locale.resolve("fr", "en-us"), "fr")
			T.expectEqual(Locale.resolve(nil, "fr-fr"), "fr")
			T.expectEqual(Locale.resolve("de", "en-us"), "en")
		end)

		T.it("traduit en anglais, garde le français, et remplit les paramètres", function()
			local Locale = load()
			local en = Locale.english()
			local fr = next(en)
			T.expect(fr ~= nil, "au moins une traduction")
			T.expectEqual(Locale.translate("en", fr), en[fr])
			T.expectEqual(Locale.translate("fr", fr), fr)
			T.expectEqual(Locale.translate("en", "Texte sans traduction {n}", { n = 3 }), "Texte sans traduction 3")
			T.expectEqual(Locale.translate("fr", "{a} et {b}", { a = 1 }), "1 et {b}")
		end)

		T.it("un texte posé suit la langue, sauf s'il a été réécrit entre-temps", function()
			local Locale = load()
			local fr, en = next(Locale.english())
			Locale.setLanguage("fr")
			local label = { Text = "" }
			local rewritten = { Text = "" }
			Locale.apply(label :: any, fr)
			Locale.apply(rewritten :: any, fr)
			rewritten.Text = "42"
			local heard
			Locale.onChanged(function(language)
				heard = language
			end)
			Locale.setLanguage("en")
			T.expectEqual(label.Text, en)
			T.expectEqual(rewritten.Text, "42")
			T.expectEqual(heard, "en")
			Locale.setLanguage("fr")
			T.expectEqual(label.Text, fr)
		end)

		T.it("chaque traduction garde les paramètres de son texte français", function()
			local Locale = load()
			for fr, en in Locale.english() do
				T.expectEqual(placeholders(en), placeholders(fr), "paramètres de « " .. fr .. " »")
				T.expect(en ~= "", "traduction vide pour « " .. fr .. " »")
			end
		end)

		T.it("une même phrase n'a qu'une traduction d'une table à l'autre", function()
			local Locale = load()
			local seen = {}
			for _, entries in Locale.EN_TABLES do
				for fr, en in entries do
					T.expect(seen[fr] == nil or seen[fr] == en, "traductions différentes pour « " .. fr .. " »")
					seen[fr] = en
				end
			end
		end)

		T.it("aucun texte affiché n'est resté sans traduction anglaise", function()
			local Locale = load()
			local found = LocaleScan.untranslated(Locale.hasEnglish)
			T.expect(
				#found == 0,
				#found .. " texte(s) sans traduction (lune run tools/locale_scan.luau) :\n" .. table.concat(found, "\n")
			)
		end)
	end)
end

-- Aide de première partie (#291) : seuil débutant, attribut de debug, choix et textes des conseils de l'écran de mort.
return function(T, Loader)
	-- Même contexte : InfosRules, HUDRules et le test lisent la même instance de KeyBindings
	local loader = Loader.new()
	local BeginnerRules = loader:require("src/client/ui/BeginnerRules")
	local InfosRules = loader:require("src/client/ui/InfosRules")
	local HUDRules = loader:require("src/client/ui/HUDRules")

	-- Cette méthode permet de simuler des statistiques relues (StatsRules.decode) lorsqu'un test choisit les manches jouées.
	local function stats(rounds: number): any
		return { kills = 0, deaths = 0, roundsPlayed = rounds, roundsWon = 0 }
	end

	local AZERTY = { W = "Z", A = "Q", Q = "A" }

	-- Cette méthode permet de composer un contexte de conseils lorsqu'un test choisit la disposition et l'auto-bhop.
	local function context(layout: { [string]: string }, autoBhop: boolean): any
		return {
			entries = HUDRules.keyDisplayEntries("full"),
			keyText = function(name: string): string
				return layout[name] or string.upper(name)
			end,
			autoBhop = autoBhop,
		}
	end

	-- Cette méthode permet de retrouver un conseil par thème lorsqu'un test vérifie son texte.
	local function tipOf(tips: { any }, topic: string): any
		for _, tip in tips do
			if tip.topic == topic then
				return tip
			end
		end
		return nil
	end

	T.describe("BeginnerRules.isBeginner", function()
		T.it("débutant sous 3 manches jouées, plus ensuite", function()
			T.expectEqual(BeginnerRules.BEGINNER_ROUNDS, 3)
			T.expectEqual(BeginnerRules.isBeginner(stats(0), nil), true, "0 manche")
			T.expectEqual(BeginnerRules.isBeginner(stats(2), nil), true, "2 manches")
			T.expectEqual(BeginnerRules.isBeginner(stats(3), nil), false, "3 manches")
			T.expectEqual(BeginnerRules.isBeginner(stats(250), nil), false, "ancien joueur")
		end)

		T.it("pas d'aide tant que les statistiques sont inconnues (chargement en cours ou en échec)", function()
			T.expectEqual(BeginnerRules.isBeginner(nil, nil), false)
		end)

		T.it("l'attribut de debug force l'un ou l'autre état", function()
			T.expectEqual(BeginnerRules.isBeginner(nil, true), true, "inconnu forcé débutant")
			T.expectEqual(BeginnerRules.isBeginner(stats(50), true), true, "ancien forcé débutant")
			T.expectEqual(BeginnerRules.isBeginner(stats(0), false), false, "neuf forcé non débutant")
		end)

		T.it("ignore un attribut de debug qui n'est pas un booléen", function()
			T.expectEqual(BeginnerRules.isBeginner(stats(0), "oui"), true)
			T.expectEqual(BeginnerRules.isBeginner(stats(5), 1), false)
		end)
	end)

	T.describe("BeginnerRules.pickTip", function()
		local tips = { "a", "b", "c" }

		T.it("un conseil par mort, à tour de rôle", function()
			local picked = {}
			for i = 1, 4 do
				table.insert(picked, BeginnerRules.pickTip(tips, true, true, i))
			end
			T.expectEqual(table.concat(picked, ","), "a,b,c,a")
		end)

		T.it("aucun conseil hors débutant, conseils coupés ou liste vide", function()
			T.expectEqual(BeginnerRules.pickTip(tips, false, true, 1), nil, "pas débutant")
			T.expectEqual(BeginnerRules.pickTip(tips, true, false, 1), nil, "conseils coupés")
			T.expectEqual(BeginnerRules.pickTip({}, true, true, 1), nil, "liste vide")
		end)

		T.it("ramène un numéro de mort nul ou négatif au premier conseil", function()
			T.expectEqual(BeginnerRules.pickTip(tips, true, true, 0), "a")
			T.expectEqual(BeginnerRules.pickTip(tips, true, true, -3), "a")
		end)
	end)

	T.describe("InfosRules.deathTips", function()
		T.it("donne un conseil de surf, de bhop et d'air strafe", function()
			local tips = InfosRules.deathTips(context({}, true))
			T.expectEqual(#tips, 3)
			for _, topic in { "SURF", "BHOP", "AIR STRAFE" } do
				T.expectEqual(tipOf(tips, topic) ~= nil, true, topic)
			end
		end)

		T.it("cite les touches du clavier du joueur : Q, D et Z en AZERTY, A, D et W en QWERTY", function()
			local azerty = InfosRules.deathTips(context(AZERTY, true))
			T.expectEqual(string.find(tipOf(azerty, "SURF").text, "maintiens Q ou D", 1, true) ~= nil, true)
			T.expectEqual(string.find(tipOf(azerty, "SURF").text, "jamais à Z", 1, true) ~= nil, true)
			T.expectEqual(string.find(tipOf(azerty, "AIR STRAFE").text, "tiens Q", 1, true) ~= nil, true)
			local qwerty = InfosRules.deathTips(context({}, true))
			T.expectEqual(string.find(tipOf(qwerty, "SURF").text, "maintiens A ou D", 1, true) ~= nil, true)
			T.expectEqual(string.find(tipOf(qwerty, "SURF").text, "jamais à W", 1, true) ~= nil, true)
		end)

		T.it("suit KeyBindings : une touche gauche changée change le texte", function()
			local ctx = context({}, true)
			for _, entry in ctx.entries do
				if entry.id == "left" then
					entry.keys = { "J" }
				end
			end
			T.expectEqual(string.find(tipOf(InfosRules.deathTips(ctx), "SURF").text, "J ou D", 1, true) ~= nil, true)
		end)

		T.it("adapte le bhop à l'auto-bhop : garder Espace, ou l'appuyer à chaque atterrissage", function()
			local on = tipOf(InfosRules.deathTips(context({}, true)), "BHOP").text
			local off = tipOf(InfosRules.deathTips(context({}, false)), "BHOP").text
			T.expectEqual(string.find(on, "garde ESPACE", 1, true) ~= nil, true, on)
			T.expectEqual(string.find(off, "appuie sur ESPACE", 1, true) ~= nil, true, off)
		end)
	end)
end

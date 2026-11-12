-- Règles pures des statistiques persistantes (#296) : chargement tolérant, fusion des écarts d'une session dans le
-- profil stocké (écritures concurrentes), format inconnu ou plus récent jamais réécrit.
return function(T, Loader)
	local Rules = Loader.new({}):require("src/shared/StatsRules")

	-- Cette méthode permet de construire un écart de session lorsqu'un test n'en précise que quelques champs.
	local function delta(fields)
		local d = Rules.zero()
		for field, value in fields do
			d[field] = value
		end
		return d
	end

	T.describe("StatsRules : chargement", function()
		T.it("nouveau joueur (aucune donnée) : zéros, écriture permise", function()
			local stats, canSave, known = Rules.loadOutcome(true, nil)
			T.expectEqual(stats.kills, 0)
			T.expectEqual(stats.roundsWon, 0)
			T.expectEqual(canSave, true)
			T.expectEqual(known, true)
		end)

		T.it("relit les compteurs, un champ absent vaut 0", function()
			local stats, canSave = Rules.loadOutcome(true, { schemaVersion = 1, stats = { kills = 12, deaths = 3 } })
			T.expectEqual(stats.kills, 12)
			T.expectEqual(stats.deaths, 3)
			T.expectEqual(stats.roundsPlayed, 0)
			T.expectEqual(canSave, true)
		end)

		T.it("enregistrement sans `stats` : zéros, sauvegarde coupée, sans planter", function()
			local stats, canSave = Rules.loadOutcome(true, { schemaVersion = 1 })
			T.expectEqual(stats.kills, 0)
			T.expectEqual(canSave, false)
		end)

		T.it("schéma plus récent : zéros, sauvegarde coupée (pas réétiqueté en version 1)", function()
			local stats, canSave =
				Rules.loadOutcome(true, { schemaVersion = Rules.SCHEMA_VERSION + 1, stats = { kills = 40 } })
			T.expectEqual(stats.kills, 0)
			T.expectEqual(canSave, false)
		end)

		T.it("format inconnu (texte, compteur négatif ou non entier) : sauvegarde coupée", function()
			T.expectEqual(select(2, Rules.loadOutcome(true, "texte")), false)
			T.expectEqual(select(2, Rules.loadOutcome(true, { stats = "beaucoup" })), false)
			T.expectEqual(select(2, Rules.loadOutcome(true, { stats = { kills = -1 } })), false)
			T.expectEqual(select(2, Rules.loadOutcome(true, { stats = { kills = 1.5 } })), false)
			T.expectEqual(select(2, Rules.loadOutcome(true, { schemaVersion = "1", stats = {} })), false)
		end)

		T.it("lecture en échec : zéros non fiables, écriture permise (la fusion revérifie)", function()
			local stats, canSave, known = Rules.loadOutcome(false, nil)
			T.expectEqual(stats.kills, 0)
			T.expectEqual(canSave, true)
			T.expectEqual(known, false)
		end)
	end)

	T.describe("StatsRules : écarts", function()
		T.it("un écart à zéro est vide, un kill ne l'est plus", function()
			local d = Rules.zero()
			T.expect(Rules.isEmpty(d), "vide au départ")
			Rules.add(d, "kills")
			T.expect(not Rules.isEmpty(d), "un kill")
			T.expectEqual(d.kills, 1)
			Rules.add(d, "roundsPlayed", 2)
			T.expectEqual(d.roundsPlayed, 2)
		end)

		T.it("additionne stocké et écarts champ par champ", function()
			local total = Rules.sum(delta({ kills = 2, roundsWon = 1 }), delta({ kills = 3, deaths = 1 }))
			T.expectEqual(total.kills, 5)
			T.expectEqual(total.deaths, 1)
			T.expectEqual(total.roundsWon, 1)
		end)
	end)

	T.describe("StatsRules : fusion à l'écriture", function()
		T.it("nouveau joueur : écrit les écarts de la session en version courante", function()
			local written = Rules.mergeForSave(nil, delta({ kills = 2, roundsPlayed = 1 }))
			T.expectEqual(written.schemaVersion, Rules.SCHEMA_VERSION)
			T.expectEqual(written.stats.kills, 2)
			T.expectEqual(written.stats.deaths, 0)
			T.expectEqual(written.stats.roundsPlayed, 1)
		end)

		T.it("ajoute les écarts au stocké, sans réécrire le profil de la session", function()
			local written = Rules.mergeForSave(
				{ schemaVersion = 1, stats = { kills = 10, deaths = 4, roundsPlayed = 6, roundsWon = 2 } },
				delta({ kills = 1, roundsPlayed = 1, roundsWon = 1 })
			)
			T.expectEqual(written.stats.kills, 11)
			T.expectEqual(written.stats.deaths, 4)
			T.expectEqual(written.stats.roundsPlayed, 7)
			T.expectEqual(written.stats.roundsWon, 3)
		end)

		T.it("deux sessions concurrentes additionnent leurs écarts, dans n'importe quel ordre", function()
			local start = { schemaVersion = 1, stats = { kills = 5, deaths = 5, roundsPlayed = 2, roundsWon = 0 } }
			local a = delta({ kills = 3, roundsPlayed = 1 })
			local b = delta({ deaths = 2, roundsPlayed = 1, roundsWon = 1 })
			local ab = Rules.mergeForSave(Rules.mergeForSave(start, a), b)
			local ba = Rules.mergeForSave(Rules.mergeForSave(start, b), a)
			for _, field in Rules.FIELDS do
				T.expectEqual(ab.stats[field], ba.stats[field], "même résultat : " .. field)
			end
			T.expectEqual(ab.stats.kills, 8)
			T.expectEqual(ab.stats.deaths, 7)
			T.expectEqual(ab.stats.roundsPlayed, 4)
			T.expectEqual(ab.stats.roundsWon, 1)
		end)

		T.it("pure : rejouée par UpdateAsync, elle ne compte pas deux fois", function()
			local old = { schemaVersion = 1, stats = { kills = 1 } }
			local d = delta({ kills = 1 })
			Rules.mergeForSave(old, d)
			local written = Rules.mergeForSave(old, d)
			T.expectEqual(written.stats.kills, 2)
			T.expectEqual(old.stats.kills, 1, "stocké intact")
			T.expectEqual(d.kills, 1, "écart intact")
		end)

		T.it("recopie un champ inconnu de cette version (ajouté plus tard au même schéma)", function()
			local written =
				Rules.mergeForSave({ schemaVersion = 1, stats = { kills = 1, headshots = 9 } }, Rules.zero())
			T.expectEqual(written.stats.headshots, 9)
		end)

		T.it("annule l'écriture (nil) sur un format inconnu ou plus récent", function()
			local d = delta({ kills = 1 })
			T.expectEqual(Rules.mergeForSave({ schemaVersion = Rules.SCHEMA_VERSION + 1, stats = {} }, d), nil)
			T.expectEqual(Rules.mergeForSave({ schemaVersion = 1 }, d), nil)
			T.expectEqual(Rules.mergeForSave("texte", d), nil)
		end)

		T.it("relit les compteurs écrits", function()
			local stats = Rules.storedStats({ schemaVersion = 1, stats = { kills = 4, roundsWon = 2 } })
			T.expectEqual(stats.kills, 4)
			T.expectEqual(stats.roundsWon, 2)
			T.expectEqual(stats.deaths, 0)
		end)
	end)
end

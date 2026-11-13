-- Règles pures des statistiques persistantes (#296) : chargement tolérant, fusion des écarts d'une session dans le
-- profil stocké (écritures concurrentes, lot renvoyé), format inconnu ou plus récent jamais réécrit.
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

	-- Cette méthode permet de construire un lot d'écarts d'une session lorsqu'un test le fusionne.
	local function batch(session: string, seq: number, fields)
		return { session = session, seq = seq, delta = delta(fields) }
	end

	T.describe("StatsRules : chargement", function()
		T.it("nouveau joueur (aucune donnée) : zéros, écriture permise", function()
			local stats, canSave = Rules.loadOutcome(true, nil)
			T.expectEqual(stats.kills, 0)
			T.expectEqual(stats.roundsWon, 0)
			T.expectEqual(canSave, true)
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
			T.expectEqual(select(2, Rules.loadOutcome(true, { stats = {}, writes = "x" })), false)
		end)

		T.it("lecture en échec : zéros, sauvegarde coupée", function()
			local stats, canSave = Rules.loadOutcome(false, nil)
			T.expectEqual(stats.kills, 0)
			T.expectEqual(canSave, false)
		end)
	end)

	T.describe("StatsRules : écarts", function()
		T.it("un écart à zéro est vide, un kill ne l'est plus", function()
			local d = Rules.zero()
			T.expect(Rules.isEmpty(d), "vide au départ")
			Rules.add(d, "kills")
			T.expect(not Rules.isEmpty(d), "un kill")
			T.expectEqual(d.kills, 1)
		end)

		T.it("additionne deux statistiques champ par champ", function()
			local total = Rules.sum(delta({ kills = 2, roundsWon = 1 }), delta({ kills = 3, deaths = 1 }))
			T.expectEqual(total.kills, 5)
			T.expectEqual(total.deaths, 1)
			T.expectEqual(total.roundsWon, 1)
		end)
	end)

	T.describe("StatsRules : fusion à l'écriture", function()
		T.it("nouveau joueur : écrit les écarts du lot en version courante", function()
			local written, status = Rules.mergeForSave(nil, batch("a", 1, { kills = 2, roundsPlayed = 1 }))
			T.expectEqual(status, "merged")
			T.expectEqual(written.schemaVersion, Rules.SCHEMA_VERSION)
			T.expectEqual(written.stats.kills, 2)
			T.expectEqual(written.stats.deaths, 0)
			T.expectEqual(written.stats.roundsPlayed, 1)
			T.expectEqual(#written.writes, 1)
		end)

		T.it("ajoute les écarts au stocké, sans réécrire le profil de la session", function()
			local written = Rules.mergeForSave(
				{ schemaVersion = 1, stats = { kills = 10, deaths = 4, roundsPlayed = 6, roundsWon = 2 } },
				batch("a", 1, { kills = 1, roundsPlayed = 1, roundsWon = 1 })
			)
			T.expectEqual(written.stats.kills, 11)
			T.expectEqual(written.stats.deaths, 4)
			T.expectEqual(written.stats.roundsPlayed, 7)
			T.expectEqual(written.stats.roundsWon, 3)
		end)

		T.it("deux sessions concurrentes additionnent leurs écarts, dans n'importe quel ordre", function()
			local start = { schemaVersion = 1, stats = { kills = 5, deaths = 5, roundsPlayed = 2, roundsWon = 0 } }
			local a = batch("a", 1, { kills = 3, roundsPlayed = 1 })
			local b = batch("b", 1, { deaths = 2, roundsPlayed = 1, roundsWon = 1 })
			local ab = Rules.mergeForSave((Rules.mergeForSave(start, a)), b)
			local ba = Rules.mergeForSave((Rules.mergeForSave(start, b)), a)
			for _, field in Rules.FIELDS do
				T.expectEqual(ab.stats[field], ba.stats[field], "même résultat : " .. field)
			end
			T.expectEqual(ab.stats.kills, 8)
			T.expectEqual(ab.stats.deaths, 7)
			T.expectEqual(ab.stats.roundsPlayed, 4)
			T.expectEqual(ab.stats.roundsWon, 1)
		end)

		T.it("un lot renvoyé après une écriture passée (échec douteux) n'est pas compté deux fois", function()
			local once = Rules.mergeForSave(nil, batch("a", 1, { kills = 2 }))
			local again, status = Rules.mergeForSave(once, batch("a", 1, { kills = 2 }))
			T.expectEqual(again, nil, "rien à écrire")
			T.expectEqual(status, "applied")
			local nextBatch = Rules.mergeForSave(once, batch("a", 2, { kills = 1 }))
			T.expectEqual(nextBatch.stats.kills, 3, "le lot suivant de la session compte")
			T.expectEqual(#nextBatch.writes, 1, "une marque par session")
		end)

		T.it("ne retient que les MAX_WRITE_MARKS sessions les plus récentes", function()
			local record = nil
			for i = 1, Rules.MAX_WRITE_MARKS + 3 do
				record = Rules.mergeForSave(record, batch("s" .. i, 1, { kills = 1 }))
			end
			T.expectEqual(#record.writes, Rules.MAX_WRITE_MARKS)
			T.expectEqual(record.writes[#record.writes].session, "s" .. (Rules.MAX_WRITE_MARKS + 3))
			T.expectEqual(record.stats.kills, Rules.MAX_WRITE_MARKS + 3)
		end)

		T.it("pure : rejouée par UpdateAsync, elle ne modifie ni le stocké ni le lot", function()
			local old = { schemaVersion = 1, stats = { kills = 1 } }
			local b = batch("a", 1, { kills = 1 })
			Rules.mergeForSave(old, b)
			local written = Rules.mergeForSave(old, b)
			T.expectEqual(written.stats.kills, 2)
			T.expectEqual(old.stats.kills, 1, "stocké intact")
			T.expectEqual(old.writes, nil, "marques du stocké intactes")
			T.expectEqual(b.delta.kills, 1, "lot intact")
		end)

		T.it("recopie un champ de stats inconnu de cette version (ajouté plus tard au même schéma)", function()
			local written =
				Rules.mergeForSave({ schemaVersion = 1, stats = { kills = 1, headshots = 9 } }, batch("a", 1, {}))
			T.expectEqual(written.stats.headshots, 9)
		end)

		T.it("recopie un champ inconnu de l'enregistrement (même schéma)", function()
			local written = Rules.mergeForSave({ schemaVersion = 1, stats = {}, lastSeen = 42 }, batch("a", 1, {}))
			T.expectEqual(written.lastSeen, 42)
		end)

		T.it("annule l'écriture (nil) sur un format inconnu ou plus récent", function()
			local b = batch("a", 1, { kills = 1 })
			local written, status = Rules.mergeForSave({ schemaVersion = Rules.SCHEMA_VERSION + 1, stats = {} }, b)
			T.expectEqual(written, nil)
			T.expectEqual(status, "refused")
			T.expectEqual((Rules.mergeForSave({ schemaVersion = 1 }, b)), nil)
			T.expectEqual((Rules.mergeForSave("texte", b)), nil)
		end)

		T.it("relit les compteurs écrits", function()
			local stats = Rules.read({ schemaVersion = 1, stats = { kills = 4, roundsWon = 2 } })
			T.expectEqual(stats.kills, 4)
			T.expectEqual(stats.roundsWon, 2)
			T.expectEqual(stats.deaths, 0)
		end)
	end)

	T.describe("StatsRules : attribut PlayerStats (#301)", function()
		T.it("encode puis relit les compteurs dans l'ordre de FIELDS", function()
			local stats = delta({ kills = 12, deaths = 3, roundsPlayed = 5, roundsWon = 1 })
			T.expectEqual(Rules.encode(stats), "12,3,5,1")
			local decoded = Rules.decode(Rules.encode(stats))
			T.expectEqual(decoded and decoded.kills, 12)
			T.expectEqual(decoded and decoded.deaths, 3)
			T.expectEqual(decoded and decoded.roundsPlayed, 5)
			T.expectEqual(decoded and decoded.roundsWon, 1)
		end)

		T.it("non chargé : attribut absent ou mal formé → nil, jamais des zéros", function()
			T.expectEqual(Rules.decode(nil), nil)
			T.expectEqual(Rules.decode(""), nil)
			T.expectEqual(Rules.decode("1,2,3"), nil, "champ manquant")
			T.expectEqual(Rules.decode("1,2,3,4,5"), nil, "champ en trop")
			T.expectEqual(Rules.decode("1,-2,3,4"), nil, "négatif")
			T.expectEqual(Rules.decode("1,2.5,3,4"), nil, "décimal")
			T.expectEqual(Rules.decode("1,x,3,4"), nil, "texte")
			T.expectEqual(Rules.decode(42), nil, "pas une chaîne")
			local huge = Rules.decode(Rules.encode(delta({ kills = 1e19 })))
			T.expectEqual(huge and huge.kills, 1e19, "compteur énorme : relu, pas « non chargé »")
			local zeros = Rules.decode("0,0,0,0")
			T.expectEqual(zeros and zeros.kills, 0, "de vrais zéros restent des zéros")
		end)
	end)
end

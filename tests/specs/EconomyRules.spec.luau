-- EconomyRules (#394) : barème, manche jouée, plafond de manche puis du jour, jour UTC, attributs lus par le client
-- (gains du jour, bandeau de fin de manche).
return function(T, Loader)
	local Economy = Loader.new({}):require("src/shared/EconomyRules")

	T.describe("EconomyRules : barème", function()
		T.it("kill sur un joueur +5, sur un bot +1", function()
			T.expectEqual(Economy.killGain(false), 5)
			T.expectEqual(Economy.killGain(true), 1)
		end)

		T.it("manche jouée : au moins un kill, ou 120 s en vie avec une activité réelle", function()
			local idle = { distance = 0, actions = 0 }
			local moving = { distance = Economy.PLAYED_MIN_DISTANCE, actions = 0 }
			local shooting = { distance = 0, actions = 1 }
			T.expect(Economy.played(1, 0, idle), "kill : jouée comme avant, même sans activité")
			T.expect(Economy.played(0, 120, moving), "a parcouru la distance")
			T.expect(Economy.played(0, 120, shooting), "a tiré")
			T.expect(not Economy.played(0, 119.9, moving), "pas assez en vie")
			T.expect(not Economy.played(0, 600, idle), "AFK que personne ne tue : écarté (#401)")
			T.expect(
				not Economy.played(0, 600, { distance = Economy.PLAYED_MIN_DISTANCE - 1, actions = 0 }),
				"juste sous le seuil de distance"
			)
			T.expectEqual(Economy.roundGain(0, 30, moving, false), 0)
			T.expectEqual(Economy.roundGain(0, 150, moving, false), 15)
			T.expectEqual(Economy.roundGain(0, 150, idle, false), 0, "AFK : rien")
			T.expectEqual(Economy.roundGain(3, 10, idle, true), 40, "manche jouée + victoire")
			T.expectEqual(Economy.roundGain(0, 0, idle, true), 0, "pas jouée : rien, même désignée vainqueur")
		end)

		T.it("distance d'un pas : horizontale seulement", function()
			T.expectEqual(Economy.horizontalStep({ X = 0, Y = 0, Z = 0 }, { X = 3, Y = 50, Z = 4 }), 5)
			T.expectEqual(Economy.horizontalStep({ X = 1, Y = 0, Z = 1 }, { X = 1, Y = -20, Z = 1 }), 0, "chute")
		end)

		T.it("pas de gain en entraînement ni hors manche active", function()
			T.expect(Economy.canEarn(false, true))
			T.expect(not Economy.canEarn(true, true), "entraînement")
			T.expect(not Economy.canEarn(false, false), "hors manche")
		end)
	end)

	T.describe("EconomyRules : plafonds", function()
		T.it("plafond de manche (60)", function()
			T.expectEqual(Economy.capRound(5, 0), 5)
			T.expectEqual(Economy.capRound(5, 57), 3)
			T.expectEqual(Economy.capRound(40, 60), 0)
			T.expectEqual(Economy.capRound(40, 75), 0, "jamais négatif")
		end)

		T.it("plafond du jour (250)", function()
			T.expectEqual(Economy.capDay(25, 240), 10)
			T.expectEqual(Economy.capDay(25, 250), 0)
		end)

		T.it("une manche à 12 kills sur joueurs plafonne à 60, fin de manche comprise", function()
			local earned = 0
			for _ = 1, 12 do
				earned += Economy.capRound(Economy.killGain(false), earned)
			end
			T.expectEqual(earned, 60)
			earned += Economy.capRound(Economy.roundGain(12, 300, { distance = 0, actions = 0 }, true), earned)
			T.expectEqual(earned, 60)
		end)
	end)

	T.describe("EconomyRules : jour UTC", function()
		T.it("change à 00:00 UTC", function()
			local day = 20407
			T.expectEqual(Economy.day(day * 86400), day)
			T.expectEqual(Economy.day(day * 86400 + 86399), day)
			T.expectEqual(Economy.day((day + 1) * 86400), day + 1)
			T.expect(Economy.isDay(day))
			T.expect(not Economy.isDay(-1))
			T.expect(not Economy.isDay(1.5))
			T.expect(not Economy.isDay("1"))
		end)
	end)

	T.describe("EconomyRules : attributs", function()
		T.it("gains du jour : relus pour le jour du client, 0 après minuit, nil si absent", function()
			local value = Economy.encodeDaily(20407, 140)
			T.expectEqual(value, "20407:140")
			T.expectEqual(Economy.decodeDaily(value, 20407), 140)
			T.expectEqual(Economy.decodeDaily(value, 20408), 0, "minuit UTC passé")
			T.expectEqual(Economy.decodeDaily(value, 20406), 140, "horloge du client en retard : le serveur fait foi")
			T.expectEqual(Economy.decodeDaily(nil, 20407), nil)
			T.expectEqual(Economy.decodeDaily("x:3", 20407), nil)
			T.expectEqual(Economy.decodeDaily(140, 20407), nil)
			T.expectEqual(Economy.dailyLabel(140), "140 / 250")
			T.expectEqual(Economy.dailyLabel(nil), "— / 250")
		end)

		T.it("bandeau : gain, plafond atteint, ou rien", function()
			local gain = Economy.roundBanner(40, 120)
			assert(gain)
			T.expectEqual(gain.amount, 40)
			T.expect(not gain.capReached)
			local capped = Economy.roundBanner(10, 250)
			assert(capped)
			T.expectEqual(capped.amount, 10)
			T.expect(capped.capReached)
			local onlyCap = Economy.roundBanner(0, 250)
			assert(onlyCap)
			T.expectEqual(onlyCap.amount, nil)
			T.expect(onlyCap.capReached)
			T.expectEqual(Economy.roundBanner(0, 30), nil, "manche sans gain sous le plafond : rien")
			T.expectEqual(Economy.roundBanner(nil, 250), nil, "pas de gain possible (attribut absent) : rien")
			T.expectEqual(Economy.roundBanner(-3, 0), nil)
		end)
	end)
end

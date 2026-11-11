return function(T, Loader)
	local ShotRules = Loader.new():require("src/server/ShotRules")
	local CharacterSyncRules = Loader.new():require("src/shared/CharacterSyncRules")

	-- Cette méthode permet de construire un tir horizontal vers +X lorsqu'un test ne porte que sur un champ.
	local function shot(overrides: { [string]: any }?)
		local s =
			{ origin = Vector3.zero, direction = Vector3.new(1, 0, 0), hitPos = Vector3.new(50, 0, 0), shotTime = 10 }
		for k, v in overrides or {} do
			s[k] = v
		end
		return s
	end

	T.describe("ShotRules : forme (#174)", function()
		T.it("accepte un tir de notre client", function()
			T.expectEqual((ShotRules.isWellFormed(shot())), true)
		end)

		T.it("refuse un tir absent, non unitaire, hors bornes ou sans instant", function()
			for label, bad in
				{
					absent = "rien",
					nonUnitaire = shot({ direction = Vector3.new(2, 0, 0) }),
					nul = shot({ direction = Vector3.zero }),
					horsBornes = shot({ hitPos = Vector3.new(2e5, 0, 0) }),
					origineNaN = shot({ origin = Vector3.new(0 / 0, 0, 0) }),
					instantNaN = shot({ shotTime = 0 / 0 }),
					instantInfini = shot({ shotTime = math.huge }),
					instantMoinsInfini = shot({ shotTime = -math.huge }),
					instantTexte = shot({ shotTime = "10" }),
				}
			do
				local ok, reason = ShotRules.isWellFormed(bad)
				T.expectEqual(ok, false, label)
				T.expect(type(reason) == "string", "raison manquante : " .. label)
			end
		end)
	end)

	T.describe("ShotRules : rembobinage", function()
		T.it("rembobine à shotTime - INTERP_DELAY, borné à [now - 0,4 s, now]", function()
			local delay = CharacterSyncRules.INTERP_DELAY
			T.expect(math.abs(ShotRules.rewindTime(100, 100) - (100 - delay)) < 1e-9, "shotTime présent")
			T.expectEqual(ShotRules.rewindTime(50, 100), 99.6, "shotTime trop ancien")
			T.expectEqual(ShotRules.rewindTime(200, 100), 100, "shotTime dans le futur")
			T.expectEqual(ShotRules.shooterTime(50, 100), 99.6)
		end)
	end)

	T.describe("ShotRules : origine, visée, portée", function()
		T.it("tolère 5 studs plus 0,1 s de la vitesse du tireur, depuis la plus proche de ses positions", function()
			T.expectEqual((ShotRules.checkOrigin(Vector3.new(0, 4.9, 0), { Vector3.zero }, 0)), true)
			T.expectEqual((ShotRules.checkOrigin(Vector3.new(0, 6, 0), { Vector3.zero }, 0)), false)
			T.expectEqual((ShotRules.checkOrigin(Vector3.new(0, 20, 0), { Vector3.zero }, 200)), true, "surf")
			T.expectEqual(
				(ShotRules.checkOrigin(Vector3.new(30, 0, 0), { Vector3.zero, Vector3.new(28, 0, 0) }, 0)),
				true,
				"position rembobinée"
			)
		end)

		T.it("mesure la distance au rayon, au point de départ derrière lui", function()
			local perp, along = ShotRules.distanceToRay(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(10, 3, 0))
			T.expectEqual(perp, 3)
			T.expectEqual(along, 10)
			perp = ShotRules.distanceToRay(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(-4, 3, 0))
			T.expectEqual(perp, 5)
		end)

		T.it("accepte un impact sur la partie, refuse un impact hors du rayon ou derrière le tireur", function()
			local part = Vector3.new(50, 0.5, 0)
			T.expectEqual((ShotRules.checkDirection(shot(), part, ShotRules.directionLimit(1, 0))), true)
			T.expectEqual(
				(
					ShotRules.checkDirection(
						shot({ hitPos = Vector3.new(50, 2, 0) }),
						part,
						ShotRules.directionLimit(1, 0)
					)
				),
				false
			)
			T.expectEqual(
				(
					ShotRules.checkDirection(
						shot({ hitPos = Vector3.new(-50, 0, 0) }),
						part,
						ShotRules.directionLimit(1, 0)
					)
				),
				false
			)
		end)

		T.it(
			"refuse un rayon qui passe loin de la partie, avec une tolérance qui croît avec la vitesse de la cible",
			function()
				local part = Vector3.new(50, 0, 6)
				T.expectEqual(
					(ShotRules.checkDirection(shot(), part, ShotRules.directionLimit(1, 0))),
					false,
					"6 studs à l'arrêt"
				)
				T.expectEqual(
					(ShotRules.checkDirection(shot(), part, ShotRules.directionLimit(1, 100))),
					true,
					"6 studs à 100 studs/s"
				)
			end
		)

		T.it("borne la portée à celle du client, marge comprise", function()
			T.expectEqual((ShotRules.checkDistance(shot({ hitPos = Vector3.new(2048, 0, 0) }))), true)
			T.expectEqual((ShotRules.checkDistance(shot({ hitPos = Vector3.new(2100, 0, 0) }))), false)
		end)

		T.it("arrête la ligne de vue avant l'impact", function()
			local from, delta = ShotRules.lineOfSightSegment(Vector3.zero, Vector3.new(50, 0, 0))
			T.expectEqual(from, Vector3.zero)
			T.expectEqual(delta, Vector3.new(50 - ShotRules.LINE_OF_SIGHT_END_MARGIN, 0, 0))
			T.expectEqual(ShotRules.lineOfSightSegment(Vector3.zero, Vector3.new(0.2, 0, 0)), nil, "bout portant")
		end)
	end)

	T.describe("ShotRules : vitesse", function()
		T.it("mesure sur une fenêtre de SPEED_WINDOW décalée dans la borne de rembobinage", function()
			local w = ShotRules.SPEED_WINDOW
			local from, to = ShotRules.speedWindow(99.8, 100)
			T.expect(
				math.abs(from - (99.8 - w / 2)) < 1e-9 and math.abs(to - (99.8 + w / 2)) < 1e-9,
				"fenêtre centrée"
			)
			from, to = ShotRules.speedWindow(100, 100)
			T.expect(math.abs(to - 100) < 1e-9 and math.abs(from - (100 - w)) < 1e-9, "décalée sous now")
			from, to = ShotRules.speedWindow(99.6, 100)
			T.expect(
				math.abs(from - 99.6) < 1e-9 and math.abs(to - (99.6 + w)) < 1e-9,
				"décalée au-dessus de now - 0,4 s"
			)
		end)

		T.it("divise par l'écart de temps réel, 0 sans historique", function()
			T.expectEqual(ShotRules.speedBetween(Vector3.zero, Vector3.new(10, 0, 0), 0.05), 200)
			T.expectEqual(ShotRules.speedBetween(nil, Vector3.new(10, 0, 0), 0.1), 0)
			T.expectEqual(ShotRules.speedBetween(Vector3.zero, Vector3.new(10, 0, 0), 0), 0)
		end)
	end)

	T.describe("ShotRules : modes", function()
		T.it("bloque selon le mode, et par prudence pour un contrôle inconnu", function()
			T.expectEqual(ShotRules.blocks("origin", { origin = "log" }), false)
			T.expectEqual(ShotRules.blocks("origin", { origin = "block" }), true)
			T.expectEqual(ShotRules.blocks("inconnu"), true)
		end)

		T.it(
			"refuse au-delà de l'ancienne borne de 250 studs un échec d'origine ou de ligne de vue, pas de visée",
			function()
				local modes = { origin = "log", lineOfSight = "log", direction = "log" }
				local far = ShotRules.LOG_ONLY_RANGE + 1
				T.expectEqual(ShotRules.refuses("lineOfSight", 100, modes), false, "proche : journal seul")
				T.expectEqual(ShotRules.refuses("lineOfSight", far, modes), true)
				T.expectEqual(ShotRules.refuses("origin", far, modes), true)
				T.expectEqual(ShotRules.refuses("direction", far, modes), false, "faux positif mesuré sur la visée")
			end
		)

		T.it("donne une gravité à chaque contrôle", function()
			for _, check in ShotRules.Check do
				T.expect(ShotRules.SEVERITY[check] ~= nil, "gravité manquante : " .. check)
				T.expect(ShotRules.MODES[check] ~= nil, "mode manquant : " .. check)
			end
		end)
	end)
end

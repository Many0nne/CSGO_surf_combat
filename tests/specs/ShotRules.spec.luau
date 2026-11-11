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

	T.describe("ShotRules : equip et chargeur (#175)", function()
		T.it("borne l'equip à EquipTime moins la tolérance, refuse un equip inconnu", function()
			local min = 1.58 - ShotRules.EQUIP_TOLERANCE
			T.expectEqual((ShotRules.checkEquip(10, 1.58, 10 + min)), true)
			T.expectEqual((ShotRules.checkEquip(10, 1.58, 10 + min - 0.01)), false)
			T.expectEqual((ShotRules.checkEquip(nil, 1.58, 1000)), false)
		end)

		T.it("livre equip et chargeur bloquants", function()
			T.expectEqual(ShotRules.blocks("equip"), true)
			T.expectEqual(ShotRules.blocks("magazine"), true)
		end)

		T.it("remplit le chargeur à la fin d'un rechargement, pas avant", function()
			local mag = ShotRules.newMagazine()
			for _ = 1, 5 do
				ShotRules.countShot(mag)
			end
			T.expectEqual((ShotRules.checkMagazine(mag, 5, 3.7, 20)), false, "vide")
			ShotRules.startReload(mag, 3.7, 20)
			T.expectEqual((ShotRules.checkMagazine(mag, 5, 3.7, 23)), false, "rechargement en cours")
			T.expectEqual((ShotRules.checkMagazine(mag, 5, 3.7, 20 + 3.7 - ShotRules.RELOAD_TOLERANCE)), true, "fini")
			T.expectEqual(mag.shots, 0)
		end)

		T.it("annule un rechargement inachevé, garde un rechargement fini", function()
			local mag = ShotRules.newMagazine()
			mag.shots = 5
			ShotRules.startReload(mag, 3.7, 0)
			ShotRules.cancelReload(mag, 3.7, 1)
			T.expectEqual(mag.shots, 5, "inachevé")
			T.expectEqual(mag.reloadAt, nil)
			ShotRules.startReload(mag, 3.7, 2)
			ShotRules.cancelReload(mag, 3.7, 10)
			T.expectEqual(mag.shots, 0, "fini avant le changement d'arme")
		end)

		T.it("refuse toute touche pendant un rechargement inachevé, même chargeur non vide", function()
			local mag = ShotRules.newMagazine()
			mag.shots = 2
			ShotRules.startReload(mag, 3.7, 0)
			local ok, detail = ShotRules.checkMagazine(mag, 5, 3.7, 1)
			T.expectEqual(ok, false)
			T.expect(string.find(detail or "", "pendant le rechargement", 1, true) ~= nil, detail)
			T.expectEqual((ShotRules.checkMagazine(mag, 5, 3.7, 3.5)), true, "fini à la tolérance près")
		end)

		T.it("redémarre un rechargement inachevé quand Reload revient", function()
			local mag = ShotRules.newMagazine()
			mag.shots = 3
			ShotRules.startReload(mag, 3.7, 0)
			ShotRules.startReload(mag, 3.7, 2) -- inachevé : repart de 2
			T.expectEqual(mag.reloadAt, 2)
			T.expectEqual(mag.shots, 3)
			T.expectEqual((ShotRules.checkMagazine(mag, 5, 3.7, 5)), false, "compté depuis le second Reload")
			T.expectEqual((ShotRules.checkMagazine(mag, 5, 3.7, 5.5)), true)
			T.expectEqual(mag.shots, 0)
		end)
	end)

	T.describe("ShotRules : orientation et ligne de vue de la mêlée (#176)", function()
		T.it("mesure l'angle horizontal, sans tenir compte de la hauteur ni du pitch", function()
			local angle, distance = ShotRules.horizontalAngle(Vector3.new(1, 0, 0), Vector3.zero, Vector3.new(0, 30, 5))
			T.expect(math.abs((angle :: number) - 90) < 1e-6, "angle " .. tostring(angle))
			T.expect(math.abs(distance - 5) < 1e-6, "distance " .. tostring(distance))
			-- Regard vers le bas : seul le cap horizontal compte
			angle = ShotRules.horizontalAngle(Vector3.new(1, -5, 0), Vector3.zero, Vector3.new(4, -2, 0))
			T.expect(math.abs(angle :: number) < 1e-6, "angle " .. tostring(angle))
			T.expectEqual((ShotRules.horizontalAngle(Vector3.new(1, 0, 0), Vector3.zero, Vector3.new(0, 3, 0))), nil)
		end)

		T.it("élargit l'angle permis de la demi-largeur du corps, jusqu'à 90° au contact", function()
			T.expect(math.abs(ShotRules.meleeAngleLimit(1) - (ShotRules.MELEE_MAX_ANGLE + 90)) < 1e-6, "contact")
			local far = ShotRules.meleeAngleLimit(7.5)
			T.expect(far > ShotRules.MELEE_MAX_ANGLE and far < ShotRules.MELEE_MAX_ANGLE + 16, "à 7,5 studs : " .. far)
		end)

		T.it("accepte une cible devant, refuse une cible dans le dos même collée", function()
			local look = Vector3.new(1, 0, 0)
			T.expectEqual((ShotRules.checkMeleeOrientation(look, Vector3.zero, Vector3.new(7, 0, 0))), true)
			T.expectEqual((ShotRules.checkMeleeOrientation(look, Vector3.zero, Vector3.new(-7, 0, 0))), false)
			-- Dans le dos à 1 stud : 180° pour 160° permis au plus
			local ok, excess, detail = ShotRules.checkMeleeOrientation(look, Vector3.zero, Vector3.new(-1, 0, 0))
			T.expectEqual(ok, false)
			T.expect(excess > 0, "excès " .. excess)
			T.expect(type(detail) == "string", "détail manquant")
			-- À la verticale : toute direction horizontale touche le corps
			T.expectEqual((ShotRules.checkMeleeOrientation(look, Vector3.zero, Vector3.new(0, 4, 0))), true)
		end)

		T.it("rembobine de now à now - MAX_REWIND, le plus récent d'abord", function()
			local times = ShotRules.meleeRewindTimes(100)
			T.expectEqual(times[1], 100)
			T.expect(math.abs(times[#times] - 99.6) < 1e-6, "dernier instant " .. times[#times])
			T.expectEqual(#times, 9)
		end)

		T.it("teste racine à racine et œil à tête, rien pour deux cibles collées", function()
			local eye, head = Vector3.new(0, 2.5, 0), Vector3.new(0, 1.5, 0)
			local segments = ShotRules.meleeSightSegments(Vector3.zero, Vector3.new(5, 0, 0), eye, head)
			T.expectEqual(#segments, 2)
			T.expectEqual(segments[2].from, eye)
			-- Le segment haut finit sur la tête de la cible, pas au-dessus (mur juste plus haut qu'elle)
			local tip = segments[2].from + segments[2].delta
			T.expect(tip.Y > 1.5 and tip.Y < 1.6, "bout du segment haut à Y = " .. tip.Y)
			T.expect(math.abs(segments[1].delta.Magnitude - (5 - ShotRules.LINE_OF_SIGHT_END_MARGIN)) < 1e-6, "marge")
			local glued = ShotRules.meleeSightSegments(Vector3.zero, Vector3.new(0.2, 0, 0), Vector3.zero, Vector3.zero)
			T.expectEqual(#glued, 0)
		end)

		T.it("livre orientation et ligne de vue de la mêlée en journal seul, gravité moyenne", function()
			T.expectEqual(ShotRules.MODES.orientation, "log")
			T.expectEqual(ShotRules.MODES.meleeLineOfSight, "log")
			T.expectEqual(ShotRules.SEVERITY.orientation, "medium")
			T.expectEqual(ShotRules.SEVERITY.meleeLineOfSight, "medium")
		end)
	end)
end

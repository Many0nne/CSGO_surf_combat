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

	T.describe("ShotRules : instant annoncé borné par le ping (#214)", function()
		T.it("accepte un tir honnête avec 50 et 150 ms de ping", function()
			-- Arrivée = aller simple (ping / 2) + une frame de tir et un Heartbeat serveur (~33 ms)
			for _, ping in { 0.05, 0.15 } do
				local delay = ping / 2 + 0.033
				local ok, detail = ShotRules.checkShotDelay(100 - delay, 100, ping)
				T.expect(ok, string.format("ping %.0f ms : %s", ping * 1000, detail or "?"))
			end
			-- Aller plus lent que le retour : l'aller-retour entier passe encore
			T.expectEqual((ShotRules.checkShotDelay(100 - 0.15, 100, 0.15)), true, "aller = aller-retour")
		end)

		T.it("signale un instant 0,4 s en arrière avec 30 ms de ping (backtrack)", function()
			local ok, detail = ShotRules.checkShotDelay(99.6, 100, 0.03)
			T.expectEqual(ok, false)
			T.expect(string.find(detail or "", "ping 30 ms", 1, true) ~= nil, "détail : " .. tostring(detail))
		end)

		T.it("signale un instant dans le futur au-delà de la tolérance d'horloge", function()
			T.expectEqual((ShotRules.checkShotDelay(100 + ShotRules.CLOCK_TOLERANCE / 2, 100, 0.03)), true)
			T.expectEqual((ShotRules.checkShotDelay(100.2, 100, 0.03)), false)
		end)

		T.it("accepte tout instant sans ping connu", function()
			T.expectEqual((ShotRules.checkShotDelay(99.6, 100, nil)), true)
			T.expectEqual((ShotRules.checkShotDelay(99.6, 100, 0 / 0)), true)
		end)

		T.it("borne = aller-retour + PING_MARGIN, toujours sous le rembobinage maximal à ping courant", function()
			T.expect(math.abs(ShotRules.maxShotDelay(0.05) - (0.05 + ShotRules.PING_MARGIN)) < 1e-9, "borne")
			T.expectEqual(ShotRules.MODES.ping, "log")
			T.expectEqual(ShotRules.SEVERITY.ping, "medium")
		end)
	end)

	T.describe("ShotRules : pose rembobinée (#213)", function()
		-- Cap (rad) d'un personnage tourné vers look, comme CharacterSyncRules.yawOf
		local function yawOf(look: Vector3): number
			return CharacterSyncRules.yawOf(look)
		end

		T.it("tourne la partie avec le cap rembobiné : cible qui a tourné entre le tir et sa réception", function()
			-- Rig serveur : racine en (0, 0, 0) tournée vers +X, main droite 1,5 stud à sa droite (-Z)
			local rootCFrame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0))
			local hand = rootCFrame:PointToWorldSpace(Vector3.new(1.5, 0, 0))
			-- Au tir, la cible était 10 studs plus loin, tournée vers +Z : sa main droite était côté +X
			local pose = { pos = Vector3.new(0, 0, 10), yaw = yawOf(Vector3.new(0, 0, 1)) }
			local center = ShotRules.posedPartCenter(rootCFrame, Vector3.zero, hand, false, pose)
			-- CFrame.Angles, pas CFrame.lookAt : sous Lune, lookAt vers +Z rend un cap -Z (cas dégénéré)
			local seen = (CFrame.new(pose.pos) * CFrame.Angles(0, pose.yaw, 0)):PointToWorldSpace(
				Vector3.new(1.5, 0, 0)
			)
			T.expect((seen - Vector3.new(-1.5, 0, 10)).Magnitude < 1e-4, "main droite d'une cible tournée vers +Z")
			T.expect(
				(center - seen).Magnitude < 1e-4,
				string.format("main à %s, vue à %s", tostring(center), tostring(seen))
			)
			-- Sans cap rembobiné, la main garde l'orientation actuelle (ancien comportement)
			local unposed = ShotRules.posedPartCenter(rootCFrame, Vector3.zero, hand, false, { pos = pose.pos })
			T.expect((unposed - (pose.pos + hand)).Magnitude < 1e-4, "cap inconnu")
		end)

		T.it("baisse les parties hautes d'une cible accroupie au tir, debout maintenant", function()
			local rootCFrame = CFrame.new(Vector3.zero)
			local head, foot = Vector3.new(0, 1.5, 0), Vector3.new(0, -2, 0)
			local crouched = { pos = Vector3.zero, yaw = 0, crouching = true }
			local standing = { pos = Vector3.zero, yaw = 0, crouching = false }
			-- Module à part : la baisse simulée ne fuit pas dans les autres specs, même si un appel lève une erreur
			local Rules = Loader.new():require("src/server/ShotRules")
			Rules.CROUCH_DROP = 2
			local headSeen = Rules.posedPartCenter(rootCFrame, Vector3.zero, head, false, crouched)
			local footSeen = Rules.posedPartCenter(rootCFrame, Vector3.zero, foot, false, crouched)
			-- Et l'inverse : debout au tir, accroupie maintenant (rig serveur baissé)
			local headUp = Rules.posedPartCenter(rootCFrame, Vector3.zero, Vector3.new(0, 0.5, 0), true, standing)
			-- Accroupi inconnu : rien ne bouge
			local unknown = Rules.posedPartCenter(rootCFrame, Vector3.zero, head, nil, crouched)
			T.expect((headSeen - Vector3.new(0, -0.5, 0)).Magnitude < 1e-4, "tête baissée : " .. tostring(headSeen))
			T.expect((footSeen - foot).Magnitude < 1e-4, "pieds immobiles")
			T.expect((headUp - Vector3.new(0, 2.5, 0)).Magnitude < 1e-4, "tête relevée : " .. tostring(headUp))
			T.expect((unknown - head).Magnitude < 1e-4, "accroupi inconnu")
		end)

		T.it("CROUCH_DROP suit la piste 3P : 0 tant que le rig 3P ne s'accroupit pas", function()
			local CharacterConfig = Loader.new():require("src/shared/CharacterConfig")
			if CharacterConfig.ANIMATIONS.CROUCH_IDLE == "" then
				T.expectEqual(ShotRules.CROUCH_DROP, 0)
			else
				-- Piste d'accroupi publiée (#120) : régler CROUCH_DROP sur la baisse de la tête qu'elle montre
				T.expect(ShotRules.CROUCH_DROP > 0, "CROUCH_DROP à régler sur la piste CROUCH_IDLE publiée")
			end
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
				ShotRules.countShot(mag, 10)
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

		T.it("accepte tout cap pour une cible à l'aplomb, nettement plus bas (tireur sur sa tête)", function()
			-- 0,5 stud derrière, 5 studs plus bas : le regard vers le bas touche son corps
			local ok = ShotRules.checkMeleeOrientation(Vector3.new(1, 0, 0), Vector3.zero, Vector3.new(-0.5, -5, 0))
			T.expectEqual(ok, true)
			-- À même hauteur, collée dans le dos : toujours refusée
			ok = ShotRules.checkMeleeOrientation(Vector3.new(1, 0, 0), Vector3.zero, Vector3.new(-1.5, 0, 0))
			T.expectEqual(ok, false)
		end)

		T.it("n'ouvre pas l'angle pour une cible proche à l'horizontale mais loin en hauteur (rampe)", function()
			-- 2,5 studs à l'horizontale (hors de l'aplomb), 6 studs plus bas, 150° du cap : permis 70° + asin(2 / 6,5) ≈ 88°
			local yaw = math.rad(150)
			local target = Vector3.new(math.cos(yaw) * 2.5, -6, math.sin(yaw) * 2.5)
			T.expectEqual((ShotRules.checkMeleeOrientation(Vector3.new(1, 0, 0), Vector3.zero, target)), false)
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

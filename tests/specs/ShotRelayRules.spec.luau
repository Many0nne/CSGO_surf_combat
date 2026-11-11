-- Relais des tirs aux autres clients (#156) : tirs relayés, cadence, bornes, destinataires.
return function(T, Loader)
	local ShotRelayRules = Loader.new():require("src/server/ShotRelayRules")
	local WeaponConfig = Loader.new():require("src/shared/WeaponConfig")
	local RemoteGuard = Loader.new():require("src/server/RemoteGuard")
	local NetworkProtocol = Loader.new():require("src/shared/NetworkProtocol")
	local MovementConfig = Loader.new():require("src/shared/MovementConfig")
	local ShotRules = Loader.new():require("src/server/ShotRules")

	local AWP_DELAY = WeaponConfig.Weapons.AWP.FireDelay
	local ROOT = Vector3.new(100, 10, -50)
	local EYE = ROOT + Vector3.new(0, 2.5, 0)
	local FORWARD = Vector3.new(0, 0, -1)

	-- Cette méthode permet de proposer un tir d'AWP honnête (origine aux yeux, direction unitaire) lorsqu'un test ne
	-- fait varier qu'un paramètre.
	local function admit(state, key, now: number, overrides: { [string]: any }?)
		local o = overrides or {}
		local weapon = if o.weapon ~= nil then o.weapon else "AWP"
		if o.noWeapon then
			weapon = nil
		end
		local shooterPos = if o.noShooter then nil else (o.shooterPos or ROOT)
		return ShotRelayRules.admit(state, key, weapon, o.origin or EYE, o.direction or FORWARD, shooterPos, now)
	end

	T.describe("ShotRelayRules.admit : tirs relayés (#156)", function()
		T.it("relaie un tir d'AWP honnête, touché ou manqué (rien ne dépend de la touche)", function()
			local state = ShotRelayRules.new()
			T.expectEqual((admit(state, "joueur", 10)), true)
		end)

		T.it("relaie chaque tir à la cadence de l'arme, et refuse un tir trop tôt", function()
			local state = ShotRelayRules.new()
			local now = 10
			for i = 1, 5 do
				T.expectEqual((admit(state, "joueur", now)), true, "tir " .. i)
				local ok, reason = admit(state, "joueur", now + 0.5)
				T.expectEqual(ok, false, "tir à 0,5 s du précédent " .. i)
				T.expect(
					type(reason) == "string" and string.find(reason, "cadence") ~= nil,
					"raison : " .. tostring(reason)
				)
				now += AWP_DELAY
			end
		end)

		T.it("accepte un tir arrivé un peu tôt (gigue), à la tolérance près", function()
			local state = ShotRelayRules.new()
			admit(state, "joueur", 10)
			local tol = ShotRelayRules.CADENCE_TOLERANCE
			T.expectEqual((admit(state, "joueur", 10 + AWP_DELAY - tol + 0.01)), true, "dans la tolérance")
			local state2 = ShotRelayRules.new()
			admit(state2, "joueur", 10)
			T.expectEqual((admit(state2, "joueur", 10 + AWP_DELAY - tol - 0.01)), false, "hors tolérance")
		end)

		T.it("un tir écarté ne relance pas la cadence (le spam ne retarde pas le vrai tir)", function()
			local state = ShotRelayRules.new()
			admit(state, "joueur", 10)
			for k = 1, 20 do
				admit(state, "joueur", 10 + k * 0.05)
			end
			T.expectEqual((admit(state, "joueur", 10 + AWP_DELAY)), true)
		end)

		T.it("borne le débit d'un spammeur à la cadence de l'arme", function()
			local state = ShotRelayRules.new()
			local relayed = 0
			for k = 0, 199 do -- 20 tirs/s pendant 10 s
				if admit(state, "tricheur", k * 0.05) then
					relayed += 1
				end
			end
			local max = math.ceil(10 / (AWP_DELAY - ShotRelayRules.CADENCE_TOLERANCE)) + 1
			T.expect(relayed <= max, string.format("%d tirs relayés (max %d)", relayed, max))
			T.expect(relayed >= 6, string.format("%d tirs relayés, au moins un par cadence", relayed))
		end)

		T.it("garde une cadence par tireur", function()
			local state = ShotRelayRules.new()
			T.expectEqual((admit(state, "a", 10)), true)
			T.expectEqual((admit(state, "b", 10)), true, "un autre tireur au même instant")
		end)

		T.it("oublie la cadence à la réapparition", function()
			local state = ShotRelayRules.new()
			admit(state, "joueur", 10)
			ShotRelayRules.forget(state, "joueur")
			T.expectEqual((admit(state, "joueur", 10.1)), true)
		end)

		T.it("refuse sans arme à distance en main (couteau, arme inconnue, rien)", function()
			local state = ShotRelayRules.new()
			T.expectEqual((admit(state, "joueur", 10, { weapon = "M9Bayonet" })), false, "couteau")
			T.expectEqual((admit(state, "joueur", 10, { weapon = "Lance-roquettes" })), false, "arme inconnue")
			T.expectEqual((admit(state, "joueur", 10, { noWeapon = true })), false, "sans arme")
		end)

		T.it("refuse une forme impossible : direction non unitaire ou nulle, coordonnées absurdes ou NaN", function()
			for label, o in
				{
					nonUnitaire = { direction = Vector3.new(0, 0, -2) },
					nulle = { direction = Vector3.zero },
					origineNaN = { origin = Vector3.new(0 / 0, 0, 0) },
					directionNaN = { direction = Vector3.new(0 / 0, 0, 0) },
					horsBornes = { origin = Vector3.new(2e5, 0, 0), shooterPos = Vector3.new(2e5, 0, 0) },
					pasUnVecteur = { origin = "ici" },
				}
			do
				local state = ShotRelayRules.new()
				T.expectEqual((admit(state, "joueur", 10, o)), false, label)
			end
		end)

		T.it("borne l'origine autour du tireur, sans écarter un tireur rapide en avance de sa latence", function()
			local state = ShotRelayRules.new()
			local ahead = ROOT + Vector3.new(ShotRelayRules.ORIGIN_MAX - 1, 0, 0)
			T.expectEqual((admit(state, "a", 10, { origin = ahead })), true, "juste dans la borne")
			local far = ROOT + Vector3.new(ShotRelayRules.ORIGIN_MAX + 1, 0, 0)
			T.expectEqual((admit(state, "b", 10, { origin = far })), false, "juste au-delà")
			T.expect(
				ShotRelayRules.ORIGIN_MAX >= ShotRules.ORIGIN_BASE + MovementConfig.MAX_HORIZONTAL_SPEED * 0.3,
				"borne large : surf à 420 studs/s et 0,3 s de latence"
			)
		end)

		T.it("refuse un tireur sans position (mort, personnage absent)", function()
			local state = ShotRelayRules.new()
			T.expectEqual((admit(state, "joueur", 10, { noShooter = true })), false)
		end)

		T.it("ne garde pas un tireur disparu en mémoire (clés faibles)", function()
			local state = ShotRelayRules.new()
			T.expectEqual(getmetatable(state.last).__mode, "k")
		end)
	end)

	T.describe("ShotRelayRules.recipients (#156)", function()
		T.it("tous les joueurs sauf le tireur", function()
			local out = ShotRelayRules.recipients({ "a", "b", "c" }, "b")
			T.expectEqual(#out, 2)
			T.expectEqual(out[1], "a")
			T.expectEqual(out[2], "c")
		end)

		T.it("tous les joueurs pour un tir de bot (pas de joueur tireur)", function()
			T.expectEqual(#ShotRelayRules.recipients({ "a", "b" }, nil), 2)
		end)

		T.it("personne quand le tireur est seul", function()
			T.expectEqual(#ShotRelayRules.recipients({ "a" }, "a"), 0)
		end)
	end)

	T.describe("RemoteGuard : règle de ShotFired (#156)", function()
		local N = NetworkProtocol.Names

		T.it("accepte origine, direction et instant du tir (#216), refuse un autre type", function()
			local guard = RemoteGuard.new()
			T.expectEqual((guard:check("p", N.SHOT_FIRED, 0, EYE, FORWARD, 100)), "ok")
			T.expectEqual((guard:check("p", N.SHOT_FIRED, 1, EYE, "devant", 100)), "malformed")
			T.expectEqual((guard:check("p", N.SHOT_FIRED, 2, nil, FORWARD, 100)), "malformed")
			T.expectEqual((guard:check("p", N.SHOT_FIRED, 3, EYE, FORWARD)), "malformed", "sans instant")
			T.expectEqual((guard:check("p", N.SHOT_FIRED, 4, EYE, FORWARD, 0 / 0)), "malformed", "instant NaN")
		end)

		T.it("ne limite jamais un tireur honnête d'AWP", function()
			local guard = RemoteGuard.new()
			for i = 0, 40 do
				T.expectEqual((guard:check("p", N.SHOT_FIRED, i * AWP_DELAY, EYE, FORWARD, 100 + i)), "ok", "tir " .. i)
			end
		end)
	end)
end

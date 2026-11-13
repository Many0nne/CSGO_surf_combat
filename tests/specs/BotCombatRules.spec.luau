-- Combat des bots (#143) : direction du tir depuis le regard réel, dispersion, délai de grâce, choix de l'arme,
-- conditions d'un tir.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/BotCombatRules")
	local Config = Loader.new():require("src/shared/BotConfig")

	-- Cette méthode permet de rejouer une suite de tirages fixe lorsqu'un test a besoin de hasard.
	local function sequence(values: { number }): () -> number
		local i = 0
		return function()
			i = i % #values + 1
			return values[i]
		end
	end

	-- Cette méthode permet de mesurer l'angle entre deux directions lorsqu'un test vérifie une dispersion (°).
	local function angle(a: Vector3, b: Vector3): number
		return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
	end

	local function fireInput(overrides: { [string]: any })
		local input = {
			visible = true,
			inGrace = false,
			ready = true,
			yawError = 0,
			distance = 50,
			range = Config.FIRE_RANGE,
		}
		for k, v in overrides do
			input[k] = v
		end
		return input
	end

	T.describe("BotCombatRules", function()
		T.it("mesure l'écart entre son cap et la cible", function()
			local eye = Vector3.zero
			-- Cap 0 : regarde vers -Z
			T.expectEqual(math.abs(Rules.yawError(eye, 0, Vector3.new(0, 30, -10))) < 1e-3, true, "droit devant")
			T.expectEqual(math.abs(Rules.yawError(eye, 0, Vector3.new(10, 0, -10)) - 45) < 1e-3, true, "45°")
			T.expectEqual(math.abs(Rules.yawError(eye, 0, Vector3.new(0, 0, 10)) - 180) < 1e-3, true, "derrière")
			T.expectEqual(math.abs(Rules.yawError(eye, 350, Vector3.new(0, 0, -10)) - 10) < 1e-3, true, "passe par 0")
		end)

		T.it("tire dans la direction de son regard réel, pas droit sur la cible", function()
			local eye = Vector3.zero
			local target = Vector3.new(0, 10, -100)
			local aligned = Rules.aimDirection(eye, 0, target)
			T.expectEqual(angle(aligned, target) < 1e-4, true, "cap aligné : droit sur la cible")
			local late = Rules.aimDirection(eye, 20, target)
			T.expectEqual(math.abs(angle(late, target) - 20) < 0.5, true, "cap en retard de 20° : tir à côté")
			T.expectEqual(math.abs(late.Y - aligned.Y) < 1e-6, true, "hauteur visée gardée")
		end)

		T.it("disperse selon la vitesse de la cible, plafonnée", function()
			T.expectEqual(Rules.spread(0), Config.AIM_SPREAD, "cible immobile")
			T.expectEqual(Rules.spread(30) > Rules.spread(0), true, "cible rapide plus dure")
			T.expectEqual(Rules.spread(10000), Config.AIM_SPREAD_MAX, "plafond")
		end)

		T.it("reste dans le cône de dispersion", function()
			local dir = Vector3.new(0, 0, -1)
			for _, rolls in { { 0, 0 }, { 0.5, 0.25 }, { 0.999, 0.7 }, { 1, 0.5 } } do
				local scattered = Rules.scatter(dir, 3, sequence(rolls))
				T.expectEqual(angle(dir, scattered) <= 3 + 1e-4, true, "dans les 3°")
				T.expectEqual(math.abs(scattered.Magnitude - 1) < 1e-6, true, "unitaire")
			end
			T.expectEqual(Rules.scatter(dir, 0, sequence({ 0.9 })), dir, "sans dispersion")
			local vertical = Rules.scatter(Vector3.new(0, 1, 0), 2, sequence({ 1, 0.3 }))
			T.expectEqual(angle(Vector3.new(0, 1, 0), vertical) <= 2 + 1e-4, true, "tir vertical")
		end)

		T.it("ne tire pas sur un participant qui vient d'apparaître", function()
			T.expectEqual(Rules.inSpawnGrace(100, 100 + Config.SPAWN_GRACE - 0.1), true, "pendant le délai")
			T.expectEqual(Rules.inSpawnGrace(100, 100 + Config.SPAWN_GRACE), false, "délai écoulé")
			T.expectEqual(Rules.inSpawnGrace(nil, 100), false, "apparition inconnue")
		end)

		T.it("compte son temps de réaction à partir de la fin du délai de grâce (#298)", function()
			local graceEnd = 100 + Config.SPAWN_GRACE
			T.expectEqual(Rules.reactionStart(101, 100), graceEnd, "vue pendant la grâce : réaction à sa fin")
			T.expectEqual(
				Rules.reactionStart(graceEnd + 2, 100),
				graceEnd + 2,
				"vue après la grâce : dès qu'il la voit"
			)
			T.expectEqual(Rules.reactionStart(101, nil), 101, "apparition inconnue : dès qu'il la voit")
			-- Vue dès l'apparition : le tir ne part qu'après REACTION_TIME + COMBAT_AIM_TIME, une fois la grâce finie
			local BehaviorRules = Loader.new():require("src/shared/BotBehaviorRules")
			local ready = Config.REACTION_TIME + Config.COMBAT_AIM_TIME
			local _, fire = BehaviorRules.combatGaze(graceEnd + 0.01 - Rules.reactionStart(100, 100), nil)
			T.expectEqual(fire, false, "pas de tir juste à la fin de la grâce")
			_, fire = BehaviorRules.combatGaze(graceEnd + ready + 1e-6 - Rules.reactionStart(100, 100), nil)
			T.expectEqual(fire, true, "tir après réaction et visée comptées depuis la fin de la grâce")
		end)

		T.it("sort le couteau au contact, reprend le fusil à distance", function()
			T.expectEqual(Rules.chooseWeapon(Rules.RIFLE, Config.KNIFE_RANGE - 1), Rules.KNIFE, "au contact")
			T.expectEqual(Rules.chooseWeapon(Rules.RIFLE, Config.KNIFE_DROP_RANGE - 1), Rules.RIFLE, "garde le fusil")
			T.expectEqual(Rules.chooseWeapon(Rules.KNIFE, Config.KNIFE_DROP_RANGE - 1), Rules.KNIFE, "garde le couteau")
			T.expectEqual(Rules.chooseWeapon(Rules.KNIFE, Config.KNIFE_DROP_RANGE + 1), Rules.RIFLE, "à distance")
			T.expectEqual(Rules.chooseWeapon(Rules.KNIFE, nil), Rules.RIFLE, "sans cible")
		end)

		T.it("ne tire que sur une cible vue, hors grâce, arme prête, à portée et regard tourné", function()
			T.expectEqual(Rules.canFire(fireInput({})), true, "tout est réuni")
			T.expectEqual(Rules.canFire(fireInput({ visible = false })), false, "hors de vue (champ, obstacle)")
			T.expectEqual(Rules.canFire(fireInput({ inGrace = true })), false, "délai de grâce")
			T.expectEqual(Rules.canFire(fireInput({ ready = false })), false, "arme pas prête")
			T.expectEqual(Rules.canFire(fireInput({ distance = Config.FIRE_RANGE + 1 })), false, "hors de portée")
			T.expectEqual(
				Rules.canFire(fireInput({ yawError = Config.FIRE_YAW_TOLERANCE + 1 })),
				false,
				"pas encore tourné vers elle"
			)
		end)

		T.it("ne tire pas quand le tir est interdit (bots passifs, DebugBotsPassive)", function()
			T.expectEqual(Rules.canFire(fireInput({ holdFire = true })), false, "tir interdit")
			T.expectEqual(Rules.canFire(fireInput({ holdFire = false })), true, "tir rétabli")
		end)

		T.it("se règle sans toucher au code : la difficulté est dans la config", function()
			for _, key in
				{
					"REACTION_TIME",
					"COMBAT_AIM_TIME",
					"COMBAT_TURN_RATE",
					"AIM_SPREAD",
					"AIM_SPREAD_SPEED",
					"SPAWN_GRACE",
				}
			do
				T.expectEqual(type(Config[key]), "number", key)
			end
			local fireDelay = Loader.new():require("src/shared/WeaponConfig").Weapons.AWP.FireDelay
			T.expectEqual(Config.COMBAT_COOLDOWN >= fireDelay, true, "regard rendu le temps du réarmement de l'AWP")
		end)
	end)
end

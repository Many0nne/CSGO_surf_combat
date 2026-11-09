-- Règles des bots (#139) : marche d'essai, nom, nombre demandé en Studio.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/BotRules")
	local Config = Loader.new():require("src/shared/BotConfig")

	local function near(a: number, b: number, msg: string?)
		T.expectEqual(math.abs(a - b) < 1e-6, true, (msg or "") .. " : " .. tostring(a) .. " ≠ " .. tostring(b))
	end

	T.describe("BotRules", function()
		T.it("suit la convention de cap de la caméra FPS", function()
			local north = Rules.headingDir(0)
			near(north.X, 0, "cap 0")
			near(north.Z, -1, "cap 0 vers -Z")
			local east = Rules.headingDir(90)
			near(east.X, 1, "cap 90 vers +X")
			local look = Rules.headingRotation(90).LookVector
			near(look.X, east.X, "la racine regarde où il marche")
			near(look.Z, east.Z, "la racine regarde où il marche")
		end)

		T.it("tire le délai du prochain saut dans les bornes", function()
			near(Rules.nextJumpDelay(0), Config.WANDER_JUMP_MIN)
			near(Rules.nextJumpDelay(1), Config.WANDER_JUMP_MAX)
		end)

		T.it("compte le temps gêné seulement au sol et lent", function()
			local wish = 20
			local slow = wish * Config.STUCK_SPEED_RATIO * 0.5
			T.expectEqual(Rules.stuckTime(0.1, true, slow, wish, 0.1) > 0.19, true, "au sol et lent : cumule")
			T.expectEqual(Rules.stuckTime(0.3, true, wish, wish, 0.1), 0, "à pleine vitesse : remis à 0")
			T.expectEqual(Rules.stuckTime(0.3, false, 0, wish, 0.1), 0, "en l'air : jamais gêné")
			T.expectEqual(Rules.stuckTime(0.3, true, 0, 0, 0.1), 0, "sans envie d'avancer : jamais gêné")
		end)

		T.it("fait demi-tour après STUCK_TIME", function()
			T.expectEqual(Rules.shouldTurn(Config.STUCK_TIME - 0.01), false)
			T.expectEqual(Rules.shouldTurn(Config.STUCK_TIME), true)
		end)

		T.it("tourne d'un angle borné et reste dans [0, 360[", function()
			near(Rules.turnedYaw(0, 0), Config.TURN_MIN)
			near(Rules.turnedYaw(300, 1), (300 + Config.TURN_MAX) % 360)
			T.expectEqual(Rules.turnedYaw(350, 0.5) < 360, true)
		end)

		T.it("donne le premier nom libre, puis un nom numéroté", function()
			T.expectEqual(Rules.pickName({}), Config.NAMES[1])
			T.expectEqual(Rules.pickName({ [Config.NAMES[1]] = true }), Config.NAMES[2])
			local all = {}
			for _, name in Config.NAMES do
				all[name] = true
			end
			local extra = Rules.pickName(all)
			T.expectEqual(all[extra], nil, "pas un nom déjà pris")
			all[extra] = true
			T.expectEqual(Rules.pickName(all) ~= extra, true, "deux noms numérotés différents")
		end)

		T.it("borne le nombre de bots demandé", function()
			T.expectEqual(Rules.requestedCount(nil), 0)
			T.expectEqual(Rules.requestedCount("3"), 0)
			T.expectEqual(Rules.requestedCount(0 / 0), 0, "NaN")
			T.expectEqual(Rules.requestedCount(2.7), 2)
			T.expectEqual(Rules.requestedCount(-1), 0)
			T.expectEqual(Rules.requestedCount(99), Config.MAX_BOTS)
		end)
	end)
end

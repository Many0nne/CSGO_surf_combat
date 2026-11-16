-- Bruits de pas (#146) : quand un personnage fait du bruit, voix d'un pas, pas des autres joués.
return function(T, Loader)
	local Rules = Loader.new():require("src/shared/FootstepRules")
	local Config = Loader.new():require("src/shared/MovementConfig")
	local DT = 1 / 64

	-- Cette méthode permet de faire avancer un état pendant duration secondes à vitesse constante lorsqu'un test simule
	-- un déplacement ; renvoie le nombre de pas et d'atterrissages.
	local function run(state, duration: number, grounded: boolean, speed: number): (number, number)
		local steps, lands = 0, 0
		for _ = 1, math.floor(duration / DT + 0.5) do
			local kind = Rules.update(state, DT, grounded, speed * DT)
			if kind == "step" then
				steps += 1
			elseif kind == "land" then
				lands += 1
			end
		end
		return steps, lands
	end

	T.describe("FootstepRules.update (#146)", function()
		T.it("la course fait 3 pas par seconde", function()
			local steps = run(Rules.new(), 2, true, Config.RUN_SPEED)
			T.expectEqual(steps, 6)
		end)

		T.it("la course avec l'AWP (0,75) s'entend", function()
			local steps = run(Rules.new(), 2, true, Config.RUN_SPEED * 0.75)
			T.expect(steps >= 4, tostring(steps))
		end)

		T.it("le premier pas suit de près le départ de la course", function()
			local state = Rules.new()
			local first = nil
			for i = 1, 64 do
				if Rules.update(state, DT, true, Config.RUN_SPEED * DT) == "step" then
					first = i * DT
					break
				end
			end
			T.expect(first ~= nil and first <= Rules.FIRST_STEP / Config.RUN_SPEED + DT, tostring(first))
			-- Puis une foulée entière jusqu'au suivant
			local steps = run(state, Rules.STRIDE / Config.RUN_SPEED - 2 * DT, true, Config.RUN_SPEED)
			T.expectEqual(steps, 0)
		end)

		T.it("la marche et l'accroupi sont silencieux", function()
			T.expectEqual(run(Rules.new(), 3, true, Config.WALK_SPEED), 0)
			T.expectEqual(run(Rules.new(), 3, true, Config.CROUCH_SPEED), 0)
		end)

		T.it("rien en l'air ni en surf, même très vite", function()
			local steps, lands = run(Rules.new(), 3, false, 200)
			T.expectEqual(steps, 0)
			T.expectEqual(lands, 0)
		end)

		T.it("un atterrissage après un saut fait un bruit, une marche franchie non", function()
			local state = Rules.new()
			run(state, 0.5, false, Config.WALK_SPEED)
			T.expectEqual(Rules.update(state, DT, true, 0), "land")
			-- Une seule fois
			T.expectEqual(Rules.update(state, DT, true, 0), nil)
			local short = Rules.new()
			run(short, 0.1, false, Config.RUN_SPEED)
			T.expectEqual(Rules.update(short, DT, true, 0), nil)
		end)

		T.it("l'atterrissage s'entend même en marchant (saut depuis la marche)", function()
			local state = Rules.new()
			run(state, 0.4, false, Config.WALK_SPEED)
			local _, lands = run(state, 1, true, Config.WALK_SPEED)
			T.expectEqual(lands, 1)
		end)

		T.it("un bond (téléportation) ne compte que pour une foulée", function()
			local state = Rules.new()
			T.expectEqual(Rules.update(state, 0.05, true, 500), "step")
			T.expectEqual(Rules.update(state, 0.05, true, 1.5), nil)
		end)

		T.it("temps nul : pas de division par zéro", function()
			T.expectEqual(Rules.update(Rules.new(), 0, true, 1), nil)
		end)
	end)

	T.describe("FootstepRules.voice (#146)", function()
		T.it("la hauteur reste dans ± PITCH_SPREAD, l'atterrissage est plus grave et plus fort", function()
			for _, r in { 0, 0.5, 1 } do
				local pitch, gain = Rules.voice("step", r)
				T.expect(math.abs(pitch - 1) <= Rules.PITCH_SPREAD + 1e-9, tostring(pitch))
				T.expectEqual(gain, 1)
				local landPitch, landGain = Rules.voice("land", r)
				T.expect(landPitch < pitch, "atterrissage pas plus grave")
				T.expect(landGain > 1, "atterrissage pas plus fort")
			end
		end)
	end)

	T.describe("FootstepRules.shouldPlay (#146)", function()
		local walker, me = {}, {}

		T.it("joue le pas d'un autre en partie, mort ou en fin de manche", function()
			for _, state in { "SPAWNING", "IN_ROUND", "DEAD", "RESULT" } do
				T.expectEqual(Rules.shouldPlay(walker, me, state, 0), true, state)
			end
		end)

		T.it("pas ses propres pas relayés, ni au menu, ni au-delà de MAX_ACTIVE", function()
			T.expectEqual(Rules.shouldPlay(me, me, "IN_ROUND", 0), false)
			T.expectEqual(Rules.shouldPlay(walker, me, "MENU", 0), false)
			T.expectEqual(Rules.shouldPlay(walker, me, nil, 0), false)
			T.expectEqual(Rules.shouldPlay(nil, me, "IN_ROUND", 0), false)
			T.expectEqual(Rules.shouldPlay(walker, me, "IN_ROUND", Rules.MAX_ACTIVE), false)
		end)

		T.it("la portée des pas reste sous celle des tirs entendus par les bots", function()
			local BotConfig = Loader.new():require("src/shared/BotConfig")
			T.expect(Rules.RANGE <= BotConfig.HEARING_RADIUS, tostring(Rules.RANGE))
			T.expect(Rules.ROLLOFF_MIN < Rules.RANGE, "atténuation inversée")
			T.expect(Rules.OWN_VOLUME < Rules.VOLUME, "ses pas pas plus bas")
		end)
	end)
end

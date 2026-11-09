return function(T, Loader)
	local StepTiming = Loader.new():require("src/shared/StepTiming")
	local TICK = StepTiming.TICK

	-- Cette méthode permet de rejouer une suite de frames lorsqu'un test compare le temps simulé à différents FPS :
	-- renvoie le nombre total de ticks joués.
	local function run(dt: number, frames: number): number
		local acc, total = 0, 0
		for _ = 1, frames do
			local ticks
			ticks, acc = StepTiming.advance(acc, dt)
			total += ticks
		end
		return total
	end

	T.describe("StepTiming.advance", function()
		T.it("tick à 64 Hz", function()
			T.expectNear(TICK, 1 / 64, 1e-12)
		end)

		T.it("frame plus courte qu'un tick : aucun tick, le temps attend et alpha avance", function()
			local ticks, acc, alpha = StepTiming.advance(0, TICK / 4)
			T.expectEqual(ticks, 0)
			T.expectNear(acc, TICK / 4, 1e-12)
			T.expectNear(alpha, 0.25, 1e-9)
		end)

		T.it("le temps en attente complète un tick à la frame suivante", function()
			local ticks, acc = StepTiming.advance(TICK * 0.75, TICK / 2)
			T.expectEqual(ticks, 1)
			T.expectNear(acc, TICK / 4, 1e-12)
		end)

		T.it("frame lente : plusieurs ticks, rien n'est perdu", function()
			local ticks, acc = StepTiming.advance(0, TICK * 3.5)
			T.expectEqual(ticks, 3)
			T.expectNear(acc, TICK / 2, 1e-12)
		end)

		T.it("exactement un tick malgré l'arrondi flottant", function()
			local ticks, acc, alpha = StepTiming.advance(0, 1 / 64)
			T.expectEqual(ticks, 1)
			T.expectNear(acc, 0, 1e-12)
			T.expectNear(alpha, 0, 1e-9)
		end)

		T.it("gel du client : plafonné à MAX_TICKS, le retard est abandonné", function()
			local ticks, acc, alpha = StepTiming.advance(0, 2)
			T.expectEqual(ticks, StepTiming.MAX_TICKS)
			T.expectEqual(acc, 0)
			T.expectEqual(alpha, 0)
		end)

		T.it("dt nul ou négatif : aucun tick, temps en attente conservé", function()
			local ticks, acc = StepTiming.advance(TICK / 3, 0)
			T.expectEqual(ticks, 0)
			T.expectNear(acc, TICK / 3, 1e-12)
			T.expectEqual((StepTiming.advance(0, -0.01)), 0)
		end)

		T.it("équité : 1 s jouée à 30, 60, 144 ou 240 FPS donne les mêmes 64 ticks", function()
			for _, fps in { 30, 60, 144, 240 } do
				local total = run(1 / fps, fps)
				T.expect(math.abs(total - 64) <= 1, `{fps} FPS : {total} ticks`)
			end
		end)
	end)
end

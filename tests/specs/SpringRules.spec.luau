-- Ressort du balancement du viewmodel (#304) : borné à basse cadence, identique à l'ancien schéma à 60 i/s.
return function(T, Loader)
	local SpringRules = Loader.new():require("src/shared/SpringRules")

	local SPEED, DAMPING = 18, 1 -- ViewmodelSystem.SWAY_SPEED / SWAY_DAMPING
	local SWAY_MAX = math.rad(6)

	-- Ancien schéma de ViewmodelSystem.springUpdate (un seul pas Euler semi-implicite de durée dt), référence "avant".
	local function oldStep(pos: Vector3, vel: Vector3, target: Vector3, dt: number): (Vector3, Vector3)
		local accel = (target - pos) * (SPEED * SPEED) - vel * (2 * DAMPING * SPEED)
		vel = vel + accel * dt
		pos = pos + vel * dt
		return pos, vel
	end

	-- Cette méthode permet de simuler une rotation continue lorsqu'on veut le pic de |pos| à une cadence donnée.
	local function peakAt(fps: number, stepFn): number
		local dt = 1 / fps
		local pos, vel = Vector3.zero, Vector3.zero
		local peak = 0
		for i = 1, math.floor(fps * 4) do
			-- la cible alterne entre les deux bornes toutes les 0,5 s : pire cas d'une caméra qui tourne sans arrêt
			local sign = (math.floor(i * dt / 0.5) % 2 == 0) and 1 or -1
			local target = Vector3.new(sign * SWAY_MAX, -sign * SWAY_MAX, 0)
			pos, vel = stepFn(pos, vel, target, dt)
			peak = math.max(peak, pos.Magnitude)
		end
		return peak
	end

	local function newStep(pos, vel, target, dt)
		return SpringRules.step(pos, vel, target, SPEED, DAMPING, dt)
	end

	T.describe("SpringRules.step (#304)", function()
		T.it("l'ancien schéma diverge à 10 i/s (le bug)", function()
			local peak = peakAt(10, function(pos, vel, target, dt)
				return oldStep(pos, vel, target, dt)
			end)
			T.expect(peak > 100 * SWAY_MAX, tostring(peak))
		end)

		for _, fps in { 10, 15, 22, 30, 60, 144 } do
			T.it(`reste borné à {fps} i/s pendant une rotation continue`, function()
				local peak = peakAt(fps, newStep)
				-- deux axes à ±SWAY_MAX : norme max sqrt(2)*SWAY_MAX, marge de 10 % pour le dépassement
				T.expect(peak <= math.sqrt(2) * SWAY_MAX * 1.1, `{peak} > {math.sqrt(2) * SWAY_MAX * 1.1}`)
			end)
		end

		T.it("à 60 i/s, même réponse que l'ancien schéma, pas pour pas", function()
			local dt = 1 / 60
			local pa, va = Vector3.zero, Vector3.zero
			local pb, vb = Vector3.zero, Vector3.zero
			local target = Vector3.new(SWAY_MAX, -SWAY_MAX / 2, 0)
			for _ = 1, 120 do
				pa, va = oldStep(pa, va, target, dt)
				pb, vb = SpringRules.step(pb, vb, target, SPEED, DAMPING, dt)
				T.expect((pa - pb).Magnitude < 1e-9 and (va - vb).Magnitude < 1e-9, `{pa} vs {pb}`)
			end
		end)

		T.it("converge vers la cible à toute cadence", function()
			local target = Vector3.new(SWAY_MAX, 0, 0)
			for _, fps in { 10, 15, 30, 60 } do
				local pos, vel = Vector3.zero, Vector3.zero
				for _ = 1, fps * 3 do
					pos, vel = SpringRules.step(pos, vel, target, SPEED, DAMPING, 1 / fps)
				end
				T.expect((pos - target).Magnitude < 1e-3, `{fps} i/s : {pos}`)
			end
		end)

		T.it("un dt énorme (saccade) reste borné et un dt nul ne change rien", function()
			local target = Vector3.new(SWAY_MAX, SWAY_MAX, 0)
			local pos, vel = SpringRules.step(Vector3.zero, Vector3.zero, target, SPEED, DAMPING, 5)
			T.expect(pos.Magnitude <= math.sqrt(2) * SWAY_MAX * 1.1, tostring(pos))
			local p2, v2 = SpringRules.step(pos, vel, target, SPEED, DAMPING, 0)
			T.expect(p2 == pos and v2 == vel)
		end)
	end)
end

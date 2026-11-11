return function(T, Loader)
	local PH = Loader.new():require("src/shared/PositionHistory")

	-- Historique rempli avec un relevé tous les 0,05 s sur l'axe X (x = 100 * t), de t0 à t0 + count * 0,05.
	local function filled(t0: number, count: number)
		local h = PH.new()
		for i = 0, count - 1 do
			local t = t0 + i * 0.05
			PH.record(h, t, Vector3.new(100 * t, 0, 0))
		end
		return h
	end

	T.describe("PositionHistory constantes", function()
		T.it("MAX_REWIND tient dans la durée du tampon", function()
			T.expect(PH.MAX_REWIND <= PH.DURATION)
		end)
	end)

	T.describe("PositionHistory.sampleAt", function()
		T.it("renvoie nil pour un tampon vide", function()
			T.expectEqual(PH.sampleAt(PH.new(), 5, 5), nil)
		end)

		T.it("renvoie l'unique relevé quel que soit t", function()
			local h = PH.new()
			PH.record(h, 10, Vector3.new(1, 2, 3))
			T.expectEqual(PH.sampleAt(h, 9.9, 10), Vector3.new(1, 2, 3))
			T.expectEqual(PH.sampleAt(h, 10, 10), Vector3.new(1, 2, 3))
		end)

		T.it("interpole entre deux relevés", function()
			local h = filled(10, 5) -- relevés à 10, 10.05, ..., 10.2
			local p = PH.sampleAt(h, 10.125, 10.2)
			T.expectNear(p.X, 1012.5, 1e-3)
		end)

		T.it("renvoie exactement un relevé quand t tombe dessus", function()
			local h = filled(10, 5)
			T.expectNear(PH.sampleAt(h, 10.1, 10.2).X, 1010, 1e-3)
		end)

		T.it("renvoie le plus récent quand t dépasse le dernier relevé", function()
			local h = filled(10, 5)
			T.expectNear(PH.sampleAt(h, 11, 10.5).X, 1020, 1e-3)
		end)

		T.it("renvoie le plus ancien quand t précède tous les relevés", function()
			local h = filled(10, 5)
			T.expectNear(PH.sampleAt(h, 9, 10.2).X, 1000, 1e-3)
		end)

		T.it("borne t à now - MAX_REWIND", function()
			local h = filled(10, 20) -- relevés de 10 à 10.95
			local now = 10.95
			local clamped = PH.sampleAt(h, now - 5, now)
			local atLimit = PH.sampleAt(h, now - PH.MAX_REWIND, now)
			T.expectEqual(clamped, atLimit)
			T.expectNear(atLimit.X, 100 * (now - PH.MAX_REWIND), 1e-3)
		end)

		T.it("borne t à now quand il est dans le futur", function()
			local h = filled(10, 20)
			T.expectEqual(PH.sampleAt(h, 99, 10.5), PH.sampleAt(h, 10.5, 10.5))
		end)
	end)

	T.describe("PositionHistory.sampleAt (cas limites)", function()
		T.it("ne traverse pas un trou entre deux relevés trop éloignés", function()
			local h = PH.new()
			PH.record(h, 10, Vector3.new(0, 0, 0))
			PH.record(h, 10.3, Vector3.new(100, 0, 0))
			T.expectEqual(PH.sampleAt(h, 10.1, 10.3), Vector3.new(0, 0, 0))
			T.expectEqual(PH.sampleAt(h, 10.2, 10.3), Vector3.new(100, 0, 0))
		end)

		T.it("renvoie nil pour un temps NaN", function()
			T.expectEqual(PH.sampleAt(filled(10, 5), 0 / 0, 10.2), nil)
		end)
	end)

	T.describe("PositionHistory.record", function()
		T.it("échantillonne à 20 Hz un flux de 40 paquets par seconde", function()
			local h = PH.new()
			local kept = 0
			for i = 0, 79 do
				if PH.record(h, 50 + i * 0.025, Vector3.new(i, 0, 0)) then
					kept += 1
				end
			end
			-- 2 s de paquets à 40 Hz : environ 40 relevés (20 Hz)
			T.expect(kept >= 39 and kept <= 41, "relevés gardés : " .. kept)
		end)

		T.it("garde tous les relevés d'un flux à 20 Hz avec de la gigue", function()
			local h = PH.new()
			local jitter = { 0, 0.006, -0.005, 0.008, -0.006, 0.004, -0.007, 0.005 }
			for i = 0, 39 do
				T.expectEqual(PH.record(h, 30 + i * 0.05 + jitter[i % 8 + 1], Vector3.new(i, 0, 0)), true)
			end
		end)

		T.it("ne met pas au tampon un relevé trop proche mais le garde comme dernière position", function()
			local h = PH.new()
			T.expectEqual(PH.record(h, 1, Vector3.zero), true)
			T.expectEqual(PH.record(h, 1.01, Vector3.new(5, 0, 0)), false)
			T.expectEqual(h.count, 1)
			T.expectEqual(PH.sampleAt(h, 1.01, 1.01), Vector3.new(5, 0, 0))
			-- Entre les deux, interpolation vers la dernière position
			T.expectNear(PH.sampleAt(h, 1.005, 1.01).X, 2.5, 1e-6)
		end)

		T.it("repart d'un tampon vide quand l'horloge recule, et ignore un temps non fini", function()
			local h = filled(100, 10)
			T.expectEqual(PH.record(h, 0 / 0, Vector3.zero), false)
			T.expectEqual(PH.record(h, math.huge, Vector3.zero), false)
			T.expectEqual(PH.record(h, 100.5 - 0.2, Vector3.zero), false) -- petit recul : ignoré
			T.expectEqual(h.count, 10)
			T.expectEqual(PH.record(h, 50, Vector3.new(1, 1, 1)), true) -- grand recul : on repart de zéro
			T.expectEqual(h.count, 1)
			T.expectEqual(PH.record(h, 51, Vector3.new(0 / 0, 0, 0)), false)
		end)

		T.it("fait tourner le tampon sans dépasser sa capacité et oublie les plus anciens", function()
			local h = filled(0, 200) -- 10 s de relevés
			T.expectEqual(h.count, PH.CAPACITY)
			local now = 0.05 * 199
			T.expectNear(PH.sampleAt(h, now - PH.MAX_REWIND, now).X, 100 * (now - PH.MAX_REWIND), 1e-3)
			-- Le plus ancien relevé gardé couvre au moins DURATION et pas beaucoup plus
			local oldest = h.times[h.first]
			T.expect(oldest <= now - PH.DURATION, "plus ancien : " .. oldest)
			T.expect(oldest >= now - PH.CAPACITY * 0.05, "plus ancien : " .. oldest)
		end)

		T.it("garde l'ordre chronologique après rotation", function()
			local h = filled(0, 60)
			local now = 0.05 * 59
			local a = PH.sampleAt(h, now - 0.3, now).X
			local b = PH.sampleAt(h, now - 0.1, now).X
			T.expect(a < b)
		end)
	end)
end

-- Notation des kills du clip de la partie (#499).
return function(T, Loader)
	local H = Loader.new():require("src/server/HighlightRules")

	local function kill(fields)
		local base = {
			killerId = 1,
			victimId = 2,
			t = 100,
			headshot = false,
			distance = 0,
			flick = false,
			speed = 0,
			killerAirborne = false,
			victimAirborne = false,
			hardWeapon = false,
			streak = 1,
			fall = false,
		}
		for k, v in fields do
			base[k] = v
		end
		return base
	end

	T.describe("HighlightRules.score", function()
		T.it("un triple kill bat un headshot isolé en l'air", function()
			local k1 = kill({ t = 100, victimId = 2 })
			local k2 = kill({ t = 101, victimId = 3 })
			local k3 = kill({ t = 102, victimId = 4 })
			local triple = H.score(k3, { k1, k2 })
			local aerial = H.score(
				kill({ headshot = true, killerAirborne = true, victimAirborne = true, speed = 120, hardWeapon = true }),
				{}
			)
			T.expectEqual(triple > aerial, true)
		end)

		T.it("exclut une mort par chute provoquée", function()
			T.expectEqual(H.score(kill({ fall = true }), {}), nil)
		end)

		T.it("un headshot bat le même kill au corps", function()
			T.expectEqual(H.score(kill({ headshot = true }), {}) > H.score(kill({}), {}), true)
		end)

		T.it("la vitesse et le saut départagent deux kills égaux", function()
			local plain = H.score(kill({ headshot = true }), {})
			local fancy = H.score(kill({ headshot = true, speed = 100, killerAirborne = true }), {})
			T.expectEqual(fancy > plain, true)
		end)

		T.it("ne chaîne pas des kills séparés de plus de la fenêtre", function()
			local old = kill({ t = 100 })
			local now = kill({ t = 100 + H.MULTI_WINDOW + 1, victimId = 3 })
			T.expectEqual(#H.chain({ old }, now), 1)
		end)

		T.it("ne chaîne pas les kills d'un autre tireur", function()
			local other = kill({ killerId = 9, t = 100 })
			T.expectEqual(#H.chain({ other }, kill({ t = 101 })), 1)
		end)

		T.it("la distance et la série sont plafonnées", function()
			local far = H.score(kill({ distance = 100000, streak = 100 }), {})
			T.expectEqual(far, H.DISTANCE_CAP + H.STREAK_CAP)
		end)
	end)

	T.describe("HighlightRules.beats", function()
		T.it("un premier score est retenu, une égalité ne remplace pas", function()
			T.expectEqual(H.beats(10, nil), true)
			T.expectEqual(H.beats(10, 10), false)
			T.expectEqual(H.beats(11, 10), true)
			T.expectEqual(H.beats(nil, 10), false)
		end)
	end)

	T.describe("HighlightRules.window", function()
		T.it("garde 3 s avant et 1 s après un kill seul", function()
			local start, stop = H.window({ kill({ t = 50 }) })
			T.expectEqual(start, 47)
			T.expectEqual(stop, 51)
		end)

		T.it("borne un multi-kill à 8 s en gardant sa fin", function()
			local start, stop = H.window({ kill({ t = 50 }), kill({ t = 53.9 }), kill({ t = 57.8 }) })
			T.expectEqual(stop, 58.8)
			T.expectEqual(stop - start, H.MAX_DURATION)
		end)
	end)
end

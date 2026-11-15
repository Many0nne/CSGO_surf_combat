-- Cette méthode permet de simuler une AnimationTrack (état de lecture, poids, appels reçus) lorsqu'on teste son arrêt.
local function fakeTrack(isPlaying: boolean, weight: number)
	local track = { IsPlaying = isPlaying, WeightCurrent = weight, Length = 0.85, TimePosition = 0, calls = {} }
	function track:Play(fade)
		table.insert(self.calls, "Play(" .. tostring(fade) .. ")")
		self.IsPlaying = true
	end
	function track:Stop(fade)
		table.insert(self.calls, "Stop(" .. tostring(fade) .. ")")
		self.IsPlaying = false
	end
	return track
end

return function(T, Loader)
	local TrackStop = Loader.new({}):require("src/client/systems/weapon/TrackStop")

	T.describe("TrackStop.stop (#368)", function()
		T.it("arrête simplement une piste en cours de lecture", function()
			local track = fakeTrack(true, 1)
			TrackStop.stop(track, 0)
			T.expectEqual(table.concat(track.calls, ","), "Stop(0)")
		end)

		T.it("coupe sans fondu une piste en fondu de fin naturel, relancée sur sa dernière image", function()
			local track = fakeTrack(false, 0.83)
			TrackStop.stop(track, 0)
			T.expectEqual(table.concat(track.calls, ","), "Play(0),Stop(0)")
			T.expectEqual(track.TimePosition, track.Length)
			T.expectEqual(track.IsPlaying, false)
		end)

		T.it("laisse finir son fondu de fin quand un fondu est demandé (AWP, défaut Roblox)", function()
			local track = fakeTrack(false, 0.83)
			TrackStop.stop(track, nil)
			T.expectEqual(table.concat(track.calls, ","), "Stop(nil)")
			local faded = fakeTrack(false, 0.83)
			TrackStop.stop(faded, 0.1)
			T.expectEqual(table.concat(faded.calls, ","), "Stop(0.1)")
		end)

		T.it("ne relance pas une piste déjà éteinte", function()
			local track = fakeTrack(false, 0)
			TrackStop.stop(track, 0)
			T.expectEqual(table.concat(track.calls, ","), "Stop(0)")
		end)

		T.it("ignore une piste absente", function()
			TrackStop.stop(nil, 0)
		end)
	end)
end

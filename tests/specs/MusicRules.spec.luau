return function(T, Loader)
	local MusicRules = Loader.new():require("src/client/systems/audio/MusicRules")

	local function settings(music: boolean, menu: number, game: number)
		return { music = music, volumeMusicMenu = menu, volumeMusicGame = game }
	end

	T.describe("MusicRules.targetVolume", function()
		T.it("se tait quand le réglage est coupé, quel que soit le volume", function()
			T.expectEqual(MusicRules.targetVolume(settings(false, 100, 100), "MENU", false), 0)
			T.expectEqual(MusicRules.targetVolume(settings(false, 100, 100), "IN_ROUND", false), 0)
		end)

		T.it("prend le volume du menu dans les écrans du menu", function()
			for _, state in { "MENU", "INFOS" } do
				T.expectNear(MusicRules.targetVolume(settings(true, 80, 20), state, false), 0.8)
			end
			T.expectNear(MusicRules.targetVolume(settings(true, 80, 20), nil, false), 0.8) -- avant le premier état
		end)

		T.it("prend le volume de la partie hors du menu", function()
			for _, state in { "SPAWNING", "IN_ROUND", "DEAD", "RESULT" } do
				T.expectNear(MusicRules.targetVolume(settings(true, 80, 20), state, false), 0.2)
			end
		end)

		T.it("baisse pendant une annonce vocale, et seulement là", function()
			local s = settings(true, 100, 40)
			T.expectNear(MusicRules.targetVolume(s, "IN_ROUND", true), 0.4 * MusicRules.ANNOUNCE_DUCK)
			T.expectNear(MusicRules.targetVolume(s, "IN_ROUND", false), 0.4)
		end)
	end)

	T.describe("MusicRules.isDucking (#405)", function()
		T.it("baisse la musique quand la voix joue et qu'elle est audible", function()
			T.expectEqual(MusicRules.isDucking({ volumeMaster = 100, volumeAnnouncer = 100 }, true), true)
			T.expectEqual(MusicRules.isDucking({ volumeMaster = 30, volumeAnnouncer = 1 }, true), true)
		end)

		T.it("ne baisse pas quand aucune voix ne joue", function()
			T.expectEqual(MusicRules.isDucking({ volumeMaster = 100, volumeAnnouncer = 100 }, false), false)
		end)

		T.it("ne baisse pas quand le canal annonces ou le général est à 0 (voix muette)", function()
			T.expectEqual(MusicRules.isDucking({ volumeMaster = 100, volumeAnnouncer = 0 }, true), false)
			T.expectEqual(MusicRules.isDucking({ volumeMaster = 0, volumeAnnouncer = 100 }, true), false)
		end)
	end)

	T.describe("MusicRules.step", function()
		T.it("baisse vite et remonte plus lentement, sans dépasser la cible", function()
			T.expectNear(MusicRules.step(1, 0, MusicRules.FADE_DOWN / 2), 0.5)
			T.expectNear(MusicRules.step(0, 1, MusicRules.FADE_UP / 2), 0.5)
			T.expectEqual(MusicRules.step(1, 0.35, 10), 0.35)
			T.expectEqual(MusicRules.step(0.1, 0.35, 10), 0.35)
			T.expectEqual(MusicRules.step(0.35, 0.35, 0.016), 0.35)
		end)
	end)
end

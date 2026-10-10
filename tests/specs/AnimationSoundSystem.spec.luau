return function(T, Loader)
	local AnimationSoundSystem = Loader.new():require("src/client/systems/weapon/AnimationSoundSystem")

	T.describe("AnimationSoundSystem.uniqueNames", function()
		T.it("retire les doublons en gardant l'ordre", function()
			local out = AnimationSoundSystem.uniqueNames({ "Bolt", "ClipIn", "Bolt", "ClipOut", "ClipIn" })
			T.expectEqual(#out, 3)
			T.expectEqual(out[1], "Bolt")
			T.expectEqual(out[2], "ClipIn")
			T.expectEqual(out[3], "ClipOut")
		end)

		T.it("ignore nil, les chaînes vides et les valeurs non textuelles", function()
			T.expectEqual(#AnimationSoundSystem.uniqueNames(nil), 0)
			T.expectEqual(#AnimationSoundSystem.uniqueNames({ "", "Draw" } :: any), 1)
		end)
	end)

	T.describe("AnimationSoundSystem.withoutOverridden", function()
		T.it("retire les sons dont le marqueur est déjà géré par un override", function()
			local out = AnimationSoundSystem.withoutOverridden({ "Stab", "Swing", "Swing" }, {
				["Stab Sound"] = function()
					return "HitFlesh"
				end,
			})
			T.expectEqual(#out, 1)
			T.expectEqual(out[1], "Swing")
		end)

		T.it("sans override, renvoie la liste dédoublonnée", function()
			T.expectEqual(#AnimationSoundSystem.withoutOverridden({ "Draw", "Draw" }, nil), 1)
			T.expectEqual(#AnimationSoundSystem.withoutOverridden(nil, nil), 0)
		end)
	end)

	T.describe("AnimationSoundSystem.computePlaybackSpeed", function()
		T.it("cale la durée de l'anim sur la durée gameplay", function()
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(3, 3, 0.5, 2), 1)
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(4, 2, 0.5, 2), 2)
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(2, 4, 0.5, 2), 0.5)
		end)

		T.it("borne la vitesse", function()
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(10, 1, 0.75, 1.5), 1.5)
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(1, 10, 0.75, 1.5), 0.75)
		end)

		T.it("retombe sur 1 si une durée est inconnue (piste pas encore chargée)", function()
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(0, 3.7, 0.75, 1.5), 1)
			T.expectEqual(AnimationSoundSystem.computePlaybackSpeed(2, nil, 0.75, 1.5), 1)
		end)
	end)
end

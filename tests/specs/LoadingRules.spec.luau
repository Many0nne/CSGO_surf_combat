local roblox = require("@lune/roblox")

return function(T, Loader)
	local LoadingRules = Loader.new():require("src/first/LoadingRules")

	T.describe("LoadingRules.shouldRelease", function()
		T.it("attend le jeu chargé et le menu prêt", function()
			T.expectEqual(LoadingRules.shouldRelease(2, false, true), false)
			T.expectEqual(LoadingRules.shouldRelease(2, true, false), false)
			T.expectEqual(LoadingRules.shouldRelease(2, true, true), true)
		end)

		T.it("reste affiché la durée minimale même si tout est prêt", function()
			T.expectEqual(LoadingRules.shouldRelease(LoadingRules.MIN_SHOWN / 2, true, true), false)
			T.expectEqual(LoadingRules.shouldRelease(LoadingRules.MIN_SHOWN, true, true), true)
		end)

		T.it("se lève au délai maximal même si rien n'est prêt", function()
			T.expectEqual(LoadingRules.shouldRelease(LoadingRules.MAX_WAIT - 0.1, false, false), false)
			T.expectEqual(LoadingRules.shouldRelease(LoadingRules.MAX_WAIT, false, false), true)
		end)
	end)

	T.describe("LoadingRules libellés", function()
		T.it("nomme la destination d'une téléportation", function()
			T.expectEqual(LoadingRules.teleportLabel(true), LoadingRules.JOIN_LABEL)
			T.expectEqual(LoadingRules.teleportLabel(false), LoadingRules.LEAVE_LABEL)
		end)

		T.it("lit l'arrivée dans les données de téléportation de TrainingService", function()
			T.expectEqual(LoadingRules.arrivalLabel({ training = true }), LoadingRules.JOIN_LABEL)
			T.expectEqual(LoadingRules.arrivalLabel({ training = false }), LoadingRules.LEAVE_LABEL)
		end)

		T.it("montre le chargement sans données valides (lancement depuis le site)", function()
			T.expectEqual(LoadingRules.arrivalLabel(nil), LoadingRules.INITIAL_LABEL)
			T.expectEqual(LoadingRules.arrivalLabel({}), LoadingRules.INITIAL_LABEL)
			T.expectEqual(LoadingRules.arrivalLabel({ training = "oui" }), LoadingRules.INITIAL_LABEL)
			T.expectEqual(LoadingRules.arrivalLabel("training"), LoadingRules.INITIAL_LABEL)
		end)
	end)

	T.describe("LoadingRules apparence", function()
		T.it("suit les volets de Transition (UITheme : SunWhite, Ground, Shutter, Oswald)", function()
			-- TweenInfo absent de Lune : UITheme n'en fait que des constantes
			local fakeTweenInfo = {
				new = function(time)
					return { Time = time }
				end,
			}
			local globals =
				{ Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum, TweenInfo = fakeTweenInfo }
			local UITheme = Loader.new({}, globals):require("src/shared/UITheme")
			local function same(a, b)
				return math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4
			end
			T.expectEqual(same(LoadingRules.PANEL_COLOR, UITheme.Colors.SunWhite), true)
			T.expectEqual(same(LoadingRules.TEXT_COLOR, UITheme.Colors.Ground), true)
			T.expectEqual(LoadingRules.SHUTTER_TIME, UITheme.Motion.Shutter.Time)
			T.expectEqual(LoadingRules.FONT_FAMILY, UITheme.Fonts.Display.Family)
		end)
	end)
end

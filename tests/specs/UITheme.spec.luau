return function(T, Loader)
	local UITheme = Loader.new():require("src/shared/UITheme")

	-- Cette méthode permet de vérifier qu'une famille de tokens contient toutes les clés attendues
	-- lorsque les écrans UI en dépendent, avec le bon type Roblox.
	local function expectTokens(group: string, keys: { string }, expectedType: string)
		local tokens = UITheme[group]
		T.expectEqual(type(tokens), "table")
		for _, key in keys do
			T.expectEqual(typeof(tokens[key]), expectedType)
		end
	end

	T.describe("UITheme", function()
		T.it("expose la marque", function()
			expectTokens("Brand", { "NAME", "TAGLINE", "VERSION" }, "string")
		end)

		T.it("expose les couleurs utilisées par les écrans", function()
			expectTokens("Color", {
				"BG",
				"BG_GRAD_TOP",
				"BG_GRAD_BOTTOM",
				"SURFACE",
				"SURFACE_RAISED",
				"SURFACE_HOVER",
				"TRACK",
				"BORDER",
				"BACKDROP",
				"TEXT",
				"TEXT_DIM",
				"MUTED",
				"FAINT",
				"ACCENT",
				"ACCENT_HOVER",
				"ON_ACCENT",
				"COMBAT",
				"WARN",
				"HANDLE",
			}, "Color3")
		end)

		T.it("expose les polices", function()
			expectTokens("Font", { "DISPLAY", "HEADING", "LABEL", "BODY", "MONO" }, "EnumItem")
		end)

		T.it("expose les tailles, rayons, espacements, traits, transparences et durées", function()
			expectTokens(
				"TextSize",
				{ "LOGO", "TITLE", "BANNER", "NUMERIC", "TIMER", "BUTTON", "BODY", "LABEL", "CAPTION" },
				"number"
			)
			expectTokens("Radius", { "SM", "MD", "LG", "PILL" }, "number")
			expectTokens("Space", { "XS", "SM", "MD", "LG", "XL" }, "number")
			expectTokens("Stroke", { "THIN", "STRIPE" }, "number")
			expectTokens("Transparency", { "OVERLAY", "BACKDROP", "ROW_ODD", "HUD" }, "number")
			expectTokens("Motion", { "FAST" }, "number")
		end)

		T.it("garde les transparences dans [0, 1]", function()
			for _, value in UITheme.Transparency do
				T.expectEqual(value >= 0 and value <= 1, true)
			end
		end)
	end)
end

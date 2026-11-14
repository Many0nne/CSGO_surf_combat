return function(T, Loader)
	local PlayerSettings = Loader.new():require("src/shared/PlayerSettings")
	local CameraConfig = Loader.new():require("src/shared/CameraConfig")

	local function keysOf(keys: { string }): string
		return table.concat(keys, ",")
	end

	T.describe("PlayerSettings.sanitize", function()
		T.it("donne les valeurs par défaut pour des données absentes ou illisibles", function()
			for _, raw in { nil, 42, "x", {} } do
				local s = PlayerSettings.sanitize(raw)
				T.expectEqual(s.sensitivity, CameraConfig.DEFAULT_SENS)
				T.expectEqual(s.scopeMultiplier, CameraConfig.SCOPE_SENS_MULT)
				T.expectEqual(s.shadows, nil)
				T.expectEqual(s.wheel, "previous")
				T.expectEqual(s.simpleAim, false)
				T.expectEqual(s.keyDisplay, "off")
				T.expectEqual(s.autoBhop, PlayerSettings.DEFAULT_AUTO_BHOP)
				T.expectEqual(keysOf(s.slotKeys), keysOf(PlayerSettings.DEFAULT_SLOT_KEYS))
			end
		end)

		T.it("garde des réglages valides", function()
			local keys = table.clone(PlayerSettings.DEFAULT_SLOT_KEYS)
			keys[1], keys[2] = "Q", "E"
			local s = PlayerSettings.sanitize({
				sensitivity = 0.25,
				scopeMultiplier = 1.5,
				shadows = false,
				wheel = "next",
				simpleAim = true,
				keyDisplay = "full",
				slotKeys = keys,
			})
			T.expectEqual(s.simpleAim, true)
			T.expectEqual(s.keyDisplay, "full")
			T.expectEqual(s.sensitivity, 0.25)
			T.expectEqual(s.scopeMultiplier, 1.5)
			T.expectEqual(s.shadows, false)
			T.expectEqual(s.wheel, "next")
			T.expectEqual(keysOf(s.slotKeys), keysOf(keys))
		end)

		T.it("borne les nombres et écarte NaN et les mauvais types", function()
			T.expectEqual(PlayerSettings.sanitize({ sensitivity = 50 }).sensitivity, CameraConfig.SENS_MAX)
			T.expectEqual(PlayerSettings.sanitize({ sensitivity = -1 }).sensitivity, CameraConfig.SENS_MIN)
			T.expectEqual(PlayerSettings.sanitize({ sensitivity = 0 / 0 }).sensitivity, CameraConfig.DEFAULT_SENS)
			T.expectEqual(
				PlayerSettings.sanitize({ scopeMultiplier = "2" }).scopeMultiplier,
				CameraConfig.SCOPE_SENS_MULT
			)
			T.expectEqual(PlayerSettings.sanitize({ shadows = "oui" }).shadows, nil)
			T.expectEqual(PlayerSettings.sanitize({ wheel = "haut" }).wheel, "previous")
			for _, bad in { "oui", 1, {} } do
				T.expectEqual(PlayerSettings.sanitize({ simpleAim = bad }).simpleAim, false)
			end
			for _, bad in { "non", 0, {} } do
				T.expectEqual(PlayerSettings.sanitize({ autoBhop = bad }).autoBhop, true)
			end
			for _, bad in { "non", 0, {} } do
				T.expectEqual(PlayerSettings.sanitize({ deathTips = bad }).deathTips, true, "conseils (#291)")
			end
			T.expectEqual(PlayerSettings.sanitize({ autoBhop = false }).autoBhop, false)
			T.expectEqual(PlayerSettings.sanitize({ sensitivity = 0.3 }).autoBhop, true) -- ancienne sauvegarde
			for _, bad in { true, 1, "complet", "FULL", {} } do
				T.expectEqual(PlayerSettings.sanitize({ keyDisplay = bad }).keyDisplay, "off")
			end
			for _, mode in { "off", "simple", "full" } do
				T.expectEqual(PlayerSettings.sanitize({ keyDisplay = mode }).keyDisplay, mode)
			end
		end)

		T.it("remet toutes les touches par défaut si une touche est en double, réservée ou manquante", function()
			local default = keysOf(PlayerSettings.DEFAULT_SLOT_KEYS)
			local double = table.clone(PlayerSettings.DEFAULT_SLOT_KEYS)
			double[2] = "One"
			local reserved = table.clone(PlayerSettings.DEFAULT_SLOT_KEYS)
			reserved[1] = "W"
			local short = { "One", "Two" }
			for label, keys in { double = double, reserved = reserved, short = short } do
				T.expectEqual(keysOf(PlayerSettings.sanitize({ slotKeys = keys }).slotKeys), default, label)
			end
		end)
	end)

	T.describe("PlayerSettings.sanitize : viseur (#251)", function()
		local C = PlayerSettings.CROSSHAIR

		T.it("donne le crosshair d'origine par défaut, y compris pour une sauvegarde d'avant le viseur", function()
			for _, raw in { {}, { sensitivity = 0.3, simpleAim = true } } do
				local s = PlayerSettings.sanitize(raw)
				T.expectEqual(s.crosshairColor, "bone")
				T.expectEqual(s.crosshairLength, 9)
				T.expectEqual(s.crosshairThickness, 2)
				T.expectEqual(s.crosshairGap, 5)
				T.expectEqual(s.crosshairDot, false)
				T.expectEqual(s.crosshairOutline, true)
				T.expectEqual(s.crosshairOpacity, 1)
			end
			T.expectEqual(PlayerSettings.sanitize({ simpleAim = true }).simpleAim, true)
		end)

		T.it("garde un style valide", function()
			local s = PlayerSettings.sanitize({
				crosshairColor = "cyan",
				crosshairLength = 14,
				crosshairThickness = 1,
				crosshairGap = 0,
				crosshairDot = true,
				crosshairOutline = false,
				crosshairOpacity = 0.6,
			})
			T.expectEqual(s.crosshairColor, "cyan")
			T.expectEqual(s.crosshairLength, 14)
			T.expectEqual(s.crosshairThickness, 1)
			T.expectEqual(s.crosshairGap, 0)
			T.expectEqual(s.crosshairDot, true)
			T.expectEqual(s.crosshairOutline, false)
			T.expectEqual(s.crosshairOpacity, 0.6)
		end)

		T.it("borne les tailles en px entiers et l'opacité, écarte NaN et les mauvais types", function()
			local high = PlayerSettings.sanitize({
				crosshairLength = 500,
				crosshairThickness = 99,
				crosshairGap = 1e9,
				crosshairOpacity = 3,
			})
			T.expectEqual(high.crosshairLength, C.length.max)
			T.expectEqual(high.crosshairThickness, C.thickness.max)
			T.expectEqual(high.crosshairGap, C.gap.max)
			T.expectEqual(high.crosshairOpacity, C.opacity.max)
			local low = PlayerSettings.sanitize({
				crosshairLength = -4,
				crosshairThickness = 0,
				crosshairGap = -1,
				crosshairOpacity = 0,
			})
			T.expectEqual(low.crosshairLength, C.length.min)
			T.expectEqual(low.crosshairThickness, C.thickness.min)
			T.expectEqual(low.crosshairGap, C.gap.min)
			T.expectEqual(low.crosshairOpacity, C.opacity.min, "un viseur invisible n'est pas permis")
			T.expectEqual(PlayerSettings.sanitize({ crosshairLength = 7.6 }).crosshairLength, 8, "px entiers")
			T.expectEqual(PlayerSettings.sanitize({ crosshairOpacity = 0.3333 }).crosshairOpacity, 0.33, "au centième")
			local bad = PlayerSettings.sanitize({
				crosshairLength = 0 / 0,
				crosshairThickness = "3",
				crosshairOpacity = {},
				crosshairDot = "oui",
				crosshairOutline = 0,
			})
			T.expectEqual(bad.crosshairLength, C.length.default)
			T.expectEqual(bad.crosshairThickness, C.thickness.default)
			T.expectEqual(bad.crosshairOpacity, C.opacity.default)
			T.expectEqual(bad.crosshairDot, false)
			T.expectEqual(bad.crosshairOutline, true)
		end)

		T.it("refuse une couleur hors de la palette", function()
			for _, bad in { "pink", "BONE", "#ff00ff", 1, true, {} } do
				T.expectEqual(PlayerSettings.sanitize({ crosshairColor = bad }).crosshairColor, "bone")
			end
			for _, id in PlayerSettings.CROSSHAIR_COLORS do
				T.expectEqual(PlayerSettings.sanitize({ crosshairColor = id }).crosshairColor, id)
			end
		end)

		T.it("palette de 6 à 8 teintes dont la couleur par défaut, alignée sur UITheme.CrosshairPalette", function()
			local ids = PlayerSettings.CROSSHAIR_COLORS
			T.expectEqual(#ids >= 6 and #ids <= 8, true)
			T.expectEqual(table.find(ids, C.color) ~= nil, true)
			local roblox = require("@lune/roblox")
			-- TweenInfo absent de Lune : UITheme n'en fait que des constantes
			local fakeTweenInfo = {
				new = function()
					return {}
				end,
			}
			local globals =
				{ Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum, TweenInfo = fakeTweenInfo }
			local UITheme = Loader.new({}, globals):require("src/shared/UITheme")
			T.expectEqual(#UITheme.CrosshairPalette, #ids)
			for i, entry in UITheme.CrosshairPalette do
				T.expectEqual(entry.id, ids[i], "même ordre")
			end
		end)
	end)

	T.describe("PlayerSettings.sanitize : volume (#249)", function()
		local V = PlayerSettings.VOLUME

		T.it("donne 100 % par défaut, y compris pour une sauvegarde d'avant le volume", function()
			for _, raw in { nil, 42, {}, { sensitivity = 0.3 } } do
				local s = PlayerSettings.sanitize(raw)
				T.expectEqual(s.volumeMaster, 100)
				T.expectEqual(s.volumeWeapons, 100)
			end
		end)

		T.it("garde un volume valide et arrondit au pourcent", function()
			local s = PlayerSettings.sanitize({ volumeMaster = 35, volumeWeapons = 0 })
			T.expectEqual(s.volumeMaster, 35)
			T.expectEqual(s.volumeWeapons, 0, "0 % (muet) est permis")
			T.expectEqual(PlayerSettings.sanitize({ volumeMaster = 42.6 }).volumeMaster, 43)
		end)

		T.it("borne les volumes et écarte NaN et les mauvais types", function()
			T.expectEqual(PlayerSettings.sanitize({ volumeMaster = 500 }).volumeMaster, V.max)
			T.expectEqual(PlayerSettings.sanitize({ volumeWeapons = -20 }).volumeWeapons, V.min)
			for _, bad in { 0 / 0, "50", true, {} } do
				T.expectEqual(PlayerSettings.sanitize({ volumeMaster = bad }).volumeMaster, V.default)
				T.expectEqual(PlayerSettings.sanitize({ volumeWeapons = bad }).volumeWeapons, V.default)
			end
		end)
	end)

	T.describe("PlayerSettings : échelle du HUD (#250)", function()
		local H = PlayerSettings.HUD_SCALE

		T.it("donne 100 % par défaut, y compris pour une sauvegarde d'avant le réglage", function()
			T.expectEqual(PlayerSettings.defaults().hudScale, 100)
			for _, raw in { nil, 42, {}, { sensitivity = 0.3 } } do
				T.expectEqual(PlayerSettings.sanitize(raw).hudScale, 100)
			end
		end)

		T.it("garde une valeur valide et l'arrondit au pourcent", function()
			T.expectEqual(PlayerSettings.sanitize({ hudScale = 50 }).hudScale, 50)
			T.expectEqual(PlayerSettings.sanitize({ hudScale = 72.4 }).hudScale, 72)
		end)

		T.it("borne à 50-100 % et retombe sur 100 % pour NaN et les mauvais types", function()
			T.expectEqual(PlayerSettings.sanitize({ hudScale = 10 }).hudScale, H.min)
			T.expectEqual(PlayerSettings.sanitize({ hudScale = 250 }).hudScale, H.max)
			for _, bad in { 0 / 0, "70", true, {} } do
				T.expectEqual(PlayerSettings.sanitize({ hudScale = bad }).hudScale, H.default)
			end
		end)

		T.it("convertit en facteur borné entre 0,5 et 1", function()
			T.expectEqual(PlayerSettings.hudScaleFactor(100), 1)
			T.expectEqual(PlayerSettings.hudScaleFactor(50), 0.5)
			T.expectEqual(PlayerSettings.hudScaleFactor(0), 0.5)
			T.expectEqual(PlayerSettings.hudScaleFactor(300), 1)
			T.expectEqual(PlayerSettings.hudScaleFactor(nil), 1)
			T.expectEqual(PlayerSettings.hudScaleFactor("x"), 1)
		end)
	end)

	T.describe("PlayerSettings : conseils de l'écran de mort (#291)", function()
		T.it("active les conseils par défaut, y compris pour un réglage sauvegardé avant eux", function()
			T.expectEqual(PlayerSettings.DEFAULT_DEATH_TIPS, true)
			T.expectEqual(PlayerSettings.defaults().deathTips, true)
			T.expectEqual(PlayerSettings.sanitize({ sensitivity = 0.25 }).deathTips, true, "champ absent")
		end)

		T.it("garde le choix du joueur", function()
			T.expectEqual(PlayerSettings.sanitize({ deathTips = false }).deathTips, false)
			T.expectEqual(PlayerSettings.sanitize({ deathTips = true }).deathTips, true)
		end)
	end)

	T.describe("PlayerSettings.assignKey", function()
		local defaults = PlayerSettings.DEFAULT_SLOT_KEYS

		T.it("donne une touche libre à l'emplacement sans toucher aux autres", function()
			local keys = PlayerSettings.assignKey(defaults, 1, "Q")
			T.expectEqual(keys and keys[1], "Q")
			T.expectEqual(keys and keys[2], "Two")
			T.expectEqual(defaults[1], "One", "la table d'origine n'est pas modifiée")
		end)

		T.it("échange les touches quand un autre emplacement avait déjà celle-ci", function()
			local keys = PlayerSettings.assignKey(defaults, 1, "Two")
			T.expectEqual(keys and keys[1], "Two")
			T.expectEqual(keys and keys[2], "One")
		end)

		T.it("accepte de redonner sa propre touche à un emplacement", function()
			local keys = PlayerSettings.assignKey(defaults, 3, "Three")
			T.expectEqual(keys and keysOf(keys), keysOf(defaults))
		end)

		T.it("refuse les touches du jeu et les touches non proposées", function()
			for _, key in { "W", "A", "S", "D", "R", "F", "P", "F3", "F4" } do
				local keys, reason = PlayerSettings.assignKey(defaults, 1, key)
				T.expectEqual(keys, nil, key)
				T.expectEqual(reason, "reserved", key)
			end
			for _, key in { "Space", "Tab", "Escape", "LeftShift", "Slash", "Unknown" } do
				local keys, reason = PlayerSettings.assignKey(defaults, 1, key)
				T.expectEqual(keys, nil, key)
				T.expectEqual(reason, "invalid", key)
			end
		end)
	end)

	T.describe("PlayerSettings.wheelStep", function()
		T.it("molette vers le haut : arme précédente par défaut, suivante si inversée, rien si coupée", function()
			T.expectEqual(PlayerSettings.wheelStep("previous", 1), -1)
			T.expectEqual(PlayerSettings.wheelStep("previous", -1), 1)
			T.expectEqual(PlayerSettings.wheelStep("next", 1), 1)
			T.expectEqual(PlayerSettings.wheelStep("next", -1), -1)
			T.expectEqual(PlayerSettings.wheelStep("off", 1), nil)
			T.expectEqual(PlayerSettings.wheelStep("previous", 0), nil)
		end)
	end)

	T.describe("PlayerSettings.keyLabel et slotForKey", function()
		T.it("affiche les chiffres en chiffres et retrouve l'emplacement d'une touche", function()
			T.expectEqual(PlayerSettings.keyLabel("One"), "1")
			T.expectEqual(PlayerSettings.keyLabel("Zero"), "0")
			T.expectEqual(PlayerSettings.keyLabel("F5"), "F5")
			T.expectEqual(PlayerSettings.slotForKey(PlayerSettings.DEFAULT_SLOT_KEYS, "Three"), 3)
			T.expectEqual(PlayerSettings.slotForKey(PlayerSettings.DEFAULT_SLOT_KEYS, "Q"), nil)
		end)
	end)
end

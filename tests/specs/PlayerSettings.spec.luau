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

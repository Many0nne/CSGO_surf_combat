-- Liaisons fixes des touches de jeu (#224) : une touche, une action ; chaque action a au moins une touche.
return function(T, Loader)
	local KeyBindings = Loader.new():require("src/shared/KeyBindings")

	T.describe("KeyBindings.keyMap", function()
		T.it("associe chaque touche de chaque action à cette action", function()
			local map = KeyBindings.keyMap()
			for action, keys in KeyBindings.KEYS do
				T.expectEqual(#keys > 0, true, action)
				for _, key in keys do
					T.expectEqual(map[key], action, key)
				end
			end
		end)

		T.it("ne lie aucune touche à deux actions", function()
			local seen = {}
			for action, keys in KeyBindings.KEYS do
				for _, key in keys do
					T.expectEqual(
						seen[key],
						nil,
						key .. " déjà liée à " .. tostring(seen[key]) .. ", aussi à " .. action
					)
					seen[key] = action
				end
			end
		end)

		T.it(
			"garde les liaisons d'avant #224 (déplacement W A S D, saut, accroupi, marche, recharge, inspection)",
			function()
				local map = KeyBindings.keyMap()
				T.expectEqual(map.W, "forward")
				T.expectEqual(map.A, "left")
				T.expectEqual(map.S, "back")
				T.expectEqual(map.D, "right")
				T.expectEqual(map.Space, "jump")
				T.expectEqual(map.LeftControl, "crouch")
				T.expectEqual(map.RightControl, "crouch")
				T.expectEqual(map.LeftShift, "walk")
				T.expectEqual(map.RightShift, "walk")
				T.expectEqual(map.R, "reload")
				T.expectEqual(map.F, "inspect")
			end
		)
	end)

	T.describe("KeyBindings et PlayerSettings", function()
		T.it("refuse chaque touche de jeu pour un emplacement d'arme", function()
			local PlayerSettings = Loader.new():require("src/shared/PlayerSettings")
			for action, keys in KeyBindings.KEYS do
				for _, key in keys do
					local result, reason = PlayerSettings.assignKey(PlayerSettings.DEFAULT_SLOT_KEYS, 1, key)
					T.expectEqual(result, nil, action .. " " .. key)
					T.expectEqual(reason == "reserved" or reason == "invalid", true, action .. " " .. key)
				end
			end
		end)

		T.it("annonce W A S D R F comme touches du jeu (réservées), comme avant #224", function()
			local PlayerSettings = Loader.new():require("src/shared/PlayerSettings")
			for _, key in { "W", "A", "S", "D", "R", "F" } do
				T.expectEqual(PlayerSettings.isReserved(key), true, key)
			end
			for _, key in { "Space", "LeftShift", "LeftControl" } do
				T.expectEqual(PlayerSettings.isReserved(key), false, key .. " : non proposée, refus « invalid »")
			end
		end)
	end)

	T.describe("KeyBindings.MOUSE", function()
		T.it("tire au clic gauche et vise au clic droit", function()
			T.expectEqual(KeyBindings.MOUSE.fire, 1)
			T.expectEqual(KeyBindings.MOUSE.aim, 2)
		end)
	end)

	T.describe("KeyBindings gelées", function()
		T.it("refuse toute modification des liaisons partagées", function()
			T.expectEqual(table.isfrozen(KeyBindings.KEYS), true)
			T.expectEqual(table.isfrozen(KeyBindings.KEYS.forward), true)
			T.expectEqual(table.isfrozen(KeyBindings.MOUSE), true)
			T.expectEqual(table.isfrozen(KeyBindings.GAMEPAD), true)
			T.expectEqual(table.isfrozen(KeyBindings.GAMEPAD.jump), true)
			T.expectEqual(table.isfrozen(KeyBindings.GAMEPAD_BUTTONS), true)
		end)
	end)

	T.describe("KeyBindings manette (#276)", function()
		T.it("donne la disposition FPS console : A saut, B accroupi, X recharge, Y inspection, L3 marche", function()
			local map = KeyBindings.gamepadMap()
			T.expectEqual(map.ButtonA, "jump")
			T.expectEqual(map.ButtonB, "crouch")
			T.expectEqual(map.ButtonX, "reload")
			T.expectEqual(map.ButtonY, "inspect")
			T.expectEqual(map.ButtonL3, "walk")
		end)

		T.it("ne lie que des actions de KeyBindings.KEYS, chacune à un bouton au plus", function()
			for action, buttons in KeyBindings.GAMEPAD do
				T.expectEqual(KeyBindings.KEYS[action] ~= nil, true, action)
				T.expectEqual(#buttons, 1, action)
			end
		end)

		T.it("laisse Start et Select à Roblox, et R1/L1 au changement d'arme", function()
			local used = KeyBindings.gamepadMap()
			for _, button in KeyBindings.GAMEPAD_BUTTONS do
				used[button] = "x"
			end
			for _, button in { "ButtonStart", "ButtonSelect", "ButtonR1", "ButtonL1" } do
				T.expectEqual(used[button], nil, button)
			end
		end)

		T.it("libelle les boutons comme la manette Xbox", function()
			T.expectEqual(KeyBindings.gamepadText("ButtonA"), "A")
			T.expectEqual(KeyBindings.gamepadText("ButtonL2"), "LT")
			T.expectEqual(KeyBindings.gamepadText("ButtonR2"), "RT")
			T.expectEqual(KeyBindings.gamepadText("ButtonL3"), "L3")
		end)
	end)

	T.describe("KeyBindings.deviceOf", function()
		T.it("classe l'appareil selon le type d'entrée", function()
			T.expectEqual(KeyBindings.deviceOf("Gamepad1"), "gamepad")
			T.expectEqual(KeyBindings.deviceOf("Gamepad2"), "gamepad")
			T.expectEqual(KeyBindings.deviceOf("Touch"), "touch")
			T.expectEqual(KeyBindings.deviceOf("Keyboard"), "keyboard")
			T.expectEqual(KeyBindings.deviceOf("MouseMovement"), "keyboard")
			T.expectEqual(KeyBindings.deviceOf("MouseButton1"), "keyboard")
			T.expectEqual(KeyBindings.deviceOf("Focus"), nil)
			T.expectEqual(KeyBindings.deviceOf("Accelerometer"), nil)
		end)
	end)
end

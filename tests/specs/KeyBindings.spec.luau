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
		end)
	end)
end

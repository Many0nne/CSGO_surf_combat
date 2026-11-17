-- Tir et visée tenus (#473) : InputModule suit les vraies touches (souris, manette, tactile) pour que WeaponSystem
-- répète l'action tant que l'une d'elles est tenue.
return function(T, Loader)
	local roblox = require("@lune/roblox")
	local Enum = roblox.Enum

	-- Cette méthode permet de créer un faux signal lorsque le test déclenche lui-même les entrées.
	local function signal()
		local handlers = {}
		return {
			Connect = function(_, fn)
				table.insert(handlers, fn)
			end,
			fire = function(...)
				for _, fn in handlers do
					fn(...)
				end
			end,
		}
	end

	-- Cette méthode permet de charger un InputModule neuf branché sur une fausse saisie lorsqu'un cas démarre.
	local function load()
		local uis = { InputBegan = signal(), InputEnded = signal(), InputChanged = signal() }
		local globals = {
			Vector2 = roblox.Vector2,
			task = {
				spawn = function(fn, ...)
					fn(...)
				end,
			},
			tick = os.clock,
		}
		local InputModule = Loader.new({ UserInputService = uis }, globals):require("src/client/input/InputModule")
		return InputModule, uis
	end

	local function mouse(n: number)
		return { UserInputType = (Enum.UserInputType :: any)["MouseButton" .. n], KeyCode = Enum.KeyCode.Unknown }
	end
	local function pad(name: string)
		return { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = (Enum.KeyCode :: any)[name] }
	end

	T.describe("InputModule.isPointerHeld", function()
		T.it("tient le tir du clic gauche jusqu'au relâchement", function()
			local InputModule, uis = load()
			uis.InputBegan.fire(mouse(1), false)
			T.expectEqual(InputModule.isPointerHeld("fire"), true, "clic tenu")
			T.expectEqual(InputModule.isPointerHeld("aim"), false, "visée non tenue")
			uis.InputEnded.fire(mouse(1))
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "clic relâché")
		end)

		T.it("ignore un clic capté par l'interface", function()
			local InputModule, uis = load()
			uis.InputBegan.fire(mouse(1), true)
			uis.InputBegan.fire(mouse(2), true)
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "tir")
			T.expectEqual(InputModule.isPointerHeld("aim"), false, "visée")
		end)

		T.it("tient la visée du clic droit et prévient une fois les écouteurs à l'appui", function()
			local InputModule, uis = load()
			local calls = 0
			InputModule.onAim(function()
				calls += 1
			end)
			uis.InputBegan.fire(mouse(2), false)
			T.expectEqual(InputModule.isPointerHeld("aim"), true, "visée tenue")
			T.expectEqual(calls, 1, "un appel à l'appui")
			uis.InputEnded.fire(mouse(2))
			T.expectEqual(InputModule.isPointerHeld("aim"), false, "visée relâchée")
			T.expectEqual(calls, 1, "rien au relâchement")
		end)

		T.it("tient le tir de R2 et la visée de L2 à la manette", function()
			local InputModule, uis = load()
			uis.InputBegan.fire(pad("ButtonR2"), false)
			uis.InputBegan.fire(pad("ButtonL2"), false)
			T.expectEqual(InputModule.isPointerHeld("fire"), true, "R2")
			T.expectEqual(InputModule.isPointerHeld("aim"), true, "L2")
			uis.InputEnded.fire(pad("ButtonR2"))
			uis.InputEnded.fire(pad("ButtonL2"))
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "R2 relâché")
			T.expectEqual(InputModule.isPointerHeld("aim"), false, "L2 relâché")
		end)

		T.it("reste tenu tant qu'une source le tient (souris et tactile)", function()
			local InputModule, uis = load()
			uis.InputBegan.fire(mouse(1), false)
			InputModule.setTouchPointer("fire", true)
			uis.InputEnded.fire(mouse(1))
			T.expectEqual(InputModule.isPointerHeld("fire"), true, "le tactile tient encore")
			InputModule.setTouchPointer("fire", false)
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "plus rien")
		end)

		T.it("le bouton tactile de visée déclenche la visée à l'appui seulement", function()
			local InputModule = load()
			local calls = 0
			InputModule.onAim(function()
				calls += 1
			end)
			InputModule.setTouchPointer("aim", true)
			T.expectEqual(InputModule.isPointerHeld("aim"), true, "tenue")
			InputModule.setTouchPointer("aim", false)
			T.expectEqual(calls, 1, "un appel")
		end)

		T.it("relâche tout à l'ouverture du menu et ne tient rien tant qu'il est ouvert", function()
			local InputModule, uis = load()
			uis.InputBegan.fire(mouse(1), false)
			uis.InputBegan.fire(mouse(2), false)
			InputModule.setSuspended(true)
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "tir relâché")
			T.expectEqual(InputModule.isPointerHeld("aim"), false, "visée relâchée")
			uis.InputBegan.fire(mouse(1), false)
			InputModule.setTouchPointer("aim", true)
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "clic menu ouvert")
			T.expectEqual(InputModule.isPointerHeld("aim"), false, "tactile menu ouvert")
		end)

		T.it("ne tient rien pendant le rejeu d'un parcours", function()
			local InputModule, uis = load()
			InputModule.setVirtual(true)
			uis.InputBegan.fire(mouse(1), false)
			T.expectEqual(InputModule.isPointerHeld("fire"), false, "rejeu")
		end)
	end)
end

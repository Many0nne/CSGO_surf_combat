-- État central du HUD (#223) : valeurs de départ, abonnés prévenus seulement d'un vrai changement, désabonnement.
return function(T, Loader)
	T.describe("HUDState", function()
		T.it("part du menu principal, menu en partie fermé, sans lunette", function()
			local HUDState = Loader.new():require("src/client/ui/HUDState")
			local hud = HUDState.get()
			T.expectEqual(hud.gameState, "MENU")
			T.expectEqual(hud.menuOpen, false)
			T.expectEqual(hud.scoped, false)
		end)

		T.it("prévient chaque abonné avec le nouvel et l'ancien état", function()
			local HUDState = Loader.new():require("src/client/ui/HUDState")
			local calls = {}
			HUDState.onChanged(function(hud, previous)
				table.insert(calls, previous.gameState .. ">" .. hud.gameState)
			end)
			HUDState.setGameState("IN_ROUND")
			HUDState.setMenuOpen(true)
			HUDState.setScoped(true)
			T.expectEqual(table.concat(calls, ","), "MENU>IN_ROUND,IN_ROUND>IN_ROUND,IN_ROUND>IN_ROUND")
			local hud = HUDState.get()
			T.expectEqual(hud.menuOpen, true)
			T.expectEqual(hud.scoped, true)
		end)

		T.it("ne prévient personne quand la valeur ne change pas", function()
			local HUDState = Loader.new():require("src/client/ui/HUDState")
			local count = 0
			HUDState.onChanged(function()
				count += 1
			end)
			HUDState.setGameState("MENU")
			HUDState.setMenuOpen(false)
			HUDState.setScoped(false)
			T.expectEqual(count, 0)
			HUDState.setScoped(true)
			HUDState.setScoped(true)
			T.expectEqual(count, 1)
		end)

		T.it("garde l'ancien instantané intact (un nouvel état à chaque changement)", function()
			local HUDState = Loader.new():require("src/client/ui/HUDState")
			local before = HUDState.get()
			HUDState.setMenuOpen(true)
			T.expectEqual(before.menuOpen, false)
			T.expectEqual(HUDState.get().menuOpen, true)
		end)

		T.it(
			"prévient les autres abonnés et rend la main quand un abonné échoue (erreur relancée à part)",
			function()
				local spawned = {}
				local fakeTask = {
					spawn = function(fn, ...)
						table.insert(spawned, { fn = fn, args = { ... } })
					end,
				}
				local HUDState = Loader.new(nil, { task = fakeTask }):require("src/client/ui/HUDState")
				local reached = false
				HUDState.onChanged(function()
					error("abonné cassé")
				end)
				HUDState.onChanged(function()
					reached = true
				end)
				HUDState.setMenuOpen(true)
				T.expectEqual(reached, true)
				T.expectEqual(HUDState.get().menuOpen, true)
				T.expectEqual(#spawned, 1)
				T.expectEqual(spawned[1].fn, error)
				T.expectEqual(string.find(tostring(spawned[1].args[1]), "abonné cassé", 1, true) ~= nil, true)
			end
		)

		T.it("ne prévient plus un abonné désabonné", function()
			local HUDState = Loader.new():require("src/client/ui/HUDState")
			local count = 0
			local disconnect = HUDState.onChanged(function()
				count += 1
			end)
			HUDState.setGameState("IN_ROUND")
			disconnect()
			HUDState.setGameState("DEAD")
			T.expectEqual(count, 1)
		end)
	end)
end

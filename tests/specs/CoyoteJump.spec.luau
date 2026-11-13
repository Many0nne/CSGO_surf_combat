return function(T, Loader)
	local Config = Loader.new():require("src/shared/MovementConfig")
	local DT = 1 / 64
	local NO_PRESS = 10 -- secondes depuis le dernier appui : hors buffer

	-- Cette méthode permet d'obtenir un CoyoteJump neuf (état vierge) lorsqu'un test démarre.
	local function fresh()
		return Loader.new():require("src/client/systems/movement/CoyoteJump")
	end

	-- Cette méthode permet de construire l'entrée d'un tick : appui (front montant) et ancienneté de l'appui.
	local function input(pressed: boolean, sincePress: number?)
		return { jumpPressed = pressed, timeSincePress = sincePress or (if pressed then 0 else NO_PRESS) }
	end

	T.describe("CoyoteJump.update", function()
		T.it("saut normal : appui au sol", function()
			local c = fresh()
			T.expectEqual(c.update(true, DT, input(false)), false)
			T.expectEqual(c.update(true, DT, input(true)), true)
		end)

		T.it("coyote : appui juste après avoir quitté le sol sans sauter", function()
			local c = fresh()
			c.update(true, DT, input(false))
			c.update(false, DT, input(false)) -- quitte le sol (rebord)
			T.expectEqual(c.update(false, DT, input(true)), true)
		end)

		T.it("coyote : appui après la fenêtre refusé", function()
			local c = fresh()
			c.update(true, DT, input(false))
			c.update(false, DT, input(false))
			local elapsed = 0
			while elapsed <= Config.COYOTE_TIME + DT do
				c.update(false, DT, input(false))
				elapsed += DT
			end
			T.expectEqual(c.update(false, DT, input(true)), false)
		end)

		T.it("buffer : appui juste avant l'atterrissage", function()
			local c = fresh()
			c.update(false, DT, input(false))
			T.expectEqual(c.update(true, DT, input(false, Config.JUMP_BUFFER_TIME / 2)), true)
		end)

		T.it("buffer : appui trop ancien avant l'atterrissage refusé", function()
			local c = fresh()
			c.update(false, DT, input(false))
			T.expectEqual(c.update(true, DT, input(false, Config.JUMP_BUFFER_TIME * 2)), false)
		end)

		T.it("saut forcé (auto-bhop) puis appui sous COYOTE_TIME : pas de second saut", function()
			local c = fresh()
			c.update(false, DT, input(false))
			c.update(true, DT, input(false)) -- atterrissage, espace maintenu (pas de front montant)
			c.notifyForcedJump() -- BhopSystem force le saut
			c.update(false, DT, input(false)) -- décolle
			T.expectEqual(c.update(false, DT, input(true)), false)
		end)

		T.it("sans notification, le défaut #294 est bien présent (garde-fou du test précédent)", function()
			local c = fresh()
			c.update(false, DT, input(false))
			c.update(true, DT, input(false))
			c.update(false, DT, input(false))
			T.expectEqual(c.update(false, DT, input(true)), true)
		end)
	end)

	T.describe("CoyoteJump.init", function()
		T.it("remet l'état à zéro : pas de coyote hérité de la vie précédente", function()
			local c = fresh()
			c.update(true, DT, input(false))
			c.update(false, DT, input(false)) -- fenêtre coyote ouverte
			c.init()
			-- réapparition en l'air : aucune fenêtre, appui refusé
			T.expectEqual(c.update(false, DT, input(true)), false)
		end)

		T.it("remet didTriggerJump à zéro : le coyote s'ouvre de nouveau après init", function()
			local c = fresh()
			c.notifyForcedJump()
			c.init()
			c.update(true, DT, input(false))
			c.update(false, DT, input(false))
			T.expectEqual(c.update(false, DT, input(true)), true)
		end)
	end)
end

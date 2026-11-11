return function(T, Loader)
	local Config = Loader.new():require("src/shared/MovementConfig")
	local DT = 1 / 64

	-- Cette méthode permet d'obtenir un BhopSystem neuf (état d'atterrissage vierge) lorsqu'un test démarre.
	local function fresh()
		return Loader.new():require("src/client/systems/movement/BhopSystem")
	end

	T.describe("BhopSystem.update", function()
		T.it("avec auto-bhop, espace maintenu au sol : saut forcé et friction ignorée", function()
			local bhop = fresh()
			bhop.update(false, false, DT, true, true)
			local r = bhop.update(true, false, DT, true, true) -- atterrissage, espace maintenu
			T.expectEqual(r.forceJump, true)
			T.expectEqual(r.skipFriction, true)
		end)

		T.it("sans auto-bhop, espace maintenu à l'atterrissage : aucun saut forcé", function()
			local bhop = fresh()
			bhop.update(false, false, DT, true, false)
			local r = bhop.update(true, false, DT, true, false)
			T.expectEqual(r.forceJump, false)
			T.expectEqual(r.skipFriction, false)
			-- reste au sol, espace toujours maintenu : toujours pas de saut
			r = bhop.update(true, false, DT, true, false)
			T.expectEqual(r.forceJump, false)
		end)

		T.it("sans auto-bhop, appui au bon moment : saut et friction ignorée", function()
			local bhop = fresh()
			bhop.update(false, false, DT, false, false)
			local r = bhop.update(true, true, DT, true, false) -- atterrissage + saut de CoyoteJump
			T.expectEqual(r.forceJump, false)
			T.expectEqual(r.skipFriction, true)
		end)

		T.it("sans auto-bhop, appui trop tard après l'atterrissage : friction appliquée", function()
			local bhop = fresh()
			bhop.update(false, false, DT, false, false)
			local elapsed = 0
			local r
			while elapsed <= Config.BHOP_LAND_WINDOW + DT do
				r = bhop.update(true, false, DT, false, false)
				elapsed += DT
			end
			r = bhop.update(true, true, DT, true, false)
			T.expectEqual(r.skipFriction, false)
		end)

		T.it("espace relâché avec auto-bhop : pas de saut forcé", function()
			local bhop = fresh()
			bhop.update(false, false, DT, false, true)
			T.expectEqual(bhop.update(true, false, DT, false, true).forceJump, false)
		end)
	end)
end

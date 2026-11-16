-- Place du pochoir de la caisse face aux boîtes des pièces (#456) : boîtes de Crate.rbxm actuel, relevées par
-- tools/shop/crate_model.py (repère du pivot, x à droite, y en haut, z vers l'avant)
return function(T, Loader)
	local CrateStencil = Loader.new({}):require("src/shared/CrateStencil")

	-- Cette méthode permet de construire les boîtes de la caisse actuelle, avec une pièce remplacée lorsqu'un test simule
	-- une caisse régénérée avec d'autres cotes.
	local function crate(overrides: { [string]: any }?)
		local boxes = {
			LidPlanks = { min = { -2.0, 1.47, -1.2 }, max = { 2.0, 2.0, 1.2 } },
			LidStripe = { min = { -1.6, 1.525, -1.1 }, max = { 0.35, 2.01, 1.209 } },
		}
		for name, box in overrides or {} do
			boxes[name] = if box == false then nil else box
		end
		return boxes
	end

	T.describe("CrateStencil : pochoir du couvercle (#456)", function()
		T.it("la caisse actuelle accueille le pochoir", function()
			T.expectEqual(#CrateStencil.problems(crate()), 0)
		end)

		T.it("lettres au-dessus du moraillon (haut à 1,64) et à gauche de la cornière (1,59)", function()
			local rect, back = CrateStencil.inkRect()
			T.expect(rect.min[2] > 1.64, "bas des lettres " .. rect.min[2])
			T.expect(rect.max[1] < 1.59, "bord droit " .. rect.max[1])
			T.expect(back >= 1.2 and back - 1.2 <= CrateStencil.MAX_GAP, "dos " .. back)
		end)

		T.it("couvercle plus profond : pochoir enfoncé dans le bois", function()
			local problems =
				CrateStencil.problems(crate({ LidPlanks = { min = { -2, 1.47, -1.3 }, max = { 2, 2, 1.3 } } }))
			T.expectEqual(#problems, 1)
			T.expect(string.find(problems[1], "enfoncé", 1, true) ~= nil, problems[1])
		end)

		T.it("couvercle moins profond : pochoir flottant", function()
			local problems =
				CrateStencil.problems(crate({ LidPlanks = { min = { -2, 1.47, -1.1 }, max = { 2, 2, 1.1 } } }))
			T.expectEqual(#problems, 1)
			T.expect(string.find(problems[1], "flottant", 1, true) ~= nil, problems[1])
		end)

		T.it("bande plus longue : pochoir sous la bande", function()
			local problems =
				CrateStencil.problems(crate({ LidStripe = { min = { -1.6, 1.5, -1.1 }, max = { 0.6, 2.0, 1.21 } } }))
			T.expectEqual(#problems, 1)
			T.expect(string.find(problems[1], "bande", 1, true) ~= nil, problems[1])
		end)

		T.it("couvercle plus bas ou plus étroit : pochoir hors du couvercle", function()
			local problems =
				CrateStencil.problems(crate({ LidPlanks = { min = { -1.2, 1.3, -1.2 }, max = { 1.2, 1.7, 1.2 } } }))
			T.expectEqual(#problems, 2)
		end)

		T.it("caisse sans planches de couvercle ni bande", function()
			T.expectEqual(#CrateStencil.problems(crate({ LidPlanks = false })), 1)
			T.expectEqual(#CrateStencil.problems(crate({ LidStripe = false })), 0)
		end)
	end)
end

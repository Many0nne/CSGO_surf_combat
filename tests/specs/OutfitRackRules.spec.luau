-- Règles pures du portant des tenues (#543) : tenues en vente lues au catalogue, place sur la barre et cintres vides,
-- sortie du rang de la tenue survolée.
return function(T, Loader)
	local loader = Loader.new({})
	local Rules = loader:require("src/shared/OutfitRackRules")
	local Inventory = loader:require("src/shared/InventoryRules")
	local Purchase = loader:require("src/server/OutfitPurchaseRules")

	T.describe("OutfitRackRules.forSale", function()
		T.it("montre au portant exactement les tenues que le serveur vend, dans l'ordre du catalogue", function()
			local shown = Rules.forSale()
			local sold = 0
			for _, item in Inventory.outfits() do
				if Purchase.order(item.id) then
					sold += 1
				end
			end
			T.expectEqual(#shown, sold)
			T.expect(#shown >= 1, "au moins une tenue en vente")
			for i, item in shown do
				T.expect(Purchase.order(item.id) ~= nil, "vendue par le serveur : " .. item.id)
				if i > 1 then
					T.expect((shown[i - 1].price :: number) <= (item.price :: number), "triées par prix")
				end
			end
		end)
	end)

	T.describe("OutfitRackRules.slots", function()
		T.it("complète le rang de cintres vides, tenues au milieu", function()
			local slots = Rules.slots(2, 13.2)
			T.expectEqual(#slots, 6)
			local ranks = {}
			for _, slot in slots do
				table.insert(ranks, slot.outfit or 0)
			end
			T.expectEqual(table.concat(ranks, ","), "0,0,1,2,0,0")
		end)

		T.it("répartit les cintres à pas égal entre les marges, centrés sur le portant", function()
			local slots = Rules.slots(6, 13.2)
			T.expectEqual(#slots, 6)
			T.expect(math.abs(slots[1].x + 5.1) < 1e-6, "premier à -5,1 : " .. slots[1].x)
			T.expect(math.abs(slots[6].x - 5.1) < 1e-6, "dernier à 5,1 : " .. slots[6].x)
			for i, slot in slots do
				T.expectEqual(slot.outfit, i)
			end
		end)

		T.it("serre les cintres au-delà de six tenues, sans cintre vide", function()
			local slots = Rules.slots(9, 13.2)
			T.expectEqual(#slots, 9)
			for i, slot in slots do
				T.expectEqual(slot.outfit, i)
			end
			T.expect(slots[2].x - slots[1].x < 1.3, "pas resserré")
		end)

		T.it("met le cintre vide en trop à droite quand le reste est impair", function()
			local ranks = {}
			for _, slot in Rules.slots(3, 13.2) do
				table.insert(ranks, slot.outfit or 0)
			end
			T.expectEqual(table.concat(ranks, ","), "0,1,2,3,0,0")
		end)
	end)

	T.describe("OutfitRackRules.pose", function()
		T.it("de trois quarts dans le rang, de face et avancée une fois sortie, bornée", function()
			local yaw, step = Rules.pose(0)
			T.expectEqual(yaw, Rules.RANK_YAW)
			T.expectEqual(step, 0)
			yaw, step = Rules.pose(1)
			T.expectEqual(yaw, Rules.OUT_YAW)
			T.expectEqual(step, Rules.OUT_STEP)
			yaw, step = Rules.pose(3)
			T.expectEqual(yaw, Rules.OUT_YAW)
		end)
	end)
end

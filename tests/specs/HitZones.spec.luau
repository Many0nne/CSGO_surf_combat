return function(T, Loader)
	local HitZones = Loader.new({}):require("src/shared/HitZones")
	local Zone = HitZones.Zone

	T.describe("HitZones", function()
		T.it("classe toutes les parties du rig R15", function()
			local single =
				{ Head = Zone.HEAD, UpperTorso = Zone.TORSO, LowerTorso = Zone.TORSO, HumanoidRootPart = Zone.TORSO }
			for name, zone in single do
				T.expectEqual(HitZones.zoneOf(name), zone, name)
			end
			local paired = {
				UpperArm = Zone.ARMS,
				LowerArm = Zone.ARMS,
				Hand = Zone.ARMS,
				UpperLeg = Zone.LEGS,
				LowerLeg = Zone.LEGS,
				Foot = Zone.LEGS,
			}
			for name, zone in paired do
				T.expectEqual(HitZones.zoneOf("Left" .. name), zone, "Left" .. name)
				T.expectEqual(HitZones.zoneOf("Right" .. name), zone, "Right" .. name)
			end
		end)

		T.it("ne classe pas une partie inconnue", function()
			T.expectEqual(HitZones.zoneOf("Handle"), nil)
			T.expectEqual(HitZones.zoneOf(nil), nil)
		end)

		T.it("donne les dégâts de l'AWP par zone : seules les jambes ne tuent pas", function()
			T.expectEqual(HitZones.damageFor(115, Zone.HEAD), 460)
			T.expectEqual(HitZones.damageFor(115, Zone.TORSO), 115)
			T.expectEqual(HitZones.damageFor(115, Zone.ARMS), 115)
			T.expectEqual(HitZones.damageFor(115, Zone.LEGS), 86)
		end)

		T.it("compte une zone inconnue à ×1", function()
			T.expectEqual(HitZones.damageFor(115, nil), 115)
		end)
	end)
end

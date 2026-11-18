-- Éclair de tir d'un skin (#520) : forme tirée au hasard, tube autour du rayon, branches, déroulé de l'éclat.
return function(T, Loader)
	local LightningRules = Loader.new():require("src/shared/LightningRules")
	local ShotEffectRules = Loader.new():require("src/shared/ShotEffectRules")

	-- Cette méthode permet de fabriquer un tirage au hasard reproductible (suite congruentielle) lorsqu'un test
	-- dessine un éclair.
	local function seeded(seed: number)
		local state = seed
		return function(min: number, max: number): number
			state = (state * 1103515245 + 12345) % 2147483648
			return min + (max - min) * (state / 2147483648)
		end
	end

	-- Cette méthode permet de mesurer l'écart d'un point à la droite start → finish lorsqu'on vérifie le tube.
	local function distanceToAxis(point, start, finish): number
		local axis = (finish - start).Unit
		local along = (point - start):Dot(axis)
		return (point - (start + axis * along)).Magnitude
	end

	local START = Vector3.new(0, 10, 0)
	local FINISH = Vector3.new(0, 10, -200)

	T.describe("LightningRules.build (#520)", function()
		T.it("le tronc part du canon et finit sur l'impact", function()
			local lines = LightningRules.build(START, FINISH, seeded(1))
			local trunk = lines[1]
			T.expectEqual(trunk.kind, "trunk")
			T.expectEqual(trunk.points[1], START)
			T.expectEqual(trunk.points[#trunk.points], FINISH)
		end)

		T.it("le tronc est brisé, mais reste dans un tube autour du rayon de visée", function()
			local trunk = LightningRules.build(START, FINISH, seeded(2))[1]
			local maxOffset = 0
			for _, point in trunk.points do
				maxOffset = math.max(maxOffset, distanceToAxis(point, START, FINISH))
			end
			T.expect(maxOffset > 0.3, "tronc trop droit : " .. maxOffset)
			-- somme des écarts plafonnés de chaque niveau
			local bound = LightningRules.TRUNK_MAX_OFFSET * LightningRules.MAX_LEVELS
			T.expect(maxOffset <= bound, "tronc hors du tube : " .. maxOffset)
		end)

		T.it("se resserre près du canon : pas de grand zigzag sous les yeux du tireur", function()
			-- tir court : des points du tronc tombent dans la rampe du canon
			local finish = START + Vector3.new(0, 0, -40)
			local bound = LightningRules.TRUNK_MAX_OFFSET * LightningRules.MAX_LEVELS
			local checked = 0
			for seed = 10, 20 do
				local trunk = LightningRules.build(START, finish, seeded(seed))[1]
				for _, point in trunk.points do
					local along = (point - START).Magnitude
					if along < LightningRules.RAMP_FROM_MUZZLE then
						checked += 1
						local allowed = bound * along / LightningRules.RAMP_FROM_MUZZLE + 1e-6
						T.expect(distanceToAxis(point, START, finish) <= allowed, "écart près du canon")
					end
				end
			end
			T.expect(checked > 10, "aucun point près du canon")
		end)

		T.it("change de forme à chaque tir", function()
			local a = LightningRules.build(START, FINISH, seeded(4))[1].points
			local b = LightningRules.build(START, FINISH, seeded(5))[1].points
			T.expect((a[3] - b[3]).Magnitude > 1e-3, "même forme pour deux tirs")
		end)

		T.it("porte des branches qui partent du tronc, et un nombre de segments borné", function()
			local lines = LightningRules.build(START, FINISH, seeded(6))
			local trunkPoints = {}
			for _, point in lines[1].points do
				trunkPoints[point] = true
			end
			local branches, segments = 0, 0
			for _, line in lines do
				segments += #line.points - 1
				if line.kind == "branch" then
					branches += 1
					T.expect(trunkPoints[line.points[1]] == true, "branche détachée du tronc")
				end
			end
			T.expectEqual(branches, LightningRules.MAX_BRANCHES)
			local maxSegments = 2 ^ LightningRules.MAX_LEVELS
				+ LightningRules.MAX_BRANCHES * (2 ^ LightningRules.BRANCH_LEVELS + 2 ^ LightningRules.TWIG_LEVELS)
			T.expect(segments <= maxSegments, "trop de segments : " .. segments)
		end)

		T.it("la réserve préparée (maxCounts) couvre l'éclair le plus chargé, sorte par sorte", function()
			local maxSegments, maxPoints = LightningRules.maxCounts()
			for seed = 30, 60 do
				local lines = LightningRules.build(START, START + Vector3.new(0, 0, -900), seeded(seed))
				local segments, points = {}, 0
				for _, line in lines do
					segments[line.kind] = (segments[line.kind] or 0) + #line.points - 1
					points += #line.points
				end
				for kind, count in segments do
					T.expect(count <= (maxSegments[kind] or 0), kind .. " : " .. count)
				end
				T.expect(points <= maxPoints, "points : " .. points)
			end
		end)

		T.it("une branche ne dépasse pas le point d'impact", function()
			for seed = 70, 90 do
				for _, line in LightningRules.build(START, FINISH, seeded(seed)) do
					local axis = (FINISH - START).Unit
					for _, point in line.points do
						local along = (point - START):Dot(axis)
						T.expect(along <= (FINISH - START).Magnitude + LightningRules.BRANCH_LENGTH[1], line.kind)
					end
				end
			end
		end)

		T.it("un tir à bout portant a au moins un tronc ; deux points confondus ne donnent rien", function()
			local short = LightningRules.build(START, START + Vector3.new(0, 0, -2), seeded(7))
			T.expect(#short >= 1, "pas de tronc")
			T.expectEqual(#LightningRules.build(START, START, seeded(8)), 0)
		end)
	end)

	T.describe("LightningRules.intensity et fadeStep (#520)", function()
		local life = LightningRules.LIFETIME

		T.it("flash, retombée, second flash, puis extinction à la fin de sa vie", function()
			T.expectEqual(LightningRules.intensity(0), 1)
			T.expectEqual(LightningRules.intensity(life * 0.2), LightningRules.DIM)
			T.expectEqual(LightningRules.intensity(life * 0.35), 1)
			local fading = LightningRules.intensity(life * 0.7)
			T.expect(fading > 0 and fading < 1, tostring(fading))
			T.expectEqual(LightningRules.intensity(life), 0)
		end)

		T.it("palier : transparence de base au plein éclat, invisible éteint ou caché", function()
			local steps = LightningRules.FADE_STEPS
			T.expectEqual(LightningRules.fadeStep(0, 1, false), 0)
			T.expectEqual(LightningRules.fadeStep(0.5, 1, false), steps / 2)
			T.expectEqual(LightningRules.fadeStep(0, 0, false), steps)
			T.expectEqual(LightningRules.fadeStep(0, 1, true), steps)
		end)
	end)

	T.describe("ShotEffectRules.styleOf (#520, #566)", function()
		T.it("chaque effet de la caisse joue son style, et un style désactivé redonne le rayon ordinaire", function()
			T.expectEqual(ShotEffectRules.styleOf("effect.eclair"), "lightning")
			T.expectEqual(ShotEffectRules.styleOf("effect.pan"), "pan")
			-- TREMPE mis de côté : plus d'item, style désactivé
			T.expectEqual(ShotEffectRules.styleOf("effect.trempe"), nil)
			T.expectEqual(ShotEffectRules.isEnabled("temper"), false)
			local saved = ShotEffectRules.STYLES.lightning
			ShotEffectRules.STYLES.lightning = false
			T.expectEqual(ShotEffectRules.styleOf("effect.eclair"), nil)
			T.expectEqual(ShotEffectRules.isEnabled("lightning"), false)
			ShotEffectRules.STYLES.lightning = saved
			T.expectEqual(ShotEffectRules.isEnabled("lightning"), true)
		end)

		T.it("un skin ne porte plus d'effet : ORAGE tire le rayon ordinaire (#566)", function()
			T.expectEqual(ShotEffectRules.styleOf("skin.awp.orage"), nil)
			T.expectEqual(ShotEffectRules.styleOf("skin.awp.pan"), nil)
		end)

		T.it("aucun effet, un id inconnu ou une arme gardent le rayon ordinaire", function()
			T.expectEqual(ShotEffectRules.styleOf(""), nil)
			T.expectEqual(ShotEffectRules.styleOf(nil), nil)
			T.expectEqual(ShotEffectRules.styleOf("effect.none"), nil)
			T.expectEqual(ShotEffectRules.styleOf("effect.inconnu"), nil)
			T.expectEqual(ShotEffectRules.styleOf("weapon.awp"), nil)
		end)

		T.it("le style d'un tireur se lit sur ses attributs, l'effet devant être possédé", function()
			local equipped = "weapon.awp:skin.awp.maquis,weapon.kabar,,effect.pan"
			T.expectEqual(ShotEffectRules.styleOfPlayer(equipped, "effect.pan"), "pan")
			T.expectEqual(ShotEffectRules.styleOfPlayer(equipped, ""), nil)
			T.expectEqual(ShotEffectRules.styleOfPlayer("weapon.awp,weapon.kabar", "effect.pan"), nil)
			T.expectEqual(ShotEffectRules.styleOfPlayer(nil, nil), nil)
		end)
	end)
end

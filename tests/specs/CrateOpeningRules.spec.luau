-- Chronologie de l'ouverture d'une caisse (#332) : temps relevés sur la référence Apex (charge étirée), tension avant
-- l'explosion, colonne et silhouette qui montent, montée de couleur, effets bornés, saut au clic.
return function(T, Loader)
	local R = Loader.new({}):require("src/shared/CrateOpeningRules")

	T.describe("CrateOpeningRules : chronologie", function()
		T.it(
			"révélation après la montée de la silhouette et sa tenue, plus tardive pour une rareté plus haute",
			function()
				local common = R.revealTime("common") - R.COLUMN
				local rare = R.revealTime("rare") - R.COLUMN
				local exceptional = R.revealTime("exceptional") - R.COLUMN
				local legendary = R.revealTime("legendary") - R.COLUMN
				T.expect(common > R.RISE_TIME, "la silhouette a fini de monter avant la révélation")
				T.expect(common < rare and rare < exceptional and exceptional < legendary, "suspense croissant")
				T.expectNear(R.revealTime(nil) - R.COLUMN, R.RISE_TIME + R.DEFAULT_HOLD)
			end
		)

		T.it("ordre des phases : charge, tension, temps d'arrêt, explosion, couvercle, colonne", function()
			T.expect(R.CRACKLE_START < R.PULSES[1].at, "crépitements avant la première bouffée")
			T.expect(R.TIER_AT[#R.TIER_AT] < R.TENSION_START, "couleur finale avant la tension")
			T.expect(R.TENSION_START < R.BURST - R.PAUSE, "la tension monte avant le temps d'arrêt")
			T.expect(R.BURST < R.LID_START and R.LID_START < R.COLUMN, "couvercle après l'explosion")
			T.expect(R.LID_START + R.LID_TIME <= R.COLUMN + R.COLUMN_GROW, "couvercle parti quand la colonne a grandi")
			T.expectEqual(R.SPARKS[#R.SPARKS], R.BURST)
		end)

		T.it("calme avant les crépitements : lueur de fond, pas de secousse ni d'éclair", function()
			local s = R.sample(0.1, "rare")
			T.expectEqual(s.shake, 0)
			T.expectEqual(s.lift, 0)
			T.expectNear(s.glow, 0.15)
			T.expectEqual(s.flash, 0)
			T.expectEqual(s.lid, 0)
			T.expectEqual(s.column, 0)
			T.expectEqual(s.revealed, false)
		end)

		T.it("une bouffée éclate en une image et s'éteint en PULSE_DECAY", function()
			local p = R.PULSES[1]
			T.expectNear(R.pulse(p.at + R.PULSE_ATTACK), p.power)
			T.expectEqual(R.pulse(p.at + R.PULSE_ATTACK + R.PULSE_DECAY + 0.01), 0)
			T.expect(R.sample(p.at + R.PULSE_ATTACK, "rare").glow >= p.power - 1e-6, "la lueur suit la bouffée")
		end)

		T.it("chaque bouffée jaillit par la fente, la bouffée à rayons à pleine force et plus longtemps", function()
			local first = R.PULSES[1]
			T.expectEqual(R.sample(first.at - 0.05, "rare").rays, 0)
			T.expectNear(R.sample(first.at + R.PULSE_ATTACK, "rare").rays, 0.8 * first.power, 1e-6)
			local rays
			for _, p in R.PULSES do
				if p.rays then
					rays = p
				end
			end
			T.expectNear(R.sample(rays.at + 0.3, "rare").rays, rays.power)
			T.expectEqual(R.sample(R.BURST + 0.1, "rare").rays, 0)
		end)

		T.it("la charge reprend les instants d'Apex étirés de CHARGE_SCALE", function()
			local apexPulses = { 0.8, 1.2, 1.5, 1.9, 2.4, 2.9 } -- 28,8 … 30,9 s de la référence, depuis 28,0 s
			for i, at in apexPulses do
				T.expectNear(R.PULSES[i].at, at * R.CHARGE_SCALE)
			end
			T.expectNear(R.BURST, 3.0 * R.CHARGE_SCALE)
			for i, at in { 2.0, 2.5, 3.0 } do
				T.expectNear(R.SPARKS[i], at * R.CHARGE_SCALE)
			end
		end)

		T.it("la caméra a fini d'avancer en PUSH_TIME", function()
			T.expectEqual(R.sample(0, "rare").push, 0)
			T.expectNear(R.sample(R.PUSH_TIME, "rare").push, 1)
		end)
	end)

	T.describe("CrateOpeningRules : tension avant l'explosion", function()
		T.it("secousses, soulèvement et lueur montent jusqu'au plein avant le temps d'arrêt", function()
			T.expectEqual(R.tension(R.TENSION_START), 0)
			local before = R.sample(R.TENSION_START + 0.1, "rare")
			local peak = R.sample(R.BURST - R.PAUSE - 0.001, "rare")
			T.expect(peak.lift > before.lift, "la caisse se soulève")
			T.expect(peak.shake >= 0.99, "secousses au plein")
			T.expect(peak.glow >= 0.99, "fente saturée")
		end)

		T.it(
			"temps d'arrêt : plus de secousse ni de jaillissement, la caisse reste soulevée et pleine de lumière",
			function()
				local s = R.sample(R.BURST - R.PAUSE / 2, "rare")
				T.expectEqual(s.shake, 0)
				T.expectEqual(s.rays, 0)
				T.expectEqual(s.lift, 1)
				T.expectEqual(s.glow, 1)
			end
		)

		T.it("explosion : éclair plein, la caisse retombe sur le socle en LIFT_DROP", function()
			local s = R.sample(R.BURST, "rare")
			T.expectNear(s.flash, 1)
			T.expectEqual(s.glow, 1)
			T.expectEqual(s.shake, 0)
			T.expectEqual(R.sample(R.BURST + R.LIFT_DROP, "rare").lift, 0)
		end)
	end)

	T.describe("CrateOpeningRules : colonne, silhouette et révélation", function()
		T.it("la colonne grandit depuis la caisse en COLUMN_GROW puis se resserre derrière la silhouette", function()
			T.expectEqual(R.sample(R.COLUMN - 0.01, "rare").column, 0)
			local start = R.sample(R.COLUMN + 0.01, "rare")
			T.expectEqual(start.column, 1)
			T.expect(start.columnHeight > 0 and start.columnHeight < 0.2, "la colonne part du bas")
			T.expectNear(R.sample(R.COLUMN + R.COLUMN_GROW, "rare").columnHeight, 1)
			local settled = R.sample(R.COLUMN + R.COLUMN_GROW + R.COLUMN_SETTLE, "rare")
			T.expectNear(settled.column, R.COLUMN_REST)
			T.expectNear(settled.columnWidth, 0.4)
		end)

		T.it("la silhouette s'élève lentement hors de la caisse, des braises montent, puis elle tient", function()
			T.expectEqual(R.sample(R.COLUMN, "rare").rise, 0)
			local mid = R.sample(R.COLUMN + R.RISE_TIME / 2, "rare")
			T.expectNear(mid.rise, 0.5)
			T.expectEqual(mid.embers, 1)
			T.expectNear(R.sample(R.COLUMN + R.SILHOUETTE_FADE, "rare").silhouette, 1)
			T.expectNear(R.sample(R.COLUMN + R.RISE_TIME, "rare").rise, 1)
			T.expectEqual(R.sample(R.COLUMN - 0.01, "rare").embers, 0)
		end)

		T.it("révélation : silhouette et braises éteintes, arme montrée, éclair", function()
			local at = R.revealTime("exceptional")
			local before = R.sample(at - 0.01, "exceptional")
			T.expectEqual(before.revealed, false)
			T.expectNear(before.silhouette, 1)
			local s = R.sample(at, "exceptional")
			T.expectEqual(s.revealed, true)
			T.expectEqual(s.silhouette, 0)
			T.expectEqual(s.embers, 0)
			T.expectNear(s.flash, 1)
			T.expectEqual(R.sample(at + R.COLUMN_FADE, "exceptional").column, 0)
		end)

		T.it("l'arme monte de trois quarts, tourne en ralentissant et finit de profil", function()
			T.expectEqual(R.sample(R.COLUMN, "rare").spin, -R.SPIN_FROM)
			local spinEnd = R.revealTime("rare") + R.SPIN_AFTER
			T.expectNear(R.sample(spinEnd, "rare").spin, 0, 0.01)
			for i = 0, 200 do
				local spin = R.sample(R.COLUMN + i / 50, "exceptional").spin
				T.expect(math.abs(spin) < 80, "jamais par la tranche : " .. spin)
			end
			local a = R.sample(R.COLUMN + 0.1, "rare").spin - R.sample(R.COLUMN, "rare").spin
			local b = R.sample(spinEnd, "rare").spin - R.sample(spinEnd - 0.1, "rare").spin
			T.expect(a > b, "la rotation ralentit")
		end)

		T.it("toutes les valeurs restent bornées sur toute l'ouverture", function()
			local keys = {
				"push",
				"shake",
				"lift",
				"glow",
				"rays",
				"flash",
				"lid",
				"column",
				"columnHeight",
				"embers",
				"silhouette",
				"rise",
			}
			for i = 0, 1000 do
				local s = R.sample(i / 100, "exceptional")
				for _, key in keys do
					local v = s[key]
					T.expect(v >= 0 and v <= 1, string.format("%s = %s à %.2f s", key, tostring(v), i / 100))
				end
			end
		end)
	end)

	T.describe("CrateOpeningRules : montée de couleur par paliers", function()
		local Shop = Loader.new({}):require("src/shared/ShopCatalog")

		T.it("les paliers suivent l'ordre des raretés du shop", function()
			T.expectEqual(#R.TIERS, #Shop.RARITIES)
			for i, rarity in Shop.RARITIES do
				T.expectEqual(R.TIERS[i], rarity.id)
				T.expect(R.HOLD[rarity.id] ~= nil, "tenue de " .. rarity.id)
			end
			T.expectEqual(R.tierOf("unknown"), 1)
		end)

		T.it("la charge commence au premier palier, quelle que soit la rareté", function()
			for _, id in R.TIERS do
				for _, t in { 0, 0.5, R.PULSES[1].at, R.tierTime(2) - 0.01 } do
					T.expectEqual(R.sample(t, id).tier, 1)
				end
			end
		end)

		T.it("les paliers montent pendant la charge, chacun sur une bouffée", function()
			for k = 2, #R.TIERS do
				local at = R.tierTime(k)
				local onPulse = false
				for _, pulse in R.PULSES do
					onPulse = onPulse or pulse.at == at
				end
				T.expect(onPulse, "palier " .. k .. " sur une bouffée")
			end
			T.expectEqual(R.sample(R.tierTime(2), "exceptional").tier, 2)
			T.expectEqual(R.sample(R.tierTime(3), "exceptional").tier, 3)
			T.expectEqual(R.sample(R.tierTime(4), "legendary").tier, 4)
			T.expectEqual(R.sample(R.tierTime(4), "exceptional").tier, 3)
			T.expectEqual(R.sample(R.tierTime(3), "rare").tier, 2)
		end)

		T.it("elle monte d'un palier à la fois jusqu'à la rareté tirée, et s'y arrête", function()
			for target, id in R.TIERS do
				local last = 1
				for i = 0, 1000 do
					local tier = R.sample(i / 100, id).tier
					T.expect(tier == last or tier == last + 1, string.format("%s : saut de %d à %d", id, last, tier))
					last = tier
				end
				T.expectEqual(last, target)
			end
		end)

		T.it("tension, explosion, colonne et silhouette sont dans la couleur finale", function()
			for target, id in R.TIERS do
				for _, t in
					{
						R.TENSION_START,
						R.BURST,
						R.COLUMN,
						R.COLUMN + R.RISE_TIME,
						R.revealTime(id),
					}
				do
					T.expectEqual(R.sample(t, id).tier, target)
				end
			end
		end)

		T.it("un commun ne change jamais de couleur", function()
			for i = 0, 1000 do
				T.expectEqual(R.sample(i / 100, "common").tier, 1)
			end
		end)
	end)

	T.describe("CrateOpeningRules : clic et événements", function()
		T.it("un clic pendant la charge saute à la révélation, après elle ne change rien", function()
			T.expectEqual(R.skip(1.0, "common"), R.revealTime("common"))
			T.expectEqual(R.skip(10, "common"), 10)
		end)

		T.it("une gerbe part une seule fois, à l'image qui franchit son instant", function()
			local first = R.SPARKS[1]
			T.expectEqual(#R.crossed(R.SPARKS, first - 0.1, first), 1)
			T.expectEqual(#R.crossed(R.SPARKS, first, first + 0.1), 0)
			T.expectEqual(#R.crossed(R.SPARKS, 0, 10), #R.SPARKS)
		end)

		T.it("le tremblement est reproductible et borné", function()
			local x1, y1, r1 = R.jitter(1.234)
			local x2, y2, r2 = R.jitter(1.234)
			T.expectEqual(x1, x2)
			T.expectEqual(y1, y2)
			T.expectEqual(r1, r2)
			for i = 0, 200 do
				local x, y, r = R.jitter(i / 37)
				T.expect(math.abs(x) <= 1 and math.abs(y) <= 1 and math.abs(r) <= 1, "borné")
			end
		end)
	end)
end

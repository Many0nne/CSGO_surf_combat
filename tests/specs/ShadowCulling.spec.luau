return function(T, Loader)
	local SC = Loader.new():require("tools/map/ShadowCulling")

	local SUN_X = { 1, 0, 0 } -- soleil à l'horizon, vers +X

	-- Cette méthode permet de construire une boîte alignée sur les axes lorsqu'un test pose une scène simple.
	local function box(px, py, pz, sx, sy, sz, wedge)
		return {
			px = px,
			py = py,
			pz = pz,
			xx = 1,
			xy = 0,
			xz = 0,
			yx = 0,
			yy = 1,
			yz = 0,
			zx = 0,
			zy = 0,
			zz = 1,
			sx = sx,
			sy = sy,
			sz = sz,
			wedge = wedge or false,
		}
	end

	-- Cette méthode permet de lancer le calcul avec toutes les boîtes masques et candidates lorsqu'un test n'a pas
	-- besoin de les distinguer.
	local function run(boxes, sun)
		local all = {}
		for i in boxes do
			all[i] = true
		end
		return SC.shadowed(boxes, all, all, sun or SUN_X)
	end

	T.describe("ShadowCulling.rayHits", function()
		T.it("boîte : traversée, ratée, origine à l'intérieur", function()
			local b = box(10, 0, 0, 2, 2, 2)
			T.expect(SC.rayHits(b, 0, 0, 0, 1, 0, 0, 100))
			T.expect(not SC.rayHits(b, 0, 5, 0, 1, 0, 0, 100))
			T.expect(not SC.rayHits(b, 0, 0, 0, -1, 0, 0, 100))
			T.expect(SC.rayHits(b, 10, 0, 0, 1, 0, 0, 100))
		end)

		T.it("coin : le coin avant-haut est vide (y·sz − z·sy > 0)", function()
			local w = box(0, 0, 0, 2, 4, 4, true)
			-- rayon vertical descendant à l'avant (z = -1,5) : touche, la pente y est basse
			T.expect(SC.rayHits(w, 0, 10, -1.5, 0, -1, 0, 100))
			-- rayon horizontal le long de X, en haut à l'avant (y = 1,5 ; z = -1,5) : dans la partie coupée
			T.expect(not SC.rayHits(w, -10, 1.5, -1.5, 1, 0, 0, 100))
			-- même hauteur, à l'arrière (z = 1,5) : dans le plein
			T.expect(SC.rayHits(w, -10, 1.5, 1.5, 1, 0, 0, 100))
		end)
	end)

	T.describe("ShadowCulling.samples", function()
		T.it("seules les faces tournées vers le soleil sont échantillonnées", function()
			local pts = SC.samples(box(0, 0, 0, 4, 4, 4), SUN_X)
			T.expect(#pts > 0)
			for _, p in pts do
				T.expect(p[1] > 2)
			end
		end)

		T.it("coin : les points des côtés restent dans le triangle", function()
			local w = box(0, 0, 0, 2, 4, 4, true)
			for _, p in SC.samples(w, { -1, 0, 0 }) do
				T.expect(p[2] * 4 - p[3] * 4 <= 1e-3)
			end
		end)
	end)

	T.describe("ShadowCulling.shadowed", function()
		T.it("un mur côté soleil masque la boîte derrière lui, pas l'inverse", function()
			local boxes = { box(0, 0, 0, 2, 2, 2), box(10, 0, 0, 2, 6, 6) }
			local s = run(boxes)
			T.expect(s[1])
			T.expect(not s[2])
		end)

		T.it("masque partiel : la boîte garde son ombre", function()
			local boxes = { box(0, 0, 0, 2, 2, 2), box(10, 0.5, 0, 2, 2, 6) }
			T.expect(not run(boxes)[1])
		end)

		T.it("chaîne : seule la boîte la plus proche du soleil garde son ombre", function()
			local boxes = { box(0, 0, 0, 2, 2, 2), box(5, 0, 0, 2, 3, 3), box(10, 0, 0, 2, 4, 4) }
			local s = run(boxes)
			T.expect(s[1])
			T.expect(s[2])
			T.expect(not s[3])
		end)

		T.it("un masque transparent (hors masques) ne compte pas", function()
			local boxes = { box(0, 0, 0, 2, 2, 2), box(10, 0, 0, 2, 6, 6) }
			local s = SC.shadowed(boxes, { [2] = false }, { [1] = true, [2] = true }, SUN_X)
			T.expect(not s[1])
		end)

		T.it("la partie coupée d'un coin laisse passer la lumière", function()
			-- coin haut de 4 côté soleil, petite boîte en face de sa partie avant-haute (vide)
			local boxes = { box(0, 1.5, -1.5, 1, 0.5, 0.5), box(10, 0, 0, 2, 4, 4, true) }
			T.expect(not run(boxes)[1])
		end)

		T.it("soleil rasant en diagonale : masque trouvé à travers plusieurs cellules", function()
			local sun = { 0.7, 0.1, 0.7 }
			local len = math.sqrt(0.99)
			sun = { sun[1] / len, sun[2] / len, sun[3] / len }
			local boxes = { box(0, 0, 0, 1, 1, 1), box(60, 9, 60, 20, 20, 20) }
			T.expect(run(boxes, sun)[1])
		end)
	end)
end

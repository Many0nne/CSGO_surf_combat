--!nocheck
-- RampCheck.luau
-- Mesure, sur chaque rampe de surf d'une map, ce qui dépasse de la surface de glisse (#136, cf. docs/maps.md
-- « Rebord sur une rampe »). Un rayon est tiré tous les STEP studs le long de la normale de la rampe, de HEIGHT studs
-- au-dessus vers la pente, dans toutes les pièces bloquantes (CanCollide ou CanQuery) : la hauteur du premier contact
-- au-dessus du plan de la dalle principale donne le profil de la rampe. La surface de glisse est la hauteur la plus
-- fréquente (le mur d'air posé sur l'acier, s'il y en a un) ; tout point plus haut de plus de TOL est un rebord, tout
-- point plus bas un creux (la marche de l'autre côté arrête le joueur), tout rayon qui ne touche rien un trou.
-- Mesure en arithmétique pure sur des boîtes (format ShadowCulling.Box) ; `check` lit une map (Instances) et mesure
-- la collision puis le rendu. Testé : tests/specs/RampEdges.spec.luau (describe « RampCheck »).

local ShadowCulling = require("./ShadowCulling")

local RampCheck = {}

RampCheck.MIN_AREA = 1000 -- studs² : une dalle de surf plus petite n'est pas une rampe (éclat de pente)
RampCheck.BAND = 1.5 -- studs : une dalle parallèle à moins de ça du plan prolonge la rampe (bandes de rive)
RampCheck.TOUCH = 0.1 -- studs : écart toléré entre deux dalles d'une même rampe
RampCheck.HEIGHT = 8 -- studs au-dessus du plan d'où partent les rayons (un corps de joueur et de la marge)
RampCheck.STEP = 0.5 -- studs entre deux rayons dans le sens de la pente
RampCheck.STEP_U = 0.25 -- studs entre deux rayons dans la longueur : une tranche de mur fine en travers du surf
-- studs : les rayons du bord sont tirés juste à l'intérieur de l'emprise. Pas moins : en haut de la rampe CT, le mur
-- qui remonte après la crête (parallèle au surf, angle rentrant) entre de quelques centièmes dans l'emprise.
RampCheck.INSET = 0.05
RampCheck.TOL = 0.02 -- studs : au-delà, un point plus haut que la surface de glisse est un rebord
RampCheck.ROUND = 0.01 -- studs : pas de l'histogramme qui donne la surface de glisse

-- Cette méthode permet de calculer le produit scalaire de deux triplets {x, y, z} lorsqu'on projette dans le repère
-- d'une rampe.
function RampCheck.dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local dot = RampCheck.dot

-- Cette méthode permet de lister les sommets d'une boîte (ses 8 coins, ceux d'un coin compris) en repère monde
-- lorsqu'on borne son emprise dans le repère d'une rampe.
local function corners(b)
	local out = {}
	for _, sx in { -0.5, 0.5 } do
		for _, sy in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				local x, y, z = sx * b.sx, sy * b.sy, sz * b.sz
				table.insert(out, {
					b.px + x * b.xx + y * b.yx + z * b.zx,
					b.py + x * b.xy + y * b.yy + z * b.zy,
					b.pz + x * b.xz + y * b.yz + z * b.zz,
				})
			end
		end
	end
	return out
end

-- Cette méthode permet de borner une boîte dans le repère (u, v, n) d'une rampe : renvoie {u0, u1, v0, v1, h0, h1},
-- h compté depuis l'origine du repère.
function RampCheck.bounds(b, frame)
	local r = { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
	for _, c in corners(b) do
		local u, v, h = dot(c, frame.u), dot(c, frame.v), dot(c, frame.n)
		r[1], r[2] = math.min(r[1], u), math.max(r[2], u)
		r[3], r[4] = math.min(r[3], v), math.max(r[4], v)
		r[5], r[6] = math.min(r[5], h), math.max(r[6], h)
	end
	return r
end
local bounds = RampCheck.bounds

-- Cette méthode permet de donner la face du dessus d'une dalle (pas un coin) : normale tournée vers le haut et
-- distance du plan à l'origine du monde.
function RampCheck.topFace(b)
	local n = { b.yx, b.yy, b.yz }
	if n[2] < 0 then
		n = { -n[1], -n[2], -n[3] }
	end
	return n, dot({ b.px, b.py, b.pz }, n) + b.sy / 2
end
local topFace = RampCheck.topFace

-- Cette méthode permet de retrouver les rampes de surf parmi les dalles de surf d'une map : une rampe par grande dalle
-- (MIN_AREA), son emprise prolongée par les dalles parallèles voisines à moins de BAND de son plan. Renvoie des
-- repères { main, members, n, u, v, top, u0, u1, v0, v1 } (top : distance du plan de la dalle principale, sur n ;
-- members : indices des dalles de la rampe, la principale comprise).
function RampCheck.ramps(surf)
	local ramps = {}
	-- grandes dalles de la plus grande à la plus petite ; une dalle déjà prise par une rampe n'en ouvre pas une autre
	local order, member = {}, {}
	for i, b in surf do
		if not b.wedge and b.sx * b.sz >= RampCheck.MIN_AREA then
			table.insert(order, i)
		end
	end
	table.sort(order, function(a, b)
		return surf[a].sx * surf[a].sz > surf[b].sx * surf[b].sz
	end)
	for _, i in order do
		local b = surf[i]
		if not member[i] then
			local n, top = topFace(b)
			local u = { b.xx, b.xy, b.xz }
			local v = { n[2] * u[3] - n[3] * u[2], n[3] * u[1] - n[1] * u[3], n[1] * u[2] - n[2] * u[1] }
			local frame = { main = i, members = { i }, n = n, u = u, v = v, top = top }
			local r = bounds(b, frame)
			frame.u0, frame.u1, frame.v0, frame.v1 = r[1], r[2], r[3], r[4]
			-- dalles parallèles voisines (rives), jusqu'à ce que l'emprise ne grandisse plus
			local taken = { [i] = true }
			member[i] = true
			local grown = true
			while grown do
				grown = false
				for j, o in surf do
					if not taken[j] and not o.wedge then
						local on, otop = topFace(o)
						if dot(on, n) > 0.999 and math.abs(otop - top) <= RampCheck.BAND then
							local ob = bounds(o, frame)
							local t = RampCheck.TOUCH
							if
								ob[1] <= frame.u1 + t
								and ob[2] >= frame.u0 - t
								and ob[3] <= frame.v1 + t
								and ob[4] >= frame.v0 - t
							then
								taken[j] = true
								member[j] = true
								grown = true
								table.insert(frame.members, j)
								frame.u0, frame.u1 = math.min(frame.u0, ob[1]), math.max(frame.u1, ob[2])
								frame.v0, frame.v1 = math.min(frame.v0, ob[3]), math.max(frame.v1, ob[4])
							end
						end
					end
				end
			end
			table.insert(ramps, frame)
		end
	end
	return ramps
end

-- Cette méthode permet de répartir des points de a à b (bornes comprises) tous les `step` au plus.
local function spread(a, b, step)
	local n = math.max(1, math.ceil((b - a) / step))
	local out = {}
	for k = 0, n do
		table.insert(out, a + (b - a) * k / n)
	end
	return out
end

-- Cette méthode permet de mesurer une rampe : tire les rayons sur son emprise dans les boîtes bloquantes `solids` et
-- renvoie { surface, above, below, area, samples, holes = { {u, v} }, offenders = { [indice de boîte] = { count,
-- height, u0, u1, v0, v1 } } } (hauteurs depuis le plan de la dalle principale ; above et below : plus grands écarts
-- au-dessus et au-dessous de la surface de glisse ; height : écart signé ; holes : rayons sans contact ; u, v :
-- position en studs depuis le début de l'emprise en longueur et en pente).
function RampCheck.measure(ramp, solids)
	local H = RampCheck.HEIGHT
	-- boîtes candidates : celles qui touchent le volume au-dessus de l'emprise
	local cands = {}
	for i, b in solids do
		local r = bounds(b, ramp)
		if
			r[2] >= ramp.u0
			and r[1] <= ramp.u1
			and r[4] >= ramp.v0
			and r[3] <= ramp.v1
			and r[6] > ramp.top - 3
			and r[5] < ramp.top + H
		then
			table.insert(cands, { i = i, b = b, r = r })
		end
	end
	local n, u, v = ramp.n, ramp.u, ramp.v
	local us = spread(ramp.u0 + RampCheck.INSET, ramp.u1 - RampCheck.INSET, RampCheck.STEP_U)
	local vs = spread(ramp.v0 + RampCheck.INSET, ramp.v1 - RampCheck.INSET, RampCheck.STEP)
	local hits, counts, holes = {}, {}, {}
	for _, a in us do
		local col = {}
		for _, c in cands do
			if c.r[1] <= a and c.r[2] >= a then
				table.insert(col, c)
			end
		end
		for _, bv in vs do
			local h0 = ramp.top + H
			local ox = u[1] * a + v[1] * bv + n[1] * h0
			local oy = u[2] * a + v[2] * bv + n[2] * h0
			local oz = u[3] * a + v[3] * bv + n[3] * h0
			local best, who = H + 3, nil
			for _, c in col do
				if c.r[3] <= bv and c.r[4] >= bv then
					local t = ShadowCulling.rayEntry(c.b, ox, oy, oz, -n[1], -n[2], -n[3], best)
					if t and t < best then
						best, who = t, c.i
					end
				end
			end
			if who then
				local h = H - best
				table.insert(hits, { h = h, who = who, u = a - ramp.u0, v = bv - ramp.v0 })
				local key = math.floor(h / RampCheck.ROUND + 0.5)
				counts[key] = (counts[key] or 0) + 1
			else
				table.insert(holes, { u = a - ramp.u0, v = bv - ramp.v0 })
			end
		end
	end
	-- surface de glisse : hauteur la plus fréquente
	local mode, most = 0, -1
	for key, c in counts do
		if c > most then
			mode, most = key, c
		end
	end
	local surface = mode * RampCheck.ROUND
	local cell = (us[2] and us[2] - us[1] or 0) * (vs[2] and vs[2] - vs[1] or 0)
	local report = { surface = surface, above = 0, below = 0, area = 0, offenders = {}, samples = #hits, holes = holes }
	for _, s in hits do
		local d = s.h - surface
		if math.abs(d) > RampCheck.TOL then
			report.area += cell
			if d > 0 then
				report.above = math.max(report.above, d)
			else
				report.below = math.max(report.below, -d)
			end
			local o = report.offenders[s.who]
				or { count = 0, height = 0, u0 = math.huge, u1 = -math.huge, v0 = math.huge, v1 = -math.huge }
			o.count += 1
			if math.abs(d) > math.abs(o.height) then
				o.height = d
			end
			o.u0, o.u1 = math.min(o.u0, s.u), math.max(o.u1, s.u)
			o.v0, o.v1 = math.min(o.v0, s.v), math.max(o.v1, s.v)
			report.offenders[s.who] = o
		end
	end
	return report
end

-- Cette méthode permet de convertir une pièce en boîte (repère de sa CFrame, taille ; un cylindre ou une boule est
-- approché par sa boîte, ce qui ne peut que signaler un rebord de trop).
function RampCheck.box(p)
	local cf, s = p.CFrame, p.Size
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return {
		px = cf.Position.X,
		py = cf.Position.Y,
		pz = cf.Position.Z,
		xx = x.X,
		xy = x.Y,
		xz = x.Z,
		yx = y.X,
		yy = y.Y,
		yz = y.Z,
		zx = z.X,
		zy = z.Y,
		zz = z.Z,
		sx = s.X,
		sy = s.Y,
		sz = s.Z,
		wedge = p.ClassName == "WedgePart",
	}
end

-- Cette méthode permet de nommer une pièce dans un bilan (dossier, nom, centre, retouche éventuelle).
local function describe(p)
	local c = p.CFrame.Position
	local patch = p:GetAttribute("Patch")
	return string.format(
		"%s/%s (%.2f, %.2f, %.2f)%s",
		p.Parent and p.Parent.Name or "?",
		p.Name,
		c.X,
		c.Y,
		c.Z,
		if patch then " [retouche : " .. patch .. "]" else ""
	)
end

-- Ce qu'on mesure : la collision (ce que touchent les rayons du mouvement) et le rendu (ce qui se voit).
local PASSES = {
	{
		name = "collision",
		keep = function(p)
			return p.CanCollide or p.CanQuery
		end,
	},
	{
		name = "rendu",
		keep = function(p)
			return p.Transparency < 1
		end,
	},
}

-- Cette méthode permet de mesurer toutes les rampes d'une map (Model avec Geometry.Ramps), en collision puis en
-- rendu : renvoie le bilan (lignes de texte, rampe par rampe, avec les pièces responsables) et le plus grand écart
-- trouvé par rapport à la surface de glisse (dépassement ou creux ; math.huge s'il y a un trou).
function RampCheck.check(map)
	local geometry = map:FindFirstChild("Geometry")
	local rampFolder = geometry and geometry:FindFirstChild("Ramps")
	assert(rampFolder, "Geometry.Ramps introuvable : pas de rampe de surf à vérifier")
	local surf = {}
	for _, p in rampFolder:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(surf, RampCheck.box(p))
		end
	end
	local ramps = RampCheck.ramps(surf)
	assert(#ramps > 0, "aucune rampe de surf trouvée dans Geometry.Ramps")
	-- boîtes de chaque mesure, construites une fois pour toutes les rampes
	local sets = {}
	for k, pass in PASSES do
		sets[k] = { parts = {}, solids = {} }
	end
	for _, p in map:GetDescendants() do
		if p:IsA("BasePart") then
			for k, pass in PASSES do
				if pass.keep(p) then
					table.insert(sets[k].parts, p)
					table.insert(sets[k].solids, RampCheck.box(p))
				end
			end
		end
	end
	local lines, worst = {}, 0
	for _, ramp in ramps do
		local m = surf[ramp.main]
		table.insert(
			lines,
			string.format(
				"rampe (%.0f, %.0f, %.0f), %.1f × %.1f studs",
				m.px,
				m.py,
				m.pz,
				ramp.u1 - ramp.u0,
				ramp.v1 - ramp.v0
			)
		)
		for k, pass in PASSES do
			local parts = sets[k].parts
			local r = RampCheck.measure(ramp, sets[k].solids)
			table.insert(
				lines,
				string.format(
					"  %s : surface à %+.3f du plan de l'acier, dépassement max %.3f, creux max %.3f sur %.1f studs², "
						.. "%d trou(s) (%d rayons)",
					pass.name,
					r.surface,
					r.above,
					r.below,
					r.area,
					#r.holes,
					r.samples
				)
			)
			if #r.holes > 0 then
				local h = r.holes[1]
				table.insert(lines, string.format("    trou, premier à long. %.1f, pente %.1f", h.u, h.v))
			end
			local list = {}
			for i, o in r.offenders do
				table.insert(list, { i = i, o = o })
			end
			table.sort(list, function(a, b)
				return math.abs(a.o.height) > math.abs(b.o.height)
			end)
			for _, e in list do
				table.insert(
					lines,
					string.format(
						"    %+.3f sur %d rayon(s), long. %.1f-%.1f, pente %.1f-%.1f : %s",
						e.o.height,
						e.o.count,
						e.o.u0,
						e.o.u1,
						e.o.v0,
						e.o.v1,
						describe(parts[e.i])
					)
				)
			end
			worst = math.max(worst, r.above, r.below, if #r.holes > 0 then math.huge else 0)
		end
	end
	return lines, worst
end

return RampCheck

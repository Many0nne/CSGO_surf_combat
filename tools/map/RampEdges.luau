--!nocheck
-- RampEdges.luau
-- Rend la surface de glisse des rampes de surf continue jusqu'à leurs bords (#136, cf. docs/maps.md « Rebord sur une
-- rampe »), appliqué par build_dizzy.luau après les retouches. Rampe par rampe (RampCheck.ramps) :
-- 1. Peau : une seule dalle d'acier de SKIN studs couvre toute l'emprise, dessus au niveau des bandes de rive (plus
--    hautes que la dalle principale de 0,17 et 0,34 stud sur ar_dizzy). La surface visible est plate.
-- 2. Sous la peau : toute autre pièce qui y entre (dalles d'acier d'origine, tranche des murs des bouts posés sur leur
--    face sans retrait, dalle de plafond ou de mur épaissie dans l'angle aigu du bas ou du haut de la pente, mur d'air
--    du bout) est rognée au dos de la peau ; hors de l'emprise, rien ne change. Aucune face en travers du surf ne reste
--    à moins de SKIN sous la surface : le joueur s'enfonce d'environ 0,3 stud en atterrissant sur une rampe (mouvement,
--    mesuré en jeu) et s'arrêtait sur la tranche d'une pièce cachée. Le mur d'air d'origine, d'un seul tenant sur toute
--    la longueur, est gardé. La découpe est exacte : la section de la pièce (perpendiculaire à la longueur de la rampe)
--    est coupée, puis reposée en coins.
-- Une pièce qui dépasse sans être extrudée dans la longueur de la rampe n'est pas touchée : la mesure de contrôle
-- (RampCheck.check, appelée par build_dizzy.luau) arrête alors la génération.
-- Testé : tests/specs/RampEdges.spec.luau.

local roblox = if Vector3 then nil else require("@lune/roblox")
local V3 = if roblox then roblox.Vector3 else Vector3
local CF = if roblox then roblox.CFrame else CFrame
local New = if roblox then roblox.Instance.new else Instance.new

local RampCheck = require("./RampCheck")

local RampEdges = {}

RampEdges.SKIN = 0.6 -- studs : épaisseur de la peau d'acier, plus que l'enfoncement du joueur à l'atterrissage (0,33)
RampEdges.TRIM_TOL = 0.005 -- studs : une pièce qui entre de moins que ça dans la peau n'est pas touchée
RampEdges.TOUCH = 0.05 -- studs : une pièce posée sur la surface à ça près y entre (au-delà : obstacle, laissé)
RampEdges.MIN_LEG = 0.002 -- studs : un coin plus mince n'est pas posé
RampEdges.ATTRIBUTE = "RampEdge" -- posé sur les pièces modifiées, visible dans Studio

-- propriétés recopiées d'une pièce rognée sur ses morceaux
local PROPS = {
	"Anchored",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"Color",
	"Material",
	"Transparency",
	"Reflectance",
	"TopSurface",
	"BottomSurface",
	"Name",
}

local dot = RampCheck.dot
local OWN = "RampEdgeSteel" -- marque temporaire de l'acier de la rampe en cours

-- Cette méthode permet de combiner deux triplets (a + b·k) lorsqu'on place un point dans le repère d'une rampe.
local function add(a, b, k)
	return { a[1] + b[1] * k, a[2] + b[2] * k, a[3] + b[3] * k }
end

-- Cette méthode permet de calculer le produit vectoriel de deux triplets.
local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

-- Cette méthode permet de convertir un triplet en Vector3.
local function vec(a)
	return V3.new(a[1], a[2], a[3])
end

-- Cette méthode permet de passer des coordonnées d'une rampe (longueur u, pente v, hauteur h sur la normale) au monde.
local function world(ramp, u, v, h)
	return add(add(add({ 0, 0, 0 }, ramp.u, u), ramp.v, v), ramp.n, h)
end

-- Cette méthode permet de calculer l'aire (signe ôté) d'un polygone plan {{v, h}, ...}.
function RampEdges.area(poly)
	local s = 0
	for i, a in poly do
		local b = poly[i % #poly + 1]
		s += a[1] * b[2] - b[1] * a[2]
	end
	return math.abs(s) / 2
end

-- Cette méthode permet de couper un polygone convexe {{v, h}, ...} par le demi-plan a·v + b·h ≤ c
-- (Sutherland-Hodgman) ; renvoie le polygone gardé, vide s'il est entièrement dehors.
function RampEdges.clip(poly, a, b, c)
	local out = {}
	for i, p in poly do
		local q = poly[i % #poly + 1]
		local fp, fq = a * p[1] + b * p[2] - c, a * q[1] + b * q[2] - c
		if fp <= 0 then
			table.insert(out, p)
		end
		if (fp < 0 and fq > 0) or (fp > 0 and fq < 0) then
			local t = fp / (fp - fq)
			table.insert(out, { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t })
		end
	end
	return out
end

-- Cette méthode permet de découper une pièce extrudée dans la longueur d'une rampe : renvoie l'indice de l'axe
-- parallèle à la longueur, la section {{v, h}, ...} (polygone convexe) et l'étendue [a0, a1] le long de la rampe ;
-- nil si la pièce n'est pas extrudée dans la longueur (coin tourné autrement, pièce de biais).
function RampEdges.section(b, ramp)
	local axes = { { b.xx, b.xy, b.xz }, { b.yx, b.yy, b.yz }, { b.zx, b.zy, b.zz } }
	local sizes = { b.sx, b.sy, b.sz }
	local along
	for i, a in axes do
		if math.abs(dot(a, ramp.u)) > 0.9999 then
			along = i
		end
	end
	if not along or (b.wedge and along ~= 1) then
		return nil
	end
	local c = { b.px, b.py, b.pz }
	local cu = dot(c, ramp.u)
	-- sommets de la section, en local : coin (x le long de la rampe) = triangle de son côté YZ, boîte = rectangle
	local local2
	if b.wedge then
		local hy, hz = b.sy / 2, b.sz / 2
		local2 = { { 2, -hy, 3, -hz }, { 2, -hy, 3, hz }, { 2, hy, 3, hz } }
	else
		local i, j = along % 3 + 1, (along + 1) % 3 + 1
		local hi, hj = sizes[i] / 2, sizes[j] / 2
		local2 = { { i, hi, j, hj }, { i, -hi, j, hj }, { i, -hi, j, -hj }, { i, hi, j, -hj } }
	end
	local poly = {}
	for _, l in local2 do
		local p = add(add(c, axes[l[1]], l[2]), axes[l[3]], l[4])
		table.insert(poly, { dot(p, ramp.v), dot(p, ramp.n) })
	end
	return along, poly, cu - sizes[along] / 2, cu + sizes[along] / 2
end

-- Cette méthode permet de poser un triangle de section {{v, h}, ×3}, extrudé de u0 à u1 le long de la rampe, en un ou
-- deux coins (triangles rectangles, comme extract_dizzy.py) : renvoie des { cframe, size }.
function RampEdges.wedges(tri, ramp, u0, u1)
	local mid, len = (u0 + u1) / 2, u1 - u0
	local pts = {}
	for _, q in tri do
		table.insert(pts, world(ramp, mid, q[1], q[2]))
	end
	-- plus long côté (p, q), sommet opposé o, pied f de la hauteur issue de o
	local best, p, q, o = -1, nil, nil, nil
	for i = 1, 3 do
		local a, b, c = pts[i], pts[i % 3 + 1], pts[(i + 1) % 3 + 1]
		local d = add(b, a, -1)
		local l = dot(d, d)
		if l > best then
			best, p, q, o = l, a, b, c
		end
	end
	if best < RampEdges.MIN_LEG ^ 2 then
		return {}
	end
	local pq = add(q, p, -1)
	local f = add(p, pq, dot(add(o, p, -1), pq) / dot(pq, pq))
	local out = {}
	for _, leg in { p, q } do
		local za, yb = add(f, leg, -1), add(o, f, -1)
		local lz, ly = math.sqrt(dot(za, za)), math.sqrt(dot(yb, yb))
		if lz >= RampEdges.MIN_LEG and ly >= RampEdges.MIN_LEG then
			local z = { za[1] / lz, za[2] / lz, za[3] / lz }
			local y = { yb[1] / ly, yb[2] / ly, yb[3] / ly }
			local x = cross(y, z)
			local center = add(add(f, add(leg, f, -1), 0.5), add(o, f, -1), 0.5)
			table.insert(out, {
				cframe = CF.fromMatrix(vec(center), vec(x), vec(y), vec(z)),
				size = V3.new(len, ly, lz),
			})
		end
	end
	return out
end

-- Cette méthode permet de calculer ce qui reste d'une pièce qui monte dans la peau d'une rampe par en dessous, après
-- la découpe au-dessus de son emprise (hauteur > surface - SKIN sur v0..v1) : liste des morceaux
-- { range = {a0, a1}, poly = section } (poly nil : section d'origine) ; nil si la pièce reste sous la peau, est
-- entièrement au-dessus de la surface (obstacle, pas un rebord) ou n'est pas extrudée dans la longueur (la mesure de
-- contrôle la signalera).
function RampEdges.cut(b, ramp, surface)
	local r = RampCheck.bounds(b, ramp)
	local e = 1e-3
	if r[2] <= ramp.u0 + e or r[1] >= ramp.u1 - e or r[4] <= ramp.v0 + e or r[3] >= ramp.v1 - e then
		return nil
	end
	local cut = surface - RampEdges.SKIN
	if r[6] <= cut + RampEdges.TRIM_TOL then
		return nil
	end
	local along, poly, a0, a1 = RampEdges.section(b, ramp)
	if not along then
		return nil
	end
	-- au-dessus de l'emprise (en pente), la pièce doit entrer dans la peau en partant de sous la surface
	local over = RampEdges.clip(RampEdges.clip(poly, -1, 0, -ramp.v0), 1, 0, ramp.v1)
	if #over < 3 then
		return nil
	end
	local hmin, hmax = math.huge, -math.huge
	for _, q in over do
		hmin, hmax = math.min(hmin, q[2]), math.max(hmax, q[2])
	end
	-- TOUCH : le mur qui remonte après la crête entre d'un cheveu dans l'emprise en partant de la surface
	if hmax <= cut + RampEdges.TRIM_TOL or hmin >= surface + RampEdges.TOUCH then
		return nil
	end
	local kept = {
		RampEdges.clip(poly, 1, 0, ramp.v0), -- avant le bas de la rampe
		RampEdges.clip(poly, -1, 0, -ramp.v1), -- après le haut
		RampEdges.clip(over, 0, 1, cut),
	}
	local total = 0
	for _, k in kept do
		if #k >= 3 then
			total += RampEdges.area(k)
		end
	end
	if RampEdges.area(poly) - total < 1e-4 then
		return nil -- la boîte dépassait, pas la pièce (coin)
	end
	local pieces = {}
	local m0, m1 = math.max(a0, ramp.u0), math.min(a1, ramp.u1)
	if a0 < m0 - e then
		table.insert(pieces, { range = { a0, m0 } })
	end
	if m1 < a1 - e then
		table.insert(pieces, { range = { m1, a1 } })
	end
	for _, k in kept do
		if #k >= 3 and RampEdges.area(k) > 1e-6 then
			table.insert(pieces, { range = { m0, m1 }, poly = k })
		end
	end
	return pieces
end

-- Cette méthode permet de créer une pièce de même habillage qu'une autre (classe donnée), rangée à côté d'elle.
local function sibling(part, class)
	local p = New(class)
	for _, name in PROPS do
		p[name] = part[name]
	end
	for k, v in part:GetAttributes() do
		p:SetAttribute(k, v)
	end
	p:SetAttribute(RampEdges.ATTRIBUTE, "rognée sous la surface de glisse")
	p.Parent = part.Parent
	return p
end

-- Cette méthode permet de remplacer une pièce par ses morceaux après découpe ; renvoie le nombre de pièces posées.
local function replace(part, b, ramp, pieces)
	local along, _, a0, a1 = RampEdges.section(b, ramp)
	local axis = ({ part.CFrame.XVector, part.CFrame.YVector, part.CFrame.ZVector })[along]
	local placed = 0
	for _, piece in pieces do
		local u0, u1 = piece.range[1], piece.range[2]
		if piece.poly == nil then
			-- hors de l'emprise dans la longueur : la pièce d'origine, raccourcie
			local p = sibling(part, part.ClassName)
			local s = part.Size
			local len = u1 - u0
			p.Size = if along == 1
				then V3.new(len, s.Y, s.Z)
				elseif along == 2 then V3.new(s.X, len, s.Z)
				else V3.new(s.X, s.Y, len)
			local shift = (u0 + u1) / 2 - (a0 + a1) / 2
			local sign = if dot({ axis.X, axis.Y, axis.Z }, ramp.u) > 0 then 1 else -1
			p.CFrame = part.CFrame + axis * (shift * sign)
			placed += 1
		else
			for i = 2, #piece.poly - 1 do
				for _, w in RampEdges.wedges({ piece.poly[1], piece.poly[i], piece.poly[i + 1] }, ramp, u0, u1) do
					local p = sibling(part, "WedgePart")
					p.CFrame = w.cframe
					p.Size = w.size
					placed += 1
				end
			end
		end
	end
	part:Destroy()
	return placed
end

-- Cette méthode permet de dire si une pièce est une dalle parallèle à la rampe qui la couvre sur toute sa longueur,
-- sans dépasser de la surface (le mur d'air d'origine) : d'un seul tenant, elle n'a aucune face en travers du surf.
local function wholeSlab(b, ramp, surface)
	if math.abs(b.yx * ramp.n[1] + b.yy * ramp.n[2] + b.yz * ramp.n[3]) < 0.9999 then
		return false
	end
	local r = RampCheck.bounds(b, ramp)
	return r[1] <= ramp.u0 + 1e-3 and r[2] >= ramp.u1 - 1e-3 and r[6] <= surface + RampEdges.TRIM_TOL
end

-- Cette méthode permet de poser la peau d'acier d'une rampe : une seule dalle de SKIN studs sur toute l'emprise,
-- dessus à `surface`, habillée comme la dalle principale `model`.
local function skin(model, ramp, surface)
	local p = New("Part")
	for _, name in PROPS do
		p[name] = model[name]
	end
	for k, v in model:GetAttributes() do
		p:SetAttribute(k, v)
	end
	local center = world(ramp, (ramp.u0 + ramp.u1) / 2, (ramp.v0 + ramp.v1) / 2, surface - RampEdges.SKIN / 2)
	p.CFrame = CF.fromMatrix(vec(center), vec(ramp.u), vec(ramp.n), vec(cross(ramp.u, ramp.n)))
	p.Size = V3.new(ramp.u1 - ramp.u0, RampEdges.SKIN, ramp.v1 - ramp.v0)
	p:SetAttribute(RampEdges.ATTRIBUTE, "peau d'acier continue de la rampe")
	p.Parent = model.Parent
	return p
end

-- Cette méthode permet d'appliquer la règle à toutes les rampes d'une géométrie de map (dossier Ramps et autres
-- dossiers de pièces) lorsque le générateur l'a posée ; renvoie un bilan par rampe
-- { center, surface, trimmed, placed } (surface : hauteur de la peau au-dessus de la dalle principale d'origine).
function RampEdges.apply(geometry)
	local folder = geometry:FindFirstChild("Ramps")
	assert(folder, "Geometry.Ramps introuvable")
	local steel, boxes = {}, {}
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(steel, p)
			table.insert(boxes, RampCheck.box(p))
		end
	end
	local report = {}
	for _, ramp in RampCheck.ramps(boxes) do
		-- surface de glisse : la plus haute des dalles d'acier de la rampe (les rives relevées)
		local surface = ramp.top
		for _, j in ramp.members do
			local _, top = RampCheck.topFace(boxes[j])
			surface = math.max(surface, top)
		end
		-- marque temporaire (et non une table indexée par pièce : sous Lune, une même Instance peut revenir sous deux
		-- références différentes d'un appel à l'autre)
		skin(steel[ramp.main], ramp, surface):SetAttribute(OWN, true)
		local trimmed, placed = 0, 0
		for _, p in geometry:GetDescendants() do
			if p:IsA("BasePart") and not p:GetAttribute(OWN) then
				local b = RampCheck.box(p)
				if wholeSlab(b, ramp, surface) then
					p:SetAttribute(OWN, true)
				else
					local pieces = RampEdges.cut(b, ramp, surface)
					if pieces then
						trimmed += 1
						placed += replace(p, b, ramp, pieces)
					end
				end
			end
		end
		for _, p in geometry:GetDescendants() do
			if p:GetAttribute(OWN) then
				p:SetAttribute(OWN, nil)
			end
		end
		table.insert(report, {
			surface = surface - ramp.top,
			trimmed = trimmed,
			placed = placed,
			center = { boxes[ramp.main].px, boxes[ramp.main].py, boxes[ramp.main].pz },
		})
	end
	return report
end

return RampEdges

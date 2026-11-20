--!nocheck
-- RadoubDressing.luau
-- Habillage de Radoub (#596), posé par build_radoub.luau sur la maquette : façades (bardage à bandeau bleu des
-- ateliers et du hangar, béton préfabriqué des magasins, brique et pierre de la salle des pompes), portes, fenêtres,
-- numéros des halls, intérieurs (pont roulant, éclairage, rayonnages, pompes), navire (peinture, soudures, blocs
-- ouverts, superstructure, hélice, échafaudages), portique (bogies, contreventements, cabine, palan), quais (bittes,
-- rails, lampadaires, conteneurs, tôles, liserés), bateau-porte et fond de décor. Références : chantiers navals récents
-- (Damen Rotterdam, Meyer Werft, Chantiers de l'Atlantique) et forme Thompson de Belfast (salle des pompes), cf.
-- docs/maps.md « Radoub ».
-- Coordonnées du plan de build_radoub.luau (X ouest → est, Z nord → sud), posées dans le monde par ctx.place.
-- Collision : seuls les volumes porteurs la gardent (`solid`) ; le reste est sans collision ni requête et ne projette
-- pas d'ombre (plaqué contre un mur, ou trop fin).

local roblox = require("@lune/roblox")

local V3 = roblox.Vector3
local CF = roblox.CFrame
local C3 = roblox.Color3
local E = roblox.Enum
local New = roblox.Instance.new
local M = E.Material

local RadoubDressing = {}

local PAL = {
	clad = C3.fromRGB(222, 224, 220), -- bardage blanc cassé
	rib = C3.fromRGB(204, 207, 205), -- nervures du bardage
	joint = C3.fromRGB(172, 176, 178), -- joints des panneaux
	blue = C3.fromRGB(38, 86, 146), -- bleu du chantier
	paleBlue = C3.fromRGB(92, 132, 178),
	white = C3.fromRGB(240, 240, 236),
	steel = C3.fromRGB(62, 70, 82), -- structure sombre, menuiseries
	galva = C3.fromRGB(150, 154, 158),
	plinth = C3.fromRGB(128, 126, 120),
	concrete = C3.fromRGB(176, 172, 164),
	coping = C3.fromRGB(196, 192, 184),
	slabJoint = C3.fromRGB(122, 118, 112),
	precast = C3.fromRGB(196, 192, 184),
	precastJoint = C3.fromRGB(150, 146, 140),
	brick = C3.fromRGB(146, 74, 56),
	brickDark = C3.fromRGB(124, 60, 46),
	stone = C3.fromRGB(206, 192, 160),
	glass = C3.fromRGB(46, 60, 76),
	sky = C3.fromRGB(150, 168, 190), -- vitre vue de l'intérieur (ciel du crépuscule)
	lit = C3.fromRGB(255, 190, 120),
	lamp = C3.fromRGB(255, 214, 160),
	yellow = C3.fromRGB(232, 180, 40),
	yellowDark = C3.fromRGB(196, 150, 30),
	black = C3.fromRGB(28, 28, 30),
	red = C3.fromRGB(176, 44, 36),
	antifoul = C3.fromRGB(150, 48, 38),
	antifoulDark = C3.fromRGB(124, 38, 30),
	navy = C3.fromRGB(34, 50, 82),
	navyDark = C3.fromRGB(26, 38, 64),
	orange = C3.fromRGB(236, 112, 30),
	wood = C3.fromRGB(150, 112, 72),
	woodDark = C3.fromRGB(118, 86, 54),
	primer = C3.fromRGB(150, 152, 148),
	bronze = C3.fromRGB(184, 140, 72),
	rubber = C3.fromRGB(34, 34, 36),
	cardboard = C3.fromRGB(176, 140, 96),
	pump = C3.fromRGB(64, 112, 120),
}

local ctx -- contexte de build : place, quay, deck, wall, dossiers
local Q -- dessus des quais

-- Pièces -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser une pièce ancrée au repère `cf` du plan ; `solid` garde collision, requêtes et ombre,
-- sinon décor pur (ni collision, ni requête, ni ombre).
local function part(parent, cf, size, color, material, solid, shape)
	local p = New("Part")
	p.Anchored = true
	p.CanTouch = false
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CastShadow = solid == true
	p.TopSurface = E.SurfaceType.Smooth
	p.BottomSurface = E.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = ctx.place * cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Parent = parent
	return p
end

-- Cette méthode permet de poser une boîte alignée sur le repère `frame`, donnée par ses bornes locales (u le long,
-- v vers le haut, w vers l'extérieur) ; rien si une dimension est nulle.
local function box(parent, frame, u0, u1, v0, v1, w0, w1, color, material, solid)
	if u1 - u0 < 0.01 or v1 - v0 < 0.01 or w1 - w0 < 0.01 then
		return nil
	end
	return part(
		parent,
		frame * CF.new((u0 + u1) / 2, (v0 + v1) / 2, (w0 + w1) / 2),
		V3.new(u1 - u0, v1 - v0, w1 - w0),
		color,
		material,
		solid
	)
end

local ORIGIN = CF.new()

-- Cette méthode permet de poser une boîte alignée sur les axes du plan, donnée par ses bornes.
local function blk(parent, x0, x1, y0, y1, z0, z1, color, material, solid)
	return box(parent, ORIGIN, x0, x1, y0, y1, z0, z1, color, material, solid)
end

-- Cette méthode permet de donner un repère dont le LookVector est `look` (jamais CFrame.lookAt sous Lune).
local function aim(pos, look)
	local z = -look.Unit
	local up = if math.abs(z.Y) > 0.99 then V3.new(1, 0, 0) else V3.new(0, 1, 0)
	local x = up:Cross(z).Unit
	return CF.fromMatrix(pos, x, z:Cross(x), z)
end

-- Cette méthode permet de poser un cylindre entre deux points locaux du repère `frame` (axe du cylindre Roblox = X).
local function cyl(parent, frame, a, b, d, color, material, solid)
	local cf = aim((a + b) / 2, b - a) * CF.Angles(0, math.pi / 2, 0)
	return part(parent, frame * cf, V3.new((b - a).Magnitude, d, d), color, material, solid, E.PartType.Cylinder)
end

-- Cette méthode permet de poser un poteau vertical (cylindre) en (x, z) du plan, de y0 à y1.
local function post(parent, x, z, y0, y1, d, color, material, solid)
	return cyl(parent, ORIGIN, V3.new(x, y0, z), V3.new(x, y1, z), d, color, material, solid)
end

-- Cette méthode permet de poser un disque sur une façade (axe selon la normale w), centré en (u, v), de w0 à w1.
local function disc(parent, frame, u, v, d, w0, w1, color, material)
	return part(
		parent,
		frame * CF.new(u, v, (w0 + w1) / 2) * CF.Angles(0, math.pi / 2, 0),
		V3.new(w1 - w0, d, d),
		color,
		material,
		false,
		E.PartType.Cylinder
	)
end

-- Cette méthode permet d'accrocher une SpotLight sans ombre à une pièce lumineuse, tournée vers la face `face`.
local function spot(p, face, angle, range, brightness)
	local l = New("SpotLight")
	l.Face = face
	l.Angle = angle
	l.Range = range
	l.Brightness = brightness
	l.Color = PAL.lamp
	l.Shadows = false
	l.Parent = p
	return l
end

-- Cette méthode permet de bâtir le repère d'une façade : origine au pied d'une extrémité, X le long du mur (vers la
-- droite vu du dehors), Y vertical, Z sortant.
local function faceFrame(origin, along, out)
	return CF.fromMatrix(origin, along, V3.new(0, 1, 0), out)
end

-- Cette méthode permet de retirer d'un intervalle [a0, a1] une liste d'intervalles ; renvoie les morceaux restants.
local function minus(a0, a1, holes)
	local segs = { { a0, a1 } }
	for _, h in holes do
		local out = {}
		for _, s in segs do
			if h[2] <= s[1] or h[1] >= s[2] then
				table.insert(out, s)
			else
				if h[1] > s[1] then
					table.insert(out, { s[1], h[1] })
				end
				if h[2] < s[2] then
					table.insert(out, { h[2], s[2] })
				end
			end
		end
		segs = out
	end
	return segs
end

-- Cette méthode permet de poser une bande horizontale sur une façade, de v0 à v1, coupée par ses ouvertures.
local function hstrip(parent, face, v0, v1, w, color, material, u0, u1)
	local hs = {}
	for _, o in face.holes do
		if o[3] < v1 and o[4] > v0 then
			table.insert(hs, { o[1], o[2] })
		end
	end
	for _, s in minus(u0 or 0, u1 or face.len, hs) do
		if s[2] - s[1] > 0.3 then
			box(parent, face.frame, s[1], s[2], v0, v1, 0, w, color, material)
		end
	end
end

-- Cette méthode permet de poser un élément vertical sur une façade, de u0 à u1, coupé par ses ouvertures (morceaux de
-- moins de `minLen` studs omis).
local function vstrip(parent, face, u0, u1, v0, v1, w, color, material, minLen)
	local hs = {}
	for _, o in face.holes do
		if o[1] < u1 and o[2] > u0 then
			table.insert(hs, { o[3], o[4] })
		end
	end
	for _, s in minus(v0, v1, hs) do
		if s[2] - s[1] > (minLen or 0.3) then
			box(parent, face.frame, u0, u1, s[1], s[2], 0, w, color, material)
		end
	end
end

-- Chiffres en sept segments (numéros des halls, des tronçons du navire, charge du portique)
local SEGMENTS = {
	["0"] = "abcdef",
	["1"] = "bc",
	["2"] = "abdeg",
	["3"] = "abcdg",
	["4"] = "bcfg",
	["5"] = "acdfg",
	["6"] = "acdefg",
	["7"] = "abc",
	["8"] = "abcdefg",
	["9"] = "abcdfg",
}

-- Cette méthode permet de peindre un nombre sur une façade, coin bas gauche en (u, v), chiffres de hauteur `H`.
local function digits(parent, frame, u, v, H, text, color, w)
	local W, s = H * 0.56, H * 0.15
	for i = 1, #text do
		local x = u + (i - 1) * (W + H * 0.24)
		local r = {
			a = { x, x + W, v + H - s, v + H },
			d = { x, x + W, v, v + s },
			g = { x, x + W, v + H / 2 - s / 2, v + H / 2 + s / 2 },
			f = { x, x + s, v + H / 2, v + H },
			e = { x, x + s, v, v + H / 2 },
			b = { x + W - s, x + W, v + H / 2, v + H },
			c = { x + W - s, x + W, v, v + H / 2 },
		}
		for k in string.gmatch(SEGMENTS[string.sub(text, i, i)], ".") do
			box(parent, frame, r[k][1], r[k][2], r[k][3], r[k][4], 0, w or 0.14, color)
		end
	end
end

-- Cette méthode permet de poser une applique (patte, bras, tête, verre lumineux et SpotLight vers le bas) sur une
-- façade, fixée en (u, v) ; `unlit` n'y met que le verre lumineux (sans SpotLight, pour le coût du rendu).
local function wallLamp(parent, frame, u, v, range, unlit)
	box(parent, frame, u - 0.5, u + 0.5, v - 0.6, v + 0.4, 0, 0.3, PAL.steel, M.Metal)
	box(parent, frame, u - 0.15, u + 0.15, v - 0.1, v + 0.2, 0.3, 1.5, PAL.steel, M.Metal)
	box(parent, frame, u - 0.9, u + 0.9, v - 0.5, v - 0.05, 0.9, 2.4, PAL.steel, M.Metal)
	local lens = box(parent, frame, u - 0.7, u + 0.7, v - 0.6, v - 0.5, 1.0, 2.3, PAL.lamp, M.Neon)
	if not unlit then
		spot(lens, E.NormalId.Bottom, 110, range or 26, 2.2)
	end
end

-- Façades -------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de donner les quatre façades extérieures d'un bâtiment du plan (repère, longueur, conversion
-- d'une coordonnée du plan en abscisse u, trous des portes avec la marge de leur bâti).
local function hallFaces(h)
	local faces = {
		S = {
			frame = faceFrame(V3.new(h.x0, Q, h.z1), V3.new(1, 0, 0), V3.new(0, 0, 1)),
			len = h.x1 - h.x0,
			toU = function(a)
				return a - h.x0
			end,
		},
		N = {
			frame = faceFrame(V3.new(h.x1, Q, h.z0), V3.new(-1, 0, 0), V3.new(0, 0, -1)),
			len = h.x1 - h.x0,
			toU = function(a)
				return h.x1 - a
			end,
		},
		E = {
			frame = faceFrame(V3.new(h.x1, Q, h.z1), V3.new(0, 0, -1), V3.new(1, 0, 0)),
			len = h.z1 - h.z0,
			toU = function(a)
				return h.z1 - a
			end,
		},
		W = {
			frame = faceFrame(V3.new(h.x0, Q, h.z0), V3.new(0, 0, 1), V3.new(-1, 0, 0)),
			len = h.z1 - h.z0,
			toU = function(a)
				return a - h.z0
			end,
		},
	}
	for name, f in faces do
		f.name = name
		f.holes = {}
		f.doors = {}
		for _, d in h.doors do
			if d[1] == name then
				local a, b = f.toU(d[2]), f.toU(d[3])
				local u0, u1 = math.min(a, b), math.max(a, b)
				table.insert(f.doors, { u0, u1, d[4] })
				table.insert(f.holes, { u0 - 1.3, u1 + 1.3, -1, d[4] + 1.3 })
			end
		end
	end
	return faces
end

-- Cette méthode permet de calculer les fenêtres d'un rang (une par travée entre poteaux), hors des ouvertures, et de
-- les ajouter aux trous de la façade ; renvoie les rectangles { u0, u1, v0, v1 }.
local function windowBays(face, pitch, v0, v1, margin, every)
	local n = math.max(1, math.floor(face.len / pitch + 0.5))
	local p = face.len / n
	local list = {}
	for k = 0, n - 1 do
		local u0, u1 = k * p + margin, (k + 1) * p - margin
		local clear = (k % (every or 1)) == 0
		for _, o in face.holes do
			if o[1] < u1 and o[2] > u0 and o[3] < v1 and o[4] > v0 then
				clear = false
			end
		end
		if clear and u1 - u0 > 1.5 then
			table.insert(list, { u0, u1, v0, v1 })
		end
	end
	for _, r in list do
		table.insert(face.holes, r)
	end
	return list
end

-- Cette méthode permet de poser une fenêtre (vitre, cadre, meneaux, appui) dans le rectangle `r` d'une façade ; `lit`
-- en fait une vitre éclairée de l'intérieur.
local function window(parent, face, r, frameColor, lit, mullion)
	local f, u0, u1, v0, v1 = face.frame, r[1], r[2], r[3], r[4]
	box(parent, f, u0, u1, v0, v1, 0, 0.1, if lit then PAL.lit else PAL.glass, if lit then M.Neon else M.Glass)
	box(parent, f, u0 - 0.25, u1 + 0.25, v1, v1 + 0.3, 0, 0.25, frameColor, M.Metal)
	box(parent, f, u0 - 0.25, u0, v0, v1, 0, 0.25, frameColor, M.Metal)
	box(parent, f, u1, u1 + 0.25, v0, v1, 0, 0.25, frameColor, M.Metal)
	box(parent, f, u0 - 0.4, u1 + 0.4, v0 - 0.35, v0, 0, 0.45, PAL.white)
	local n = math.max(1, math.floor((u1 - u0) / (mullion or 2.8) + 0.5))
	for i = 1, n - 1 do
		local u = u0 + (u1 - u0) * i / n
		box(parent, f, u - 0.1, u + 0.1, v0, v1, 0, 0.2, frameColor, M.Metal)
	end
end

-- Cette méthode permet de poser le revers d'une fenêtre sur la face intérieure du mur (vitre claire, meneaux).
local function innerWindow(parent, face, r)
	local W = ctx.wall
	box(parent, face.frame, r[1], r[2], r[3], r[4], -W - 0.1, -W, PAL.sky, M.Glass)
	local n = math.max(1, math.floor((r[2] - r[1]) / 2.8 + 0.5))
	for i = 0, n do
		local u = r[1] + (r[2] - r[1]) * i / n
		box(parent, face.frame, u - 0.12, u + 0.12, r[3], r[4], -W - 0.25, -W, PAL.steel, M.Metal)
	end
	box(parent, face.frame, r[1] - 0.2, r[2] + 0.2, r[3] - 0.3, r[3], -W - 0.5, -W, PAL.steel, M.Metal)
end

-- Cette méthode permet de peindre la plinthe intérieure d'un bâtiment (sur toute la face intérieure, hors portes).
local function innerDado(parent, face, height, color)
	local W = ctx.wall
	local hs = {}
	for _, d in face.doors do
		table.insert(hs, { d[1], d[2] })
	end
	for _, sg in minus(W, face.len - W, hs) do
		box(parent, face.frame, sg[1], sg[2], 0, height, -W - 0.08, -W, color)
	end
end

-- Cette méthode permet de dire si la travée `k` d'une façade est éclairée (motif fixe, pas de hasard).
local function litBay(k, seed)
	return ((k * 7 + seed * 3) % 5) < 2
end

-- Cette méthode permet de poser le bâti d'une porte (montants, linteau, chevrons, bas du rideau relevé) et ses
-- accessoires : coffre, plots et lampes pour une grande porte, auvent et lampe pour une petite.
local function door(parent, face, d, style)
	local f, u0, u1, h = face.frame, d[1], d[2], d[3]
	local frameColor = if style == "brick" then PAL.stone else PAL.steel
	local material = if style == "brick" then M.SmoothPlastic else M.Metal
	box(parent, f, u0 - 1.2, u0, 0, h + 1.2, 0, 0.7, frameColor, material)
	box(parent, f, u1, u1 + 1.2, 0, h + 1.2, 0, 0.7, frameColor, material)
	box(parent, f, u0, u1, h, h + 1.2, 0, 0.7, frameColor, material)
	-- bas du rideau métallique relevé, dans l'embrasure
	box(parent, f, u0, u1, h - 1.4, h, -0.9, -0.2, PAL.galva, M.Metal)
	if style == "brick" then
		-- clé de voûte au milieu du linteau
		box(parent, f, (u0 + u1) / 2 - 0.9, (u0 + u1) / 2 + 0.9, h - 0.2, h + 2, 0, 0.9, PAL.stone)
		wallLamp(parent, f, u1 + 2.6, h - 1)
		return
	end
	-- chevrons jaunes et noirs au pied des montants
	for i = 0, 5 do
		local c = if i % 2 == 0 then PAL.yellow else PAL.black
		box(parent, f, u0 - 1.2, u0, i * 0.8, (i + 1) * 0.8, 0.7, 0.76, c)
		box(parent, f, u1, u1 + 1.2, i * 0.8, (i + 1) * 0.8, 0.7, 0.76, c)
	end
	if u1 - u0 > 24 then
		box(parent, f, u0 - 1.2, u1 + 1.2, h + 1.2, h + 3.4, 0, 1.3, PAL.steel, M.Metal)
		for _, u in { u0 - 2.6, u1 + 2.6 } do
			cyl(parent, f, V3.new(u, 0, 1.6), V3.new(u, 3.2, 1.6), 0.9, PAL.yellow)
			cyl(parent, f, V3.new(u, 3.2, 1.6), V3.new(u, 3.7, 1.6), 0.9, PAL.black)
		end
		wallLamp(parent, f, u0 - 3.5, h - 2, 34)
		wallLamp(parent, f, u1 + 3.5, h - 2, 34, true)
		-- armoire à incendie rouge
		box(parent, f, u1 + 5.5, u1 + 7.5, 3, 6, 0, 0.7, PAL.red)
		box(parent, f, u1 + 5.8, u1 + 7.2, 3.3, 5.7, 0.7, 0.75, PAL.white)
	else
		-- auvent et lampe dessous
		box(parent, f, u0 - 1.2, u1 + 1.2, h + 1.6, h + 2.0, 0, 3.2, PAL.steel, M.Metal)
		local lens = box(parent, f, (u0 + u1) / 2 - 0.8, (u0 + u1) / 2 + 0.8, h + 1.5, h + 1.6, 1.4, 2.4, PAL.lamp, M.Neon)
		spot(lens, E.NormalId.Bottom, 110, 22, 2)
	end
end

-- Cette méthode permet d'habiller une façade de bardage : socle béton, joints des panneaux, poteaux, rang de fenêtres,
-- filet et bandeau bleus, couvertine et angles, portes.
local function cladFacade(parent, face, h, opt)
	local bandLow = h - (opt.band or 9)
	local wins = {}
	if opt.windows then
		wins = windowBays(face, opt.pitch, opt.windows[1], opt.windows[2], 1.0)
	end
	hstrip(parent, face, 0, 3.5, 0.25, PAL.plinth, M.Concrete)
	local v = 7
	while v < bandLow - 2.5 do
		hstrip(parent, face, v - 0.07, v + 0.07, 0.08, PAL.joint)
		v += 3.5
	end
	hstrip(parent, face, bandLow - 1.6, bandLow - 1.0, 0.12, PAL.blue)
	hstrip(parent, face, bandLow, h, 0.12, PAL.blue)
	box(parent, face.frame, -0.35, face.len, h - 0.2, h + 3.2, 0, 0.35, PAL.steel, M.Metal)
	local n = math.max(1, math.floor(face.len / opt.pitch + 0.5))
	for k = 1, n - 1 do
		local u = k * face.len / n
		vstrip(parent, face, u - 0.5, u + 0.5, 0, bandLow, 0.6, PAL.steel, M.Metal, 2)
	end
	box(parent, face.frame, 0, 0.9, 0, h, 0, 0.6, PAL.steel, M.Metal)
	box(parent, face.frame, face.len - 0.9, face.len + 0.6, 0, h, 0, 0.6, PAL.steel, M.Metal)
	for k, r in wins do
		window(parent, face, r, PAL.steel, litBay(k, opt.seed or 0))
	end
	for _, d in face.doors do
		door(parent, face, d, "clad")
	end
	-- descente d'eau pluviale près de l'angle de fin
	box(parent, face.frame, face.len - 2.2, face.len - 1.6, 0, h, 0.6, 1.2, PAL.galva, M.Metal)
	return wins
end

-- Cette méthode permet d'habiller une façade en béton préfabriqué : socle, panneaux à joints, fenêtres de bureaux une
-- travée sur deux, filet bleu, corniche anthracite, portes.
local function precastFacade(parent, face, h, opt)
	local P = 6
	local wins = windowBays(face, P, h - 11, h - 5.5, 1.1, 2)
	hstrip(parent, face, 0, 2, 0.2, PAL.plinth, M.Concrete)
	hstrip(parent, face, 10 - 0.08, 10 + 0.08, 0.06, PAL.precastJoint)
	hstrip(parent, face, h - 13 - 0.08, h - 13 + 0.08, 0.06, PAL.precastJoint)
	local n = math.max(1, math.floor(face.len / P + 0.5))
	for k = 1, n - 1 do
		local u = k * face.len / n
		vstrip(parent, face, u - 0.08, u + 0.08, 2, h - 2.6, 0.06, PAL.precastJoint)
	end
	hstrip(parent, face, h - 3.4, h - 2.8, 0.12, PAL.blue)
	box(parent, face.frame, -0.4, face.len, h - 2.6, h + 3.2, 0, 0.4, PAL.steel, M.Concrete)
	for k, r in wins do
		window(parent, face, r, PAL.steel, litBay(k, opt.seed or 0), 1.9)
	end
	for _, d in face.doors do
		door(parent, face, d, "clad")
	end
	if opt.number then
		-- panneau bleu du numéro, à droite de la porte principale
		local d = face.doors[1]
		local u = if d then d[2] + 9 else 10
		box(parent, face.frame, u, u + 15, 6, 19, 0, 0.15, PAL.blue)
		digits(parent, face.frame, u + 2.4, 8.5, 8, opt.number, PAL.white, 0.22)
	end
	return wins
end

-- Cette méthode permet d'habiller une façade en brique (salle des pompes) : socle et corniche en pierre, pilastres,
-- hautes fenêtres cintrées et oculus dans chaque travée, cordon de pierre, portes à clé de voûte.
local function brickFacade(parent, face, h)
	local pitch = 10
	local n = math.max(1, math.floor(face.len / pitch + 0.5))
	local p = face.len / n
	local bays, rects = {}, {}
	for k = 0, n - 1 do
		local uc = (k + 0.5) * p
		local clear = true
		for _, o in face.holes do
			if o[1] < uc + 3.6 and o[2] > uc - 3.6 then
				clear = false
			end
		end
		if clear then
			table.insert(bays, uc)
			table.insert(rects, { uc - 2.2, uc + 2.2, 4.6, 14.5 })
		end
	end
	hstrip(parent, face, 0, 3, 0.4, PAL.stone)
	hstrip(parent, face, 17.4, 18.1, 0.35, PAL.stone)
	box(parent, face.frame, -0.6, face.len, h - 2.2, h - 1.2, 0, 0.45, PAL.stone)
	box(parent, face.frame, -0.9, face.len, h - 1.2, h + 2.8, 0, 0.9, PAL.stone)
	for k = 0, n do
		local u = k * p
		vstrip(parent, face, u - 0.9, u + 0.9, 3, h - 2.2, 0.5, PAL.brickDark, nil, 2)
	end
	for _, uc in bays do
		local u0, u1 = uc - 2.2, uc + 2.2
		-- tableau de pierre, vitre, arc (disque de pierre puis de verre derrière la vitre), petits bois
		box(parent, face.frame, u0 - 0.6, u1 + 0.6, 4.4, 14.5, 0, 0.05, PAL.stone)
		disc(parent, face.frame, uc, 14.5, 5.6, 0, 0.05, PAL.stone)
		disc(parent, face.frame, uc, 14.5, 4.4, 0, 0.1, PAL.glass, M.Glass)
		box(parent, face.frame, u0, u1, 4.6, 14.5, 0, 0.15, PAL.glass, M.Glass)
		box(parent, face.frame, uc - 0.1, uc + 0.1, 4.6, 16.6, 0, 0.22, PAL.white)
		for _, v in { 8, 11.5, 14.5 } do
			box(parent, face.frame, u0, u1, v - 0.1, v + 0.1, 0, 0.22, PAL.white)
		end
		box(parent, face.frame, u0 - 0.7, u1 + 0.7, 4.0, 4.6, 0, 0.5, PAL.stone)
		-- oculus au-dessus du cordon
		disc(parent, face.frame, uc, 20, 3.4, 0, 0.1, PAL.stone)
		disc(parent, face.frame, uc, 20, 2.4, 0, 0.18, PAL.glass, M.Glass)
	end
	for _, d in face.doors do
		door(parent, face, d, "brick")
	end
	return rects
end

-- Toits et intérieurs ---------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser l'acrotère (porteur) sur le bord du toit plat d'un bâtiment.
local function parapet(parent, h, y0, height, color)
	local t = 0.8
	blk(parent, h.x0, h.x1, y0, y0 + height, h.z0, h.z0 + t, color, M.Metal, true)
	blk(parent, h.x0, h.x1, y0, y0 + height, h.z1 - t, h.z1, color, M.Metal, true)
	blk(parent, h.x0, h.x0 + t, y0, y0 + height, h.z0 + t, h.z1 - t, color, M.Metal, true)
	blk(parent, h.x1 - t, h.x1, y0, y0 + height, h.z0 + t, h.z1 - t, color, M.Metal, true)
end

-- Cette méthode permet de poser un groupe de toiture (caisson, grille, ventilateur) au point (x, z) du toit `y`.
local function roofUnit(parent, x, z, y)
	blk(parent, x - 5, x + 5, y, y + 0.6, z - 3, z + 3, PAL.steel, M.Metal, true)
	blk(parent, x - 4.6, x + 4.6, y + 0.6, y + 4.2, z - 2.6, z + 2.6, PAL.white, M.Metal, true)
	blk(parent, x - 4.2, x + 0.4, y + 1.2, y + 3.6, z - 2.7, z - 2.6, PAL.steel, M.Metal)
	post(parent, x + 2.2, z, y + 4.2, y + 5, 3.4, PAL.galva, M.Metal)
	post(parent, x + 2.2, z, y + 5, y + 5.1, 2.8, PAL.black)
end

-- Cette méthode permet de poser les lanterneaux (bandes vitrées en relief, porteuses) d'un toit d'atelier.
local function skylights(parent, h, y)
	for _, t in { 0.25, 0.5, 0.75 } do
		local x = h.x0 + (h.x1 - h.x0) * t
		blk(parent, x - 2.6, x + 2.6, y, y + 0.8, h.z0 + 8, h.z1 - 8, PAL.steel, M.Metal, true)
		blk(parent, x - 2.2, x + 2.2, y + 0.8, y + 1.4, h.z0 + 8.4, h.z1 - 8.4, PAL.paleBlue, M.Glass, true)
	end
end

-- Cette méthode permet de suspendre une lampe d'atelier (cloche, verre lumineux, SpotLight vers le bas sauf si
-- `unlit`) en (x, z).
local function highBay(parent, x, z, y, unlit)
	post(parent, x, z, y + 0.6, y + 4, 0.15, PAL.black)
	post(parent, x, z, y, y + 0.9, 2.4, PAL.steel, M.Metal)
	local lens = blk(parent, x - 0.8, x + 0.8, y - 0.12, y, z - 0.8, z + 0.8, PAL.lamp, M.Neon)
	if not unlit then
		spot(lens, E.NormalId.Bottom, 120, 44, 1.6)
	end
end

-- Cette méthode permet d'aménager un atelier : poteaux et chemins de roulement le long des longs murs, pont roulant
-- (hors des écrans des portes), lampes suspendues, liseré jaune des allées.
local function atelierInside(parent, h)
	local W, y1 = ctx.wall, Q + h.h
	local xi0, xi1, zi0, zi1 = h.x0 + W, h.x1 - W, h.z0 + W, h.z1 - W
	for _, side in { { zi0, zi0 + 1.5 }, { zi1 - 1.5, zi1 } } do
		blk(parent, xi0, xi1, y1 - 10, y1 - 8.5, side[1], side[2], PAL.steel, M.Metal)
	end
	local n = math.floor((xi1 - xi0) / 16.5 + 0.5)
	for k = 1, n - 1 do
		local x = xi0 + k * (xi1 - xi0) / n
		local free = true
		for _, d in h.doors do
			if (d[1] == "S" or d[1] == "N") and x > math.min(d[2], d[3]) - 2 and x < math.max(d[2], d[3]) + 2 then
				free = false
			end
		end
		if free then
			blk(parent, x - 0.6, x + 0.6, Q, y1 - 10, zi0, zi0 + 1.2, PAL.steel, M.Metal, true)
			blk(parent, x - 0.6, x + 0.6, Q, y1 - 10, zi1 - 1.2, zi1, PAL.steel, M.Metal, true)
		end
		-- ferme du toit : membrure basse, membrure haute, montants
		blk(parent, x - 0.4, x + 0.4, y1 - 3.2, y1 - 2.6, zi0, zi1, PAL.steel, M.Metal)
		blk(parent, x - 0.4, x + 0.4, y1 - 0.6, y1, zi0, zi1, PAL.steel, M.Metal)
		for z = zi0 + 6, zi1 - 3, 6 do
			blk(parent, x - 0.2, x + 0.2, y1 - 2.6, y1 - 0.6, z - 0.2, z + 0.2, PAL.steel, M.Metal)
		end
	end
	-- lanterneaux vus du dessous : bandes claires au plafond
	for _, t in { 0.25, 0.5, 0.75 } do
		local x = h.x0 + (h.x1 - h.x0) * t
		blk(parent, x - 2.2, x + 2.2, y1 - 0.08, y1, h.z0 + 8.4, h.z1 - 8.4, PAL.sky, M.Glass)
	end
	-- pont roulant : poutre jaune, sommiers, palan, chaîne, crochet
	local xc, zm = h.x0 + (h.x1 - h.x0) * 0.82, (zi0 + zi1) / 2
	blk(parent, xc - 1.2, xc + 1.2, y1 - 8.5, y1 - 6, zi0 + 0.5, zi1 - 0.5, PAL.yellow, M.Metal)
	for _, z in { zi0 + 0.5, zi1 - 4.5 } do
		blk(parent, xc - 3, xc + 3, y1 - 8.5, y1 - 7, z, z + 4, PAL.yellowDark, M.Metal)
	end
	blk(parent, xc - 1.8, xc + 1.8, y1 - 11, y1 - 8.5, zm - 2, zm + 2, PAL.steel, M.Metal)
	post(parent, xc, zm, y1 - 21, y1 - 11, 0.25, PAL.black)
	blk(parent, xc - 0.7, xc + 0.7, y1 - 22.6, y1 - 21, zm - 0.7, zm + 0.7, PAL.yellow, M.Metal)
	for _, tx in { 0.3, 0.7 } do
		for _, tz in { 0.3, 0.7 } do
			highBay(parent, h.x0 + (h.x1 - h.x0) * tx, h.z0 + (h.z1 - h.z0) * tz, y1 - 4, tx ~= tz)
		end
	end
	-- liseré des allées, à 3 studs des murs
	local y = Q + 0.05
	blk(parent, xi0 + 3, xi1 - 3, Q, y, zi0 + 3, zi0 + 3.3, PAL.yellow)
	blk(parent, xi0 + 3, xi1 - 3, Q, y, zi1 - 3.3, zi1 - 3, PAL.yellow)
	blk(parent, xi0 + 3, xi0 + 3.3, Q, y, zi0 + 3.3, zi1 - 3.3, PAL.yellow)
	blk(parent, xi1 - 3.3, xi1 - 3, Q, y, zi0 + 3.3, zi1 - 3.3, PAL.yellow)
end

-- Cette méthode permet de poser une palette chargée (palette en bois, charge porteuse) au pied (x, z), long de X.
local function palletLoad(parent, x, z, y, height, color)
	blk(parent, x - 2, x + 2, y, y + 0.6, z - 1.6, z + 1.6, PAL.wood, M.WoodPlanks)
	blk(parent, x - 1.9, x + 1.9, y + 0.6, y + height, z - 1.5, z + 1.5, color, M.SmoothPlastic, true)
end

-- Cette méthode permet de poser un rayonnage à palettes (échelles bleues, lisses orange, charges) le long du mur sud
-- d'un magasin, de x0 à x1, le dos contre le mur en `zBack`.
local function rack(parent, x0, x1, zBack)
	local zf, levels = zBack - 3.2, { 0, 5.5, 11 }
	local n = math.floor((x1 - x0) / 9)
	for k = 0, n do
		local x = x0 + k * 9
		for _, z in { zf, zBack - 0.3 } do
			blk(parent, x - 0.2, x + 0.2, Q, Q + 16, z, z + 0.3, PAL.blue, M.Metal, true)
		end
		if k < n then
			for li, lv in levels do
				if lv > 0 then
					blk(parent, x + 0.2, x + 8.8, Q + lv - 0.5, Q + lv, zf, zf + 0.3, PAL.orange, M.Metal, true)
					blk(parent, x + 0.2, x + 8.8, Q + lv - 0.5, Q + lv, zBack - 0.3, zBack, PAL.orange, M.Metal, true)
				end
				if (k + li) % 3 ~= 0 then
					local colors = { PAL.cardboard, PAL.white, PAL.paleBlue }
					palletLoad(parent, x + 2.4, zBack - 1.6, Q + lv, 3.4, colors[(k + li) % 3 + 1])
					palletLoad(parent, x + 6.6, zBack - 1.6, Q + lv, 2.6, colors[(k + 2 * li) % 3 + 1])
				end
			end
		end
	end
end

-- Cette méthode permet d'aménager un magasin : rayonnages contre le mur du fond, lampes suspendues.
local function storeInside(parent, h)
	rack(parent, h.x0 + ctx.wall + 12, h.x1 - ctx.wall - 12, h.z1 - ctx.wall)
	for _, t in { 0.25, 0.5, 0.75 } do
		highBay(parent, h.x0 + (h.x1 - h.x0) * t, (h.z0 + h.z1) / 2, Q + h.h - 4, t == 0.5)
	end
end

-- Cette méthode permet d'aménager la salle des pompes : deux groupes motopompes sur socle, tuyauteries vers le mur,
-- armoires électriques, lampes.
local function pumpInside(parent, h)
	for _, zc in { 186, 204 } do
		blk(parent, 8, 34, Q, Q + 1.5, zc - 3.5, zc + 3.5, PAL.concrete, M.Concrete, true)
		cyl(parent, ORIGIN, V3.new(10, Q + 4.5, zc), V3.new(18, Q + 4.5, zc), 5.4, PAL.pump, M.Metal, true)
		cyl(parent, ORIGIN, V3.new(18, Q + 4, zc), V3.new(20, Q + 4, zc), 2, PAL.steel, M.Metal, true)
		cyl(parent, ORIGIN, V3.new(20, Q + 4, zc), V3.new(30, Q + 4, zc), 4.4, PAL.blue, M.Metal, true)
		cyl(parent, ORIGIN, V3.new(14, Q + 7, zc), V3.new(14, Q + 17, zc), 2.6, PAL.pump, M.Metal, true)
		cyl(parent, ORIGIN, V3.new(14, Q + 17, zc), V3.new(h.x0 + ctx.wall, Q + 17, zc), 2.6, PAL.pump, M.Metal, true)
		local elbow = part(parent, CF.new(14, Q + 17, zc), V3.new(2.6, 2.6, 2.6), PAL.pump, M.Metal, true)
		elbow.Shape = E.PartType.Ball
		-- volant de vanne rouge
		cyl(parent, ORIGIN, V3.new(14, Q + 12, zc - 1.4), V3.new(14, Q + 12, zc - 1.7), 1.8, PAL.red)
	end
	local xe = h.x1 - ctx.wall
	blk(parent, xe - 2, xe, Q, Q + 7, 250, 266, C3.fromRGB(180, 184, 186), M.Metal, true)
	for z = 251.5, 264.5, 3.25 do
		blk(parent, xe - 2.05, xe - 2, Q + 5.3, Q + 5.7, z - 0.2, z + 0.2, PAL.lit, M.Neon)
	end
	for _, z in { 192, 270 } do
		highBay(parent, 27, z, Q + h.h - 3, z < 230)
	end
end

-- Hangar ---------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'habiller la façade est du hangar (face à la forme) et ses pignons : bardage nervuré blanc,
-- poteaux, rang de fenêtres, bandeau bleu au numéro 05, grande porte coulissante bleue à quatre vantaux.
local function hangar(parent, hg)
	local h = hg.h
	local front = {
		frame = faceFrame(V3.new(hg.x1, Q, hg.z1), V3.new(0, 0, -1), V3.new(1, 0, 0)),
		len = hg.z1 - hg.z0,
		holes = {},
		doors = {},
	}
	local du0, du1, dh = hg.z1 - (hg.doorZ + hg.doorW / 2), hg.z1 - (hg.doorZ - hg.doorW / 2), hg.doorH
	table.insert(front.holes, { du0 - 1.6, du1 + 1.6, -1, dh + 3 })
	local wins = windowBays(front, 41.6, 54, 61, 3)
	local ends = {
		{
			frame = faceFrame(V3.new(hg.x1, Q, hg.z0), V3.new(-1, 0, 0), V3.new(0, 0, -1)),
			len = hg.x1 - hg.x0,
			holes = {},
		},
		{
			frame = faceFrame(V3.new(hg.x0, Q, hg.z1), V3.new(1, 0, 0), V3.new(0, 0, 1)),
			len = hg.x1 - hg.x0,
			holes = {},
		},
	}
	for _, face in { front, ends[1], ends[2] } do
		hstrip(parent, face, 0, 4, 0.3, PAL.plinth, M.Concrete)
		for u = 2, face.len - 1, 4 do
			vstrip(parent, face, u - 0.3, u + 0.3, 4, 68.4, 0.25, PAL.rib, nil, 2)
		end
		hstrip(parent, face, 68.4, 69, 0.14, PAL.blue)
		hstrip(parent, face, 70, 88, 0.14, PAL.blue)
		box(parent, face.frame, -0.4, face.len, 88, h + 1.2, 0, 0.4, PAL.steel, M.Metal)
	end
	local n = 12
	for k = 1, n - 1 do
		local u = k * front.len / n
		vstrip(parent, front, u - 0.8, u + 0.8, 0, 70, 0.8, PAL.steel, M.Metal, 2)
	end
	for k, r in wins do
		window(parent, front, r, PAL.steel, litBay(k, 2), 3)
	end
	digits(parent, front.frame, 34, 72.5, 13, "05", PAL.white, 0.22)
	-- grande porte : quatre vantaux bleus raidis, rail haut, montants, portillon, plinthe hachurée
	local f = front.frame
	local leaf = (du1 - du0) / 4
	for i = 0, 3 do
		local a, b = du0 + i * leaf, du0 + (i + 1) * leaf
		box(parent, f, a + 0.12, b - 0.12, 0, dh, 0, 0.35, PAL.blue)
		for v = 8, dh - 4, 8 do
			box(parent, f, a + 0.6, b - 0.6, v - 0.3, v + 0.3, 0.35, 0.55, PAL.paleBlue, M.Metal)
		end
		box(parent, f, a + 0.6, a + 1.2, 0.6, dh - 0.6, 0.35, 0.55, PAL.paleBlue, M.Metal)
		box(parent, f, b - 1.2, b - 0.6, 0.6, dh - 0.6, 0.35, 0.55, PAL.paleBlue, M.Metal)
	end
	box(parent, f, du0 - 6, du1 + 6, dh, dh + 3, 0, 1.6, PAL.steel, M.Metal)
	box(parent, f, du0 - 1.6, du0, 0, dh, 0, 1.0, PAL.steel, M.Metal)
	box(parent, f, du1, du1 + 1.6, 0, dh, 0, 1.0, PAL.steel, M.Metal)
	box(parent, f, du0 + leaf + 6, du0 + leaf + 10, 0, 7.5, 0.35, 0.6, PAL.steel, M.Metal)
	box(parent, f, du0 + leaf + 6.4, du0 + leaf + 9.6, 0.3, 7.1, 0.6, 0.65, PAL.navy)
	for u = du0, du1 - 3, 6 do
		box(parent, f, u, u + 3, 0, 1, 0.55, 0.7, PAL.yellow)
		box(parent, f, u + 3, u + 6, 0, 1, 0.55, 0.7, PAL.black)
	end
	wallLamp(parent, f, du0 - 6, 22, 40)
	wallLamp(parent, f, du1 + 6, 22, 40)
end

-- Navire ---------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de peindre les flancs d'un tronçon : soudures (lisses et abouts), liston blanc du pavois,
-- numéro du tronçon, échelles de tirant d'eau si demandées.
local function hullSides(parent, s, index, marks)
	local a, b, deck = s[1], s[2], ctx.deck
	local sides = {
		{ frame = faceFrame(V3.new(b, 0, 205), V3.new(-1, 0, 0), V3.new(0, 0, -1)), north = true },
		{ frame = faceFrame(V3.new(a, 0, 255), V3.new(1, 0, 0), V3.new(0, 0, 1)) },
	}
	local len = b - a
	for _, side in sides do
		local f = side.frame
		for _, sv in { { 23.2, PAL.antifoulDark }, { 33, PAL.navyDark }, { 38.5, PAL.navyDark } } do
			box(parent, f, 0, len, sv[1] - 0.09, sv[1] + 0.09, 0, 0.08, sv[2], M.Metal)
		end
		for u = 6, len - 3, 12 do
			box(parent, f, u - 0.09, u + 0.09, 20, 26.5, 0, 0.08, PAL.antifoulDark, M.Metal)
			box(parent, f, u - 0.09, u + 0.09, 28, deck - 0.9, 0, 0.08, PAL.navyDark, M.Metal)
		end
		box(parent, f, 0, len, deck + 2.5, deck + 2.75, -0.1, 0.9, PAL.white)
		digits(parent, f, 8, 31.5, 8.5, tostring(index), PAL.white, 0.14)
		for _, mx in marks do
			local u = if side.north then b - mx - 0.7 else mx - a - 0.7
			for v = 21, deck - 2, 2 do
				box(parent, f, u, u + 1.4, v, v + 0.35, 0, 0.12, PAL.white)
			end
		end
	end
end

-- Cette méthode permet de montrer la coupe d'un tronçon ouvert (bout tourné vers un autre tronçon) : tôles en
-- primaire, ponts et couples en relief, dans le profil de la coque.
local function openEnd(parent, x, out)
	local deck = ctx.deck
	local f = if out > 0
		then faceFrame(V3.new(x, 0, 255), V3.new(0, 0, -1), V3.new(1, 0, 0))
		else faceFrame(V3.new(x, 0, 205), V3.new(0, 0, 1), V3.new(-1, 0, 0))
	local rects = { { 0, 50, 20, deck }, { 5, 45, 10, 20 }, { 15, 35, 5, 10 } }
	for _, r in rects do
		box(parent, f, r[1] + 0.8, r[2] - 0.8, r[3], r[4], 0, 0.1, PAL.primer, M.Metal)
	end
	for _, v in { 26.5, 32.5, 38.5 } do
		box(parent, f, 0.8, 49.2, v - 0.25, v + 0.25, 0, 0.45, PAL.steel, M.Metal)
	end
	box(parent, f, 5.8, 44.2, 14.75, 15.25, 0, 0.45, PAL.steel, M.Metal)
	for u = 5, 45, 5 do
		local v0 = if u >= 15 and u <= 35 then 5 elseif u >= 5 and u <= 45 then 10 else 20
		box(parent, f, u - 0.2, u + 0.2, v0, deck - 0.9, 0, 0.4, PAL.steel, M.Metal)
	end
end

-- Cette méthode permet de poser un échafaudage (montants, lisses, moises, planchers, diagonales) devant une façade,
-- de u0 à u1, jusqu'à la hauteur `top`, profond de `depth`.
local function scaffold(parent, f, u0, u1, top, depth)
	local n = math.max(1, math.floor((u1 - u0) / 6.3 + 0.5))
	local p = (u1 - u0) / n
	for k = 0, n do
		local u = u0 + k * p
		for _, w in { 0.6, depth } do
			cyl(parent, f, V3.new(u, 0, w), V3.new(u, top + 3, w), 0.3, PAL.galva, M.Metal)
		end
	end
	for v = 6, top, 6 do
		for _, w in { 0.6, depth } do
			cyl(parent, f, V3.new(u0, v, w), V3.new(u1, v, w), 0.25, PAL.galva, M.Metal)
			cyl(parent, f, V3.new(u0, v + 1, w), V3.new(u1, v + 1, w), 0.2, PAL.galva, M.Metal)
		end
		for k = 0, n, 2 do
			local u = u0 + k * p
			cyl(parent, f, V3.new(u, v, 0.6), V3.new(u, v, depth), 0.25, PAL.galva, M.Metal)
		end
		box(parent, f, u0, u1, v - 0.35, v - 0.12, 0.8, depth - 0.2, PAL.wood, M.WoodPlanks)
	end
	for k = 0, n - 1, 2 do
		local u = u0 + k * p
		cyl(parent, f, V3.new(u, 0.4, depth), V3.new(u + p, math.min(top, 12), depth), 0.22, PAL.galva, M.Metal)
	end
end

-- Cette méthode permet d'habiller le château : fenêtres, passerelle, cheminée bleue à bande blanche et coiffe noire,
-- mât et radar, canots de sauvetage orange sur bossoirs.
local function superstructure(parent)
	local deck = ctx.deck
	local faces = {
		{ faceFrame(V3.new(150, 0, 212), V3.new(-1, 0, 0), V3.new(0, 0, -1)), 45 },
		{ faceFrame(V3.new(105, 0, 248), V3.new(1, 0, 0), V3.new(0, 0, 1)), 45 },
		{ faceFrame(V3.new(105, 0, 212), V3.new(0, 0, 1), V3.new(-1, 0, 0)), 36 },
	}
	for fi, fd in faces do
		local f, len = fd[1], fd[2]
		for u = 3, len - 3, 4.5 do
			local lit = ((math.floor(u) + fi) % 3) == 0
			box(parent, f, u - 0.8, u + 0.8, deck + 4, deck + 6, 0, 0.1, if lit then PAL.lit else PAL.glass, if lit then M.Neon else M.Glass)
		end
		for u = 3, len - 4, 4 do
			box(parent, f, u, u + 3, deck + 15, deck + 18.5, 0, 0.1, PAL.glass, M.Glass)
		end
		box(parent, f, 0, len, deck + 9.8, deck + 10.2, 0, 0.2, PAL.navy)
	end
	-- passerelle : vitrage continu à l'avant (face est), visière
	local front = faceFrame(V3.new(150, 0, 248), V3.new(0, 0, -1), V3.new(1, 0, 0))
	box(parent, front, 1.5, 34.5, deck + 14.5, deck + 19.5, 0, 0.1, PAL.glass, M.Glass)
	for u = 1.5, 34.5, 3 do
		box(parent, front, u - 0.12, u + 0.12, deck + 14.5, deck + 19.5, 0, 0.2, PAL.white)
	end
	box(parent, front, 0, 36, deck + 19.5, deck + 20, 0, 1.4, PAL.white)
	-- cheminée : bande blanche et coiffe noire (enveloppes autour du caisson), chapeau
	blk(parent, 111.85, 124.15, deck + 28.4, deck + 30.4, 223.85, 236.15, PAL.white)
	blk(parent, 111.85, 124.15, deck + 32.4, deck + 34.05, 223.85, 236.15, PAL.black)
	blk(parent, 112.6, 123.4, deck + 34, deck + 34.4, 224.6, 235.4, PAL.black)
	-- mât, vergue, radar, feux
	post(parent, 142, 230, deck + 23.5, deck + 40, 0.8, PAL.white)
	blk(parent, 141.6, 142.4, deck + 36, deck + 36.5, 224, 236, PAL.white)
	post(parent, 134, 230, deck + 23.5, deck + 27, 1, PAL.white)
	blk(parent, 130, 138, deck + 27, deck + 27.4, 229.5, 230.5, PAL.black)
	blk(parent, 141.7, 142.3, deck + 36.5, deck + 37.1, 224, 224.6, PAL.red, M.Neon)
	blk(parent, 141.7, 142.3, deck + 36.5, deck + 37.1, 235.4, 236, C3.fromRGB(60, 200, 90), M.Neon)
	blk(parent, 141.7, 142.3, deck + 40, deck + 40.6, 229.7, 230.3, PAL.white, M.Neon)
	-- canots sur bossoirs, de chaque côté (au-dessus des têtes, coursive libre dessous)
	for _, s in { { 207, 211, 212, -1 }, { 249, 253, 248, 1 } } do
		local z0, z1, zw = s[1], s[2], s[3]
		local boat = blk(parent, 118, 132, deck + 9, deck + 11, z0, z1, PAL.orange)
		boat.CastShadow = true
		blk(parent, 119, 131, deck + 11, deck + 12.4, z0 + 0.3, z1 - 0.3, PAL.orange)
		blk(parent, 121, 129, deck + 12.4, deck + 12.9, z0 + 0.8, z1 - 0.8, PAL.white)
		for _, x in { 119.5, 130.5 } do
			blk(parent, x - 0.3, x + 0.3, deck + 8, deck + 14, math.min(zw, zw + s[4] * 0.6), math.max(zw, zw + s[4] * 0.6), PAL.white)
			blk(parent, x - 0.3, x + 0.3, deck + 13.6, deck + 14.2, math.min(zw, (z0 + z1) / 2), math.max(zw, (z0 + z1) / 2), PAL.white)
			post(parent, x, (z0 + z1) / 2, deck + 12.4, deck + 13.6, 0.12, PAL.black)
		end
	end
end

-- Cette méthode permet d'équiper le pont : bittes d'amarrage, manches à air, guindeau, rebords et joints des panneaux
-- de cale, cerclage du bois de chantier.
local function deckGear(parent, hatches)
	local deck = ctx.deck
	for _, b in { { 99, 208.5 }, { 99, 251.5 }, { 402, 208.5 }, { 402, 251.5 }, { 300, 208.5 }, { 230, 251.5 } } do
		blk(parent, b[1] - 2, b[1] + 2, deck, deck + 0.3, b[2] - 1, b[2] + 1, PAL.black, M.Metal)
		post(parent, b[1] - 1, b[2], deck, deck + 2, 1.3, PAL.black, M.Metal, true)
		post(parent, b[1] + 1, b[2], deck, deck + 2, 1.3, PAL.black, M.Metal, true)
	end
	for _, v in { { 165, 209 }, { 165, 251 }, { 268, 209 }, { 268, 251 }, { 372, 209 }, { 372, 251 } } do
		post(parent, v[1], v[2], deck, deck + 2.6, 1.1, PAL.white, M.Metal, true)
		post(parent, v[1], v[2], deck + 2.6, deck + 3.3, 1.9, PAL.white, M.Metal)
	end
	-- guindeau sur le pont d'étrave, chaînes vers les écubiers
	blk(parent, 412, 419, deck, deck + 1, 221, 239, PAL.steel, M.Metal, true)
	for _, z in { 224, 236 } do
		cyl(parent, ORIGIN, V3.new(415.5, deck + 2.2, z - 1.8), V3.new(415.5, deck + 2.2, z + 1.8), 2.6, PAL.navy, M.Metal, true)
		local dz = if z < 230 then -1 else 1
		blk(parent, 419, 428, deck, deck + 0.35, z + dz * 0.2 - 0.4, z + dz * 0.2 + 0.4, PAL.black, M.Metal)
	end
	for _, hb in hatches do
		local x0, x1, top, z0, z1 = hb[1], hb[2], hb[3], hb[4], hb[5]
		blk(parent, x0 - 0.4, x1 + 0.4, deck, deck + 1.2, z0 - 0.4, z1 + 0.4, PAL.steel, M.Metal)
		local n = math.max(1, math.floor((x1 - x0) / 8.5 + 0.5))
		for i = 1, n - 1 do
			local x = x0 + (x1 - x0) * i / n
			blk(parent, x - 0.15, x + 0.15, top, top + 0.08, z0, z1, PAL.steel, M.Metal)
		end
		blk(parent, x0, x1, top, top + 0.06, (z0 + z1) / 2 - 0.12, (z0 + z1) / 2 + 0.12, PAL.steel, M.Metal)
	end
	for _, x in { 383, 389, 395 } do
		blk(parent, x - 0.3, x + 0.3, deck, deck + 7.6, 219.9, 240.1, PAL.galva, M.Metal)
	end
end

-- Cette méthode permet de poser l'arrière du navire : hélice en bronze (moyeu, quatre pales vrillées), safran et son
-- talon, échelle de tirant d'eau peinte.
local function sternGear(parent)
	local hub = V3.new(91.5, 13, 230)
	cyl(parent, ORIGIN, V3.new(89.8, 13, 230), V3.new(95, 13, 230), 2.8, PAL.bronze, M.Metal, true)
	for i = 0, 3 do
		local ang = math.pi / 4 + i * math.pi / 2
		local dir = V3.new(0, math.sin(ang), math.cos(ang))
		local cf = CF.fromMatrix(hub + dir * 3.3, V3.new(1, 0, 0), dir) * CF.Angles(0, 0.45, 0)
		part(parent, cf, V3.new(0.5, 4.6, 2.2), PAL.bronze, M.Metal, true)
	end
	blk(parent, 86, 87.6, 5.5, 22, 227.5, 232.5, PAL.antifoul, M.Metal, true)
	blk(parent, 86, 95, 20, 22.5, 228.6, 231.4, PAL.antifoul, M.Metal, true)
end

-- Portique ------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'habiller le portique (structure porteuse posée par build_radoub) : contreventement des pieds,
-- roues des bogies, raidisseurs et panneau de charge des poutres, damiers d'extrémité, garde-corps de la passerelle,
-- cabine suspendue, palan et crochet, butoirs des rails.
local function gantry(parent, g)
	local yb = g.beamLow
	for _, leg in g.legs do
		local zc = (leg[1] + leg[2]) / 2
		for _, y in { 80, 95 } do
			cyl(parent, ORIGIN, V3.new(251, y, zc), V3.new(261, y, zc), 1.4, PAL.yellow, M.Metal)
		end
		for _, z in { leg[1] + 0.8, leg[2] - 0.8 } do
			cyl(parent, ORIGIN, V3.new(251, Q + 6, z), V3.new(261, yb - 1, z), 0.9, PAL.yellowDark, M.Metal)
			cyl(parent, ORIGIN, V3.new(261, Q + 6, z), V3.new(251, yb - 1, z), 0.9, PAL.yellowDark, M.Metal)
		end
		for _, x in { 248.5, 256, 263.5 } do
			cyl(parent, ORIGIN, V3.new(x, Q + 1.6, leg[1] + 2.7), V3.new(x, Q + 1.6, leg[2] - 2.7), 3.2, PAL.black, M.Metal)
		end
		blk(parent, 244.9, 267.1, Q + 4.6, Q + 5, leg[1] + 2.9, leg[2] - 2.9, PAL.black, M.Metal)
	end
	-- raidisseurs sur les faces extérieures des poutres, panneau bleu de charge « 300 »
	local z0, z1 = g.z0, g.z1
	local west = faceFrame(V3.new(245, 0, z0), V3.new(0, 0, 1), V3.new(-1, 0, 0))
	local east = faceFrame(V3.new(267, 0, z1), V3.new(0, 0, -1), V3.new(1, 0, 0))
	for _, f in { west, east } do
		for u = 10, (z1 - z0) - 5, 10 do
			box(parent, f, u - 0.25, u + 0.25, yb, g.top, 0, 0.3, PAL.yellowDark, M.Metal)
		end
		local mid = (z1 - z0) / 2
		box(parent, f, mid - 21, mid + 21, yb + 1.2, g.top - 1.2, 0.3, 0.45, PAL.blue)
		digits(parent, f, mid - 7.5, yb + 2.4, 4.2, "300", PAL.white, 0.6)
	end
	-- damiers rouge et blanc aux bouts des poutres
	for _, e in { { z0, -1 }, { z1, 1 } } do
		for _, x0 in { 245, 261 } do
			for i = 0, 1 do
				for j = 0, 1 do
					local c = if (i + j) % 2 == 0 then PAL.red else PAL.white
					local za, zb = if e[2] < 0 then e[1] - 0.12 else e[1], if e[2] < 0 then e[1] else e[1] + 0.12
					blk(parent, x0 + i * 3, x0 + (i + 1) * 3, yb + j * 4.5, yb + (j + 1) * 4.5, za, zb, c)
				end
			end
		end
	end
	-- garde-corps (porteurs) le long des bords de la passerelle haute : main courante à 3,5, sous-lisse, poteaux
	-- (côté ouest : coupé au débouché des échelles, sinon on resterait coincé sous la main courante)
	for _, x in { 245.3, 266.7 } do
		local gaps = if x < 256 then g.ladderGaps else {}
		for _, s in minus(z0, z1, gaps) do
			blk(parent, x - 0.15, x + 0.15, g.top + g.railH - 0.2, g.top + g.railH + 0.1, s[1], s[2], PAL.yellow, M.Metal, true)
			blk(parent, x - 0.1, x + 0.1, g.top + g.railH / 2, g.top + g.railH / 2 + 0.2, s[1], s[2], PAL.yellow, M.Metal, true)
			for z = s[1] + 0.15, s[2] - 0.1, 5 do
				blk(parent, x - 0.15, x + 0.15, g.top, g.top + g.railH - 0.2, z - 0.15, z + 0.15, PAL.yellow, M.Metal, true)
			end
			blk(parent, x - 0.15, x + 0.15, g.top, g.top + g.railH - 0.2, s[2] - 0.3, s[2], PAL.yellow, M.Metal, true)
		end
	end
	-- cabine suspendue sous la poutre est, près du pied nord
	blk(parent, 263, 267, yb - 3, yb, 129, 135, PAL.steel, M.Metal)
	local cab = blk(parent, 261.5, 270, yb - 11, yb - 3, 127.5, 136.5, PAL.white, M.Metal)
	cab.CastShadow = true
	blk(parent, 261.4, 270.1, yb - 8.5, yb - 4.5, 127.4, 136.6, PAL.glass, M.Glass)
	blk(parent, 261.3, 270.2, yb - 3.3, yb - 2.9, 127.3, 136.7, PAL.steel, M.Metal)
	-- palan : chariot (tambours, moteurs, bande hachurée), quatre brins jusqu'à la moufle, crochet
	local t = g.trolley
	local xc, zc = (t[1] + t[2]) / 2, (t[5] + t[6]) / 2
	for _, x in { t[1] - 0.12, t[2] } do
		blk(parent, x, x + 0.12, t[3] + 1, t[4] - 1, t[5] + 1, t[6] - 1, PAL.blue)
	end
	for z = t[5], t[6] - 2, 4 do
		blk(parent, t[1] - 0.05, t[2] + 0.05, t[3] - 0.05, t[3] + 0.6, z, z + 2, PAL.black)
	end
	cyl(parent, ORIGIN, V3.new(t[1] + 1.5, t[3] - 1.6, zc - 4), V3.new(t[2] - 1.5, t[3] - 1.6, zc - 4), 3, PAL.steel, M.Metal)
	cyl(parent, ORIGIN, V3.new(t[1] + 1.5, t[3] - 1.6, zc + 4), V3.new(t[2] - 1.5, t[3] - 1.6, zc + 4), 3, PAL.steel, M.Metal)
	blk(parent, t[1] + 1, t[1] + 4, t[3] - 3, t[3], t[6] - 4, t[6] - 1, PAL.blue, M.Metal)
	for _, dx in { -2.5, 2.5 } do
		for _, dz in { -2.5, 2.5 } do
			post(parent, xc + dx, zc + dz, 71, t[3], 0.3, PAL.black)
		end
	end
	blk(parent, xc - 3.2, xc + 3.2, 68, 71, zc - 3.2, zc + 3.2, PAL.yellow, M.Metal)
	for i = 0, 3 do
		blk(parent, xc - 3.25, xc + 3.25, 68.2 + i * 0.7, 68.55 + i * 0.7, zc - 3.25, zc + 3.25, PAL.black)
	end
	blk(parent, xc - 0.6, xc + 0.6, 64.2, 68, zc - 0.6, zc + 0.6, PAL.steel, M.Metal)
	blk(parent, xc - 0.6, xc + 1.8, 63.4, 64.2, zc - 0.6, zc + 0.6, PAL.steel, M.Metal)
	-- butoirs aux bouts des rails
	for _, r in g.rails do
		for _, x in { g.railX0 + 1.2, r.x1 - 1.2 } do
			blk(parent, x - 1, x + 1, Q, Q + 2.2, r.z - 1.4, r.z + 1.4, PAL.yellow, M.Metal)
			blk(parent, x - 1.05, x + 1.05, Q + 0.8, Q + 1.4, r.z - 1.45, r.z + 1.45, PAL.black)
		end
	end
end

-- Quais ---------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser une bitte d'amarrage (embase, fût porteur, tête évasée à liseré jaune) en (x, z).
local function bollard(parent, x, z)
	post(parent, x, z, Q, Q + 0.4, 3.2, PAL.black, M.Metal)
	post(parent, x, z, Q + 0.4, Q + 2.4, 2.2, PAL.black, M.Metal, true)
	post(parent, x, z, Q + 2.4, Q + 3.0, 2.9, PAL.black, M.Metal, true)
	post(parent, x, z, Q + 3.0, Q + 3.12, 2.9, PAL.yellow)
end

-- Cette méthode permet de garder la composante horizontale d'un vecteur (cap d'un projecteur vu de dessus).
local function flat(v)
	local f = V3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else V3.new(1, 0, 0)
end

-- Cette méthode permet de poser un mât d'éclairage (embase, fût porteur, traverse, trois projecteurs tournés vers
-- `target`, une SpotLight sur celui du milieu).
local function lampMast(parent, x, z, target)
	blk(parent, x - 1.3, x + 1.3, Q, Q + 1, z - 1.3, z + 1.3, PAL.concrete, M.Concrete, true)
	post(parent, x, z, Q + 1, Q + 44, 1.3, PAL.galva, M.Metal, true)
	local side = flat(target - V3.new(x, Q + 44, z)):Cross(V3.new(0, 1, 0)).Unit
	local head = V3.new(x, Q + 44, z)
	-- projecteurs pointés sur le quai devant le mât, vers la forme (une SpotLight ne porte qu'à 60 studs)
	target = V3.new(x, Q, z) + flat(target - head) * 36
	cyl(parent, ORIGIN, head - side * 4, head + side * 4, 0.5, PAL.galva, M.Metal)
	for i = -1, 1 do
		local pos = head + side * (i * 3) + V3.new(0, 0.9, 0)
		local f = aim(pos, (target - pos).Unit)
		part(parent, f, V3.new(2.2, 1.4, 1.0), PAL.steel, M.Metal)
		local lens = part(parent, f * CF.new(0, 0, -0.55), V3.new(1.9, 1.1, 0.12), PAL.lamp, M.Neon)
		if i == 0 then
			spot(lens, E.NormalId.Front, 70, 60, 4)
		end
	end
end

-- Cette méthode permet d'habiller un conteneur (bloc porteur posé par build_radoub) : longerons, montants d'angle,
-- ondulations des flancs, portes à barres de verrouillage, pièces de coin.
local function container(parent, c)
	local x0, z0, y0, color = c[1], c[2], Q + c[3], c[4]
	local x1, z1, y1 = x0 + 24, z0 + 10, y0 + 10
	local shade = color:Lerp(PAL.black, 0.22)
	local sides = {
		faceFrame(V3.new(x1, y0, z0), V3.new(-1, 0, 0), V3.new(0, 0, -1)),
		faceFrame(V3.new(x0, y0, z1), V3.new(1, 0, 0), V3.new(0, 0, 1)),
	}
	for _, f in sides do
		box(parent, f, 0, 24, 0, 0.6, 0, 0.2, shade)
		box(parent, f, 0, 24, 9.4, 10, 0, 0.2, shade)
		box(parent, f, 0, 0.6, 0, 10, 0, 0.25, shade)
		box(parent, f, 23.4, 24, 0, 10, 0, 0.25, shade)
		for u = 1.6, 22.5, 1.5 do
			box(parent, f, u - 0.35, u + 0.35, 0.6, 9.4, 0, 0.12, shade)
		end
	end
	local doorFace = faceFrame(V3.new(x1, y0, z1), V3.new(0, 0, -1), V3.new(1, 0, 0))
	box(parent, doorFace, 0, 10, 0, 0.6, 0, 0.2, shade)
	box(parent, doorFace, 0, 10, 9.4, 10, 0, 0.2, shade)
	box(parent, doorFace, 4.95, 5.05, 0.6, 9.4, 0, 0.12, PAL.black)
	for _, u in { 1.6, 3.3, 6.7, 8.4 } do
		cyl(parent, doorFace, V3.new(u, 0.7, 0.3), V3.new(u, 9.3, 0.3), 0.25, PAL.galva, M.Metal)
		box(parent, doorFace, u - 0.15, u + 0.6, 4.4, 4.7, 0.2, 0.45, PAL.galva, M.Metal)
	end
	for _, x in { x0 - 0.05, x1 - 0.85 } do
		for _, y in { y0 - 0.05, y1 - 0.85 } do
			for _, z in { z0 - 0.05, z1 - 0.85 } do
				blk(parent, x, x + 0.9, y, y + 0.9, z, z + 0.9, PAL.black, M.Metal)
			end
		end
	end
end

-- Cette méthode permet de dessiner une pile de tôles (bloc porteur invisible posé par build_radoub) : lits de tôles
-- en acier ou en primaire séparés de bastaings.
local function plateStack(parent, t)
	local x0, x1, h, z0, z1 = t[1], t[2], t[3], t[4], t[5]
	local y, layer = Q, 0
	while y + 0.9 <= Q + h + 0.01 do
		for _, x in { x0 + 2, (x0 + x1) / 2, x1 - 2 } do
			blk(parent, x - 0.5, x + 0.5, y, y + 0.35, z0 + 0.3, z1 - 0.3, PAL.wood, M.WoodPlanks)
		end
		local inset = (layer % 3) * 0.15
		local color = if layer % 2 == 0 then C3.fromRGB(112, 118, 124) else C3.fromRGB(140, 128, 118)
		blk(parent, x0 + inset, x1 - 0.3 + inset, y + 0.35, y + 0.9, z0 + inset, z1 - 0.2, color, M.Metal)
		y += 0.9
		layer += 1
	end
end

-- Cette méthode permet de poser une bobine de câble (joues, fût, spires) d'axe Z, porteuse, centrée en (x, z).
local function cableReel(parent, x, z, d, width)
	local y = Q + d / 2
	for _, dz in { -width / 2, width / 2 - 0.4 } do
		cyl(parent, ORIGIN, V3.new(x, y, z + dz), V3.new(x, y, z + dz + 0.4), d, PAL.wood, M.WoodPlanks, true)
	end
	cyl(parent, ORIGIN, V3.new(x, y, z - width / 2 + 0.4), V3.new(x, y, z + width / 2 - 0.4), d * 0.78, PAL.black, M.SmoothPlastic, true)
end

-- Cette méthode permet de poser une cabane de chantier (bloc porteur, jupe bleue, fenêtres, porte, climatiseur) dont la
-- façade est tournée vers +X.
local function siteCabin(parent, x0, x1, z0, z1)
	local cab = blk(parent, x0, x1, Q, Q + 8.5, z0, z1, PAL.white, M.Metal, true)
	cab.Name = "SiteCabin"
	blk(parent, x0 - 0.1, x1 + 0.1, Q, Q + 1, z0 - 0.1, z1 + 0.1, PAL.blue)
	blk(parent, x0 - 0.2, x1 + 0.2, Q + 8.5, Q + 9, z0 - 0.2, z1 + 0.2, PAL.steel, M.Metal, true)
	local f = faceFrame(V3.new(x1, Q, z1), V3.new(0, 0, -1), V3.new(1, 0, 0))
	local face = { frame = f, len = z1 - z0, holes = {} }
	window(parent, face, { 1.5, 4.5, 3.5, 6.5 }, PAL.steel, true)
	window(parent, face, { 9.5, 12.5, 3.5, 6.5 }, PAL.steel, false)
	box(parent, f, 6, 8.4, 1, 7.4, 0, 0.12, PAL.blue)
	box(parent, f, 4.8, 9.6, 1, 1.25, 0, 1.2, PAL.galva, M.Metal)
	box(parent, f, 13.2, 15, 5, 7.5, 0, 1.2, PAL.galva, M.Metal)
	wallLamp(parent, f, 7.2, 8.0, 20)
end

-- Cette méthode permet de poser un râtelier de bouteilles de gaz (cage, bouteilles colorées) contre une façade.
local function gasRack(parent, f, u0)
	box(parent, f, u0, u0 + 6, 0, 0.2, 0, 1.6, PAL.galva, M.Metal)
	box(parent, f, u0, u0 + 6, 4, 4.15, 0.2, 1.6, PAL.galva, M.Metal)
	for _, u in { u0, u0 + 5.85 } do
		box(parent, f, u, u + 0.15, 0, 4.15, 1.45, 1.6, PAL.galva, M.Metal)
	end
	local colors = { C3.fromRGB(60, 120, 70), PAL.galva, PAL.red, C3.fromRGB(60, 120, 70), PAL.galva }
	for i, c in colors do
		local u = u0 + 0.7 + (i - 1) * 1.15
		cyl(parent, f, V3.new(u, 0.2, 0.8), V3.new(u, 4.2, 0.8), 0.9, c, M.Metal)
		cyl(parent, f, V3.new(u, 4.2, 0.8), V3.new(u, 4.7, 0.8), 0.4, PAL.black, M.Metal)
	end
end

-- Cette méthode permet de poser un tas de profilés en H (âme et ailes porteuses) sur cales, le long de X.
local function beamStack(parent, x0, x1, z0, rows)
	local y = Q
	for r = 1, rows do
		for _, x in { x0 + 2, x1 - 2 } do
			blk(parent, x - 0.6, x + 0.6, y, y + 0.5, z0, z0 + 2.4 * 3, PAL.wood, M.WoodPlanks)
		end
		y += 0.5
		for i = 0, 2 do
			local z = z0 + i * 2.4 + (r % 2) * 0.6
			blk(parent, x0, x1, y, y + 0.2, z, z + 1.8, PAL.primer, M.Metal, true)
			blk(parent, x0, x1, y + 0.2, y + 1.6, z + 0.82, z + 0.98, PAL.primer, M.Metal, true)
			blk(parent, x0, x1, y + 1.6, y + 1.8, z, z + 1.8, PAL.primer, M.Metal, true)
		end
		y += 1.8
	end
end

-- Cette méthode permet de peindre les quais : couronnement clair et liseré de sécurité jaune le long de la forme et
-- des bords de mer, joints de dalles, rails du portique sur leur longrine, défenses en caoutchouc côté mer.
local function quays(parent, q)
	-- bord de la forme (couronnement, liseré à 6,5 studs du bord, derrière les bittes)
	blk(parent, q.dockX0, q.dockX1, Q, Q + 0.07, q.crestN - 2.5, q.crestN, PAL.coping, M.Concrete)
	blk(parent, q.dockX0, q.dockX1, Q, Q + 0.1, q.crestN - 6.7, q.crestN - 6.3, PAL.yellow)
	blk(parent, q.dockX0, q.dockX1, Q, Q + 0.07, q.crestS, q.crestS + 2.5, PAL.coping, M.Concrete)
	blk(parent, q.dockX0, q.dockX1, Q, Q + 0.1, q.crestS + 6.3, q.crestS + 6.7, PAL.yellow)
	-- bords de mer : nord, sud, est (hors bateau-porte)
	blk(parent, q.x0, q.x1, Q, Q + 0.07, q.z0, q.z0 + 1.5, PAL.coping, M.Concrete)
	blk(parent, q.x0, q.x1, Q, Q + 0.1, q.z0 + 3, q.z0 + 3.4, PAL.yellow)
	blk(parent, q.x0, q.x1, Q, Q + 0.07, q.z1 - 1.5, q.z1, PAL.coping, M.Concrete)
	blk(parent, q.x0, q.x1, Q, Q + 0.1, q.z1 - 3.4, q.z1 - 3, PAL.yellow)
	for _, zr in { { q.z0 + 1.5, q.crestN, q.z0 + 3.4, q.crestN }, { q.crestS, q.z1 - 1.5, q.crestS, q.z1 - 3.4 } } do
		blk(parent, q.x1 - 1.5, q.x1, Q, Q + 0.07, zr[1], zr[2], PAL.coping, M.Concrete)
		blk(parent, q.x1 - 3.4, q.x1 - 3, Q, Q + 0.1, zr[3], zr[4], PAL.yellow)
	end
	-- joints de dalles
	for z = q.z0 + 30, q.z1 - 10, 30 do
		if z < q.crestN - 8 or z > q.crestS + 8 then
			blk(parent, q.x0, q.x1 - 3.4, Q, Q + 0.04, z - 0.15, z + 0.15, PAL.slabJoint)
		elseif z > q.crestN and z < q.crestS then
			blk(parent, q.x0, q.dockX0, Q, Q + 0.04, z - 0.15, z + 0.15, PAL.slabJoint)
		end
	end
	for x = q.x0 + 32, q.x1 - 8, 32 do
		if x < q.dockX0 then
			blk(parent, x - 0.15, x + 0.15, Q, Q + 0.04, q.z0 + 3.4, q.z1 - 3.4, PAL.slabJoint)
		else
			blk(parent, x - 0.15, x + 0.15, Q, Q + 0.04, q.z0 + 3.4, q.crestN - 6.7, PAL.slabJoint)
			blk(parent, x - 0.15, x + 0.15, Q, Q + 0.04, q.crestS + 6.7, q.z1 - 3.4, PAL.slabJoint)
		end
	end
	-- rails du portique : longrine béton, champignon d'acier
	for _, r in q.rails do
		blk(parent, q.x0, r.x1, Q, Q + 0.12, r.z - 2.5, r.z + 2.5, PAL.coping, M.Concrete)
		blk(parent, q.x0, r.x1, Q + 0.12, Q + 0.6, r.z - 0.4, r.z + 0.4, PAL.steel, M.Metal)
	end
	-- défenses côté mer (faces verticales du quai au-dessus de l'eau)
	local sea = ctx.sea
	for x = q.x0 + 8, q.x1 - 4, 16 do
		blk(parent, x - 1, x + 1, sea + 1.5, Q - 0.5, q.z0 - 1.4, q.z0, PAL.rubber)
		blk(parent, x - 1, x + 1, sea + 1.5, Q - 0.5, q.z1, q.z1 + 1.4, PAL.rubber)
	end
	for _, zr in { { q.z0, q.crestN }, { q.crestS, q.z1 } } do
		for z = zr[1] + 8, zr[2] - 4, 16 do
			blk(parent, q.x1, q.x1 + 1.4, sea + 1.5, Q - 0.5, z - 1, z + 1, PAL.rubber)
		end
	end
end

-- Cette méthode permet d'habiller le bateau-porte : raidisseurs, lisses et bandeau bleu côté forme (entre les pieds
-- des flancs) et côté mer, liserés et bittes sur le dessus.
local function caissonGate(parent, gt)
	local inner = faceFrame(V3.new(gt.x0, 0, gt.z0), V3.new(0, 0, 1), V3.new(-1, 0, 0))
	local ua, ub = gt.freeZ0 - gt.z0, gt.freeZ1 - gt.z0
	for _, z in gt.stiffeners do
		local u = z - gt.z0
		box(parent, inner, u - 0.4, u + 0.4, 0.5, 50, 0, 0.6, PAL.steel, M.Metal)
	end
	for _, v in { 15, 30, 45 } do
		box(parent, inner, ua, ub, v - 0.6, v + 0.6, 0, 0.8, PAL.steel, M.Metal)
	end
	box(parent, inner, ua, ub, 50, Q, 0, 0.15, PAL.blue)
	box(parent, inner, ua, ub, 48.4, 49.1, 0, 0.15, PAL.white)
	local outer = faceFrame(V3.new(gt.x1, 0, gt.z1), V3.new(0, 0, -1), V3.new(1, 0, 0))
	local len = gt.z1 - gt.z0
	box(parent, outer, 0, len, 50, Q, 0, 0.15, PAL.blue)
	box(parent, outer, 0, len, 48.4, 49.1, 0, 0.15, PAL.white)
	for u = 8, len - 4, 10 do
		box(parent, outer, u - 0.4, u + 0.4, ctx.sea, 48.4, 0, 0.6, PAL.steel, M.Metal)
	end
	digits(parent, outer, len / 2 - 3, 51.2, 7, "1", PAL.white, 0.2)
	blk(parent, gt.x0 + 0.4, gt.x0 + 0.8, Q, Q + 0.1, gt.z0, gt.z1, PAL.yellow)
	blk(parent, gt.x1 - 0.8, gt.x1 - 0.4, Q, Q + 0.1, gt.z0, gt.z1, PAL.yellow)
	for _, z in { gt.z0 + 4, gt.z1 - 4 } do
		bollard(parent, (gt.x0 + gt.x1) / 2, z)
	end
end

-- Forme ---------------------------------------------------------------------------------------------------------------

-- Cette méthode permet d'équiper le fond de la forme : tins de bouchain (béton et bois, porteurs) sous les tronçons,
-- caniveaux le long des pieds de flancs, taquets antidérapants de la rampe d'accès.
local function dockFloor(parent, d)
	for _, s in d.sections do
		for x = s[1] + 10, s[2] - 8, 28 do
			for _, z in { 211, 243 } do
				blk(parent, x, x + 5, 0, 7, z, z + 6, PAL.concrete, M.Concrete, true)
				blk(parent, x, x + 5, 7, 10, z + 0.5, z + 5.5, PAL.wood, M.WoodPlanks, true)
			end
		end
	end
	for _, z in { d.toeN + 2, d.toeS - 4 } do
		blk(parent, d.x0 + 16, d.x1 - 2, 0, 0.08, z, z + 2, PAL.steel, M.Metal)
	end
	-- taquets jaunes sur la rampe d'accès (pente le long de Z, du quai au fond)
	local r = d.ramp
	local run, rise = r.z1 - r.z0, Q
	local n = V3.new(0, run, rise).Unit
	local len = math.sqrt(run * run + rise * rise)
	for s = 3, len - 2, 4 do
		local t = s / len
		local pos = V3.new((r.x0 + r.x1) / 2, Q - rise * t, r.z0 + run * t) + n * 0.08
		part(parent, CF.fromMatrix(pos, V3.new(1, 0, 0), n), V3.new(r.x1 - r.x0 - 1, 0.16, 0.5), PAL.yellow)
	end
end

-- Fond de décor ---------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser le fond de décor (sans collision ni ombre) : rive d'en face avec portiques à
-- conteneurs, piles de conteneurs, entrepôts aux fenêtres allumées, cheminée rayée, cuves ; digue et phare au nord.
local function scenery(parent)
	local ground = PAL.plinth:Lerp(PAL.black, 0.35)
	blk(parent, 1100, 1700, 0, 48, -700, 900, ground, M.Concrete)
	-- portiques à conteneurs : pieds, poutre, flèche relevée, chevalet et haubans
	for _, z in { -260, -60, 140, 340 } do
		for _, x in { 1130, 1165 } do
			for _, dz in { -14, 14 } do
				blk(parent, x - 1.5, x + 1.5, 48, 150, z + dz - 1.5, z + dz + 1.5, PAL.blue)
			end
		end
		blk(parent, 1060, 1230, 146, 154, z - 15, z + 15, PAL.white)
		blk(parent, 1126, 1169, 92, 96, z - 15, z + 15, PAL.blue)
		cyl(parent, ORIGIN, V3.new(1148, 154, z), V3.new(1148, 196, z), 3, PAL.blue)
		cyl(parent, ORIGIN, V3.new(1148, 196, z), V3.new(1062, 154, z), 0.8, PAL.galva)
		cyl(parent, ORIGIN, V3.new(1148, 196, z), V3.new(1228, 154, z), 0.8, PAL.galva)
		blk(parent, 1142, 1156, 154, 162, z - 6, z + 6, PAL.white)
		blk(parent, 1062, 1064, 150, 151.5, z - 15, z + 15, PAL.red, M.Neon)
	end
	-- piles de conteneurs (couleurs fixes, hauteurs variées)
	local colors = { PAL.red, PAL.blue, PAL.orange, C3.fromRGB(80, 120, 80), PAL.white, PAL.navy }
	local i = 0
	for z = -380, 520, 60 do
		for x = 1200, 1320, 40 do
			i += 1
			local h = 10 + (i * 7 % 4) * 9
			blk(parent, x, x + 30, 48, 48 + h, z, z + 48, colors[i % #colors + 1])
		end
	end
	-- entrepôts, bandes de fenêtres éclairées côté forme
	for k, w in { { -620, -420, 34 }, { 560, 760, 28 }, { 780, 880, 44 } } do
		blk(parent, 1380, 1560, 48, 48 + w[3], w[1], w[2], C3.fromRGB(150, 150, 146))
		blk(parent, 1379.5, 1380, 48 + w[3] * 0.55, 48 + w[3] * 0.55 + 3, w[1] + 10, w[2] - 10, PAL.lit, M.Neon)
		if k ~= 2 then
			blk(parent, 1379.5, 1380, 48 + w[3] * 0.25, 48 + w[3] * 0.25 + 3, w[1] + 30, w[2] - 40, PAL.lit, M.Neon)
		end
	end
	-- cheminée rayée rouge et blanc, feu au sommet ; cuves
	for b = 0, 7 do
		local c = if b % 2 == 0 then PAL.red else PAL.white
		cyl(parent, ORIGIN, V3.new(1500, 48 + b * 24, 640), V3.new(1500, 72 + b * 24, 640), 14 - b * 0.6, c)
	end
	blk(parent, 1498, 1502, 240, 242, 638, 642, PAL.red, M.Neon)
	for _, t in { { 1450, -540 }, { 1490, -500 }, { 1440, -470 } } do
		cyl(parent, ORIGIN, V3.new(t[1], 48, t[2]), V3.new(t[1], 80, t[2]), 34, PAL.white)
	end
	-- digue et phare au nord
	blk(parent, 560, 1000, 30, 46, -440, -410, ground, M.Concrete)
	cyl(parent, ORIGIN, V3.new(760, 46, -425), V3.new(760, 96, -425), 10, PAL.white)
	cyl(parent, ORIGIN, V3.new(760, 70, -425), V3.new(760, 78, -425), 10.3, PAL.red)
	cyl(parent, ORIGIN, V3.new(760, 96, -425), V3.new(760, 102, -425), 7, PAL.lamp, M.Neon)
	cyl(parent, ORIGIN, V3.new(760, 102, -425), V3.new(760, 104.5, -425), 8.5, PAL.red)
end

-- Assemblage -----------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser tout l'habillage dans le dossier `Dressing` de la map. `c` donne la pose (place), les
-- cotes (quay, deck, sea, wall) et les objets de la maquette à habiller (halls, hangar, sections, portique, conteneurs,
-- piles de tôles, bittes, forme, quais, bateau-porte) ; renvoie le dossier.
function RadoubDressing.build(c)
	ctx = c
	Q = c.quay
	local root = New("Folder")
	root.Name = "Dressing"
	root.Parent = c.map
	-- Cette méthode permet de créer un sous-dossier de l'habillage.
	local function sub(name)
		local f = New("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	local fac, ins = sub("Facades"), sub("Interiors")
	for i, h in c.halls do
		local faces = hallFaces(h)
		local roofTop = Q + h.h + 1.5
		if h.style == "atelier" then
			for name, face in faces do
				local wins = cladFacade(fac, face, h.h, {
					pitch = 11,
					band = 9,
					windows = if name == "N" or name == "S" then { 20, 27 } else nil,
					seed = i,
				})
				for _, r in wins do
					innerWindow(ins, face, r)
				end
				innerDado(ins, face, 1.4, PAL.steel)
			end
			digits(fac, faces.S.frame, 12, 30, 7, h.number, PAL.white, 0.2)
			parapet(fac, h, roofTop, 1.4, PAL.steel)
			skylights(fac, h, roofTop)
			roofUnit(fac, h.x0 + 18, h.z0 + 14, roofTop)
			atelierInside(ins, h)
		elseif h.style == "magasin" then
			for name, face in faces do
				local wins = precastFacade(fac, face, h.h, { seed = i, number = if name == "N" then h.number else nil })
				for _, r in wins do
					innerWindow(ins, face, r)
				end
				innerDado(ins, face, 1.4, PAL.blue)
			end
			parapet(fac, h, roofTop, 1.4, PAL.steel)
			for _, t in { 0.3, 0.6 } do
				roofUnit(fac, h.x0 + (h.x1 - h.x0) * t, h.z0 + 20, roofTop)
			end
			storeInside(ins, h)
		elseif h.style == "pompes" then
			for _, face in faces do
				for _, r in brickFacade(fac, face, h.h) do
					innerWindow(ins, face, r)
				end
				innerDado(ins, face, 3, PAL.stone)
			end
			parapet(fac, h, roofTop, 1.3, PAL.stone)
			pumpInside(ins, h)
			-- cheminée de briques : socle et cordons de pierre, couronnement
			local ch = h.chimney
			blk(fac, ch.x - 3.4, ch.x + 3.4, roofTop, roofTop + 2, ch.z - 3.4, ch.z + 3.4, PAL.stone, nil, true)
			blk(fac, ch.x - 2.6, ch.x + 2.6, roofTop + 2, ch.top, ch.z - 2.6, ch.z + 2.6, PAL.brick, nil, true)
			for _, y in { roofTop + 13, ch.top - 4 } do
				blk(fac, ch.x - 2.8, ch.x + 2.8, y, y + 0.8, ch.z - 2.8, ch.z + 2.8, PAL.stone)
			end
			blk(fac, ch.x - 3.2, ch.x + 3.2, ch.top, ch.top + 1.2, ch.z - 3.2, ch.z + 3.2, PAL.stone, nil, true)
			blk(fac, ch.x - 2, ch.x + 2, ch.top + 1.2, ch.top + 1.5, ch.z - 2, ch.z + 2, PAL.black)
		else
			for _, face in faces do
				for _, r in cladFacade(fac, face, h.h, { pitch = 8, band = 3.5, windows = { 6.5, 10.5 }, seed = i }) do
					innerWindow(ins, face, r)
				end
			end
			parapet(fac, h, roofTop, 1.2, PAL.steel)
			post(fac, h.x0 + 6, h.z0 + 6, roofTop, roofTop + 12, 0.5, PAL.galva, M.Metal)
			highBay(ins, (h.x0 + h.x1) / 2, (h.z0 + h.z1) / 2, Q + h.h - 2)
		end
	end
	hangar(fac, c.hangar)

	local ship = sub("Ship")
	for i, s in c.sections do
		hullSides(ship, s, i, c.draftMarks[i] or {})
	end
	for _, oe in c.openEnds do
		openEnd(ship, oe[1], oe[2])
	end
	superstructure(ship)
	deckGear(ship, c.hatches)
	sternGear(ship)
	scaffold(ship, faceFrame(V3.new(200, 0, 255), V3.new(0, 0, -1), V3.new(1, 0, 0)), 4, 46, 42, 3)
	scaffold(ship, faceFrame(V3.new(330, 0, 205), V3.new(0, 0, 1), V3.new(-1, 0, 0)), 4, 46, 42, 3)

	local dock = sub("Dock")
	dockFloor(dock, c.dock)
	caissonGate(dock, c.gate)

	gantry(sub("Gantry"), c.gantry)

	local quay = sub("Quays")
	quays(quay, c.quays)
	for _, b in c.bollards do
		bollard(quay, b[1], b[2])
	end
	for _, m in c.masts do
		lampMast(quay, m[1], m[2], c.mastTarget)
	end
	for _, ct in c.containers do
		container(quay, ct)
	end
	for _, t in c.plates do
		plateStack(quay, t)
	end
	cableReel(quay, 264, 97, 6, 3)
	cableReel(quay, 267, 103.5, 5, 2.6)
	siteCabin(quay, -58.9, -34.9, 56, 72)
	palletLoad(quay, 27, 86, Q, 3.2, PAL.cardboard)
	palletLoad(quay, 27, 90, Q, 2.4, PAL.wood)
	palletLoad(quay, 27, 376, Q, 3.2, PAL.white)
	beamStack(quay, 214, 246, 360, 2)
	gasRack(quay, faceFrame(V3.new(440, Q, 110), V3.new(0, 0, -1), V3.new(1, 0, 0)), 26)

	local far = sub("Scenery")
	scenery(far)
	return root
end

return RadoubDressing

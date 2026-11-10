--!nocheck
-- Habillage détaillé de Dizzy, posé par build_dizzy.luau après le plan relevé et les retouches : objets construits
-- pièce par pièce là où le relevé ne donne qu'une boîte ou un trou (groupes de climatisation, extracteurs d'air des
-- estrades, auvents et câbles des
-- portes de garage, fenêtres et lampes des murs du milieu ; grue, bardage en tôle ondulée, double porte, groupes du
-- toit du garage, zone de stockage du lot #166 ; fûts, parpaings, contreplaqué et baladeuses de la fosse centrale,
-- charge de la grue et clôtures grillagées du lot #187). Coordonnées du plan relevé (sans le décalage de la map,
-- ajouté par `build`). La map est symétrique par rotation d'un demi-tour autour de (0, -260,1) : chaque objet est
-- décrit une fois côté T et recopié côté CT par `mirror`. Cf. docs/maps.md, « Habillage détaillé ».
--
-- Règle de collision : seuls les volumes porteurs (caisson et châssis des groupes, carénages des ventilateurs) gardent
-- la collision ; tout le reste est sans collision ni requête (le mouvement détecte les murs par raycast).

local roblox = if Vector3 then nil else require("@lune/roblox")
local V3 = if roblox then roblox.Vector3 else Vector3
local CF = if roblox then roblox.CFrame else CFrame
local C3 = if roblox then roblox.Color3 else Color3
local E = if roblox then roblox.Enum else Enum
local New = if roblox then roblox.Instance.new else Instance.new

local DizzyDressing = {}

-- centre de la symétrie de la map (plan relevé)
DizzyDressing.CENTER_Z = -260.1

local PAINT = C3.fromRGB(190, 192, 186) -- tôle peinte des groupes
local TRIM = C3.fromRGB(70, 74, 82) -- acier sombre (châssis, cadres, auvents)
local GRILLE = C3.fromRGB(38, 40, 44)
local GALVA = C3.fromRGB(150, 154, 158) -- conduits électriques
local COPPER = C3.fromRGB(176, 106, 62)
local INSUL = C3.fromRGB(30, 30, 32) -- isolant des tuyaux frigorifiques
local HAZARD = C3.fromRGB(224, 170, 40)
local GLASS = C3.fromRGB(70, 92, 112)
local ROOM = C3.fromRGB(34, 36, 44) -- pièce sombre derrière les vitres
local LAMP = C3.fromRGB(255, 196, 140)

-- Cette méthode permet de recopier un repère côté CT lorsqu'un objet est décrit côté T (demi-tour autour de l'axe
-- vertical passant par le centre de la map).
function DizzyDressing.mirror(cf)
	local c = CF.new(0, 0, DizzyDressing.CENTER_Z)
	return c * CF.Angles(0, math.pi, 0) * c:Inverse() * cf
end

-- Cette méthode permet de bâtir un repère en `pos` dont -Z (LookVector) suit `look`, Y restant au plus près de la
-- verticale. Remplace CFrame.lookAt, faux sous Lune (repère retourné vers +Z, invalide à la verticale).
function DizzyDressing.aim(pos, look)
	local z = -look.Unit
	local up = if math.abs(z.Y) > 0.99 then V3.new(1, 0, 0) else V3.new(0, 1, 0)
	local x = up:Cross(z).Unit
	return CF.fromMatrix(pos, x, z:Cross(x), z)
end

-- Cette méthode permet de poser une pièce ancrée dans le repère `frame` (position et taille locales) ; `solid` garde
-- la collision, sinon la pièce est purement décorative (ni collision ni requête).
local function piece(parent, frame, pos, size, color, material, solid, kind)
	local p = New(kind or "Part")
	p.Anchored = true
	p.CanTouch = false
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.TopSurface = E.SurfaceType.Smooth
	p.BottomSurface = E.SurfaceType.Smooth
	p.Size = size
	p.CFrame = frame * (if typeof(pos) == "CFrame" then pos else CF.new(pos))
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- Cette méthode permet de poser un cylindre (tuyau, carénage) entre deux points locaux du repère `frame`.
local function tube(parent, frame, a, b, diameter, color, material, solid)
	local length = (b - a).Magnitude
	-- l'axe d'un cylindre Roblox est son X local
	local cf = DizzyDressing.aim((a + b) / 2, b - a) * CF.Angles(0, math.pi / 2, 0)
	local p = piece(parent, frame, cf, V3.new(length, diameter, diameter), color, material, solid)
	p.Shape = E.PartType.Cylinder
	return p
end

-- Cette méthode permet de poser un disque vertical (cylindre couché sur l'axe Y local) de centre `pos`.
local function disc(parent, frame, pos, diameter, height, color, material, solid)
	local p = piece(
		parent,
		frame,
		CF.new(pos) * CF.Angles(0, 0, math.pi / 2),
		V3.new(height, diameter, diameter),
		color,
		material,
		solid
	)
	p.Shape = E.PartType.Cylinder
	return p
end

-- Cette méthode permet de tirer un tuyau coudé le long d'une suite de points locaux, avec une rotule à chaque coude.
local function run(parent, frame, points, diameter, color, material)
	for i = 1, #points - 1 do
		tube(parent, frame, points[i], points[i + 1], diameter, color, material)
		if i > 1 then
			local b = piece(parent, frame, points[i], V3.new(diameter, diameter, diameter), color, material)
			b.Shape = E.PartType.Ball
		end
	end
end

-- Cette méthode permet d'ajouter une lampe murale (potence, abat-jour, ampoule et SpotLight vers le bas) dont `pos` est
-- le point de fixation au mur ; le mur est derrière (+Z local), la lampe avance vers -Z.
local function wallLamp(parent, frame, pos, reach)
	local model = New("Model")
	model.Name = "Lamp"
	model.Parent = parent
	piece(model, frame, pos, V3.new(1.2, 1.6, 0.3), TRIM, E.Material.Metal)
	tube(model, frame, pos + V3.new(0, 0.3, -0.1), pos + V3.new(0, 0.3, -reach), 0.3, TRIM, E.Material.Metal)
	local head = pos + V3.new(0, -0.1, -reach)
	piece(model, frame, head + V3.new(0, 0.25, 0), V3.new(1.8, 0.35, 1.8), TRIM, E.Material.Metal)
	piece(model, frame, head + V3.new(0, -0.05, 0), V3.new(1.4, 0.3, 1.4), TRIM, E.Material.Metal)
	local bulb = piece(model, frame, head + V3.new(0, -0.3, 0), V3.new(1.0, 0.25, 1.0), LAMP, E.Material.Neon)
	local light = New("SpotLight")
	light.Face = E.NormalId.Bottom
	light.Angle = 100
	light.Range = 34
	light.Brightness = 2.2
	light.Color = LAMP
	light.Shadows = false
	light.Parent = bulb
	return model
end

-- Cette méthode permet de construire un groupe de climatisation de toiture dans `frame` (origine au sol, au centre de
-- l'emprise, -Z local tourné vers l'intérieur de la map) : châssis sur longerons, caisson à montants, portes de
-- visite, grille d'aspiration, deux ventilateurs carénés, coffret électrique et tuyaux frigorifiques.
local function hvac(parent, frame)
	local m = New("Model")
	m.Name = "AirHandler"
	m.Parent = parent
	local L, D, H0, H1 = 36.6, 16.3, 2.85, 13.7 -- longueur, profondeur, haut du châssis, haut du caisson
	-- châssis : deux longerons en I et des traverses (porteurs)
	for _, z in { -7.4, 7.4 } do
		piece(m, frame, V3.new(0, 0.3, z), V3.new(38.1, 0.6, 2.4), TRIM, E.Material.Metal, true)
		piece(m, frame, V3.new(0, 1.425, z), V3.new(38.1, 1.65, 0.5), TRIM, E.Material.Metal, true)
		piece(m, frame, V3.new(0, 2.55, z), V3.new(38.1, 0.6, 2.4), TRIM, E.Material.Metal, true)
	end
	for _, x in { -17, -8.5, 0, 8.5, 17 } do
		piece(m, frame, V3.new(x, 2.55, 0), V3.new(1.2, 0.6, 12.4), TRIM, E.Material.Metal)
	end
	-- caisson (porteur), coins abattus par des montants sombres
	local midY = (H0 + H1) / 2
	local h = H1 - H0
	piece(m, frame, V3.new(0, midY, 0), V3.new(L, h, D), PAINT, E.Material.Metal, true)
	for _, x in { -L / 2, L / 2 } do
		for _, z in { -D / 2, D / 2 } do
			piece(m, frame, V3.new(x, midY, z), V3.new(0.8, h + 0.1, 0.8), TRIM, E.Material.Metal)
		end
	end
	-- corniche : arêtes du toit chanfreinées
	for _, s in { -1, 1 } do
		piece(
			m,
			frame,
			CF.new(0, H1 + 0.35, s * (D / 2 - 0.35)) * CF.Angles(0, if s > 0 then math.pi else 0, 0),
			V3.new(L + 0.4, 0.7, 0.7),
			PAINT,
			E.Material.Metal,
			false,
			"WedgePart"
		)
	end
	piece(m, frame, V3.new(0, H1 + 0.35, 0), V3.new(L + 0.4, 0.7, D - 1.4), PAINT, E.Material.Metal, true)
	local roof = H1 + 0.7
	-- dos : raidisseurs verticaux (tôle nervurée)
	for i = -5, 5 do
		piece(m, frame, V3.new(i * 3.1, midY, D / 2 + 0.12), V3.new(0.35, h - 1, 0.25), PAINT, E.Material.Metal)
	end
	-- façade : trois portes de visite (cadre, poignée, ouïes) et une plaque signalétique
	for i, x in { -11.6, 0, 11.6 } do
		local f = -D / 2 - 0.1
		piece(m, frame, V3.new(x, midY, f), V3.new(10, h - 1.6, 0.12), C3.fromRGB(176, 178, 172), E.Material.Metal)
		for _, e in { { 0, h / 2 - 0.85, 10, 0.25 }, { 0, -(h / 2 - 0.85), 10, 0.25 } } do
			piece(m, frame, V3.new(x + e[1], midY + e[2], f - 0.08), V3.new(e[3], e[4], 0.1), TRIM, E.Material.Metal)
		end
		for _, dx in { -4.9, 4.9 } do
			piece(m, frame, V3.new(x + dx, midY, f - 0.08), V3.new(0.25, h - 1.6, 0.1), TRIM, E.Material.Metal)
		end
		piece(m, frame, V3.new(x + 3.8, midY, f - 0.3), V3.new(0.3, 1.6, 0.35), TRIM, E.Material.Metal)
		if i ~= 2 then
			for k = 0, 4 do
				piece(
					m,
					frame,
					CF.new(x - 1, H0 + 1.6 + k * 0.7, f - 0.15) * CF.Angles(math.rad(-35), 0, 0),
					V3.new(6, 0.15, 0.5),
					GRILLE,
					E.Material.Metal
				)
			end
		end
	end
	piece(m, frame, V3.new(-11.6, H1 - 2, -D / 2 - 0.2), V3.new(2.6, 0.9, 0.08), HAZARD, E.Material.SmoothPlastic)
	-- bout +X : grille d'aspiration à lames inclinées sur fond sombre
	piece(m, frame, V3.new(L / 2 + 0.05, midY, 0), V3.new(0.1, h - 1.6, D - 2.4), GRILLE, E.Material.Metal)
	for k = 0, 11 do
		piece(
			m,
			frame,
			CF.new(L / 2 + 0.25, H0 + 1.3 + k * 0.78, 0) * CF.Angles(0, 0, math.rad(40)),
			V3.new(0.6, 0.12, D - 2.6),
			TRIM,
			E.Material.Metal
		)
	end
	-- bout -X : coffret électrique et son conduit qui plonge dans la dalle
	local box = V3.new(-L / 2 - 1.1, H0 + 5.5, -3)
	piece(m, frame, box, V3.new(1.6, 5, 4.2), C3.fromRGB(150, 152, 150), E.Material.Metal)
	piece(m, frame, box + V3.new(-0.85, 1.4, 0), V3.new(0.06, 0.9, 1.4), HAZARD, E.Material.SmoothPlastic)
	run(m, frame, {
		box + V3.new(0, -2.5, 1),
		V3.new(box.X, 1.2, box.Z + 1),
		V3.new(box.X - 2.5, 1.2, box.Z + 1),
		V3.new(box.X - 2.5, -0.3, box.Z + 1),
	}, 0.45, GALVA, E.Material.Metal)
	-- tuyaux frigorifiques (cuivre et isolé) sortant de la façade jusqu'à une crosse au sol
	for j, dz in { 0, 1.1 } do
		local x0 = 14 + dz
		run(m, frame, {
			V3.new(x0, H0 + 2.2 - j * 0.4, -D / 2),
			V3.new(x0, H0 + 2.2 - j * 0.4, -D / 2 - 1.6 - j * 0.6),
			V3.new(x0, 0.6, -D / 2 - 1.6 - j * 0.6),
			V3.new(x0 + 6, 0.6, -D / 2 - 1.6 - j * 0.6),
		}, if j == 1 then 0.5 else 0.7, if j == 1 then COPPER else INSUL, E.Material.Metal)
	end
	piece(m, frame, V3.new(20.6, 0.9, -D / 2 - 2), V3.new(1.6, 1.8, 2.6), TRIM, E.Material.Metal)
	-- deux ventilateurs carénés sur le toit : virole (porteuse), fond sombre, moyeu, pales et grille en croix
	for _, x in { -9.2, 9.2 } do
		local c = V3.new(x, roof, 0)
		disc(m, frame, c + V3.new(0, 1.1, 0), 12.6, 2.2, PAINT, E.Material.Metal, true)
		disc(m, frame, c + V3.new(0, 2.25, 0), 13.2, 0.3, TRIM, E.Material.Metal)
		disc(m, frame, c + V3.new(0, 2.3, 0), 11.4, 0.2, GRILLE, E.Material.Metal)
		disc(m, frame, c + V3.new(0, 2.5, 0), 2.2, 0.5, TRIM, E.Material.Metal)
		for k = 0, 2 do
			piece(
				m,
				frame,
				CF.new(c + V3.new(0, 2.45, 0))
					* CF.Angles(0, k * 2 * math.pi / 3, 0)
					* CF.new(2.8, 0, 0)
					* CF.Angles(math.rad(25), 0, 0),
				V3.new(4.6, 0.12, 1.6),
				C3.fromRGB(110, 114, 118),
				E.Material.Metal
			)
		end
		for k = -2, 2 do
			local w = math.sqrt(math.max(0, 5.6 ^ 2 - (k * 2.2) ^ 2)) * 2
			piece(m, frame, c + V3.new(k * 2.2, 2.65, 0), V3.new(0.12, 0.12, w), TRIM, E.Material.Metal)
		end
		piece(m, frame, c + V3.new(0, 2.7, 0), V3.new(11.2, 0.15, 0.15), TRIM, E.Material.Metal)
	end
	return m
end

-- Cette méthode permet de construire l'auvent d'une porte de garage et les câbles qui courent sur sa façade, dans
-- `frame` (origine au milieu du haut de l'ouverture, sur le nu du mur ; -Z local vers l'extérieur, X le long du mur).
local function garage(parent, frame, width)
	local m = New("Model")
	m.Name = "GarageCanopy"
	m.Parent = parent
	local w = width + 6
	local depth = 8
	local y = 3
	-- tôle de l'auvent, légèrement inclinée vers l'avant, lisse contre le mur et rive en U à l'avant
	local tilt = math.rad(4)
	local plate = CF.new(0, y, -depth / 2) * CF.Angles(-tilt, 0, 0)
	piece(m, frame, plate, V3.new(w, 0.35, depth), TRIM, E.Material.Metal)
	piece(m, frame, V3.new(0, y - 0.2, -0.3), V3.new(w, 1, 0.6), TRIM, E.Material.Metal)
	local front = V3.new(0, y - math.sin(tilt) * depth / 2 * 2, -depth)
	piece(m, frame, front + V3.new(0, -0.2, 0), V3.new(w + 0.3, 1.3, 0.3), TRIM, E.Material.Metal)
	for _, s in { -1, 1 } do
		piece(
			m,
			frame,
			CF.new(s * w / 2, y - 0.4, -depth / 2) * CF.Angles(-tilt, 0, 0),
			V3.new(0.3, 1.1, depth),
			TRIM,
			E.Material.Metal
		)
	end
	-- nervures sous la tôle
	for k = -3, 3 do
		piece(
			m,
			frame,
			CF.new(k * w / 7, y - 0.45, -depth / 2) * CF.Angles(-tilt, 0, 0),
			V3.new(0.35, 0.55, depth - 0.4),
			TRIM,
			E.Material.Metal
		)
	end
	-- tirants vers le mur, avec platines
	for _, x in { -w / 2 + 3, 0, w / 2 - 3 } do
		tube(m, frame, V3.new(x, y + 0.1, -depth + 0.4), V3.new(x, y + 8, -0.2), 0.3, TRIM, E.Material.Metal)
		piece(m, frame, V3.new(x, y + 8, -0.1), V3.new(1.3, 1.3, 0.2), TRIM, E.Material.Metal)
	end
	-- deux lampes sous l'auvent
	for _, x in { -width / 4, width / 4 } do
		local bulb = piece(m, frame, V3.new(x, y - 0.95, -depth / 2), V3.new(3, 0.3, 0.8), LAMP, E.Material.Neon)
		piece(m, frame, V3.new(x, y - 0.7, -depth / 2), V3.new(3.4, 0.25, 1.2), TRIM, E.Material.Metal)
		local light = New("SpotLight")
		light.Face = E.NormalId.Bottom
		light.Angle = 110
		light.Range = 30
		light.Brightness = 1.8
		light.Color = LAMP
		light.Shadows = false
		light.Parent = bulb
	end
	-- câbles : deux conduits galvanisés et un câble noir sur la façade, du coffret au-dessus de l'auvent jusqu'à une
	-- descente vers le sol, colliers tous les 6 studs
	local off = -0.45
	local xL, xR = -width / 2 - 14, width / 2 - 2
	local top = y + 17
	local cables = {
		{ 0, 0.45, GALVA },
		{ 0.9, 0.45, GALVA },
		{ 1.8, 0.3, INSUL },
	}
	for _, c in cables do
		local dy, d, color = c[1], c[2], c[3]
		run(m, frame, {
			V3.new(xR + dy, y + 2.6, off),
			V3.new(xR + dy, top - dy, off),
			V3.new(xL - dy, top - dy, off),
			V3.new(xL - dy, -18.9, off),
		}, d, color, E.Material.Metal)
	end
	for x = xL + 3, xR - 3, 6 do
		piece(m, frame, V3.new(x, top - 0.9, -0.25), V3.new(0.35, 2.6, 0.5), TRIM, E.Material.Metal)
	end
	for yy = -15, top - 3, 6 do
		piece(m, frame, V3.new(xL - 0.9, yy, -0.25), V3.new(2.6, 0.35, 0.5), TRIM, E.Material.Metal)
	end
	piece(m, frame, V3.new(xR + 0.9, y + 2.6, -0.5), V3.new(3.4, 2.2, 0.9), C3.fromRGB(150, 152, 150), E.Material.Metal)
	piece(
		m,
		frame,
		V3.new(xL - 0.9, top - 0.9, -0.5),
		V3.new(3.4, 3.4, 0.9),
		C3.fromRGB(150, 152, 150),
		E.Material.Metal
	)
	piece(m, frame, V3.new(xL - 0.9, -17.6, -0.5), V3.new(3, 2.4, 0.9), C3.fromRGB(150, 152, 150), E.Material.Metal)
	return m
end

-- Cette méthode permet de construire un extracteur d'air « champignon » dans `frame` (origine au pied, sur l'estrade) :
-- platine, fût cerclé (porteur), bande d'aspiration à lames, chapeau en dôme (porteur), gaine et coffret au pied.
local function vent(parent, frame)
	local m = New("Model")
	m.Name = "RoofVent"
	m.Parent = parent
	disc(m, frame, V3.new(0, 0.3, 0), 14.6, 0.6, TRIM, E.Material.Metal)
	for k = 0, 7 do
		local a = k * math.pi / 4
		piece(
			m,
			frame,
			V3.new(math.cos(a) * 6.6, 0.7, math.sin(a) * 6.6),
			V3.new(0.5, 0.25, 0.5),
			GRILLE,
			E.Material.Metal
		)
	end
	disc(m, frame, V3.new(0, 1.4, 0), 12.6, 1.6, TRIM, E.Material.Metal, true)
	disc(m, frame, V3.new(0, 7.4, 0), 11.2, 10.4, PAINT, E.Material.Metal, true)
	for _, y in { 4.2, 8, 11.8 } do
		disc(m, frame, V3.new(0, y, 0), 11.7, 0.35, TRIM, E.Material.Metal)
	end
	-- bande d'aspiration : fond sombre et lames verticales tout autour
	disc(m, frame, V3.new(0, 13.6, 0), 10.2, 2.2, GRILLE, E.Material.Metal, true)
	for k = 0, 23 do
		local a = k * math.pi / 12
		piece(
			m,
			frame,
			CF.new(math.cos(a) * 5.3, 13.6, math.sin(a) * 5.3) * CF.Angles(0, -a + math.rad(30), 0),
			V3.new(0.12, 2.2, 1.1),
			TRIM,
			E.Material.Metal
		)
	end
	-- chapeau : jupe large puis dôme en gradins
	disc(m, frame, V3.new(0, 15.05, 0), 16.4, 0.7, PAINT, E.Material.Metal, true)
	disc(m, frame, V3.new(0, 14.6, 0), 16.6, 0.25, TRIM, E.Material.Metal)
	for i, d in { 14.2, 11.6, 8.6, 5.2 } do
		disc(m, frame, V3.new(0, 15.4 + i * 0.55, 0), d, 0.6, PAINT, E.Material.Metal, true)
	end
	disc(m, frame, V3.new(0, 18.1, 0), 2, 0.5, TRIM, E.Material.Metal)
	-- gaine électrique du moteur et coffret au pied
	run(m, frame, {
		V3.new(0, 11.2, -5.65),
		V3.new(0, 11.2, -6.6),
		V3.new(0, 1.6, -6.6),
		V3.new(2.2, 1.6, -6.6),
	}, 0.35, GALVA, E.Material.Metal)
	piece(m, frame, V3.new(3.4, 1.6, -6.6), V3.new(1.8, 2.2, 0.9), C3.fromRGB(150, 152, 150), E.Material.Metal)
	piece(m, frame, V3.new(0, 9.5, -5.62), V3.new(2.4, 0.8, 0.06), HAZARD, E.Material.SmoothPlastic)
	return m
end

-- Cette méthode permet de vitrer une baie du mur dans `frame` (origine au centre de l'ouverture sur le nu du mur, -Z
-- local vers l'extérieur) : pièce sombre au fond, vitre, cadre à meneaux, appui saillant.
local function window(parent, frame, width, height, depth)
	local m = New("Model")
	m.Name = "Window"
	m.Parent = parent
	piece(m, frame, V3.new(0, 0, depth - 0.15), V3.new(width, height, 0.1), ROOM, E.Material.SmoothPlastic)
	local glass =
		piece(m, frame, V3.new(0, 0, depth * 0.55), V3.new(width - 0.1, height - 0.1, 0.12), GLASS, E.Material.Glass)
	glass.Transparency = 0.35
	glass.Reflectance = 0.25
	local fz = depth * 0.55 - 0.15
	piece(m, frame, V3.new(0, height / 2 - 0.25, fz), V3.new(width, 0.5, 0.45), TRIM, E.Material.Metal)
	piece(m, frame, V3.new(0, -height / 2 + 0.25, fz), V3.new(width, 0.5, 0.45), TRIM, E.Material.Metal)
	for _, s in { -1, 1 } do
		piece(m, frame, V3.new(s * (width / 2 - 0.25), 0, fz), V3.new(0.5, height, 0.45), TRIM, E.Material.Metal)
	end
	for k = 1, 3 do
		piece(
			m,
			frame,
			V3.new(-width / 2 + k * width / 4, 0, fz),
			V3.new(0.3, height - 0.5, 0.35),
			TRIM,
			E.Material.Metal
		)
	end
	piece(m, frame, V3.new(0, height * 0.12, fz), V3.new(width - 0.5, 0.2, 0.3), TRIM, E.Material.Metal)
	piece(
		m,
		frame,
		V3.new(0, -height / 2 - 0.2, -0.3),
		V3.new(width + 1.2, 0.4, 1.4),
		C3.fromRGB(150, 140, 128),
		E.Material.Concrete
	)
	return m
end

-- Cette méthode permet de construire une échelle à crinoline fixée au mur dans `frame` (origine au pied, sur le nu du
-- mur ; -Z local vers l'extérieur) : rails, barreaux, pattes scellées, crosses qui passent par-dessus l'acrotère
-- (`parapet` : hauteur du dessus du mur, `roof` : sol derrière) et arceaux dont les côtés touchent le mur. Décor pur :
-- la grimpe passe par le volume de LADDERS.
local function ladder(parent, frame, top, parapet, roof)
	local m = New("Model")
	m.Name = "Ladder"
	m.Parent = parent
	local half, off = 3.05, -1.02 -- demi-largeur entre rails, écart au mur
	for _, x in { -half, half } do
		piece(m, frame, V3.new(x, top / 2, off), V3.new(0.5, top, 0.5), TRIM, E.Material.Metal)
		piece(m, frame, V3.new(x, 0.75, off), V3.new(0.76, 1.5, 0.76), TRIM, E.Material.Metal)
		-- pattes scellées au mur
		for _, y in { 1.8, 11.8, 21.8, 30.8 } do
			piece(m, frame, V3.new(x, y, off / 2), V3.new(0.35, 0.6, -off), TRIM, E.Material.Metal)
			-- platines posées sur les nervures du bardage (0,3 stud devant le nu du mur)
			piece(m, frame, V3.new(x, y, -0.38), V3.new(1.2, 1.4, 0.16), TRIM, E.Material.Metal)
		end
		-- crosse : le rail passe au-dessus de l'acrotère et redescend sur le toit
		run(m, frame, {
			V3.new(x, top, off),
			V3.new(x, top, 2.6),
			V3.new(x, roof, 2.6),
		}, 0.5, TRIM, E.Material.Metal)
		piece(m, frame, V3.new(x, roof + 0.08, 2.6), V3.new(1.2, 0.16, 1.2), TRIM, E.Material.Metal)
	end
	for y = 2.7, parapet - 0.5, 2.85 do
		tube(m, frame, V3.new(-half, y, off), V3.new(half, y, off), 0.36, TRIM, E.Material.Metal)
	end
	-- crinoline : arceaux en U (côtés droits scellés au mur, demi-cercle devant) et lisses verticales
	local W, straight, segments = 4.6, 3.6, 8
	local hoops = { 14, 20, 26, parapet - 1 }
	-- Cette méthode permet de placer un point du demi-cercle d'un arceau (angle 0 : côté +X, pi : côté -X).
	local function arc(a)
		return V3.new(W * math.cos(a), 0, -straight - W * math.sin(a))
	end
	for _, y in hoops do
		for _, s in { -1, 1 } do
			piece(m, frame, V3.new(s * W, y, -straight / 2), V3.new(0.25, 0.4, straight), TRIM, E.Material.Metal)
			piece(m, frame, V3.new(s * W, y, -0.38), V3.new(0.8, 1, 0.16), TRIM, E.Material.Metal)
		end
		for k = 0, segments - 1 do
			local a, b = arc(k * math.pi / segments), arc((k + 1) * math.pi / segments)
			local mid = (a + b) / 2 + V3.new(0, y, 0)
			local cf = DizzyDressing.aim(mid, b - a) * CF.Angles(0, math.pi / 2, 0)
			piece(m, frame, cf, V3.new((b - a).Magnitude + 0.1, 0.4, 0.25), TRIM, E.Material.Metal)
		end
	end
	local bars = { V3.new(-W, 0, -straight / 2), V3.new(W, 0, -straight / 2) }
	for k = 0, 4 do
		table.insert(bars, arc(k * math.pi / 4))
	end
	for _, b in bars do
		tube(m, frame, b + V3.new(0, hoops[1], 0), b + V3.new(0, hoops[#hoops], 0), 0.25, TRIM, E.Material.Metal)
	end
	return m
end

-- Cette méthode permet de poser le volume de grimpe d'une échelle (LadderRules) dans `frame` (même repère que
-- `ladder`) : boîte invisible devant le mur, du sol au-dessus de l'acrotère, LookVector = normale sortante.
local function ladderVolume(parent, frame, bottom, top)
	local p = New("Part")
	p.Name = "Ladder"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Size = V3.new(5, top - bottom, 2.5)
	p.CFrame = frame * CF.new(0, (bottom + top) / 2, -1.25)
	p.Parent = parent
	return p
end

-- Rhabillage d'objets relevés en boîtes (REDRESS) --------------------------------------------------------------------

local BURLAP = C3.fromRGB(156, 134, 98)
local CRATE = C3.fromRGB(168, 128, 82)
local BATTEN = C3.fromRGB(118, 86, 56)
local BLOCK = C3.fromRGB(150, 148, 142)
local SHEET = C3.fromRGB(214, 212, 204)

-- Cette méthode permet de varier une teinte sans hasard (même map à chaque génération) lorsque des objets répétés
-- (sacs, parpaings) ne doivent pas être tous identiques.
local function shade(color, k)
	local f = 1 + 0.06 * math.sin(k * 12.9898)
	return C3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
end

-- Cette méthode permet de ramener une boîte relevée (souvent posée de travers : axe vertical en Y, Z ou X local) à un
-- repère dont Y est vertical, et de donner sa taille dans ce repère.
local function upright(cf, size)
	local axes = { { cf.RightVector, size.X }, { cf.UpVector, size.Y }, { cf.LookVector, size.Z } }
	local best = 1
	for i, a in axes do
		if math.abs(a[1].Y) > math.abs(axes[best][1].Y) then
			best = i
		end
	end
	local others = {}
	for i, a in axes do
		if i ~= best then
			table.insert(others, a)
		end
	end
	local x = V3.new(others[1][1].X, 0, others[1][1].Z).Unit
	local y = V3.new(0, 1, 0)
	return CF.fromMatrix(cf.Position, x, y, x:Cross(y)), V3.new(others[1][2], axes[best][2], others[2][2])
end

-- Cette méthode permet de poser un sac de sable (corps, dessus bombé, bout cousu) de taille `size` dans `frame`.
local function sandbag(parent, frame, size, k)
	local base = frame * CF.Angles(0, math.rad(3 * math.sin(k * 7.1)), 0)
	local color = shade(BURLAP, k)
	piece(parent, base, V3.new(0, -size.Y * 0.12, 0), V3.new(size.X, size.Y * 0.76, size.Z), color, E.Material.Fabric)
	piece(
		parent,
		base,
		V3.new(0, size.Y * 0.26, 0),
		V3.new(size.X * 0.86, size.Y * 0.4, size.Z * 0.78),
		color,
		E.Material.Fabric
	)
	piece(
		parent,
		base,
		V3.new(size.X / 2 - 0.25, -size.Y * 0.05, 0),
		V3.new(0.5, size.Y * 0.62, size.Z * 0.6),
		shade(BURLAP, k + 3),
		E.Material.Fabric
	)
end

-- Cette méthode permet de remplir une boîte relevée de sacs de sable en rangs croisés (léger retrait à chaque rang) ;
-- une boîte basse devient un ou deux sacs couchés.
local function sandbags(parent, frame, size)
	local m = New("Model")
	m.Name = "Sandbags"
	m.Parent = parent
	local layers = math.max(1, math.floor(size.Y / 1.05 + 0.5))
	local h = size.Y / layers
	local k = 0
	for layer = 0, layers - 1 do
		local inset = if layers > 2 then layer * 0.18 else 0
		local lx, lz = size.X - 2 * inset, size.Z - 2 * inset
		-- rangs croisés : les sacs changent de sens d'un rang à l'autre
		local along = layer % 2 == 0
		local bagL, bagW = 5.6, 3.3
		local nx = math.max(1, math.floor((if along then lx / bagL else lx / bagW) + 0.35))
		local nz = math.max(1, math.floor((if along then lz / bagW else lz / bagL) + 0.35))
		local sx, sz = lx / nx, lz / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				k += 1
				local at = frame
					* CF.new(-lx / 2 + (i + 0.5) * sx, -size.Y / 2 + (layer + 0.5) * h, -lz / 2 + (j + 0.5) * sz)
				if along then
					sandbag(m, at, V3.new(sx * 0.96, h, sz * 0.94), k)
				else
					sandbag(m, at * CF.Angles(0, math.pi / 2, 0), V3.new(sz * 0.96, h, sx * 0.94), k)
				end
			end
		end
	end
	return m
end

-- Cette méthode permet de rhabiller une boîte relevée en caisse en bois : panneaux de planches, montants et traverses
-- sombres sur les arêtes, écharpe en diagonale sur les deux grandes faces.
local function crate(parent, frame, size)
	local m = New("Model")
	m.Name = "Crate"
	m.Parent = parent
	piece(m, frame, V3.zero, size - V3.new(0.1, 0.1, 0.1), CRATE, E.Material.WoodPlanks)
	local t = math.min(0.45, math.min(size.X, size.Y, size.Z) * 0.12)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local e = t / 2 - 0.05 -- retrait d'une baguette par rapport à l'arête
	for _, a in { -1, 1 } do
		for _, b in { -1, 1 } do
			piece(m, frame, V3.new(a * (hx - e), 0, b * (hz - e)), V3.new(t, size.Y, t), BATTEN, E.Material.Wood)
			piece(m, frame, V3.new(0, a * (hy - e), b * (hz - e)), V3.new(size.X, t, t), BATTEN, E.Material.Wood)
			piece(m, frame, V3.new(a * (hx - e), b * (hy - e), 0), V3.new(t, t, size.Z), BATTEN, E.Material.Wood)
		end
	end
	-- écharpes sur les deux faces les plus grandes
	local alongX = size.X >= size.Z
	local w = if alongX then size.X else size.Z
	local len = math.sqrt(w * w + size.Y * size.Y) - 2 * t
	local ang = math.atan2(size.Y, w)
	for _, s in { -1, 1 } do
		local cf = if alongX
			then CF.new(0, 0, s * (hz + 0.02)) * CF.Angles(0, 0, ang)
			else CF.new(s * (hx + 0.02), 0, 0) * CF.Angles(0, math.pi / 2, 0) * CF.Angles(0, 0, ang)
		piece(m, frame, cf, V3.new(len, t, 0.12), BATTEN, E.Material.Wood)
	end
	return m
end

-- Cette méthode permet de remplir une boîte relevée de parpaings (blocs de béton à deux alvéoles) en rangs croisés.
local function cinderBlocks(parent, frame, size)
	local m = New("Model")
	m.Name = "CinderBlocks"
	m.Parent = parent
	local layers = math.max(1, math.floor(size.Y / 1.8 + 0.5))
	local h = size.Y / layers
	for layer = 0, layers - 1 do
		-- rangs croisés : le grand côté des blocs change d'axe d'un rang à l'autre
		local along = (layer % 2 == 0) == (size.X >= size.Z)
		local L = if along then size.X else size.Z
		local D = if along then size.Z else size.X
		local per = math.max(1, math.floor(L / 4.6 + 0.4))
		local n = math.max(1, math.floor(D / 2.3 + 0.4))
		local bl, bd = L / per - 0.12, D / n - 0.12
		for i = 0, per - 1 do
			for j = 0, n - 1 do
				local u = -L / 2 + (i + 0.5) * L / per
				local v = -D / 2 + (j + 0.5) * D / n
				local y = -size.Y / 2 + (layer + 0.5) * h
				local at = if along then CF.new(u, y, v) else CF.new(v, y, u) * CF.Angles(0, math.pi / 2, 0)
				local color = shade(BLOCK, layer * 7 + i * 3 + j)
				piece(m, frame, at, V3.new(bl, h - 0.06, bd), color, E.Material.Concrete)
				-- deux alvéoles sur le dessus
				for _, s in { -1, 1 } do
					piece(
						m,
						frame,
						at * CF.new(s * bl / 4, h / 2 - 0.02, 0),
						V3.new(bl * 0.32, 0.06, bd * 0.55),
						C3.fromRGB(56, 54, 52),
						E.Material.Concrete
					)
				end
			end
		end
	end
	return m
end

-- Cette méthode permet de rhabiller une boîte relevée en pile de plaques de plâtre : plaques empilées légèrement
-- décalées, deux teintes alternées pour lire les tranches.
local function drywall(parent, frame, size)
	local m = New("Model")
	m.Name = "Drywall"
	m.Parent = parent
	local n = math.max(1, math.floor(size.Y / 0.42 + 0.5))
	local t = size.Y / n
	for i = 0, n - 1 do
		local dx, dz = 0.12 * math.sin(i * 2.3), 0.12 * math.cos(i * 3.1)
		piece(
			m,
			frame,
			V3.new(dx, -size.Y / 2 + (i + 0.5) * t, dz),
			V3.new(size.X - 0.3, t - 0.03, size.Z - 0.3),
			if i % 2 == 0 then SHEET else C3.fromRGB(196, 194, 186),
			E.Material.SmoothPlastic
		)
	end
	return m
end

-- Cette méthode permet de rhabiller une boîte relevée en bois brut (cales, chevrons) sans en changer la forme.
local function timber(parent, frame, size)
	local p = piece(parent, frame, V3.zero, size, BATTEN, E.Material.Wood)
	p.Name = "Timber"
	return p
end

local PALLET = C3.fromRGB(184, 146, 98)
local PAPER = C3.fromRGB(186, 182, 170) -- sacs de ciment

-- Cette méthode permet de poser une palette (trois longerons, planches du dessus et du dessous) dont `frame` est le
-- centre du dessous ; L le long de X, W le long de Z, hauteur 1 stud.
local function pallet(parent, frame, L, W)
	local m = New("Model")
	m.Name = "Pallet"
	m.Parent = parent
	for _, z in { -W / 2 + 0.45, 0, W / 2 - 0.45 } do
		piece(m, frame, V3.new(0, 0.5, z), V3.new(L, 0.6, 0.9), shade(PALLET, z + 3), E.Material.Wood)
	end
	local n = 7
	for i = 0, n - 1 do
		local x = -L / 2 + (i + 0.5) * L / n
		piece(m, frame, V3.new(x, 0.9, 0), V3.new(L / n - 0.45, 0.2, W), shade(PALLET, i), E.Material.Wood)
	end
	for _, x in { -L / 2 + 0.6, 0, L / 2 - 0.6 } do
		piece(m, frame, V3.new(x, 0.1, 0), V3.new(1.2, 0.2, W), shade(PALLET, x), E.Material.Wood)
	end
	return m
end

-- Cette méthode permet de remplir une boîte relevée de sacs de ciment couchés à plat, en rangs croisés, sur une
-- palette (le bas de la boîte) ; une boîte basse (moins de 2 studs) devient un rang de sacs sans palette.
local function cement(parent, frame, size)
	local m = New("Model")
	m.Name = "CementSacks"
	m.Parent = parent
	local bottom = -size.Y / 2
	if size.Y >= 2 then
		pallet(m, frame * CF.new(0, bottom, 0), size.X - 0.2, size.Z - 0.2)
		bottom += 1
	end
	local top = size.Y / 2
	local layers = math.max(1, math.floor((top - bottom) / 0.95 + 0.5))
	local h = (top - bottom) / layers
	local k = 0
	for layer = 0, layers - 1 do
		local along = layer % 2 == 0
		local lx, lz = size.X - 0.3, size.Z - 0.3
		local bagL, bagW = 5.2, 3.4
		local nx = math.max(1, math.floor((if along then lx / bagL else lx / bagW) + 0.35))
		local nz = math.max(1, math.floor((if along then lz / bagW else lz / bagL) + 0.35))
		local sx, sz = lx / nx, lz / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				k += 1
				local at = frame * CF.new(-lx / 2 + (i + 0.5) * sx, bottom + (layer + 0.5) * h, -lz / 2 + (j + 0.5) * sz)
				piece(
					m,
					at * CF.Angles(0, math.rad(2 * math.sin(k * 5.3)), 0),
					V3.zero,
					V3.new(sx * 0.95, h * 0.94, sz * 0.93),
					shade(PAPER, k),
					E.Material.Fabric
				)
			end
		end
	end
	return m
end

local REDRESS_KINDS = {
	sandbags = sandbags,
	cement = cement,
	crate = crate,
	cinder = cinderBlocks,
	drywall = drywall,
	timber = timber,
	-- « hide » : pas d'habillage, la boîte devient seulement invisible (cf. redress)
}

-- Bardage, grue, porte, groupes du toit, zone de stockage (#166) ----------------------------------------------------

local CLAD = C3.fromRGB(178, 182, 184) -- tôle nervurée
local OCHRE = C3.fromRGB(200, 156, 72) -- bande basse du bardage
local PLY = C3.fromRGB(206, 170, 118) -- contreplaqué (même teinte que LOOK.plywood)
local BEAM = C3.fromRGB(128, 94, 64) -- bois de charpente (LOOK.timber)
local CRANE = C3.fromRGB(228, 180, 44) -- treillis de la grue
local DOOR = C3.fromRGB(122, 134, 142)
local BUCKET = C3.fromRGB(226, 224, 216)

-- Cette méthode permet de poser une barre de section carrée entre deux points locaux du repère `frame`.
local function bar(parent, frame, a, b, width, color, material)
	return piece(
		parent,
		frame,
		DizzyDressing.aim((a + b) / 2, b - a),
		V3.new(width, width, (b - a).Magnitude),
		color,
		material
	)
end

-- Cette méthode permet de couper l'ombre de toutes les pièces d'un objet plaqué contre un mur, dont l'ombre se
-- confond avec celle du mur (bardage, barricade, porte) : la passe d'ombres est le premier coût de rendu de Dizzy.
local function flat(model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CastShadow = false
		end
	end
	return model
end

-- Cette méthode permet d'habiller de tôle ondulée (nervures, bande basse ocre de hauteur `band`, couvertine, cornières)
-- un pan de mur dont `frame` est le milieu du bas, sur le nu du mur, -Z local vers l'extérieur.
local function cladding(parent, frame, width, height, band)
	local m = New("Model")
	m.Name = "Cladding"
	m.Parent = parent
	band = math.clamp(band, 0, height)
	-- tôle : deux plaques (bande et haut) côte à côte, jamais l'une sur l'autre (scintillement)
	if band > 0 then
		piece(m, frame, V3.new(0, band / 2, -0.06), V3.new(width, band, 0.12), OCHRE, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, (band + height) / 2, -0.06), V3.new(width, height - band, 0.12), CLAD, E.Material.Metal)
	local n = math.max(1, math.floor(width / 1.6 + 0.5))
	local step = width / n
	for i = 0, n - 1 do
		local x = -width / 2 + (i + 0.5) * step
		if band > 0 then
			piece(m, frame, V3.new(x, band / 2, -0.21), V3.new(0.5, band, 0.18), shade(OCHRE, i), E.Material.Metal)
		end
		piece(
			m,
			frame,
			V3.new(x, (band + height) / 2, -0.21),
			V3.new(0.5, height - band, 0.18),
			shade(CLAD, i),
			E.Material.Metal
		)
	end
	if band > 0 then
		piece(m, frame, V3.new(0, band, -0.3), V3.new(width, 0.3, 0.3), TRIM, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, height - 0.3, -0.32), V3.new(width, 0.6, 0.64), GALVA, E.Material.Metal)
	for _, s in { -1, 1 } do
		-- cornières arrêtées sous la couvertine (faces confondues sinon)
		local ch = height - 0.6
		piece(m, frame, V3.new(s * (width / 2 - 0.3), ch / 2, -0.32), V3.new(0.6, ch, 0.64), GALVA, E.Material.Metal)
	end
	return flat(m)
end

-- Cette méthode permet d'habiller une face du socle de la grue en barricade de contreplaqué (panneaux, joints, vis)
-- lorsque `frame` est le milieu du bas de la face, -Z local vers l'extérieur.
local function barricade(parent, frame, width, height)
	piece(parent, frame, V3.new(0, height / 2, -0.08), V3.new(width, height, 0.16), BEAM, E.Material.Wood)
	local cols = math.max(1, math.floor(width / 12.2 + 0.5))
	local rows = 3
	local pw, ph = width / cols, height / rows
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			local x, y = -width / 2 + (c + 0.5) * pw, (r + 0.5) * ph
			piece(
				parent,
				frame,
				V3.new(x, y, -0.32),
				V3.new(pw - 0.22, ph - 0.22, 0.3),
				shade(PLY, c * 3 + r * 7 + width),
				E.Material.Wood
			)
			for _, s in { -1, 1 } do
				for k = 0, 3 do
					local sy = y - ph / 2 + (k + 0.5) * ph / 4
					piece(parent, frame, V3.new(x + s * (pw / 2 - 0.7), sy, -0.5), V3.new(0.32, 0.32, 0.08), TRIM, E.Material.Metal)
				end
			end
		end
	end
end

-- charge de la grue, définie avec les habillages du lot #187
local girderLoad

-- Cette méthode permet de construire la grue (socle en contreplaqué, mât et flèche en treillis, câbles jusqu'à la charge)
-- au pied `frame`, -Z vers la charge ; hauteurs `top`, `hook`, `load` et portée `reach` relevées, boîte `bundle` de la
-- charge (cf. CRANE).
local function crane(parent, frame, top, hook, load, reach, bundle)
	local m = New("Model")
	m.Name = "Crane"
	m.Parent = parent
	local HX, HZ, H = 24.4, 24.25, 45.5
	local base0 = New("Model")
	base0.Name = "Barricade"
	base0.Parent = m
	local lattice = New("Model")
	lattice.Name = "Lattice"
	lattice.Parent = m
	-- socle : quatre faces de contreplaqué, cornières en bois, lisse haute, dessus fermé
	for _, f in {
		{ V3.new(0, 0, -HZ), V3.new(0, 0, -1), 2 * HX },
		{ V3.new(0, 0, HZ), V3.new(0, 0, 1), 2 * HX },
		{ V3.new(-HX, 0, 0), V3.new(-1, 0, 0), 2 * HZ },
		{ V3.new(HX, 0, 0), V3.new(1, 0, 0), 2 * HZ },
	} do
		local face = frame * DizzyDressing.aim(f[1], f[2])
		barricade(base0, face, f[3], H)
		-- lisses arrêtées aux cornières (elles se croiseraient dans le même plan aux angles)
		piece(base0, face, V3.new(0, H - 0.5, -0.75), V3.new(f[3], 1, 0.9), BEAM, E.Material.Wood)
		piece(base0, face, V3.new(0, 0.5, -0.7), V3.new(f[3], 1, 0.8), BEAM, E.Material.Wood)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			piece(base0, frame, V3.new(x * (HX + 0.45), H / 2 + 0.1, z * (HZ + 0.45)), V3.new(1.1, H + 0.2, 1.1), BEAM, E.Material.Wood)
		end
	end
	piece(base0, frame, V3.new(0, H + 0.05, 0), V3.new(2 * HX, 0.1, 2 * HZ), PLY, E.Material.Wood)
	flat(base0)
	-- mât : quatre membrures, entretoises et diagonales en zigzag sur chaque face
	local s = 15.2
	local n = math.max(1, math.floor((top - H) / 32 + 0.5))
	local sh = (top - H) / n
	for _, x in { -s, s } do
		for _, z in { -s, s } do
			piece(m, frame, V3.new(x, (H + top) / 2, z), V3.new(1.6, top - H, 1.6), CRANE, E.Material.Metal)
		end
	end
	for k = 0, n do
		local y = H + k * sh
		for _, z in { -s, s } do
			piece(lattice, frame, V3.new(0, y, z), V3.new(2 * s, 0.9, 0.9), CRANE, E.Material.Metal)
		end
		for _, x in { -s, s } do
			piece(lattice, frame, V3.new(x, y, 0), V3.new(0.9, 0.9, 2 * s), CRANE, E.Material.Metal)
		end
	end
	for k = 0, n - 1 do
		local y0, y1 = H + k * sh, H + (k + 1) * sh
		local d = if k % 2 == 0 then 1 else -1
		for _, z in { -s, s } do
			bar(lattice, frame, V3.new(-d * s, y0, z), V3.new(d * s, y1, z), 0.8, CRANE, E.Material.Metal)
		end
		for _, x in { -s, s } do
			bar(lattice, frame, V3.new(x, y0, d * s), V3.new(x, y1, -d * s), 0.8, CRANE, E.Material.Metal)
		end
	end
	-- plateforme d'orientation
	piece(m, frame, V3.new(0, top + 1.25, 0), V3.new(36, 2.5, 36), TRIM, E.Material.Metal)
	disc(m, frame, V3.new(0, top + 3, 0), 26, 1, GRILLE, E.Material.Metal)
	local base = top + 3.5
	-- flèche : section triangulaire (deux membrures basses, une haute), treillis en zigzag
	local L, half, jh, bay = reach + 45, 4, 8, 10
	local z0 = -s
	for _, x in { -half, half } do
		piece(m, frame, V3.new(x, base, z0 - L / 2), V3.new(0.9, 0.9, L), CRANE, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, base + jh, z0 - L / 2), V3.new(0.9, 0.9, L), CRANE, E.Material.Metal)
	local bays = math.floor(L / bay)
	for i = 0, bays - 1 do
		local za, zb = z0 - i * bay, z0 - (i + 1) * bay
		piece(lattice, frame, V3.new(0, base, za), V3.new(2 * half, 0.6, 0.6), CRANE, E.Material.Metal)
		for _, x in { -half, half } do
			bar(lattice, frame, V3.new(x, base, za), V3.new(0, base + jh, (za + zb) / 2), 0.6, CRANE, E.Material.Metal)
			bar(lattice, frame, V3.new(0, base + jh, (za + zb) / 2), V3.new(x, base, zb), 0.6, CRANE, E.Material.Metal)
		end
	end
	-- contre-flèche : poutres, plancher, lest en béton et treuil
	local cl = 62
	for _, x in { -half, half } do
		piece(m, frame, V3.new(x, base + 0.6, s + cl / 2), V3.new(1.2, 2, cl), CRANE, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, base + 0.2, s + cl / 2), V3.new(2 * half, 0.3, cl), GRILLE, E.Material.Metal)
	for i = 0, 3 do
		piece(
			m,
			frame,
			V3.new(0, base - 3, s + cl - 3 - i * 4.2),
			V3.new(12, 9, 3.8),
			shade(C3.fromRGB(150, 146, 140), i),
			E.Material.Concrete
		)
	end
	piece(m, frame, V3.new(0, base + 3, s + 22), V3.new(9, 5, 10), PAINT, E.Material.Metal)
	-- cabine contre le mât, côté flèche
	piece(m, frame, V3.new(s + 5, top - 4, -s + 6), V3.new(8, 9, 9), PAINT, E.Material.Metal)
	local glass = piece(m, frame, V3.new(s + 5, top - 3, -s + 1.4), V3.new(7, 5, 0.2), GLASS, E.Material.Glass)
	glass.Reflectance = 0.25
	-- pylône et tirants vers la flèche et la contre-flèche
	local apex = V3.new(0, base + 42, 0)
	for _, x in { -6, 6 } do
		for _, z in { -6, 6 } do
			bar(m, frame, V3.new(x, base, z), apex, 1.2, CRANE, E.Material.Metal)
		end
	end
	tube(lattice, frame, apex, V3.new(0, base + jh, z0 - L * 0.7), 0.4, TRIM, E.Material.Metal)
	tube(lattice, frame, apex, V3.new(0, base + 2, s + cl - 1), 0.4, TRIM, E.Material.Metal)
	-- chariot (bloc relevé sous la flèche), câbles de levage et moufle au-dessus de la charge
	for _, x in { -2.5, 2.5 } do
		piece(m, frame, V3.new(x, (hook + base) / 2, -reach), V3.new(0.6, base - hook, 1.4), TRIM, E.Material.Metal)
	end
	for _, x in { -0.8, 0.8 } do
		tube(lattice, frame, V3.new(x, hook, -reach), V3.new(x, load + 6, -reach), 0.3, INSUL, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, load + 4.5, -reach), V3.new(3, 3, 2), CRANE, E.Material.Metal)
	piece(m, frame, V3.new(0, load + 2.2, -reach), V3.new(1, 1.6, 1), TRIM, E.Material.Metal)
	girderLoad(m, frame, bundle.center, bundle.size, V3.new(0, load + 1.4, -reach))
	-- treillis, tirants et câbles : barres fines, ombre coupée (un trait étiré par le soleil rasant)
	flat(lattice)
	return m
end

-- Cette méthode permet de construire une double porte (bâti, vantaux à oculus, poignées, plaque, lampe) sur l'aplat
-- relevé, `frame` au milieu du bas de sa face, -Z vers l'extérieur (nu du mur 0,28 stud derrière).
local function door(parent, frame, w, h)
	local m = New("Model")
	m.Name = "DoubleDoor"
	m.Parent = parent
	local lw, lh = 15.24, 19.56 -- vantaux (plaque relevée)
	local jamb = (w - lw) / 2
	for _, sgn in { -1, 1 } do
		piece(m, frame, V3.new(sgn * (lw + jamb) / 2, h / 2, -0.25), V3.new(jamb, h, 0.5), TRIM, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, (lh + h) / 2, -0.25), V3.new(lw, h - lh, 0.5), TRIM, E.Material.Metal)
	for _, sgn in { -1, 1 } do
		local cx = sgn * lw / 4
		piece(m, frame, V3.new(cx, lh / 2, -0.12), V3.new(lw / 2 - 0.12, lh - 0.1, 0.24), DOOR, E.Material.Metal)
		-- oculus : vitre sombre dans un cadre
		local oy = lh * 0.68
		piece(m, frame, V3.new(cx, oy, -0.26), V3.new(2.8, 6, 0.05), TRIM, E.Material.Metal)
		local g = piece(m, frame, V3.new(cx, oy, -0.29), V3.new(2.2, 5.4, 0.04), ROOM, E.Material.Glass)
		g.Reflectance = 0.3
		piece(m, frame, V3.new(cx, 1.4, -0.26), V3.new(lw / 2 - 1, 2.4, 0.05), GALVA, E.Material.Metal)
		-- poignée verticale près du battement
		local hx = sgn * 1.2
		tube(m, frame, V3.new(hx, lh * 0.4, -0.75), V3.new(hx, lh * 0.4 + 3.6, -0.75), 0.32, GALVA, E.Material.Metal)
		for _, dy in { 0.3, 3.3 } do
			piece(m, frame, V3.new(hx, lh * 0.4 + dy, -0.47), V3.new(0.25, 0.25, 0.5), GALVA, E.Material.Metal)
		end
	end
	piece(m, frame, V3.new(0, lh / 2, -0.3), V3.new(0.4, lh, 0.32), TRIM, E.Material.Metal)
	piece(m, frame, V3.new(0, 0.08, -0.55), V3.new(w, 0.16, 1.1), GALVA, E.Material.Metal)
	piece(m, frame, V3.new(0, h + 1.5, 0.24), V3.new(5, 1.3, 0.08), HAZARD, E.Material.SmoothPlastic)
	wallLamp(m, frame, V3.new(0, h + 4.2, 0.28), 1.8)
	return flat(m)
end

-- Cette méthode permet de construire un groupe de ventilation de toit (caisson, ventilateur, capot à lames) lorsque
-- `frame` est le bas du caisson, au centre, -Z vers la façade.
local function roofUnit(parent, frame)
	local m = New("Model")
	m.Name = "RoofUnit"
	m.Parent = parent
	local b, h = 12.4, 8.9
	piece(m, frame, V3.new(0, h / 2, 0), V3.new(b - 0.2, h - 0.2, b - 0.2), PAINT, E.Material.Metal)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			piece(m, frame, V3.new(x * b / 2, h / 2, z * b / 2), V3.new(0.6, h, 0.6), TRIM, E.Material.Metal)
		end
		-- panneau de visite et raidisseurs sur les côtés
		piece(m, frame, V3.new(x * (b / 2 - 0.05), h / 2, 1), V3.new(0.1, h - 2, 7), C3.fromRGB(176, 178, 172), E.Material.Metal)
		piece(m, frame, V3.new(x * (b / 2 + 0.05), h / 2, 3.8), V3.new(0.2, 1.4, 0.3), TRIM, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, h + 0.1, 0), V3.new(b + 0.3, 0.2, b + 0.3), TRIM, E.Material.Metal)
	disc(m, frame, V3.new(0, h + 0.5, 1), 8.6, 0.6, PAINT, E.Material.Metal)
	disc(m, frame, V3.new(0, h + 0.85, 1), 7.6, 0.1, GRILLE, E.Material.Metal)
	disc(m, frame, V3.new(0, h + 0.95, 1), 1.6, 0.2, TRIM, E.Material.Metal)
	for _, a in { 0, math.pi / 2 } do
		piece(
			m,
			frame,
			CF.new(0, h + 0.95, 1) * CF.Angles(0, a, 0),
			V3.new(7.6, 0.12, 0.12),
			TRIM,
			E.Material.Metal
		)
	end
	-- capot avant : joues, toit, grille à lames
	local d = 6.45
	local zc = -b / 2 - d / 2
	for _, x in { -1, 1 } do
		piece(m, frame, V3.new(x * (b / 2 - 0.15), 4.45, zc), V3.new(0.3, 6.8, d), PAINT, E.Material.Metal)
	end
	piece(m, frame, V3.new(0, 8, zc), V3.new(b, 0.3, d), PAINT, E.Material.Metal)
	piece(m, frame, V3.new(0, 4.45, -b / 2 - d + 0.2), V3.new(b - 0.6, 6.6, 0.1), GRILLE, E.Material.Metal)
	for k = 0, 8 do
		piece(
			m,
			frame,
			CF.new(0, 1.5 + k * 0.72, -b / 2 - d + 0.05) * CF.Angles(math.rad(35), 0, 0),
			V3.new(b - 0.6, 0.12, 0.7),
			TRIM,
			E.Material.Metal
		)
	end
	piece(m, frame, V3.new(b / 2 + 0.12, 6.8, -2.5), V3.new(0.06, 0.9, 2.6), HAZARD, E.Material.SmoothPlastic)
	return m
end

-- Cette méthode permet de construire deux bobines de câble empilées dans `frame` (origine au pied, au centre) :
-- joues rondes en contreplaqué, tambour enroulé de câble noir, spires en relief, moyeu et boulons.
local function cableReels(parent, frame)
	local m = New("Model")
	m.Name = "CableReels"
	m.Parent = parent
	-- joues de la taille des plaques relevées (15,1) : plus larges, elles entreraient dans le mur voisin (axe à 8,1 du nu)
	local D, t, hgt = 15.1, 0.5, 9.3
	for r = 0, 1 do
		local y0 = r * (hgt + 0.1)
		for _, y in { y0 + t / 2, y0 + hgt - t / 2 } do
			disc(m, frame, V3.new(0, y, 0), D, t, shade(PLY, y), E.Material.Wood)
		end
		disc(m, frame, V3.new(0, y0 + hgt / 2, 0), 10.6, hgt - 2 * t, INSUL, E.Material.Fabric)
		for k = 1, 4 do
			disc(m, frame, V3.new(0, y0 + t + k * (hgt - 2 * t) / 5, 0), 10.9, 0.25, GRILLE, E.Material.Fabric)
		end
		local cap = y0 + hgt
		disc(m, frame, V3.new(0, cap + 0.02, 0), 3, 0.06, GRILLE, E.Material.Metal)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			piece(m, frame, V3.new(math.cos(a) * 3, cap + 0.06, math.sin(a) * 3), V3.new(0.4, 0.12, 0.4), TRIM, E.Material.Metal)
		end
	end
	return m
end

-- Cette méthode permet de poser une palette au sol chargée de trois seaux de peinture, et une palette debout contre le
-- mur derrière, dans `frame` (origine au sol, au pied du mur ; -Z local vers l'extérieur).
local function bucketPallets(parent, frame)
	local m = New("Model")
	m.Name = "Buckets"
	m.Parent = parent
	-- palette debout : son haut s'arrête devant les nervures du bardage (0,3 stud)
	pallet(m, frame * CF.new(0, 0, -1.4) * CF.Angles(math.rad(-84), 0, 0) * CF.new(0, 0, 4), 11, 8)
	pallet(m, frame * CF.new(0, 0, -6.2), 11, 8)
	for i, at in { V3.new(-2.6, 1, -5.2), V3.new(0.2, 1, -6.8), V3.new(2.8, 1, -5) } do
		local col = if i == 2 then C3.fromRGB(214, 168, 64) else BUCKET
		disc(m, frame, at + V3.new(0, 1.35, 0), 2.6, 2.7, col, E.Material.SmoothPlastic)
		disc(m, frame, at + V3.new(0, 2.75, 0), 2.75, 0.12, shade(col, 9), E.Material.SmoothPlastic)
		disc(m, frame, at + V3.new(0, 1, 0), 2.7, 0.5, shade(col, 5), E.Material.SmoothPlastic)
	end
	return m
end

-- Fosse aux fûts, charge de la grue, clôtures grillagées (#187) ----------------------------------------------------

local DRUM = C3.fromRGB(150, 58, 42) -- fûts rouges
local DRUM_RIM = C3.fromRGB(112, 42, 32)
local LABEL = C3.fromRGB(222, 216, 196)
local STRAP = C3.fromRGB(46, 48, 52) -- feuillards des piles de contreplaqué
local GIRDER = C3.fromRGB(172, 184, 192) -- poutrelles de la charge de la grue
local SLING = C3.fromRGB(196, 84, 40) -- élingues textiles
local CORD = C3.fromRGB(24, 24, 26) -- câble électrique des baladeuses

-- image du grillage (tools/map/chainlink.png publiée en Decal ; id de l'image contenue, cf. docs/maps.md)
DizzyDressing.CHAINLINK = "rbxassetid://76216722967371" -- Decal 99427681323673

-- Cette méthode permet de rhabiller une boîte relevée en fût métallique (corps, cercles de roulement, rebord, bondes,
-- étiquette) ; teinte et orientation de l'étiquette varient avec la position du fût.
local function barrel(parent, frame, size)
	local m = New("Model")
	m.Name = "Barrel"
	m.Parent = parent
	local k = frame.Position.X * 0.37 + frame.Position.Z * 0.11
	local d, h = math.min(size.X, size.Z) - 0.1, size.Y
	local body, rim = shade(DRUM, k), shade(DRUM_RIM, k)
	disc(m, frame, V3.new(0, -0.05, 0), d - 0.2, h - 0.1, body, E.Material.Metal)
	for _, y in { -h * 0.18, h * 0.18 } do
		disc(m, frame, V3.new(0, y, 0), d, 0.32, rim, E.Material.Metal)
	end
	-- rebords du haut et du bas, un peu sous les fonds (le fond garde la couleur du corps)
	for _, s in { -1, 1 } do
		disc(m, frame, V3.new(0, s * (h / 2 - 0.4), 0), d - 0.05, 0.3, rim, E.Material.Metal)
	end
	local top = h / 2 - 0.1
	for _, b in { { 0.28, 0.75 }, { -0.3, 0.45 } } do
		disc(m, frame, V3.new(d * b[1], top + 0.05, 0), b[2], 0.1, rim, E.Material.Metal)
	end
	-- étiquette : plaque à peine enfoncée dans le corps (ses bords affleurent la courbe)
	local face = CF.Angles(0, k, 0) * CF.new(0, 0, -((d - 0.2) / 2 - 0.03))
	piece(m, frame, face, V3.new(1.4, 2.3, 0.06), LABEL, E.Material.SmoothPlastic)
	piece(m, frame, face * CF.new(0, 0.3, -0.04) * CF.Angles(0, 0, math.pi / 4), V3.new(0.55, 0.55, 0.02), HAZARD, E.Material.SmoothPlastic)
	return m
end

-- Cette méthode permet de rhabiller une boîte relevée en parpaing creux : deux parois, trois cloisons, alvéoles
-- ouvertes dans l'axe de la dimension moyenne de la boîte (le bloc relevé peut être couché ou debout).
local function hollowBlock(parent, frame, size)
	local axes = { { V3.new(1, 0, 0), size.X }, { V3.new(0, 1, 0), size.Y }, { V3.new(0, 0, 1), size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	local x, y = axes[1][1], axes[2][1]
	local f = frame * CF.fromMatrix(V3.zero, x, y, x:Cross(y))
	local L, H, T = axes[1][2], axes[2][2], axes[3][2]
	local m = New("Model")
	m.Name = "CinderBlock"
	m.Parent = parent
	local color = shade(BLOCK, frame.Position.X * 0.7 + frame.Position.Z)
	local w = math.min(0.32, T / 4)
	for _, s in { -1, 1 } do
		piece(m, f, V3.new(0, 0, s * (T / 2 - w / 2)), V3.new(L - 0.06, H - 0.06, w), color, E.Material.Concrete)
	end
	for _, cx in { -(L / 2 - w / 2), 0, L / 2 - w / 2 } do
		piece(m, f, V3.new(cx, 0, 0), V3.new(w, H - 0.06, T - 2 * w), color, E.Material.Concrete)
	end
	return m
end

-- Cette méthode permet de rhabiller une boîte relevée en pile de contreplaqué (plaques légèrement décalées, deux
-- feuillards sur les piles assez larges) ; une planche debout du relevé devient la tranche d'une pile.
local function plyStack(parent, frame, size)
	local m = New("Model")
	m.Name = "PlywoodStack"
	m.Parent = parent
	local n = math.max(1, math.floor(size.Y / 0.45 + 0.5))
	local t = size.Y / n
	for i = 0, n - 1 do
		piece(
			m,
			frame,
			V3.new(0.1 * math.sin(i * 2.3), -size.Y / 2 + (i + 0.5) * t, 0.1 * math.cos(i * 3.1)),
			V3.new(math.max(0.1, size.X - 0.25), t - 0.04, math.max(0.1, size.Z - 0.25)),
			shade(PLY, i * 1.7),
			E.Material.Wood
		)
	end
	if math.min(size.X, size.Z) > 2 then
		-- repère où X suit la longueur de la pile
		local f = if size.X >= size.Z then frame else frame * CF.Angles(0, math.pi / 2, 0)
		local L, W = math.max(size.X, size.Z), math.min(size.X, size.Z)
		for _, u in { -L / 4, L / 4 } do
			piece(m, f, V3.new(u, size.Y / 2 + 0.005, 0), V3.new(0.35, 0.05, W + 0.1), STRAP, E.Material.Metal)
			for _, s in { -1, 1 } do
				piece(m, f, V3.new(u, 0, s * (W / 2 + 0.03)), V3.new(0.35, size.Y, 0.05), STRAP, E.Material.Metal)
			end
		end
	end
	return m
end

-- Cette méthode permet de rhabiller une boîte relevée en bois de palette (planche ou longeron, sans en changer la forme).
local function palletWood(parent, frame, size)
	local p = piece(parent, frame, V3.zero, size, shade(PALLET, frame.Position.X + frame.Position.Z * 3), E.Material.Wood)
	p.Name = "PalletWood"
	return p
end

-- Cette méthode permet de rhabiller une boîte relevée en clôture de chantier : poteaux et lisses en tube galvanisé,
-- grillage en losanges (texture sur un panneau invisible, on voit et on tire au travers comme avant).
local function fence(parent, frame, size)
	local m = New("Model")
	m.Name = "Fence"
	m.Parent = parent
	local f = if size.X >= size.Z then frame else frame * CF.Angles(0, math.pi / 2, 0)
	local L, H = math.max(size.X, size.Z), size.Y
	local mesh = piece(m, f, V3.zero, V3.new(L - 0.2, H - 0.6, 0.05), GALVA, E.Material.Metal)
	mesh.Name = "Mesh"
	mesh.Transparency = 1
	for _, face in { E.NormalId.Front, E.NormalId.Back } do
		local tex = New("Texture")
		tex.Texture = DizzyDressing.CHAINLINK
		tex.Face = face
		tex.StudsPerTileU = 2.4
		tex.StudsPerTileV = 2.4
		tex.Parent = mesh
	end
	local bays = math.max(1, math.floor(L / 11 + 0.5))
	for i = 0, bays do
		local x = math.clamp(-L / 2 + i * L / bays, -L / 2 + 0.25, L / 2 - 0.25)
		tube(m, f, V3.new(x, -H / 2, 0), V3.new(x, H / 2, 0), 0.5, GALVA, E.Material.Metal)
	end
	for _, y in { -H / 2 + 0.3, 0, H / 2 - 0.3 } do
		tube(m, f, V3.new(-L / 2 + 0.25, y, 0), V3.new(L / 2 - 0.25, y, 0), 0.35, GALVA, E.Material.Metal)
	end
	return flat(m)
end

-- Cette méthode permet de rhabiller un poteau de clôture relevé en tube galvanisé coiffé, dans l'axe de la boîte.
local function fencePost(parent, frame, size)
	local m = New("Model")
	m.Name = "FencePost"
	m.Parent = parent
	local d = math.min(size.X, size.Z)
	tube(m, frame, V3.new(0, -size.Y / 2, 0), V3.new(0, size.Y / 2 - 0.15, 0), d * 0.8, GALVA, E.Material.Metal)
	disc(m, frame, V3.new(0, size.Y / 2 - 0.075, 0), d, 0.15, TRIM, E.Material.Metal)
	return flat(m)
end

REDRESS_KINDS.barrel = barrel
REDRESS_KINDS.hollowblock = hollowBlock
REDRESS_KINDS.plystack = plyStack
REDRESS_KINDS.pallet = palletWood
REDRESS_KINDS.fence = fence
REDRESS_KINDS.fencepost = fencePost

-- Cette méthode permet de suspendre une baladeuse (fil, douille, ampoule sous cage, SpotLight sans ombre) à `drop`
-- studs sous le point d'attache `frame` (dessous d'une poutre de la pergola).
local function cageLamp(parent, frame, drop)
	local m = New("Model")
	m.Name = "CageLamp"
	m.Parent = parent
	tube(m, frame, V3.zero, V3.new(0, -drop, 0), 0.15, CORD, E.Material.SmoothPlastic)
	disc(m, frame, V3.new(0, -drop - 0.3, 0), 0.6, 0.6, CORD, E.Material.SmoothPlastic)
	disc(m, frame, V3.new(0, -drop - 0.65, 0), 1.3, 0.1, TRIM, E.Material.Metal)
	local bulb = piece(m, frame, V3.new(0, -drop - 1.25, 0), V3.new(0.8, 0.8, 0.8), LAMP, E.Material.Neon)
	bulb.Shape = E.PartType.Ball
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local c = V3.new(math.cos(a) * 0.6, 0, math.sin(a) * 0.6)
		bar(m, frame, c + V3.new(0, -drop - 0.65, 0), c * 0.4 + V3.new(0, -drop - 2, 0), 0.08, TRIM, E.Material.Metal)
	end
	disc(m, frame, V3.new(0, -drop - 2, 0), 0.5, 0.1, TRIM, E.Material.Metal)
	local light = New("SpotLight")
	light.Face = E.NormalId.Bottom
	light.Angle = 120
	light.Range = 30
	light.Brightness = 1.6
	light.Color = LAMP
	light.Shadows = false
	light.Parent = bulb
	return flat(m)
end

-- Cette méthode permet de tendre une ligne de baladeuses sous une poutre de la pergola : fil en guirlande d'une lampe
-- à l'autre (creux au milieu), une lampe à chaque point de `zs`, dans le repère `frame` (poutre le long de Z).
local function lampLine(parent, frame, zs, drop, sag)
	local m = New("Model")
	m.Name = "LampLine"
	m.Parent = parent
	for i, z in zs do
		cageLamp(m, frame * CF.new(0, 0, z), drop)
		if i > 1 then
			local z0 = zs[i - 1]
			run(m, frame, { V3.new(0, -0.1, z0), V3.new(0, -sag, (z0 + z) / 2), V3.new(0, -0.1, z) }, 0.15, CORD, E.Material.SmoothPlastic)
		end
	end
	return flat(m)
end

-- Cette méthode permet de construire la charge de la grue (poutrelles en H sur deux rangs, cales en bois, deux
-- élingues ceinturées et leurs brins jusqu'au crochet) dans la boîte `center`/`size` du repère `frame` (X en largeur,
-- Z en longueur) ; `hook` est le point d'accroche des brins.
function girderLoad(parent, frame, center, size, hook)
	local m = New("Model")
	m.Name = "GirderLoad"
	m.Parent = parent
	local f = frame * CF.new(center)
	local cols, rows, gap = 4, 2, 0.6
	local bw, bh = size.X / cols, (size.Y - gap) / rows
	local fl = 0.55 -- épaisseur des ailes
	for r = 0, rows - 1 do
		local y0 = -size.Y / 2 + r * (bh + gap)
		for c = 0, cols - 1 do
			local x = -size.X / 2 + (c + 0.5) * bw
			local col = shade(GIRDER, r * 4 + c)
			-- poutrelles un peu décalées en longueur (bouts jamais dans le même plan)
			local dz, L = if (r + c) % 2 == 0 then 0.6 else -0.6, size.Z - 1.2
			piece(m, f, V3.new(x, y0 + fl / 2, dz), V3.new(bw - 0.3, fl, L), col, E.Material.Metal)
			piece(m, f, V3.new(x, y0 + bh - fl / 2, dz), V3.new(bw - 0.3, fl, L), col, E.Material.Metal)
			piece(m, f, V3.new(x, y0 + bh / 2, dz), V3.new(0.45, bh - 2 * fl, L), col, E.Material.Metal)
		end
	end
	for _, z in { -size.Z / 3, 0, size.Z / 3 } do
		piece(m, f, V3.new(0, -size.Y / 2 + bh + gap / 2, z), V3.new(size.X, gap, 1.2), BEAM, E.Material.Wood)
	end
	-- élingues : une ceinture par point de levage, deux brins jusqu'au crochet
	for _, z in { -size.Z * 0.28, size.Z * 0.28 } do
		for _, s in { -1, 1 } do
			piece(m, f, V3.new(0, s * (size.Y / 2 + 0.075), z), V3.new(size.X + 0.3, 0.15, 1.4), SLING, E.Material.Fabric)
			piece(m, f, V3.new(s * (size.X / 2 + 0.075), 0, z), V3.new(0.15, size.Y + 0.3, 1.4), SLING, E.Material.Fabric)
			tube(m, frame, hook, center + V3.new(s * (size.X / 2), size.Y / 2 + 0.15, z), 0.35, SLING, E.Material.Fabric)
		end
	end
	return m
end

-- Repères côté T (le côté CT en est le symétrique) -----------------------------------------------------------------

-- Cette méthode permet de bâtir un repère au sol tourné vers `front` (vecteur horizontal) à partir de coordonnées.
local function facing(x, y, z, fx, fz)
	local p = V3.new(x, y, z)
	return DizzyDressing.aim(p, V3.new(fx, 0, fz))
end

-- groupes de climatisation : remplacent les caissons relevés (retirés par dizzy_patches.luau), même emprise et même
-- hauteur de châssis ; -Z local (avant) vers l'intérieur de la map
DizzyDressing.AIR_HANDLERS = {
	facing(-32.52, 46.4, 20.37, 0.191, -0.982), -- balcon nord, à gauche
	facing(48.78, 46.4, 20.37, -0.182, -0.983), -- balcon nord, à droite
	facing(-77.17, 104.72, -229.62, 1, 0), -- toit haut côté T
}
-- extracteurs « champignon » sur les estrades des coins : remplacent les boîtes tournées relevées (retirées par
-- dizzy_patches.luau) ; un repère par extracteur, au pied, sur le dessus de l'estrade
DizzyDressing.VENTS = {
	facing(-241.81, 44.94, -50.8, 0, -1),
	facing(-219.46, 44.94, -50.8, 0, -1),
}
-- portes de garage : milieu du haut de l'ouverture sur le nu du mur, largeur de l'ouverture
DizzyDressing.GARAGES = {
	{ frame = facing(-211.25, 61.25, -195.07, 0, 1), width = 62.5 },
}
-- baies des murs du milieu (relevées au raycast) : centre de l'ouverture sur le nu du mur, profondeur du tableau
DizzyDressing.WINDOWS = {
	{ frame = facing(-65.03, 96.14, -261.11, 1, 0), width = 28.45, height = 5.69, depth = 2.5 },
	{ frame = facing(-65.03, 96.14, -228.6, 1, 0), width = 28.45, height = 5.69, depth = 2.5 },
}
-- lampes des murs du milieu : sous les baies, aux extrémités et au trumeau
DizzyDressing.LAMPS = {
	facing(-65.03, 89.5, -277.3, 1, 0),
	facing(-65.03, 89.5, -244.86, 1, 0),
	facing(-65.03, 89.5, -212.4, 1, 0),
}

-- échelles des murs des rampes sur pilotis (relevées en boîtes, retirées par dizzy_patches.luau) : pied sur le nu du
-- mur ; haut des rails, dessus de l'acrotère, sol du toit et bas du volume de grimpe, relatifs au pied
DizzyDressing.LADDERS = {
	{ frame = facing(-97.54, 72, -188.98, 0, 1), top = 35.5, parapet = 33.39, roof = 32.65, from = -11 },
}

-- Habillages du lot #166 (côté T, recopiés côté CT ; la grue est unique, au milieu du bord nord) ---------------------

-- grue : pied du socle au centre ; haut du mât, bas du chariot, hauteur de la moufle et portée du chariot,
-- relatifs au pied (blocs relevés : mât (0, 310,2, -81,3), chariot (0, 545,3, -268,2), charge (-2, 159,5, -268,9))
DizzyDressing.CRANE = {
	frame = facing(0, 70.55, -81.3, 0, -1),
	top = 479.25,
	hook = 473.7,
	load = 125, -- moufle : relevée de 98,55 pour que les élingues tombent à ~45° (#187)
	reach = 186.9,
	-- charge (poutrelles), boîte relevée (-2, 159,5, -268,9) dans le repère du pied : X en largeur, Z en longueur
	bundle = { center = V3.new(-1.99, 88.96, -187.56), size = V3.new(29.96, 13.95, 108.06) },
}
-- pans de tôle ondulée : milieu du bas du pan sur le nu du mur, -Z vers l'extérieur ; `band` : hauteur de la bande
-- ocre au-dessus du bas du pan (le sol devant les façades du garage est à 42,09)
DizzyDressing.CLADDING = {
	{ frame = facing(-251.3, 42.09, -195.07, 0, 1), width = 17.6, height = 54.85, band = 9 }, -- garage, trumeau gauche
	{ frame = facing(-211.25, 61.25, -195.07, 0, 1), width = 62.5, height = 35.69, band = 0 }, -- garage, au-dessus
	{ frame = facing(-155.025, 42.09, -195.07, 0, 1), width = 49.95, height = 54.85, band = 9 }, -- garage, droite
	{ frame = facing(-130.05, 42.09, -192.02, -1, 0), width = 6.1, height = 54.1, band = 9 }, -- retour vers l'échelle
	{ frame = facing(-97.5, 42.09, -188.97, 0, 1), width = 65, height = 63.36, band = 9 }, -- volume de l'échelle
	{ frame = facing(-81.28, 70.56, -357.63, 0.894, -0.447), width = 72.7, height = 34.1, band = 7 }, -- mur du stockage
}
-- groupes de ventilation du toit du garage : bas du caisson, au centre ; capot vers la façade
DizzyDressing.ROOF_UNITS = {
	facing(-247.9, 98.95, -207.4, 0, 1),
	facing(-231.6, 98.95, -207.4, 0, 1),
}
-- double porte (aplat relevé) : milieu du bas, sur la face de l'aplat ; largeur et hauteur de l'aplat
DizzyDressing.DOORS = {
	{ frame = facing(-65.3, 42.09, -53.35, -1, 0), width = 20.11, height = 21.25 },
}
-- zone de stockage des chantiers, au pied du mur en tôle : bobines (sur la pile de plaques, à la place de la bobine
-- relevée), palettes et seaux. Bobines posées de chaque côté : la bobine relevée côté CT n'est pas le symétrique exact
-- de celle du côté T (2 studs d'écart), repère au centre des joues relevées.
DizzyDressing.REELS = {
	facing(-73.8, 76.25, -360.8, 0.894, -0.447), -- T
	facing(74.9, 76.25, -157.3, -0.894, 0.447), -- CT
}
DizzyDressing.BUCKETS = { facing(-67.87, 70.56, -330.81, 0.894, -0.447) }

-- Fosse centrale (#187, unique : le milieu de la map) : lignes de baladeuses sous les deux poutres longitudinales de la
-- pergola (dessous à 70,71) ; repère au dessous de la poutre, Z le long de la poutre
DizzyDressing.PIT_LAMPS = {
	lines = { facing(-20.32, 70.71, -260.1, 0, -1), facing(19.81, 70.71, -260.1, 0, -1) },
	zs = { -27, 0, 27 }, -- le long de la poutre, depuis le milieu de la fosse
	drop = 6,
	sag = 4,
}

-- Objets relevés en boîtes, rhabillés sur place : la boîte d'origine reste (invisible) pour la collision, l'habillage
-- est sans collision. Coordonnées du monde (comme dizzy_patches.luau), `group` = groupe source (attribut Group),
-- `minVolume` / `maxVolume` pour trier les boîtes d'une même zone, `zone.radius` pour une zone ronde (en plan),
-- `folders` pour viser d'autres dossiers que Decor (sans `group`). `hide` : la boîte devient invisible et un objet
-- construit à part la remplace à l'image. Chantiers des étages (T vers (1925, 76, -360), CT vers (2074, 76, -160)) et
-- tas de sacs sous la rampe CT.
DizzyDressing.REDRESS = {
	{ kind = "cement", group = "stucco", why = "sacs de ciment du chantier T",
		zone = { center = { 1912.9, 79, -384 }, size = { 12, 14, 14 } } },
	{ kind = "cement", group = "stucco", why = "sacs de ciment du chantier CT",
		zone = { center = { 2086, 79, -138.5 }, size = { 12, 14, 14 } } },
	{ kind = "hide", group = "metal", why = "mât de la grue (treillis de DizzyDressing)",
		zone = { center = { 2000, 310.2, -81.3 }, size = { 1, 1, 1 } } },
	{ kind = "hide", group = "metal", why = "aplat de la porte T (DizzyDressing.DOORS)",
		zone = { center = { 1935.9, 47.4, -53.35 }, size = { 1, 12, 2 } } },
	{ kind = "hide", group = "metal", why = "aplat de la porte CT (DizzyDressing.DOORS)",
		zone = { center = { 2064.1, 47.4, -466.85 }, size = { 1, 12, 1 } } },
	{ kind = "hide", group = "metal", why = "groupe du toit du garage T (gauche)",
		zone = { center = { 1752.1, 103.15, -202.3 }, size = { 1, 1.5, 11 } } },
	{ kind = "hide", group = "metal", why = "groupe du toit du garage T (droite)",
		zone = { center = { 1768.4, 103.15, -202.3 }, size = { 1, 1.5, 11 } } },
	{ kind = "hide", group = "metal", why = "groupe du toit du garage CT (gauche)",
		zone = { center = { 2247.9, 103.15, -317.9 }, size = { 1, 1.5, 11 } } },
	{ kind = "hide", group = "metal", why = "groupe du toit du garage CT (droite)",
		zone = { center = { 2231.6, 103.15, -317.9 }, size = { 1, 1.5, 11 } } },
	-- bobines relevées : faces du tambour et des joues (murs, sols, plafonds, pentes rangées en rampes) jusqu'à 10 studs
	-- de l'axe, puis les deux plaques carrées des joues ; zone ronde et petites pièces seulement (mur voisin, parpaings)
	{ kind = "hide", folders = { "Walls", "Ceilings", "Floors", "Ramps" }, maxVolume = 100,
		why = "bobine relevée du chantier T",
		zone = { center = { 1926.2, 85.75, -360.8 }, radius = 10.5, size = { 21, 19.5, 21 } } },
	{ kind = "hide", group = "metal", why = "joues relevées de la bobine T",
		zone = { center = { 1926.2, 85.6, -360.8 }, size = { 3, 19.5, 3 } } },
	{ kind = "hide", folders = { "Walls", "Ceilings", "Floors", "Ramps" }, maxVolume = 100,
		why = "bobine relevée du chantier CT",
		zone = { center = { 2074.9, 85.75, -157.3 }, radius = 10.5, size = { 21, 19.5, 21 } } },
	{ kind = "hide", group = "metal", why = "joues relevées de la bobine CT",
		zone = { center = { 2074.9, 85.6, -157.3 }, size = { 3, 19.5, 3 } } },
	{ kind = "sandbags", group = "stucco", why = "sacs de sable sous la rampe CT (ouest)",
		zone = { center = { 2077, 49, -427 }, size = { 10, 10, 12 } } },
	{ kind = "sandbags", group = "stucco", why = "sacs de sable sous la rampe CT (est)",
		zone = { center = { 2105, 49, -427.5 }, size = { 10, 10, 12 } } },
	{ kind = "crate", group = "metal", why = "caisse debout du chantier T",
		zone = { center = { 1915.29, 81.94, -368.43 }, size = { 1, 1, 1 } } },
	{ kind = "crate", group = "metal", why = "caisse debout du chantier CT",
		zone = { center = { 2075.62, 85.32, -169.89 }, size = { 1, 1, 1 } } },
	{ kind = "crate", group = "plastic", why = "caisses sous la caisse debout CT",
		zone = { center = { 2073.3, 78.13, -169.4 }, size = { 3, 1, 7 } } },
	{ kind = "cinder", group = "rock", why = "parpaings du chantier T",
		zone = { center = { 1929.5, 78, -348 }, size = { 14, 5, 14 } } },
	{ kind = "cinder", group = "plastic", why = "parpaings du chantier CT",
		zone = { center = { 2072.14, 78.13, -175.77 }, size = { 1, 1, 1 } } },
	{ kind = "drywall", group = "sheetrock", why = "plaques de plâtre du chantier T", minVolume = 100,
		zone = { center = { 1928.36, 73.5, -357.29 }, size = { 1, 4, 1 } } },
	{ kind = "timber", group = "sheetrock", why = "cales entre les plaques T", maxVolume = 100,
		zone = { center = { 1928.3, 73.51, -357.3 }, size = { 14, 0.5, 26 } } },
	{ kind = "drywall", group = "metal", why = "plaques de plâtre du chantier CT", minVolume = 1000,
		zone = { center = { 2072.62, 73.74, -160.46 }, size = { 1, 1, 1 } } },
	{ kind = "timber", group = "metal", why = "chants et chevrons des plaques CT", maxVolume = 100,
		zone = { center = { 2072.6, 72.3, -160.4 }, size = { 13, 3.5, 25 } } },
	-- lot #187 : fosse centrale (fûts sur palettes, piles de contreplaqué, parpaings), charge de la grue, clôtures
	{ kind = "barrel", group = "rock", minVolume = 300, why = "fûts de la fosse centrale",
		zone = { center = { 2000, 50, -260 }, size = { 90, 24, 100 } } },
	{ kind = "barrel", group = "metal_barrel", why = "fût isolé de la fosse centrale",
		zone = { center = { 1975.87, 37.6, -258.06 }, size = { 1, 1, 1 } } },
	{ kind = "hollowblock", group = "rock", maxVolume = 40, why = "parpaings de la fosse centrale",
		zone = { center = { 2000, 36, -260 }, size = { 90, 10, 100 } } },
	{ kind = "plystack", group = "metal", minVolume = 20, why = "piles de contreplaqué de la fosse",
		zone = { center = { 2000, 36.8, -260 }, size = { 90, 1, 100 } } },
	{ kind = "pallet", group = "metal", maxVolume = 12, why = "palettes sous les fûts de la fosse",
		zone = { center = { 2000, 45, -260 }, size = { 90, 14, 100 } } },
	{ kind = "timber", group = "metal", maxVolume = 12, why = "chevrons au sol de la fosse",
		zone = { center = { 2000, 33.95, -260 }, size = { 90, 1, 100 } } },
	{ kind = "hide", group = "metal", why = "charge de la grue (poutrelles de DizzyDressing)",
		zone = { center = { 1998.01, 159.51, -268.86 }, size = { 1, 1, 1 } } },
	{ kind = "fence", group = "passbullets_chainlink", why = "clôtures grillagées",
		zone = { center = { 2000, 80, -260 }, size = { 600, 100, 600 } } },
	{ kind = "fencepost", group = "chainlink", why = "poteaux des clôtures grillagées",
		zone = { center = { 2000, 80, -260 }, size = { 600, 100, 600 } } },
}

-- Cette méthode permet de rhabiller les boîtes relevées listées dans REDRESS lorsque la géométrie est posée : chaque
-- boîte devient invisible (collision gardée) et reçoit son habillage dans `parent`. Lève une erreur si une zone ne
-- contient aucune boîte (relevé changé). Renvoie le nombre de boîtes rhabillées.
function DizzyDressing.redress(map, parent)
	local geometry = map:FindFirstChild("Geometry")
	assert(geometry and geometry:FindFirstChild("Decor"), "Geometry.Decor absent")
	local total = 0
	for _, r in DizzyDressing.REDRESS do
		local c = V3.new(r.zone.center[1], r.zone.center[2], r.zone.center[3])
		local s = V3.new(r.zone.size[1], r.zone.size[2], r.zone.size[3])
		local n = 0
		local candidates = {}
		for _, name in r.folders or { "Decor" } do
			local f = geometry:FindFirstChild(name)
			for _, p in if f then f:GetChildren() else {} do
				-- seules les pièces ont une position (un dossier ajouté par une retouche ferait échouer la lecture)
				if p:IsA("BasePart") then
					table.insert(candidates, p)
				end
			end
		end
		for _, p in candidates do
			local d = p.CFrame.Position - c
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if
				p.Transparency < 1
				and (r.group == nil or p:GetAttribute("Group") == r.group)
				and math.abs(d.X) <= s.X / 2
				and math.abs(d.Y) <= s.Y / 2
				and math.abs(d.Z) <= s.Z / 2
				and (r.zone.radius == nil or d.X * d.X + d.Z * d.Z <= r.zone.radius ^ 2)
				and v >= (r.minVolume or 0)
				and v <= (r.maxVolume or math.huge)
			then
				if r.kind ~= "hide" then
					local frame, size = upright(p.CFrame, p.Size)
					REDRESS_KINDS[r.kind](parent, frame, size)
				end
				p.Transparency = 1
				p.CastShadow = false
				p:SetAttribute("Redress", r.why)
				n += 1
			end
		end
		assert(n > 0, string.format("REDRESS %q : aucune boîte dans la zone", r.why))
		print(string.format("  habillage %q : %d boîte(s)", r.why, n))
		total += n
	end
	return total
end

-- Cette méthode permet de poser tout l'habillage détaillé dans `map` (dossier Dressing) lorsque le générateur a fini
-- la géométrie ; `offset` est le décalage de la map. Renvoie le nombre d'objets posés.
function DizzyDressing.build(map, offset)
	local root = New("Folder")
	root.Name = "Dressing"
	root.Parent = map
	local shift = CF.new(offset)
	local count = 0
	-- Cette méthode permet de poser un objet côté T puis son symétrique côté CT.
	local function both(build, cf, ...)
		build(root, shift * cf, ...)
		build(root, shift * DizzyDressing.mirror(cf), ...)
		count += 2
	end
	for _, cf in DizzyDressing.AIR_HANDLERS do
		both(hvac, cf)
	end
	for _, cf in DizzyDressing.VENTS do
		both(vent, cf)
	end
	for _, g in DizzyDressing.GARAGES do
		both(garage, g.frame, g.width)
	end
	for _, w in DizzyDressing.WINDOWS do
		both(window, w.frame, w.width, w.height, w.depth)
	end
	for _, cf in DizzyDressing.LAMPS do
		both(wallLamp, cf, V3.new(0, 0, 0), 1.8)
	end
	-- échelles : décor des deux côtés, volumes de grimpe dans Maps.Map.Ladders (LadderRules.LADDERS_FOLDER)
	local volumes = New("Folder")
	volumes.Name = "Ladders"
	volumes.Parent = map
	for _, l in DizzyDressing.LADDERS do
		both(ladder, l.frame, l.top, l.parapet, l.roof)
		ladderVolume(volumes, shift * l.frame, l.from, l.parapet + 5.6)
		ladderVolume(volumes, shift * DizzyDressing.mirror(l.frame), l.from, l.parapet + 5.6)
	end
	-- lot #166 : grue (unique), bardage, groupes du toit, portes, zone de stockage
	local c = DizzyDressing.CRANE
	crane(root, shift * c.frame, c.top, c.hook, c.load, c.reach, c.bundle)
	count += 1
	for _, w in DizzyDressing.CLADDING do
		both(cladding, w.frame, w.width, w.height, w.band)
	end
	for _, cf in DizzyDressing.ROOF_UNITS do
		both(roofUnit, cf)
	end
	for _, d in DizzyDressing.DOORS do
		both(door, d.frame, d.width, d.height)
	end
	for _, cf in DizzyDressing.REELS do
		cableReels(root, shift * cf)
		count += 1
	end
	for _, cf in DizzyDressing.BUCKETS do
		both(bucketPallets, cf)
	end
	-- lot #187 : baladeuses de la fosse centrale (unique)
	local pit = DizzyDressing.PIT_LAMPS
	for _, cf in pit.lines do
		lampLine(root, shift * cf, pit.zs, pit.drop, pit.sag)
		count += 1
	end
	count += DizzyDressing.redress(map, root)
	return count
end

return DizzyDressing

--!nocheck
-- Habillage détaillé de Dizzy, posé par build_dizzy.luau après le plan relevé et les retouches : objets construits
-- pièce par pièce là où le relevé ne donne qu'une boîte ou un trou (groupes de climatisation, extracteurs d'air des
-- estrades, auvents et câbles des
-- portes de garage, fenêtres et lampes des murs du milieu). Coordonnées du plan relevé (sans le décalage de la map,
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
	return count
end

return DizzyDressing

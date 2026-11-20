--!nocheck
-- Générateur de Radoub (#593), maquette grise jouable, exécuté dans Lune sans Studio :
--   lune run tools/map/build_radoub.luau      (racine du worktree, plugin Rojo déconnecté de ce serveur)
-- Écrit assets/rbx/Maps/Radoub.rbxm (Workspace.Maps.Radoub). Plan inventé (pas une reprise) : chantier naval sur une
-- presqu'île, forme de radoub dont les deux flancs sont des rampes de surf face à face, navire en trois tronçons au
-- fond. Maquette de référence : docs/maps/plans-radoub.html ; règles et pièges : docs/maps.md « Radoub ».
-- Repère du plan (sans OFFSET) : X ouest → est, Z nord → sud, quais à y 60, fond de la forme à y 0, mer à y 42.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local MapBuild = require("./MapBuild")
local RampCheck = require("./RampCheck")
local RadoubDressing = require("./RadoubDressing")
local RampEdges = require("./RampEdges")
local SpawnSight = require("./SpawnSight")

local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local OUT = "assets/rbx/Maps/Radoub.rbxm"
-- Pose du plan dans le monde : demi-tour autour de CENTER (le soleil du jeu, très bas à l'ouest-nord-ouest, se couche
-- sur la mer au lieu d'être caché par le hangar : à 1,4° de haut, son ombre couvrait toute la map), puis décalage pour
-- ne pas se superposer à Dizzy (posée en X 2000) en mode Edit. Le plan ci-dessous est écrit avant ce demi-tour.
local OFFSET = Vector3.new(-2000, 0, 0)
local CENTER = Vector3.new(236, 0, 220)
local PLACE = CFrame.new(OFFSET + CENTER) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-CENTER)
local folder, ghost = MapBuild.folder, MapBuild.ghost

local QUAY = 60 -- dessus des quais
local SEA = 42 -- surface de la mer
local DECK = 44.5 -- dessus du pont du navire
-- Haut des volumes de mort au-dessus de la surface de l'eau : la position testée est la racine, à 4,765 studs au-dessus
-- des pieds (SpawnCheck.ROOT_TO_FEET) ; à 4 studs, on meurt les pieds dans l'eau.
local KILL_ABOVE_SEA = 4
local KILL_HEIGHT = -40
-- Échelle (retour du 20/11/2026 : trop encombrée pour prendre de la vitesse en bhop) : le plan est écrit à l'échelle 1
-- puis toute la map (pièces, tailles, portées des lampes) est agrandie de SCALE autour du centre posé, y = 0 compris ;
-- les pentes de surf gardent leur angle. Restent en vraie grandeur : points d'apparition, hauteur des volumes de mort
-- au-dessus de l'eau, KillHeight (en studs du monde), garde-corps du portique (GANTRY.railH).
local SCALE = 1.4
-- salle des pompes reculée vers le hangar (retour du 20/11/2026) : 25 studs du plan jusqu'à la tête de forme
local PUMP_X0, PUMP_X1 = -20, 35
local WALL = 1.5 -- épaisseur des murs des bâtiments
local SCREEN_GAP = 7 -- studs entre une porte et l'écran intérieur qui la masque (passage de chaque côté)
local SCREEN_OVERLAP = 5 -- studs dont l'écran dépasse la porte de chaque côté

-- Couleur et matière des pièces de la maquette ; l'habillage (RadoubDressing) se pose par-dessus. Chantier propre et
-- récent (retour du 20/11/2026 : la matière Brick de Roblox jugée laide, aucune matière rouillée) : teintes unies.
local LOOK = {
	quay = { Color3.fromRGB(158, 154, 146), Enum.Material.Concrete },
	dock = { Color3.fromRGB(118, 114, 108), Enum.Material.Concrete },
	surf = { Color3.fromRGB(70, 74, 82), Enum.Material.DiamondPlate },
	clad = { Color3.fromRGB(222, 224, 220), Enum.Material.SmoothPlastic }, -- bardage des ateliers et du hangar
	precast = { Color3.fromRGB(196, 192, 184), Enum.Material.Concrete }, -- béton préfabriqué des magasins
	brick = { Color3.fromRGB(146, 74, 56), Enum.Material.SmoothPlastic }, -- salle des pompes (teinte, pas la matière Brick)
	roof = { Color3.fromRGB(92, 98, 110), Enum.Material.Metal },
	antifoul = { Color3.fromRGB(150, 48, 38), Enum.Material.Metal }, -- carène sous la flottaison
	boottop = { Color3.fromRGB(28, 28, 30), Enum.Material.Metal }, -- liston noir de flottaison
	hull = { Color3.fromRGB(34, 50, 82), Enum.Material.Metal }, -- œuvres mortes bleu marine
	deck = { Color3.fromRGB(78, 98, 86), Enum.Material.Metal },
	cabin = { Color3.fromRGB(232, 232, 226), Enum.Material.Metal },
	funnel = { Color3.fromRGB(38, 86, 146), Enum.Material.Metal },
	steel = { Color3.fromRGB(96, 104, 112), Enum.Material.Metal },
	gate = { Color3.fromRGB(88, 100, 114), Enum.Material.Metal },
	grating = { Color3.fromRGB(70, 74, 80), Enum.Material.DiamondPlate },
	crane = { Color3.fromRGB(232, 180, 40), Enum.Material.Metal },
	concrete = { Color3.fromRGB(176, 172, 164), Enum.Material.Concrete },
	wood = { Color3.fromRGB(150, 112, 72), Enum.Material.WoodPlanks },
	dark = { Color3.fromRGB(35, 36, 44), Enum.Material.SmoothPlastic },
	water = { Color3.fromRGB(43, 86, 119), Enum.Material.SmoothPlastic },
	red = { Color3.fromRGB(176, 52, 40), Enum.Material.Metal },
	blue = { Color3.fromRGB(40, 90, 150), Enum.Material.Metal },
	ochre = { Color3.fromRGB(214, 160, 44), Enum.Material.Metal },
	green = { Color3.fromRGB(70, 120, 84), Enum.Material.Metal },
}

local map = Instance.new("Model")
map.Name = "Radoub"
map:SetAttribute("KillHeight", KILL_HEIGHT * SCALE)
map:SetAttribute("GeneratedBy", "build_radoub")
local geometry = folder(map, "Geometry")
local F = {
	floors = folder(geometry, "Floors"),
	walls = folder(geometry, "Walls"),
	ramps = folder(geometry, "Ramps"),
	clips = folder(geometry, "Clips"),
	decor = folder(geometry, "Decor"),
	scenery = folder(map, "Scenery"),
	ladders = folder(map, "Ladders"),
	spawns = folder(map, "GroundSpawns"),
	kill = folder(map, "KillVolumes"),
}

-- Cette méthode permet de poser une pièce ancrée habillée (repère du plan, posé par PLACE) ; solid faux en fait un
-- décor sans collision ni requête.
local function piece(parent, class, cf, size, look, solid)
	local p = Instance.new(class)
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = PLACE * cf
	local spec = LOOK[look]
	assert(spec, "habillage inconnu : " .. tostring(look))
	p.Color = spec[1]
	p.Material = spec[2]
	p.Name = look
	if solid == false then
		ghost(p)
	end
	p.Parent = parent
	return p
end

-- Cette méthode permet de poser un bloc aligné sur les axes à partir de ses bornes (repère du plan).
local function block(parent, x0, x1, y0, y1, z0, z1, look, solid)
	return piece(
		parent,
		"Part",
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		look,
		solid
	)
end

-- Cette méthode permet de donner un repère dont le LookVector est `look` (jamais CFrame.lookAt sous Lune, cf.
-- docs/maps.md « Repères »).
local function aim(pos, look)
	local z = -look.Unit
	local up = if math.abs(z.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local x = up:Cross(z).Unit
	return CFrame.fromMatrix(pos, x, z:Cross(x), z)
end

-- Terre-plein, hangar, mer ------------------------------------------------------------------------------------------

-- Cette méthode permet de poser le terre-plein des quais, le hangar qui ferme l'ouest, la mer (décor) et ses volumes
-- de mort.
local function land()
	block(F.floors, -60, 472, -20, QUAY, -30, 150, "quay")
	block(F.floors, -60, 472, -20, QUAY, 310, 470, "quay")
	block(F.floors, -60, 60, -20, QUAY, 150, 310, "quay")
	-- hangar : mur de 90 studs qui borne la map à l'ouest, faîtage en décor
	block(F.walls, -150, -60, -20, 150, -30, 470, "clad")
	for _, side in { { -150, -105, 1 }, { -105, -60, -1 } } do
		-- deux pans de toit (coins) au-dessus du hangar, faîtage au milieu
		local w = side[2] - side[1]
		local cf = CFrame.new((side[1] + side[2]) / 2, 161, 220) * CFrame.Angles(0, side[3] * math.pi / 2, 0)
		piece(F.scenery, "WedgePart", cf, Vector3.new(500, 22, w), "roof", false)
	end
	-- mer : nappes autour de la presqu'île (sans collision), volumes de mort jusqu'à KILL_ABOVE_SEA au-dessus
	local seas = {
		{ -1600, 2400, -1600, -30 },
		{ -1600, 2400, 470, 2400 },
		{ 472, 2400, -30, 470 },
		{ -1600, -150, -30, 470 },
	}
	for _, s in seas do
		local w = block(F.scenery, s[1], s[2], SEA - 1, SEA, s[3], s[4], "water", false)
		-- opaque : une nappe translucide de cette taille se redessine sur tout l'écran (coût GPU, cf. nuages de Dizzy)
		w.Transparency = 0
		w.Reflectance = 0.15
		w.CastShadow = false
		local k = block(F.kill, s[1], s[2], KILL_HEIGHT - 20, SEA + KILL_ABOVE_SEA / SCALE, s[3], s[4], "water", false)
		k.Transparency = 1
		k.CastShadow = false
		k.Name = "Sea"
	end
	-- rive d'en face, digue et phare : RadoubDressing (fond de décor)
end

-- Forme de radoub ---------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser un flanc de surf : remplissage en coin sous la pente, dalle d'acier dans Ramps (dessus
-- dans le plan de la pente, axe Y = normale) que RampEdges transforme en peau continue. `top` : bord haut en Z, `toe` :
-- pied en Z (y 0).
local function flank(x0, x1, top, toe)
	local run = math.abs(toe - top)
	local zc = (top + toe) / 2
	-- coin : côté haut au +Z local ; flanc nord (haut au nord, -Z du monde) tourné d'un demi-tour
	local turn = if top < toe then CFrame.Angles(0, math.pi, 0) else CFrame.new()
	piece(F.floors, "WedgePart", CFrame.new((x0 + x1) / 2, QUAY / 2, zc) * turn, Vector3.new(x1 - x0, QUAY, run), "dock")
	local len = math.sqrt(run * run + QUAY * QUAY)
	local sign = if top < toe then 1 else -1
	local n = Vector3.new(0, run / len, sign * QUAY / len)
	local mid = Vector3.new((x0 + x1) / 2, QUAY / 2, zc) - n * 0.5
	local cf = CFrame.fromMatrix(mid, Vector3.new(1, 0, 0), n)
	return piece(F.ramps, "Part", cf, Vector3.new(x1 - x0, 1, len), "surf")
end

-- Cette méthode permet de poser la forme : fond, deux flancs de surf, rampe d'accès le long de la tête, bateau-porte.
local function dock()
	block(F.floors, 60, 460, -20, 0, 150, 310, "dock")
	-- flanc nord (x 74 → 460 : la rampe d'accès occupe la tête) et flanc sud, 55°
	flank(74, 460, 150, 192)
	flank(60, 460, 310, 268)
	-- rampe d'accès à pied (32°) le long de la tête de forme, du quai nord au fond
	piece(
		F.floors,
		"WedgePart",
		CFrame.new(67, QUAY / 2, 198) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(14, QUAY, 96),
		"quay"
	)
	-- bateau-porte : passage à hauteur de quai au bout est
	block(F.floors, 460, 472, -20, QUAY, 150, 310, "gate")
	-- tins de quille sous la coque : socle béton, chapeau en bois
	for x = 100, 425, 14 do
		block(F.decor, x, x + 5, 0, 3.5, 222, 238, "concrete")
		block(F.decor, x, x + 5, 3.5, 5, 222, 238, "wood")
	end
end

-- Navire ------------------------------------------------------------------------------------------------------------

-- Cette méthode permet de poser une moitié d'étrave (coin couché, extrudé verticalement) dont l'angle droit est en
-- (x0, zc) : côtés de `len` vers l'est et de `half` vers le nord (side -1) ou le sud (side 1).
local function bowHalf(x0, zc, len, half, side, y0, y1, look)
	-- local Y vers l'est, local Z vers le sud (side 1) ou le nord (side -1) : local X vertical, X = Y × Z
	local xv = Vector3.new(0, side, 0)
	local yv = Vector3.new(1, 0, 0)
	local cf = CFrame.fromMatrix(Vector3.new(x0 + len / 2, (y0 + y1) / 2, zc + side * half / 2), xv, yv)
	piece(F.walls, "WedgePart", cf, Vector3.new(y1 - y0, len, half), look or "hull")
end

-- tronçons du navire (bornes en X), flottaison peinte : carène rouge sous BOOT_LOW, liston noir jusqu'à BOOT_HIGH
local SECTIONS = { { 95, 200 }, { 215, 315 }, { 330, 410 } }
local BOOT_LOW, BOOT_HIGH = 26.5, 28
local HATCHES = {
	{ 228, 262, DECK + 3.5, 215, 245 },
	{ 272, 306, DECK + 3.5, 215, 245 },
	{ 345, 365, DECK + 5.5, 218, 242 },
}

-- Cette méthode permet de poser le navire : trois tronçons sur leurs tins, étrave, château arrière, panneaux de cale.
local function ship()
	for _, s in SECTIONS do
		local a, b = s[1], s[2]
		block(F.walls, a, b, 20, BOOT_LOW, 205, 255, "antifoul")
		block(F.walls, a, b, BOOT_LOW, BOOT_HIGH, 205, 255, "boottop")
		block(F.walls, a, b, BOOT_HIGH, DECK - 0.9, 205, 255, "hull")
		block(F.walls, a, b, 10, 20, 210, 250, "antifoul")
		block(F.walls, a, b, 5, 10, 220, 240, "antifoul")
		block(F.floors, a, b, DECK - 0.9, DECK, 205, 255, "deck")
		-- pavois : couvert bas le long des bords du pont
		block(F.walls, a, b, DECK, DECK + 2.5, 205, 205.8, "hull")
		block(F.walls, a, b, DECK, DECK + 2.5, 254.2, 255, "hull")
	end
	for _, side in { -1, 1 } do
		bowHalf(410, 230, 32, 25, side, 10, BOOT_LOW, "antifoul")
		bowHalf(410, 230, 32, 25, side, BOOT_LOW, BOOT_HIGH, "boottop")
		bowHalf(410, 230, 32, 25, side, BOOT_HIGH, DECK)
	end
	-- château arrière (ouvert à l'est), mât
	block(F.walls, 105, 150, DECK, DECK + 22, 212, 213.5, "cabin")
	block(F.walls, 105, 150, DECK, DECK + 22, 246.5, 248, "cabin")
	block(F.walls, 105, 106.5, DECK, DECK + 22, 213.5, 246.5, "cabin")
	block(F.walls, 148.5, 150, DECK + 10, DECK + 22, 213.5, 246.5, "cabin")
	block(F.floors, 105, 150, DECK + 22, DECK + 23.5, 212, 248, "cabin")
	block(F.decor, 112, 124, DECK + 23.5, DECK + 34, 224, 236, "funnel")
	-- panneaux de cale, tôles, bois de chantier
	for _, h in HATCHES do
		block(F.decor, h[1], h[2], DECK, h[3], h[4], h[5], "steel")
	end
	block(F.decor, 380, 398, DECK, DECK + 7.5, 220, 240, "wood")
end

-- Cette méthode permet de poser une passerelle en pente (le long de X) d'un quai à y QUAY jusqu'au pont, garde-corps
-- compris.
local function gangway(xq, xd, zc)
	local dx, dy = xd - xq, DECK - QUAY
	local len = math.sqrt(dx * dx + dy * dy)
	local angle = math.atan2(dy, dx)
	local mid = Vector3.new((xq + xd) / 2, (QUAY + DECK) / 2, zc)
	local frame = CFrame.new(mid) * CFrame.Angles(0, 0, angle)
	if dx < 0 then
		frame = CFrame.new(mid) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.atan2(dy, -dx))
	end
	piece(F.floors, "Part", frame * CFrame.new(0, -0.4, 0), Vector3.new(len, 0.8, 8), "steel")
	for _, side in { -3.8, 3.8 } do
		-- garde-corps : plan de collision invisible (arrête toujours les balles), main courante, sous-lisse, plinthe
		-- et poteaux verticaux en décor
		local guard = piece(F.walls, "Part", frame * CFrame.new(0, 1.5, side), Vector3.new(len, 3, 0.4), "crane")
		guard.Transparency = 1
		guard.CastShadow = false
		piece(F.decor, "Part", frame * CFrame.new(0, 3, side), Vector3.new(len, 0.25, 0.25), "crane", false)
		piece(F.decor, "Part", frame * CFrame.new(0, 1.6, side), Vector3.new(len, 0.16, 0.16), "crane", false)
		piece(F.decor, "Part", frame * CFrame.new(0, 0.2, side), Vector3.new(len, 0.4, 0.12), "crane", false)
		for t = -len / 2 + 0.3, len / 2 - 0.2, 3.5 do
			local base = (frame * CFrame.new(t, 0, side)).Position
			local top = (frame * CFrame.new(t, 3, side)).Position
			piece(F.decor, "Part", CFrame.new((base + top) / 2), Vector3.new(0.18, (top - base).Magnitude, 0.18), "crane", false)
		end
	end
end

-- Cette méthode permet de poser une échelle : montants et barreaux en décor, volume de grimpe (LadderRules) devant le
-- mur, du pied `y0` jusqu'à une hauteur de corps au-dessus du haut `y1`. `pos` : pied de l'échelle sur la face du mur,
-- `out` : normale sortante.
local function ladder(pos, out, y0, y1)
	local frame = aim(Vector3.new(pos.X, y0, pos.Z), out)
	local h = y1 - y0
	for _, side in { -1.2, 1.2 } do
		piece(F.decor, "Part", frame * CFrame.new(side, h / 2, -0.3), Vector3.new(0.3, h, 0.3), "crane", false)
	end
	for y = 1, h - 0.5, 1.2 do
		piece(F.decor, "Part", frame * CFrame.new(0, y, -0.3), Vector3.new(2.4, 0.2, 0.2), "crane", false)
	end
	local v = Instance.new("Part")
	v.Name = "Ladder"
	v.Anchored = true
	ghost(v)
	v.Transparency = 1
	v.CastShadow = false
	v.Size = Vector3.new(5, h + 5.6, 2.5)
	v.CFrame = PLACE * (frame * CFrame.new(0, (h + 5.6) / 2, -1.25))
	v.Parent = F.ladders
end

-- Portique roulant, bâtiments, quais ----------------------------------------------------------------------------------

-- Portique : chaque pied fait de deux poteaux sur un bogie, deux poutres-caissons reliées par une passerelle en
-- caillebotis (dessus praticable à y GANTRY.top, même emprise que la maquette), chariot sous les poutres. Les rails,
-- roues, contreventements, garde-corps, cabine et palan sont dans RadoubDressing.
local GANTRY = {
	legs = { { 110, 124 }, { 336, 350 } },
	beamLow = 103,
	top = 112,
	z0 = 110,
	z1 = 350,
	trolley = { 247, 265, 97, 103, 200, 222 },
	rails = { { z = 117, x1 = 470.5 }, { z = 343, x1 = 436 } }, -- le rail sud s'arrête avant le local du bateau-porte
	railX0 = -60,
	ladderGaps = { { 115, 119 }, { 341, 345 } },
	railH = 3.5 / SCALE, -- main courante à 3,5 studs du monde après l'échelle : on tire par-dessus
}

-- Cette méthode permet de poser la structure porteuse du portique : poteaux, bogies, poutres, passerelle, chariot,
-- échelles dans les pieds.
local function crane()
	local g = GANTRY
	for _, leg in g.legs do
		block(F.walls, 245, 251, QUAY + 5, g.beamLow, leg[1], leg[2], "crane")
		block(F.walls, 261, 267, QUAY + 5, g.beamLow, leg[1], leg[2], "crane")
		block(F.walls, 245, 267, QUAY, QUAY + 5, leg[1] + 3, leg[2] - 3, "crane")
	end
	block(F.floors, 245, 251, g.beamLow, g.top, g.z0, g.z1, "crane")
	block(F.floors, 261, 267, g.beamLow, g.top, g.z0, g.z1, "crane")
	block(F.floors, 251, 261, g.top - 1, g.top, g.z0, g.z1, "grating")
	local t = g.trolley
	block(F.walls, t[1], t[2], t[3], t[4], t[5], t[6], "crane")
	ladder(Vector3.new(245, 0, 117), Vector3.new(-1, 0, 0), QUAY, g.top)
	ladder(Vector3.new(245, 0, 343), Vector3.new(-1, 0, 0), QUAY, g.top)
end

-- Cette méthode permet de poser un bâtiment creux (murs, toit plat) avec ses portes : `doors` = { { côté N/S/E/W,
-- début, fin le long du mur, hauteur } }.
local function hall(x0, x1, z0, z1, h, doors, look)
	local y0, y1 = QUAY, QUAY + h
	local sides = {
		N = { along = "x", a0 = x0, a1 = x1, fixed = { z0, z0 + WALL } },
		S = { along = "x", a0 = x0, a1 = x1, fixed = { z1 - WALL, z1 } },
		W = { along = "z", a0 = z0 + WALL, a1 = z1 - WALL, fixed = { x0, x0 + WALL } },
		E = { along = "z", a0 = z0 + WALL, a1 = z1 - WALL, fixed = { x1 - WALL, x1 } },
	}
	for name, s in sides do
		local cuts = {}
		for _, d in doors do
			if d[1] == name then
				table.insert(cuts, d)
			end
		end
		table.sort(cuts, function(a, b)
			return a[2] < b[2]
		end)
		-- Cette méthode permet de poser un pan de ce mur de a à b, entre les hauteurs ya et yb.
		local function pan(a, b, ya, yb)
			if b - a < 0.05 then
				return
			end
			if s.along == "x" then
				block(F.walls, a, b, ya, yb, s.fixed[1], s.fixed[2], look)
			else
				block(F.walls, s.fixed[1], s.fixed[2], ya, yb, a, b, look)
			end
		end
		local cursor = s.a0
		-- écran intérieur derrière chaque porte : pas de vue directe du dehors vers les points d'apparition (on le
		-- contourne par les côtés)
		local inward = if name == "N" or name == "W" then 1 else -1
		for _, d in cuts do
			pan(cursor, d[2], y0, y1)
			pan(d[2], d[3], y0 + d[4], y1)
			cursor = d[3]
			local c = (if inward > 0 then s.fixed[2] else s.fixed[1]) + inward * SCREEN_GAP
			local a, b = d[2] - SCREEN_OVERLAP, d[3] + SCREEN_OVERLAP
			local f0, f1 = math.min(c, c + inward * WALL), math.max(c, c + inward * WALL)
			if s.along == "x" then
				block(F.walls, a, b, y0, y1, f0, f1, look)
			else
				block(F.walls, f0, f1, y0, y1, a, b, look)
			end
		end
		pan(cursor, s.a1, y0, y1)
	end
	block(F.floors, x0, x1, y1, y1 + 1.5, z0, z1, "roof")
end

-- bâtiments (habillés par RadoubDressing selon `style`) ; doors = { { côté N/S/E/W, début, fin le long du mur,
-- hauteur } }
local HALLS = {}
-- conteneurs { x, z, hauteur au-dessus du quai, couleur } (24 × 10 × 10), piles de tôles { x0, x1, hauteur, z0, z1 }
local CONTAINERS = {
	{ 200, 32, 0, "red" },
	{ 200, 32, 10.2, "blue" },
	{ 228, 46, 0, "ochre" },
	{ 205, 64, 0, "green" },
	{ 232, 78, 0, "red" },
	{ 232, 78, 10.2, "ochre" },
}
local PLATES = {
	-- entre les bâtiments, hors des lignes droites le long de la forme (retour du 20/11/2026)
	{ 198, 218, 4, 92, 106 },
	{ 226, 248, 5, 94, 108 },
	{ 200, 218, 3, 372, 386 },
	{ 224, 246, 6, 376, 390 },
}

-- Cette méthode permet de poser un bâtiment et de le noter pour l'habillage.
local function building(style, x0, x1, z0, z1, h, doors, look, extra)
	hall(x0, x1, z0, z1, h, doors, look)
	local entry = { style = style, x0 = x0, x1 = x1, z0 = z0, z1 = z1, h = h, doors = doors }
	for k, v in extra or {} do
		entry[k] = v
	end
	table.insert(HALLS, entry)
end

-- Cette méthode permet de poser les bâtiments d'angle, la salle des pompes, le local du bateau-porte et les objets des
-- quais (conteneurs, tôles ; les bittes sont dans RadoubDressing).
local function buildings()
	for i, s in { { 30, 195 }, { 275, 440 } } do
		local a, b = s[1], s[2]
		-- ateliers : grande porte vers la forme, portes de côté
		building(
			"atelier",
			a,
			b,
			25,
			110,
			38,
			{ { "S", a + 55, a + 105, 26 }, { "E", 40, 60, 12 }, { "W", 60, 75, 12 } },
			"clad",
			{ number = string.format("%02d", i) }
		)
		-- magasins : porte vers la forme, portes de côté
		building(
			"magasin",
			a,
			b,
			350,
			435,
			30,
			{ { "N", a + 60, a + 100, 20 }, { "E", 400, 415, 12 }, { "W", 400, 415, 12 } },
			"precast",
			{ number = string.format("%02d", i + 2) }
		)
	end
	building(
		"pompes",
		PUMP_X0,
		PUMP_X1,
		160,
		300,
		24,
		{ { "E", 222, 238, 12 }, { "N", 20, 35, 12 } },
		"brick",
		{ chimney = { x = PUMP_X0 + 27, z = 178, top = QUAY + 52 } }
	)
	building("local", 438, 470, 312, 346, 16, { { "W", 322, 334, 10 }, { "N", 448, 460, 10 } }, "clad")
	for _, c in CONTAINERS do
		block(F.walls, c[1], c[1] + 24, QUAY + c[3], QUAY + c[3] + 10, c[2], c[2] + 10, c[4])
	end
	-- piles de tôles (couverts bas) : volume porteur invisible, lits de tôles dessinés par l'habillage
	for _, t in PLATES do
		local p = block(F.decor, t[1], t[2], QUAY, QUAY + t[3], t[4], t[5], "steel")
		p.Transparency = 1
		p.CastShadow = false
	end
end

-- Points d'apparition -----------------------------------------------------------------------------------------------

-- 6 zones de 3 points, à l'intérieur des bâtiments (aucune vue entre zones, contrôlé par SpawnSight). Regard vers la
-- porte de la zone.
local SPAWNS = {
	{ zone = "AtelierOuest", look = { 1, 1 }, points = { { 60, 85 }, { 72, 85 }, { 60, 95 } } },
	{ zone = "AtelierEst", look = { -1, 1 }, points = { { 400, 85 }, { 412, 85 }, { 412, 95 } } },
	{ zone = "MagasinOuest", look = { 1, -1 }, points = { { 60, 410 }, { 72, 410 }, { 60, 420 } } },
	{ zone = "MagasinEst", look = { 1, -1 }, points = { { 300, 415 }, { 312, 415 }, { 300, 425 } } },
	{ zone = "Pompes", look = { 1, -1 }, points = { { PUMP_X0 + 27, 270 }, { PUMP_X0 + 20, 282 }, { PUMP_X0 + 34, 282 } } },
	{ zone = "BateauPorte", look = { -1, 0 }, points = { { 454, 329 }, { 460, 338 }, { 460, 320 } } },
}

-- Cette méthode permet de poser les points d'apparition des zones ; renvoie leur nombre.
local function spawns()
	local n = 0
	for _, z in SPAWNS do
		for _, pt in z.points do
			n += 1
			local pos = Vector3.new(pt[1], QUAY + MapBuild.SPAWN_SKIN + 0.5, pt[2])
			local cf = aim(pos, Vector3.new(z.look[1], 0, z.look[2]))
			MapBuild.spawnPoint(F.spawns, string.format("FFA%02d", n), PLACE * cf, "FFA", z.zone)
		end
	end
	return n
end

MapBuild.checkSun()
land()
dock()
ship()
gangway(60, 95, 230)
gangway(460, 415, 230)
ladder(Vector3.new(460, 0, 230), Vector3.new(-1, 0, 0), 0, QUAY)
crane()
buildings()
local spawnCount = spawns()
local bollards, containers = {}, {}
for _, c in CONTAINERS do
	table.insert(containers, { c[1], c[2], c[3], LOOK[c[4]][1] })
end
for x = 80, 400, 80 do
	table.insert(bollards, { x, 146 })
	table.insert(bollards, { x, 314 })
end
RadoubDressing.build({
	map = map,
	place = PLACE,
	quay = QUAY,
	deck = DECK,
	sea = SEA,
	wall = WALL,
	halls = HALLS,
	hangar = { x0 = -150, x1 = -60, z0 = -30, z1 = 470, h = 90, doorZ = 230, doorW = 120, doorH = 66 },
	sections = SECTIONS,
	draftMarks = { { 99 }, {}, { 404 } },
	openEnds = { { 200, 1 }, { 215, -1 }, { 315, 1 }, { 330, -1 } },
	hatches = HATCHES,
	gantry = GANTRY,
	containers = containers,
	plates = PLATES,
	bollards = bollards,
	masts = { { -50, 140 }, { 466, 136 }, { -50, 320 }, { 466, 354 } }, -- aux angles, hors des voies de course
	mastTarget = Vector3.new(260, 20, 230),
	dock = {
		sections = SECTIONS,
		x0 = 60,
		x1 = 460,
		toeN = 192,
		toeS = 268,
		ramp = { x0 = 60, x1 = 74, z0 = 150, z1 = 246 },
	},
	gate = {
		x0 = 460,
		x1 = 472,
		z0 = 150,
		z1 = 310,
		freeZ0 = 196,
		freeZ1 = 264,
		stiffeners = { 200, 208, 216, 224, 236, 244, 252, 260 },
	},
	quays = {
		x0 = -60,
		x1 = 472,
		z0 = -30,
		z1 = 470,
		crestN = 150,
		crestS = 310,
		dockX0 = 60,
		dockX1 = 460,
		rails = GANTRY.rails,
	},
})

-- Cette méthode permet d'agrandir toute la map de SCALE autour du centre posé (positions et tailles ; points
-- d'apparition gardés en vraie grandeur, face basse remise à SPAWN_SKIN du sol agrandi ; portée des lampes).
local function scaleMap()
	local pivot = OFFSET + CENTER
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local pos = pivot + (cf.Position - pivot) * SCALE
			if d.Parent == F.spawns then
				local bottom = cf.Position.Y - d.Size.Y / 2 - MapBuild.SPAWN_SKIN
				pos = Vector3.new(pos.X, bottom * SCALE + MapBuild.SPAWN_SKIN + d.Size.Y / 2, pos.Z)
			else
				d.Size = d.Size * SCALE
			end
			d.CFrame = (cf - cf.Position) + pos
		elseif d:IsA("SpotLight") then
			d.Range = math.min(60, d.Range * SCALE)
		end
	end
end
scaleMap()

-- Ombres sans intérêt au soleil rasant (retour du 20/11/2026) : une pièce linéaire (rails, poteaux, garde-corps,
-- acrotères, raidisseurs) ou un petit objet traîne une longue ombre fine sur le quai sans rien dessiner.
local THIN_SHADOW, SMALL_SHADOW = 3, 5 -- studs du monde : deuxième et plus grande dimension
local thinCut = 0
for _, p in map:GetDescendants() do
	if p:IsA("BasePart") and p.CastShadow then
		local s = { p.Size.X, p.Size.Y, p.Size.Z }
		table.sort(s)
		if s[2] < THIN_SHADOW or s[3] < SMALL_SHADOW then
			p.CastShadow = false
			thinCut += 1
		end
	end
end
print(string.format("  ombres : %d pièces fines ou petites coupées", thinCut))

-- rampes de surf : une seule pièce en surface, rien en travers dessous (#136), puis mesure de contrôle
for _, r in RampEdges.apply(geometry) do
	print(
		string.format(
			"  rampe (%.0f, %.0f, %.0f) : peau d'acier (%+.3f), %d pièce(s) rognée(s) en %d (plus haut rebord rogné : %.3f)",
			r.center[1],
			r.center[2],
			r.center[3],
			r.surface,
			r.trimmed,
			r.placed,
			r.rise
		)
	)
end
local sightTested, sightVisible = SpawnSight.check(map)
print(string.format("  vues entre zones d'apparition : %d paire(s) testée(s), %d visible(s)", sightTested, #sightVisible))
if #sightVisible > 0 or sightTested == 0 then
	for _, v in sightVisible do
		print(string.format("  VU : %s <-> %s", v.a, v.b))
	end
	error("zones d'apparition qui se voient, ou aucune paire testée : map non écrite")
end
local rampLines, rampWorst = RampCheck.check(map)
print(table.concat(rampLines, "\n"))
if rampWorst > RampCheck.TOL then
	error(
		string.format(
			"rebord, creux ou trou de %.3f stud sur une rampe de surf (tolérance %.2f), map non écrite",
			rampWorst,
			RampCheck.TOL
		)
	)
end
local small, culled, kept = MapBuild.cullShadows(map)
print(string.format("  ombres : %d petites pièces et %d pièces masquées coupées, %d gardées", small, culled, kept))
fs.writeFile(OUT, roblox.serializeModel({ map }))
local count = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("Radoub : %d pièces, %d spawns, KillHeight %d -> %s", count, spawnCount, KILL_HEIGHT * SCALE, OUT))

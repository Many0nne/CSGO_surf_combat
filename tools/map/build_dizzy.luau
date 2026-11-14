--!nocheck
-- Générateur de Dizzy (map par défaut, d'après ar_dizzy), exécuté dans Lune sans Studio :
--   lune run tools/map/build_dizzy.luau      (racine du worktree, plugin Rojo déconnecté de ce serveur)
-- Lit le plan relevé tools/map/dizzy_layout.json (tools/map/extract_dizzy.py, à ne pas éditer à la main), applique les
-- retouches locales de tools/map/dizzy_patches.luau et écrit assets/rbx/Maps/Dizzy.rbxm (Workspace.Maps.Dizzy).
-- Habillage à nous (béton, enduit, acier, crépuscule), cf. docs/maps.md.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local DizzyDressing = require("./DizzyDressing")
local DizzyPatches = require("./DizzyPatches")
local RampCheck = require("./RampCheck")
local RampEdges = require("./RampEdges")
local ShadowCulling = require("./ShadowCulling")

local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local LAYOUT = "tools/map/dizzy_layout.json"
local OUT = "assets/rbx/Maps/Dizzy.rbxm"
-- Décalage de la map : ne pas se superposer à une autre map de Workspace.Maps en mode Edit
local OFFSET = Vector3.new(2000, 0, 0)

-- Ombres (cf. docs/performance.md) : direction vers le soleil pour Lighting.ClockTime 17,9 et GeographicLatitude 0
-- (Lighting:GetSunDirection() relevé dans Studio). Changer l'heure ou la latitude (default.project.json)
-- oblige à la relever de nouveau : le générateur refuse de tourner si default.project.json ne correspond plus.
local SUN_CLOCK, SUN_LATITUDE = 17.9, 0
local SUN = { -0.9167592525482178, 0.024006040766835213, -0.39871811866760254 }
local SMALL_SHADOW = 2 -- studs : une pièce plus petite que ça dans toutes ses dimensions ne projette pas d'ombre

-- Habillage par rôle de face (relevé par extract_dizzy.py) : couleur, matière
local CONCRETE = Color3.fromRGB(150, 140, 128)
local PLASTER = Color3.fromRGB(222, 218, 206) -- enduit blanc cassé des murs (#189, beige avant)
local SHADOW = Color3.fromRGB(112, 100, 92)
local STEEL = Color3.fromRGB(70, 74, 82)
local GLOW = Color3.fromRGB(255, 170, 110)
local LOOK = {
	floor = { CONCRETE, Enum.Material.Concrete },
	slope = { CONCRETE, Enum.Material.Concrete },
	wall = { PLASTER, Enum.Material.Plaster },
	ceiling = { SHADOW, Enum.Material.Plaster },
	surf = { STEEL, Enum.Material.DiamondPlate },
	-- bois de chantier, posé par les retouches (dizzy_patches.luau) : contreplaqué des rampes, planches sur la fosse,
	-- charpente sous les rampes
	plywood = { Color3.fromRGB(206, 170, 118), Enum.Material.Wood },
	planks = { Color3.fromRGB(170, 126, 82), Enum.Material.WoodPlanks },
	timber = { Color3.fromRGB(128, 94, 64), Enum.Material.Wood },
}
-- Blocs de décor : d'après le groupe de surface source
local DECOR = {
	metal = { STEEL, Enum.Material.Metal },
	metalvent = { Color3.fromRGB(120, 124, 128), Enum.Material.CorrodedMetal },
	plastic = { Color3.fromRGB(60, 62, 66), Enum.Material.SmoothPlastic },
	rock = { Color3.fromRGB(118, 108, 98), Enum.Material.Slate },
	carpet = { Color3.fromRGB(90, 46, 40), Enum.Material.Fabric },
	tile = { Color3.fromRGB(200, 196, 188), Enum.Material.Marble },
	stucco = { PLASTER, Enum.Material.Plaster },
	concrete = { CONCRETE, Enum.Material.Concrete },
	sheetrock = { PLASTER, Enum.Material.Plaster },
	chainlink = { STEEL, Enum.Material.Metal },
	passbullets_chainlink = { STEEL, Enum.Material.Metal },
}
local FOLDERS = {
	floor = "Floors",
	slope = "Floors",
	wall = "Walls",
	ceiling = "Ceilings",
	surf = "Ramps",
	block = "Decor",
	clip = "Clips",
}

-- Cette méthode permet de créer (ou retrouver) un dossier enfant lorsqu'on range les pièces de la map par rôle.
local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

-- Cette méthode permet de rendre une pièce purement décorative : sans collision ni requête (les raycasts du
-- mouvement la prendraient sinon pour un mur ou une rampe).
local function ghost(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Cette méthode permet d'habiller une pièce selon son rôle (floor, slope, wall, ceiling, surf, clip) ou son groupe de
-- décor (decor:<groupe>), pour le plan relevé comme pour les retouches de dizzy_patches.luau.
local function style(p, look)
	p.Transparency = 0
	p.CastShadow = true
	if look == "clip" then
		-- mur d'air (playerclip, func_brush) : invisible mais bloquant ; CanQuery reste vrai, le mouvement détecte les
		-- collisions par raycast
		p.Transparency = 1
		p.CastShadow = false
		p.Name = "Clip"
		return
	end
	local group = string.match(look, "^decor:(.+)$")
	local spec = if group then DECOR[group] or DECOR.metal else LOOK[look]
	assert(spec, "habillage inconnu : " .. tostring(look))
	p.Color = spec[1]
	p.Material = spec[2]
	p.Name = if group then "block" else look
	if group == "chainlink" or group == "passbullets_chainlink" then
		p.Transparency = 0.55
	end
end

-- Cette méthode permet de poser une pièce ancrée (Part ou WedgePart) à partir d'une entrée du plan relevé.
local function place(entry, parent)
	local group, role, wedge = entry[1], entry[2], entry[3]
	local p = Instance.new(if wedge == 1 then "WedgePart" else "Part")
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local pos = Vector3.new(entry[4], entry[5], entry[6]) + OFFSET
	local x = Vector3.new(entry[7], entry[8], entry[9])
	local y = Vector3.new(entry[10], entry[11], entry[12])
	local z = Vector3.new(entry[13], entry[14], entry[15])
	p.CFrame = CFrame.fromMatrix(pos, x, y, z)
	p.Size = Vector3.new(entry[16], entry[17], entry[18])
	style(p, if role == "block" then "decor:" .. group else role)
	if role == "block" then
		-- groupe source, pour viser une structure sans les objets posés dessous (champ `group` des retouches)
		p:SetAttribute("Group", group)
	end
	p.Parent = folder(parent, FOLDERS[role] or "Decor")
	return p
end

-- Cette méthode permet d'habiller le dessous du toit : fût de la tour (bandes de fenêtres allumées) et mer de nuages,
-- sans collision, la mort par chute (KillHeight) se déclenchant avant.
local function underside(parent, data)
	local deco = folder(parent, "Underside")
	local s = data.shaft
	local x0, x1, z0, z1 = s[1], s[2], s[3], s[4]
	local top = data.cutY
	local depth = 1400
	local shaft = ghost(Instance.new("Part"))
	shaft.Anchored = true
	shaft.Size = Vector3.new(x1 - x0, depth, z1 - z0)
	shaft.CFrame = CFrame.new(Vector3.new((x0 + x1) / 2, top - depth / 2, (z0 + z1) / 2) + OFFSET)
	shaft.Color = PLASTER
	shaft.Material = Enum.Material.Plaster
	shaft.Name = "Shaft"
	shaft.Parent = deco
	-- bandes de fenêtres tous les 28 studs (un étage = 4 m), une sur trois allumée
	local floorH = 4 * data.scale.v
	local n = 0
	for y = top - 10, top - depth + 40, -floorH do
		n += 1
		local lit = n % 3 == 0
		local band = ghost(Instance.new("Part"))
		band.Anchored = true
		band.Size = Vector3.new(x1 - x0 + 0.6, floorH * 0.45, z1 - z0 + 0.6)
		band.CFrame = CFrame.new(Vector3.new((x0 + x1) / 2, y, (z0 + z1) / 2) + OFFSET)
		band.Color = if lit then GLOW else Color3.fromRGB(34, 38, 52)
		band.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
		band.Transparency = if lit then 0.35 else 0
		band.Name = "Windows"
		band.Parent = deco
	end
	-- mer de nuages : nappes translucides sous le toit, au-dessus de la hauteur de mort. Deux nappes (quatre avant
	-- #88) : chaque nappe se dessine sur tout l'écran quand on regarde vers le bas. Opacité cumulée gardée
	-- (0,42 × 0,55 ≈ 0,55 × 0,65 × 0,75 × 0,85).
	local cloudY = data.killY + 6
	for i, transparency in { 0.42, 0.55 } do
		local sheet = ghost(Instance.new("Part"))
		sheet.Anchored = true
		sheet.Size = Vector3.new(3000, 2, 3000)
		sheet.CFrame = CFrame.new(Vector3.new(0, cloudY - (i - 1) * 36, -260) + OFFSET)
		sheet.Color = Color3.fromRGB(226, 170, 150)
		sheet.Material = Enum.Material.SmoothPlastic
		sheet.Transparency = transparency
		sheet.CastShadow = false
		sheet.Name = "Clouds"
		sheet.Parent = deco
	end
end

-- Points d'apparition ajoutés (#329) : SpawnPointRules choisit un point loin et hors de vue des ennemis, et deux grappes
-- (bases T et CT) ne lui laissaient presque pas de choix. Zones choisies hors de vue l'une de l'autre et des bases
-- (tools/map/spawn_sight.luau), accessibles à pied aller et retour (le plan des bots ne garde que la partie reliée au
-- premier point). Coordonnées du plan sans le décalage, y = dessus du sol ; regard horizontal vers la sortie de la
-- zone. Décrites côté T, recopiées côté CT par le demi-tour de la map autour de (0, -260,1) (cf. DizzyDressing.mirror).
local FFA_SPAWNS = {
	{
		zone = "BalconSud",
		mirror = "BalconNord",
		floor = 48.1045,
		look = { -1, 0 },
		points = { { -38.486, -506.212 }, { -38.486, -517.428 }, { -38.486, -494.995 } },
	},
	{
		zone = "ToitT",
		mirror = "ToitCT",
		floor = 96.1105,
		look = { 1, 0 },
		points = { { -241.037, -261.783 }, { -230.668, -256.516 }, { -241.037, -251.249 } },
	},
}
local MIRROR_Z = -260.1 -- centre du demi-tour de la map (z), en x : 0
local SPAWN_SKIN = 0.029 -- studs : face basse du point au-dessus du sol, comme les points T/CT relevés

-- Cette méthode permet de poser un point d'apparition au sol (pièce invisible sans collision, regard horizontal) lorsque
-- le générateur remplit GroundSpawns.
local function spawnPoint(f, name, center, lookX, lookZ, team, zone)
	local p = ghost(Instance.new("Part"))
	p.Anchored = true
	p.Transparency = 1
	p.Size = Vector3.new(2, 1, 2)
	p.CFrame = CFrame.lookAt(center, center + Vector3.new(lookX, 0, lookZ))
	p.Name = name
	p:SetAttribute("Team", team)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	p.Parent = f
end

-- Cette méthode permet de poser les points d'apparition au sol : info_player_* de l'original (attribut Team T ou CT,
-- point mis au niveau du sol, 0,406 m sous l'origine source), puis les zones FFA_SPAWNS des deux côtés de la map
-- (#329). Le joueur apparaît 5 studs au-dessus du point (SpawnManager). Renvoie le nombre de points.
local function spawns(parent, data)
	local f = folder(parent, "GroundSpawns")
	for i, s in data.spawns do
		local feet = Vector3.new(s[2], s[3] - 0.406 * data.scale.v + 0.5, s[4]) + OFFSET
		spawnPoint(f, string.format("%s%02d", s[1], i), feet, s[5], s[6], s[1], nil)
	end
	local n = 0
	for _, z in FFA_SPAWNS do
		local y = z.floor + SPAWN_SKIN + 0.5
		for _, side in { { z.zone, 1 }, { z.mirror, -1 } } do
			local sign = side[2]
			for _, pt in z.points do
				-- côté CT : demi-tour autour de (0, MIRROR_Z), le regard tourne avec
				local x = sign * pt[1]
				local zz = if sign == 1 then pt[2] else 2 * MIRROR_Z - pt[2]
				n += 1
				local center = Vector3.new(x, y, zz) + OFFSET
				spawnPoint(f, string.format("FFA%02d", n), center, sign * z.look[1], sign * z.look[2], "FFA", side[1])
			end
		end
	end
	return #data.spawns + n
end

-- Cette méthode permet de vérifier que l'heure et la latitude de default.project.json sont celles du soleil SUN
-- lorsque le générateur va couper des ombres d'après sa direction.
local function checkSun()
	local project = serde.decode("json", fs.readFile("default.project.json"))
	local props = project.tree.Lighting["$properties"]
	assert(
		props.ClockTime == SUN_CLOCK and props.GeographicLatitude == SUN_LATITUDE,
		"Lighting de default.project.json ≠ soleil de build_dizzy.luau : relever SUN dans Studio (GetSunDirection)"
	)
end

-- Cette méthode permet de couper CastShadow là où l'ombre ne se voit pas lorsque la map est complète : petites
-- pièces, puis pièces entièrement à l'ombre des autres (ShadowCulling). Renvoie (petites, masquées, gardées).
local function cullShadows(map)
	local parts, boxes, occluders, candidates = {}, {}, {}, {}
	local small = 0
	for _, p in map:GetDescendants() do
		if p:IsA("BasePart") and p.CastShadow then
			local s = p.Size
			if math.max(s.X, s.Y, s.Z) < SMALL_SHADOW then
				p.CastShadow = false
				small += 1
			else
				table.insert(parts, p)
				table.insert(boxes, RampCheck.box(p))
				local i = #boxes
				candidates[i] = true
				-- seules les vraies boîtes et les coins arrêtent la lumière (un cylindre traité en boîte masquerait trop)
				occluders[i] = p.Transparency == 0
					and (p.ClassName == "WedgePart" or (p.ClassName == "Part" and p.Shape == Enum.PartType.Block))
			end
		end
	end
	local hidden = ShadowCulling.shadowed(boxes, occluders, candidates, SUN)
	local culled = 0
	for i in hidden do
		parts[i].CastShadow = false
		culled += 1
	end
	return small, culled, #parts - culled
end

checkSun()
local data = serde.decode("json", fs.readFile(LAYOUT))
local map = Instance.new("Model")
map.Name = "Dizzy"
map:SetAttribute("KillHeight", data.killY)
map:SetAttribute("GeneratedBy", "build_dizzy")
local geometry = folder(map, "Geometry")
for _, entry in data.parts do
	place(entry, geometry)
end
-- retouches locales (tools/map/dizzy_patches.luau), après le plan relevé et avant le décor du dessous
local patches = require("./dizzy_patches")
local counts = DizzyPatches.apply(geometry, patches, style)
for i, p in patches do
	print(string.format("  retouche %d (%s) : %s, %d pièce(s)", i, p.why, p.op, counts[i]))
end
-- rampes de surf : rien ne dépasse de la surface de glisse (#136), puis mesure de contrôle sur la map complète
for _, r in RampEdges.apply(geometry) do
	print(
		string.format(
			"  rampe (%.0f, %.0f, %.0f) : peau d'acier au niveau des rives (%+.3f), %d pièce(s) rognée(s) en %d"
				.. " (plus haut rebord rogné : %.3f)",
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
local dressed = DizzyDressing.build(map, OFFSET)
underside(map, data)
local spawnCount = spawns(map, data)
local rampLines, rampWorst = RampCheck.check(map)
if rampWorst > RampCheck.TOL then
	-- bilan en entier (un message d'erreur long est tronqué), puis arrêt avant d'écrire la map
	print(table.concat(rampLines, "\n"))
	error(
		string.format(
			"rebord, creux ou trou de %.3f stud sur une rampe de surf (tolérance %.2f), map non écrite",
			rampWorst,
			RampCheck.TOL
		)
	)
end
local t0 = os.clock()
local small, culled, kept = cullShadows(map)
print(
	string.format(
		"  ombres : %d petites pièces et %d pièces masquées coupées, %d gardées (%.1f s)",
		small,
		culled,
		kept,
		os.clock() - t0
	)
)
fs.writeFile(OUT, roblox.serializeModel({ map }))
print(
	string.format(
		"Dizzy : %d pièces relevées, %d retouche(s), %d objets d'habillage, %d spawns, KillHeight %.1f -> %s",
		#data.parts,
		#patches,
		dressed,
		spawnCount,
		data.killY,
		OUT
	)
)

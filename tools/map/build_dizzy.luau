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

local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local LAYOUT = "tools/map/dizzy_layout.json"
local OUT = "assets/rbx/Maps/Dizzy.rbxm"
-- Décalage de la map : ne pas se superposer à une autre map de Workspace.Maps en mode Edit
local OFFSET = Vector3.new(2000, 0, 0)

-- Habillage par rôle de face (relevé par extract_dizzy.py) : couleur, matière
local CONCRETE = Color3.fromRGB(150, 140, 128)
local PLASTER = Color3.fromRGB(196, 176, 152)
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
	-- mer de nuages : nappes translucides sous le toit, au-dessus de la hauteur de mort
	local cloudY = data.killY + 6
	for i = 0, 3 do
		local sheet = ghost(Instance.new("Part"))
		sheet.Anchored = true
		sheet.Size = Vector3.new(3000, 2, 3000)
		sheet.CFrame = CFrame.new(Vector3.new(0, cloudY - i * 18, -260) + OFFSET)
		sheet.Color = Color3.fromRGB(226, 170, 150)
		sheet.Material = Enum.Material.SmoothPlastic
		sheet.Transparency = 0.55 + i * 0.1
		sheet.CastShadow = false
		sheet.Name = "Clouds"
		sheet.Parent = deco
	end
end

-- Cette méthode permet de poser les points d'apparition au sol (info_player_* de l'original) : le joueur apparaît
-- 5 studs au-dessus du point (SpawnManager), le point est mis au niveau du sol (0,406 m sous l'origine source).
local function spawns(parent, data)
	local f = folder(parent, "GroundSpawns")
	for i, s in data.spawns do
		local p = ghost(Instance.new("Part"))
		p.Anchored = true
		p.Transparency = 1
		p.Size = Vector3.new(2, 1, 2)
		local feet = Vector3.new(s[2], s[3] - 0.406 * data.scale.v + 0.5, s[4]) + OFFSET
		p.CFrame = CFrame.lookAt(feet, feet + Vector3.new(s[5], 0, s[6]))
		p.Name = string.format("%s%02d", s[1], i)
		p:SetAttribute("Team", s[1])
		p.Parent = f
	end
end

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
local dressed = DizzyDressing.build(map, OFFSET)
underside(map, data)
spawns(map, data)
fs.writeFile(OUT, roblox.serializeModel({ map }))
print(
	string.format(
		"Dizzy : %d pièces relevées, %d retouche(s), %d objets d'habillage, %d spawns, KillHeight %.1f -> %s",
		#data.parts,
		#patches,
		dressed,
		#data.spawns,
		data.killY,
		OUT
	)
)

--!nocheck
-- MapBuild.luau
-- Outils communs aux générateurs de maps (build_dizzy.luau, build_radoub.luau), exécutés dans Lune sans Studio :
-- dossiers, pièces décoratives, direction du soleil, coupe des ombres invisibles, points d'apparition.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local RampCheck = require("./RampCheck")
local ShadowCulling = require("./ShadowCulling")

local Enum = roblox.Enum
local Instance = roblox.Instance

local MapBuild = {}

-- Ombres (cf. docs/performance.md) : direction vers le soleil pour Lighting.ClockTime 17,9 et GeographicLatitude 0
-- (Lighting:GetSunDirection() relevé dans Studio). Changer l'heure ou la latitude (default.project.json)
-- oblige à la relever de nouveau : les générateurs refusent de tourner si default.project.json ne correspond plus.
MapBuild.SUN_CLOCK, MapBuild.SUN_LATITUDE = 17.9, 0
MapBuild.SUN = { -0.9167592525482178, 0.024006040766835213, -0.39871811866760254 }
MapBuild.SMALL_SHADOW = 2 -- studs : une pièce plus petite que ça dans toutes ses dimensions ne projette pas d'ombre
MapBuild.SPAWN_SKIN = 0.029 -- studs : face basse d'un point d'apparition au-dessus du sol (SpawnCheck)

-- Cette méthode permet de créer (ou retrouver) un dossier enfant lorsqu'on range les pièces de la map par rôle.
function MapBuild.folder(parent, name)
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
function MapBuild.ghost(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Cette méthode permet de vérifier que l'heure et la latitude de default.project.json sont celles du soleil SUN
-- lorsque le générateur va couper des ombres d'après sa direction.
function MapBuild.checkSun()
	local project = serde.decode("json", fs.readFile("default.project.json"))
	local props = project.tree.Lighting["$properties"]
	assert(
		props.ClockTime == MapBuild.SUN_CLOCK and props.GeographicLatitude == MapBuild.SUN_LATITUDE,
		"Lighting de default.project.json ≠ soleil de MapBuild.luau : relever SUN dans Studio (GetSunDirection)"
	)
end

-- Cette méthode permet de couper CastShadow là où l'ombre ne se voit pas lorsque la map est complète : petites
-- pièces, puis pièces entièrement à l'ombre des autres (ShadowCulling). Renvoie (petites, masquées, gardées).
function MapBuild.cullShadows(map)
	local parts, boxes, occluders, candidates = {}, {}, {}, {}
	local small = 0
	for _, p in map:GetDescendants() do
		if p:IsA("BasePart") and p.CastShadow then
			local s = p.Size
			if math.max(s.X, s.Y, s.Z) < MapBuild.SMALL_SHADOW then
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
	local hidden = ShadowCulling.shadowed(boxes, occluders, candidates, MapBuild.SUN)
	local culled = 0
	for i in hidden do
		parts[i].CastShadow = false
		culled += 1
	end
	return small, culled, #parts - culled
end

-- Cette méthode permet de poser un point d'apparition au sol (pièce invisible sans collision, repère `cf`) lorsque le
-- générateur remplit GroundSpawns.
function MapBuild.spawnPoint(f, name, cf, team, zone)
	local p = MapBuild.ghost(Instance.new("Part"))
	p.Anchored = true
	p.Transparency = 1
	p.Size = roblox.Vector3.new(2, 1, 2)
	p.CFrame = cf
	p.Name = name
	p:SetAttribute("Team", team)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	p.Parent = f
end

return MapBuild

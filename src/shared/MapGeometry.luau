-- Dossiers d'une map lus par le code (#292) et règle des balles : les murs d'air (Geometry.Clips, invisibles) et les
-- boîtes des grillages `passbullets` arrêtent le mouvement (CanCollide inchangé) mais pas les balles ni le regard des
-- bots. Les rayons de tir (client, ligne de vue serveur, bots) et de vue des bots les écartent tous par ce module :
-- bulletTransparent pour une liste d'exclusion, includeAllBut pour une liste d'inclusion.
-- Sans dépendance : relu aussi par tools/rbxm/verify_place.luau (dossiers attendus dans chaque map).

local MapGeometry = {}

MapGeometry.GEOMETRY = "Geometry" -- pièces relevées, rangées par rôle (cf. tools/map/build_dizzy.luau, FOLDERS)
MapGeometry.CLIPS = "Clips" -- murs d'air, dans Geometry
MapGeometry.RAMPS = "Ramps" -- rampes de surf, dans Geometry (BotConfig.RAMPS_FOLDER)
MapGeometry.GROUND_SPAWNS = "GroundSpawns" -- points d'apparition au sol
MapGeometry.LADDERS = "Ladders" -- volumes d'échelle (LadderRules.LADDERS_FOLDER)

-- Attribut posé par le générateur sur une boîte de décor (groupe du relevé), et groupes que les balles traversent
MapGeometry.GROUP_ATTRIBUTE = "Group"
MapGeometry.PASSBULLETS_GROUPS = { passbullets_chainlink = true } :: { [string]: boolean }

-- Dossiers que le code lit dans chaque map, chemin depuis la map : un renommage fait échouer verify_place (CI)
MapGeometry.REQUIRED_FOLDERS = {
	{ MapGeometry.GEOMETRY, MapGeometry.CLIPS },
	{ MapGeometry.GEOMETRY, MapGeometry.RAMPS },
	{ MapGeometry.GROUND_SPAWNS },
	{ MapGeometry.LADDERS },
} :: { { string } }

-- Dernière liste calculée et sa map (une seule map jouée par serveur ; référence forte : une clé faible pourrait être
-- recalculée à chaque tir)
local cachedMap: Instance? = nil
local cachedList: { Instance } = {}

-- Cette méthode permet de retrouver le dossier des murs d'air d'une map lorsqu'un rayon doit les écarter (nil si la map
-- n'en a pas).
function MapGeometry.clips(map: Instance): Instance?
	local geometry = map:FindFirstChild(MapGeometry.GEOMETRY)
	return if geometry then geometry:FindFirstChild(MapGeometry.CLIPS) else nil
end

-- Cette méthode permet de savoir si une boîte de décor laisse passer les balles lorsqu'on liste les pièces à écarter des
-- tirs : groupe du relevé dans PASSBULLETS_GROUPS.
function MapGeometry.passesBullets(inst: Instance): boolean
	local group = inst:GetAttribute(MapGeometry.GROUP_ATTRIBUTE)
	return type(group) == "string" and MapGeometry.PASSBULLETS_GROUPS[group] == true
end

-- Cette méthode permet de lister ce que les balles et le regard traversent dans une map lorsqu'on prépare un rayon : le
-- dossier des murs d'air, puis les pièces des grillages `passbullets`. Calculée une fois par map (map statique).
function MapGeometry.bulletTransparent(map: Instance): { Instance }
	if cachedMap and cachedMap == map then
		return cachedList
	end
	local list: { Instance } = {}
	local clips = MapGeometry.clips(map)
	if clips then
		table.insert(list, clips)
	end
	local geometry = map:FindFirstChild(MapGeometry.GEOMETRY)
	for _, inst in if geometry then geometry:GetDescendants() else {} do
		if inst:IsA("BasePart") and MapGeometry.passesBullets(inst) and not (clips and inst:IsDescendantOf(clips)) then
			table.insert(list, inst)
		end
	end
	cachedMap, cachedList = map, list
	return list
end

-- Cette méthode permet de lister ce qu'un rayon en inclusion doit garder lorsqu'il vise toute la map sauf `ignored` :
-- les enfants de `root` sans élément écarté sont gardés entiers, ceux qui en contiennent sont parcourus (liste courte :
-- seuls les ancêtres des éléments écartés sont détaillés).
function MapGeometry.includeAllBut(root: Instance, ignored: { Instance }): { Instance }
	-- Comparaisons par == et IsDescendantOf, pas de table indexée par instance (identité non garantie hors Roblox, Lune)
	local include: { Instance } = {}
	-- Cette méthode permet de parcourir un niveau de l'arbre lorsqu'il contient un élément écarté : chaque enfant est
	-- écarté, détaillé (il contient un élément écarté) ou gardé entier.
	local function visit(node: Instance)
		for _, child in node:GetChildren() do
			local skipped, holds = false, false
			for _, inst in ignored do
				if inst == child then
					skipped = true
					break
				end
				holds = holds or inst:IsDescendantOf(child)
			end
			if holds and not skipped then
				visit(child)
			elseif not skipped then
				table.insert(include, child)
			end
		end
	end
	visit(root)
	return include
end

-- Cette méthode permet de lister les dossiers attendus absents d'une map lorsque verify_place contrôle la place
-- (chemins « Geometry.Clips », vide si tout y est).
function MapGeometry.missingFolders(map: Instance): { string }
	local missing = {}
	for _, path in MapGeometry.REQUIRED_FOLDERS do
		local node: Instance? = map
		for _, name in path do
			node = if node then node:FindFirstChild(name) else nil
		end
		if not node or node:IsA("BasePart") then
			table.insert(missing, table.concat(path, "."))
		end
	end
	return missing
end

return MapGeometry

-- Dossiers d'une map lus par le code (#292) et règle des balles : les murs d'air (Geometry.Clips, invisibles) et les
-- boîtes des grillages `passbullets` arrêtent le mouvement (CanCollide inchangé) mais pas les balles ni le regard des
-- bots. Les rayons de tir (client, ligne de vue serveur, bots) et de vue des bots les écartent tous par ce module :
-- bulletTransparent pour une liste d'exclusion, castThrough (rayon relancé derrière) pour un rayon en inclusion.
-- Liste gardée par map (#605) et préparée en tâche de fond dès qu'une map est jouée ou annoncée (prepare) : le premier
-- tir sur une nouvelle map ne parcourt plus ses ~20 000 pièces.
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

-- Rayon en inclusion relancé à cette distance (studs) derrière une pièce traversée, au plus MAX_PASSES fois
MapGeometry.PASS_STEP = 0.01
MapGeometry.MAX_PASSES = 16

-- Repère de la préparation en tâche de fond (MicroProfiler, sonde serveur, overlay F3 ; cf. docs/performance.md)
MapGeometry.PREPARE_MARKER = "map géométrie"

-- Liste de chaque map, calculée une fois (maps statiques, rangées sans être détruites entre deux rounds ; clés fortes :
-- une clé faible pourrait être recalculée à chaque tir)
local cache: { [Instance]: { Instance } } = {}
-- Maps dont la liste est en cours de préparation en tâche de fond (prepare avec step)
local preparing: { [Instance]: boolean } = {}

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

-- Cette méthode permet de visiter les descendants d'une instance dans l'ordre de GetDescendants lorsque la liste d'une
-- map est préparée en tâche de fond : step appelé après chaque visite (il peut céder la main).
local function eachDescendant(root: Instance, visit: (Instance) -> (), step: (() -> ())?)
	for _, child in root:GetChildren() do
		visit(child)
		if step then
			step()
		end
		eachDescendant(child, visit, step)
	end
end

-- Cette méthode permet de calculer la liste d'une map une fois pour toutes lorsqu'elle est jouée ou annoncée (#605) :
-- le dossier des murs d'air, puis les pièces des grillages `passbullets`, liste figée. step (optionnel) est appelé à
-- chaque pièce parcourue pour étaler le calcul sur plusieurs frames. Renvoie la liste gardée.
function MapGeometry.prepare(map: Instance, step: (() -> ())?): { Instance }
	local known = cache[map]
	if known then
		return known
	end
	local list: { Instance } = {}
	local clips = MapGeometry.clips(map)
	if clips then
		table.insert(list, clips)
	end
	local geometry = map:FindFirstChild(MapGeometry.GEOMETRY)
	if geometry then
		local background = step ~= nil and not preparing[map]
		if background then
			preparing[map] = true
		end
		local ok, err = pcall(eachDescendant, geometry, function(inst)
			if
				inst:IsA("BasePart")
				and MapGeometry.passesBullets(inst)
				and not (clips and inst:IsDescendantOf(clips))
			then
				table.insert(list, inst)
			end
		end, step)
		if background then
			preparing[map] = nil
		end
		if not ok then
			error(err, 0)
		end
	end
	table.freeze(list)
	-- Une autre préparation de la même map a pu finir pendant celle-ci : la première liste reste la liste gardée
	known = cache[map]
	if known then
		return known
	end
	cache[map] = list
	return list
end

-- Cette méthode permet de savoir si la liste d'une map est déjà prête lorsqu'on vérifie qu'un tir ne la calculera pas.
function MapGeometry.isPrepared(map: Instance): boolean
	return cache[map] ~= nil
end

-- Cette méthode permet de savoir si la liste d'une map est prête ou en cours de préparation en tâche de fond lorsqu'une
-- nouvelle préparation est demandée (map jouée et annoncée à la fois : un seul parcours).
function MapGeometry.isPreparedOrPreparing(map: Instance): boolean
	return cache[map] ~= nil or preparing[map] == true
end

-- Cette méthode permet de lister ce que les balles et le regard traversent dans une map lorsqu'on prépare un rayon :
-- la liste préparée (prepare), calculée sur le champ si la map n'a pas encore été préparée.
function MapGeometry.bulletTransparent(map: Instance): { Instance }
	return cache[map] or MapGeometry.prepare(map)
end

-- Cette méthode permet de savoir si une pièce touchée est traversée par les balles et le regard lorsqu'un rayon en
-- inclusion la rencontre : mur d'air de la map ou grillage `passbullets` (même règle que bulletTransparent).
function MapGeometry.seeThrough(map: Instance): (Instance) -> boolean
	local clips = MapGeometry.clips(map)
	return function(inst: Instance): boolean
		return MapGeometry.passesBullets(inst) or (clips ~= nil and inst:IsDescendantOf(clips))
	end
end

-- Cette méthode permet de lancer un rayon qui traverse murs d'air et grillages lorsque ses paramètres sont en inclusion
-- (une longue liste d'inclusion rend chaque rayon ~9x plus cher, #292) : relancé derrière chaque pièce traversée.
function MapGeometry.castThrough(
	cast: (Vector3, Vector3) -> RaycastResult?,
	from: Vector3,
	delta: Vector3,
	skip: (Instance) -> boolean
): RaycastResult?
	local length = delta.Magnitude
	if length < 1e-6 then
		return cast(from, delta)
	end
	local dir = delta / length
	local travelled = 0
	for _ = 1, MapGeometry.MAX_PASSES do
		local hit = cast(from + dir * travelled, dir * (length - travelled))
		if not hit or not skip(hit.Instance) then
			return hit
		end
		travelled = (hit.Position - from):Dot(dir) + MapGeometry.PASS_STEP
		if travelled >= length then
			return nil
		end
	end
	return nil
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

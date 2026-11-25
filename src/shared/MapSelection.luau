-- Map jouée parmi les maps du jeu (une par .rbxm de assets/rbx/Maps, cf. docs/maps.md « Choisir la map jouée »).
-- Rojo les synchronise toutes dans Workspace.Maps ; au démarrage, le serveur (setup) n'y laisse que la map jouée et range
-- les autres dans ReplicatedStorage.MapStore (connues des clients, ni rendues ni touchées par les rayons). La rotation
-- (#594, MapRotation côté serveur) échange les maps entre les rounds (switch) et publie deux attributs sur Workspace.Maps :
-- ActiveMap (map jouée) et NextMap (map du round suivant, annoncée par le bandeau de fin). Tout code qui lit la map passe
-- par ce module (current, waitForActive, observe), jamais par un nom de map en dur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapSelection = {}

MapSelection.ACTIVE_ATTRIBUTE = "ActiveMap"
MapSelection.NEXT_ATTRIBUTE = "NextMap"
-- Attribut de Workspace, Studio uniquement : force la map jouée (nom d'une map), rotation suspendue tant qu'il est posé
MapSelection.DEBUG_ATTRIBUTE = "DebugMap"
MapSelection.STORE_NAME = "MapStore"
MapSelection.FALLBACK = "Dizzy"

-- Cette méthode permet de choisir le nom de la map jouée lorsque le serveur démarre : le nom demandé s'il existe,
-- sinon la map de repli, sinon la première par ordre alphabétique (nil s'il n'y a aucune map).
function MapSelection.resolve(available: { string }, wanted: string?): string?
	local sorted = table.clone(available)
	table.sort(sorted)
	for _, candidate in { wanted, MapSelection.FALLBACK } do
		if candidate and table.find(sorted, candidate) then
			return candidate
		end
	end
	return sorted[1]
end

-- Cette méthode permet de choisir la map du round suivant lorsqu'un round se termine ou commence : la map forcée si elle
-- existe, sinon celle qui suit `current` dans l'ordre de `rotation` (maps absentes sautées, retour au début en fin de
-- liste) ; une map présente hors rotation passe après les autres. nil s'il n'y a aucune map.
function MapSelection.nextInRotation(
	rotation: { string },
	available: { string },
	current: string?,
	forced: string?
): string?
	if forced and table.find(available, forced) then
		return forced
	end
	-- Ordre effectif : la rotation (maps présentes), puis les maps présentes absentes de la rotation, par ordre alphabétique
	local order = {}
	for _, name in rotation do
		if table.find(available, name) and not table.find(order, name) then
			table.insert(order, name)
		end
	end
	local extra = {}
	for _, name in available do
		if not table.find(order, name) then
			table.insert(extra, name)
		end
	end
	table.sort(extra)
	for _, name in extra do
		table.insert(order, name)
	end
	if #order == 0 then
		return nil
	end
	local index = if current then table.find(order, current) else nil
	if not index then
		return order[1]
	end
	return order[index % #order + 1]
end

-- Cette méthode permet de lire le nom d'une map forcée lorsque le serveur choisit la map : attribut DebugMap de
-- Workspace dans Studio, nil ailleurs ou s'il n'est pas une chaîne non vide.
function MapSelection.forced(isStudio: boolean, value: any): string?
	if isStudio and type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

-- Cette méthode permet de trouver le rangement des maps qui ne sont pas jouées lorsque le serveur le remplit ou qu'un
-- client y cherche une map ; create le crée côté serveur s'il manque.
function MapSelection.store(create: boolean?): Folder?
	local store = ReplicatedStorage:FindFirstChild(MapSelection.STORE_NAME)
	if not store and create then
		local folder = Instance.new("Folder")
		folder.Name = MapSelection.STORE_NAME
		folder.Parent = ReplicatedStorage
		store = folder
	end
	return store :: Folder?
end

-- Cette méthode permet de lister les noms de toutes les maps du jeu (jouée et rangées) lorsque la rotation choisit la
-- suivante.
function MapSelection.names(): { string }
	local names = {}
	for _, parent in { workspace:FindFirstChild("Maps"), MapSelection.store() } do
		for _, child in if parent then parent:GetChildren() else {} do
			if child:IsA("Model") and not table.find(names, child.Name) then
				table.insert(names, child.Name)
			end
		end
	end
	return names
end

-- Cette méthode permet de retrouver une map par son nom, jouée ou rangée, lorsqu'un écran ou la rotation en a besoin
-- (lecteur de démo, échange de maps) ; nil si elle n'existe pas.
function MapSelection.find(name: string): Instance?
	local maps = workspace:FindFirstChild("Maps")
	local store = MapSelection.store()
	return (maps and maps:FindFirstChild(name)) or (store and store:FindFirstChild(name)) or nil
end

-- Cette méthode permet de ne laisser que la map jouée dans Workspace.Maps lorsque le serveur démarre : les autres sont
-- rangées dans ReplicatedStorage.MapStore, le nom retenu est publié dans l'attribut ActiveMap.
function MapSelection.setup(maps: Instance?, wanted: string?): Instance?
	if not maps then
		return nil
	end
	local names = {}
	for _, child in maps:GetChildren() do
		table.insert(names, child.Name)
	end
	local chosen = MapSelection.resolve(names, wanted)
	if wanted and chosen ~= wanted then
		warn(string.format("[MapSelection] map %q absente de Workspace.Maps, repli sur %q", wanted, tostring(chosen)))
	end
	local store = MapSelection.store(true) :: Folder
	for _, child in maps:GetChildren() do
		if child.Name ~= chosen then
			child.Parent = store
		end
	end
	maps:SetAttribute(MapSelection.ACTIVE_ATTRIBUTE, chosen)
	return if chosen then maps:FindFirstChild(chosen) else nil
end

-- Cette méthode permet de changer la map jouée lorsque la rotation passe à la suivante : la nouvelle entre dans
-- Workspace.Maps, ActiveMap est publié, puis l'ancienne est rangée. Renvoie la map jouée, inchangée si le nom est inconnu
-- ou déjà joué.
function MapSelection.switch(maps: Instance, name: string): Instance?
	local active = maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	local map = MapSelection.find(name)
	if not map then
		warn(string.format("[MapSelection] map %q introuvable : la map jouée ne change pas", name))
		return if type(active) == "string" then maps:FindFirstChild(active) else nil
	end
	map.Parent = maps
	maps:SetAttribute(MapSelection.ACTIVE_ATTRIBUTE, name)
	local store = MapSelection.store(true) :: Folder
	for _, child in maps:GetChildren() do
		if child.Name ~= name then
			child.Parent = store
		end
	end
	return map
end

-- Cette méthode permet de lire la map jouée sans attendre lorsqu'un module en a besoin à chaque fois (tir, analytics) ;
-- nil tant que le serveur ne l'a pas publiée.
function MapSelection.current(): Instance?
	local maps = workspace:FindFirstChild("Maps")
	local name = maps and maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	return if maps and type(name) == "string" then maps:FindFirstChild(name) else nil
end

-- Cette méthode permet de lire le nom de la map jouée sans attendre lorsqu'un outil l'inscrit (enregistrements, démo) ;
-- nil tant que le serveur ne l'a pas publié.
function MapSelection.currentName(): string?
	local maps = workspace:FindFirstChild("Maps")
	local name = maps and maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	return if type(name) == "string" then name else nil
end

-- Cette méthode permet de lire le nom de la map du round suivant lorsque le bandeau de fin l'annonce ; nil s'il n'est
-- pas publié.
function MapSelection.nextName(): string?
	local maps = workspace:FindFirstChild("Maps")
	local name = maps and maps:GetAttribute(MapSelection.NEXT_ATTRIBUTE)
	return if type(name) == "string" then name else nil
end

-- Cette méthode permet d'attendre la map jouée lorsque le serveur ou un client en a besoin une fois (copie de décor du
-- menu) : attend Workspace.Maps, puis l'attribut ActiveMap, puis la map elle-même, dans la limite de timeout secondes.
function MapSelection.waitForActive(timeout: number): Instance?
	local deadline = os.clock() + timeout
	local maps = workspace:WaitForChild("Maps", timeout)
	if not maps then
		return nil
	end
	local name = maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	while type(name) ~= "string" and os.clock() < deadline do
		task.wait(0.1)
		name = maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
	end
	if type(name) ~= "string" then
		return nil
	end
	return maps:WaitForChild(name, math.max(deadline - os.clock(), 0.1))
end

-- Cette méthode permet de suivre la map jouée lorsqu'un système en relève le contenu (volumes, géométrie, plan) :
-- callback reçoit la map dès qu'elle est connue, puis la nouvelle à chaque changement (#594), en tâche de fond. Un
-- changement arrivé pendant l'attente de la map précédente l'emporte (seule la dernière est passée).
function MapSelection.observe(timeout: number, callback: (Instance) -> ())
	task.spawn(function()
		local maps = workspace:WaitForChild("Maps", timeout)
		if not maps then
			return
		end
		local generation = 0
		-- Cette méthode permet d'attendre la map nommée dans ActiveMap puis de la passer au callback lorsque l'attribut
		-- est posé ou change, sauf si un changement plus récent est arrivé entre-temps.
		local function deliver()
			generation += 1
			local mine = generation
			local name = maps:GetAttribute(MapSelection.ACTIVE_ATTRIBUTE)
			if type(name) ~= "string" then
				return
			end
			local map = maps:FindFirstChild(name) or maps:WaitForChild(name, timeout)
			if map and mine == generation and map.Parent == maps then
				callback(map)
			end
		end
		maps:GetAttributeChangedSignal(MapSelection.ACTIVE_ATTRIBUTE):Connect(function()
			task.spawn(deliver)
		end)
		deliver()
	end)
end

-- Cette méthode permet de suivre la map du round suivant lorsqu'un système veut la préparer avant l'échange (#605 :
-- géométrie des tirs, boîte de la map) : callback reçoit la map annoncée (rangée ou jouée) dès qu'elle est connue, puis
-- à chaque nouvelle annonce, en tâche de fond.
function MapSelection.observeNext(timeout: number, callback: (Instance) -> ())
	task.spawn(function()
		local maps = workspace:WaitForChild("Maps", timeout)
		if not maps then
			return
		end
		-- Cette méthode permet de passer la map annoncée au callback lorsque l'attribut NextMap est posé ou change.
		local function deliver()
			local name = maps:GetAttribute(MapSelection.NEXT_ATTRIBUTE)
			local map = if type(name) == "string" then MapSelection.find(name) else nil
			if map then
				callback(map)
			end
		end
		maps:GetAttributeChangedSignal(MapSelection.NEXT_ATTRIBUTE):Connect(function()
			task.spawn(deliver)
		end)
		deliver()
	end)
end

return MapSelection

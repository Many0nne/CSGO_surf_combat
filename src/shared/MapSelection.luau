-- Choix de la map jouée parmi Workspace.Maps (une map par .rbxm de assets/rbx/Maps, cf. docs/maps.md).
-- Le serveur garde celle de GameConfig.ACTIVE_MAP, détruit les autres et pose l'attribut ActiveMap sur Workspace.Maps ;
-- le serveur et le client la retrouvent ensuite par waitForActive. Nom absent : repli sur la map « Map » (l'Arène).

local MapSelection = {}

MapSelection.ACTIVE_ATTRIBUTE = "ActiveMap"
MapSelection.FALLBACK = "Map"

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

-- Cette méthode permet de ne garder que la map jouée lorsque le serveur démarre : les autres maps sont détruites
-- (elles ne se superposent plus et ne coûtent rien aux clients), le nom retenu est publié dans l'attribut ActiveMap.
function MapSelection.activate(maps: Instance?, wanted: string?): Instance?
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
	for _, child in maps:GetChildren() do
		if child.Name ~= chosen then
			child:Destroy()
		end
	end
	maps:SetAttribute(MapSelection.ACTIVE_ATTRIBUTE, chosen)
	return if chosen then maps:FindFirstChild(chosen) else nil
end

-- Cette méthode permet d'attendre la map jouée lorsque le serveur ou un client en a besoin : attend Workspace.Maps,
-- puis l'attribut ActiveMap posé par activate, puis la map elle-même, dans la limite de timeout secondes au total.
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

return MapSelection

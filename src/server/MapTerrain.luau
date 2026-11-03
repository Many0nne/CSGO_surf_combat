-- Sable de l'Arène en Terrain (#71) : le Terrain n'est pas dans Map.rbxm (Rojo ne le versionne pas), il est donc
-- reconstruit au démarrage du serveur depuis le champ de dunes (Shared.DuneField), à partir des attributs posés par
-- le générateur sur Maps.Map. Le générateur l'appelle aussi en mode Edit pour l'aperçu. Le Terrain se réplique aux
-- clients ; le mouvement fait maison le voit comme n'importe quelle surface (raycasts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuneField = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DuneField"))

local MapTerrain = {}

local SAND_COLOR = Color3.fromRGB(190, 134, 94) -- même teinte que le sol de l'île (matière Sand de Roblox)
local SPAWN_FLAT = 6 -- rayon gardé plat autour d'un point d'apparition au sol
local PAD_FLAT = 10 -- rayon gardé plat autour d'une dalle de geyser ou de lanceur

-- Cette méthode permet de relever les zones à garder plates (plan) lorsqu'on construit le sable : points d'apparition
-- au sol et dalles des geysers et lanceurs, lus dans la map pour ne pas dupliquer les données du générateur.
local function flatZones(map: Instance, plan: CFrame): { { number } }
	local flats = {}
	local function add(part: Instance, radius: number)
		if part:IsA("BasePart") then
			local p = plan:PointToObjectSpace(part.Position)
			table.insert(flats, { p.X, p.Z, radius })
		end
	end
	local spawns = map:FindFirstChild("GroundSpawns")
	for _, s in if spawns then spawns:GetChildren() else {} do
		add(s, SPAWN_FLAT)
	end
	local boosts = map:FindFirstChild("Boosts")
	for _, b in if boosts then boosts:GetChildren() else {} do
		local kind = b:GetAttribute("Kind")
		if kind == "Geyser" or kind == "Launcher" then
			add(b, PAD_FLAT)
		end
	end
	return flats
end

-- Cette méthode permet de poser le sable de la map dans le Terrain lorsqu'elle porte les attributs de dunes ;
-- efface d'abord tout le Terrain (la map en est seule propriétaire). Renvoie le nombre de colonnes de sable posées.
function MapTerrain.build(map: Instance?): number
	local terrain = workspace.Terrain
	local plan = map and map:GetAttribute(DuneField.PLAN_ATTRIBUTE)
	local ring = map and map:GetAttribute(DuneField.RING_ATTRIBUTE)
	if typeof(plan) ~= "CFrame" or typeof(ring) ~= "Vector3" then
		return 0
	end
	terrain:Clear()
	local flats = flatZones(map :: Instance, plan)

	-- région alignée sur la grille du Terrain, qui couvre l'île dans le repère du monde
	local reach = ring.X + ring.Y
	local corners = {}
	for _, c in
		{
			Vector3.new(-ring.X, 0, -reach),
			Vector3.new(ring.X, 0, -reach),
			Vector3.new(-ring.X, 0, reach),
			Vector3.new(ring.X, 0, reach),
		}
	do
		table.insert(corners, plan:PointToWorldSpace(c))
	end
	local lo, hi = corners[1], corners[1]
	for _, c in corners do
		lo, hi = lo:Min(c), hi:Max(c)
	end
	local R = DuneField.VOXEL
	local region = Region3.new(
		Vector3.new(lo.X, plan.Position.Y - R, lo.Z),
		Vector3.new(hi.X, plan.Position.Y + DuneField.MAX_HEIGHT + R, hi.Z)
	):ExpandToGrid(R)
	local cells = region.Size / R
	local nx, ny, nz = cells.X, cells.Y, cells.Z
	local origin = region.CFrame.Position - region.Size / 2

	local materials, occupancy = table.create(nx), table.create(nx)
	local columns = 0
	for i = 1, nx do
		materials[i], occupancy[i] = table.create(ny), table.create(ny)
		for j = 1, ny do
			materials[i][j] = table.create(nz, Enum.Material.Air)
			occupancy[i][j] = table.create(nz, 0)
		end
		for k = 1, nz do
			local world = origin + Vector3.new((i - 0.5) * R, 0, (k - 0.5) * R)
			local p = plan:PointToObjectSpace(world)
			local h = DuneField.height(p.X, p.Z, ring, flats)
			if h then
				columns += 1
				local top = plan.Position.Y + h
				for j = 1, ny do
					-- remplissage partiel du voxel du dessus : surface lisse à la bonne hauteur
					local fill = math.clamp((top - (origin.Y + (j - 1) * R)) / R, 0, 1)
					if fill > 0 then
						materials[i][j][k] = Enum.Material.Sand
						occupancy[i][j][k] = fill
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, R, materials, occupancy)
	terrain:SetMaterialColor(Enum.Material.Sand, SAND_COLOR)
	return columns
end

return MapTerrain

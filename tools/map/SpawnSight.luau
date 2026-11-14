--!nocheck
-- SpawnSight.luau
-- Lignes de vue entre les points d'apparition d'une map (dossier GroundSpawns, #329) : les points sont rangés par zone
-- (attribut `Zone`, sinon `Team`), et deux points de zones différentes ne doivent pas se voir, sans quoi SpawnPointRules
-- n'a plus de point « hors de vue » à proposer et retombe au hasard. Même test que SpawnManager : yeux à yeux
-- (POINT_EYE studs au-dessus du centre du point), arrêté par les pièces CanQuery hors murs d'air (dossier Clips) et
-- moins transparentes que SEE_THROUGH (grillages), SpawnPointRules.blocksSight.
-- Arithmétique sur des boîtes (RampCheck.box, ShadowCulling.rayEntry ; un cylindre est approché par sa boîte) dans
-- une grille en plan : tourne dans Lune sans Studio. Lancé par tools/map/spawn_sight.luau ; testé :
-- tests/specs/SpawnSight.spec.luau.

local RampCheck = require("./RampCheck")
local ShadowCulling = require("./ShadowCulling")

local SpawnSight = {}

SpawnSight.FOLDER = "GroundSpawns"
-- studs : yeux au-dessus du centre d'un point, SpawnPointRules.POINT_EYE_OFFSET (ROOT_ABOVE_POINT 5 + EYE_HEIGHT 1,5,
-- vérifié par le test)
SpawnSight.POINT_EYE = 6.5
-- une pièce au moins aussi transparente se voit au travers (SpawnPointRules.SEE_THROUGH_TRANSPARENCY)
SpawnSight.SEE_THROUGH = 0.5
SpawnSight.CELL = 16 -- studs, côté d'une cellule de la grille en plan

-- Cette méthode permet de savoir si une pièce est sous un dossier nommé Clips (murs d'air) lorsqu'on liste ce qui
-- arrête le regard.
local function inClips(p)
	local a = p.Parent
	while a do
		if a.Name == "Clips" then
			return true
		end
		a = a.Parent
	end
	return false
end

-- Cette méthode permet de construire l'index des pièces qui arrêtent le regard dans une map lorsqu'on va tester des
-- lignes de vue : boîtes rangées dans une grille en plan (XZ).
function SpawnSight.index(map)
	local spawnFolder = map:FindFirstChild(SpawnSight.FOLDER)
	local boxes, grid = {}, {}
	local cell = SpawnSight.CELL
	for _, p in map:GetDescendants() do
		if
			p:IsA("BasePart")
			and p.CanQuery
			and p.Transparency < SpawnSight.SEE_THROUGH
			and not (spawnFolder and p:IsDescendantOf(spawnFolder))
			and not inClips(p)
		then
			local b = RampCheck.box(p)
			table.insert(boxes, b)
			local id = #boxes
			local hx = math.abs(b.xx) * b.sx / 2 + math.abs(b.yx) * b.sy / 2 + math.abs(b.zx) * b.sz / 2
			local hz = math.abs(b.xz) * b.sx / 2 + math.abs(b.yz) * b.sy / 2 + math.abs(b.zz) * b.sz / 2
			for ix = math.floor((b.px - hx) / cell), math.floor((b.px + hx) / cell) do
				for iz = math.floor((b.pz - hz) / cell), math.floor((b.pz + hz) / cell) do
					local key = ix * 65536 + iz
					local list = grid[key]
					if not list then
						list = {}
						grid[key] = list
					end
					table.insert(list, id)
				end
			end
		end
	end
	return { boxes = boxes, grid = grid, stamp = {}, round = 0 }
end

-- Cette méthode permet de savoir si le segment de a à b (positions {x, y, z}) ne traverse aucune pièce de l'index
-- lorsqu'on teste une vue d'yeux à yeux : parcourt les cellules du plan que couvre le segment.
function SpawnSight.clear(index, a, b)
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-6 then
		return true
	end
	dx, dy, dz = dx / len, dy / len, dz / len
	index.round += 1
	local round, stamp, boxes, grid = index.round, index.stamp, index.boxes, index.grid
	local cell = SpawnSight.CELL
	-- échantillonne le segment tous les quarts de cellule, avec les cellules voisines (couverture large et simple)
	local steps = math.max(1, math.ceil(len / (cell / 4)))
	local seen = {}
	for s = 0, steps do
		local t = len * s / steps
		local cx = math.floor((a[1] + dx * t) / cell)
		local cz = math.floor((a[3] + dz * t) / cell)
		for ix = cx - 1, cx + 1 do
			for iz = cz - 1, cz + 1 do
				local key = ix * 65536 + iz
				if not seen[key] then
					seen[key] = true
					for _, id in grid[key] or {} do
						if stamp[id] ~= round then
							stamp[id] = round
							if ShadowCulling.rayEntry(boxes[id], a[1], a[2], a[3], dx, dy, dz, len) then
								return false
							end
						end
					end
				end
			end
		end
	end
	return true
end

-- Cette méthode permet de lister les points d'apparition d'une map avec leur zone (attribut Zone, sinon Team, sinon
-- leur nom) et la position de leurs yeux lorsqu'on vérifie les vues entre zones.
function SpawnSight.points(map)
	local folder = map:FindFirstChild(SpawnSight.FOLDER)
	local out = {}
	for _, p in if folder then folder:GetChildren() else {} do
		if p:IsA("BasePart") then
			local c = p.CFrame.Position
			table.insert(out, {
				name = p.Name,
				zone = p:GetAttribute("Zone") or p:GetAttribute("Team") or p.Name,
				eye = { c.X, c.Y + SpawnSight.POINT_EYE, c.Z },
			})
		end
	end
	table.sort(out, function(x, y)
		return x.name < y.name
	end)
	return out
end

-- Cette méthode permet de vérifier qu'aucun point ne voit un point d'une autre zone lorsqu'on contrôle une map :
-- renvoie le nombre de paires testées, la liste des paires qui se voient ({ a, b }) et le bilan par paire de zones
-- (zones triées, { za, zb, pairs, visible }).
function SpawnSight.check(map)
	local index = SpawnSight.index(map)
	local points = SpawnSight.points(map)
	local tested, visible, byZone = 0, {}, {}
	for i = 1, #points do
		for j = i + 1, #points do
			local a, b = points[i], points[j]
			if a.zone ~= b.zone then
				tested += 1
				local za, zb = a.zone, b.zone
				if za > zb then
					za, zb = zb, za
				end
				local key = za .. "|" .. zb
				local row = byZone[key]
				if not row then
					row = { za = za, zb = zb, pairs = 0, visible = 0 }
					byZone[key] = row
				end
				row.pairs += 1
				if SpawnSight.clear(index, a.eye, b.eye) then
					row.visible += 1
					table.insert(visible, { a = a.name, b = b.name })
				end
			end
		end
	end
	local rows = {}
	for _, row in byZone do
		table.insert(rows, row)
	end
	table.sort(rows, function(x, y)
		return if x.za == y.za then x.zb < y.zb else x.za < y.za
	end)
	return tested, visible, rows
end

return SpawnSight

-- build_city.luau
-- Générateur de la map « ville ensablée » (issue #69). À exécuter DANS Roblox Studio, mode Edit, plugin Rojo
-- déconnecté : via le MCP Studio (`execute_luau`, contexte Edit, coller le contenu du fichier) ou la barre de commande.
-- Construit Workspace.Maps.Map à partir des données ci-dessous (déterministe : même graine = même ville), puis
-- l'export (`tools/rbxm/studio_export.luau`) l'écrit dans assets/rbx/Maps/Map.rbxm, synchronisé par Rojo.
--
-- Repère local du plan : origine au centre de la place, -Z vers le soleil couchant (ClockTime 17.9, latitude 0,
-- cf. Lighting dans default.project.json), X vers la droite quand on regarde le soleil. Unités : studs.
-- Pentes : surfable entre 46° et 84° (MovementConfig.SURF_NORMAL_Y / SURF_NORMAL_MIN), marchable en dessous.

local SEED = 69
-- Direction horizontale du soleil à ClockTime 17.9, latitude 0 (Lighting:GetSunDirection(), Y retiré)
local SUN_DIR = Vector3.new(-0.9168, 0, -0.3987).Unit

-- Contour de la zone jouable (x, z), sens horaire vu du dessus : façades hautes + murs invisibles
local BOUNDARY = {
	{ -200, -270 },
	{ -60, -300 },
	{ 90, -290 },
	{ 210, -250 },
	{ 255, -150 },
	{ 235, -40 },
	{ 265, 60 },
	{ 230, 170 },
	{ 120, 215 },
	{ 10, 235 },
	{ -110, 205 },
	{ -215, 150 },
	{ -265, 40 },
	{ -235, -80 },
	{ -255, -180 },
}
local SUN_SIDE_Z = -230 -- façades plus basses au-delà (côté soleil), pour garder l'horizon
local PLAZA_RADIUS = 55

-- Rues : demi-largeur et tracé (x, z). minH : hauteur minimale des immeubles qui la bordent.
local STREETS = {
	avenue = { hw = 26, pts = { { 0, 0 }, { 25, -130 }, { -10, -250 } } },
	gauche = { hw = 18, pts = { { 0, 0 }, { -130, 40 }, { -205, 140 } } },
	droite = { hw = 24, pts = { { 0, 0 }, { 140, -20 }, { 215, 70 } } },
	ruelle = { hw = 10, pts = { { 0, 0 }, { 20, 165 } } },
	ouest = { hw = 30, minH = 48, pts = { { -130, 40 }, { -178, -80 }, { -100, -195 }, { -10, -250 } } },
	est = { hw = 14, pts = { { 25, -130 }, { 135, -150 }, { 205, -65 }, { 140, -20 } } },
	nord = { hw = 10, pts = { { 20, 165 }, { -100, 150 }, { -205, 140 } } },
}

-- Talus de sable continus le long d'une rue (couloir de surf) : hauteur, pente (degrés), côtés (-1 gauche, 1 droite)
local DUNE_BANKS = {
	{ street = "ouest", height = 40, slope = 55, sides = { -1, 1 } },
}

-- Tours tombées à l'horizontale et roulées sur le côté : face surfable (slope) d'un côté, marchable (90 - slope) de
-- l'autre. a, b : extrémités de l'axe (x, y, z) ; w : section carrée ; flip inverse le côté de la face surfable.
local FALLEN_TOWERS = {
	{ a = { 205, 72, -205 }, b = { 60, 38, -70 }, w = 30, slope = 55, flip = false }, -- par-dessus la rue est
	{ a = { 48, 16, -12 }, b = { 150, 30, -34 }, w = 34, slope = 55, flip = true }, -- dans la rue de droite
	{ a = { -150, 64, 175 }, b = { -40, 30, 95 }, w = 26, slope = 58, flip = false }, -- au nord-ouest
}

-- Arête de sable en travers de l'avenue : marchable côté place, surfable côté soleil
local AVENUE_RIDGE = { x = 5, z = -205, yaw = 20, width = 90, height = 30, slopeWalk = 32, slopeSurf = 56 }

-- Lanceurs du soleil : le joueur apparaît là, projeté vers target (x, y, z) à speed studs/s
local SUN_LAUNCHES = {
	{ pos = { -20, 120, -255 }, target = { -5, 70, -120 }, speed = 120 },
	{ pos = { -120, 125, -215 }, target = { -150, 60, -90 }, speed = 115 },
	{ pos = { 120, 125, -240 }, target = { 140, 70, -150 }, speed = 115 },
}

-- Points d'apparition au sol (repli si aucun lanceur) : (x, z)
local GROUND_SPAWNS = {
	{ 0, 30 },
	{ -30, -40 },
	{ 40, -80 },
	{ -90, 40 },
	{ 90, -10 },
	{ 15, 120 },
	{ -60, 150 },
	{ 180, 20 },
}

-- Palette (direction « Ligne de mire », cf. docs/ui.md)
local GLOW = Color3.fromRGB(255, 170, 110)
local GROUND = Color3.fromRGB(190, 134, 94)

---------------------------------------------------------------------------------------------------------------------

local rng = Random.new(SEED)
local base = CFrame.lookAt(Vector3.zero, SUN_DIR)

-- Cette méthode permet de passer du repère du plan au monde lorsqu'on place une pièce.
local function g(x: number, y: number, z: number): CFrame
	return base * CFrame.new(x, y, z)
end

local map = Instance.new("Model")
map.Name = "Map"
map:SetAttribute("Generator", "tools/map/build_city.luau")
map:SetAttribute("Seed", SEED)
local folders = {}
for _, name in { "Ground", "Buildings", "Ramps", "Boundary", "Skyline", "Props", "GroundSpawns", "SunLaunch" } do
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = map
	folders[name] = f
end

-- Cette méthode permet de créer une pièce ancrée dans un dossier de la map lorsqu'on construit un élément.
local function part(folder: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, class: string?)
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folders[folder]
	return p
end

-- Cette méthode permet de tirer une teinte d'immeuble sombre lorsqu'on crée un bloc.
local function ink(): Color3
	return Color3.fromRGB(rng:NextInteger(32, 60), rng:NextInteger(29, 44), rng:NextInteger(35, 49))
end

-- Cette méthode permet de tirer une teinte de sable lorsqu'on crée une dune.
local function sand(): Color3
	local k = rng:NextNumber()
	return Color3.fromRGB(176 + k * 24, 118 + k * 24, 82 + k * 16)
end

-- Cette méthode permet de mesurer la distance d'un point à un segment lorsqu'on teste l'emprise d'une rue.
local function distSeg(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
	return math.sqrt((px - ax - t * dx) ^ 2 + (pz - az - t * dz) ^ 2)
end

-- Cette méthode permet de savoir si un point est dans la zone jouable lorsqu'on place un bloc ou un spawn
-- (test pair-impair sur le contour).
local function inside(x: number, z: number): boolean
	local c = false
	local n = #BOUNDARY
	for i = 1, n do
		local a, b = BOUNDARY[i], BOUNDARY[i % n + 1]
		if (a[2] > z) ~= (b[2] > z) and x < (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2]) + a[1] then
			c = not c
		end
	end
	return c
end

-- Cette méthode permet de mesurer la distance au contour lorsqu'un bloc ne doit pas mordre sur la ceinture.
local function distBoundary(x: number, z: number): number
	local best = math.huge
	local n = #BOUNDARY
	for i = 1, n do
		local a, b = BOUNDARY[i], BOUNDARY[i % n + 1]
		best = math.min(best, distSeg(x, z, a[1], a[2], b[1], b[2]))
	end
	return best
end

-- Emprises réservées (rues, place, rampes) : un bloc ne s'y pose pas
local occupied: { { number } } = {}

-- Cette méthode permet de savoir si un disque (x, z, r) est libre lorsqu'on veut y poser un bloc.
local function free(x: number, z: number, r: number): boolean
	if math.sqrt(x * x + z * z) < PLAZA_RADIUS + r then
		return false
	end
	if not inside(x, z) or distBoundary(x, z) < r + 8 then
		return false
	end
	for _, st in STREETS do
		for i = 1, #st.pts - 1 do
			local a, b = st.pts[i], st.pts[i + 1]
			if distSeg(x, z, a[1], a[2], b[1], b[2]) < st.hw + r * 0.85 then
				return false
			end
		end
	end
	for _, c in occupied do
		if math.sqrt((x - c[1]) ^ 2 + (z - c[2]) ^ 2) < (r + c[3]) * 0.82 then
			return false
		end
	end
	return true
end

-- Cette méthode permet de réserver l'emprise d'une rampe lorsqu'aucun bloc ne doit la traverser
-- (disques posés tous les `step` studs le long de [a, b]).
local function reserveLine(ax: number, az: number, bx: number, bz: number, r: number)
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local n = math.max(1, math.ceil(len / (r * 0.8)))
	for i = 0, n do
		local t = i / n
		table.insert(occupied, { ax + (bx - ax) * t, az + (bz - az) * t, r })
	end
end

-- Cette méthode permet de poser un immeuble enfoui (bloc, fenêtres allumées éparses, antenne si haut)
-- lorsqu'on borde une rue ou remplit un îlot ; facing = côté de la façade sur rue (-1/1 sur X local, 0 sans).
local function building(x: number, z: number, w: number, d: number, h: number, yaw: number, facing: number)
	local sink = rng:NextNumber(4, 20)
	local cf = g(x, (h - sink) / 2, z) * CFrame.Angles(0, yaw, 0)
	part("Buildings", Vector3.new(w, h + sink, d), cf, ink(), Enum.Material.Concrete)
	if facing ~= 0 then
		for wy = 12, h - 6, 16 do
			if rng:NextNumber() < 0.1 then
				local win = Vector3.new(0.5, 3, d * rng:NextNumber(0.2, 0.5))
				local off = CFrame.new(-facing * (w / 2 + 0.1), wy - (h - sink) / 2, rng:NextNumber(-d / 4, d / 4))
				part("Buildings", win, cf * off, GLOW, Enum.Material.Neon)
			end
		end
	end
	if h > 90 then
		local mast = Vector3.new(0.8, rng:NextNumber(12, 30), 0.8)
		local off = CFrame.new(rng:NextNumber(-w / 3, w / 3), (h + sink) / 2 + mast.Y / 2, 0)
		part("Props", mast, cf * off, Color3.fromRGB(30, 28, 34), Enum.Material.Metal)
	end
end

-- Cette méthode permet de poser un talus de sable (WedgePart, côté haut = +Z local) lorsqu'on veut une pente
-- de `slope` degrés, haute de `height`, large de `width`, dont le pied est en (x, z) et qui monte vers `dir`.
local function wedge(x: number, z: number, dir: Vector3, width: number, height: number, slope: number)
	local run = height / math.tan(math.rad(slope))
	local c = Vector3.new(x, 0, z) + dir * (run / 2)
	local cf = g(c.X, height / 2, c.Z) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0)
	return part("Ramps", Vector3.new(width, height, run), cf, sand(), Enum.Material.Sand, "WedgePart"), run
end

-- Cette méthode permet de poser une tour tombée (prisme roulé autour de son axe) et ses deux appuis
-- lorsqu'on veut une longue rampe de surf au-dessus des toits.
local function fallenTower(t)
	local a = Vector3.new(t.a[1], t.a[2], t.a[3])
	local b = Vector3.new(t.b[1], t.b[2], t.b[3])
	local len = (b - a).Magnitude
	local roll = math.rad(t.slope) * (t.flip and -1 or 1)
	local cf = base * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, 0, roll)
	part("Ramps", Vector3.new(t.w, t.w, len), cf, ink(), Enum.Material.Concrete)
	-- face surfable = +Y local après roulis ; face marchable = +X (ou -X si flip) : arêtes ambrées de la face surfable
	local sx = t.flip and -1 or 1
	for _, cx in { t.w / 2, -t.w / 2 } do
		part("Ramps", Vector3.new(0.8, 0.8, len), cf * CFrame.new(cx, t.w / 2, 0), GLOW, Enum.Material.Neon)
	end
	-- fenêtres allumées sur la face marchable
	for _ = 1, math.floor(len / 40) do
		local off =
			CFrame.new(sx * (t.w / 2 + 0.1), rng:NextNumber(-t.w / 4, t.w / 4), rng:NextNumber(-len / 2.5, len / 2.5))
		part("Ramps", Vector3.new(0.5, t.w * 0.25, 3), cf * off, GLOW, Enum.Material.Neon)
	end
	-- appuis : l'immeuble sur lequel chaque extrémité est tombée
	for _, p in { a, b } do
		local h = p.Y - t.w * 0.55
		if h > 4 then
			local s = t.w * 1.5
			building(p.X, p.Z, s, s, h, rng:NextNumber(0, math.pi), 0)
			table.insert(occupied, { p.X, p.Z, s * 0.75 })
		end
	end
	reserveLine(a.X, a.Z, b.X, b.Z, t.w * 0.9)
end

---------------------------------------------------------------------------------------------------------------------
-- Sol
part("Ground", Vector3.new(1600, 4, 1600), g(0, -2, -35), GROUND, Enum.Material.Sand)

-- Rampes d'abord : leurs emprises sont réservées avant les immeubles
for _, t in FALLEN_TOWERS do
	fallenTower(t)
end

for _, bank in DUNE_BANKS do
	local st = STREETS[bank.street]
	for i = 1, #st.pts - 1 do
		local a, b = st.pts[i], st.pts[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local along = Vector3.new(dx, 0, dz) / len
		local X = Vector3.new(-along.Z, 0, along.X) -- perpendiculaire (gauche/droite du tracé)
		local mid = Vector3.new((a[1] + b[1]) / 2, 0, (a[2] + b[2]) / 2)
		for _, side in bank.sides do
			-- pied du talus vers l'axe, haut contre la façade (à hw du centre)
			local run = bank.height / math.tan(math.rad(bank.slope))
			local foot = mid + X * side * (st.hw - run)
			-- longueur prolongée pour fermer les coudes entre deux segments
			wedge(foot.X, foot.Z, X * side, len + run * 0.9, bank.height, bank.slope)
		end
	end
end

do
	local r = AVENUE_RIDGE
	local yaw = math.rad(r.yaw)
	local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw)) -- vers la place
	local runWalk = r.height / math.tan(math.rad(r.slopeWalk))
	local runSurf = r.height / math.tan(math.rad(r.slopeSurf))
	-- versant marchable côté place (monte vers -dir), versant surfable côté soleil (monte vers +dir)
	wedge(r.x + dir.X * runWalk, r.z + dir.Z * runWalk, -dir, r.width, r.height, r.slopeWalk)
	wedge(r.x - dir.X * runSurf, r.z - dir.Z * runSurf, dir, r.width, r.height, r.slopeSurf)
	local crest = g(r.x, r.height + 0.2, r.z) * CFrame.Angles(0, yaw + math.pi / 2, 0)
	part("Ramps", Vector3.new(0.6, 0.6, r.width), crest, GLOW, Enum.Material.Neon)
end
task.wait()

-- Immeubles le long des rues, avec des dunes contre les façades (marchables pour monter aux toits, ou surfables)
for _, st in STREETS do
	for i = 1, #st.pts - 1 do
		local a, b = st.pts[i], st.pts[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local yaw = math.atan2(dx, dz)
		local X = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
		for side = -1, 1, 2 do
			local t = rng:NextNumber(0, 10)
			while t < len do
				local along, w = rng:NextNumber(26, 55), rng:NextNumber(26, 55)
				local off = st.hw + rng:NextNumber(2, 8)
				local p = Vector3.new(a[1] + dx * (t + along / 2) / len, 0, a[2] + dz * (t + along / 2) / len)
				local c = p + X * side * (off + w / 2)
				if free(c.X, c.Z, math.min(w, along) * 0.5) then
					table.insert(occupied, { c.X, c.Z, math.min(w, along) * 0.5 })
					local roll = rng:NextNumber()
					local h = if roll < 0.6
						then rng:NextNumber(14, 50)
						elseif roll < 0.9 then rng:NextNumber(55, 95)
						else rng:NextNumber(105, 140)
					h = math.max(h, st.minH or 0)
					building(c.X, c.Z, w, along, h, yaw + math.rad(rng:NextNumber(-8, 8)), side)
					if not st.minH and rng:NextNumber() < 0.4 then
						local walk = rng:NextNumber() < 0.5
						local slope = if walk then rng:NextNumber(30, 40) else rng:NextNumber(50, 62)
						local dh = if walk then h else math.min(h * 0.85, rng:NextNumber(18, 45))
						local run = dh / math.tan(math.rad(slope))
						local foot = p + X * side * (off - run)
						wedge(foot.X, foot.Z, X * side, along * rng:NextNumber(0.6, 1), dh, slope)
					end
				end
				t += along + rng:NextNumber(2, 14)
			end
		end
	end
end
task.wait()

-- Îlots intérieurs bas : toits accessibles, couverture
for _ = 1, 250 do
	local x, z = rng:NextNumber(-250, 260), rng:NextNumber(-290, 230)
	local w, d = rng:NextNumber(22, 50), rng:NextNumber(22, 50)
	if free(x, z, math.max(w, d) * 0.5) then
		table.insert(occupied, { x, z, math.max(w, d) * 0.5 })
		building(x, z, w, d, rng:NextNumber(10, 55), math.rad(rng:NextNumber(-20, 20)), 0)
	end
end
task.wait()

-- Ceinture : façades le long du contour, murs invisibles, ouverture basse côté soleil
local n = #BOUNDARY
for i = 1, n do
	local a, b = BOUNDARY[i], BOUNDARY[i % n + 1]
	local A, B = Vector3.new(a[1], 0, a[2]), Vector3.new(b[1], 0, b[2])
	local len = (B - A).Magnitude
	local dir = (B - A) / len
	local out = Vector3.new(-dir.Z, 0, dir.X) -- extérieur (contour en sens horaire)
	if inside(((A + B) / 2 + out * 5).X, ((A + B) / 2 + out * 5).Z) then
		out = -out
	end
	local yaw = math.atan2(dir.X, dir.Z)
	local t = 0
	while t < len do
		local w = math.min(rng:NextNumber(45, 75), len - t + 10)
		local p = A + dir * (t + w / 2) + out * rng:NextNumber(18, 30)
		local h = if p.Z < SUN_SIDE_Z then rng:NextNumber(20, 45) else rng:NextNumber(110, 200)
		local cf = g(p.X, (h - 20) / 2, p.Z) * CFrame.Angles(0, yaw + math.rad(rng:NextNumber(-6, 6)), 0)
		part("Boundary", Vector3.new(rng:NextNumber(36, 50), h + 20, w), cf, ink(), Enum.Material.Concrete)
		t += w - 4
	end
	local wall = part("Boundary", Vector3.new(2, 420, len + 4), g((A.X + B.X) / 2, 200, (A.Z + B.Z) / 2), GLOW)
	wall.CFrame = g((A.X + B.X) / 2, 200, (A.Z + B.Z) / 2) * CFrame.Angles(0, yaw, 0)
	wall.Transparency = 1
	wall.CastShadow = false
	wall.Name = "InvisibleWall"
end
task.wait()

-- Silhouettes lointaines : décor hors d'atteinte, sans collision
for _ = 1, 45 do
	local a = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(430, 900)
	local x, z = math.cos(a) * dist, -35 + math.sin(a) * dist
	local h = rng:NextNumber(80, 320)
	local w = rng:NextNumber(40, 90)
	local tilt = if rng:NextNumber() < 0.2 then math.rad(rng:NextNumber(15, 35)) else 0
	local cf = g(x, h / 2 - 30, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), tilt)
	local p = part("Skyline", Vector3.new(w, h, w), cf, ink(), Enum.Material.Concrete)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- Accessoires : bus enfoui, lampadaires penchés
part(
	"Props",
	Vector3.new(10, 10, 32),
	g(12, 2, -85) * CFrame.Angles(math.rad(-14), math.rad(30), math.rad(9)),
	Color3.fromRGB(122, 58, 38),
	Enum.Material.Metal
)
for _ = 1, 10 do
	local x, z = rng:NextNumber(-180, 180), rng:NextNumber(-230, 170)
	if inside(x, z) then
		local cf = g(x, 9, z) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, math.rad(rng:NextNumber(-25, 25)))
		part("Props", Vector3.new(1.2, 26, 1.2), cf, Color3.fromRGB(28, 26, 32), Enum.Material.Metal)
	end
end

-- Points d'apparition au sol (repli de SpawnManager)
for i, s in GROUND_SPAWNS do
	local p = part("GroundSpawns", Vector3.new(4, 1, 4), g(s[1], 0.5, s[2]), GLOW)
	p.Name = "Spawn" .. i
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- Lanceurs du soleil : LookVector = direction du lancement, attribut Speed (studs/s)
for i, l in SUN_LAUNCHES do
	local from = (g(l.pos[1], l.pos[2], l.pos[3])).Position
	local to = (g(l.target[1], l.target[2], l.target[3])).Position
	local p = part("SunLaunch", Vector3.new(4, 4, 4), CFrame.lookAt(from, to), GLOW)
	p.Name = "Launch" .. i
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("Speed", l.speed)
end

-- Remplace la map générée précédente ; refuse d'écraser une map qui ne vient pas de ce générateur
local maps = workspace:FindFirstChild("Maps")
if not maps then
	maps = Instance.new("Folder")
	maps.Name = "Maps"
	maps.Parent = workspace
end
local old = maps:FindFirstChild("Map")
if old then
	assert(
		old:GetAttribute("Generator") ~= nil,
		"Workspace.Maps.Map ne vient pas du générateur : l'archiver puis la supprimer à la main avant de générer"
	)
	old:Destroy()
end
local count = #map:GetDescendants()
map.Parent = maps
return string.format("Map générée : %d instances", count)

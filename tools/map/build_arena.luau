-- build_arena.luau
-- Générateur de la map « Arène » : un anneau de dunes surfables adossé à des gratte-ciel ensablés, autour d'une
-- place, sur une île au-dessus du vide. À exécuter DANS Roblox Studio, mode Edit, plugin Rojo déconnecté
-- (cf. docs/maps.md). Construit Workspace.Maps.Map (déterministe : même graine = même map), que l'export
-- (`tools/rbxm/studio_export.luau`) écrit dans assets/rbx/Maps/Map.rbxm.
--
-- Repère local du plan : origine au centre de la place, -Z vers le soleil couchant (ClockTime 17.9, latitude 0,
-- cf. Lighting dans default.project.json), X vers la droite quand on regarde le soleil. Unités : studs.
-- L'anneau est allongé sur Z : deux lignes droites (x = ±RING_W) et deux virages (centres z = ±RING_L).
-- Pentes : surfable entre 46° et 84° (MovementConfig.SURF_NORMAL_Y / SURF_NORMAL_MIN), marchable en dessous.

local SEED = 71
-- Direction horizontale du soleil à ClockTime 17.9, latitude 0 (Lighting:GetSunDirection(), Y retiré)
local SUN_DIR = Vector3.new(-0.9168, 0, -0.3987).Unit
local GRAVITY = -110 -- MovementConfig.GRAVITY : sert à viser les geysers, lanceurs et sorties du soleil

-- Anneau : dos vertical des dunes à x = ±RING_W (lignes droites) et à RING_W des centres des virages
local RING_W = 120
local RING_L = 170
local BANK_H = 55
local BANK_SLOPE = 55
local ARC_SEGMENTS = 36 -- segments par virage : plus il y en a, moins chaque jointure freine

local TOWER_DEPTH = 46
local ISLAND_THICK = 30
local KILL_HEIGHT = -60 -- sous l'île : mort (MapRules.KILL_HEIGHT_ATTRIBUTE)

-- Passerelle des snipers, en travers de la place entre les deux tours centrales
local BRIDGE_Y = 78
local BRIDGE_W = 14

-- Boosts. Geyser / lanceur : on vise un point `to` atteint en `t` secondes (vitesse balistique imposée).
-- Portique : volume en travers d'une ligne droite, ajoute `boost` studs/s dans le sens du mouvement.
local GEYSERS = {
	{ at = { -45, 100 }, to = { -104, 36, 172 }, t = 1.3 },
	{ at = { 45, -100 }, to = { 104, 36, -172 }, t = 1.3 },
}
local LAUNCHERS = {
	{ at = { -30, 45 }, to = { -10, 82, 3 }, t = 1.5 }, -- vers la passerelle
}
local PORTALS = {
	{ side = 1, z = -70, boost = 40 },
	{ side = -1, z = 70, boost = 40 },
}

-- Sorties du soleil : depuis le ciel côté soleil, on vise un point de la place atteint en t secondes
local SUN_LAUNCHES = {
	{ pos = { -70, 130, -480 }, target = { -40, 22, -110 }, t = 2.2 },
	{ pos = { 70, 135, -470 }, target = { 40, 22, -90 }, t = 2.2 },
	{ pos = { 0, 145, -500 }, target = { 0, 22, -40 }, t = 2.4 },
}

-- Points d'apparition au sol (repli si aucun lanceur) : (x, z)
local GROUND_SPAWNS = { { 0, -30 }, { -40, 20 }, { 40, 60 }, { -30, -120 }, { 30, 140 }, { 0, 200 } }

-- Palette (direction « Ligne de mire », cf. docs/ui.md)
local GLOW = Color3.fromRGB(255, 170, 110)
local GOLD = Color3.fromRGB(255, 211, 110)
local GROUND = Color3.fromRGB(190, 134, 94)
local CLIFF = Color3.fromRGB(176, 116, 86)
local FOG = Color3.fromRGB(214, 140, 112) -- couleur de l'Atmosphere du crépuscule, un ton plus sombre
-- Matières définitives (MaterialVariant de MaterialService, exportées dans assets/rbx/Materials). Le sable garde la
-- matière Sand de Roblox (une texture générée a été rejetée), comme le Terrain des dunes.
local MAT_FACADE = "ArenaFacade"
local MAT_CLIFF = "ArenaCliff"

---------------------------------------------------------------------------------------------------------------------

local rng = Random.new(SEED)
-- Décor ajouté après coup (enseignes, toits ensablés, falaise, silhouettes étagées) : tirage à part, pour ne pas
-- décaler celui du plan jouable (hauteurs des tours, place)
local deco = Random.new(SEED + 1000)
local base = CFrame.lookAt(Vector3.zero, SUN_DIR)

-- Cette méthode permet de passer du repère du plan au monde lorsqu'on place une pièce.
local function g(x: number, y: number, z: number): CFrame
	return base * CFrame.new(x, y, z)
end

-- Cette méthode permet de convertir un point du plan en position monde lorsqu'on vise une cible.
local function gp(x: number, y: number, z: number): Vector3
	return g(x, y, z).Position
end

local map = Instance.new("Model")
map.Name = "Map"
map:SetAttribute("Generator", "tools/map/build_arena.luau")
map:SetAttribute("Seed", SEED)
map:SetAttribute("KillHeight", KILL_HEIGHT)
-- sable en Terrain (Shared.DuneField, posé par Server.MapTerrain au démarrage) : repère du plan et anneau
map:SetAttribute("DunesPlan", base)
map:SetAttribute("DunesRing", Vector3.new(RING_W, RING_L, BANK_H / math.tan(math.rad(BANK_SLOPE))))
local folders = {}
for _, name in { "Ground", "Ramps", "Buildings", "Props", "Skyline", "Boosts", "BoostFx", "GroundSpawns", "SunLaunch" } do
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

-- Cette méthode permet d'habiller une pièce d'une matière définitive (MaterialVariant) lorsqu'on la crée.
local function skin(p: BasePart, variant: string): BasePart
	p.MaterialVariant = variant
	return p
end

-- Cette méthode permet de rendre une pièce purement décorative (ni collision, ni raycast, ni ombre portée
-- optionnelle) lorsqu'elle ne doit pas gêner le mouvement fait maison.
local function ghost(p: BasePart, castShadow: boolean?): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = castShadow == true
	return p
end

-- Cette méthode permet de tirer une teinte d'immeuble sombre lorsqu'on crée un bloc.
local function ink(): Color3
	return Color3.fromRGB(rng:NextInteger(32, 60), rng:NextInteger(29, 44), rng:NextInteger(35, 49))
end

-- Cette méthode permet de tirer une teinte de façade (même tirage que ink, un ton plus clair sous la texture)
-- lorsqu'on crée un gratte-ciel.
local function facade(): Color3
	return Color3.fromRGB(rng:NextInteger(78, 104), rng:NextInteger(66, 84), rng:NextInteger(70, 88))
end

-- Cette méthode permet de tirer une teinte de sable lorsqu'on crée une dune.
local function sand(): Color3
	local k = rng:NextNumber()
	return Color3.fromRGB(176 + k * 24, 118 + k * 24, 82 + k * 16)
end

-- Cette méthode permet de tirer une teinte de sable pour le décor sans toucher au tirage du plan jouable.
local function decoSand(): Color3
	local k = deco:NextNumber()
	return Color3.fromRGB(176 + k * 24, 118 + k * 24, 82 + k * 16)
end

-- Cette méthode permet de poser un segment de dune surfable (WedgePart, côté haut = +Z local) dont le dos vertical
-- suit [a, b] (plan, y = 0) et dont la pente descend vers l'intérieur, opposé à `out`.
local function bankSegment(a: Vector3, b: Vector3, out: Vector3)
	local run = BANK_H / math.tan(math.rad(BANK_SLOPE))
	local along = b - a
	local len = along.Magnitude
	local mid = (a + b) / 2
	local center = mid - out * (run / 2)
	-- repère local : X le long du dos, Y vertical, Z vers l'extérieur (côté haut du WedgePart)
	local localCf =
		CFrame.fromMatrix(Vector3.new(center.X, BANK_H / 2, center.Z), Vector3.yAxis:Cross(out), Vector3.yAxis, out)
	part("Ramps", Vector3.new(len, BANK_H, run), base * localCf, sand(), Enum.Material.Sand, "WedgePart")
	-- arête ambrée en haut de la pente
	local ridgeCf = CFrame.fromMatrix(
		Vector3.new(mid.X, BANK_H + 0.2, mid.Z) - out * 0.6,
		Vector3.yAxis:Cross(out),
		Vector3.yAxis,
		out
	)
	ghost(part("Ramps", Vector3.new(len, 0.6, 0.6), base * ridgeCf, GLOW, Enum.Material.Neon))
end

-- Cette méthode permet de poser un immeuble ensablé (bloc, bande ambrée, fenêtres allumées éparses sur la face
-- tournée vers l'arène) lorsqu'on borde une ligne droite ; facing = sens de la face vers l'arène sur X (-1/1).
local function tower(x: number, z: number, w: number, d: number, h: number, facing: number)
	local sink = ISLAND_THICK - 2
	local cf = g(x, (h - sink) / 2, z)
	skin(part("Buildings", Vector3.new(d, h + sink, w), cf, facade(), Enum.Material.Concrete), MAT_FACADE)
	ghost(part("Buildings", Vector3.new(d + 0.6, 1.2, w + 0.6), g(x, h - 2.5, z), GLOW, Enum.Material.Neon))
	-- toit ensablé (décor : le joueur se pose sur le vrai toit, quelques dixièmes de stud plus bas)
	local roof = Vector3.new(d - deco:NextNumber(2, 8), 0.6, w - deco:NextNumber(2, 10))
	ghost(part("Buildings", roof, g(x, h + 0.3, z), decoSand(), Enum.Material.Sand))
	-- enseigne ensablée sur la face tournée vers l'arène : panneau sombre penché, néon à moitié éteint
	if deco:NextNumber() < 0.4 then
		local sw, sh = w * deco:NextNumber(0.35, 0.6), deco:NextNumber(7, 12)
		local sy = deco:NextNumber(BANK_H + 10, math.max(BANK_H + 12, h - sh - 6))
		local signCf = cf
			* CFrame.new(facing * (d / 2 + 1), sy - (h - sink) / 2, deco:NextNumber(-w / 5, w / 5))
			* CFrame.Angles(math.rad(deco:NextNumber(-10, 10)), 0, 0)
		ghost(part("Buildings", Vector3.new(0.6, sh, sw), signCf, Color3.fromRGB(28, 24, 30), Enum.Material.Metal))
		local lit = sw * deco:NextNumber(0.3, 0.8)
		local side = if deco:NextNumber() < 0.5 then -1 else 1
		local litCf = signCf * CFrame.new(facing * 0.4, sh / 2 - 1, (sw - lit) / 2 * side)
		ghost(part("Buildings", Vector3.new(0.3, 0.8, lit), litCf, GLOW, Enum.Material.Neon))
		-- sable accumulé sur le haut du panneau
		local drift = signCf * CFrame.new(0, sh / 2 + 0.3, 0)
		ghost(part("Buildings", Vector3.new(1.4, 0.8, sw * 0.9), drift, decoSand(), Enum.Material.Sand))
	end
	for wy = BANK_H + 8, h - 8, 14 do
		if rng:NextNumber() < 0.3 then
			local win = Vector3.new(0.4, 3, w * rng:NextNumber(0.15, 0.4))
			local off = CFrame.new(facing * (d / 2 + 0.05), wy - (h - sink) / 2, rng:NextNumber(-w / 4, w / 4))
			ghost(part("Buildings", win, cf * off, GLOW, Enum.Material.Neon))
		end
	end
	if h > 120 then
		local mast = Vector3.new(0.8, rng:NextNumber(12, 30), 0.8)
		local off = CFrame.new(0, (h + sink) / 2 + mast.Y / 2, rng:NextNumber(-w / 3, w / 3))
		ghost(part("Props", mast, cf * off, Color3.fromRGB(30, 28, 34), Enum.Material.Metal))
	end
end

-- Cette méthode permet de créer le volume invisible d'un boost lorsqu'on le pose, avec ses attributs (MapRules).
local function boostVolume(name: string, size: Vector3, cf: CFrame, kind: string)
	local p = ghost(part("Boosts", size, cf, GOLD))
	p.Name = name
	p.Transparency = 1
	p:SetAttribute("Kind", kind)
	return p
end

-- Cette méthode permet de poser un geyser ou un lanceur (dalle, colonne de sable, volume déclencheur)
-- qui projette le joueur vers `to` en `t` secondes.
local function padBoost(kind: string, i: number, b)
	local x, z = b.at[1], b.at[2]
	local from = gp(x, 3, z)
	local to = gp(b.to[1], b.to[2], b.to[3])
	local d = to - from
	local v = Vector3.new(d.X / b.t, d.Y / b.t - 0.5 * GRAVITY * b.t, d.Z / b.t)
	local vol = boostVolume(kind .. i, Vector3.new(12, 8, 12), g(x, 4, z), kind)
	vol:SetAttribute("Velocity", v)
	-- dalle et anneau
	local pad = ghost(
		part(
			"BoostFx",
			Vector3.new(0.4, 12, 12),
			g(x, 0.2, z) * CFrame.Angles(0, 0, math.pi / 2),
			GOLD,
			Enum.Material.Neon
		)
	)
	pad.Shape = Enum.PartType.Cylinder
	-- colonne visible de loin (geyser) ou flèche (lanceur), orientée vers la cible
	if kind == "Geyser" then
		local col = ghost(
			part(
				"BoostFx",
				Vector3.new(70, 9, 9),
				g(x, 35, z) * CFrame.Angles(0, 0, math.pi / 2),
				GOLD,
				Enum.Material.Neon
			)
		)
		col.Shape = Enum.PartType.Cylinder
		col.Transparency = 0.75
		local fx = Instance.new("ParticleEmitter")
		fx.Color = ColorSequence.new(Color3.fromRGB(214, 160, 110))
		fx.LightEmission = 0.3
		fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
		fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		fx.Speed = NumberRange.new(35, 55)
		fx.Lifetime = NumberRange.new(1, 1.6)
		fx.Rate = 40
		fx.SpreadAngle = Vector2.new(8, 8)
		fx.EmissionDirection = Enum.NormalId.Right -- axe du cylindre (vertical après rotation)
		fx.Parent = col
	else
		local arrow = ghost(
			part(
				"BoostFx",
				Vector3.new(4, 4, 9),
				CFrame.lookAt(from + Vector3.new(0, 6, 0), from + Vector3.new(0, 6, 0) + v),
				GOLD,
				Enum.Material.Neon,
				"WedgePart"
			)
		)
		arrow.Name = "Arrow"
	end
end

-- Cette méthode permet de poser un portique en travers d'une ligne droite (volume déclencheur et cadre ambré
-- qui épouse la pente) ; side = côté de la dune sur X (-1/1).
local function portal(i: number, b)
	local run = BANK_H / math.tan(math.rad(BANK_SLOPE))
	local toeX = b.side * (RING_W - run)
	local backX = b.side * RING_W
	local vol = boostVolume(
		"Portal" .. i,
		Vector3.new(run + 4, BANK_H + 6, 14),
		g((toeX + backX) / 2, BANK_H / 2 + 3, b.z),
		"Portal"
	)
	vol:SetAttribute("Boost", b.boost)
	-- deux bandes posées sur la pente, une barre au-dessus de l'arête
	local slopeLen = math.sqrt(run * run + BANK_H * BANK_H)
	local tilt = math.atan2(BANK_H, run) * b.side
	for _, dz in { -7, 7 } do
		local c = Vector3.new((toeX + backX) / 2, BANK_H / 2, b.z + dz)
		local cf = g(c.X, c.Y, c.Z) * CFrame.Angles(0, 0, tilt) * CFrame.new(0, 0.5, 0)
		ghost(part("BoostFx", Vector3.new(slopeLen, 0.4, 2), cf, GOLD, Enum.Material.Neon))
	end
	ghost(part("BoostFx", Vector3.new(1, 1, 16), g(backX - b.side * 2, BANK_H + 9, b.z), GOLD, Enum.Material.Neon))
	for _, dz in { -7, 7 } do
		ghost(
			part(
				"BoostFx",
				Vector3.new(1, 9, 1),
				g(backX - b.side * 2, BANK_H + 4.5, b.z + dz),
				GOLD,
				Enum.Material.Neon
			)
		)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Île : plateau en stade (rectangle + deux disques), falaise, socle qui plonge dans la brume
local islandHalfW = RING_W + TOWER_DEPTH
part(
	"Ground",
	Vector3.new(islandHalfW * 2, ISLAND_THICK, RING_L * 2),
	g(0, -ISLAND_THICK / 2, 0),
	GROUND,
	Enum.Material.Sand
)
for _, sz in { -1, 1 } do
	local disc = part(
		"Ground",
		Vector3.new(ISLAND_THICK, RING_W * 2, RING_W * 2),
		g(0, -ISLAND_THICK / 2, sz * RING_L) * CFrame.Angles(0, 0, math.pi / 2),
		GROUND,
		Enum.Material.Sand
	)
	disc.Shape = Enum.PartType.Cylinder
end
local socle = part(
	"Ground",
	Vector3.new(islandHalfW * 1.7, 160, RING_L * 2.4),
	g(0, -ISLAND_THICK - 80, 0),
	CLIFF,
	Enum.Material.Rock
)
ghost(skin(socle, MAT_CLIFF), true)
-- falaise qui s'effile vers la brume : blocs de roche de plus en plus étroits sous le socle
for i = 1, 4 do
	local k = 1 - i * 0.18
	local chunk = Vector3.new(islandHalfW * 1.6 * k, deco:NextNumber(50, 80), RING_L * 2.2 * k)
	local cf = g(deco:NextNumber(-20, 20), -ISLAND_THICK - 150 - i * 45, deco:NextNumber(-30, 30))
		* CFrame.Angles(0, deco:NextNumber(-0.25, 0.25), math.rad(deco:NextNumber(-6, 6)))
	ghost(skin(part("Ground", chunk, cf, CLIFF, Enum.Material.Rock), MAT_CLIFF), true)
end
-- mer de brume sous l'île (décor, sans collision : on meurt avant de la toucher) : un fond opaque et des nappes
-- translucides, d'où sortent la falaise et les silhouettes
local seaFloor = Color3.fromRGB(110, 66, 58)
ghost(part("Ground", Vector3.new(4000, 2, 4000), g(0, -300, 0), seaFloor, Enum.Material.SmoothPlastic))
for _, layer in { { -250, 0.35 }, { -200, 0.6 }, { -160, 0.8 } } do
	local sheet = ghost(part("Ground", Vector3.new(4000, 1, 4000), g(0, layer[1], 0), FOG, Enum.Material.SmoothPlastic))
	sheet.Transparency = layer[2]
end

-- Anneau de dunes : deux lignes droites, puis les virages en segments
for _, side in { -1, 1 } do
	local out = Vector3.new(side, 0, 0)
	bankSegment(Vector3.new(side * RING_W, 0, -RING_L - 1), Vector3.new(side * RING_W, 0, RING_L + 1), out)
end
for _, sz in { -1, 1 } do
	local cz = sz * RING_L
	local step = math.pi / ARC_SEGMENTS
	for i = 0, ARC_SEGMENTS - 1 do
		-- virage +Z : de t = 0 (x = +W) à t = π (x = -W) ; virage -Z : de π à 2π
		local t0 = (if sz > 0 then 0 else math.pi) + i * step
		local t1 = t0 + step
		local tm = (t0 + t1) / 2
		local over = 0.01
		local a = Vector3.new(RING_W * math.cos(t0 - over), 0, cz + RING_W * math.sin(t0 - over))
		local b = Vector3.new(RING_W * math.cos(t1 + over), 0, cz + RING_W * math.sin(t1 + over))
		bankSegment(a, b, Vector3.new(math.cos(tm), 0, math.sin(tm)))
	end
end
task.wait()

-- Ceinture de gratte-ciel le long des lignes droites (les virages restent ouverts sur le vide)
for _, side in { -1, 1 } do
	local z = -RING_L
	while z < RING_L - 10 do
		local w = math.min(rng:NextNumber(44, 60), RING_L - z)
		local zc = z + w / 2
		local h = if math.abs(zc) < 35 then rng:NextNumber(105, 125) else rng:NextNumber(70, 150)
		tower(side * (RING_W + TOWER_DEPTH / 2), zc, w - 1, TOWER_DEPTH, h, -side)
		z += w
	end
end
task.wait()

-- Passerelle des snipers entre les deux tours centrales, rambardes ambrées
part(
	"Props",
	Vector3.new(RING_W * 2, 3, BRIDGE_W),
	g(0, BRIDGE_Y - 1.5, 0),
	Color3.fromRGB(45, 40, 54),
	Enum.Material.Metal
)
for _, dz in { -1, 1 } do
	part(
		"Props",
		Vector3.new(RING_W * 2, 3, 0.6),
		g(0, BRIDGE_Y + 1.5, dz * (BRIDGE_W / 2 - 0.3)),
		Color3.fromRGB(45, 40, 54),
		Enum.Material.Metal
	)
	ghost(
		part(
			"Props",
			Vector3.new(RING_W * 2, 0.4, 0.4),
			g(0, BRIDGE_Y + 3.2, dz * (BRIDGE_W / 2 - 0.3)),
			GLOW,
			Enum.Material.Neon
		)
	)
end

-- Place : bus ensevelis, kiosque, murets, petites dunes marchables (couverts pour qui a perdu sa vitesse)
local BUS = Color3.fromRGB(122, 58, 38)
part(
	"Props",
	Vector3.new(10, 10, 32),
	g(-38, 3, 55) * CFrame.Angles(math.rad(-8), math.rad(20), math.rad(6)),
	BUS,
	Enum.Material.Metal
)
part(
	"Props",
	Vector3.new(10, 10, 32),
	g(40, 3, -40) * CFrame.Angles(math.rad(6), math.rad(-35), math.rad(-5)),
	BUS,
	Enum.Material.Metal
)
part(
	"Props",
	Vector3.new(10, 10, 32),
	g(10, 3, 180) * CFrame.Angles(0, math.rad(75), math.rad(8)),
	BUS,
	Enum.Material.Metal
)
part(
	"Props",
	Vector3.new(10, 10, 32),
	g(-15, 3, -190) * CFrame.Angles(math.rad(10), math.rad(-60), 0),
	BUS,
	Enum.Material.Metal
)
part("Props", Vector3.new(18, 13, 18), g(0, 6.5, -110), ink(), Enum.Material.Concrete)
ghost(part("Props", Vector3.new(18.6, 0.8, 18.6), g(0, 12, -110), GLOW, Enum.Material.Neon))
for _, w in
	{ { -50, -10, 26, 0.3 }, { 52, 30, 30, -0.2 }, { -20, 130, 22, 0.1 }, { 25, -150, 24, 1.2 }, { -55, -70, 20, 1.4 } }
do
	part(
		"Props",
		Vector3.new(w[3], 5, 3),
		g(w[1], 2.5, w[2]) * CFrame.Angles(0, w[4], 0),
		ink(),
		Enum.Material.Concrete
	)
end
for _, m in { { -10, 20, 34, 7, 0.4 }, { 30, 100, 30, 6, -0.6 }, { -35, -150, 30, 6, 0.9 } } do
	-- dune marchable à ~30° des deux côtés (deux WedgePart dos à dos)
	local run = m[4] / math.tan(math.rad(30))
	for _, s in { -1, 1 } do
		local cf = g(m[1], m[4] / 2, m[2])
			* CFrame.Angles(0, m[5] + (if s > 0 then 0 else math.pi), 0)
			* CFrame.new(0, 0, -run / 2)
		part("Props", Vector3.new(m[3], m[4], run), cf, sand(), Enum.Material.Sand, "WedgePart")
	end
end
task.wait()

-- Silhouettes lointaines qui sortent de la brume : décor hors d'atteinte, sans collision
for _ = 1, 50 do
	local a = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(650, 1400)
	local h = rng:NextNumber(260, 520)
	local w = rng:NextNumber(40, 90)
	local tilt = if rng:NextNumber() < 0.2 then math.rad(rng:NextNumber(10, 30)) else 0
	local cf = g(math.cos(a) * dist, -260 + h / 2, math.sin(a) * dist)
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), tilt)
	ghost(skin(part("Skyline", Vector3.new(w, h, w), cf, ink(), Enum.Material.Concrete), MAT_FACADE), true)
	-- étages en retrait et, sur certaines, un feu ambré au sommet
	local top, tw = h / 2, w
	for _ = 1, deco:NextInteger(0, 2) do
		tw *= deco:NextNumber(0.55, 0.8)
		local th = deco:NextNumber(30, 90)
		local tint = Color3.fromRGB(deco:NextInteger(32, 60), deco:NextInteger(29, 44), deco:NextInteger(35, 49))
		local tierCf = cf * CFrame.new(0, top + th / 2, 0)
		ghost(skin(part("Skyline", Vector3.new(tw, th, tw), tierCf, tint, Enum.Material.Concrete), MAT_FACADE), true)
		top += th
	end
	if deco:NextNumber() < 0.3 then
		ghost(part("Skyline", Vector3.new(2, 2, 2), cf * CFrame.new(0, top + 1, 0), GLOW, Enum.Material.Neon))
	end
end

-- Boosts
for i, b in GEYSERS do
	padBoost("Geyser", i, b)
end
for i, b in LAUNCHERS do
	padBoost("Launcher", i, b)
end
for i, b in PORTALS do
	portal(i, b)
end

-- Points d'apparition au sol (repli de SpawnManager)
for i, s in GROUND_SPAWNS do
	local p = ghost(part("GroundSpawns", Vector3.new(4, 1, 4), g(s[1], 0.5, s[2]), GLOW))
	p.Name = "Spawn" .. i
	p.Transparency = 1
end

-- Sorties du soleil : LookVector = direction, attribut Speed, visées pour atteindre la place (balistique)
for i, l in SUN_LAUNCHES do
	local from = gp(l.pos[1], l.pos[2], l.pos[3])
	local to = gp(l.target[1], l.target[2], l.target[3])
	local d = to - from
	local v = Vector3.new(d.X / l.t, d.Y / l.t - 0.5 * GRAVITY * l.t, d.Z / l.t)
	local p = ghost(part("SunLaunch", Vector3.new(4, 4, 4), CFrame.lookAt(from, from + v), GLOW))
	p.Name = "Launch" .. i
	p.Transparency = 1
	p:SetAttribute("Speed", math.floor(v.Magnitude * 10 + 0.5) / 10)
end

-- Remplace la map générée précédente ; refuse d'écraser une map qui ne vient pas d'un générateur
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
-- aperçu du sable en Terrain (même code qu'au démarrage du serveur), si le code du jeu est synchronisé dans Studio
local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local terrainModule = server and server:FindFirstChild("MapTerrain")
local columns = if terrainModule then require(terrainModule:Clone()).build(map) else 0
return string.format(
	"Map générée : %d instances, %s",
	count,
	if terrainModule then columns .. " colonnes de sable" else "sable non prévisualisé (Server.MapTerrain absent)"
)

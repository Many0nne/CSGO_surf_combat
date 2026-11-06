--!nocheck
-- ShadowCulling.luau
-- Repère les pièces dont l'ombre portée ne se voit pas, pour leur couper CastShadow (cf. docs/performance.md).
-- Une pièce entièrement dans l'ombre d'autres pièces opaques n'ajoute rien à l'image : son ombre tombe là où celle de
-- ses masques tombe déjà. Le long de chaque rayon vers le soleil, la pièce la plus proche du soleil garde son ombre
-- (elle a une face éclairée), donc couper toutes les pièces masquées ne retire aucune ombre, même en chaîne.
-- Calcul en arithmétique pure (pas de Vector3) : des boîtes orientées et des coins (WedgePart), une grille régulière,
-- un rayon par point d'échantillonnage des faces tournées vers le soleil. Testé : tests/specs/ShadowCulling.spec.luau.

local ShadowCulling = {}

ShadowCulling.CELL = 16 -- studs, côté d'une cellule de la grille
ShadowCulling.SPACING = 2 -- studs entre deux points d'échantillonnage d'une face
ShadowCulling.MAX_PER_AXIS = 32 -- points au plus par côté de face (grandes faces : espacement plus large)
ShadowCulling.OFFSET = 0.02 -- studs : le point est décollé de la face pour ne pas se toucher lui-même
ShadowCulling.MAX_DIST = 4000 -- studs : longueur des rayons vers le soleil

local EPS = 1e-9
local BIAS = 512 -- décalage des indices de cellule (positifs) dans la clé numérique

-- Une boîte : centre (px, py, pz), axes unitaires X (xx, xy, xz), Y, Z (repère de la CFrame), taille (sx, sy, sz).
-- wedge = true : coin Roblox, dont l'intérieur vérifie y·sz − z·sy ≤ 0 en repère local (pente vers l'avant-haut).
export type Box = {
	px: number,
	py: number,
	pz: number,
	xx: number,
	xy: number,
	xz: number,
	yx: number,
	yy: number,
	yz: number,
	zx: number,
	zy: number,
	zz: number,
	sx: number,
	sy: number,
	sz: number,
	wedge: boolean,
}

-- Cette méthode permet de calculer la clé numérique d'une cellule de la grille lorsqu'on range ou parcourt les boîtes.
local function cellKey(ix: number, iy: number, iz: number): number
	return ((ix + BIAS) * 1024 + (iy + BIAS)) * 1024 + (iz + BIAS)
end

-- Cette méthode permet de calculer la demi-étendue alignée sur les axes du monde d'une boîte orientée lorsqu'on la
-- range dans la grille.
local function halfExtents(b: Box): (number, number, number)
	local hx, hy, hz = b.sx / 2, b.sy / 2, b.sz / 2
	return math.abs(b.xx) * hx + math.abs(b.yx) * hy + math.abs(b.zx) * hz,
		math.abs(b.xy) * hx + math.abs(b.yy) * hy + math.abs(b.zy) * hz,
		math.abs(b.xz) * hx + math.abs(b.yz) * hy + math.abs(b.zz) * hz
end

-- Cette méthode permet de dire si le rayon (o + t·d, 0 ≤ t ≤ maxT) traverse une boîte ou un coin lorsqu'on cherche
-- un masque entre un point et le soleil (un point déjà à l'intérieur compte comme masqué).
function ShadowCulling.rayHits(
	b: Box,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	maxT: number
)
	local rx, ry, rz = ox - b.px, oy - b.py, oz - b.pz
	-- origine et direction en repère local
	local lo =
		{ rx * b.xx + ry * b.xy + rz * b.xz, rx * b.yx + ry * b.yy + rz * b.yz, rx * b.zx + ry * b.zy + rz * b.zz }
	local ld =
		{ dx * b.xx + dy * b.xy + dz * b.xz, dx * b.yx + dy * b.yy + dz * b.yz, dx * b.zx + dy * b.zy + dz * b.zz }
	local half = { b.sx / 2, b.sy / 2, b.sz / 2 }
	local tmin, tmax = 0, maxT
	for a = 1, 3 do
		local o, d, h = lo[a], ld[a], half[a]
		if math.abs(d) < EPS then
			if o < -h or o > h then
				return false
			end
		else
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then
				tmin = t1
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return false
			end
		end
	end
	if b.wedge then
		-- demi-espace f(q) = q.y·sz − q.z·sy ≤ 0
		local fo = lo[2] * b.sz - lo[3] * b.sy
		local fd = ld[2] * b.sz - ld[3] * b.sy
		if math.abs(fd) < EPS then
			if fo > 0 then
				return false
			end
		elseif fd > 0 then
			tmax = math.min(tmax, -fo / fd)
		else
			tmin = math.max(tmin, -fo / fd)
		end
		if tmin > tmax then
			return false
		end
	end
	return true
end

-- Cette méthode permet de produire les points d'échantillonnage des faces d'une boîte tournées vers le soleil
-- lorsqu'on teste si elle est entièrement à l'ombre (points en repère monde, décollés de la face).
function ShadowCulling.samples(b: Box, sun: { number }): { { number } }
	local points = {}
	local hx, hy, hz = b.sx / 2, b.sy / 2, b.sz / 2
	local spacing, maxN, off = ShadowCulling.SPACING, ShadowCulling.MAX_PER_AXIS, ShadowCulling.OFFSET

	-- Cette méthode permet de convertir un point local, décalé le long d'une normale locale, en point monde.
	local function emit(x: number, y: number, z: number, nx: number, ny: number, nz: number)
		x, y, z = x + nx * off, y + ny * off, z + nz * off
		table.insert(points, {
			b.px + x * b.xx + y * b.yx + z * b.zx,
			b.py + x * b.xy + y * b.yy + z * b.zy,
			b.pz + x * b.xz + y * b.yz + z * b.zz,
		})
	end

	-- Cette méthode permet de dire si une normale locale regarde le soleil (produit scalaire monde positif).
	local function facesSun(nx: number, ny: number, nz: number): boolean
		local wx = nx * b.xx + ny * b.yx + nz * b.zx
		local wy = nx * b.xy + ny * b.yy + nz * b.zy
		local wz = nx * b.xz + ny * b.yz + nz * b.zz
		return wx * sun[1] + wy * sun[2] + wz * sun[3] > 1e-6
	end

	-- Cette méthode permet de répartir n valeurs sur [-h, h] (bords compris, en retrait de 2 % de la face au plus).
	local function steps(h: number): { number }
		local n = math.clamp(math.ceil(2 * h / spacing) + 1, 2, maxN)
		local inset = math.min(0.02, h / 4)
		local list = {}
		for i = 0, n - 1 do
			table.insert(list, -h + inset + (2 * (h - inset)) * i / (n - 1))
		end
		return list
	end

	local xs, ys, zs = steps(hx), steps(hy), steps(hz)
	-- Cette méthode permet de dire si un point local est dans le coin (toujours vrai pour une boîte).
	local function inside(y: number, z: number): boolean
		return not b.wedge or y * b.sz - z * b.sy <= 1e-6
	end

	for _, sign in { -1, 1 } do
		-- faces ±X (triangles pour un coin)
		if facesSun(sign, 0, 0) then
			for _, y in ys do
				for _, z in zs do
					if inside(y, z) then
						emit(sign * hx, y, z, sign, 0, 0)
					end
				end
			end
		end
		-- faces ±Y (un coin n'a que le dessous)
		if (not b.wedge or sign < 0) and facesSun(0, sign, 0) then
			for _, x in xs do
				for _, z in zs do
					emit(x, sign * hy, z, 0, sign, 0)
				end
			end
		end
		-- faces ±Z (un coin n'a que l'arrière, +Z)
		if (not b.wedge or sign > 0) and facesSun(0, 0, sign) then
			for _, x in xs do
				for _, y in ys do
					emit(x, y, sign * hz, 0, 0, sign)
				end
			end
		end
	end
	if b.wedge then
		-- pente : de l'avant-bas (z = -hz, y = -hy) à l'arrière-haut (z = hz, y = hy), normale (0, sz, -sy)
		local len = math.sqrt(b.sy * b.sy + b.sz * b.sz)
		local ny, nz = b.sz / len, -b.sy / len
		if facesSun(0, ny, nz) then
			local ts = steps(len / 2)
			for _, x in xs do
				for _, t in ts do
					local f = (t + len / 2) / len -- 0 à l'avant, 1 à l'arrière
					emit(x, -hy + f * b.sy, -hz + f * b.sz, 0, ny, nz)
				end
			end
		end
	end
	return points
end

-- Cette méthode permet de lister les boîtes candidates entièrement à l'ombre des masques lorsque le générateur décide
-- à qui couper CastShadow. `occluders[i]` : la boîte i arrête la lumière (opaque, garde son ombre) ;
-- `candidates[i]` : la boîte i est à tester. `sun` : direction unitaire vers le soleil. Renvoie { [i] = true }.
function ShadowCulling.shadowed(
	boxes: { Box },
	occluders: { [number]: boolean },
	candidates: { [number]: boolean },
	sun: { number }
): { [number]: boolean }
	local cell = ShadowCulling.CELL
	local grid: { [number]: { number } } = {}
	local gmin = { math.huge, math.huge, math.huge }
	local gmax = { -math.huge, -math.huge, -math.huge }
	for i, b in boxes do
		if occluders[i] then
			local ex, ey, ez = halfExtents(b)
			local lo = { b.px - ex, b.py - ey, b.pz - ez }
			local hi = { b.px + ex, b.py + ey, b.pz + ez }
			for a = 1, 3 do
				gmin[a] = math.min(gmin[a], lo[a])
				gmax[a] = math.max(gmax[a], hi[a])
			end
			for ix = math.floor(lo[1] / cell), math.floor(hi[1] / cell) do
				for iy = math.floor(lo[2] / cell), math.floor(hi[2] / cell) do
					for iz = math.floor(lo[3] / cell), math.floor(hi[3] / cell) do
						local key = cellKey(ix, iy, iz)
						local list = grid[key]
						if not list then
							list = {}
							grid[key] = list
						end
						table.insert(list, i)
					end
				end
			end
		end
	end

	local stamp: { [number]: number } = {}
	local rayId = 0
	local dx, dy, dz = sun[1], sun[2], sun[3]
	local dir = { dx, dy, dz }
	local maxT = ShadowCulling.MAX_DIST

	-- Cette méthode permet de dire si un point est masqué du soleil par un masque autre que `self` lorsqu'on parcourt
	-- la grille cellule par cellule le long du rayon (DDA).
	local function blocked(p: { number }, self: number): boolean
		rayId += 1
		-- fin du parcours : sortie de la boîte englobante des masques
		local tEnd = maxT
		for a = 1, 3 do
			if math.abs(dir[a]) > EPS then
				local bound = if dir[a] > 0 then gmax[a] else gmin[a]
				tEnd = math.min(tEnd, math.max(0, (bound - p[a]) / dir[a]))
			elseif p[a] < gmin[a] or p[a] > gmax[a] then
				return false
			end
		end
		local idx = { math.floor(p[1] / cell), math.floor(p[2] / cell), math.floor(p[3] / cell) }
		local stepA, tMaxA, tDeltaA = {}, {}, {}
		for a = 1, 3 do
			if dir[a] > EPS then
				stepA[a] = 1
				tMaxA[a] = ((idx[a] + 1) * cell - p[a]) / dir[a]
				tDeltaA[a] = cell / dir[a]
			elseif dir[a] < -EPS then
				stepA[a] = -1
				tMaxA[a] = (idx[a] * cell - p[a]) / dir[a]
				tDeltaA[a] = -cell / dir[a]
			else
				stepA[a] = 0
				tMaxA[a] = math.huge
				tDeltaA[a] = math.huge
			end
		end
		local t = 0
		while t <= tEnd do
			local list = grid[cellKey(idx[1], idx[2], idx[3])]
			if list then
				for _, j in list do
					if j ~= self and stamp[j] ~= rayId then
						stamp[j] = rayId
						if ShadowCulling.rayHits(boxes[j], p[1], p[2], p[3], dx, dy, dz, maxT) then
							return true
						end
					end
				end
			end
			local a = if tMaxA[1] < tMaxA[2]
				then (if tMaxA[1] < tMaxA[3] then 1 else 3)
				else (if tMaxA[2] < tMaxA[3] then 2 else 3)
			t = tMaxA[a]
			idx[a] += stepA[a]
			tMaxA[a] += tDeltaA[a]
		end
		return false
	end

	local result = {}
	for i, b in boxes do
		if candidates[i] then
			local all = true
			for _, p in ShadowCulling.samples(b, sun) do
				if not blocked(p, i) then
					all = false
					break
				end
			end
			if all then
				result[i] = true
			end
		end
	end
	return result
end

return ShadowCulling

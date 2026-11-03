-- Champ de dunes de l'Arène (#71) : hauteur du sable en tout point du sol de l'île, dans le repère du plan
-- (cf. tools/map/build_arena.luau). Règles pures et déterministes, testées sous Lune ; le Terrain est posé par
-- src/server/MapTerrain.luau. Imite le sable : grandes dunes transverses au vent, dos en pente douce et face
-- d'éboulement à ~34° (angle de repos), petites dunes obliques par-dessus, rides, champs de dunes séparés de
-- couloirs plats. Les dunes s'effacent au pied des rampes : le sable ne doit jamais dépasser de la surface d'une
-- rampe de surf. Reste marchable partout (pente < SURF_NORMAL_Y).

local DuneField = {}

-- Attributs posés par le générateur sur Maps.Map : sans eux, pas de dunes (ancienne ville)
DuneField.PLAN_ATTRIBUTE = "DunesPlan" -- CFrame du repère du plan (origine au centre de la place)
DuneField.RING_ATTRIBUTE = "DunesRing" -- Vector3 (demi-largeur de l'anneau, demi-longueur, largeur au sol de la rampe)

DuneField.FLOOR = 0.6 -- épaisseur minimale du sable au-dessus du sol de l'île (y = 0), qui le recouvre partout
DuneField.MAX_HEIGHT = 24 -- borne haute du sable, pour dimensionner la région de Terrain
DuneField.VOXEL = 4 -- résolution du Terrain Roblox

-- direction du vent dans le plan (unitaire) : u le long du vent, v en travers
local WIND_X, WIND_Z = 0.8, 0.6
local BIG_WAVELENGTH = 72
local BIG_HEIGHT = 11
local SMALL_WAVELENGTH = 26
local SMALL_HEIGHT = 2
local TOE_BLEND = 28 -- distance sur laquelle les dunes s'effacent avant le pied d'une rampe
local FLAT_BLEND = 30 -- distance sur laquelle le sable remonte autour d'une zone plate

-- Cette méthode permet d'adoucir une transition 0 -> 1 lorsqu'on mélange deux hauteurs.
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Cette méthode permet de donner le profil d'une dune (0 au creux, 1 à la crête) lorsqu'on avance dans le sens du
-- vent : dos qui monte en douceur sur (1 - slip) de la période, face d'éboulement raide sur `slip`.
local function profile(phase: number, slip: number): number
	local t = phase - math.floor(phase)
	if t < 1 - slip then
		return smooth(t / (1 - slip)) ^ 1.3
	end
	return 1 - smooth((t - (1 - slip)) / slip)
end

-- Cette méthode permet de calculer la hauteur du sable en (x, z) du plan lorsqu'on construit le Terrain ; nil hors de
-- l'anneau. ring = (demi-largeur, demi-longueur, largeur au sol de la rampe) ; flats = { {x, z, rayon} } à garder plats
-- (points d'apparition, dalles des geysers et lanceurs).
function DuneField.height(x: number, z: number, ring: Vector3, flats: { { number } }): number?
	local dz = math.max(0, math.abs(z) - ring.Y)
	local fromBack = ring.X - math.sqrt(x * x + dz * dz)
	if fromBack < DuneField.VOXEL then
		return nil
	end
	local u = x * WIND_X + z * WIND_Z
	local v = -x * WIND_Z + z * WIND_X
	local big =
		profile(u / BIG_WAVELENGTH + 0.6 * math.noise(v / 110, 3.1) + 0.2 * math.noise(v / 40, u / 70, 7.7), 0.4)
	local small = profile((u * 0.9 + v * 0.45) / SMALL_WAVELENGTH + 0.5 * math.noise(v / 50, 1.7), 0.4)
	-- champs de dunes et couloirs presque plats (bruit basse fréquence)
	local zone = smooth(0.45 + 1.1 * math.noise(x / 160, z / 160, 1.3))
	local h = DuneField.FLOOR
		+ BIG_HEIGHT * zone * big
		+ SMALL_HEIGHT * (0.15 + 0.85 * zone) * small
		+ 0.6 * (math.noise(x / 18, z / 18, 5.5) + 0.5)
	for _, f in flats do
		local d = math.sqrt((x - f[1]) ^ 2 + (z - f[2]) ^ 2)
		h = DuneField.FLOOR + (h - DuneField.FLOOR) * smooth((d - f[3]) / FLAT_BLEND)
	end
	-- au pied des rampes : sable à plat (sous la rampe, il est caché ; au pied, il n'en mord que le bas)
	h = DuneField.FLOOR + (h - DuneField.FLOOR) * smooth((fromBack - ring.Z) / TOE_BLEND)
	return math.clamp(h, DuneField.FLOOR, DuneField.MAX_HEIGHT)
end

return DuneField

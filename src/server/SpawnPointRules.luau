-- Choix du point d'apparition (#288), règle pure testée par tests/specs/SpawnPointRules.spec.luau ; SpawnManager
-- l'applique avec les points GroundSpawns de la map, les ennemis vivants et un vrai raycast de vue.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local SpawnPointRules = {}

-- Hauteur des yeux au-dessus d'une racine de personnage (celle des bots, BotConfig.EYE_HEIGHT) et d'un point
-- d'apparition (racine posée ROOT_ABOVE_POINT studs au-dessus du point, SpawnManager.place) : la vue se teste d'yeux à yeux
SpawnPointRules.ROOT_ABOVE_POINT = 5
SpawnPointRules.ROOT_EYE_OFFSET = BotConfig.EYE_HEIGHT
SpawnPointRules.POINT_EYE_OFFSET = SpawnPointRules.ROOT_ABOVE_POINT + BotConfig.EYE_HEIGHT

-- Une pièce au moins aussi transparente se voit au travers (grillages de Dizzy : 0,55 ; murs d'air : 1)
SpawnPointRules.SEE_THROUGH_TRANSPARENCY = 0.5

-- Cette méthode permet de savoir si une pièce de la map arrête le regard lorsque SpawnManager prépare son test de vue :
-- ni mur d'air (dossier Clips, il n'arrête ni le regard ni les balles), ni pièce transparente (grillage).
function SpawnPointRules.blocksSight(inClips: boolean, transparency: number): boolean
	return not inClips and transparency < SpawnPointRules.SEE_THROUGH_TRANSPARENCY
end

-- Test de vue injecté : true si un ennemi aux yeux en `from` voit des yeux en `to`
export type IsVisible = (from: Vector3, to: Vector3) -> boolean
-- Tirage injecté : un entier uniforme de 1 à n
export type Pick = (n: number) -> number

-- Cette méthode permet de savoir si un point convient lorsqu'on choisit où faire apparaître un personnage : aucun
-- ennemi à moins de SPAWN_SAFE_RADIUS, aucun ennemi qui le voit (yeux à yeux, à toute distance). Les distances sont
-- testées d'abord : un point trop proche ne coûte aucun raycast.
function SpawnPointRules.isSafe(point: Vector3, enemies: { Vector3 }, isVisible: IsVisible): boolean
	for _, enemy in enemies do
		if (enemy - point).Magnitude < GameConfig.SPAWN_SAFE_RADIUS then
			return false
		end
	end
	for _, enemy in enemies do
		if isVisible(enemy, point) then
			return false
		end
	end
	return true
end

-- Cette méthode permet de choisir le repli lorsqu'aucun point n'est sûr : les points les plus loin de leur ennemi le
-- plus proche, puis, à égalité, ceux que voient le moins d'ennemis ; renvoie leurs indices (au moins un).
function SpawnPointRules.farthest(points: { Vector3 }, enemies: { Vector3 }, isVisible: IsVisible): { number }
	local best, tied = -math.huge, {}
	for i, point in points do
		local nearest = math.huge
		for _, enemy in enemies do
			nearest = math.min(nearest, (enemy - point).Magnitude)
		end
		if nearest > best + 1e-6 then
			best, tied = nearest, { i }
		elseif nearest >= best - 1e-6 then
			table.insert(tied, i)
		end
	end
	if #tied <= 1 then
		return tied
	end
	local fewest, kept = math.huge, {}
	for _, i in tied do
		local seers = 0
		for _, enemy in enemies do
			if isVisible(enemy, points[i]) then
				seers += 1
			end
		end
		if seers < fewest then
			fewest, kept = seers, { i }
		elseif seers == fewest then
			table.insert(kept, i)
		end
	end
	return kept
end

-- Cette méthode permet de choisir un point d'apparition lorsqu'un personnage apparaît : tirage uniforme parmi les
-- points sûrs (isSafe), sinon parmi les plus éloignés des ennemis (farthest, décision de #288). Points et ennemis sont
-- des positions d'yeux. Renvoie l'indice du point (nil sans point) et true s'il est sûr.
function SpawnPointRules.choose(
	points: { Vector3 },
	enemies: { Vector3 },
	isVisible: IsVisible,
	pick: Pick
): (number?, boolean)
	if #points == 0 then
		return nil, false
	end
	local safe = {}
	for i, point in points do
		if SpawnPointRules.isSafe(point, enemies, isVisible) then
			table.insert(safe, i)
		end
	end
	if #safe == 0 then
		local fallback = SpawnPointRules.farthest(points, enemies, isVisible)
		return fallback[pick(#fallback)], false
	end
	return safe[pick(#safe)], true
end

return SpawnPointRules

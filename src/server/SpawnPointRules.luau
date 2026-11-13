-- Choix du point d'apparition (#288), règle pure testée par tests/specs/SpawnPointRules.spec.luau ; SpawnManager
-- l'applique avec les points GroundSpawns de la map, les ennemis vivants et un vrai raycast de vue.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local SpawnPointRules = {}

-- Hauteur des yeux au-dessus d'un point d'apparition ou d'une racine de personnage (studs) : la vue se teste d'yeux à
-- yeux (racine posée 5 studs au-dessus du point, yeux 1,5 stud au-dessus de la racine)
SpawnPointRules.POINT_EYE_OFFSET = 6.5
SpawnPointRules.ROOT_EYE_OFFSET = 1.5

-- Test de vue injecté : true si un ennemi aux yeux en `from` voit des yeux en `to`
export type IsVisible = (from: Vector3, to: Vector3) -> boolean
-- Tirage injecté : un entier uniforme de 1 à n
export type Pick = (n: number) -> number

-- Cette méthode permet de savoir si un point convient lorsqu'on choisit où faire apparaître un personnage : aucun
-- ennemi à moins de SPAWN_SAFE_RADIUS, aucun ennemi qui le voit (yeux à yeux, à toute distance).
function SpawnPointRules.isSafe(point: Vector3, enemies: { Vector3 }, isVisible: IsVisible): boolean
	for _, enemy in enemies do
		if (enemy - point).Magnitude < GameConfig.SPAWN_SAFE_RADIUS or isVisible(enemy, point) then
			return false
		end
	end
	return true
end

-- Cette méthode permet de choisir un point d'apparition lorsqu'un personnage apparaît : tirage uniforme parmi les
-- points sûrs (isSafe), ou parmi tous si aucun ne l'est. Points et ennemis sont des positions d'yeux. Renvoie l'indice
-- du point (nil sans point) et true s'il est sûr.
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
		return pick(#points), false
	end
	return safe[pick(#safe)], true
end

return SpawnPointRules

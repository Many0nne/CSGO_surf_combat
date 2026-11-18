-- Copie locale d'un morceau de la map jouée, posée loin de la vraie (aucun joueur ni bot n'y passe), pour les scènes du
-- menu : accueil (MenuScene) et démonstration des effets de tir (EffectStage, #575). Seules les pièces visibles vues
-- depuis les points de vue donnés sont copiées, ancrées et sans collision ni requête.
local Rules = require(script.Parent.MenuSceneRules)

local MapCopy = {}

-- Point de vue d'une copie : œil et direction du regard (coordonnées de la vraie map)
export type View = { eye: Vector3, forward: Vector3 }
-- Cône copié autour de chaque vue : tangente du demi-angle, distance maximale, voisinage de l'œil gardé en entier
export type Cone = { tanHalf: number, distance: number, near: number }

-- Cette méthode permet de dire si une pièce de la map est vue depuis l'un des points de vue lorsque la copie la trie.
local function seen(part: BasePart, views: { View }, cone: Cone): boolean
	for _, view in views do
		if
			Rules.inView(
				part.Position,
				part.Size.Magnitude / 2,
				view.eye,
				view.forward,
				cone.tanHalf,
				cone.distance,
				cone.near
			)
		then
			return true
		end
	end
	return false
end

-- Cette méthode permet de copier dans `folder`, décalées de `offset` et sans physique, les pièces visibles de la map vues
-- depuis `views` lorsqu'une scène se construit ; les pièces invisibles (murs d'air, volumes) sont ignorées. Les pièces
-- enfants d'une autre pièce sont copiées pour elles-mêmes, pas avec leur parent. Cède la main tous les 4 000 descendants.
function MapCopy.copy(map: Instance, views: { View }, cone: Cone, offset: Vector3, folder: Folder)
	for i, part in map:GetDescendants() do
		if i % 4000 == 0 then
			task.wait() -- la map compte plusieurs dizaines de milliers d'instances
		end
		if part:IsA("BasePart") and part.Transparency < 1 and seen(part, views, cone) then
			local copy = part:Clone()
			for _, child in copy:GetDescendants() do
				if
					child:IsA("BasePart")
					or child:IsA("JointInstance")
					or child:IsA("Constraint")
					or child:IsA("LuaSourceContainer")
				then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CFrame = part.CFrame + offset
			copy.Parent = folder
		end
	end
end

-- Cette méthode permet de trouver le sol d'une copie sous un point (`feet`, déjà décalé) lorsqu'un personnage y est
-- posé ; garde le point si le rayon ne touche rien.
function MapCopy.groundUnder(feet: Vector3, folder: Folder): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	-- Les copies ont CanQuery coupé : on le rend le temps du rayon aux seules pièces sous les pieds
	local under = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and (part.Position - feet).Magnitude < part.Size.Magnitude / 2 + 2 then
			part.CanQuery = true
			table.insert(under, part)
		end
	end
	local hit = workspace:Raycast(feet + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
	for _, part in under do
		part.CanQuery = false
	end
	return if hit then hit.Position else feet
end

return MapCopy

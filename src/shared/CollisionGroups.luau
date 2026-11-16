-- Groupes de collision (#312) : les personnages (joueurs et bots) se traversent, comme `mp_solid_teammates 0` étendu à
-- tous. Le groupe `Characters` ne collisionne pas avec lui-même (PhysicsService) ; le serveur y range chaque pièce d'un
-- personnage à l'apparition, et celles ajoutées ensuite (arme 3P, outils, accessoires), sinon elles resteraient dans
-- `Default`. Les requêtes du mouvement (sol, murs, marches, tête, accroupi) prennent ce groupe
-- (`RaycastParams.CollisionGroup`) et ignorent donc tous les personnages ; les tirs et le couteau gardent `Default` et
-- les touchent toujours.
-- Les corps (ragdolls locaux, #452) vont dans `Corpses` : ils tombent sur la map et leurs membres se cognent entre eux,
-- mais ni les personnages ni les requêtes du mouvement ne les heurtent (une pièce `CanCollide` reste visible des
-- raycasts malgré `CanQuery = false`, seul le groupe l'écarte).

local CollisionGroups = {}

CollisionGroups.CHARACTERS = "Characters"
CollisionGroups.CORPSES = "Corpses"

-- Cette méthode permet d'enregistrer les groupes des personnages (non collidable avec lui-même) et des corps (qui ne
-- heurtent pas les personnages) lorsque le serveur démarre ; sans effet s'ils le sont déjà. Répliqués aux clients.
function CollisionGroups.register()
	local PhysicsService = game:GetService("PhysicsService")
	for _, group in { CollisionGroups.CHARACTERS, CollisionGroups.CORPSES } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.CHARACTERS, CollisionGroups.CHARACTERS, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.CORPSES, CollisionGroups.CHARACTERS, false)
end

-- Cette méthode permet de ranger une instance dans le groupe des personnages lorsqu'elle est une pièce (les autres
-- instances sont ignorées).
local function assign(inst: Instance)
	if inst:IsA("BasePart") then
		(inst :: BasePart).CollisionGroup = CollisionGroups.CHARACTERS
	end
end

-- Cette méthode permet de ranger toutes les pièces d'un personnage dans le groupe des personnages lorsqu'il apparaît,
-- puis chaque pièce ajoutée ensuite (l'écoute meurt avec le personnage détruit).
function CollisionGroups.assignCharacter(char: Model)
	for _, inst in char:GetDescendants() do
		assign(inst)
	end
	char.DescendantAdded:Connect(assign)
end

-- Cette méthode permet de faire ignorer tous les personnages à un rayon ou un balayage de mouvement lorsqu'on le prépare.
function CollisionGroups.ignoreCharacters(params: RaycastParams)
	params.CollisionGroup = CollisionGroups.CHARACTERS
end

-- Cette méthode permet de faire ignorer tous les personnages à une requête de recouvrement de mouvement lorsqu'on la
-- prépare.
function CollisionGroups.ignoreCharactersOverlap(params: OverlapParams)
	params.CollisionGroup = CollisionGroups.CHARACTERS
end

return CollisionGroups

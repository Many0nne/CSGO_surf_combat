-- Groupes de collision (#312) : les personnages (joueurs et bots) se traversent, comme `mp_solid_teammates 0` étendu à
-- tous. Le groupe `Characters` ne collisionne pas avec lui-même (PhysicsService) ; le serveur y range chaque pièce d'un
-- personnage à l'apparition, et celles ajoutées ensuite (arme 3P, outils, accessoires), sinon elles resteraient dans
-- `Default`. Les requêtes du mouvement (sol, murs, marches, tête, accroupi, vue des bots) prennent ce groupe
-- (`RaycastParams.CollisionGroup`) et ignorent donc tous les personnages ; les tirs et le couteau gardent `Default` et
-- les touchent toujours.

local CollisionGroups = {}

CollisionGroups.CHARACTERS = "Characters"

-- Cette méthode permet d'enregistrer le groupe des personnages, non collidable avec lui-même, lorsque le serveur démarre
-- (avant d'y ranger une pièce) ; sans effet s'il l'est déjà. Les groupes sont répliqués aux clients.
function CollisionGroups.register()
	local PhysicsService = game:GetService("PhysicsService")
	if not PhysicsService:IsCollisionGroupRegistered(CollisionGroups.CHARACTERS) then
		PhysicsService:RegisterCollisionGroup(CollisionGroups.CHARACTERS)
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.CHARACTERS, CollisionGroups.CHARACTERS, false)
end

-- Cette méthode permet de ranger une instance dans le groupe des personnages lorsqu'elle est une pièce (les autres
-- instances sont ignorées).
local function assign(inst: Instance)
	if inst:IsA("BasePart") then
		(inst :: BasePart).CollisionGroup = CollisionGroups.CHARACTERS
	end
end

-- Cette méthode permet de ranger toutes les pièces d'un personnage dans le groupe des personnages lorsqu'il apparaît,
-- puis chaque pièce ajoutée ensuite ; la connexion renvoyée meurt avec le personnage.
function CollisionGroups.assignCharacter(char: Model): RBXScriptConnection
	for _, inst in char:GetDescendants() do
		assign(inst)
	end
	return char.DescendantAdded:Connect(assign)
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

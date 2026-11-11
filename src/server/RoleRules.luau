-- Règles pures d'attribution des rôles (#266) : userId + propriétaire + listes d'UserId -> rôles. Testées
-- (tests/specs/RoleRules.spec.luau). La source des listes (module `Roles`) est la seule chose à changer pour passer à un groupe Roblox.
local RoleRules = {}

export type Lists = { [string]: { number } }

-- Cette méthode permet de calculer les rôles d'un joueur lorsqu'il arrive : ceux dont la liste contient son UserId,
-- plus Admin d'office pour le propriétaire du jeu (creatorId). Renvoie un ensemble { [rôle] = true }.
function RoleRules.assign(userId: number, creatorId: number, lists: Lists): { [string]: boolean }
	local roles: { [string]: boolean } = {}
	for role, ids in lists do
		if table.find(ids, userId) then
			roles[role] = true
		end
	end
	if creatorId ~= 0 and userId == creatorId then
		roles.Admin = true
	end
	return roles
end

-- Cette méthode permet de savoir si un ensemble de rôles contient un rôle donné ; un rôle inconnu renvoie false.
function RoleRules.has(roles: { [string]: boolean }?, role: string): boolean
	return roles ~= nil and roles[role] == true
end

-- Cette méthode permet de choisir le rôle affiché lorsqu'un joueur en cumule plusieurs : le premier de `order`, ou "" sans rôle.
function RoleRules.display(roles: { [string]: boolean }, order: { string }): string
	for _, role in order do
		if roles[role] then
			return role
		end
	end
	return ""
end

return RoleRules

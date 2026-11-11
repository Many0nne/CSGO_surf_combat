-- Rôles des joueurs (#266), décidés par le serveur seul. Source : les listes d'UserId ci-dessous (versionnées, jamais
-- répliquées) + game.CreatorId ajouté d'office à Admin. Passer à un groupe Roblox ne change que `compute`.
-- L'attribut `Role` posé sur le Player est INFORMATIF (affichage client) : il n'ouvre aucun droit, le serveur relit
-- sa propre table (`hasRole`), jamais l'attribut. Ajouter un rôle = une ligne dans LISTS (et dans DISPLAY_ORDER).
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local RoleRules = require(ServerScriptService.Server.RoleRules)

local Roles = {}

export type Role = "Admin"

Roles.ADMIN = "Admin" :: Role

local LISTS: RoleRules.Lists = {
	Admin = {}, -- UserId en plus du propriétaire (game.CreatorId, déjà Admin)
}
-- Rôle affiché en premier lorsqu'un joueur en cumule plusieurs
local DISPLAY_ORDER = { "Admin" }

local assigned: { [Player]: { [string]: boolean } } = {}

-- Cette méthode permet de calculer les rôles d'un joueur lorsqu'on ne les a pas encore en mémoire.
local function compute(player: Player): { [string]: boolean }
	return RoleRules.assign(player.UserId, game.CreatorId, LISTS)
end

-- Cette méthode permet de savoir si un joueur a un rôle lorsqu'un système serveur doit réserver une action.
function Roles.hasRole(player: Player, role: string): boolean
	local roles = assigned[player]
	if not roles then
		roles = compute(player)
		assigned[player] = roles
	end
	return RoleRules.has(roles, role)
end

-- Cette méthode permet de poser l'attribut informatif `Role` lorsqu'un joueur arrive.
function Roles.setup(player: Player)
	local roles = compute(player)
	assigned[player] = roles
	player:SetAttribute("Role", RoleRules.display(roles, DISPLAY_ORDER))
end

-- Cette méthode permet d'oublier les rôles d'un joueur lorsqu'il quitte.
function Roles.forget(player: Player)
	assigned[player] = nil
end

Players.PlayerRemoving:Connect(Roles.forget)

return Roles

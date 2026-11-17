-- Amis Roblox du joueur local pour le lobby (#523) : liste et statut (FriendRules), droit d'inviter et invitation
-- (SocialService). Les API d'amis et d'invitation ne marchent pas avec les joueurs de test de Studio : dans Studio,
-- l'attribut `DebugFriends` du Player remplace la liste par de faux amis, les autres joueurs du serveur compris.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FriendRules = require(Shared:WaitForChild("FriendRules"))
local PartyRules = require(Shared:WaitForChild("PartyRules"))

local FriendsProvider = {}

-- Dernières entrées lues (GetFriendsAsync, GetFriendsOnline) : le statut « sur ce serveur » se recalcule sans rappeler
-- Roblox quand un joueur arrive ou part (FriendsProvider.remerge)
local lastAll: { any }? = nil
local lastOnline: { any } = {}

-- Résultat d'une invitation : prompt de Roblox ouvert, refusé par Roblox, impossible dans Studio, ou en échec
export type InviteResult = "prompted" | "refused" | "studio" | "failed"

-- Cette méthode permet de savoir si les faux amis remplacent la liste lorsque le lobby la charge (Studio seulement).
local function usesDebugFriends(): boolean
	return RunService:IsStudio() and Players.LocalPlayer:GetAttribute(FriendRules.DEBUG_ATTRIBUTE) == true
end

-- Joueurs en train de partir (PlayerRemoving arrive alors qu'ils sont encore dans Players:GetPlayers())
local leaving: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
Players.PlayerRemoving:Connect(function(player)
	leaving[player] = true
end)

-- Cette méthode permet de lire les joueurs présents sur ce serveur lorsque la liste est construite (sans ceux qui
-- partent).
local function playersOnServer(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if not leaving[player] then
			table.insert(list, player)
		end
	end
	return list
end

-- Cette méthode permet de lire les ids des joueurs présents sur ce serveur lorsque la liste est construite.
local function playersHere(): { [number]: boolean }
	local here = {}
	for _, player in playersOnServer() do
		here[player.UserId] = true
	end
	return here
end

-- Cette méthode permet de lire tous les amis du joueur (pages de GetFriendsAsync, MAX_FRIENDS au plus) lorsque la liste
-- se charge ; nil si l'appel échoue.
local function readAll(userId: number): { any }?
	local ok, pages = pcall(Players.GetFriendsAsync, Players, userId)
	if not ok then
		warn("[FriendsProvider] amis illisibles :", pages)
		return nil
	end
	local all = {}
	while #all < FriendRules.MAX_FRIENDS do
		for _, entry in pages:GetCurrentPage() do
			if #all >= FriendRules.MAX_FRIENDS then
				break
			end
			table.insert(all, entry)
		end
		if pages.IsFinished then
			break
		end
		local advanced, err = pcall(pages.AdvanceToNextPageAsync, pages)
		if not advanced then
			warn("[FriendsProvider] page d'amis illisible :", err)
			break
		end
	end
	return all
end

-- Cette méthode permet de charger la liste des amis avec leur statut lorsque le lobby s'ouvre (appel bloquant : à
-- lancer à part) ; nil si Roblox ne répond pas.
function FriendsProvider.fetch(): { FriendRules.Friend }?
	local localPlayer = Players.LocalPlayer
	if usesDebugFriends() then
		local others = {}
		for _, player in playersOnServer() do
			if player ~= localPlayer then
				table.insert(others, { id = player.UserId, name = player.DisplayName })
			end
		end
		local all, online = FriendRules.debugEntries(others, game.PlaceId)
		return FriendRules.merge(all, online, game.PlaceId, game.JobId, playersHere())
	end
	local all = readAll(localPlayer.UserId)
	if not all then
		return nil
	end
	local ok, online = pcall(localPlayer.GetFriendsOnline, localPlayer, FriendRules.MAX_FRIENDS)
	if not ok then
		warn("[FriendsProvider] amis en ligne illisibles :", online)
		online = {}
	end
	lastAll, lastOnline = all, online
	return FriendRules.merge(all, online, game.PlaceId, game.JobId, playersHere())
end

-- Cette méthode permet de recalculer les statuts de la dernière liste lue lorsqu'un joueur arrive sur le serveur ou en
-- part (statut « sur ce serveur »), sans appel web ; faux amis de Studio relus (ils suivent les joueurs du serveur). nil
-- si aucune liste n'a encore été lue.
function FriendsProvider.remerge(): { FriendRules.Friend }?
	if usesDebugFriends() then
		return FriendsProvider.fetch()
	end
	if not lastAll then
		return nil
	end
	return FriendRules.merge(lastAll, lastOnline, game.PlaceId, game.JobId, playersHere())
end

-- Cette méthode permet de demander à Roblox si le joueur peut inviter lorsque le lobby s'ouvre (appel bloquant) ; nil
-- si la réponse est illisible (le clic sur INVITER la redemande), false dans Studio.
function FriendsProvider.canInvite(): boolean?
	if RunService:IsStudio() then
		return false
	end
	local ok, result = pcall(SocialService.CanSendGameInviteAsync, SocialService, Players.LocalPlayer)
	if not ok then
		warn("[FriendsProvider] droit d'inviter illisible :", result)
		return nil
	end
	return result == true
end

-- Cette méthode permet d'inviter un ami lorsque le joueur clique INVITER : Roblox vérifie d'abord le droit pour cet ami
-- (CanSendGameInviteAsync), puis ouvre son prompt d'invitation ; l'invité qui accepte arrive sur ce serveur avec l'id du
-- joueur dans les données de lancement, et entre dans son groupe (PartyService).
function FriendsProvider.invite(friendId: number): InviteResult
	if RunService:IsStudio() then
		return "studio"
	end
	local localPlayer = Players.LocalPlayer
	local ok, allowed = pcall(SocialService.CanSendGameInviteAsync, SocialService, localPlayer, friendId)
	if not ok then
		warn("[FriendsProvider] droit d'inviter " .. friendId .. " illisible :", allowed)
		return "failed"
	end
	if not allowed then
		return "refused"
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.InviteUser = friendId
	options.LaunchData = PartyRules.launchData(localPlayer.UserId)
	local prompted, err = pcall(SocialService.PromptGameInvite, SocialService, localPlayer, options)
	if not prompted then
		warn("[FriendsProvider] invitation impossible :", err)
		return "failed"
	end
	return "prompted"
end

return FriendsProvider

-- Mode entraînement (#345) : reconnaît un serveur d'entraînement (serveur réservé de la même place), et téléporte les
-- joueurs qui le demandent (remote Training) vers leur propre serveur d'entraînement, ou de là vers un serveur public.
-- Un serveur par joueur (#388) : seul, il garde ses armes sans que personne puisse l'attaquer ; un serveur réservé vide
-- s'éteint seul. Ce qui change dans un serveur d'entraînement (pas de bots ni de stats, manche sans fin) est branché par
-- init.server selon TrainingService.isTraining().
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local TrainingRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TrainingRules"))
local CheatLog = require(script.Parent.CheatLog)

local TrainingService = {}

-- Téléportation en cours, par joueur : demande, code visé (join) et numéro de l'essai
type Pending = { request: string, code: string?, try: number }

local training = TrainingRules.isTrainingServer(
	game.PrivateServerId,
	game.PrivateServerOwnerId,
	RunService:IsStudio(),
	workspace:GetAttribute(TrainingRules.DEBUG_ATTRIBUTE)
)
-- Publié dès le chargement du module, avant la création des remotes : un client qui voit le remote Training connaît
-- déjà le mode (TrainingClient.waitForMode)
ReplicatedStorage:SetAttribute(TrainingRules.ATTRIBUTE, training)
local remote: RemoteEvent
local pending: { [Player]: Pending } = {}
-- Délai (s) au bout duquel une téléportation lancée sans suite ne bloque plus une nouvelle demande
local PENDING_TIMEOUT = 30

-- Cette méthode permet de savoir si ce serveur est un serveur d'entraînement lorsqu'un système s'y adapte (bots, stats,
-- manche) ; fixé au démarrage du serveur.
function TrainingService.isTraining(): boolean
	return training
end

-- Cette méthode permet de répondre au client lorsque sa demande est traitée ou échoue (message du menu, TrainingRules).
local function reply(player: Player, status: TrainingRules.Status)
	if player.Parent then
		remote:FireClient(player, status)
	end
end

-- Cette méthode permet de réserver le serveur d'entraînement d'un joueur lorsqu'il veut s'entraîner, ou qu'une
-- téléportation vers le précédent a échoué ; nil si la réservation échoue.
local function reserve(): string?
	local ok, code = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not ok or type(code) ~= "string" then
		warn("[TrainingService] réservation d'un serveur impossible :", code)
		return nil
	end
	return code
end

-- Cette méthode permet de lancer la téléportation d'un joueur lorsque sa demande est acceptée ou retentée : vers le
-- serveur d'entraînement `code` (join), ou vers un serveur public de la place (leave).
local function teleport(player: Player, entry: Pending)
	local options = Instance.new("TeleportOptions")
	if entry.code then
		options.ReservedServerAccessCode = entry.code
	end
	options:SetTeleportData({ training = entry.request == TrainingRules.JOIN })
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		warn("[TrainingService] téléportation de " .. player.Name .. " impossible :", err)
		pending[player] = nil
		reply(player, "failed")
		return
	end
	reply(player, "teleporting")
	-- Ni départ ni échec annoncé (cas rare) : la demande suivante n'est pas refusée en « busy » pour toujours
	task.delay(PENDING_TIMEOUT, function()
		if pending[player] == entry then
			pending[player] = nil
		end
	end)
end

-- Cette méthode permet de traiter une demande du joueur (rejoindre ou quitter l'entraînement) lorsqu'elle arrive.
local function onRequest(player: Player, raw: any)
	if not CheatLog.admit(player, remote.Name, raw) then
		return
	end
	local request = TrainingRules.readRequest(raw)
	if not request then
		return
	end
	local decision = TrainingRules.decide(request, training, RunService:IsStudio(), pending[player] ~= nil)
	if decision ~= "teleport" then
		reply(player, decision :: TrainingRules.Status)
		return
	end
	local entry: Pending = { request = request, code = nil, try = 1 }
	pending[player] = entry
	if request == TrainingRules.JOIN then
		local code = reserve()
		if not code then
			pending[player] = nil
			reply(player, "failed")
			return
		end
		entry.code = code
	end
	teleport(player, entry)
end

-- Cette méthode permet de retenter avec un serveur neuf une téléportation vers l'entraînement qui échoue (serveur plein
-- ou introuvable), ou de prévenir le joueur, lorsque Roblox annonce l'échec.
local function onTeleportFailed(player: Player, result: Enum.TeleportResult, message: string)
	local entry = pending[player]
	if not entry then
		return
	end
	warn(
		string.format("[TrainingService] échec de téléportation de %s : %s (%s)", player.Name, result.Name, message)
	)
	if entry.code and TrainingRules.retriesWithFreshCode(result.Name, entry.try) then
		local fresh = reserve()
		if fresh then
			entry.try += 1
			entry.code = fresh
			teleport(player, entry)
			return
		end
	end
	pending[player] = nil
	reply(player, "failed")
end

-- Cette méthode permet de brancher les demandes des joueurs (et les échecs de téléportation) lorsque le serveur démarre ;
-- le mode est déjà publié au chargement du module.
function TrainingService.init(trainingRemote: RemoteEvent)
	remote = trainingRemote
	if training then
		print("[TrainingService] serveur d'entraînement : ni bots, ni stats")
	end
	remote.OnServerEvent:Connect(onRequest)
	TeleportService.TeleportInitFailed:Connect(onTeleportFailed)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return TrainingService

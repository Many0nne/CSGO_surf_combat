-- Réglages du joueur (#100) conservés entre les sessions : sensibilités, ombres, molette, visée simplifiée (#195) et
-- style du viseur (#251), auto-bhop (#255) et touches de la barre d'armes. Roblox n'a pas de stockage côté client : le client demande ses réglages (RemoteFunction
-- GetSettings) et envoie chaque changement (SaveSettings) ; le serveur les valide (PlayerSettings.sanitize) et les écrit dans un DataStore, au plus une
-- fois par SAVE_DELAY, puis au départ du joueur et à l'arrêt du serveur.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))
local CheatLog = require(ServerScriptService.Server.CheatLog)

local SCHEMA_VERSION = 1
local SAVE_DELAY = 10 -- s entre un changement et l'écriture (un curseur qu'on glisse envoie beaucoup de changements)
local LOAD_TIMEOUT = 20 -- s d'attente maximale d'une demande de réglages avant le chargement

type Profile = { settings: PlayerSettings.Settings, loaded: boolean, dirty: boolean, saveScheduled: boolean }

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local saveDisabled: { [Player]: boolean } = {}

local SettingsStore = {}

-- Cette méthode permet d'ouvrir le DataStore une seule fois lorsque le premier joueur arrive ; renvoie nil si les
-- services d'API sont coupés (Studio sans « Enable Studio Access to API Services »).
local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "PlayerSettings_v1")
	if ok then
		store = result
	end
	return store
end

-- Cette méthode permet de lire ou d'écrire le DataStore avec trois essais espacés lorsque le réseau ou les quotas
-- refusent une requête ; renvoie la réussite et le résultat.
local function withRetry(fn: () -> any): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < 3 then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

-- Cette méthode permet de charger les réglages d'un joueur lorsqu'il arrive ; un échec de lecture coupe la sauvegarde
-- pour la session, pour ne pas écraser ses réglages par les valeurs par défaut.
function SettingsStore.load(player: Player)
	local profile: Profile = {
		settings = PlayerSettings.defaults(),
		loaded = false,
		dirty = false,
		saveScheduled = false,
	}
	profiles[player] = profile
	local ds = getStore()
	local ok, data = false, nil
	if ds then
		ok, data = withRetry(function()
			return ds:GetAsync(tostring(player.UserId))
		end)
	end
	if profiles[player] ~= profile then
		return -- parti pendant le chargement
	end
	if ok then
		profile.settings = PlayerSettings.sanitize(type(data) == "table" and data.settings or nil)
	else
		saveDisabled[player] = true
		warn("[SettingsStore] chargement impossible pour", player.Name, "— réglages non sauvegardés cette session")
	end
	profile.loaded = true
end

-- Cette méthode permet d'écrire les réglages d'un joueur s'ils ont changé lorsque le délai d'écriture est écoulé, que le
-- joueur part ou que le serveur s'arrête.
function SettingsStore.save(player: Player)
	local profile = profiles[player]
	local ds = getStore()
	if not (profile and profile.dirty and ds) or saveDisabled[player] then
		return
	end
	profile.dirty = false
	local payload = { schemaVersion = SCHEMA_VERSION, settings = profile.settings }
	local ok = withRetry(function()
		return ds:SetAsync(tostring(player.UserId), payload, { player.UserId })
	end)
	if not ok then
		profile.dirty = true
		warn("[SettingsStore] sauvegarde impossible pour", player.Name)
	end
end

-- Cette méthode permet de renvoyer au client ses réglages lorsqu'il les demande au démarrage ; attend la fin du
-- chargement (LOAD_TIMEOUT au plus), puis renvoie les valeurs par défaut si le chargement n'a pas abouti.
local function onGetSettings(player: Player): PlayerSettings.Settings
	local deadline = os.clock() + LOAD_TIMEOUT
	-- Le profil peut ne pas exister encore : la demande peut arriver avant que PlayerAdded lance le chargement
	while not (profiles[player] and profiles[player].loaded) and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	local profile = profiles[player]
	return if profile then profile.settings else PlayerSettings.defaults()
end

-- Cette méthode permet d'enregistrer les réglages envoyés par un client lorsqu'il en change un : ils sont validés,
-- gardés en mémoire, puis écrits après SAVE_DELAY (une seule écriture pour une série de changements).
local function onSaveSettings(player: Player, raw: any)
	local profile = profiles[player]
	if not (profile and profile.loaded) then
		return
	end
	profile.settings = PlayerSettings.sanitize(raw)
	profile.dirty = true
	if profile.saveScheduled then
		return
	end
	profile.saveScheduled = true
	task.delay(SAVE_DELAY, function()
		profile.saveScheduled = false
		if profiles[player] == profile then
			SettingsStore.save(player)
		end
	end)
end

-- Cette méthode permet de brancher les remotes, le départ des joueurs et l'arrêt du serveur lorsque le serveur démarre.
function SettingsStore.init(getRemote: RemoteFunction, saveRemote: RemoteEvent)
	-- Garde commune (#170) : débit (GetSettings borne aussi les demandes en attente du chargement) et type
	getRemote.OnServerInvoke = function(player: Player)
		if not CheatLog.admit(player, getRemote.Name) then
			-- Sans attendre : réglages déjà chargés (rien d'écrasé par un retour vide), nil pendant le chargement. Pas
			-- d'error() : chaque appel refusé écrirait une erreur dans la console serveur.
			local profile = profiles[player]
			return if profile and profile.loaded then profile.settings else nil
		end
		return onGetSettings(player)
	end
	saveRemote.OnServerEvent:Connect(function(player: Player, raw: any)
		if CheatLog.admit(player, saveRemote.Name, raw) then
			onSaveSettings(player, raw)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		SettingsStore.save(player)
		profiles[player] = nil
		saveDisabled[player] = nil
	end)

	game:BindToClose(function()
		for player in profiles do
			SettingsStore.save(player)
		end
	end)
end

return SettingsStore

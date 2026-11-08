-- Réglages du joueur côté client (#100) : copie locale des réglages sauvegardés par le serveur (server/SettingsStore).
-- Au démarrage, les valeurs par défaut s'appliquent, puis les réglages sauvegardés dès que le serveur les renvoie.
-- Chaque changement prévient les modules abonnés (écran Réglages, barre d'armes) et part au serveur après SEND_DELAY.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)

local SEND_DELAY = 1 -- s : une série de changements (curseur glissé) ne part qu'une fois

local LocalSettings = {}

local current: PlayerSettings.Settings = PlayerSettings.defaults()
local loaded = false
local dirty = false -- changé par le joueur depuis le dernier envoi
local sendScheduled = false
local saveRemote: RemoteEvent?
local listeners: { (PlayerSettings.Settings) -> () } = {}
local loadedListeners: { (PlayerSettings.Settings) -> () } = {}

-- Cette méthode permet de prévenir les modules abonnés lorsque les réglages changent (joueur ou chargement).
local function notify(list: { (PlayerSettings.Settings) -> () })
	for _, callback in list do
		task.spawn(callback, current)
	end
end

-- Cette méthode permet d'envoyer les réglages au serveur lorsque le délai suivant un changement est écoulé ; avant le
-- chargement, l'envoi attend (le serveur ignorerait des réglages reçus avant d'avoir lu les siens).
local function send()
	sendScheduled = false
	if not (dirty and loaded and saveRemote) then
		return
	end
	dirty = false
	saveRemote:FireServer(current)
end

-- Cette méthode permet de renvoyer les réglages en cours lorsqu'un module doit les lire.
function LocalSettings.get(): PlayerSettings.Settings
	return current
end

-- Cette méthode permet de donner le libellé d'une touche tel qu'il est imprimé sur le clavier du joueur (AZERTY : la
-- touche Q de Roblox s'affiche « A ») lorsqu'elle est montrée ; chiffres et touches F gardent leur libellé fixe.
function LocalSettings.keyText(keyName: string): string
	if PlayerSettings.isDigit(keyName) or string.sub(keyName, 1, 1) == "F" and #keyName > 1 then
		return PlayerSettings.keyLabel(keyName)
	end
	local ok, text = pcall(function()
		return UserInputService:GetStringForKeyCode((Enum.KeyCode :: any)[keyName])
	end)
	if ok and type(text) == "string" and text ~= "" then
		return string.upper(text)
	end
	return PlayerSettings.keyLabel(keyName)
end

-- Cette méthode permet de savoir si les réglages sauvegardés sont arrivés lorsque l'écran Réglages s'affiche.
function LocalSettings.isLoaded(): boolean
	return loaded
end

-- Cette méthode permet de changer un ou plusieurs réglages lorsque le joueur les modifie : les abonnés sont prévenus,
-- puis l'envoi au serveur est programmé.
function LocalSettings.update(patch: { [string]: any })
	local changed = false
	for key, value in patch do
		if (current :: any)[key] ~= value then
			(current :: any)[key] = value
			changed = true
		end
	end
	if not changed then
		return
	end
	dirty = true
	notify(listeners)
	if not sendScheduled then
		sendScheduled = true
		task.delay(SEND_DELAY, send)
	end
end

-- Cette méthode permet de s'abonner aux changements de réglages lorsqu'un module en dépend (barre d'armes).
function LocalSettings.onChanged(callback: (PlayerSettings.Settings) -> ())
	table.insert(listeners, callback)
end

-- Cette méthode permet d'être prévenu une fois les réglages sauvegardés arrivés lorsqu'un écran doit afficher leurs
-- valeurs ; appelle tout de suite si c'est déjà fait.
function LocalSettings.onLoaded(callback: (PlayerSettings.Settings) -> ())
	if loaded then
		task.spawn(callback, current)
	else
		table.insert(loadedListeners, callback)
	end
end

-- Cette méthode permet de demander ses réglages au serveur lorsque le client démarre ; si le joueur a déjà changé un
-- réglage entre-temps, ses choix locaux l'emportent et repartent au serveur.
function LocalSettings.init()
	task.spawn(function()
		saveRemote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.SAVE_SETTINGS, 15) :: RemoteEvent?
		local getRemote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.GET_SETTINGS, 15) :: RemoteFunction?
		local ok, raw = false, nil
		if getRemote then
			ok, raw = pcall(getRemote.InvokeServer, getRemote)
		end
		if not ok then
			warn("[LocalSettings] réglages sauvegardés indisponibles, valeurs par défaut")
		elseif not dirty then
			current = PlayerSettings.sanitize(raw)
		end
		loaded = true
		notify(loadedListeners)
		loadedListeners = {}
		notify(listeners)
		send()
	end)
end

return LocalSettings

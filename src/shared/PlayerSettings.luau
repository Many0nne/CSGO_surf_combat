-- Réglages du joueur (#100) : valeurs par défaut, validation et règles pures, partagées par le client (écran Réglages,
-- barre d'armes) et le serveur (SettingsStore, qui valide ce que le client envoie avant de le sauvegarder).
-- Les touches sont stockées par nom d'Enum.KeyCode (« One », « Q », « F5 ») : une chaîne passe dans un DataStore.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)

export type WheelMode = "previous" | "next" | "off"

-- Affichage des touches (#197) : « off » (défaut), « simple » (directions et saut), « full » (plus accroupi et actions)
export type KeyDisplayMode = "off" | "simple" | "full"

export type Settings = {
	sensitivity: number,
	scopeMultiplier: number,
	-- nil : ombres de la place (Lighting.GlobalShadows d'origine), le joueur n'a rien choisi
	shadows: boolean?,
	wheel: WheelMode,
	-- Visée simplifiée (#195) : crosshair au centre de l'écran, désactivé par défaut
	simpleAim: boolean,
	keyDisplay: KeyDisplayMode,
	-- une touche par emplacement de la barre d'armes, dans l'ordre des emplacements
	slotKeys: { string },
}

local PlayerSettings = {}

-- Emplacements gérés par la barre d'armes ; l'écran Réglages n'en montre qu'autant que d'armes (MAX_ROWS au plus)
PlayerSettings.SLOT_COUNT = 9
PlayerSettings.MAX_ROWS = 7
PlayerSettings.DEFAULT_SLOT_KEYS = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
-- Molette vers le haut : arme précédente (comportement d'origine de la barre)
PlayerSettings.DEFAULT_WHEEL = "previous" :: WheelMode
PlayerSettings.WHEEL_MODES = { "previous", "next", "off" } :: { WheelMode }
PlayerSettings.DEFAULT_KEY_DISPLAY = "off" :: KeyDisplayMode
PlayerSettings.KEY_DISPLAY_MODES = { "off", "simple", "full" } :: { KeyDisplayMode }
-- Touche du menu en partie (#157 : reprendre, réglages, retour au menu principal), nom d'Enum.KeyCode ; au menu
-- principal elle ouvre les Réglages. Seule source de cette touche : InGameMenu, l'écran Infos et la liste des réservées.
PlayerSettings.MENU_KEY = "P"

local DIGITS = {
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}

-- Touches déjà prises par le jeu (déplacement, saut, accroupi, recharge, inspection, menu, classement, F3/F4 de
-- debug) ou par Roblox (F9 console, F11 plein écran, F12 capture) : refusées pour un emplacement
local RESERVED = {
	W = true,
	A = true,
	S = true,
	D = true,
	R = true,
	F = true,
	[PlayerSettings.MENU_KEY] = true,
	F3 = true,
	F4 = true,
	F9 = true,
	F11 = true,
	F12 = true,
}

-- Touches proposées : lettres, chiffres de la rangée du haut et touches F (hors réservées). Une liste fermée garde des
-- libellés courts dans la barre et écarte les touches système (Échap, Tab, Espace, Maj, Ctrl, Alt, « / » du chat).
local BINDABLE: { [string]: boolean } = {}
for code = string.byte("A"), string.byte("Z") do
	BINDABLE[string.char(code)] = true
end
for name in DIGITS do
	BINDABLE[name] = true
end
for n = 1, 12 do
	BINDABLE["F" .. n] = true
end
for name in RESERVED do
	BINDABLE[name] = nil
end

-- Cette méthode permet de donner un jeu de réglages neuf aux valeurs par défaut lorsqu'un joueur n'a rien sauvegardé
-- ou que ses données sont illisibles.
function PlayerSettings.defaults(): Settings
	return {
		sensitivity = CameraConfig.DEFAULT_SENS,
		scopeMultiplier = CameraConfig.SCOPE_SENS_MULT,
		shadows = nil,
		wheel = PlayerSettings.DEFAULT_WHEEL,
		simpleAim = false,
		keyDisplay = PlayerSettings.DEFAULT_KEY_DISPLAY,
		slotKeys = table.clone(PlayerSettings.DEFAULT_SLOT_KEYS),
	}
end

-- Cette méthode permet de savoir si une touche (nom d'Enum.KeyCode) peut être donnée à un emplacement lorsque le
-- joueur la choisit ou que le serveur valide des réglages reçus.
function PlayerSettings.isBindable(keyName: any): boolean
	return type(keyName) == "string" and BINDABLE[keyName] == true
end

-- Cette méthode permet de savoir si une touche est refusée parce que le jeu s'en sert déjà lorsque le joueur la choisit.
function PlayerSettings.isReserved(keyName: string): boolean
	return RESERVED[keyName] == true
end

-- Cette méthode permet de borner un nombre reçu (type, NaN, bornes) lorsque des réglages sont validés.
local function clampNumber(value: any, minVal: number, maxVal: number, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, minVal, maxVal)
end

-- Cette méthode permet de valider les touches reçues lorsque des réglages sont chargés ou envoyés : une touche absente,
-- non autorisée ou en double remet toutes les touches par défaut, pour ne jamais laisser deux emplacements sur une touche.
local function sanitizeKeys(raw: any): { string }
	if type(raw) ~= "table" then
		return table.clone(PlayerSettings.DEFAULT_SLOT_KEYS)
	end
	local keys, used = {}, {}
	for i = 1, PlayerSettings.SLOT_COUNT do
		local key = raw[i]
		if not PlayerSettings.isBindable(key) or used[key] then
			return table.clone(PlayerSettings.DEFAULT_SLOT_KEYS)
		end
		used[key] = true
		keys[i] = key
	end
	return keys
end

-- Cette méthode permet de construire des réglages sûrs à partir de données quelconques (DataStore, client) lorsque le
-- serveur les charge ou les reçoit : tout champ invalide reprend sa valeur par défaut, les champs inconnus sont ignorés.
function PlayerSettings.sanitize(raw: any): Settings
	local settings = PlayerSettings.defaults()
	if type(raw) ~= "table" then
		return settings
	end
	settings.sensitivity =
		clampNumber(raw.sensitivity, CameraConfig.SENS_MIN, CameraConfig.SENS_MAX, CameraConfig.DEFAULT_SENS)
	settings.scopeMultiplier = clampNumber(
		raw.scopeMultiplier,
		CameraConfig.SCOPE_SENS_MIN,
		CameraConfig.SCOPE_SENS_MAX,
		CameraConfig.SCOPE_SENS_MULT
	)
	if type(raw.shadows) == "boolean" then
		settings.shadows = raw.shadows
	end
	if table.find(PlayerSettings.WHEEL_MODES, raw.wheel) then
		settings.wheel = raw.wheel
	end
	if type(raw.simpleAim) == "boolean" then
		settings.simpleAim = raw.simpleAim
	end
	if table.find(PlayerSettings.KEY_DISPLAY_MODES, raw.keyDisplay) then
		settings.keyDisplay = raw.keyDisplay
	end
	settings.slotKeys = sanitizeKeys(raw.slotKeys)
	return settings
end

-- Cette méthode permet de donner une touche à un emplacement lorsque le joueur la choisit dans l'écran Réglages :
-- si un autre emplacement l'avait, les deux échangent leurs touches. Renvoie les nouvelles touches, ou nil et la raison
-- (« reserved » : le jeu s'en sert, « invalid » : touche non proposée).
function PlayerSettings.assignKey(keys: { string }, slot: number, keyName: string): ({ string }?, string?)
	if PlayerSettings.isReserved(keyName) then
		return nil, "reserved"
	end
	if not PlayerSettings.isBindable(keyName) or not keys[slot] then
		return nil, "invalid"
	end
	local result = table.clone(keys)
	local other = table.find(result, keyName)
	if other and other ~= slot then
		result[other] = result[slot]
	end
	result[slot] = keyName
	return result
end

-- Cette méthode permet de retrouver l'emplacement d'une touche lorsque le joueur appuie dessus en partie.
function PlayerSettings.slotForKey(keys: { string }, keyName: string): number?
	return table.find(keys, keyName)
end

-- Cette méthode permet de traduire un cran de molette en pas d'arme (-1 précédente, 1 suivante, nil sans effet)
-- lorsque la molette tourne ; `delta` > 0 vers le haut.
function PlayerSettings.wheelStep(mode: WheelMode, delta: number): number?
	if mode == "off" or delta == 0 then
		return nil
	end
	local up = delta > 0
	if mode == "next" then
		return up and 1 or -1
	end
	return up and -1 or 1
end

-- Cette méthode permet de donner le libellé court d'une touche (« 1 », « Q », « F5 ») lorsqu'elle est affichée et que
-- la disposition du clavier n'en donne pas (chiffres, touches F).
function PlayerSettings.keyLabel(keyName: string): string
	return DIGITS[keyName] or keyName
end

-- Cette méthode permet de savoir si une touche est un chiffre de la rangée du haut lorsque son libellé est choisi :
-- sur un clavier AZERTY, la disposition donnerait « & » ou « é » au lieu du chiffre.
function PlayerSettings.isDigit(keyName: string): boolean
	return DIGITS[keyName] ~= nil
end

return PlayerSettings

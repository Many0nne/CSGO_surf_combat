-- Contexte des textes à touches (InfosRules.Context) lu dans le jeu : actions de l'affichage des touches (KeyBindings),
-- libellés du clavier du joueur, réglages d'armes et auto-bhop. Partagé par les écrans Infos (COMMANDES) et Apprendre
-- (légende de la démo, #285) ; les règles de composition, pures, restent dans InfosRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local InfosRules = require(script.Parent.InfosRules)

local InfosContext = {}

-- Cette méthode permet de réunir ce dont les textes à touches dépendent lorsqu'un écran les compose, à son affichage.
function InfosContext.compose(): InfosRules.Context
	local settings = LocalSettings.get()
	return {
		entries = HUDRules.keyDisplayEntries("full"),
		keyText = LocalSettings.keyText,
		menuKey = PlayerSettings.MENU_KEY,
		slotKeys = settings.slotKeys,
		defaultSlotKeys = PlayerSettings.DEFAULT_SLOT_KEYS,
		wheel = settings.wheel,
		autoBhop = settings.autoBhop,
	}
end

return InfosContext

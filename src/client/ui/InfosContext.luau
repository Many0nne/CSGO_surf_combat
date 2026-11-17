-- Contexte des textes à touches (InfosRules.Context) lu dans le jeu : actions de l'affichage des touches (KeyBindings),
-- libellés du clavier du joueur, réglages d'armes et auto-bhop. Partagé par les écrans Infos (COMMANDES) et Apprendre
-- (légende de la démo, #285) ; les règles de composition, pures, restent dans InfosRules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
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

-- Cette méthode permet de traduire un texte de InfosRules (gabarit français `{nom}` + arguments) lorsqu'un écran
-- l'affiche : les arguments qui sont eux-mêmes des libellés français (« ESPACE ») sont traduits aussi ; une lettre de
-- touche reste telle quelle.
function InfosContext.text(fr: string, args: { [string]: any }?): string
	local translated: { [string]: any }? = nil
	if args then
		local copy: { [string]: any } = {}
		for name, value in args do
			copy[name] = if type(value) == "string" then Locale.t(value) else value
		end
		translated = copy
	end
	return Locale.t(fr, translated)
end

-- Cette méthode permet de poser sur un objet un texte de InfosRules lorsqu'un écran l'affiche ; il suit ensuite les
-- changements de langue (cf. `Locale.bind`). `prop` : autre propriété texte (`PlaceholderText`).
function InfosContext.apply(object: Instance, fr: string, args: { [string]: any }?, prop: string?)
	Locale.bind(object, function()
		return InfosContext.text(fr, args)
	end, prop)
end

return InfosContext

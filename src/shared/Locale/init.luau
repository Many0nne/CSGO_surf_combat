-- Langue du jeu (#518) : français (langue d'écriture du code) ou anglais. Le texte français sert de clé : les écrans
-- passent leurs libellés français à `Locale.t` / `Locale.apply`, et les tables de `en/` donnent leur traduction.
-- Paramètres dans le texte entre accolades : `Locale.t("ARME {n}", { n = 2 })`. Un texte sans traduction reste tel quel
-- (noms propres, nombres) ; tests/specs/Locale.spec.luau vérifie qu'aucun texte affiché n'est resté sans traduction.
-- Changer de langue (`Locale.setLanguage`) réécrit tous les textes posés par `Locale.apply`/`Locale.bind` et prévient
-- les abonnés de `Locale.onChanged` : tous les écrans basculent sans relancer le jeu.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocaleFolder = ReplicatedStorage.Shared.Locale

export type Language = "fr" | "en"

local Locale = {}

-- Langues proposées dans les réglages, dans l'ordre du choix ; défaut hors compte français : anglais
Locale.LANGUAGES = { "fr", "en" } :: { Language }
Locale.DEFAULT = "en" :: Language
-- Nom de chaque langue, écrit dans sa propre langue (le choix se lit même dans une langue qu'on ne comprend pas)
Locale.NAMES = { fr = "FRANÇAIS", en = "ENGLISH" } :: { [Language]: string }

-- Traductions anglaises, une table par domaine (texte français -> texte anglais) : un écran = un fichier, pour que deux
-- tâches ne se marchent pas dessus. Ajouter un fichier : l'ajouter aussi à cette liste.
Locale.EN_TABLES = {
	require(LocaleFolder.en.Common),
	require(LocaleFolder.en.Menu),
	require(LocaleFolder.en.Settings),
	require(LocaleFolder.en.HUD),
	require(LocaleFolder.en.Shop),
	require(LocaleFolder.en.Equipment),
	require(LocaleFolder.en.Infos),
	require(LocaleFolder.en.Lobby),
	require(LocaleFolder.en.Misc),
} :: { { [string]: string } }

local EN: { [string]: string } = {}
for _, entries in Locale.EN_TABLES do
	for fr, en in entries do
		EN[fr] = en
	end
end

local current: Language = Locale.DEFAULT
local listeners: { (Language) -> () } = {}
-- Textes posés par apply/bind : objet -> { propriété, producteur, dernier texte écrit }. Clés faibles : un libellé
-- détruit disparaît de la table.
type Binding = { prop: string, produce: () -> string, last: string }
local bindings: { [Instance]: { [string]: Binding } } = setmetatable({}, { __mode = "k" }) :: any

-- Cette méthode permet de savoir si une valeur est une langue proposée lorsque des réglages sont lus ou validés.
function Locale.isLanguage(value: any): boolean
	return table.find(Locale.LANGUAGES, value) ~= nil
end

-- Cette méthode permet de choisir la langue par défaut d'un joueur d'après la langue de son compte Roblox
-- (`LocalizationService.RobloxLocaleId`, « fr-fr », « en-us »…) lorsqu'il n'en a pas choisi : français pour un compte
-- français, anglais sinon.
function Locale.fromLocaleId(localeId: any): Language
	if type(localeId) == "string" and string.lower(string.sub(localeId, 1, 2)) == "fr" then
		return "fr"
	end
	return Locale.DEFAULT
end

-- Cette méthode permet de donner la langue à afficher lorsque le réglage du joueur (nil : pas choisi) et la langue de
-- son compte sont connus.
function Locale.resolve(setting: any, localeId: any): Language
	if Locale.isLanguage(setting) then
		return setting
	end
	return Locale.fromLocaleId(localeId)
end

-- Cette méthode permet de renvoyer la langue affichée lorsqu'un module en dépend (choix des voix, réglages).
function Locale.get(): Language
	return current
end

-- Cette méthode permet de remplacer les paramètres `{nom}` d'un texte par leurs valeurs lorsqu'il est traduit ;
-- un paramètre absent reste tel quel (repérable à l'écran).
local function fill(text: string, args: { [string]: any }?): string
	if not args then
		return text
	end
	return (
		string.gsub(text, "{([%w_]+)}", function(name)
			local value = args[name]
			if value == nil then
				return nil
			end
			return tostring(value)
		end)
	)
end

-- Cette méthode permet de traduire un texte français dans une langue donnée lorsque la langue n'est pas forcément celle
-- affichée (serveur, tests) ; un texte sans traduction est rendu tel quel.
function Locale.translate(language: Language, fr: string, args: { [string]: any }?): string
	local text = if language == "en" then EN[fr] or fr else fr
	return fill(text, args)
end

-- Cette méthode permet de traduire un texte français dans la langue affichée lorsqu'un écran calcule un libellé ; un
-- texte calculé ainsi ne suit pas un changement de langue : le poser par `Locale.apply`, ou le recalculer dans
-- `Locale.onChanged`.
function Locale.t(fr: string, args: { [string]: any }?): string
	return Locale.translate(current, fr, args)
end

-- Cette méthode permet de savoir si un texte français a une traduction anglaise lorsque les tests vérifient les écrans.
function Locale.hasEnglish(fr: string): boolean
	return EN[fr] ~= nil
end

-- Cette méthode permet de renvoyer toutes les traductions anglaises lorsque les tests les vérifient.
function Locale.english(): { [string]: string }
	return EN
end

-- Cette méthode permet de poser sur un objet (propriété `Text` par défaut) un texte calculé par `produce` lorsqu'il doit
-- suivre la langue : il est recalculé à chaque changement de langue, tant que personne n'a écrit autre chose par-dessus
-- (un `label.Text = …` direct reprend la main sans être écrasé).
function Locale.bind(object: Instance, produce: () -> string, prop: string?)
	local property = prop or "Text"
	local text = produce();
	(object :: any)[property] = text
	local perObject = bindings[object]
	if not perObject then
		perObject = {}
		bindings[object] = perObject
	end
	perObject[property] = { prop = property, produce = produce, last = text }
end

-- Cette méthode permet de poser un texte français traduit sur un libellé lorsqu'un écran l'affiche ; il suit ensuite
-- les changements de langue (cf. `Locale.bind`). `prop` : autre propriété texte (`PlaceholderText`).
function Locale.apply(object: Instance, fr: string, args: { [string]: any }?, prop: string?)
	Locale.bind(object, function()
		return Locale.t(fr, args)
	end, prop)
end

-- Cette méthode permet d'être prévenu d'un changement de langue lorsqu'un écran affiche des textes calculés (listes,
-- valeurs de réglages) qu'il doit recalculer ; renvoie de quoi se désabonner.
function Locale.onChanged(callback: (Language) -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

-- Cette méthode permet de changer la langue affichée lorsque le joueur la choisit ou que ses réglages arrivent : les
-- textes posés par apply/bind sont réécrits, puis les abonnés prévenus. Sans effet si la langue ne change pas.
function Locale.setLanguage(language: Language)
	if not Locale.isLanguage(language) or language == current then
		return
	end
	current = language
	for object, perObject in bindings do
		for property, binding in perObject do
			local ok, value = pcall(function()
				return (object :: any)[property]
			end)
			if not ok or value ~= binding.last then
				perObject[property] = nil -- réécrit par l'écran entre-temps : il n'est plus traduit d'ici
				continue
			end
			local text = binding.produce();
			(object :: any)[property] = text
			binding.last = text
		end
	end
	for _, callback in table.clone(listeners) do
		task.spawn(callback, language)
	end
end

return Locale

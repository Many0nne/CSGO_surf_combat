-- Repère dans les sources les textes affichés restés sans traduction anglaise (#518, cf. src/shared/Locale).
-- Un texte « affiché » est une chaîne littérale qui ressemble à du français lisible : lettre accentuée, mot en capitales
-- (« JOUER »), ou au moins deux mots dont un en minuscules. Commentaires, journaux (print, warn, error) et fichiers de
-- debug, d'analytics ou de serveur sans texte joueur sont écartés. Chaque texte retenu doit être une clé des tables
-- `en/`, ou figurer dans ALLOWED (noms propres, sigles, noms de touches identiques dans les deux langues).
local fs = require("@lune/fs")

local LocaleScan = {}

-- Dossiers et fichiers lus : tout le client hors debug, l'écran de chargement, et les modules partagés ou serveur dont
-- un texte arrive à l'écran
LocaleScan.ROOTS = { "src/client", "src/first" }
LocaleScan.FILES = {
	"src/shared/ShopCatalog.luau",
	"src/shared/UITheme.luau",
	"src/shared/CrateOpeningRules.luau",
	"src/shared/InventoryRules.luau",
	"src/shared/WeaponSkins.luau",
	"src/shared/CreditPacks.luau",
	"src/shared/WalletRules.luau",
	"src/shared/PartyRules.luau",
	"src/shared/FriendRules.luau",
	"src/shared/KeyBindings.luau",
	"src/shared/PlayerSettings.luau",
	"src/server/FeedbackService.luau",
}
-- Sous-chemins ignorés : outils de debug (overlay F3, routes de perf, enregistreurs), jamais vus d'un joueur
LocaleScan.SKIP = { "src/client/debug/", "src/client/ui/DemoClipRules.luau" }

-- Textes affichés tels quels dans les deux langues
LocaleScan.ALLOWED = {
	["FRANÇAIS"] = true, -- nom de la langue, écrit dans sa langue (Locale.NAMES)
	["ENGLISH"] = true,
	-- Sigles, noms d'armes et mots identiques en anglais
	["AWP"] = true,
	["CTRL"] = true,
	["RUN"] = true,
	["FAST"] = true,
	["SURF"] = true,
	["MACH"] = true,
	-- Identifiants (états du client et de l'arme), jamais affichés
	["IDLE"] = true,
	["SCOPED"] = true,
	["RELOADING"] = true,
	["FIRING"] = true,
	["EQUIPPING"] = true,
	["SPAWNING"] = true,
	["DEAD"] = true,
	["RESULT"] = true,
	-- Titre du message du webhook de feedback (Discord du développeur)
	["Feedback joueur"] = true,
	-- Gabarit de texte riche du kill feed
	['<font color="#%s">%s</font>'] = true,
}

-- Champs dont la valeur n'est jamais traduite : noms d'Instances et identifiants partout, noms propres des skins (#518 :
-- choix de l'utilisateur, gardés tels quels) dans le catalogue
LocaleScan.UNTRANSLATED_FIELDS = { "Name", "id", "tool", "slot", "weapon", "appearance", "state", "kind" }
LocaleScan.UNTRANSLATED_FIELDS_BY_FILE = {
	["src/shared/InventoryRules.luau"] = { "name" },
}

-- Cette méthode permet de lister récursivement les fichiers .luau d'un dossier lorsque le scan démarre.
local function listFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			listFiles(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
end

-- Cette méthode permet de savoir si une chaîne littérale ressemble à un texte lu par le joueur lorsque le scan la
-- rencontre (cf. en-tête du module).
function LocaleScan.looksDisplayed(text: string): boolean
	if string.match(text, "^rbxasset") or string.match(text, "^https?:") then
		return false
	end
	-- Lettres accentuées du français (UTF-8)
	for _, accent in
		{
			"é",
			"è",
			"ê",
			"ë",
			"à",
			"â",
			"ç",
			"ù",
			"û",
			"ô",
			"î",
			"ï",
			"œ",
			"É",
			"È",
			"Ê",
			"À",
			"Ç",
			"Ô",
			"Î",
		}
	do
		if string.find(text, accent, 1, true) then
			return true
		end
	end
	-- Mot de trois capitales ou plus, hors identifiants (SCREAMING_CASE, chiffres collés)
	for word in string.gmatch(text, "[%a_%d]+") do
		if #word >= 3 and string.match(word, "^%u+$") then
			return true
		end
	end
	-- Phrase : deux mots ou plus, dont un en minuscules de deux lettres ou plus
	local words, lower = 0, false
	for word in string.gmatch(text, "%a+") do
		words += 1
		if string.match(word, "^%l%l+$") then
			lower = true
		end
	end
	return words >= 2 and lower and string.find(text, " ", 1, true) ~= nil
end

-- Cette méthode permet d'écarter le commentaire de fin d'une ligne lorsque ses chaînes sont lues (un « -- » placé dans
-- une chaîne est gardé).
local function stripComment(line: string): string
	local inString: string? = nil
	local i = 1
	while i <= #line do
		local ch = string.sub(line, i, i)
		if inString then
			if ch == "\\" then
				i += 1
			elseif ch == inString then
				inString = nil
			end
		elseif ch == '"' or ch == "'" or ch == "`" then
			inString = ch
		elseif string.sub(line, i, i + 1) == "--" then
			return string.sub(line, 1, i - 1)
		end
		i += 1
	end
	return line
end

-- Cette méthode permet de lister les chaînes littérales d'une ligne (guillemets doubles, simples et gabarits `…`) lorsque
-- le scan la lit ; les morceaux `{…}` d'un gabarit ne sont pas des textes.
local function literals(line: string): { string }
	local out = {}
	local i = 1
	while i <= #line do
		local quote = string.sub(line, i, i)
		if quote == '"' or quote == "'" or quote == "`" then
			local j = i + 1
			local buffer = {}
			while j <= #line do
				local ch = string.sub(line, j, j)
				if ch == "\\" then
					table.insert(buffer, string.sub(line, j + 1, j + 1))
					j += 2
				elseif ch == quote then
					break
				else
					table.insert(buffer, ch)
					j += 1
				end
			end
			table.insert(out, table.concat(buffer))
			i = j + 1
		else
			i += 1
		end
	end
	return out
end

-- Lignes de journal : leurs textes vont à la console, pas au joueur
local LOG_PATTERNS =
	{ "print%(", "warn%(", "error%(", "assert%(", "log%(", "Log%(", "CheatLog%.", "Analytics%.", "PerfMarkers%." }

-- Cette méthode permet de lister les textes affichés sans traduction des sources lorsque le test les vérifie ;
-- `hasEnglish(texte)` dit si un texte a sa traduction. Renvoie des lignes « fichier:ligne: texte ».
function LocaleScan.untranslated(hasEnglish: (string) -> boolean): { string }
	local files = table.clone(LocaleScan.FILES)
	for _, root in LocaleScan.ROOTS do
		listFiles(root, files)
	end
	local found = {}
	for _, path in files do
		local skipped = false
		for _, prefix in LocaleScan.SKIP do
			if string.sub(path, 1, #prefix) == prefix then
				skipped = true
			end
		end
		if skipped then
			continue
		end
		local lineNumber = 0
		local inLog = 0 -- parenthèses encore ouvertes d'un appel de journal sur plusieurs lignes
		for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			local code = stripComment(line)
			local isLog = inLog > 0
			for _, pattern in LOG_PATTERNS do
				if string.find(code, pattern) then
					isLog = true
				end
			end
			if isLog then
				local _, opened = string.gsub(code, "%(", "")
				local _, closed = string.gsub(code, "%)", "")
				inLog = math.max(0, inLog + opened - closed)
				continue
			end
			if string.match(code, "^%s*export type ") or string.match(code, "^%s*type ") then
				continue
			end
			-- Valeurs de champs non traduits et comparaisons (états, identifiants) : retirées de la ligne avant la lecture
			local fields = table.clone(LocaleScan.UNTRANSLATED_FIELDS)
			for _, field in LocaleScan.UNTRANSLATED_FIELDS_BY_FILE[path] or {} do
				table.insert(fields, field)
			end
			for _, field in fields do
				code = string.gsub(code, "%f[%w_]" .. field .. '%s*=%s*"[^"]*"', "")
			end
			code = string.gsub(code, '[=~]=%s*"[^"]*"', "")
			code = string.gsub(code, '"[^"]*"%s*[=~]=', "")
			code = string.gsub(code, '"[^"]*"%s*::', "")
			for _, text in literals(code) do
				if LocaleScan.looksDisplayed(text) and not LocaleScan.ALLOWED[text] and not hasEnglish(text) then
					table.insert(found, string.format("%s:%d: %s", path, lineNumber, text))
				end
			end
		end
	end
	return found
end

return LocaleScan

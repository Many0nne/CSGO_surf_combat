-- Écrit un parcours de mesure (#379) enregistré dans le jeu (debug/PerfRecorder) dans son module de données, après
-- l'avoir validé et, au besoin, coupé. Usage, depuis la racine du worktree :
--   lune run tools/perf/write_route.luau <source> <Nom> [début_s] [fin_s]
-- <source> : fichier contenant la valeur de Player.PerfRoutes.<nom> (lue par le MCP, contexte Client), ou une copie de
-- la console avec les lignes [PerfRoute …], ou un dossier de journaux Roblox (ex. %LOCALAPPDATA%\Roblox\logs) : la
-- dernière prise complète de la piste y est recollée ;
-- <Nom> : nom de la piste (module src/client/debug/routes/<Nom>.luau, remplacé ; attribut PerfRun = "<Nom>") ;
-- début et fin (secondes, optionnels) : garde seulement cette partie (le début recule au point de contrôle précédent).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local RULES = "src/shared/PerfRouteRules.luau"
local OUT_DIR = "src/client/debug/routes"

local source, name = process.args[1], process.args[2]
if not source or not name then
	print("usage : lune run tools/perf/write_route.luau <fichier|dossier de journaux> <Nom> [début_s] [fin_s]")
	process.exit(1)
end

local Rules = luau.load(fs.readFile(RULES), { debugName = RULES })()
local logName = string.lower(name)
local marker = "[" .. Rules.LOG_TAG .. " " .. logName .. " "

-- Cette méthode permet de lire la source donnée lorsque l'outil démarre : un fichier tel quel, ou les journaux d'un
-- dossier qui contiennent la piste, mis bout à bout (la prise la plus récente l'emporte au recollage).
local function readSource(path: string): string
	if not fs.isDir(path) then
		return fs.readFile(path)
	end
	local parts = {}
	for _, entry in fs.readDir(path) do
		local file = path .. "/" .. entry
		if fs.isFile(file) and string.sub(entry, -4) == ".log" then
			local ok, text = pcall(fs.readFile, file)
			if ok and string.find(text, marker, 1, true) then
				table.insert(parts, text)
			end
		end
	end
	return table.concat(parts, "\n")
end

-- Fins de ligne Windows retirées : le texte vient d'un copier-coller ou d'un journal
local raw = string.gsub(readSource(source), "\r", "")
if string.find(raw, marker, 1, true) then
	local fromLog, missing = Rules.fromLog(raw, logName)
	if not fromLog then
		print("console ou journal : " .. tostring(missing))
		process.exit(1)
	end
	raw = fromLog :: string
elseif fs.isDir(source) then
	print("aucune ligne " .. marker .. "…] dans les journaux de " .. source)
	process.exit(1)
end
raw = string.gsub(string.gsub(raw, "^%s+", ""), "%s+$", "")
local route, why = Rules.decode(raw)
if not route then
	print("piste illisible : " .. tostring(why))
	process.exit(1)
end

local first = tonumber(process.args[3]) or 0
local last = tonumber(process.args[4]) or Rules.duration(route)
local cut, cutWhy = Rules.trim(route, first, last)
if not cut then
	print(tostring(cutWhy))
	process.exit(1)
end

local text = Rules.encode(cut)
local checks = 0
for _, t in cut.ticks do
	if t.check then
		checks += 1
	end
end
local path = OUT_DIR .. "/" .. name .. ".luau"
fs.writeDir(OUT_DIR)
-- Fins de ligne CRLF, celles de StyLua (stylua.toml) : PerfRouteRules.decode ignore les \r
local module = "-- Parcours de mesure (#379) enregistré dans le jeu (debug/PerfRecorder) et écrit par\n"
	.. "-- tools/perf/write_route.luau. Rejoué par debug/PerfReplay (attribut PerfRun). Format : PerfRouteRules.\n"
	.. "return [[\n"
	.. text
	.. "\n]]\n"
fs.writeFile(path, (string.gsub(module, "\n", "\r\n")))
print(
	string.format(
		"%s : %.1f s, %d ticks, %d points de contrôle, %d octets, map %s",
		path,
		Rules.duration(cut),
		#cut.ticks,
		checks,
		#text,
		cut.map
	)
)

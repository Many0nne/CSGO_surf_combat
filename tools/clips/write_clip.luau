-- Écrit un clip de démo (#285) extrait de Studio dans son module de données, après l'avoir validé et, au besoin, coupé.
-- Usage, depuis la racine du worktree :
--   lune run tools/clips/write_clip.luau <texte_brut.txt> <Nom> [début_s] [fin_s]
-- <texte_brut.txt> : valeur de Player.DebugClips.<nom> lue par le MCP (contexte Client), copiée telle quelle, ou copie
-- de la sortie de Studio contenant les lignes [ClipData …] (playtest arrêté : dernière prise complète du clip) ;
-- <Nom> : Surf, Bhop, Strafe ou Chain (module src/client/ui/DemoClips/<Nom>.luau, remplacé) ;
-- début et fin (secondes, optionnels) : garde seulement cette partie de la prise.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local RULES = "src/client/ui/DemoClipRules.luau"
local OUT_DIR = "src/client/ui/DemoClips"

local rawPath, name = process.args[1], process.args[2]
if not rawPath or not name then
	print("usage : lune run tools/clips/write_clip.luau <texte_brut.txt> <Nom> [début_s] [fin_s]")
	process.exit(1)
end

local Rules = luau.load(fs.readFile(RULES), { debugName = RULES })()
-- Fins de ligne Windows retirées : le texte vient d'un copier-coller
local raw = string.gsub(fs.readFile(rawPath), "\r", "")
-- Copie de la sortie de Studio (lignes [ClipData …]) : dernière prise complète du clip
if string.find(raw, "[" .. Rules.LOG_TAG .. " ", 1, true) then
	local fromLog, missing = Rules.fromLog(raw, string.lower(name))
	if not fromLog then
		print("sortie de Studio : " .. tostring(missing))
		process.exit(1)
	end
	raw = fromLog :: string
end
raw = string.gsub(raw, "^%s+", "")
raw = string.gsub(raw, "%s+$", "")
local clip, why = Rules.decode(raw)
if not clip then
	print("clip illisible : " .. tostring(why))
	process.exit(1)
end

local first = tonumber(process.args[3]) or 0
local last = tonumber(process.args[4]) or Rules.duration(clip)
local kept = {}
for i, sample in clip.samples do
	local t = (i - 1) / clip.hz
	if t >= first - 1e-6 and t <= last + 1e-6 then
		table.insert(kept, sample)
	end
end
clip.samples = kept
if #kept < 2 then
	print("moins de deux échantillons entre " .. first .. " et " .. last .. " s")
	process.exit(1)
end

local text = Rules.encode(clip)
local path = OUT_DIR .. "/" .. name .. ".luau"
fs.writeDir(OUT_DIR)
-- Fins de ligne CRLF, celles de StyLua (stylua.toml) : DemoClipRules.decode ignore les \r
local module = "-- Démo rejouée de l'écran Infos > SURFER (#285), enregistrée dans Studio (debug/ClipRecorder) et écrite par\n"
	.. "-- tools/clips/write_clip.luau. Format : DemoClipRules (en-tête, puis écarts x y z yeux lacet tangage en\n"
	.. "-- centièmes, touches, vitesse x 10).\n"
	.. "return [[\n"
	.. text
	.. "\n]]\n"
fs.writeFile(path, (string.gsub(module, "\n", "\r\n")))
print(string.format("%s : %.1f s, %d échantillons, %d octets, map %s", path, Rules.duration(clip), #kept, #text, clip.map))

-- Extrait un enregistrement de partie (#582, debug/MatchRecorder) des journaux Roblox et l'écrit dans
-- recordings/<Nom>/ (un .txt par morceau, synchronisé par Rojo dans ServerStorage.MatchRecordings.<Nom> pour le rejeu
-- dans Studio, cf. docs/promo.md « Enregistreur de partie »). Usage, depuis la racine du checkout :
--   lune run tools/matchrec/extract.luau <source> <Nom> [enregistrement]
-- <source> : un journal Roblox, un dossier de journaux (ex. %LOCALAPPDATA%\Roblox\logs : ceux qui contiennent des
-- lignes [MatchRec …] sont lus) ou une copie de la console ;
-- <Nom> : nom du rejeu (attribut joueur MatchReplay = "<Nom>") ; le dossier recordings/<Nom>/ est remplacé ;
-- [enregistrement] : numéro de l'enregistrement (affiché au départ et à l'arrêt) ; défaut : le plus récent.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("../../tests/lib/Loader")

local OUT_DIR = "recordings"

local Rules = Loader.new():require("src/shared/MatchRecordRules")
local marker = "[" .. Rules.LOG_TAG .. " "

local source, name, wanted = process.args[1], process.args[2], process.args[3]
if not source or not name or not string.match(name, "^[%w_%-]+$") then
	print("usage : lune run tools/matchrec/extract.luau <journal|dossier de journaux> <Nom> [enregistrement]")
	print("  <Nom> : lettres, chiffres, _ et - seulement")
	process.exit(1)
end

-- Cette méthode permet de lire la source donnée lorsque l'outil démarre : un fichier tel quel, ou les journaux d'un
-- dossier qui contiennent des morceaux, mis bout à bout.
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

-- Cette méthode permet de décoder et de vérifier un morceau lorsqu'il est recollé ; nil et la raison s'il est abîmé.
local function decode(text: string): (any?, string?)
	local ok, data = pcall(serde.decode, "json", text)
	if not ok then
		return nil, "JSON illisible"
	end
	return Rules.readChunk(data)
end

local found = Rules.fromLog((string.gsub(readSource(source), "\r", "")))
local recs = {}
for rec in found do
	table.insert(recs, rec)
end
table.sort(recs, function(a, b)
	return (tonumber(a) or 0) < (tonumber(b) or 0)
end)
if #recs == 0 then
	print("aucun morceau [" .. Rules.LOG_TAG .. " …] complet dans " .. source)
	process.exit(1)
end

print("enregistrements trouvés :")
for _, rec in recs do
	local count, date = 0, "?"
	for seq, text in found[rec] do
		count += 1
		if seq == 1 then
			local chunk = decode(text)
			if chunk and chunk.meta and chunk.meta.date then
				date = tostring(chunk.meta.date)
			end
		end
	end
	print(string.format("  %s : %d morceau(x), début %s", rec, count, date))
end

local rec = wanted or recs[#recs]
local chunks = found[rec]
if not chunks then
	print("enregistrement " .. rec .. " introuvable")
	process.exit(1)
end

local seqs = {}
for seq in chunks do
	table.insert(seqs, seq)
end
table.sort(seqs)

local match = Rules.newMatch()
local dir = OUT_DIR .. "/" .. name
if fs.isDir(dir) then
	fs.removeDir(dir)
end
fs.writeDir(dir)
local written, bytes = 0, 0
for _, seq in seqs do
	local text = chunks[seq]
	local chunk, why = decode(text)
	if not chunk then
		print(string.format("morceau %d écarté : %s", seq, tostring(why)))
		continue
	end
	Rules.addChunk(match, chunk)
	fs.writeFile(string.format("%s/%04d.txt", dir, seq), text)
	written += 1
	bytes += #text
end
Rules.finish(match)
local summary = Rules.summary(match)
print(
	string.format(
		"%s → %s/ : %d morceau(x), %.0f Ko, %.1f s, %d participant(s), %d kill(s), %d tir(s), caméra %d relevés, map %s",
		rec,
		dir,
		written,
		bytes / 1024,
		summary.duration,
		summary.actors,
		summary.kills,
		summary.shots,
		summary.povRows,
		tostring(match.meta.map)
	)
)
if #match.missing > 0 then
	local list = {}
	for _, seq in match.missing do
		table.insert(list, tostring(seq))
	end
	print("morceaux manquants (trous dans le rejeu) : " .. table.concat(list, ", "))
end
for id, actor in match.actors do
	print(string.format("  %s%s (id %d) : %d relevés", actor.name, if actor.bot then " [bot]" else "", id, #actor.track.t))
end

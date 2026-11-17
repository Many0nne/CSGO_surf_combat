-- Liste les textes affichés restés sans traduction anglaise (#518), par fichier : `lune run tools/locale_scan.luau`
-- depuis la racine du worktree. Même règle que tests/specs/Locale.spec.luau (tests/lib/LocaleScan).
local Loader = require("../tests/lib/Loader")
local LocaleScan = require("../tests/lib/LocaleScan")

local fakeTask = {
	spawn = function(fn, ...)
		fn(...)
	end,
}
local Locale = Loader.new({}, { task = fakeTask }):require("src/shared/Locale")
local found = LocaleScan.untranslated(Locale.hasEnglish)
for _, line in found do
	print(line)
end
print(string.format("%d texte(s) sans traduction", #found))

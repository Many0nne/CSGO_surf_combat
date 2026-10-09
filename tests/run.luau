-- Point d'entrée des tests : `lune run tests/run.luau` depuis la racine du repo.
-- Exécute tous les fichiers tests/specs/*.spec.luau et sort en code 1 si un test échoue.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Loader = require("./lib/Loader")
local Test = require("./lib/Test")

local SPECS_DIR = "tests/specs"

local specs = {}
for _, name in fs.readDir(SPECS_DIR) do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in specs do
	local path = SPECS_DIR .. "/" .. name
	local env = { Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Instance = roblox.Instance }
	local ok, err = pcall(function()
		local spec = luau.load(fs.readFile(path), { debugName = path, environment = env })()
		spec(Test, Loader)
	end)
	if not ok then
		table.insert(Test.failures, { name = path .. " (chargement)", err = tostring(err) })
	end
end

for _, failure in Test.failures do
	print("ÉCHEC  " .. failure.name .. "\n       " .. failure.err)
end
print(string.format("\n%d réussi(s), %d échec(s) sur %d spec(s)", Test.passed, #Test.failures, #specs))

process.exit(#Test.failures == 0 and 0 or 1)

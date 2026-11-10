--!nocheck
-- Vérifie qu'aucune pièce ne dépasse de la surface de glisse des rampes de surf d'une map générée (#136) :
--   lune run tools/map/verify_ramps.luau [assets/rbx/Maps/Dizzy.rbxm]
-- Mesure de tools/map/RampCheck.luau (rayons le long de la normale de chaque rampe), en collision puis en rendu.
-- Affiche, rampe par rampe, la surface de glisse, le plus grand dépassement et les pièces responsables ; code de
-- sortie 1 s'il reste un rebord. build_dizzy.luau fait la même mesure et refuse d'écrire une map avec un rebord.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local RampCheck = require("./RampCheck")

local path = process.args[1] or "assets/rbx/Maps/Dizzy.rbxm"
local map = roblox.deserializeModel(fs.readFile(path))[1]
local lines, worst = RampCheck.check(map)
for _, line in lines do
	print(line)
end
print(string.format("tolérance %.2f stud : %s", RampCheck.TOL, if worst > RampCheck.TOL then "REBORD" else "OK"))
process.exit(if worst > RampCheck.TOL then 1 else 0)

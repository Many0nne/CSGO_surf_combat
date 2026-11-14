--!nocheck
-- Vues entre zones d'apparition d'une map générée (#329, tools/map/SpawnSight.luau) :
--   lune run tools/map/spawn_sight.luau [assets/rbx/Maps/Dizzy.rbxm]     (racine du worktree, sans Studio)
-- Bilan par paire de zones (attribut Zone des points, sinon Team) et paires de points qui se voient ; code de sortie 1
-- si deux zones différentes se voient. À relancer après tout ajout ou déplacement de point (docs/maps.md).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SpawnSight = require("./SpawnSight")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local path = args[1] or "assets/rbx/Maps/Dizzy.rbxm"
local map = roblox.deserializeModel(fs.readFile(path))[1]
local t0 = os.clock()
local tested, visible, rows = SpawnSight.check(map)
for _, row in rows do
	print(string.format("  %s / %s : %d paire(s), %d visible(s)", row.za, row.zb, row.pairs, row.visible))
end
for _, v in visible do
	print(string.format("  VU : %s <-> %s", v.a, v.b))
end
print(
	string.format(
		"%s : %d points, %d paires de zones différentes testées, %d visible(s) (%.1f s)",
		map.Name,
		#SpawnSight.points(map),
		tested,
		#visible,
		os.clock() - t0
	)
)
if #visible > 0 then
	process.exit(1)
end

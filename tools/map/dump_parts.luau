--!nocheck
-- Export des pièces visibles d'une map générée, pour les planches Blender (tools/map/render_dizzy.py, cf. docs/maps.md,
-- « Planche Blender ») :
--   lune run tools/map/dump_parts.luau -- <sortie.json> [x y z rayon]   (racine du worktree)
-- Lit assets/rbx/Maps/Dizzy.rbxm tel que build_dizzy.luau l'a écrit ; garde les pièces visibles (Transparency < 1) dont
-- le centre est à moins de `rayon` studs du point (toutes sans point). Coordonnées du monde (décalage de la map compris).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local MAP = "assets/rbx/Maps/Dizzy.rbxm"

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
assert(args[1], "usage : lune run tools/map/dump_parts.luau -- <sortie.json> [x y z rayon]")
local center = if args[5] then roblox.Vector3.new(tonumber(args[2]), tonumber(args[3]), tonumber(args[4])) else nil
local radius = tonumber(args[5] or "") or math.huge

-- Cette méthode permet d'arrondir un nombre au millième lorsqu'on l'écrit dans le JSON (fichier plus léger).
local function r(x)
	return math.floor(x * 1000 + 0.5) / 1000
end

-- directions des faces d'une pièce (SpotLight.Face), dans le repère de la pièce
local FACES = {
	Top = roblox.Vector3.new(0, 1, 0),
	Bottom = roblox.Vector3.new(0, -1, 0),
	Front = roblox.Vector3.new(0, 0, -1),
	Back = roblox.Vector3.new(0, 0, 1),
	Right = roblox.Vector3.new(1, 0, 0),
	Left = roblox.Vector3.new(-1, 0, 0),
}

local out, lights = {}, {}
for _, root in roblox.deserializeModel(fs.readFile(MAP)) do
	for _, p in root:GetDescendants() do
		if p:IsA("SpotLight") and p.Parent:IsA("BasePart") then
			local cf = p.Parent.CFrame
			local pos = cf.Position
			if not center or (pos - center).Magnitude <= radius then
				local d = cf:VectorToWorldSpace(FACES[p.Face.Name])
				table.insert(lights, {
					r(pos.X),
					r(pos.Y),
					r(pos.Z),
					r(d.X),
					r(d.Y),
					r(d.Z),
					p.Angle,
					p.Range,
					p.Brightness,
					math.floor(p.Color.R * 255 + 0.5),
					math.floor(p.Color.G * 255 + 0.5),
					math.floor(p.Color.B * 255 + 0.5),
				})
			end
		elseif p:IsA("BasePart") and p.Transparency < 1 then
			local cf = p.CFrame
			local pos = cf.Position
			if not center or (pos - center).Magnitude <= radius then
				local x, y, z = cf.RightVector, cf.UpVector, -cf.LookVector
				local shape = if p.ClassName == "Part" then p.Shape.Name else p.ClassName
				table.insert(out, {
					shape,
					r(pos.X),
					r(pos.Y),
					r(pos.Z),
					r(x.X),
					r(x.Y),
					r(x.Z),
					r(y.X),
					r(y.Y),
					r(y.Z),
					r(z.X),
					r(z.Y),
					r(z.Z),
					r(p.Size.X),
					r(p.Size.Y),
					r(p.Size.Z),
					math.floor(p.Color.R * 255 + 0.5),
					math.floor(p.Color.G * 255 + 0.5),
					math.floor(p.Color.B * 255 + 0.5),
					p.Material.Name,
					r(p.Transparency),
				})
			end
		end
	end
end
fs.writeFile(args[1], serde.encode("json", { parts = out, lights = lights }))
print(string.format("%d pièces, %d lumières -> %s", #out, #lights, args[1]))

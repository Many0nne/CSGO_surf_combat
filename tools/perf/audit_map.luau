-- audit_map.luau
-- Audit statique du coût de rendu et de physique d'une map (.rbxm), sans ouvrir Studio (cf. docs/performance.md) :
-- par dossier, nombre de pièces, ombres projetées, transparences, collisions et requêtes actives ; puis les lumières,
-- les plus grandes surfaces transparentes et les pièces dont l'ombre ou la requête ne sert probablement à rien.
-- Usage (racine du dépôt) : lune run tools/perf/audit_map.luau [assets/rbx/Maps/Dizzy.rbxm]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local mapPath = process.args[1] or "assets/rbx/Maps/Dizzy.rbxm"
local roots = roblox.deserializeModel(fs.readFile(mapPath))

local SMALL = 2 -- studs : une pièce dont la plus grande dimension est plus petite a une ombre peu visible
local TOP = 10 -- lignes des classements

type Row = {
	name: string,
	parts: number,
	wedges: number,
	shadow: number,
	transparent: number,
	invisible: number,
	collide: number,
	query: number,
	touch: number,
	smallShadow: number,
	invisibleShadow: number,
	materials: { [string]: boolean },
}

-- Cette méthode permet de créer une ligne de comptage vide lorsqu'un dossier est audité.
local function newRow(name: string): Row
	return {
		name = name,
		parts = 0,
		wedges = 0,
		shadow = 0,
		transparent = 0,
		invisible = 0,
		collide = 0,
		query = 0,
		touch = 0,
		smallShadow = 0,
		invisibleShadow = 0,
		materials = {},
	}
end

-- Cette méthode permet de compter une pièce dans une ligne lorsque l'audit parcourt son dossier.
local function count(row: Row, part: any)
	row.parts += 1
	if part.ClassName == "WedgePart" or part.ClassName == "CornerWedgePart" then
		row.wedges += 1
	end
	local size = part.Size
	local maxDim = math.max(size.X, size.Y, size.Z)
	if part.Transparency >= 1 then
		row.invisible += 1
	elseif part.Transparency > 0 then
		row.transparent += 1
	end
	if part.CastShadow then
		row.shadow += 1
		if part.Transparency >= 1 then
			row.invisibleShadow += 1
		elseif maxDim < SMALL then
			row.smallShadow += 1
		end
	end
	if part.CanCollide then
		row.collide += 1
	end
	if part.CanQuery then
		row.query += 1
	end
	if part.CanTouch then
		row.touch += 1
	end
	row.materials[tostring(part.Material)] = true
end

-- Cette méthode permet de donner le chemin lisible d'une instance lorsqu'un classement la cite.
local function pathOf(inst: any): string
	local names = {}
	local cur = inst
	while cur do
		table.insert(names, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(names, "/")
end

-- Cette méthode permet de lister les dossiers à auditer séparément lorsque la map a des sous-dossiers par rôle
-- (Geometry/Walls, Geometry/Ceilings, Dressing…).
local function groups(root: any): { any }
	local list = {}
	for _, child in root:GetChildren() do
		if child.Name == "Geometry" and #child:GetChildren() > 0 then
			for _, sub in child:GetChildren() do
				table.insert(list, sub)
			end
		else
			table.insert(list, child)
		end
	end
	return list
end

local total = newRow("TOTAL")
local rows: { Row } = {}
local transparentParts = {}
local lights = {}

for _, root in roots do
	for _, group in groups(root) do
		local row =
			newRow(if group.Parent and group.Parent ~= root then group.Parent.Name .. "/" .. group.Name else group.Name)
		local items = group:GetDescendants()
		table.insert(items, group)
		for _, inst in items do
			if inst:IsA("BasePart") then
				count(row, inst)
				count(total, inst)
				if inst.Transparency > 0 and inst.Transparency < 1 then
					local s = inst.Size
					local area = math.max(s.X * s.Y, s.Y * s.Z, s.X * s.Z)
					table.insert(transparentParts, { path = pathOf(inst), area = area, t = inst.Transparency })
				end
			elseif inst:IsA("Light") then
				table.insert(lights, inst)
			end
		end
		if row.parts > 0 then
			table.insert(rows, row)
		end
	end
end

table.sort(rows, function(a, b)
	return a.parts > b.parts
end)

-- Cette méthode permet de compter les matières distinctes d'une ligne lorsqu'on l'affiche.
local function materialCount(row: Row): number
	local n = 0
	for _ in row.materials do
		n += 1
	end
	return n
end

-- Cette méthode permet d'écrire une ligne du tableau lorsque l'audit affiche un dossier ou le total.
local function printRow(row: Row)
	print(
		string.format(
			"%-20s %6d %6d %7d %6d %6d %7d %6d %6d %8d %8d %4d",
			row.name,
			row.parts,
			row.wedges,
			row.shadow,
			row.transparent,
			row.invisible,
			row.collide,
			row.query,
			row.touch,
			row.smallShadow,
			row.invisibleShadow,
			materialCount(row)
		)
	)
end

print("Audit de " .. mapPath .. "\n")
print(
	string.format(
		"%-20s %6s %6s %7s %6s %6s %7s %6s %6s %8s %8s %4s",
		"dossier",
		"pièces",
		"coins",
		"ombre",
		"transp",
		"invis",
		"collide",
		"query",
		"touch",
		"ombre<2",
		"ombreInv",
		"mat"
	)
)
for _, row in rows do
	printRow(row)
end
printRow(total)
print(
	"\nombre<2 : ombre projetée par une pièce de moins de "
		.. SMALL
		.. " studs ; ombreInv : ombre projetée par une pièce invisible (Transparency 1)."
)

print(string.format("\nLumières : %d", #lights))
for _, light in lights do
	print(
		string.format(
			"  %-12s ombres=%-5s portée=%-5.0f luminosité=%-4.1f %s",
			light.ClassName,
			tostring(light.Shadows),
			light.Range or 0,
			light.Brightness,
			pathOf(light)
		)
	)
end

table.sort(transparentParts, function(a, b)
	return a.area > b.area
end)
print(string.format("\nPlus grandes surfaces transparentes (%d pièces translucides) :", #transparentParts))
for i, p in transparentParts do
	if i > TOP then
		break
	end
	print(string.format("  %10.0f studs²  T=%.2f  %s", p.area, p.t, p.path))
end

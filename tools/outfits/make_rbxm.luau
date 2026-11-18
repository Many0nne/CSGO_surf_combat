-- make_rbxm.luau
-- Fabrique le dossier d'une tenue de personnage (#521) sans Studio : clone le dossier d'une tenue existante
-- (SurfaceAppearance de chaque pièce du rig et coque de tête, avec toutes leurs propriétés) depuis une place construite
-- par Rojo, y pose les ids d'image publiés de la nouvelle tenue (ids.json de tools/skins/publish_skin.py) et écrit
-- assets/rbx/Outfits/<nom>.rbxm. La coque garde le mesh du modèle (même forme, autre carte).
-- Le .rbxm d'origine, écrit par Studio, ne se relit pas directement dans Lune (propriété Tags) : passer par la place.
-- Usage (racine du worktree) :
--   rojo build -o <place.rbxl>
--   lune run tools/outfits/make_rbxm.luau <place.rbxl> <modèle> <nom> <ids.json>
--   ex. lune run tools/outfits/make_rbxm.luau place.rbxl mercure bronze assets/outfits/bronze/maps/patine/ids.json

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath, template, name, idsPath = table.unpack(process.args)
assert(placePath and template and name and idsPath, "usage : make_rbxm.luau <place.rbxl> <modèle> <nom> <ids.json>")
assert(string.match(name, "^[%w_%-]+$"), "nom de tenue invalide : " .. name)

local ids = serde.decode("json", fs.readFile(idsPath))
local game = roblox.deserializePlace(fs.readFile(placePath))
local source = game:GetService("ReplicatedStorage"):FindFirstChild("Outfits")
source = source and source:FindFirstChild(template)
assert(source, "ReplicatedStorage.Outfits." .. template .. " absent de la place")

-- Cette méthode permet de donner l'atlas (groupe de r15_bake) d'une pièce du rig lorsqu'on lui pose ses cartes.
local function groupOf(part: string): string
	if string.find(part, "Torso") then
		return "Torso"
	end
	local side = if string.sub(part, 1, 4) == "Left" then "Left" else "Right"
	local limb = if string.find(part, "Arm") or string.find(part, "Hand") then "Arm" else "Leg"
	return side .. limb
end

-- Cette méthode permet de poser les quatre cartes d'un atlas publié sur une SurfaceAppearance lorsqu'on habille une
-- pièce de la nouvelle tenue.
local function apply(appearance, maps)
	assert(maps, "cartes absentes de ids.json pour " .. appearance:GetFullName())
	appearance.ColorMapContent = roblox.Content.fromUri(maps.Color)
	appearance.NormalMapContent = roblox.Content.fromUri(maps.Normal)
	appearance.MetalnessMapContent = roblox.Content.fromUri(maps.Metal)
	appearance.RoughnessMapContent = roblox.Content.fromUri(maps.Rough)
end

local outfit = source:Clone()
outfit.Name = name
local count = 0
for _, child in outfit:GetChildren() do
	if child:IsA("SurfaceAppearance") then
		apply(child, ids.R15[groupOf(child.Name)])
		count += 1
	elseif child:IsA("MeshPart") and child.Name == "Head" then
		local appearance = child:FindFirstChildOfClass("SurfaceAppearance")
		assert(appearance, "coque sans SurfaceAppearance dans " .. template)
		apply(appearance, ids.Head and ids.Head.Head)
	end
end
assert(count == 14, "14 SurfaceAppearance attendues, " .. count .. " trouvées")

local out = "assets/rbx/Outfits/" .. name .. ".rbxm"
fs.writeFile(out, roblox.serializeModel({ outfit }))
print("[make_rbxm] " .. out .. " (" .. count .. " pièces + coque, modèle " .. template .. ")")

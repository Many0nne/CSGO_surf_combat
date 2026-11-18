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

local OutfitMaps = require("./OutfitMaps")

local placePath, template, name, idsPath = table.unpack(process.args)
assert(placePath and template and name and idsPath, "usage : make_rbxm.luau <place.rbxl> <modèle> <nom> <ids.json>")
assert(string.match(name, "^[%w_%-]+$"), "nom de tenue invalide : " .. name)

local ids = serde.decode("json", fs.readFile(idsPath))
local game = roblox.deserializePlace(fs.readFile(placePath))
local source = game:GetService("ReplicatedStorage"):FindFirstChild("Outfits")
source = source and source:FindFirstChild(template)
assert(source, "ReplicatedStorage.Outfits." .. template .. " absent de la place")

-- Cette méthode permet de poser les quatre cartes d'un atlas publié sur une SurfaceAppearance lorsqu'on habille une
-- pièce de la nouvelle tenue.
local function apply(appearance, maps)
	assert(maps, "cartes absentes de ids.json pour " .. appearance:GetFullName())
	for property, kind in OutfitMaps.KINDS do
		assert(maps[kind], "carte " .. kind .. " absente de ids.json pour " .. appearance:GetFullName())
		appearance[property] = roblox.Content.fromUri(maps[kind])
	end
end

local outfit = source:Clone()
outfit.Name = name
local count = 0
local hasHead = false
for _, child in outfit:GetChildren() do
	if child:IsA("SurfaceAppearance") then
		local group = OutfitMaps.groupOf(child.Name)
		assert(group, "SurfaceAppearance " .. child.Name .. " : pas une pièce du rig")
		apply(child, ids.R15[group])
		count += 1
	elseif child:IsA("MeshPart") and child.Name == "Head" then
		local appearance = child:FindFirstChildOfClass("SurfaceAppearance")
		assert(appearance, "coque sans SurfaceAppearance dans " .. template)
		apply(appearance, ids.Head and ids.Head.Head)
		hasHead = true
	end
end
assert(count == 14, "14 SurfaceAppearance attendues, " .. count .. " trouvées")
assert(hasHead or not ids.Head, "ids.json publie une coque, mais le modèle " .. template .. " n'en a pas")

local out = "assets/rbx/Outfits/" .. name .. ".rbxm"
fs.writeFile(out, roblox.serializeModel({ outfit }))
print("[make_rbxm] " .. out .. " (" .. count .. " pièces + coque, modèle " .. template .. ")")

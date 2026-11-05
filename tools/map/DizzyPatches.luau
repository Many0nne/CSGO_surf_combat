--!nocheck
-- Retouches locales de Dizzy (tools/map/dizzy_patches.luau), appliquées par build_dizzy.luau après le plan relevé :
-- une correction ponctuelle survit ainsi à la régénération et à un nouveau relevé. Coordonnées du monde, telles que
-- Studio les affiche (décalage de la map compris). Testé par tests/specs/DizzyPatches.spec.luau.
--
-- Opérations (chaque retouche a un champ `why` obligatoire) :
--   { op = "remove",  why = "...", zone = { center = {x, y, z}, size = {x, y, z} }, folder = "Clips" }
--   { op = "add",     why = "...", position = {x, y, z}, size = {x, y, z}, rotation = {rx, ry, rz},
--                     kind = "Part" | "WedgePart", look = "wall" }
--   { op = "restyle", why = "...", zone = {...}, folder = "Walls", look = "decor:metal" }
-- `folder` (facultatif) limite la zone à un dossier de Geometry (Floors, Walls, Ceilings, Ramps, Decor, Clips).
-- `rotation` (facultatif, degrés) suit CFrame.Angles ; `kind` vaut Part par défaut. `look` : floor, slope, wall,
-- ceiling, surf, clip, ou decor:<groupe> (metal, rock, plastic…), cf. LOOK et DECOR de build_dizzy.luau.
-- Une zone qui ne contient aucune pièce est une erreur (coordonnées fausses, ou pièce déjà retirée par le relevé).

local roblox = if Vector3 then nil else require("@lune/roblox")
local V3 = if roblox then roblox.Vector3 else Vector3
local CF = if roblox then roblox.CFrame else CFrame
local New = if roblox then roblox.Instance.new else Instance.new

local DizzyPatches = {}

DizzyPatches.OPS = { remove = true, add = true, restyle = true }
DizzyPatches.FOLDERS = { Floors = true, Walls = true, Ceilings = true, Ramps = true, Decor = true, Clips = true }
-- dossier où ranger une pièce ajoutée, d'après son habillage
local FOLDER_OF = {
	floor = "Floors",
	slope = "Floors",
	wall = "Walls",
	ceiling = "Ceilings",
	surf = "Ramps",
	clip = "Clips",
}

-- Cette méthode permet de lire un triplet {x, y, z} de la liste des retouches en Vector3 (nil s'il est mal formé).
local function vec(t)
	if type(t) ~= "table" or #t ~= 3 then
		return nil
	end
	for _, c in t do
		if type(c) ~= "number" then
			return nil
		end
	end
	return V3.new(t[1], t[2], t[3])
end

-- Cette méthode permet de vérifier la liste des retouches avant de toucher à la map : renvoie la liste des erreurs
-- (vide si tout est bon), chaque erreur nommant la retouche par son numéro et son `why`.
function DizzyPatches.validate(patches): { string }
	local errors = {}
	for i, p in patches do
		local name = string.format("retouche %d (%s)", i, tostring(p.why))
		local function bad(msg)
			table.insert(errors, name .. " : " .. msg)
		end
		if type(p.why) ~= "string" or p.why == "" then
			bad("champ `why` manquant (dire pourquoi la retouche existe)")
		end
		if not DizzyPatches.OPS[p.op] then
			bad(string.format("op %q inconnue (remove, add, restyle)", tostring(p.op)))
		elseif p.op == "add" then
			if not vec(p.position) or not vec(p.size) then
				bad("`position` et `size` doivent être des triplets de nombres")
			end
			if p.rotation ~= nil and not vec(p.rotation) then
				bad("`rotation` doit être un triplet de degrés")
			end
			if p.kind ~= nil and p.kind ~= "Part" and p.kind ~= "WedgePart" then
				bad("`kind` vaut Part ou WedgePart")
			end
			if type(p.look) ~= "string" then
				bad("`look` manquant")
			end
		else
			if type(p.zone) ~= "table" or not vec(p.zone.center) or not vec(p.zone.size) then
				bad("`zone` doit avoir `center` et `size` (triplets de nombres)")
			end
			if p.folder ~= nil and not DizzyPatches.FOLDERS[p.folder] then
				bad(string.format("dossier %q inconnu", tostring(p.folder)))
			end
			if p.op == "restyle" and type(p.look) ~= "string" then
				bad("`look` manquant")
			end
		end
	end
	return errors
end

-- Cette méthode permet de savoir si un point est dans une zone (boîte alignée sur les axes, centre et taille).
function DizzyPatches.inZone(point, zone): boolean
	local c, s = vec(zone.center), vec(zone.size)
	local d = point - c
	return math.abs(d.X) <= s.X / 2 and math.abs(d.Y) <= s.Y / 2 and math.abs(d.Z) <= s.Z / 2
end

-- Cette méthode permet de lister les pièces de Geometry dont le centre est dans la zone d'une retouche, limitées à
-- son dossier s'il est donné.
local function matching(geometry, p)
	local found = {}
	for _, folder in geometry:GetChildren() do
		if p.folder == nil or folder.Name == p.folder then
			for _, part in folder:GetChildren() do
				-- CFrame.Position et non Position : hors moteur (Lune), Position n'existe pas sur une pièce posée par CFrame
				if part:IsA("BasePart") and DizzyPatches.inZone(part.CFrame.Position, p.zone) then
					table.insert(found, part)
				end
			end
		end
	end
	return found
end

-- Cette méthode permet d'appliquer les retouches dans l'ordre à la géométrie d'une map lorsque le générateur l'a
-- posée ; style(part, look) habille une pièce. Lève une erreur si la liste est invalide ou si une zone est vide.
-- Renvoie, pour chaque retouche, le nombre de pièces touchées.
function DizzyPatches.apply(geometry, patches, style): { number }
	local errors = DizzyPatches.validate(patches)
	if #errors > 0 then
		error("dizzy_patches invalide :\n  " .. table.concat(errors, "\n  "), 2)
	end
	local counts = {}
	for i, p in patches do
		if p.op == "add" then
			local part = New(p.kind or "Part")
			part.Anchored = true
			part.CanTouch = false
			local r = if p.rotation then vec(p.rotation) else V3.new(0, 0, 0)
			part.CFrame = CF.new(vec(p.position)) * CF.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
			part.Size = vec(p.size)
			style(part, p.look)
			part:SetAttribute("Patch", p.why)
			local folderName = FOLDER_OF[p.look] or "Decor"
			local folder = geometry:FindFirstChild(folderName)
			if not folder then
				folder = New("Folder")
				folder.Name = folderName
				folder.Parent = geometry
			end
			part.Parent = folder
			counts[i] = 1
		else
			local found = matching(geometry, p)
			if #found == 0 then
				error(string.format("retouche %d (%s) : aucune pièce dans la zone", i, p.why), 2)
			end
			for _, part in found do
				if p.op == "remove" then
					part:Destroy()
				else
					style(part, p.look)
					part:SetAttribute("Patch", p.why)
				end
			end
			counts[i] = #found
		end
	end
	return counts
end

return DizzyPatches

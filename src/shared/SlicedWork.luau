-- Travail long étalé sur plusieurs frames (#605) : parcours et copie de maps (~20 000 pièces) sans geler une image.
-- `slicer` rend une tranche de calcul par frame (budget en secondes), repérée sous son nom dans le MicroProfiler
-- (debug.profilebegin, refermé avant chaque attente) et chronométrée pour la sonde serveur et l'overlay (PerfMarkers).
-- `eachDescendant` parcourt dans l'ordre de GetDescendants (préfixe, en profondeur), `cloneInto` copie une map dossier
-- par dossier, dans le même ordre que Clone : les calculs faits sur la copie sont ceux qu'on ferait sur l'original.
-- Limites de cloneInto : pièces copiées une à une, donc une référence d'un sous-arbre à un autre (Weld, ObjectValue,
-- PrimaryPart) garde sa cible d'origine, et un modèle recréé n'a ni PrimaryPart ni pivot. Le plan des bots ne lit que
-- la géométrie (pièces, noms de dossiers, attributs) : à revoir si un calcul fait sur la copie en vient à les lire.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local SlicedWork = {}

-- debug.profilebegin n'existe que dans Roblox : sous Lune (tests), les repères ne font rien.
local profilebegin = (debug :: any).profilebegin or function(_label: string) end
local profileend = (debug :: any).profileend or function() end

export type Slicer = {
	step: () -> (), -- à appeler souvent : rend la main au moteur une fois la tranche de la frame écoulée
	finish: () -> (), -- à appeler une fois le travail fini (referme le repère)
}

-- Cette méthode permet de préparer le découpage d'un travail long lorsqu'il ne doit pas dépasser `budget` secondes par
-- frame : `step` cède la main (task.wait) quand la tranche est écoulée, `finish` clôt la dernière tranche.
function SlicedWork.slicer(label: string, budget: number): Slicer
	local sliceStart = os.clock()
	local open = true
	profilebegin(label)
	-- Cette méthode permet de clore la tranche en cours (repère refermé, temps relevé) lorsqu'on va céder la main.
	local function close()
		if open then
			profileend()
			PerfMarkers.record(label, os.clock() - sliceStart)
			open = false
		end
	end
	return {
		step = function()
			if os.clock() - sliceStart > budget then
				close()
				task.wait()
				sliceStart = os.clock()
				open = true
				profilebegin(label)
			end
		end,
		finish = close,
	}
end

-- Cette méthode permet de visiter tous les descendants d'une instance lorsqu'un parcours doit être étalé : même ordre
-- que GetDescendants, `step` appelé après chaque visite.
function SlicedWork.eachDescendant(root: Instance, visit: (Instance) -> (), step: (() -> ())?)
	for _, child in root:GetChildren() do
		visit(child)
		if step then
			step()
		end
		SlicedWork.eachDescendant(child, visit, step)
	end
end

-- Cette méthode permet de copier un dossier ou un modèle sans son contenu lorsqu'une copie est faite morceau par
-- morceau : classe, nom, attributs et tags (pas le pivot d'un modèle : sans effet sur les requêtes du plan).
local function shellOf(source: Instance): Instance
	local copy = Instance.new(source.ClassName :: any)
	copy.Name = source.Name
	for key, value in source:GetAttributes() do
		copy:SetAttribute(key, value)
	end
	for _, tag in source:GetTags() do
		copy:AddTag(tag)
	end
	return copy
end

-- Cette méthode permet de copier une map sous `parent` lorsque Clone d'une traite gèlerait une frame : dossiers et
-- modèles recréés vides puis remplis un enfant à la fois, dans l'ordre (non Archivable ignoré, comme Clone).
function SlicedWork.cloneInto(source: Instance, parent: Instance, step: (() -> ())?): Instance
	local copy = shellOf(source)
	copy.Parent = parent
	for _, child in source:GetChildren() do
		if not child.Archivable then
			continue
		end
		if child:IsA("Folder") or child:IsA("Model") then
			SlicedWork.cloneInto(child, copy, step)
		else
			local part = child:Clone()
			if part then
				part.Parent = copy
			end
		end
		if step then
			step()
		end
	end
	return copy
end

-- Cette méthode permet de détruire une copie de map lorsqu'on n'en a plus besoin, sans geler une frame : enfants
-- détruits un à un, dossiers vidés avant d'être détruits.
function SlicedWork.destroy(root: Instance, step: (() -> ())?)
	for _, child in root:GetChildren() do
		if child:IsA("Folder") or child:IsA("Model") then
			SlicedWork.destroy(child, step)
		else
			child:Destroy()
		end
		if step then
			step()
		end
	end
	root:Destroy()
end

return SlicedWork

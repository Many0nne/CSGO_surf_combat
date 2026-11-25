-- AssetPreload.luau
-- Préparation en tâche de fond de ce qui coûterait au premier usage (#606) : chargement des images et des meshes, et
-- remplissage des réserves d'Instances des effets par petits lots (une frame cédée tous les CHUNK Instances créées).
-- Les fonctions qui cèdent la frame (`images`, `instances`, `created`) s'appellent depuis une tâche (task.spawn).
--
-- ContentProvider:PreloadAsync échoue sur un id brut (type d'asset deviné) et ne lit pas les cartes d'une
-- SurfaceAppearance : chaque image passe par un ImageLabel hors de l'interface (cf. docs/assets.md).
local ContentProvider = game:GetService("ContentProvider")

local AssetPreload = {}

-- Instances créées par frame au plus pendant le remplissage des réserves
AssetPreload.CHUNK = 60

local made = 0

-- Cette méthode permet de compter les Instances qu'une réserve vient de créer lorsqu'elle se remplit en tâche de fond,
-- et de céder la frame une fois CHUNK atteint.
function AssetPreload.created(count: number)
	made += count
	if made >= AssetPreload.CHUNK then
		made = 0
		task.wait()
	end
end

-- Cette méthode permet de charger des images (ids rbxassetid://) lorsqu'on veut les trouver en cache à leur premier
-- affichage ; `onStatus` reçoit l'état de chaque image. Cède la frame jusqu'à la fin du chargement.
function AssetPreload.images(uris: { string }, onStatus: ((string, Enum.AssetFetchStatus) -> ())?)
	if #uris == 0 then
		return
	end
	local labels = table.create(#uris)
	for _, uri in uris do
		local label = Instance.new("ImageLabel")
		label.Image = uri
		table.insert(labels, label)
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, labels, onStatus)
	for _, label in labels do
		label:Destroy()
	end
end

-- Cette méthode permet de charger le contenu d'Instances (meshes et textures de MeshParts, de modèles) lorsqu'on veut
-- le trouver en cache à leur première apparition. Cède la frame jusqu'à la fin du chargement.
function AssetPreload.instances(list: { Instance })
	if #list > 0 then
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end
end

return AssetPreload

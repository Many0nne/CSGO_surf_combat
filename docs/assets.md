# Assets : viewmodels, Tools, publication

Procédures détaillées pour modifier une arme et publier un asset. Les règles à ne jamais oublier sont résumées dans `CLAUDE.md`.

## Viewmodels et Tools (.rbxm)

Les viewmodels et les Tools sont versionnés en `.rbxm` binaires (Git LFS, `assets/rbx/**`) et synchronisés par Rojo :
une branche peut modifier une arme sans manipulation dans la place. Un fichier = une instance racine, nommée d'après le
fichier. Rojo gère `ReplicatedStorage.ViewModels` et `StarterPack` : une instance ajoutée à la main dans Studio y est supprimée à la
connexion (patch de rattrapage du plugin, testé), et toute modification faite dans Studio est perdue si elle n'est pas
réexportée.

**Ne jamais réécrire un `.rbxm` pendant que Studio est connecté à ce serveur Rojo** (export, `git checkout`, `git pull`…).
Même à l'identique, Rojo envoie sur chaque `Model` du fichier un patch contenant `NeedsPivotMigration`, que le plugin ne peut
pas écrire : il remplace alors le `Model` par une copie venue de `/api/serialize`, qui n'a plus de `PrimaryPart` (Rojo 7.7.1).
Une instance créée à la main peut aussi se retrouver en double, avec un joint cassé : la pièce détachée tombe.
**Réparation : Disconnect puis Connect, et accepter le patch de rattrapage** (`PrimaryPart` rétablis, doublons retirés). Ne pas
sauvegarder la place avant.

Mettre à jour un `.rbxm` (après modification d'une arme dans Studio, ou pour ajouter une arme) :

0. Plugin Rojo : **Disconnect**, et rester déconnecté jusqu'à la fin de l'export.
1. Dans Studio (mode Edit), modifier ou ajouter l'instance sous `ReplicatedStorage.ViewModels` ou dans `StarterPack`
   (noms en `[A-Za-z0-9_-]`). Rojo n'écrit jamais vers les fichiers : la modification n'existe que dans Studio.
2. Depuis la racine du worktree : `lune run tools/rbxm/receive.luau` (serveur local, port fixe 34990, attend Studio ;
   un seul export à la fois, tous worktrees confondus).
3. Exécuter `tools/rbxm/studio_export.luau` dans Studio : via le MCP (`execute_luau`, contexte Edit, coller le contenu du
   fichier) ou la barre de commande (exige Game Settings > Security > *Allow HTTP Requests*). Il vérifie les noms (un
   fichier par instance, sans doublon) et que `StarterPack` ne contient que des Tools, sérialise (`SerializationService`)
   chaque viewmodel, chaque Tool, la map et ses matières (`MaterialService`, cf. `docs/maps.md`) et les envoie au
   serveur, qui écrit `assets/rbx/ViewModels/<Nom>.rbxm`, `assets/rbx/Tools/<Nom>.rbxm`, `assets/rbx/Maps/<Nom>.rbxm`
   et `assets/rbx/Materials/<Nom>.rbxm`, supprime les `.rbxm` qui n'existent plus dans la place, puis s'arrête. Si l'export
   échoue dans Studio, le serveur s'arrête en erreur sans rien supprimer.
   Sans MCP : clic droit sur l'instance > *Save to File…* > `assets/rbx/<Dossier>/<Nom>.rbxm` (format binaire).
4. `rojo build default.project.json -o CSGO.rbxlx && lune run tools/rbxm/verify_place.luau` : relit la place produite,
   liste viewmodels et Tools (animations, sons, scripts, MeshParts, attributs), échoue si un viewmodel ou un Tool manque,
   si un `ViewmodelName` ne pointe vers aucun viewmodel, ou si une animation ou un mesh n'a pas d'id ; signale les Tools
   sans entrée dans `WeaponConfig.Weapons` (attribut `WeaponName`, sinon nom du Tool). Lancé aussi par la CI.
5. Reconnecter le plugin Rojo et accepter le patch de rattrapage, puis lancer le helper de playtest sur l'arme (étape `VIEWMODEL`).
6. Relire `git status` (l'export réécrit tous les fichiers) et commiter. Un `.rbxm` d'arme non modifiée peut différer de
   quelques octets d'un export à l'autre (constaté sur `AWP.rbxm` : 1 octet, ids identiques, cause inconnue).

Notes :
- Studio écrit les ids sous leurs noms récents (`AnimationContent`, `AudioContent`, `MeshContent`) : Lune 0.9 ne les
  expose pas tous ni ne relit tous les `.rbxm` de Studio (`Animation.Tags`), d'où la vérification sur la place XML
  produite par Rojo plutôt que sur les `.rbxm`.
- `MeshPart.MeshId` n'est pas modifiable par un plugin : Rojo 7.7 passe par son endpoint `/api/serialize` pour créer ces
  instances (testé en synchro live et à la reconnexion : aucun mesh vide).

Transition d'une place qui contient déjà ces instances (une fois, pour éviter les doublons et l'ancienne version) :
1. Studio en mode Edit, plugin Rojo déconnecté. Supprimer `ReplicatedStorage.ViewModels` (le dossier entier) et les Tools
   de `StarterPack` (`AWP`, `M9Bayonet`).
2. Connecter le plugin Rojo (port du checkout ou du worktree) : Rojo recrée le dossier et les Tools depuis `assets/rbx/`.
3. Vérifier qu'il y a un seul exemplaire de chaque, que les MeshParts sont visibles (pas de bloc gris) et qu'une arme
   s'équipe en playtest, puis sauvegarder la place (File > Save to Roblox).
   Si un MeshPart est vide : clic droit sur `ReplicatedStorage` > *Insert from File…* > le `.rbxm`, et le signaler.

## Publier un asset (Open Cloud)

Clé dans la variable d'environnement utilisateur `ROBLOX_OPEN_CLOUD_KEY` (scopes `asset:read` et `asset:write`). Créateur :
user 434916384, propriétaire de l'expérience.

```bash
bash tools/publish_asset.sh <fichier> <Animation|Model|Audio|Decal> <nom>    # écrit l'assetId sur la sortie standard
bash tools/anim/publish.sh <dossier> <prefixe> <Nom1> [Nom2 ...] # plusieurs animations, affiche Nom=id
```

- Animation : `.rbxm` ou `.rbxmx` contenant une KeyframeSequence. `rbxtemp://` est refusé en playtest : publier pour tester.
- Image d'interface : publier en `Decal`, puis prendre l'id de l'image contenue dans le Decal (voir `docs/ui.md`) : celui du Decal ne s'affiche pas.
- Mesh : exporter avec `blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx>`, publier
  en `Model`, puis `insert_asset(assetId)` via le MCP Studio (mode Edit). On obtient un Model de MeshParts, sans import manuel.
- Axes : dans Blender, l'avant du modèle est +Y et le haut +Z ; Roblox reçoit `(x, z, -y)` et 1 unité Blender = 1 stud.
  `axis_forward` et `bake_space_transform` n'ont aucun effet : l'importeur Roblox donne toujours `(-x, z, y)` depuis un FBX
  brut (4 combinaisons testées). `export_mesh_fbx.py` compense donc par une rotation de 180° autour de Z.

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
   Export partiel : `lune run tools/rbxm/receive.luau Menu` et `ONLY = "Menu"` dans le script (seul ce dossier est
   écrit et nettoyé) ; `assets/rbx/Menu/` reçoit les jeux d'éclats du menu (`ReplicatedStorage.MenuMirrors`, #112).
   Le MCP refuse l'envoi tant que `localhost:34990` n'est pas dans la liste HTTP autorisée de l'Assistant
   (« not in the Assistant HTTP allowlist », Studio > Assistant > Settings > MCP Permissions) : l'y ajouter une fois.
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

## Aperçus three.js (skins, nouveaux modèles)

Tant qu'un élément n'est pas défini (skin, matière, nouvelle arme), on ne cherche ni dans le Blender ouvert ni dans
Studio : on montre à l'utilisateur une page three.js avec des variantes numérotées sur le vrai modèle, il répond par
numéro (« la 3 avec la lame de la 5 »), on refait la page. Ce n'est pas un outil qu'il manipule : il regarde et tourne le
modèle, les variantes sont produites par Claude.

**Règle : une variante est faite de PNG** (`Color`, `Rough`, `Metal`, `Normal`, les cartes de la `SurfaceAppearance`),
jamais d'un effet propre à three.js. C'est ce qui permet de publier telle quelle la version retenue. Le rendu three.js
(éclairage neutre, ACES) reste proche de Roblox sans être identique : la validation finale se fait en jeu.

1. **Le modèle en `.glb`**, hors du dépôt (`%TEMP%/preview/<arme>/`), avec un manifeste `.json` qui liste les textures
   actuelles de chaque matériau :
   - depuis la source Blender (l'AWP : `assets/sniper/Sniper.blend`) ; écrit aussi le dépliage UV de chaque matériau en
     SVG (`<sortie>_uv_<MATERIAU>.svg`), pour dessiner une texture qui tombe au bon endroit :
     ```bash
     blender -b assets/sniper/Sniper.blend --factory-startup --python tools/preview/export_glb.py -- "$TEMP/preview/awp/awp.glb" assets/sniper/textures
     ```
   - depuis le jeu, pour une arme sans source Blender (la M9, mesh du Creator Store) ou pour voir ce que le jeu affiche :
     lit la place construite par Rojo, télécharge meshs et cartes par Open Cloud (un matériau par pièce, nommé comme
     elle ; bras ignorés ; dépliage UV en SVG comme ci-dessus). La clé `ROBLOX_OPEN_CLOUD_KEY` doit avoir le scope `legacy-asset:manage` (Asset Delivery) ;
     sans lui : `Scope not authorized`. Meshs Roblox v2 à v7 lus, y compris compressés en Draco (cas des meshs publiés récemment ; normales recalculées).
     ```bash
     uv run tools/preview/fetch_viewmodel.py M9Bayonet "$TEMP/preview/m9/m9.glb"
     ```
2. **Les variantes** dans un `spec.json` (format en tête de `tools/preview/make_preview.py`) : chaque variante remplace,
   matériau par matériau, les cartes du manifeste par un PNG, une teinte (`"#rrggbb"`) ou un nombre (rugosité, métal).
   Les PNG des pistes vont à côté du spec, hors du dépôt.
3. **La page** : `uv run tools/preview/make_preview.py <spec.json> <sortie.html>`. Tout est dans le fichier (seul three.js
   vient de jsDelivr). Avec `"height": 560` et `"maxSize": 512` dans le spec, elle s'affiche dans la conversation
   (`html_render` de T3) ; sans, elle prend tout l'écran du navigateur. L'aperçu sans GPU de T3 (`html_preview`) dépasse
   son délai au-delà d'environ 3 Mo : réduire `maxSize` pour un contrôle.
4. **Version retenue** : ses PNG à pleine résolution dans `assets/skins/<Viewmodel>/<skin>/` (LFS), avec le `spec.json`
   qui l'a produite. Puis l'appliquer dans le jeu (ci-dessous).

### Appliquer un skin dans le jeu

1. Publier chaque PNG (`bash tools/publish_asset.sh <png> Decal <nom>`) et relever l'id de l'image contenue dans le
   Decal (procédure dans `docs/ui.md` : l'id du Decal lui-même ne s'affiche pas). Noter les ids dans
   `assets/skins/<Viewmodel>/<skin>/ids.json`.
2. Studio réservé et connecté au worktree, mode Edit : poser les ids sur la `SurfaceAppearance` de chaque pièce du
   viewmodel (`ColorMapContent`, `RoughnessMapContent`, `MetalnessMapContent`, `NormalMapContent`, avec
   `Content.fromUri("rbxassetid://…")`), via `execute_luau`.
3. Réexporter le viewmodel (« Mettre à jour un `.rbxm` » ci-dessus), puis vérifier en jeu (helper de playtest, étape
   `VIEWMODEL`) et faire juger le rendu par l'utilisateur. Le modèle 3P clone les pièces du viewmodel : il suit. La
   vitrine du menu, elle, est une image précalculée (`MenuMirrorsData`) : elle garde l'ancien rendu.

## Ajouter un couteau

Un couteau qui se joue comme la M9, avec un autre modèle et d'autres animations. Le comportement de mêlée est piloté par
la config (`IsMelee`), pas par le nom de l'arme ; seuls quelques endroits nomment la M9.

1. **Modèle** : chercher la forme par aperçus three.js (ci-dessus), puis le modéliser dans Blender par script avec des
   UV propres et les cartes PBR en PNG, publier (« Publier un asset » ci-dessus, point Mesh), `insert_asset`.
2. **Viewmodel** : copier `ViewModels.M9Bayonet` (bras, `FakeCamera`, `HumanoidRootPart`, Motor6D), remplacer la pièce
   `Handle` par le nouveau mesh, en gardant son nom (le 3P en a besoin) et ses joints. Réexporter.
3. **Animations** : `Equip`, `Shoot`, `Shoot2`, `Stab`, `Inspect` (noms lus par `WeaponConfig`), méthode de
   `docs/animations.md` à partir d'une vidéo de référence ; le rig de `assets/m9_viewmodel/` (`rig.json`,
   `build_viewmodel.py`) sert de base. Le coup part au marqueur `Stab Sound`.
4. **Tool** : copier `StarterPack.M9Bayonet`, attributs `ViewmodelName` (le nouveau viewmodel) et `WeaponName` (la
   nouvelle entrée de config).
5. **Config** : une entrée dans `WeaponConfig.Weapons` (copier `M9Bayonet` : mêmes dégâts et cadences pour un couteau
   identique en jeu ; refaire `ThirdPerson.Grip` pour le nouveau mesh, `tools/anim/poses3p/`), et une poussée dans
   `DeathRules.PUSH_BY_WEAPON` (sinon `DEFAULT_PUSH`).
6. **Endroits qui nomment la M9**, à décider selon que le couteau la remplace ou s'y ajoute : `BotCombatRules.KNIFE`
   (couteau des bots), `MainMenu.CONFIG_KEYS` et `MenuMirrorsData` (vitrine du menu, qui demande un jeu d'éclats
   recalculé, `tools/menu/`).
7. `rojo build` + `tools/rbxm/verify_place.luau` (signale un Tool sans entrée de config), puis le helper de playtest sur
   le nouveau Tool.

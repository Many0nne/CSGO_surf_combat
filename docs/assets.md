# Assets : viewmodels, Tools, publication

Procédures détaillées pour modifier une arme et publier un asset. Les règles à ne jamais oublier sont résumées dans `CLAUDE.md`.

## Viewmodels et Tools (.rbxm)

Les viewmodels et les Tools sont versionnés en `.rbxm` binaires (Git LFS, `assets/rbx/**`) et synchronisés par Rojo :
une branche peut modifier une arme sans manipulation dans la place. Un fichier = une instance racine, nommée d'après le
fichier. Rojo gère `ReplicatedStorage.ViewModels`, `ReplicatedStorage.Tools` et `StarterPack` (vide depuis #267 : les
Tools sont donnés par le serveur selon l'inventaire, `InventoryStore`) : une instance ajoutée à la main dans Studio y est supprimée à la
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
1. Dans Studio (mode Edit), modifier ou ajouter l'instance sous `ReplicatedStorage.ViewModels` ou `ReplicatedStorage.Tools`
   (noms en `[A-Za-z0-9_-]`). Rojo n'écrit jamais vers les fichiers : la modification n'existe que dans Studio.
2. Depuis la racine du worktree : `lune run tools/rbxm/receive.luau` (serveur local, port fixe 34990, attend Studio ;
   un seul export à la fois, tous worktrees confondus).
3. Exécuter `tools/rbxm/studio_export.luau` dans Studio : via le MCP (`execute_luau`, contexte Edit, coller le contenu du
   fichier) ou la barre de commande (exige Game Settings > Security > *Allow HTTP Requests*). Il vérifie les noms (un
   fichier par instance, sans doublon) et que `ReplicatedStorage.Tools` ne contient que des Tools, sérialise (`SerializationService`)
   chaque viewmodel, chaque Tool, la map et ses matières (`MaterialService`, cf. `docs/maps.md`) et les envoie au
   serveur, qui écrit `assets/rbx/ViewModels/<Nom>.rbxm`, `assets/rbx/Tools/<Nom>.rbxm`, `assets/rbx/Maps/<Nom>.rbxm`
   et `assets/rbx/Materials/<Nom>.rbxm`, supprime les `.rbxm` qui n'existent plus dans la place, puis s'arrête. Si l'export
   échoue dans Studio, le serveur s'arrête en erreur sans rien supprimer.
   Export partiel : `lune run tools/rbxm/receive.luau Maps` et `ONLY = "Maps"` dans le script (seul ce dossier est
   écrit et nettoyé).
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
   de `StarterPack` (`AWP`, `M9Bayonet` : une place d'avant #267 les y garde encore, le serveur les retire au démarrage
   avec un warn `[InventoryStore]`).
2. Connecter le plugin Rojo (port du checkout ou du worktree) : Rojo recrée le dossier et les Tools depuis `assets/rbx/`.
3. Vérifier qu'il y a un seul exemplaire de chaque, que les MeshParts sont visibles (pas de bloc gris) et qu'une arme
   s'équipe en playtest, puis sauvegarder la place (File > Save to Roblox).
   Si un MeshPart est vide : clic droit sur `ReplicatedStorage` > *Insert from File…* > le `.rbxm`, et le signaler.

## Effets du tir (flamme, rayon)

Code : `ShotEffects` (client), réglages et règles pures dans `ShotEffectRules` (testées). Une arme à distance porte sa
bouche de canon dans son viewmodel : l'Attachment `Barrel.ShootPart` (chemin `ShotEffectRules.MUZZLE_PATH`, à la sortie
du canon) et son `ParticleEmitter` `MuzzleEffect`, **désactivé** (`Enabled = false`) : le code l'allume par `Emit` à
chaque tir. Le modèle 3P clone les pièces du viewmodel (`WeaponThirdPerson`), il a donc la même bouche de canon, réduite
par `ScaleTo` avec le reste de l'arme.

- **Flamme :** forme, taille, couleur et durée sont celles du `MuzzleEffect` du `.rbxm` (texture 421803006, vie 0,1 s,
  `LockedToPart` pour suivre le recul). Seul le nombre de particules par tir est dans le code
  (`MUZZLE_EMIT_COUNT`) : elles naissent au même point, en ajouter rend la flamme plus opaque, pas plus grande.
- **Rayon :** `TRACER_WIDTH`, `TRACER_LIFETIME` (durée du fondu, courbe `tracerTransparency`), `TRACER_RGB`. Il part de la
  bouche du canon et finit au point d'impact du raycast de visée (le vide : portée `HITSCAN_RANGE`). Canon dans un mur
  (bouche au-delà de l'impact) ou rayon plus court que `TRACER_MIN_LENGTH` : pas de rayon. Le rayon reste fixe dans le
  monde : une caméra qui passe à moins de `HIDE_RADIUS` de lui (surf vers l'avant juste après le tir) le masque pour la
  frame. Le fondu passe par `FADE_STEPS` séquences précalculées (pas de `NumberSequence` créée par frame).
- **Chez les autres :** chaque `ShotFired` relayé par le serveur (joueurs et bots) allume la flamme du canon 3P du tireur
  et trace un rayon de ce canon au point que touche, chez le client, le rayon origine + direction relayées. Le tireur
  distant est dessiné en retard (interpolation) alors que l'origine relayée est à jour : comme dans CS, le rayon va du
  canon dessiné à l'impact réel, un peu de biais quand le tireur surfe vite. Seul un canon à plus de
  `MUZZLE_MAX_OFFSET` de l'origine (personnage pas à jour) fait partir le rayon de l'origine. La partie d'un rayon à
  moins de `NEAR_CAMERA` de notre caméra est retirée (`clipNearCamera` : tir qui nous touche, nous frôle, ou tireur
  collé à nous) : sinon le Beam, face à la caméra, couvre l'écran. Au plus `MAX_ACTIVE` rayons en même temps (au-delà,
  un tir relayé n'a que sa flamme) ; le tir local a toujours son rayon et compte parmi eux.
- **Nouvelle arme à distance :** garder `Barrel.ShootPart.MuzzleEffect` dans son viewmodel (le copier de l'AWP), sinon
  elle tire sans flamme et son rayon part de l'œil.
- **Vérifier qu'un tir ne laisse rien :** le rayon crée deux `Attachment` dans `Terrain` (et un `Beam`), tous nommés
  `ShotTracer` : leur nombre revient à 0 après `TRACER_LIFETIME`.
- **Mesures (#54, Studio) :** bouche du canon du viewmodel AWP à 8,5 studs de la caméra (un mur plus proche que ça :
  pas de rayon local) ; flamme 3P à 0,7 × la taille du viewmodel (`ScaleTo` réduit aussi les particules) ; créer un
  rayon coûte ~0,1 ms ; un tir relayé de bot donne un rayon qui part exactement du canon 3P.
- **Juger la flamme en capture :** elle vit 0,1 s et commence invisible (taille 0, transparence 1), donc la figer
  (`TimeScale = 0`) juste après l'`Emit` ne montre rien. Allonger plutôt `Lifetime` (par ex. 3 s, les courbes suivent),
  `Emit`, puis capturer avec `screen_capture` du MCP. La capture de fenêtre par `PrintWindow` (`capture_server.py`)
  montre bien le rayon, mais **pas les particules** : une flamme absente de ces images n'est pas une flamme absente.
- **Piloter un tir de test (MCP, contexte Server) :** le remote `DebugPlaytest` accepte les commandes du helper,
  `FireClient(player, id, "aim", { target = Vector3 })` puis `"attack", { tool = "AWP" }`. Un tir relayé de bot se
  simule par `ShotFired:FireClient(player, botCharacter, "AWP", origine, direction)` (vrai chemin de `ShotEffects`).

## Douille éjectée (#237)

Code : `CasingEjection` (client), réglages et règles pures dans `CasingRules` (testées). Une arme qui éjecte porte sa
fenêtre d'éjection dans son viewmodel : l'Attachment `Handle.EjectPort` (chemin `CasingRules.PORT_PATH`), orientée
+X vers l'extérieur (côté droit de l'arme), +Y vers le haut, +Z vers l'arrière. Le modèle 3P clone les pièces du
viewmodel avec leurs enfants (`WeaponThirdPerson`) : il a la même fenêtre, réduite par `ScaleTo`.

- **Déclenchement 1P :** marqueur `Eject` de la piste `Shoot` (culasse en arrière, `docs/animations.md`), branché par
  `ViewmodelSystem.playAnimation`. Pas de douille si le viewmodel est masqué (lunette) à cet instant.
- **Chez les autres :** chaque `ShotFired` relayé (joueurs et bots) éjecte de l'arme 3P du tireur `CasingEjectDelay`
  plus tard (champ de l'arme dans `WeaponConfig`, instant du marqueur : l'arme 3P ne joue pas la piste ; sans ce champ,
  pas de douille 3P). L'état du client est revérifié à l'éjection (menu ouvert entre-temps : rien). La douille hérite
  du déplacement moyen de l'arme pendant ce délai (approximation ; un saut au-delà de `MAX_INHERITED_SPEED`, vitesse
  maximale d'un joueur plus une marge, est ignoré). Pas de douille pour un tireur à plus de `MAX_REMOTE_DISTANCE`.
- **Vol calculé :** arc balistique et rotation constante (`CasingRules.cframeAt`), dans le monde : la douille hérite de
  la vitesse du joueur (`MovementController.getVelocity`), comme dans CS. Forme : cylindre de laiton (`LENGTH`,
  `DIAMETER`, `COLOR_RGB`), à l'échelle de l'arme. Vitesse, dispersion, rotation, gravité et durée de vie dans
  `CasingRules`.
- **Pool :** au plus `POOL_SIZE` Parts ancrées, sans collision ni requête ni ombre, créées au premier besoin et
  réutilisées. Pool plein : une douille du joueur local prend la plus ancienne, celle d'un autre est abandonnée (elle
  ne chasse jamais celle qu'on voit devant soi). Dans `workspace` pendant le vol (pas sous la caméra : une caméra
  remplacée détruirait la pièce), `Parent = nil` ensuite. Pas de douille d'un tireur mort pendant le délai. Boucle
  `RenderStepped` (repère `douilles`) branchée seulement tant qu'une douille vole.
- **Échelle :** `CasingRules` est réglé dans le repère du viewmodel tel qu'il est stocké (échelle 1 en 1P). Ne pas
  lire `GetScale()` sur le viewmodel : il vaut 0,517 pour l'AWP (modèle mis à l'échelle à sa création), ce qui rendait
  la douille 1P deux fois trop petite et lente. Sur l'arme 3P (`Model` neuf passé par `ScaleTo`), `GetScale()` est
  bien l'échelle relative au viewmodel (0,7).
- **Vérifier qu'un tir ne laisse rien :** aucune pièce `ShotCasing` dans le `DataModel` après `LIFETIME`.
- **Nouvelle arme qui éjecte :** ajouter `Handle.EjectPort` à son viewmodel, le marqueur `Eject` à sa piste de tir et
  `CasingEjectDelay` (instant de ce marqueur) à son entrée de `WeaponConfig`.

## Publier un asset (Open Cloud)

Clé dans la variable d'environnement utilisateur `ROBLOX_OPEN_CLOUD_KEY` (scopes `asset:read` et `asset:write`). Créateur :
user 434916384, propriétaire de l'expérience.

```bash
bash tools/publish_asset.sh <fichier> <Animation|Model|Audio|Decal> <nom>    # écrit l'assetId sur la sortie standard
bash tools/anim/publish.sh <dossier> <prefixe> <Nom1> [Nom2 ...] # plusieurs animations, affiche Nom=id
```

- Animation : `.rbxm` ou `.rbxmx` contenant une KeyframeSequence. `rbxtemp://` est refusé en playtest : publier pour tester.
- Image d'interface : publier en `Decal`, puis prendre l'id de l'image contenue dans le Decal (voir `docs/ui.md`) : celui du Decal ne s'affiche pas.
  Sans Studio : `curl -H "x-api-key: $CLE" https://apis.roblox.com/asset-delivery-api/v1/assetId/<id du Decal>` renvoie
  une `location` ; le fichier qu'elle désigne (le Decal en XML) contient `id=<id de l'image>` (`curl --compressed`).
- Mesh : exporter avec `blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx>`, publier
  en `Model`, puis `insert_asset(assetId)` via le MCP Studio (mode Edit). On obtient un Model de MeshParts, sans import manuel.
- Axes : dans Blender, l'avant du modèle est +Y et le haut +Z ; Roblox reçoit `(x, z, -y)` et 1 unité Blender = 1 stud.
  `axis_forward` et `bake_space_transform` n'ont aucun effet : l'importeur Roblox donne toujours `(-x, z, y)` depuis un FBX
  brut (4 combinaisons testées). `export_mesh_fbx.py` compense donc par une rotation de 180° autour de Z.

## Modèle d'arme procédural dans Blender (couteau Ka-Bar)

Source : `assets/kabar_knife/` (`build_knife.py` forme + UV, `make_textures.py` cartes PBR, `render_board.py` planche).
Dans Blender : `TEX_DIR = ".../assets/kabar_knife/textures"`, puis `exec` de `build_knife.py` **avant** `make_textures.py`
(le second réutilise les constantes du premier), puis `render_board.py`. Unité du modèle : le pouce (à recaler sur la M9 à
l'export). Trois objets, un par matériau (lame, ferrures, cuir), donc trois MeshParts et trois `SurfaceAppearance`.

- **Juger le matériau en aperçu matériau (`look`, `shading: material`), jamais en Workbench** : Workbench n'a aucun reflet et
  fait paraître n'importe quel métal en plastique. Se comparer à la M9 dans le même éclairage : `fetch_viewmodel.py` (section
  ci-dessous) donne son `.glb` et ses PNG, à importer dans Blender avec ses cartes branchées.
- **Valeurs PBR de la M9 à reprendre** : métal à 0 ou 1 (jamais 0,5), rugosité de 0,3 à 0,5 pour le métal, jamais 0,6 à 0,7.
  Le détail vient de stries fines étirées (brossage), pas de nuages à grande échelle (ça fait « vieille texture »).
- **Les PNG sont en sRGB direct** : une valeur de 0,07 est presque noire à l'écran, viser 0,25 à 0,4 pour de l'acier sombre.
- **Normales** : forces modérées. Un grain de cuir trop marqué (plis profonds, cellules larges) donne un crocodile ; relief de
  l'ordre de 0,006 en hauteur pour 1024 px. Sens des normales (Y vers le haut) à vérifier dans Studio.
- **Dépliage** : lame à plat par côté (moitié droite de la texture pour x >= 0, marquage d'un seul côté), pièces de révolution
  en cylindre (u = angle, v = y), garde et fonds plats en planaire dans la zone médiane de la texture (sinon stries radiales).

## Aperçus three.js (skins, nouveaux modèles)

> Piste abandonnée pour créer un modèle ou un skin (essai jeté le 2026-11-10) : modéliser dans Blender (section ci-dessus). Les
> étapes de `fetch_viewmodel.py` restent utiles pour récupérer un modèle du jeu.

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
4. **Version retenue** : voir « Skins d'arme (#268) » ci-dessous (la méthode des skins a changé : plus de three.js).

## Skins d'arme (#268)

Un skin est un item de l'inventaire (`InventoryRules.ITEMS` : `skin.<arme>.<nom>`, `name` affiché, `appearance`), choisi
à l'écran d'équipement et rendu partout où l'arme apparaît : 1re personne (`ViewmodelSystem`), arme vue par les autres
(`WeaponThirdPerson.attach` côté serveur, skin lu dans l'équipement du joueur), personnage de l'accueil (`MenuScene`),
grand rendu et cartes de l'écran d'équipement (`UIKit.weaponSilhouette`). Tous passent par `WeaponSkins.apply`.

**Un script de jeu ne peut pas écrire les cartes d'une `SurfaceAppearance`** (`ColorMapContent`… : sécurité plugin). Les
`SurfaceAppearance` d'un skin sont donc toutes faites : `assets/rbx/Skins/<Viewmodel>/<skin>.model.json` (Rojo :
`ReplicatedStorage.Skins.<Viewmodel>.<skin>`, une par pièce, nommée comme elle), et le jeu les clone sur les pièces de
l'arme clonée. Le skin d'origine reprend les `SurfaceAppearance` du viewmodel. Le viewmodel 1re personne est cloné une
fois par session (cache) : seules ses `SurfaceAppearance` changent quand le skin change.

Sources versionnées : `assets/skins/<skin>/<Viewmodel>/<PREFIXE>_<Carte>.png` (LFS, une paire AWP + M9 par dossier) et
`assets/skins/<skin>/ids.json` (ids des images publiées). Pas de skin par défaut : ils viendront des caisses, l'admin a
tout le catalogue.

### Fabriquer un skin

Tout est généré par script : motifs calculés sur la position 3D de chaque texel (continus d'une pièce à l'autre, quel
que soit le découpage UV) ou projetés depuis la vue de profil (livrée, texte), détail des cartes d'origine gardé.

1. **Cartes utilitaires** (une fois par arme, hors du dépôt) : position, normale, occlusion, arêtes et objet de chaque
   texel, à la résolution des textures. La M9 vient du jeu (`fetch_viewmodel.py`, section « Aperçus three.js »).
   ```bash
   blender -b assets/sniper/Sniper.blend --factory-startup --python tools/skins/bake_maps.py -- <sortie>/awp
   blender -b --factory-startup --python tools/skins/bake_maps.py -- <sortie>/m9 --glb <m9.glb>
   ```
2. **Cartes PBR** : `uv run --with numpy --with pillow --with scipy tools/skins/make_skins.py <bake> <m9_orig> <sortie>
   [skin…]` (une fonction par skin et par arme dans le script : couchant, impact, releve, recuit, strate, sillage).
3. **Planche** : `tools/skins/render_views.py` (Cycles, HDRI de Blender, une vue par PNG, ~12 s par vue à 32
   échantillons) puis `tools/skins/compose_board.py`. Se comparer aux références `references/skins/` avant de montrer.
4. **Publier** : `uv run tools/skins/publish_skin.py assets/skins/<skin> <skin>` (Decals, puis id de l'image par Asset
   Delivery, ~5 s par carte, reprise possible), puis `uv run tools/skins/make_rbx.py assets/skins/<skin>`.
5. **Catalogue** : une ligne par arme dans `InventoryRules.ITEMS` (`appearance` = nom du fichier `.model.json`). Le test
   du catalogue vérifie que le fichier existe.
6. **Juger en jeu** (Studio, écran d'équipement) : l'éclairage du jeu change beaucoup le rendu des métaux.

Pour un aperçu sans code (avant d'avoir le catalogue) : `tools/skins/apply_skin_lua.py <ids.json | origine>` écrit le
Luau qui pose un skin sur les viewmodels de Studio (mode Edit) ; Disconnect/Connect de Rojo remet l'origine.

### Pièges

- **Juger la couleur en « Standard »**, pas en AgX : AgX fait virer un rouge vif au saumon.
- **Un bois ou une peinture sombre non métallique prend un voile gris** sous les reflets (Fresnel) et fait plastique :
  une peinture « candy » sombre se fait en métal (métal 1, couleur sombre saturée, rugosité basse).
- **Profondeur d'un Doppler** : fond presque noir marbré, nappes lumineuses saturées, rugosité 0,05 à 0,12. Des
  paillettes en points clairs font poussière : à éviter.
- **Courbes de niveau** : écart mesuré en unités monde (taille monde d'un pixel, propre à chaque îlot UV), pas en pixels
  UV ; les courbes trop serrées s'effacent (intermédiaires d'abord), sinon une pièce fine se couvre de rayures.
- **Livrée projetée de profil** : texte lisible des deux côtés en retournant la toile de la face +y ; placer le texte
  d'après la silhouette mesurée sur les cartes cuites (la crosse de l'AWP n'a que ~0,18 de hauteur de boîte à la poignée).
- **Densité de texture** : la crosse de l'AWP a peu de pixels dans sa carte (îlots en diagonale) ; une livrée plus fine
  demanderait de redéplier ses UV (mesh à republier).
- **Bois teinté (crosse de l'AWP)** : partir de la couleur et de la rugosité du bois d'origine. Des couleurs posées à
  plat virent au pastel sous le voile du vernis ; teinter en divisant canal par canal par la couleur moyenne fait virer
  au violet. Moduler la nouvelle teinte par la luminance d'origine (`mat.lum`) garde le grain et la saturation.
- **Laque noire brillante = chrome** sous l'HDRI : une peinture noire se fait satinée (rugosité ~0,38).
- **Biseau de la M9** : le masque `Knife.grind` couvre tout le grand biseau, pas seulement le fil. Un skin peint (laque,
  céramique) ne garde poli que le fil (`blade_height < 0.1` dans `grind`), sinon la lame paraît chromée.
- Sous l'éclairage du mode Edit (crépuscule), les skins métalliques paraissent bien plus sombres qu'en Blender.
- **Tester un skin en jeu** : le serveur refuse `EquipItem` pendant un round ; équiper depuis l'accueil (remote
  `ReplicatedStorage.EquipItem:FireServer(slot, armeId, skinId)` côté client, juste après le lancement du playtest), puis
  `DebugPlaytest`.
- **Préchargement (#333)** : un skin jamais affiché met 1 à 3 s à charger ses cartes (16 cartes de l'AWP : ~2,9 s à
  froid, 66 ms en cache, mesuré dans Studio), l'arme paraît grise entre-temps. `SkinPreloader` (client) précharge les
  skins équipés au démarrage et à chaque changement d'équipement. `ContentProvider:PreloadAsync` ne lit **pas** les
  cartes d'une `SurfaceAppearance` (aucune requête) et échoue sur un id brut (`Asset type does not match`) ; passer
  chaque carte par un `ImageLabel` (un `Decal` marche aussi mais écrit deux avertissements par carte). Le rendu d'une
  arme ne remplit pas `GetAssetFetchStatus` : ce statut ne dit pas si l'arme affichée est texturée. Le cache persiste
  d'un playtest à l'autre dans une même session Studio : mesurer à froid sur un skin jamais chargé.
  **Autres joueurs (#342)** : `SkinPreloader` lit aussi `OwnedItems` / `EquippedItems` des autres `Player` (déjà présents,
  arrivants, changements), au plus 1 skin par emplacement (`SkinPreloadRules.skinsOf`, spec `SkinPreloadRules`), même
  passage par `ImageLabel` et même table `requested`. Mesure (Studio, 1 seul client) : `PreloadAsync` des 16 cartes
  d'un skin froid = 0,64 s (+100 Mo de `Memory`), mais le même appel sur un skin déjà demandé met encore 0,45 à
  0,60 s : ce chronomètre ne distingue pas le froid du chaud, il ne mesure donc pas le gris visible. Le gain du
  préchargement des autres joueurs n'est **pas mesuré** (il faut un 2e client : Test > Clients and Servers).
- Rojo (7.7) écrit bien `ColorMapContent`… d'une `SurfaceAppearance` depuis un `.model.json`, en build comme en synchro
  directe (vérifié dans Studio) : pas besoin de `.rbxm` pour les skins.
- Suites ouvertes : caisses (#332), UV de la crosse de l'AWP (#335).

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
4. **Tool** : copier `ReplicatedStorage.Tools.M9Bayonet`, attributs `ViewmodelName` (le nouveau viewmodel) et
   `WeaponName` (la nouvelle entrée de config). Puis l'item dans le catalogue de l'inventaire (`InventoryRules.ITEMS`,
   id stable `weapon.<nom>`, `tool` = nom du Tool) : sans lui, aucun joueur ne reçoit l'arme (admin compris), et dans
   `InventoryRules.DEFAULT_ITEMS` si tout joueur doit l'avoir (#267).
5. **Config** : une entrée dans `WeaponConfig.Weapons` (copier `M9Bayonet` : mêmes dégâts et cadences pour un couteau
   identique en jeu ; refaire `ThirdPerson.Grip` pour le nouveau mesh, `tools/anim/poses3p/`), et une poussée dans
   `DeathRules.PUSH_BY_WEAPON` (sinon `DEFAULT_PUSH`).
6. **Endroits qui nomment la M9**, à décider selon que le couteau la remplace ou s'y ajoute : `BotCombatRules.KNIFE`
   (couteau des bots, pris dans l'inventaire par défaut : Ka-Bar depuis #267). L'accueil du menu prend tout seul les
   Tools possédés de `ReplicatedStorage.Tools` (`MenuScene`, attribut `WeaponName`) et tient un couteau le long du corps (`MenuPoses.Melee`, tenue M2, avec la prise du jeu). Une nouvelle arme à
   distance demande sa tenue de menu (`MenuPoses`, tenue M1 de `tools/anim/poses3p/poses.js`).
7. `rojo build` + `tools/rbxm/verify_place.luau` (signale un Tool sans entrée de config), puis le helper de playtest sur
   le nouveau Tool.

### Retour d'expérience : le Ka-Bar (3 MeshParts)

Mesh et textures déjà publiés (créateur 434916384) : `KaBar_Mesh` (Model) `83975015198873` ; images des `SurfaceAppearance`
(`ColorMap`, `MetalnessMap`, `NormalMap`, `RoughnessMap`) : lame `124191312180866`, `74907094682910`, `94195951916794`,
`140077592249861` ; ferrures `118493701544171`, `97521279426765`, `139401042642764`, `117522299042669` ; manche
`133923595339041`, `97532613922522`, `73079325706533`, `87566334772377`. `assets/kabar_viewmodel/export_mesh.py` refait le FBX.

- **Un couteau en plusieurs matières = plusieurs MeshParts** : `Handle` (le manche, qui porte le Motor6D `Handle`) et des pièces
  soudées par `WeldConstraint` (`Blade`, `Fittings`). Le 3P clone toutes les pièces du viewmodel et les soude à `Handle`.
- **Repère après l'import FBX** : la pointe est à -Z local, l'épaisseur de la lame sur X, le dos sur +Y. Le repère de prise du script
  d'animation (+Z pointe, +X tranchant) se retrouve avec `Q = CFrame.fromMatrix(0, (0,-1,0), (-1,0,0))` : `Handle.CFrame = Hs * Q`
  et `C1 = Q⁻¹ * C1_script`. Le `Grip` 3P devient celui de la M9 recalé : `Grip_M9 * CFrame.new(0,0,-1.21) * Q`.
- **Le FBX exporte aussi le cube de la scène par défaut** (`--factory-startup`) : le supprimer avant l'export (fait dans `export_mesh.py`).
- **`insert_asset` d'un Model publié** rend les MeshParts à leur disposition d'origine (pièces à rotation identique) : on y lit les
  décalages relatifs avant d'assembler.
- **Pas d'export complet pendant que Rojo est connecté** : un petit serveur local qui n'écrit que `KaBar.rbxm` évite de réécrire
  les autres armes. Le MCP Studio n'autorise que `localhost:34990` (liste HTTP de l'Assistant) : y faire tourner aussi le serveur
  de capture des animations (`CAPTURE_PORT=34990`, voir `docs/animations.md`), pas le 34991 par défaut.

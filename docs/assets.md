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

## Sons de l'AWP (#52, #488)

Les sons sont des `Sound` du dossier `Sounds` du viewmodel (`assets/rbx/ViewModels/AWP.rbxm`), joués par les marqueurs
`<Nom> Sound` des animations (`AnimationSoundSystem`). Le tir entendu par les autres joueurs réutilise le son `Shoot`
(`WeaponConfig.Weapons.AWP.RemoteShotSound`) : changer `Shoot` change les deux.

- **Tir (`Shoot`) :** « AWM/AWP FIRE » du Creator Store (`rbxassetid://6755643387`, son de Magmacow publié par
  Condecadence), 4,49 s, volume 0,5, validé à l'écoute en jeu (#488). Le critère « plus léger, peu de réverbération »
  de #52 était faux : l'AWP doit sonner **lourd**. Écartés à l'écoute : le Mosin-Nagant et le Kar98k (trop légers),
  « Heavy Sniper Fire 1 » (`87139385063956`) et « BARRETT .50CAL FIRE » (`6150717352`).
- **Chercher un son :** écarter les sons dont la description dit qu'ils viennent d'un autre jeu (CS, CoD, TF2…). Le MCP
  `search_asset` ne trouve rien avec plusieurs mots séparés par des espaces : chercher un mot (`sniper`, `barrett`,
  `awp`) avec `assetType = "Audio"` et `audioMaxDuration`.
- **Essayer un son :** changer `SoundId` de `ReplicatedStorage.ViewModels.AWP.Sounds.Shoot` en mode Edit (MCP), faire
  écouter, puis exporter (procédure « Mettre à jour un `.rbxm` » ci-dessus). En Play, le viewmodel déjà cloné sous la
  caméra garde l'ancien id : modifier aussi ses copies côté client (`workspace`, `Sound` nommés `Shoot`).
- **Export partiel `ViewModels` :** il réécrit aussi les viewmodels non modifiés (`KaBar.rbxm`, `M9Bayonet.rbxm`) avec
  quelques octets d'écart. Ne commiter que le viewmodel modifié.

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

## Caisse du shop (#332)

Source : `tools/shop/crate_model.py` (Blender sans interface). Une MeshPart par matière : `Interior`, `BodyPlanks`,
`BodyFrame`, `BodySteel`, `Rope`, et pour le couvercle (à ouvrir d'un bloc) `LidPlanks`, `LidFrame`, `LidSteel`,
`LidStripe` (bande de la collection). Origine au centre du dessous, avant vers -Y Blender (+Z Roblox), UV en
projection cubique (4 studs par unité). Couleurs et matières sont posées par le jeu (`ShopScene`, `CRATE_LOOK`), le
`.rbxm` ne porte que la géométrie ; `verify_place.luau` vérifie que les neuf pièces existent, et qu'il n'y a pas de
`LidStencil` dans le mesh.

**Pochoir du couvercle (#434)** : rien n'est écrit dans le mesh. `ShopScene` (`crate`, à la place donnée par `src/shared/CrateStencil.luau`) ajoute à chaque caisse
de la vitrine et du socle une pièce invisible `LidStencil` (préfixe `Lid` : elle s'ouvre avec le couvercle) portant une
`SurfaceGui` à droite de la bande, en Oswald Bold couleur encre (24, 22, 20), éclairée comme le bois. Le texte vient de
`ShopCatalog.stencil` (testé) : code de série tiré de ce qui suit `crate.<arme>.` dans l'id, séparateurs retirés (`serie<n>` → `S<n>`, sinon
première et dernière lettre, `film` → `FM`), ou le champ facultatif `series` de la caisse, prioritaire (#454). Un test vérifie que
les caisses du catalogue ont des pochoirs distincts : en cas de collision (`foam` → `FM` comme `film`), donner un `series`
(« FO ») à la nouvelle caisse, jamais renommer un id déjà vendu (serveur, inventaires). Puis un tiret, puis le nom court de l'arme (`WEAPON_LABELS`, sinon l'id sans `weapon.` en
capitales). Une nouvelle caisse `crate.<arme>.<série>` reçoit donc son pochoir sans toucher au rendu. Sans série, le
pochoir est l'arme seule ; caisses de stock (racks, rangées vides) : pas de pochoir. Ne pas remettre de texte dans le
mesh : il serait le même sur toutes les caisses (l'ancien « S1-0332 » se lisait « série 1 » même sur les FILM).

**Place du pochoir (#456)** : `CrateStencil` (`AT`, `SIZE`, `INK_HEIGHT`) est la seule source des cotes, et deux contrôles
la relient au mesh. `crate_model.py` relit ces lignes (garder la forme `CrateStencil.AT = { a, b, c }`) et refuse
d'exporter si une pièce passe devant les lettres (bande, cornière, moraillon, cadre) ou si le pochoir flotte à plus de
`MAX_GAP` devant les planches. `verify_place.luau` compare les mêmes cotes aux boîtes des pièces de `Crate.rbxm`
(face avant de `LidPlanks`, bord droit de `LidStripe`) ; en Lune, le pivot se lit dans `WorldPivotData` (pas de
`GetPivot`). Caisse redessinée : régénérer, puis déplacer le pochoir dans `CrateStencil` si le générateur s'arrête.

1. `blender -b --factory-startup --python tools/shop/crate_model.py -- <sortie.fbx> [aperçu.png]`
2. `bash tools/publish_asset.sh <sortie.fbx> Model Crate` (id du Model).
3. Studio (réservé, connecté au worktree, mode Edit) : `insert_asset(<id>, parentPath = game.ReplicatedStorage.Props)`.
   L'insertion ajoute un `PackageLink` : le supprimer. Le pivot du Model arrive déjà au centre du dessous.
4. `lune run tools/rbxm/receive.luau Props`, puis `studio_export.luau` avec `ONLY = "Props"` ; détruire ensuite la caisse
   insérée à la main (Rojo la recrée depuis `assets/rbx/Props/Crate.rbxm`, sinon elle est en double).

Retirer une pièce sans changer le reste de la géométrie (#434) ne demande ni publication ni Studio. Lune ne relit pas le
`.rbxm` binaire (`MeshPart.Tags should be SharedString`), mais il relit la place XML de `rojo build` : y prendre
`ReplicatedStorage.Props.Crate`, détruire la pièce, puis `roblox.serializeModel({ crate })` vers `Crate.rbxm`. Comparer
ensuite toutes les propriétés des pièces restantes avant et après (même `MeshContent`, tailles, pivots), Studio
déconnecté de ce serveur Rojo.

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

## AWP : modèle procédural (#403)

Source : `assets/awp/` (remplace `assets/sniper/Sniper.blend`, fusil générique à crosse en bois, qui ne sert plus qu'aux
anciens outils de `tools/skins/make_skins.py`). Skins de l'AWP : « Skins dessinés de l'AWP » ci-dessous. Tout se refait
sans interface :

```bash
blender -b --factory-startup --python assets/awp/build_awp.py -- <abs>/assets/awp/AWP.blend   # formes, UV, matériaux
blender -b assets/awp/AWP.blend --factory-startup --python tools/skins/bake_maps.py -- <cuisson>
uv run assets/awp/make_textures.py <cuisson> assets/awp/textures                             # cartes PBR d'origine
blender -b --factory-startup --python assets/awp/build_awp.py -- <abs>/assets/awp/AWP.blend   # rebranche les cartes
blender -b assets/awp/AWP.blend --factory-startup --python assets/awp/render_board.py -- <dossier> new
uv run assets/awp/compose_board.py <dossier> references/awp_reel/L115A3_sniper_rifle.jpg references/skins/AWP/Default/01-repos.png <planche.jpg>
```

- **Repère hérité de l'ancien modèle** : bouche vers -X, haut +Z, droite du tireur +Y, origine = `Joint` du viewmodel,
  1 unité = 1 stud en 1P. L'œilleton (X 1,42, axe à Z 0,5) et la bouche (X -5,45, Z 0) sont à la place de ceux de
  l'ancien : ce sont les deux points que suivent les pistes (`build_anims.py`, `EYE_REST`, `MUZZLE_REST`), le cadrage
  ne bouge pas. Pivots gardés : culasse (0,95 ; 0 ; 0), chargeur (0,29 ; 0 ; -0,45), détente (1,06 ; 0 ; -0,36).
- **Proportions** relevées sur une photo de profil (L115A3, Wikimedia Commons, `references/awp_reel/`, non versionné) :
  `X(px)`, `Z(py)` de `build_awp.py`. La planche superpose le modèle à la photo (vue 2) : un écart s'y voit tout de suite.
  Lunette montée 0,10 plus haut que sur la photo pour garder l'œilleton à Z 0,5. La lunette suit l'AWP de CS2 plutôt
  que la photo : tourelles basses (celle de la photo, 0,42 au-dessus de l'axe, rendait mal au repos) et oculaire
  resserré avant son évasement final. Toucher la géométrie déplace la boîte de l'arme qui normalise la cuisson : toutes
  les cartes changent un peu, les republier toutes.
- **Tube fermé derrière les verres** : `ScopeLens` est en Glass à 60 % de transparence ; un tube ouvert laisse voir le
  décor à travers la lunette. Le profil de la lunette se ferme par un fond noir juste derrière chaque verre.
- **Dépliage** : îlots en unités monde (faces planes à plat, pourtours en bandes, pièces de révolution en cylindre), coupés
  en tronçons de 1,5, rangés par un empaquetage en étagères déterministe (le packer de Blender ne l'est pas). Une seule
  densité pour les quatre matériaux, celle du plus chargé (le châssis) : 226 px/unité en 1024.
- **Booléens** (fenêtre d'éjection, évents du frein) : seulement sur une coque isolée, puis fusionner. Sur un maillage
  qui contient plusieurs coques qui se chevauchent (canon + frein, boîtier + rail), le booléen EXACT jette des pièces.
- `ob.dimensions` reste périmé après un `bmesh.to_mesh` tant que `view_layer.update()` n'a pas tourné.
- **Couleurs** (`make_textures.py`) : vert olive tirant sur le kaki, lunette peinte du même olive (comme l'AWP Default
  de CS2), bagues et tourelles noires moletées, culasse en acier nu. Le rendu Cycles de `render_views.py` délave l'olive
  sous sa lumière principale : juger en jeu.
- **Publication** : `export_mesh_fbx.py --no-turn` (repère des meshes de l'AWP), `publish_asset.sh … Model`, cartes par
  `tools/skins/publish_skin.py` sur un dossier `<x>/AWP/<PREFIXE>_<Carte>.png` (ids dans `assets/awp/texture_ids.json`).
- **Poser le modèle sur le viewmodel** (Studio, mode Edit, MCP) : `insert_asset` dans `ServerStorage`, puis pour chaque
  pièce `ApplyMesh`, `Size` du mesh inséré et `CFrame` = `Joint.Position + (cx, cz, -cy)` (centre de la boîte Blender)
  avec la rotation de l'ancienne pièce. Joints : désactiver les Motor6D de l'arme, garder leur repère de pivot monde
  `J = Part0.CFrame * C0`, puis `C0 = Part0⁻¹ J`, `C1 = Part1⁻¹ J` : les pistes publiées s'appliquent telles quelles.
  `Barrel.ShootPart` garde sa position monde ; `Handle.EjectPort` va sur la nouvelle fenêtre (X 0,22, côté +Y).
- **3P** : `ThirdPerson.Grip` est la Handle (centre du boîtier) dans le repère de la main : un déplacement du centre
  de la Handle se compense par `Grip * CFrame.new(0,7 · L(c_neuf - c_ancien))`, avec L = (-X, Z, Y) du repère Blender.
- **Rig d'animation** : `assets/awp/update_anim_rig.py` remplace les pièces de l'arme de `AWP_Viewmodel_Anims.blend`
  (origine au centre de chaque pièce, comme une MeshPart), sinon `frames_<Nom>.json` place les nouvelles pièces aux
  centres des anciennes.

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

Sources versionnées : `assets/skins/<skin>/<Viewmodel>/<PREFIXE>_<Carte>.png` (LFS, un dossier par arme) et
`assets/skins/<skin>/ids.json` (ids des images publiées). Pas de skin par défaut : ils viendront des caisses, l'admin a
tout le catalogue.

### Skins dessinés de l'AWP (#417)

Un skin AWP est **dessiné pour l'AWP seule**, pièce par pièce (pas un motif réappliquable sur une autre arme) : un script
par skin dans `assets/awp/skins/` (`balise`, `trempe`, `ciselure`, `pan`, `orage`, `circuit`, `maquis`, `mue`, et
`remorqueur` et `logogramme` de la série FILM, #433 et #436, les communs `epure`, `tartan`, `banche`, et ceux de la
série 2, `parquet`, `cannage`, `tole`, #482, ses rares `capiton`, `vitrail`, `laque`, #487, et l'exceptionnel
illustré `velours`, #492), avec
une fonction `paint(maps, cv)`. Il part des cartes d'origine de `make_textures.py` (granité, moletage, vis, crasse) et
les repeint. Outils communs (`common.py`) :

- **Toile de profil** (`Canvas`) : on dessine avec PIL en coordonnées de la photo de profil (`px`, `py` de
  `build_awp.py`), une couche par encre (masque 0 à 1), puis `cv.sample(couche, m)` la lit sur chaque texel par sa
  position (x, z). Une paire de toiles (flanc gauche, flanc droit) : `cv.text` retourne le texte sur le flanc droit pour
  qu'il reste lisible des deux côtés. `cv.sample_at` lit la toile en des points donnés (couleur d'une écaille en son centre).
- **Contours de l'arme** : `outline("STOCK")` relit un contour de `build_awp.py` sans bpy ; `band` trace un filet
  intérieur qui suit le contour et le tour des trous (pontet, trou de pouce), `zone` donne la distance au bord pour
  limiter un motif à l'intérieur ; `halftone` pose une trame de points.
- **Encre** : `paint(m, opacité, couleur, rugosité, métal)` ; `chip` écaille la peinture sur les arêtes.

```bash
blender -b assets/awp/AWP.blend --factory-startup --python tools/skins/bake_maps.py -- <cuisson>   # une fois
uv run assets/awp/skins/paint.py <cuisson> <skin> <sortie> [--canvas <apercu.png>]
blender -b assets/awp/AWP.blend --factory-startup --python tools/skins/render_views.py -- awp <sortie> <sortie>
uv run --with pillow tools/skins/compose_board.py <planche.jpg> 2 "Profil gauche|<sortie>_profil.png" …
```

Puis copier les PNG dans `assets/skins/<skin>/AWP/`, publier et cataloguer (étapes 4 et 5 ci-dessous). Les polices des
marquages sont celles de Windows (`C:/Windows/Fonts`, Bahnschrift, Impact) : génération sur le poste, pas en CI.

- **La vue « profil » de `render_views.py` est le flanc gauche, celui qu'on voit en 1P** (caméra du côté -Y).
- **Comparer à la référence CS avant de montrer** : une première version de TREMPE (rose et violet) ressemblait au Fade,
  une d'ORAGE (violet à éclairs blancs) à Lightning Strike ; la palette a été changée pour rester original.
- **Raccord au joint garde-main / crosse** (`JOINT`, px 2430, retour utilisateur sur CIRCUIT, MUE et ORAGE) : le châssis
  est en deux pièces, et un motif qui atteint le joint doit le **traverser à la même hauteur** ou s'arrêter nettement
  avant, jamais s'arrêter dessus ni repartir décalé de l'autre côté. Défauts constatés : pistes terminées par une
  pastille au bord du garde-main et reprises plus bas sur la crosse, losanges rognés par une marge de 6 px de chaque
  côté du joint (zones calculées pièce par pièce), éclair qui finit dans le joint. Remèdes : tracer d'un seul trait à
  travers le joint, limiter un motif avec `zone(cv, chassis(), …)` (garde-main et crosse réunis), caler une chaîne
  pour qu'une jointure de motifs tombe sur `JOINT`, faire passer un éclair par un point imposé à mi-hauteur
  (`strike(…, via=…)`). Contrôler un zoom du joint sur les deux profils avant de montrer.
- **Rendus de planche** : passer à `paint.py` et `render_views.py` des chemins en barres obliques (`cygpath -m`). Avec
  des barres inverses, `"$W\$S"` donne le texte `$S` en bash, et tous les skins s'écrivent dans le même dossier : la
  planche montre alors d'anciens rendus.
- **Un filet de contour commence sur le congé** : les 7 premiers px photo (~0,02 unité) d'un filet `band(…, 0, d1)`
  tombent sur l'arrondi du bord ; un contour de BD lisible demande `d1` ≈ 22.
- **Un non-métal sombre prend un voile gris** (carbone de CIRCUIT, noir mat) : le poser en métal 1 avec une couleur sombre,
  comme une candy.
- **Écailles** : un Voronoï 3D donne des galets (crocodile) ; des écailles de serpent sont un quinconce de losanges
  relevés vers l'arrière, une couleur par écaille lue au centre (MUE).
- **Rendu en jeu plus sombre et plus chaud** que la planche Cycles : sous le crépuscule de la map, l'orange de BALISE vire
  au rouge et le blanc au gris lavande.
- **Une base métallique sombre tombe au noir en jeu** (salle du playtest) : à 0,10-0,16 de couleur de reflet, écailles
  de MUE, carbone de CIRCUIT et émeraude d'ORAGE ne se voyaient plus. Viser au moins ~0,2 sur le canal dominant (MUE
  0,32, ORAGE 0,38, CISELURE 0,28) et une rugosité de 0,2 à 0,4 ; la planche Cycles paraît alors trop claire, c'est voulu.
- **Un non-métal sombre tombe aussi au noir en jeu** (TARTAN) : un tissu à 0,25 sur le canal dominant, juste sur la planche
  Cycles, était presque noir en 1P ; il faut ~0,4 (vert 0,42, bleu 0,42, noir des séparations 0,07). À l'inverse, un
  béton à 0,56 paraît presque blanc dans Cycles mais gris moyen en jeu (BANCHE : 0,36 donnait un gris foncé). Pour un
  aplat clair ou sombre non métallique, juger en jeu, pas sur la planche.
- **Petits pores sombres = saleté en 1P** : un semis de pores à 0,7 de teinte (bullage du béton) se lisait comme des
  points noirs ; à 0,88 il reste une matière.
- **Communs (ÉPURE, TARTAN, BANCHE)** : un skin commun reste sobre et graphique (plan technique à cotes, tissu écossais
  au sett inventé, béton de coffrage à trous de banche en grille), tout en motifs réguliers calés sur `JOINT` (pas de
  quadrillage, carreau ou panneau rogné au joint). Ce qui doit se voir en 1P va sur l'avant de la crosse (cote, plaque
  de laiton, pochoir « C35/45 ») ; le reste (cartouche) sur l'arrière, pour l'écran d'équipement.
- **Communs de la série 2 (PARQUET, CANNAGE, TÔLE LARMÉE, #482)** : motif calculé texel par texel en coordonnées de
  profil (`mt_px`, `mt_py` ; sur les dessus et dessous, `y` à la place de `z`), calé sur `JOINT` et `TOP` (363), donc
  continu d'une pièce à l'autre. Bâtons rompus : en repère tourné de 45°, des lames 1 x N posées horizontales là où
  `(i - j) mod 2N < N` et verticales ailleurs pavent le plan, et les rangées de zigzag courent le long de l'arme.
  **Cannage** : un pas serré (34 px) faisait un panneau perforé, des trous noirs faisaient des pois ; il faut des
  mailles larges (56 px), un fond de trou brun sombre et surtout les **brins diagonaux en X sur chaque nœud**, qui
  coupent les coins des trous. **Tôle larmée** : à 30 px de pas, les larmes disparaissaient de profil (36 px) ; un rivet
  bombé se fond dans l'aluminium sans un liseré d'ombre à son pied.
- **Rares de la série 2 (CAPITON, VITRAIL, LAQUE, #487)** : matières d'intérieur plus précieuses que les communs
  (cuir capitonné, vitrail serti de plomb, laque à l'or). Le cuir bordeaux et les verres posés en **non-métal** prenaient
  le reflet du ciel : cuir rose, verres blancs de trois quarts. Le cuir posé en métal (« candy », rugosité 0,55)
  garde sa teinte. Les verres en métal, justes sur la planche, paraissaient éteints en jeu (ils ne renvoient que le ciel
  sombre du crépuscule) : verres non métalliques et couleur relevée (luminance moyenne 0,18 → 0,23). Mats (0,42), ils
  faisaient peinture : le verre se lit par des reflets nets (rugosité 0,10), un relief martelé qui les brise d'un verre
  à l'autre, et une **lueur** (carte facultative `<PREFIXE>_Emissive.png`, voir ci-dessous).
- **Lueur d'un skin (carte Emissive, #487)** : un skin peut poser `m.emissive` (0 à 1 par texel) ; `Maps.save` écrit
  alors `<PREFIXE>_Emissive.png`, `publish_skin.py` la publie et `make_rbx.py` la pose en `EmissiveMaskContent` (Rojo
  7.7 la synchronise, vérifié dans Studio). La lumière émise prend la couleur de `ColorMapContent`. `WeaponSkins.mapUris`
  la précharge avec les autres cartes. Rester discret (VITRAIL : 0,3 au pied des plombs, 0,65 au centre d'un verre) :
  plus fort, le verre fait néon.
- **Une carte publiée peut ne jamais s'afficher** : approuvée, servie par Asset Delivery et `Success` pour `PreloadAsync`,
  elle laisse pourtant toute la pièce grise (VITRAIL, #487 : la normale du châssis, et une couleur republiée identique
  au bit près à la précédente). Attendre n'y change rien. Isoler la carte fautive sur une AWP posée en mode Edit
  (clone de `ReplicatedStorage.ViewModels.AWP`, une `SurfaceAppearance` neuve par essai, `Content.fromUri`, puis
  `screen_capture` à caméra fixe), puis retirer sa seule entrée de `ids.json` et la republier ; une carte identique à
  une version qui s'affiche reprend l'ancien id. Changer les cartes d'une arme déjà en main pendant une partie ne
  recharge rien : tester en mode Edit ou relancer la partie.
- **Rojo ne remet pas à zéro une propriété retirée d'un `.model.json`** : un essai qui a posé `EmissiveMaskContent` ou
  `EmissiveStrength` reste dans Studio après restauration du fichier (lunette et canon de VITRAIL lumineux). Remettre
  la valeur à la main dans Studio ; le fichier versionné, lui, est propre. Une rosace en anneaux concentriques coupés de rayons faisait cible de fléchettes : des lobes
  circulaires qui se chevauchent (rosace gothique) se lisent comme une fleur. Des boutons de capiton lustrés brillaient
  comme des perles : boutons mats. Deux skins d'une même caisse ne doivent pas partager leur couleur dominante
  (CAPITON foncé en lie-de-vin face au rouge de LAQUE) : comparer les skins de la caisse côte à côte.
- **Skins illustrés (exceptionnels, légendaires ; VELOURS, #492)** : pour un vrai dessin (un sujet, une scène, comme
  Hyper Beast ou Neo-Noir), ni le code ni l'IA de Studio ne suffisent. Des formes en Bézier écrites à la main donnent
  du clip-art ; `generate_texture` de Studio (mode Quality) peint un vrai oiseau mais flou, sans contrôle de la
  composition, coupé au joint, et sur un maillage qu'il re-déplie lui-même. Ce qui marche (méthode retenue par
  l'utilisateur pour ces skins) : `gabarit.py` écrit la silhouette exacte du châssis (masque, version annotée avec la
  zone vue en 1P et la marge du cadre) ; on lui livre gabarit et brief (style, sujet entier dans la zone 1P, rien de
  coupé par les trous, pas de texte ni d'arme dessinée ; modèle : `art/velours.brief.md`), il fait peindre
  l'illustration par un modèle d'image et la rapporte ; elle va dans `assets/awp/skins/art/<skin>.png` et `illustration.py` la recale
  (échelle et décalage par axe qui maximisent le recouvrement des silhouettes : 0,94 pour VELOURS, l'écart tient sous
  le cadre sombre de 9 px), prolonge ses couleurs au-delà de son bord puis la lit par texel. Matière tirée de la
  luminance : sombres en métal teinté (voile gris sinon), clairs en non-métal, lueur sur les plus clairs. Fidèle en
  jeu (couleurs saturées gardées) ; la planche Cycles, elle, délave les tons clairs.
- **Republier un skin corrigé** (si une seule carte change, retirer seulement son entrée, voir plus haut) : `publish_skin.py` saute les cartes déjà dans `ids.json` (reprise). Supprimer
  `ids.json` avant de republier des cartes modifiées, sinon le jeu garde les anciennes images.
- **Essayer tous les skins en jeu sans relancer de partie** : en playtest, AWP en main, cloner depuis le contexte Client
  les `SurfaceAppearance` de `ReplicatedStorage.Skins.AWP.<skin>` sur les pièces de `workspace.CurrentCamera.AWP` (ce
  que fait `WeaponSkins.apply`), puis `screen_capture`. Un skin jamais chargé reste gris 1 à 3 s : recapturer.

### Skins dessinés de la M9 (#420)

Même principe que pour l'AWP : un skin est **dessiné pour la M9 seule**, un script par skin dans `assets/m9/skins/`
(`emaille` pour ÉMAIL, `patrouille`, `artdeco`, `hote` et `sphinx` de la série FILM, #433 et #436, et les communs
`leurre`, `chantier`, `topo` et `ceramique`, #476, le rare `guilloche`, et ceux de la série 2, les communs `piedpoule`
et `tomette` et les rares `azulejo` et `nacre`, #495), avec une fonction `paint(kn)`. La M9 n'a pas de source Blender : on
part de ses cartes d'origine et de sa cuisson (`fetch_viewmodel.py` puis `bake_maps.py --glb`, étape 1 de « Fabriquer
un skin » ci-dessous). Outils communs (`common.py`) :

- **`Knife`** : les cartes d'origine en cours de peinture, les zones de `make_skins.Knife` (lame, biseau, garde, manche,
  pommeau) et une **toile de profil dans le repère du couteau** (t le long de l'axe, pointe à gauche ; h vers le dos, le
  tranchant en bas), 640 px par unité. `sil` est la lame vue de profil (trou et dents compris), `dist` la distance à son
  bord en unités : un filet qui suit le contour se trace par `(dist > d0) & (dist < d1)`, et passe tout seul autour du
  trou et des dents. `edges_at(t)` donne la hauteur du tranchant et du dos à une abscisse.
- **Dessin** : `line`, `poly`, `disc`, `text` (retourné sur la face droite pour rester lisible) en coordonnées (t, h),
  ou `put` d'un masque calculé sur `grid()` ; `sample` lit une couche sur les texels. **Encre** : `paint`, `tint_grip`
  (teinte du manche en gardant son quadrillage), `edge` (fil repoli).

```bash
uv run assets/m9/skins/paint.py <cuisson> <cartes_origine> <skin> assets/skins/<id>/M9Bayonet [--flat <profil.png>]
blender -b --factory-startup --python tools/skins/render_views.py -- m9 <dossier> <sortie> --glb <m9.glb> --samples 32
```

`--flat` écrit la couleur peinte vue de profil en quelques secondes : régler le dessin dessus, ne rendre la planche
qu'ensuite. Puis publier et cataloguer (étapes 4 et 5 de « Fabriquer un skin »).

- **Repères mesurés** : tranchant à h ≈ -0,21 et dos à ≈ 0,22 au talon, fond des dents ≈ 0,15, gouttière t -1,03 à
  -0,16 et h 0,02 à 0,13, trou vers t -1,25, ricasso t -0,15 à 0,25, pointe à t ≈ -2,1.
- **Un motif ordonné, pas un tracé au hasard** : SIDÉRITE (figures de Widmanstätten, lamelles croisées tirées au hasard)
  et FÊLURE (fissures kintsugi en marche aléatoire) ont été rejetés (« des griffures dans tous les sens »). ÉMAIL
  (écailles régulières cloisonnées) a plu tout de suite. Une bande ivoire large le long du tranchant d'ART DÉCO a été
  refusée aussi : préférer des lignes fines qui fuient vers la pointe.
- **Éviter les symboles connotés** : un éventail de rayons alternés depuis un demi-soleil (ART DÉCO, première version)
  rappelait le drapeau du Soleil levant ; remplacé par des arcs concentriques. Un point d'impact central sur une lame
  cassée rappelait IMPACT et faisait araignée.
- **Ne pas nommer un module de skin comme un module de la bibliothèque standard** : `email.py` masquait `email` et
  cassait `uv` ; d'où `emaille.py`.
- **Crête d'écaille fine** : à anneaux égaux, l'anneau extérieur (le plus visible) dominait et le champ virait au blanc ;
  bords d'anneaux à 0,32 / 0,55 / 0,85 / 1 du rayon.
- **Émail trop lisse** (rugosité 0,1) : reflet blanc du ciel sur toute la pointe dans la vue rapprochée ; 0,2 suffit.
- **Fil d'argent sur ivoire** : invisible en couleur (même clarté) ; découper l'ivoire par des fentes noires.
- **`--flat` ne montre pas tout le bas de la lame** : sur HÔTE, les côtes vers le tranchant manquaient dans la vue à plat
  alors que les cartes les portaient (même couleur que celles du haut, vérifié texel par texel). Juger un motif qui
  descend vers le tranchant sur un rendu `render_views.py`.
- **Arête de la gouttière à h ≈ 0,02** : le bord bas de la gouttière est une arête du mesh, visible comme un trait sombre ;
  un motif centré dessus (colonne de HÔTE) paraît coupé en deux. Placer un motif linéaire au-dessus ou en dessous.
- **Communs sobres (#476)** : un ou deux tons et un motif régulier (bandes dazzle, chevrons et pochoir, courbes de niveau,
  bicolore), pour que les rares et au-delà restent plus riches. Ils sont rangés dans M9 · SÉRIE 1 (le test du shop
  exige qu'un skin soit dans une caisse), comme les communs de l'AWP.
- **Rien ne tient le long du dos de la M9** : entre le haut de la gouttière (0,13) et le creux des dents (0,15) il reste
  0,015 unité ; une bande du dos ne se voit que sur les dents. Le grand biseau (`grind`) ne fait qu'un liseré de
  profil. Un bicolore se partage en hauteur (CÉRAMIQUE : le tiers côté tranchant, sur une ligne calée entre le tranchant
  et le dos lissé par-dessus les dents, `maximum_filter1d`).
- **Projeter des texels sur la toile** donne un semis clairsemé (texels ~3 fois moins denses que la toile) : un
  `binary_closing` ne comble pas un masque fin comme `grind`. Prendre plutôt une hauteur par colonne, puis lisser.
- **Courbes de niveau** (TOPO) : à largeur constante, écart au niveau divisé par la pente. Des sommets ronds font une
  cible ; des courbes allongées brunes sur fond sable font du bois : sommets en ellipses orientées reliés par un col, papier
  vert pâle et quadrillage bleu marqué.
- **Texte de la M9 à l'envers en 1P** : le couteau est tenu tranchant en haut, un texte posé droit sur la toile (dos en
  haut) se lit tête en bas (premières versions de PATROUILLE et de CHANTIER, corrigées en #478 et #476). `kn.text(...,
  angle=180)`, et la ligne qui doit paraître au-dessus se place côté tranchant (h plus bas). Retourner une pile de lignes
  la fait monter vers le dos : au talon, rien d'écrit au-dessus de h ≈ 0,10, les dents mordent le texte. Une vue
  `--flat` tournée de 180° (PIL `rotate(180)`) montre le sens de lecture en 1P ; contrôler ensuite dans le jeu.
- **Guilloché (GUILLOCHÉ)** : sillons espacés d'au moins ~6 texels (0,028 unité, la texture fait ~210 texels par
  unité sur la lame) et tracés en profil cosinus, pas en traits fins : plus serrés, ils crénellent. Émail translucide
  en métal (« candy ») assombri au fond du sillon. Le médaillon du talon en argent clair et brillant brûlait au blanc
  et sa rosace disparaissait : argent satiné, sillons sombres. Un motif du talon s'arrête après t -0,12 : l'arête de
  fin de gouttière (t -0,16) y fait une encoche. Émail grenat préféré au bleu nuit, trop proche d'ÉMAIL dans la caisse.
- **Rendus `render_views.py` brûlés au blanc** (vue `lame`, même PATROUILLE : lame claire face à la lumière principale) :
  `--exposure -1`.
- **Série 2 de la M9 (#495, matières d'intérieur comme la série 2 de l'AWP)** : PIED-DE-POULE et TOMETTE (communs),
  AZULEJO et NACRE (rares). Motifs calculés sur `kn.grid()` puis `kn.put`, valeurs par cellule (nuance d'une tomette,
  reflet d'une plaquette) lues par `kn.sample_array(…, order=0)`. Pièges vus en jeu :
  - **Le fil repoli couvre ~0,04 unité au-dessus du tranchant vu de profil** : une frise posée sur le bas de la lame
    disparaît sous l'acier de `kn.edge`. La commencer au-dessus (`FIL` d'`azulejo.py`). Le biseau, incliné, tasse aussi
    la frise en hauteur : une chaîne d'anneaux n'y laissait que des traits verticaux, des losanges pleins tiennent.
  - **Terre cuite** : (0,55 ; 0,22 ; 0,13), saumon sur la planche Cycles, tournait au rouge sang en jeu, et des
    hexagones de 0,062 de rayon faisaient peau de serpent. Ton plus clair et orangé (0,72 ; 0,34 ; 0,19), rayon 0,078.
  - **Émail blanc brillant** (rugosité 0,16) : il renvoie le ciel du crépuscule et vire au gris bleuté en 1P ; 0,3 le
    garde blanc.
  - **Nacre** : des stries droites et contrastées faisaient des rayures de berlingot. Stries ondulées et discrètes, et
    l'irisation portée surtout par une teinte qui glisse le long de la lame et un reflet propre à chaque plaquette.

### Série FILM (#433)

Une caisse par arme sur le thème du cinéma, ouverte par un **hommage** au film de science-fiction de 1979 : REMORQUEUR
(AWP, le vaisseau industriel de Ron Cobb : coque crème en plaques rivetées, pictogrammes à coins arrondis, écran vert) et
HÔTE (M9, la biomécanique de Giger : colonne vertébrale couleur os sur laque noir bleuté). Planche de références : à
refaire au besoin depuis Typeset in the Future (« Alien ») et Monster Legacy (galerie Alien 1979), non versionnée.

Deuxième vague (#436), choisie dans le top de films de l'utilisateur : LOGOGRAMME (AWP, *Arrival* : roche graphite
striée de fibres verticales comme la paroi du vaisseau, trois anneaux d'encre inventés, chargeur orange combinaison) et
SPHINX (M9, *Le Silence des agneaux* par son papillon : aile antérieure brun-noir sur la lame, aile postérieure ocre à
bandes noires le long du tranchant, thorax et sa tache en crâne au talon, abdomen annelé sur le manche). Références :
concept art du vaisseau (blog de Meinert Hansen), vfxblog (« The language of Arrival »), Acherontia atropos du Muséum de
Toulouse sur Wikimedia Commons. Pistes proposées et écartées : AQABA (*Lawrence d'Arabie*, poignard d'or ciselé), reportée ;
le chiffre du Zodiac (vrai tueur), les drames de guerre et les broderies osages (artisanat vivant), refusés d'office.

- **Hommage, pas de reprise** (décision utilisateur) : les caisses sont payantes et Roblox retire les contenus qui reprennent
  une licence. Ni nom du film, ni logo de la compagnie, ni pictogramme de Cobb ou tête de la créature recopiés : on
  reprend la grammaire (carré à coins arrondis, côtes répétées), avec des symboles et des noms dessinés pour le jeu.
- **Un autre film ne s'ajoute qu'après une recherche de DA** (planche de références validée) : l'utilisateur ne veut pas
  de films choisis à la hâte, dont la DA ne lui plairait pas.
- **Caisses FILM retirées (17/11/2026)** : avec la composition 4 / 3 / 2 / 1 et un skin par caisse, les quatre skins
  hommage ne remplissent pas une caisse par arme ; ils attendent dans `ShopCatalog.RESERVE` qu'il y en ait assez.
  Historique : les skins hommage étaient complétés par des skins de la série 1
  pour atteindre 6. Un skin repris garde sa rareté d'origine (`rarityOf` lit la première caisse qui le contient ; le test
  du shop l'exige). Chaque nouvel hommage prend la place d'un skin repris : LOGOGRAMME celle de MAQUIS, SPHINX celle de
  RELEVÉ (#436).
- **Logogramme qui se lit comme une lettre** : un renflement en bas de l'anneau, vrilles pendantes, faisait un « Q ».
  Les renflements se placent de côté (`RINGS` de `logogramme.py`).
- **Encre noire sur roche mate** : à rugosité 0,5 l'encre prenait le reflet du ciel et virait au blanc de trois quarts ;
  encre mate (0,95). Roche non métallique à 0,2 : presque noire en 1P dans le jeu (anneaux invisibles) ; à 0,3 elle
  paraît gris clair sur la planche mais juste en jeu. Un motif à voir en 1P va sur l'avant de la crosse (px ~2590) :
  le garde-main et l'arrière de la crosse sont hors champ.
- **Brun sombre de la M9 (SPHINX)** : posé en non-métal, l'aile et le thorax prenaient un voile gris d'acier terne ;
  en métal (« candy »), rugosité ~0,5 : à 0,45 le reflet de l'HDRI les faisait virer au cuivre.
- **Pommeau de la M9 trop petit pour un motif** : il ne fait que 0,095 unité le long de l'axe (t 1,5 à 1,595). Un motif
  figuratif (crâne de SPHINX) va sur le talon de lame (t -0,16 à 0,3), visible en 1P.
- **Crâne figuratif** : un crâne complet (nez, dents) faisait drapeau pirate ; la tache du papillon (calotte, deux
  orbites, bords flous) suffit.
- **Texte d'écran aligné à gauche sur les deux flancs** : `Canvas.text(anchor="lm")` aligne le flanc droit à droite du
  point donné, hors de l'écran. En chasse fixe (Consolas), compléter les lignes à la même longueur et les centrer.
- **Écran peint** : une dalle brillante (rugosité 0,18) reflétait le ciel et noyait le texte de trois quarts ; 0,4 et
  relief du granité retiré sous le cadre.

### Fabriquer un skin (motifs calculés : COUCHANT, RELEVÉ, RECUIT)

Tout est généré par script : motifs calculés sur la position 3D de chaque texel (continus d'une pièce à l'autre, quel
que soit le découpage UV) ou projetés depuis la vue de profil (livrée, texte), détail des cartes d'origine gardé.

1. **Cartes utilitaires** (une fois par arme, hors du dépôt) : position, normale, occlusion, arêtes et objet de chaque
   texel, à la résolution des textures. La M9 vient du jeu (`fetch_viewmodel.py`, section « Aperçus three.js »).
   ```bash
   blender -b --factory-startup --python tools/skins/bake_maps.py -- <sortie>/m9 --glb <m9.glb>
   ```
2. **Cartes PBR** : `uv run --with numpy --with pillow --with scipy tools/skins/make_skins.py <bake> <m9_orig> <sortie>
   [skin…]` (une fonction par skin et par arme dans le script : couchant, releve, recuit ; les fonctions AWP visaient
   l'ancien modèle `assets/sniper`, leurs skins AWP ont été retirés en #417 ; impact, strate et sillage, retirés en
   #420, sont remplacés par les skins dessinés de la M9 ci-dessus).
3. **Planche** : `tools/skins/render_views.py` (Cycles, HDRI de Blender, une vue par PNG, ~12 s par vue à 32
   échantillons) puis `tools/skins/compose_board.py`. Se comparer aux références `references/skins/` avant de montrer.
4. **Publier** : `uv run tools/skins/publish_skin.py assets/skins/<skin> <skin>` (Decals, puis id de l'image par Asset
   Delivery, ~5 s par carte, reprise possible), puis `uv run tools/skins/make_rbx.py assets/skins/<skin>`.
5. **Catalogue** : une ligne par arme dans `InventoryRules.ITEMS` (`appearance` = nom du fichier `.model.json`). Le test
   du catalogue vérifie que le fichier existe. Puis ranger le skin dans la caisse de son arme, à sa rareté
   (`ShopCatalog.CRATES`, `contents`) ou dans la réserve (`ShopCatalog.RESERVE`) : le test du shop exige que tout skin
   soit dans l'une ou l'autre, une seule fois, et qu'une caisse en vente ait exactement 4 communs, 3 rares, 2
   exceptionnels et 1 légendaire (choix de l'utilisateur, 17/11/2026). Pas assez de skins pour une caisse : ils restent
   en réserve, la caisse n'est pas créée.
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
- **Densité de texture** : voir « Redéplier les UV d'un matériau » ci-dessous. Un réglage de `make_skins.py` exprimé en
  pixels (flou, épaisseur de trait, force du relief) change de taille dans le monde avec la densité : `PX_SCALE` le
  ramène à celle pour laquelle il a été choisi.
- **Toile de profil (livrées)** : `sample_side` la lit en bilinéaire, à ~400 px par unité (deux fois la crosse) ; au plus
  proche et à 200 px par unité, texte et filets se crénelaient.
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
- Suites ouvertes : caisses (#332).

### Redéplier les UV d'un matériau (#335)

La crosse de l'AWP (`WOOD` : `Stock`, `Handguard`) n'occupait que 16 % de sa carte (longues bandes en diagonale, 111 px
par unité contre 250 à 300 pour les métaux) : les livrées y étaient floues. Redépliée : 55 %, 205 px par unité.

1. `blender -b assets/sniper/Sniper.blend --factory-startup --python tools/skins/repack_uv.py -- <sortie.blend>
   <corresp.npz> Stock,Handguard` : garde l'aplatissement d'origine, coupe en tronçons les îlots trop longs (le long de
   leur grand axe, coutures marquées), puis range tout à plat avec le packer de Blender. Chaque tronçon ne subit qu'une
   similitude. Le packer n'est pas déterministe d'un lancement à l'autre : garder ensemble le `.blend` et le `.npz` d'un
   même lancement. Le `.blend` réenregistré perd les données orphelines (Blender les retire à chaque enregistrement).
2. `uv run --with numpy --with pillow --with scipy tools/skins/remap_textures.py <corresp.npz> assets/sniper/textures
   <sortie> WOOD --check <aller-retour.png>` : transpose les cartes d'origine triangle par triangle et tourne la carte
   de normales avec son repère tangent. L'aller-retour (nouvelle carte reprojetée sur l'ancien dépliage) doit rester
   sous 1/255 : 0,25/255 en moyenne sur la crosse.
3. Recuire les cartes utilitaires (`bake_maps.py`), mettre à jour `PX_SCALE` dans `make_skins.py`, regénérer les skins
   (seules les cartes du matériau redéplié changent : les autres sortent identiques au bit près), comparer aux rendus
   d'avant (`render_views.py`, mêmes vues), puis republier : cartes d'origine, cartes des skins, mesh (`--only` de
   `export_mesh_fbx.py`), et poser mesh et cartes sur le viewmodel dans Studio avant de le réexporter.
- **Mesh d'une pièce de l'AWP** : exporter avec `--only <pièces> --no-turn`. Les meshes de l'AWP ont été publiés depuis
  un FBX brut ; avec la rotation habituelle d'`export_mesh_fbx.py`, la pièce arrive tournée de 180° (constaté : crosse à
  l'envers). Dans Studio (mode Edit, MCP) : `insert_asset` du Model dans `ServerStorage`, puis
  `vm.<Pièce>:ApplyMesh(modèle.<Pièce>)` : l'instance, ses `Motor6D`, sa taille et sa `SurfaceAppearance` sont gardés
  (taille et centre de masse identiques à 10⁻⁶ près si le repère est le bon).
- **Couper Rojo avant l'export sans clic** : ne pas utiliser `-Stop` ni `-ReleaseStudio` (Studio se reconnecte au checkout
  principal et le patch écrase les modifications faites dans Studio). Arrêter le processus `rojo` du worktree (le
  `.pid` de `worktrees/.run` est celui du `pwsh` parent : le tuer laisse `rojo` tourner), puis vérifier qu'aucune
  connexion TCP ne reste sur le port (`Get-NetTCPConnection -LocalPort <port>`), pas par une requête HTTP. Après
  l'export : relancer le script (Rojo) puis `-AcquireStudio`, qui reconnecte avec le patch de rattrapage.
- Référence : avant toute modification, regénérer les skins sur la cuisson actuelle et vérifier qu'ils sortent
  identiques aux PNG versionnés (écart 0 constaté). `make_skins.py` relit `assets/sniper/textures` pour chaque skin : ne
  pas remplacer ces cartes pendant qu'il tourne.

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
7. **Profil (vignettes, shop)** : une arme vendue au shop a une entrée dans `WeaponProfile.REFERENCES` (pièce dont les
   axes suivent l'arme, direction de la pointe et du haut dans son repère, mesurées dans Studio), exigée par le test
   `WeaponProfile` ; sans elle, vignette et aperçu peuvent montrer l'arme tournée de 180° (#429, `docs/ui.md`).
8. `rojo build` + `tools/rbxm/verify_place.luau` (signale un Tool sans entrée de config), puis le helper de playtest sur
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

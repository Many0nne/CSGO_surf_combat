# CSGO

## Overview

Projet Rojo qui synchronise une expérience Roblox depuis l'arborescence `src/`.

## Current Structure

```text
CSGO/
  rokit.toml
  CLAUDE.md
  CSGO.rbxlx
  default.project.json
  assets/
    rbx/
      ViewModels/*.rbxm
      Tools/*.rbxm
  tools/
    check.sh
    export_mesh_fbx.py
    publish_asset.sh
    rbxm/
      receive.luau
      studio_export.luau
      verify_place.luau
  feedback.md
  GAME_SYSTEM_SPEC.md
  logs.md
  README.md
  SOURCE_ENGINE_SURF.md
  sourcemap.json
  SPEC.md
  src/
    client/
      init.client.luau
      camera/
        FPSCamera.luau
      debug/
        DebugPlaytest.luau
        Noclip.luau
      input/
        InputModule.luau
      systems/
        game/
          GameStateController.luau
        movement/
          BhopSystem.luau
          CharacterDimensions.luau
          CoyoteJump.luau
          CrouchSystem.luau
          GroundDetection.luau
          HeadCollisionResolver.luau
          MovementController.luau
          PhysicsStepAir.luau
          PhysicsStepGround.luau
          SlopeSystem.luau
          StepupSystem.luau
          WallSlide.luau
        weapon/
          AnimationSoundSystem.luau
          HitscanSystem.luau
          MeleeHitDetection.luau
          ScopeSystem.luau
          ViewmodelSystem.luau
          WeaponSystem.luau
          WeaponThirdPersonView.luau
      ui/
        InfosScreen.luau
        MainMenu.luau
        RoundHUD.luau
        ScopeOverlay.luau
        SettingsMenu.luau
        Speedometer.luau
    server/
      init.server.luau
      DebugPlaytest.luau
      RoundManager.luau
      SettingsStore.luau
      SpawnManager.luau
      StatsStore.luau
      Validator.luau
    shared/
      CameraConfig.luau
      CharacterAnimator.luau
      CharacterAppearance.luau
      CharacterConfig.luau
      DebugPlaytestRules.luau
      GameConfig.luau
      MovementConfig.luau
      MovementState.luau
      NetworkProtocol.luau
      PhysicsUtils.luau
      WeaponConfig.luau
      WeaponThirdPerson.luau
  tests/
    run.luau
    lib/
      Loader.luau
      Test.luau
    specs/
      *.spec.luau
```

## Workflow d'une tâche (feature, bug…)

1. Créer le worktree et démarrer son serveur Rojo : `.\scripts\csgo-worktree.ps1 <feature|fix>/<n>-<slug>` (le thread T3
   courant est inscrit comme propriétaire pour le nettoyage). Travailler uniquement dans ce worktree.
2. Implémenter, puis `bash tools/check.sh` dans le worktree. Vérifier en jeu via le MCP Studio si le changement le demande
   (Studio connecté au port du worktree, voir ci-dessous).
3. Besoin d'un avis de l'utilisateur (gameplay, rendu, UI) : lui donner le port Rojo du worktree (`34872+N`), la procédure
   de connexion Studio ci-dessous, et le scénario à suivre (étapes, ce qu'il faut observer). Attendre son retour.
4. Fonctionnement vérifié (et validé par l'utilisateur si l'étape 3 s'appliquait) : commit, push, `gh pr create --base main`
   avec `Closes #<n>` dans la description si une issue est liée, puis fermer le thread (settle via `t3_thread_organize`).
5. Pas de merge sans ordre explicite. Le nettoyage automatique arrête Rojo une fois le thread fermé, et supprime le worktree
   et la branche locale une fois la PR mergée (à la main : `.\scripts\csgo-worktree.ps1 <branche> -Remove`).

## Worktrees (travail en parallèle)

Une branche = un worktree `worktrees/csgo-<slug>/` (slug = branche avec `/` → `-`) = un `rojo serve` sur son propre port.
Script idempotent, à relancer au début de chaque tâche (PowerShell, depuis la racine du checkout principal) :

```powershell
.\scripts\csgo-worktree.ps1 feature/x             # crée/réutilise, lance rojo serve, vérifie [OK (200)]
.\scripts\csgo-worktree.ps1 fix/y -Base feature/x # nouvelle branche depuis une autre base (défaut : main)
.\scripts\csgo-worktree.ps1 feature/x -NoUp       # sans démarrer Rojo
.\scripts\csgo-worktree.ps1 feature/x -Stop       # arrête Rojo
.\scripts\csgo-worktree.ps1 feature/x -Remove     # arrête Rojo, supprime le worktree (branche gardée)
```

- Ports par slot N : checkout principal = slot 0 = `34872` (`rojo serve` lancé à la main), worktrees `34872+N` (34873, 34874…).
- Port, pid et journal du serveur d'un worktree : `worktrees/.run/<slug>.port|.pid|.log` (hors du worktree, rien de versionné).
- Connecter Studio à un worktree (le plugin Rojo ne se connecte qu'en mode **Edit** ; en Play il renvoie
  `Http requests can only be executed by game server`) :
  1. Studio en mode Edit (arrêter le playtest s'il tourne), Disconnect dans le plugin Rojo s'il est connecté ailleurs.
  2. Plugin Rojo : saisir le port du worktree (affiché par le script), Connect.
  3. Pour revenir au checkout principal : Disconnect, port `34872`, Connect.
- Une fenêtre Studio ne suit qu'un serveur Rojo à la fois : deux tâches qui doivent tester en jeu en même temps ont besoin
  de deux fenêtres Studio (le MCP cible alors l'instance choisie, voir `list_roblox_studios`), sinon elles se relaient.
- Lancer `bash tools/check.sh`, `rojo build` et `lune run …` depuis le worktree concerné.
- Nettoyage auto (registre `worktrees/.owners.json`) : `scripts/csgo-worktree-cleanup.ps1` arrête Rojo quand les threads T3
  du worktree ne sont plus actifs (settled, archivés), et supprime le worktree quand la PR de la branche est mergée
  (ou fermée sans merge) et que tout est poussé ; la branche locale est aussi supprimée si la PR est mergée. Fermer ou
  archiver un thread ne supprime jamais rien à lui seul. Tâche planifiée (toutes les 10 min, à réinstaller sur un nouveau
  poste) : `scripts/install-cleanup-task.ps1`. À chaque passage, elle avance aussi le checkout principal sur `origin/main`
  (fast-forward, seulement s'il est sur `main` sans modification).

## Rojo Mapping

- `src/shared` -> `ReplicatedStorage/Shared`
- `src/server` -> `ServerScriptService/Server`
- `src/client` -> `StarterPlayerScripts/Client`
- `assets/rbx/ViewModels/<Nom>.rbxm` -> `ReplicatedStorage/ViewModels/<Nom>` (viewmodels FPS, aussi clonés pour l'arme 3P)
- `assets/rbx/Tools/<Nom>.rbxm` -> `StarterPack/<Nom>` (Tools des armes, attribut `ViewmodelName`)

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
   chaque viewmodel et chaque Tool et les envoie au serveur, qui écrit `assets/rbx/ViewModels/<Nom>.rbxm` et
   `assets/rbx/Tools/<Nom>.rbxm`, supprime les `.rbxm` qui n'existent plus dans la place, puis s'arrête. Si l'export
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
bash tools/publish_asset.sh <fichier> <Animation|Model> <nom>    # écrit l'assetId sur la sortie standard
bash tools/anim/publish.sh <dossier> <prefixe> <Nom1> [Nom2 ...] # plusieurs animations, affiche Nom=id
```

- Animation : `.rbxm` ou `.rbxmx` contenant une KeyframeSequence. `rbxtemp://` est refusé en playtest : publier pour tester.
- Mesh : exporter avec `blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx>`, publier
  en `Model`, puis `insert_asset(assetId)` via le MCP Studio (mode Edit). On obtient un Model de MeshParts, sans import manuel.
- Axes : dans Blender, l'avant du modèle est +Y et le haut +Z ; Roblox reçoit `(x, z, -y)` et 1 unité Blender = 1 stud.
  `axis_forward` et `bake_space_transform` n'ont aucun effet : l'importeur Roblox donne toujours `(-x, z, y)` depuis un FBX
  brut (4 combinaisons testées). `export_mesh_fbx.py` compense donc par une rotation de 180° autour de Z.

## Animations de viewmodel

Avant de créer ou modifier une animation d'arme, lire `docs/animations.md` (méthode, outils, pièges). L'essentiel :

- Partir d'une vidéo de référence fournie par l'utilisateur et ne pas itérer sur des descriptions.
- Faire valider les poses, puis le mouvement avec une vidéo côte à côte (`tools/anim/side_by_side.py`), **avant de publier**,
  même si l'utilisateur demande de finir. Des images fixes justes ne garantissent pas un mouvement juste.
- Rendre dans Studio au FOV du jeu (90°) et juger le cadrage en 16:9, pas dans Blender avec un volume à la place de l'arme.

## Description des fichiers

- `docs/animations.md`: méthode de création des animations de viewmodel (processus de validation, outils, pièges connus).
- `tools/anim/`: outils de ces animations : mesure sur vidéo, rendu et capture dans Studio, vidéo côte à côte, publication Open Cloud.
- `default.project.json`: configuration Rojo qui mappe `src/` et `assets/rbx/` (viewmodels, Tools) vers le projet Roblox.
- `assets/rbx/ViewModels/*.rbxm`, `assets/rbx/Tools/*.rbxm`: viewmodels et Tools des armes (binaires LFS, voir « Viewmodels et Tools »).
- `tools/rbxm/receive.luau`: serveur Lune local qui reçoit les `.rbxm` exportés de Studio et les écrit sous `assets/rbx/`.
- `tools/rbxm/studio_export.luau`: script à exécuter dans Studio qui sérialise viewmodels et Tools et les envoie à `receive.luau`.
- `tools/publish_asset.sh`: publie une animation ou un modèle par Open Cloud, attend la fin de l'opération et écrit l'`assetId`.
- `tools/export_mesh_fbx.py`: exporte les meshes d'un `.blend` en FBX avec l'orientation attendue dans Roblox.
- `tools/rbxm/verify_place.luau`: relit la place construite par Rojo et vérifie viewmodels, Tools, ids d'assets et noms d'armes.
- `rokit.toml`: versions des outils (Rojo, StyLua, Selene, luau-lsp, Lune) gérées par Rokit.
- `CLAUDE.md`: guide de contexte et conventions pour travailler dans ce dépôt.
- `SPEC.md`: spécification détaillée du projet (mappings, architecture, constantes). Utilisez-le comme source de vérité.
- `src/`: code source organisé par rôle : `client/`, `server/`, `shared/`.
  - `src/client`: scripts et systèmes côté client (caméra, input, UI, systèmes de mouvement).
  - `src/server`: scripts côté serveur (stores, validateurs, logique persistante).
  - `src/shared`: modules partagés (protocoles réseau, états, configs, utils physiques).
- `README.md`: informations générales et instructions d'usage du dépôt.
- `SOURCE_ENGINE_SURF.md`: notes de référence sur le surf Source et les comportements de mouvement à reproduire.
- `CSGO.rbxlx`: artefact de build produit par `rojo build`.
- `feedback.md`: journal de retours et notes de travail.
- `logs.md`: journalisation et traces de debug.
- `sourcemap.json`: mapping de source pour la synchro Rojo.

## Notes

- Garder `default.project.json` synchronisé avec l'arborescence `src/` (mappings Rojo).
- `rokit.toml` gère la version de Rojo et des outils qualité (`rokit install` pour les installer).
- `SPEC.md` contient la spécification détaillée (mappings, architecture, constantes). Utilisez-le comme source de vérité pour la structure des fichiers.
- Valeurs récentes : `RUN_SPEED=30`, `AIR_SPEED_CAP=6`, `AIR_ACCEL=150`, `GROUND_ACCEL=12`, `GRAVITY=-110`, `MAX_FALL_SPEED=130`, `AUTO_BHOP=true`.
- Consigne de lecture : pour les revues de code, analyses ou demandes de modification, ne lire que les fichiers strictement concernés par l'étape ou la demande.
- Évitez d'analyser ou d'indexer l'ensemble du dépôt sauf si la tâche l'exige explicitement. Quand vous consultez des fichiers, précisez lesquels dans votre message ou votre PR.

## Notes importantes post-implémentation Phase 1

- `Players.CharacterAutoLoads = false` est défini dans `init.server.luau` — les personnages ne spawnt que via `RequestSpawn` remote.
- Le round démarre automatiquement dès qu'un joueur clique Play (état idle → active).
- Aucun point de spawn n'existe encore dans le workspace : `SpawnManager` utilise les `SpawnLocation` Roblox ou les `Part` nommées `"SpawnPoint"` ; fallback à `(0, 10, 0)`.
- `StatsStore` désactive la sauvegarde pour la session si le DataStore load échoue (sécurité anti-écrasement).
- §12 question 1 résolue : stats et réglages restent dans deux DataStores séparés.

## Descriptions courtes des fichiers dans `src/`

- `src/client/init.client.luau`: point d'entrée client, initialise les modules côté client.
- `src/client/camera/FPSCamera.luau`: contrôles et logique de la caméra FPS.
- `src/client/debug/DebugPlaytest.luau`: moitié client du helper de playtest (Studio uniquement) : exécute les commandes du serveur et observe pistes, marqueurs et sons.
- `src/client/debug/Noclip.luau`: outil de debug pour activer/désactiver le noclip.
- `src/client/input/InputModule.luau`: gestion des entrées utilisateur et mapping des actions.
- `src/client/systems/movement/BhopSystem.luau`: implémentation du bunnyhop (saut en chaîne).
- `src/client/systems/movement/CharacterDimensions.luau`: calcule les dimensions du personnage et les hitboxes debout/accroupi.
- `src/client/systems/movement/CoyoteJump.luau`: gestion du "coyote time" pour les sauts.
- `src/client/systems/movement/CrouchSystem.luau`: logique de position accroupie, hauteur caméra et hitbox.
- `src/client/systems/movement/GroundDetection.luau`: détection du sol et transitions air/sol.
- `src/client/systems/movement/HeadCollisionResolver.luau`: résolution des collisions tête (plafond, mur haut) lors du déplacement.
- `src/client/systems/movement/MovementController.luau`: orchestrateur principal du mouvement (boucle Heartbeat, transitions d'état).
- `src/client/systems/movement/PhysicsStepAir.luau`: étape physique aérienne (air accelerate Source + cap `AIR_SPEED_CAP`).
- `src/client/systems/movement/PhysicsStepGround.luau`: étape physique pour l'état au sol.
- `src/client/systems/movement/SlopeSystem.luau`: gestion des pentes et adaptation du mouvement.
- `src/client/systems/movement/StepupSystem.luau`: logique pour monter sur de petits obstacles.
- `src/client/systems/movement/WallSlide.luau`: glisse le long des murs/rampe avec conservation de normale surf si on avance vers la rampe.
- `src/client/systems/weapon/AnimationSoundSystem.luau`: gestion des marqueurs sons sur les AnimationTracks.
- `src/client/systems/weapon/MeleeHitDetection.luau`: raycast et calcul de dégâts melee (backstab inclus).
- `src/client/systems/weapon/ScopeSystem.luau`: gestion du scope (FOV, affichage de la lunette, sensibilité caméra) pour les armes à lunette.
- `src/client/systems/weapon/ViewmodelSystem.luau`: gestion du viewmodel, des animations et des sons des armes en vue FPS.
- `src/client/systems/weapon/WeaponSystem.luau`: logique client des armes, munitions, recharge et vitesse liée à l'arme.
- `src/client/systems/weapon/WeaponThirdPersonView.luau`: rendu client des armes 3e personne de tous les personnages (décalage procédural du grip pour tir/recharge/switch, modèle 3P masqué pour soi en 1re personne).
- `src/client/systems/game/GameStateController.luau`: machine d'état client (MENU/INFOS/SPAWNING/IN_ROUND/DEAD/RESULT), caméra lobby, coordination UI ↔ remotes.
- `src/client/ui/InfosScreen.luau`: overlay Infos (comment surfer, contrôles, crédits).
- `src/client/ui/MainMenu.luau`: menu d'accueil avec boutons Play et Infos.
- `src/client/ui/RoundHUD.luau`: HUD en jeu (timer, leaderboard Tab, overlay respawn, bannière résultat).
- `src/client/ui/ScopeOverlay.luau`: lunette des armes à scope, dessinée sans image (masque rond et réticule en Frames).
- `src/client/ui/SettingsMenu.luau`: interface des réglages côté client.
- `src/client/ui/Speedometer.luau`: affichage de la vitesse du joueur.
- `src/server/init.server.luau`: point d'entrée serveur — crée tous les RemoteEvents, orchestre SpawnManager, RoundManager, StatsStore.
- `src/server/DebugPlaytest.luau`: helper de playtest (Studio uniquement) : déclenché par un attribut joueur, enchaîne spawn, équipement, cible immobile et attaque, avec un PASS/FAIL par étape.
- `src/server/RoundManager.luau`: boucle de round FFA (timer, kills/deaths, fin de round, diffusion résultat).
- `src/server/SettingsStore.luau`: stockage et récupération des paramètres serveur.
- `src/server/SpawnManager.luau`: gestion du spawn différé (RequestSpawn remote, LoadCharacter, point de spawn aléatoire).
- `src/server/StatsStore.luau`: DataStore stats joueur (kills/deaths/rounds), save périodique + déconnexion, robustesse load.
- `src/server/Validator.luau`: validation serveur des dégâts melee et hitscan (distance, ownership, sanity).
- `src/shared/CameraConfig.luau`: constantes caméra (FOV, sensibilité, pitch min/max, hauteurs, lerp speed, scope sens multiplier).
- `src/shared/CharacterConfig.luau`: rig/skin communs (couleurs, ids d'images Shirt/Pants/visage) et animations 3e personne (ids, fallbacks, seuils de vitesse, fondus).
- `src/shared/CharacterAppearance.luau`: rig de référence (`StarterPlayer.StarterCharacter`, cloné pour la cible du helper de playtest) et application du skin commun (BodyColors + vêtements) côté serveur.
- `src/shared/CharacterAnimator.luau`: pipeline d'animation 3e personne des joueurs (état de mouvement → piste, fondus, vitesse de lecture) ; alimenté par `MovementController` (client, répliqué via l'Animator).
- `src/shared/DebugPlaytestRules.luau`: règles pures du helper de playtest (choix de l'outil, marqueurs et dégâts attendus, visée, rapport PASS/FAIL).
- `src/shared/GameConfig.luau`: constantes jeu (ROUND_DURATION=300, RESPAWN_DELAY=2.5, RESULT_DURATION=6, AUTO_SAVE_INTERVAL=120).
- `src/shared/MovementConfig.luau`: constantes physique du mouvement uniquement (vitesses, accel, friction, saut, pentes, bhop, réseau, hitbox).
- `src/shared/MovementState.luau`: structure d'état partagée pour le mouvement du joueur.
- `src/shared/NetworkProtocol.luau`: noms des RemoteEvents et helper getRemote(name). Remotes : MeleeDamage, HitscanDamage, RequestSpawn, RoundState, ScoreUpdate, RoundResult, PlayerDied, WeaponAction, DebugPlaytest (créé uniquement dans Studio).
- `src/shared/PhysicsUtils.luau`: fonctions utilitaires pour la physique.
- `src/shared/WeaponConfig.luau`: définitions partagées des armes et de leurs paramètres par défaut (dont `ThirdPerson` : échelle, grip, pose 3P).
- `src/shared/WeaponThirdPerson.luau`: arme 3e personne des joueurs : construction du modèle 3P depuis `ViewModels`, grip soudé à la main, pose des épaules, actions répliquées en attributs (`Weapon3PAction`/`Weapon3PActionAt`), règles pures (grip, décalages d'action, visibilité).

## Common Commands

```bash
rojo serve                  # checkout principal, port 34872 (worktrees : scripts/csgo-worktree.ps1)
rojo build -o "CSGO.rbxlx"
bash tools/check.sh         # selene + stylua --check + luau-lsp analyze sur src/, puis tests Lune
lune run tests/run.luau     # tests unitaires seuls
bash tools/check.sh --fix   # idem, en appliquant le formatage StyLua
```

## Outillage qualité

- Outils gérés par Rokit (`rokit.toml`) : `rojo`, `stylua`, `selene`, `luau-lsp`, `lune`. Binaires dans `~/.rokit/bin` ; installer avec `rokit install`.
- Configs : `stylua.toml` (tabs, guillemets doubles, 120 colonnes), `selene.toml` (std roblox, règles par défaut), `.luaurc` (mode `nonstrict`).
- Les fichiers de constantes (`CameraConfig`, `GameConfig`, `MovementConfig`) sont exclus de StyLua via `-- stylua: ignore` pour garder l'alignement en colonnes : respecter cet alignement à la main quand on les modifie.
- Après toute modification de code `.luau`, lancer `bash tools/check.sh` et ne pas introduire de nouvel avertissement.
- Tests unitaires (Lune, hors Roblox) dans `tests/specs/*.spec.luau` : chaque spec retourne `function(T, Loader)`. `Loader.new({ Players = mock }):require("src/...")` charge un module de `src/` en simulant `game:GetService` et le `require` d'Instances Rojo ; les services non simulés lèvent une erreur. Seuls les modules sans raycast/`workspace` sont testables (physique pure, `Validator`). Ajouter un test pour toute correction de bug physique.
- Git LFS : les binaires d'assets (`*.blend`, `*.fbx`, `*.obj`, images, sons) sont suivis par LFS via `.gitattributes`. Installer `git lfs` puis `git lfs install` avant de cloner. Un nouveau format binaire doit être ajouté à `.gitattributes` avant son premier commit. Les `.rbxm` de `assets/rbx/` sont aussi en LFS (le checkout de la CI utilise `lfs: true`).
- CI GitHub Actions (`.github/workflows/ci.yml`) : sur chaque PR et push sur `main`, lance `tools/check.sh`, `rojo build`, puis `tools/rbxm/verify_place.luau`. Les définitions de types luau-lsp sont téléchargées pour la version déclarée dans `rokit.toml`.

## Roblox Studio MCP

- Le serveur MCP `Roblox_Studio` (officiel, intégré à Studio) est configuré en scope local. Studio doit être ouvert avec "Enable Studio as MCP server" activé.
- **Ne jamais modifier de scripts via le MCP** (`multi_edit`, `execute_luau` qui écrit dans `Source`, etc.) : la synchro Rojo va uniquement des fichiers vers Studio, toute modification de script faite dans Studio sera écrasée ou perdue. Le code se modifie exclusivement dans `src/`.
- Usages du MCP : inspecter la scène (`search_game_tree`, `inspect_instance`), construire la map et les objets du workspace (rampes de surf, spawns, décor), chercher et insérer des assets, playtester (`start_stop_play`, simulation d'input, `get_console_output`, `screen_capture`) pour vérifier un comportement.
- Les éléments créés dans le workspace via le MCP ne sont pas dans `src/` : penser à sauvegarder la place dans Studio.
- Helper de playtest (Studio uniquement, inactif hors Studio) : vérifie en une commande l'équipement, l'attaque, le son et les dégâts d'une arme. Playtest lancé, en contexte `Server` (`execute_luau`), avec un nom d'outil ou un numéro de slot (ordre alphabétique) :
  ```lua
  game.Players:GetPlayers()[1]:SetAttribute("DebugPlaytest", "AWP")
  ```
  Puis `get_console_output`, lignes préfixées `[DebugPlaytest]` : un `PASS`/`FAIL` par étape (SPAWN, EQUIP, TARGET, AIM, VIEWMODEL, ATTACK, SOUND, DAMAGE, STILL_EQUIPPED) et un `RESULT` final. `VIEWMODEL` échoue si le viewmodel n'est pas devant la caméra ou si son modèle source est abîmé (`PrimaryPart` absent, enfant en double, joint cassé). L'attribut revient à nil en fin de run. La cible `DebugDummy` reste en jeu jusqu'au run suivant.

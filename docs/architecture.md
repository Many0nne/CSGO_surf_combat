# Architecture et carte des fichiers

À consulter pour trouver où se trouve un comportement. Lire ensuite seulement les fichiers concernés.

Les valeurs de réglage ne sont pas recopiées ici : leur source est le fichier de config (`src/shared/MovementConfig.luau`, `GameConfig.luau`, `WeaponConfig.luau`, `CameraConfig.luau`).

Les anciennes specs ont été retirées du dépôt et restent lisibles dans l'historique git : `git show 9880fa3^:SPEC.md`, `git show 9880fa3^:SOURCE_ENGINE_SURF.md`, `git show d0e3faf^:GAME_SYSTEM_SPEC.md`. Elles décrivent un état ancien : le code fait foi.

## Comportements à connaître

- `Players.CharacterAutoLoads = false` (`init.server.luau`) : les personnages n'apparaissent que via le remote `RequestSpawn`.
- Un round démarre quand un joueur demande à spawn alors que le round est à l'état `idle` (`init.server.luau`).
- `SpawnManager` tire un point au hasard dans `Workspace.Maps.Map.GroundSpawns` (dans la place, pas dans `src/`) ; s'il n'en trouve aucun, il avertit et utilise `(0, 10, 0)`.
- `StatsStore` désactive la sauvegarde pour la session si le chargement DataStore échoue, pour ne pas écraser les données.
- **Crash de Rojo :** `rojo serve` 7.7.1 peut s'arrêter sur `Rojo crashed!` (`change_processor.rs:172`, fichier introuvable). Constaté après la suppression puis la recréation immédiate de fichiers surveillés dans `src/` (cause probable, non reproduite) : écrire par-dessus un fichier plutôt que le supprimer d'abord. Si Rojo ne répond plus, lire `worktrees/.run/<slug>.log`, relancer `.\scripts\csgo-worktree.ps1 <branche>`, puis reconnecter le plugin.

## Racine, outils et assets

- `docs/animations.md`: méthode de création des animations de viewmodel (processus de validation, outils, pièges connus).
- `docs/ui.md`: direction artistique de l'interface (principe, essais rejetés, construction du menu, pièges, reste à faire).
- `tools/anim/`: outils de ces animations : mesure sur vidéo, rendu et capture dans Studio, vidéo côte à côte, publication Open Cloud.
- `assets/awp_viewmodel/`: animations de l'AWP : trajectoires mesurées (`build_anims.py`), rig Studio (`rig.json`), build sans toucher au Blender ouvert (`run_build.py`). Sons de l'arme : découpe depuis leurs sources (`build_sounds.py`), extraits CC0 dans `sounds/` ; `Shoot` et `Bolt` (Pixabay) sont publiés sur Roblox, pas versionnés.
- `default.project.json`: configuration Rojo qui mappe `src/` et `assets/rbx/` (viewmodels, Tools) vers le projet Roblox.
- `assets/rbx/ViewModels/*.rbxm`, `assets/rbx/Tools/*.rbxm`: viewmodels et Tools des armes (binaires LFS, voir « Viewmodels et Tools »).
- `tools/rbxm/receive.luau`: serveur Lune local qui reçoit les `.rbxm` exportés de Studio et les écrit sous `assets/rbx/`.
- `tools/rbxm/studio_export.luau`: script à exécuter dans Studio qui sérialise viewmodels et Tools et les envoie à `receive.luau`.
- `tools/publish_asset.sh`: publie une animation, un modèle, un son ou une image par Open Cloud, attend la fin de l'opération et écrit l'`assetId`.
- `tools/ui/make_menu_type.py`: génère le titrage du menu (lettres usées, éclats, impacts) dans `assets/ui/menu/`.
- `tools/export_mesh_fbx.py`: exporte les meshes d'un `.blend` en FBX avec l'orientation attendue dans Roblox.
- `tools/rbxm/verify_place.luau`: relit la place construite par Rojo et vérifie viewmodels, Tools, ids d'assets et noms d'armes.
- `rokit.toml`: versions des outils (Rojo, StyLua, Selene, luau-lsp, Lune) gérées par Rokit.
- `CSGO.rbxlx`: artefact de build produit par `rojo build`.
- `sourcemap.json`: mapping de source pour la synchro Rojo.
- `tools/studio/ramp_crest_sim.luau`: harnais à exécuter dans Studio qui reproduit l'issue #7 (perte de vitesse à la jonction entre une rampe et le sol).

## `src/`

- `src/client/camera/FPSCamera.luau`: contrôles et logique de la caméra FPS.
- `src/client/debug/DebugPlaytest.luau`: moitié client du helper de playtest (Studio uniquement) : exécute les commandes du serveur et observe pistes, marqueurs et sons.
- `src/client/debug/Noclip.luau`: outil de debug pour activer/désactiver le noclip.
- `src/client/init.client.luau`: point d'entrée client, initialise les modules côté client.
- `src/client/input/InputModule.luau`: gestion des entrées utilisateur et mapping des actions.
- `src/client/systems/game/GameStateController.luau`: machine d'état client (MENU/INFOS/SPAWNING/IN_ROUND/DEAD/RESULT), coordination UI ↔ remotes.
- `src/client/systems/game/MenuScene.luau`: scène 3D du menu (canyon, AWP qui suit le curseur, surfeurs à abattre, plongée sur JOUER), éclairage temporaire rétabli à la sortie.
- `src/client/systems/game/MenuSceneRules.luau`: règles pures de cette scène (amortis, angles de visée, trajectoire, touche).
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
- `src/client/systems/weapon/HitscanSystem.luau`: raycast des armes à distance, traceur du tir et signalement de la touche au serveur.
- `src/client/systems/weapon/MeleeHitDetection.luau`: raycast melee et signalement de la touche au serveur (type d'attaque, les dégâts sont calculés côté serveur).
- `src/client/systems/weapon/ScopeSystem.luau`: gestion du scope (FOV, affichage de la lunette, sensibilité caméra) pour les armes à lunette.
- `src/client/systems/weapon/ViewmodelSystem.luau`: gestion du viewmodel, des animations et des sons des armes en vue FPS.
- `src/client/systems/weapon/WeaponSystem.luau`: logique client des armes, munitions, recharge et vitesse liée à l'arme.
- `src/client/systems/weapon/WeaponThirdPersonView.luau`: rendu client des armes 3e personne de tous les personnages (décalage procédural du grip pour tir/recharge/switch, modèle 3P masqué pour soi en 1re personne).
- `src/client/ui/FeedbackScreen.luau`: écran Feedback (message de 10 à 500 caractères envoyé au serveur, ENVOYER se tire).
- `src/client/ui/HUDRules.luau`: règles pures du HUD (paliers de vitesse, timer, classement).
- `src/client/ui/Hitmarker.luau`: marqueur de touche confirmée par le serveur (X blanc à contour noir, rouge sur un tir à la tête, plus grand sur un kill).
- `src/client/ui/InfosScreen.luau`: écran Infos (surfer, commandes, crédits, à propos), onglets à tirer.
- `src/client/ui/MainMenu.luau`: menu d'accueil où l'on choisit en tirant : titre et libellés en images, hitmarker en guise de curseur, impacts de balles.
- `src/client/ui/MenuCursor.luau`: hitmarker qui remplace le curseur sur tous les écrans du menu.
- `src/client/ui/MenuPage.luau`: gabarit des écrans secondaires du menu (dégradé, titre en image, action de sortie) et ids des mots publiés.
- `src/client/ui/MenuShot.luau`: tir sur un élément du menu (impact, puis action) et choix en images usées.
- `src/client/ui/RoundHUD.luau`: HUD en jeu (timer, leaderboard Tab, overlay respawn, bannière résultat).
- `src/client/ui/ScopeOverlay.luau`: lunette des armes à scope, dessinée sans image (masque rond et réticule en Frames).
- `src/client/ui/SettingsMenu.luau`: écran Réglages, à même la scène dans le menu (on règle en tirant), sur un voile sombre sans tir en partie (touche P).
- `src/client/ui/Speedometer.luau`: affichage de la vitesse du joueur.
- `src/client/ui/Transition.luau`: volets de transition entre le menu et le jeu.
- `src/client/ui/UIKit.luau`: briques communes des écrans (création d'Instances, texte au thème, tweens, icônes, mise à l'échelle).
- `src/server/DebugPlaytest.luau`: helper de playtest (Studio uniquement) : déclenché par un attribut joueur, enchaîne spawn, équipement, cible immobile et attaque, avec un PASS/FAIL par étape.
- `src/server/FeedbackService.luau`: réception des feedbacks côté serveur (longueur, délai entre deux envois, limite hebdomadaire).
- `src/server/RoundManager.luau`: boucle de round FFA (timer, kills/deaths, fin de round, diffusion résultat).
- `src/server/SettingsStore.luau`: module vide, non utilisé pour l'instant.
- `src/server/SpawnManager.luau`: gestion du spawn différé (RequestSpawn remote, LoadCharacter, point de spawn aléatoire).
- `src/server/StatsStore.luau`: DataStore stats joueur (kills/deaths/rounds), save périodique + déconnexion, robustesse load.
- `src/server/Validator.luau`: décision serveur des touches melee et hitscan (cible, arme en main, partie touchée, portée, cadence), calcul des dégâts depuis `WeaponConfig` (zone du corps pour le hitscan, backstab pour la mêlée) et qualification d'une touche (hit/kill).
- `src/server/init.server.luau`: point d'entrée serveur — crée tous les RemoteEvents, orchestre SpawnManager, RoundManager, StatsStore.
- `src/shared/CameraConfig.luau`: constantes caméra (FOV, sensibilité, pitch min/max, hauteurs, lerp speed, scope sens multiplier).
- `src/shared/CharacterAnimator.luau`: pipeline d'animation 3e personne des joueurs (état de mouvement → piste, fondus, vitesse de lecture) ; alimenté par `MovementController` (client, répliqué via l'Animator).
- `src/shared/CharacterAppearance.luau`: rig de référence (`StarterPlayer.StarterCharacter`, cloné pour la cible du helper de playtest) et application du skin commun (BodyColors + vêtements) côté serveur.
- `src/shared/CharacterConfig.luau`: rig/skin communs (couleurs, ids d'images Shirt/Pants/visage) et animations 3e personne (ids, fallbacks, seuils de vitesse, fondus).
- `src/shared/DebugPlaytestRules.luau`: règles pures du helper de playtest (choix de l'outil, marqueurs et dégâts attendus, visée, rapport PASS/FAIL).
- `src/shared/GameConfig.luau`: constantes jeu (ROUND_DURATION=300, RESPAWN_DELAY=2.5, RESULT_DURATION=6, AUTO_SAVE_INTERVAL=120).
- `src/shared/HitZones.luau`: zones du corps touchées (tête, torse, bras, jambes), multiplicateurs de dégâts des armes à distance et règle de calcul.
- `src/shared/MovementConfig.luau`: constantes physique du mouvement uniquement (vitesses, accel, friction, saut, pentes, bhop, réseau, hitbox).
- `src/shared/MovementState.luau`: structure d'état partagée pour le mouvement du joueur.
- `src/shared/NetworkProtocol.luau`: noms des RemoteEvents et helper getRemote(name). Remotes : MeleeDamage, HitscanDamage, HitConfirm, RequestSpawn, RoundState, ScoreUpdate, RoundResult, PlayerDied, WeaponAction, SendFeedback, FeedbackAck, DebugPlaytest (créé uniquement dans Studio).
- `src/shared/PhysicsUtils.luau`: fonctions utilitaires pour la physique.
- `src/shared/UITheme.luau`: tokens de style de l'interface (couleurs, polices, tailles, durées, courbes).
- `src/shared/WeaponConfig.luau`: définitions partagées des armes et de leurs paramètres par défaut (dont `ThirdPerson` : échelle, grip, pose 3P).
- `src/shared/WeaponThirdPerson.luau`: arme 3e personne des joueurs : construction du modèle 3P depuis `ViewModels`, grip soudé à la main, pose des épaules, actions répliquées en attributs (`Weapon3PAction`/`Weapon3PActionAt`), règles pures (grip, décalages d'action, visibilité).

# Architecture et carte des fichiers

À consulter pour trouver où se trouve un comportement. Lire ensuite seulement les fichiers concernés.

Les valeurs de réglage ne sont pas recopiées ici : leur source est le fichier de config (`src/shared/MovementConfig.luau`, `GameConfig.luau`, `WeaponConfig.luau`, `CameraConfig.luau`).

Les anciennes specs ont été retirées du dépôt et restent lisibles dans l'historique git : `git show 9880fa3^:SPEC.md`, `git show 9880fa3^:SOURCE_ENGINE_SURF.md`, `git show d0e3faf^:GAME_SYSTEM_SPEC.md`. Elles décrivent un état ancien : le code fait foi.

## Comportements à connaître

- `Players.CharacterAutoLoads = false` (`init.server.luau`) : les personnages n'apparaissent que via le remote `RequestSpawn`.
- Un round démarre quand un joueur demande à spawn alors que le round est à l'état `idle` (`init.server.luau`).
- `SpawnManager` tire un lanceur au hasard dans `SunLaunch` de la map jouée (map versionnée dans `assets/rbx/Maps`, cf. `docs/maps.md`) : le joueur est projeté depuis le soleil, invulnérable `GameConfig.SPAWN_PROTECTION` secondes. Sans lanceur, il tire un point dans `GroundSpawns` ; sans aucun point, il avertit et utilise `(0, 10, 0)`.
- **Position des personnages (#75) :** la racine est ancrée (client et serveur, `StarterCharacter`) et déplacée à la main par `MovementController` : la physique ne réplique rien. Le client envoie sa position et son cap à `MovementConfig.NET_SYNC_RATE` (`UnreliableRemoteEvent` `CharacterSync`) ; `src/server/CharacterSync.luau` vérifie le déplacement depuis le dernier point accepté (`MAX_SPEED_SERVER`, `MAX_DELTA_POS`, règles dans `CharacterSyncRules`), pose le CFrame de la racine serveur, teste la hauteur de mort, et relaie la position horodatée aux autres clients, qui l'interpolent avec `INTERP_DELAY` de retard. Une position impossible est ignorée avec un warn, sans renvoi du client.
- **Piège, écho serveur :** le CFrame posé par le serveur se réplique aussi au client propriétaire, avec un aller-retour de retard. `MovementController` réécrit donc son dernier CFrame (`ownCFrame`) avant chaque pas, sinon le personnage recule à chaque paquet. Tout déplacement client de la racine hors de la boucle de mouvement doit mettre `ownCFrame` à jour (cf. `applyLaunch`), et une téléportation décidée par le serveur sur un personnage vivant serait annulée par le client.
- `StatsStore` désactive la sauvegarde pour la session si le chargement DataStore échoue, pour ne pas écraser les données. `SettingsStore` fait de même pour les réglages.
- **Réglages du joueur (#100) :** Roblox n'a pas de stockage local côté client, tout passe par le serveur. Le client demande ses réglages au démarrage (`RemoteFunction` `GetSettings`, réponse après le chargement DataStore), applique d'abord les valeurs par défaut, puis les réglages reçus ; chaque changement repart au serveur 1 s plus tard (`SaveSettings`), qui le valide (`PlayerSettings.sanitize`) et l'écrit au plus toutes les 10 s, puis au départ du joueur. Dans Studio sans « Enable Studio Access to API Services », le chargement échoue (warn `[SettingsStore]`) : défauts, rien n'est sauvegardé.
- **Participants, joueurs et bots (#137) :** `RoundManager`, `Validator` et `init.server.luau` ne manipulent que des participants (`src/server/Participants.luau`) : un joueur y entre par `Participants.fromPlayer` (id = `UserId`), un bot par `Participants.addBot` (id négatif, pas de `Player`, personnage posé par `setCharacter`). Les scores (`ScoreUpdate`) et `PlayerDied` portent nom et drapeau `isBot` : le client n'a pas besoin de `Player` pour le kill feed ni le classement, où un bot porte le préfixe `BOT` en gris (`ParticipantRules.BOT_PREFIX`). Une mort infligée par un bot ne compte pas dans `StatsStore` (`ParticipantRules.countsInStats`). Ne pas réintroduire de fonctions `*ById` en double : toute nouvelle API du round prend un participant.
- **Mort (#102) :** `RoundManager` retient le dernier coup reçu par chaque participant (tireur, arme en main, tir à la tête) et, à la mort, envoie `PlayerDied` à **tous** les clients : `{ victimId, victimName, victimIsBot, killerId?, killerName?, killerIsBot, weapon?, headshot, position, direction? }` (direction = du tueur vers la victime ; pas de tueur pour une chute ou un tueur parti), lu côté client par `HUDRules.readDeath`. Le serveur ne détruit le personnage qu'après `CORPSE_HANDOFF_DELAY` (0,3 s, `init.server.luau`) : chaque client le clone en ragdoll local (`DeathRagdoll`), la physique n'étant pas répliquée. Une touche sur un personnage déjà mort n'est pas attribuée, sinon elle créditerait la mort suivante de la victime. Côté client, `GameStateController.onPlayerDied` crée le corps, ajoute la ligne de kill feed et, pour le tué, renseigne l'écran de mort et lance `DeathCamera`. `PlayerDied` et `Humanoid.Died` arrivent dans un ordre quelconque : l'info du tueur est gardée `DEATH_INFO_TTL` et appliquée au passage en `DEAD`.
- **Crash de Rojo :** `rojo serve` 7.7.1 peut s'arrêter sur `Rojo crashed!` (`change_processor.rs:172`, fichier introuvable). Constaté après la suppression puis la recréation immédiate de fichiers surveillés dans `src/` (cause probable, non reproduite) : écrire par-dessus un fichier plutôt que le supprimer d'abord. Si Rojo ne répond plus, lire `worktrees/.run/<slug>.log`, relancer `.\scripts\csgo-worktree.ps1 <branche>`, puis reconnecter le plugin.
- **Erreur console `rbxassetid://203785492` (#93) :** `ContentId: rbxassetid://203785492 failed due to: Asset type does not match requested type`, plusieurs fois au lancement d'un playtest, vient du plugin Rojo, pas du jeu. C'est son son de notification (`Rojo.Plugin.Assets`, `Sounds.Notification`, audio « Pop Close Sound »), chargé côté client par le widget `Rojo_soundPlayer`. Aucune instance de la place ne le référence. L'ignorer ; pour le faire taire, désactiver « Play Sounds » dans les réglages du plugin Rojo.

## Racine, outils et assets

- `docs/animations.md`: méthode de création des animations de viewmodel (processus de validation, outils, pièges connus).
- `docs/ui.md`: direction artistique de l'interface (principe, essais rejetés, construction du menu, pièges, reste à faire).
- `tools/anim/`: outils de ces animations : mesure sur vidéo, rendu et capture dans Studio, vidéo côte à côte, publication Open Cloud.
- `assets/awp_viewmodel/`: animations de l'AWP : trajectoires mesurées (`build_anims.py`), rig Studio (`rig.json`), build sans toucher au Blender ouvert (`run_build.py`). Sons de l'arme : découpe depuis leurs sources (`build_sounds.py`), extraits CC0 dans `sounds/` ; `Shoot` et `Bolt` (Pixabay) sont publiés sur Roblox, pas versionnés.
- `default.project.json`: configuration Rojo qui mappe `src/` et `assets/rbx/` (viewmodels, Tools, maps) vers le projet Roblox, et fixe la lumière du crépuscule (Lighting, Atmosphere).
- `tools/map/build_dizzy.luau`: générateur de Dizzy (seule map, cf. `docs/maps.md`), exécuté dans Lune sans Studio, lit le plan `tools/map/dizzy_layout.json` (relevé par `tools/map/extract_dizzy.py`, contrôlé par `tools/map/verify_dizzy.py` et `tools/map/zfight_dizzy.py` pour le scintillement, tous dans Blender sans interface), puis applique les retouches locales de `tools/map/dizzy_patches.luau` (module `tools/map/DizzyPatches.luau`), et coupe les ombres invisibles (`tools/map/ShadowCulling.luau`, testé par `tests/specs/ShadowCulling.spec.luau`). `src/shared/MapSelection.luau` : choix de la map jouée (`GameConfig.ACTIVE_MAP`) parmi `Workspace.Maps`.
- `docs/maps/plans-arene-digue-echangeur.html`: maquettes 3D des trois plans proposés (l'Arène, retirée depuis ; Digue et Échangeur gardés de côté).
- `assets/rbx/ViewModels/*.rbxm`, `assets/rbx/Tools/*.rbxm`: viewmodels et Tools des armes (binaires LFS, voir « Viewmodels et Tools »).
- `tools/rbxm/receive.luau`: serveur Lune local qui reçoit les `.rbxm` exportés de Studio et les écrit sous `assets/rbx/`.
- `tools/rbxm/studio_export.luau`: script à exécuter dans Studio qui sérialise viewmodels et Tools et les envoie à `receive.luau`.
- `tools/publish_asset.sh`: publie une animation, un modèle, un son ou une image par Open Cloud, attend la fin de l'opération et écrit l'`assetId`.
- `tools/export_mesh_fbx.py`: exporte les meshes d'un `.blend` en FBX avec l'orientation attendue dans Roblox.
- `tools/rbxm/verify_place.luau`: relit la place construite par Rojo et vérifie viewmodels, Tools, ids d'assets et noms d'armes.
- `tools/perf/audit_map.luau`: audit statique d'une map `.rbxm` (pièces, ombres, transparences, collisions et requêtes par dossier, lumières), cf. `docs/performance.md`.
- `rokit.toml`: versions des outils (Rojo, StyLua, Selene, luau-lsp, Lune) gérées par Rokit.
- `CSGO.rbxlx`: artefact de build produit par `rojo build`.
- `sourcemap.json`: mapping de source pour la synchro Rojo.
- `tools/studio/ramp_crest_sim.luau`: harnais à exécuter dans Studio qui reproduit l'issue #7 (perte de vitesse à la jonction entre une rampe et le sol).

## `src/`

- `src/client/camera/FPSCamera.luau`: contrôles et logique de la caméra FPS (rendu, priorité `Camera`) : rotation à la souris, position lue sur `hrp.Position` juste après le pas de mouvement de la même frame.
- `src/client/debug/DebugPlaytest.luau`: moitié client du helper de playtest (Studio uniquement) : exécute les commandes du serveur et observe pistes, marqueurs et sons.
- `src/client/debug/FrameProbe.luau`: sonde de saccades (Studio uniquement, attribut joueur `FrameProbe`) : mesure chaque frame et signale les frames anormales, cf. `docs/performance.md`.
- `src/client/debug/PerfOverlay.luau`: overlay de performance (touche F3, Studio ou créateur du jeu publié) : frames, coût du rendu, mémoire, réseau, coût de nos boucles, bilan console toutes les 10 s ; active aussi les relevés mémoire client, cf. `docs/performance.md`.
- `src/client/debug/PerfBench.luau`: banc de rendu (touche F4 ou attribut `PerfBench`, mêmes droits que l'overlay) : coupe les leviers de rendu un par un et écrit une ligne `[Perf] BANC` par phase ; règles de résumé dans `PerfRules`.
- `src/client/debug/Noclip.luau`: outil de debug pour activer/désactiver le noclip.
- `src/client/init.client.luau`: point d'entrée client, initialise les modules côté client.
- `src/client/input/InputModule.luau`: gestion des entrées utilisateur et mapping des actions.
- `src/client/systems/game/GameStateController.luau`: machine d'état client (MENU/INFOS/SPAWNING/IN_ROUND/DEAD/RESULT), coordination UI ↔ remotes.
- `src/client/systems/game/MenuScene.luau`: scène 3D du menu (salle des miroirs : éclats qui reconstituent l'arme, tir sur les éclats, explosion sur JOUER), éclairage temporaire rétabli à la sortie.
- `src/client/systems/game/DeathRagdoll.luau`: corps d'un joueur tué : clone local du personnage, Motor6D du rig en rotules limitées, vitesse du joueur plus poussée dans le sens du tir ; estompé puis retiré (6 corps au plus).
- `src/client/systems/game/DeathRules.luau`: règles pures de la mort (poussée par arme, durée de vie des corps, lissage de la caméra, distance affichée), testées (`tests/specs/DeathRules.spec.luau`).
- `src/client/camera/DeathCamera.luau`: caméra du joueur tué : reste au lieu de la mort et pivote vers le tueur (priorité `Camera + 1`, après `FPSCamera`), repère « NOM · distance » au-dessus de lui.
- `src/client/systems/game/MenuSceneRules.luau`: règles pures de cette scène (amortis, angles de visée, trajectoire, touche).
- `src/client/systems/network/CharacterSync.luau`: envoi de la position du personnage local (appelé par `MovementController`) et affichage des autres joueurs à leur position relayée, interpolée (rendu, priorité `Camera - 2`).
- `src/client/systems/movement/BoostSystem.luau`: boosts de la map (geysers, lanceurs, portiques de `Maps.Map.Boosts`) détectés à chaque frame, avec recharge par boost.
- `src/client/systems/movement/BhopSystem.luau`: implémentation du bunnyhop (saut en chaîne).
- `src/shared/movement/CharacterDimensions.luau`: calcule les dimensions du personnage et les hitboxes debout/accroupi.
- `src/client/systems/movement/CoyoteJump.luau`: gestion du "coyote time" pour les sauts.
- `src/client/systems/movement/CrouchSystem.luau`: logique de position accroupie, hauteur caméra et hitbox.
- `src/shared/movement/GroundDetection.luau`: détection du sol et transitions air/sol (un muret plus bas que le centre du corps n'est pas pris pour le sol : `PhysicsUtils.isSideContact`).
- `src/client/systems/movement/LadderSystem.luau`: échelles de la map (volumes de `Maps.Map.Ladders`) détectées à chaque frame ; `MovementController` y remplace la physique sol/air par la grimpe.
- `src/shared/movement/HeadCollisionResolver.luau`: résolution des collisions tête (plafond, mur haut) lors du déplacement.
- `src/client/systems/movement/MovementController.luau`: orchestrateur principal du mouvement (boucle sur le rendu, priorité `Camera - 1`, physique en ticks fixes de 64 Hz par `StepTiming`, position affichée interpolée entre les deux derniers ticks ; transitions d'état) ; `getVelocity()` et `getStepStats()` exposent la vitesse du dernier pas et les pas simulés (lus par la sonde de saccades).
- Piège `src/shared/movement/` (#138) : `WallSlide`, `GroundDetection`, `StepupSystem`, `HeadCollisionResolver`, `CharacterDimensions` gardent l'état d'UN seul personnage au niveau du module (`init(char)`), et filtrent `workspace.CurrentCamera` (nil côté serveur). Les bots devront les rendre par instance avant de les utiliser à plusieurs ; `WallSlide.init` parente aussi une sonde `penProbe` dans `workspace`.
- `src/client/systems/movement/PhysicsStepAir.luau`: étape physique aérienne (air accelerate Source + cap `AIR_SPEED_CAP`).
- `src/shared/movement/PhysicsStepGround.luau`: étape physique pour l'état au sol. Tout `src/shared/movement/` (pas de sol et ses dépendances) est partagé client/serveur, pour que les futurs bots bougent comme les joueurs (#138) ; le surf (`PhysicsStepAir`) reste côté client.
- `src/shared/movement/SlopeSystem.luau`: gestion des pentes et adaptation du mouvement.
- `src/shared/movement/StepupSystem.luau`: logique pour monter sur de petits obstacles.
- `src/shared/movement/WallSlide.luau`: glisse le long des murs/rampe avec conservation de normale surf si on avance vers la rampe.
- `src/client/systems/weapon/AnimationSoundSystem.luau`: gestion des marqueurs sons sur les AnimationTracks.
- `src/client/systems/weapon/HitscanSystem.luau`: raycast des armes à distance, traceur du tir et signalement de la touche au serveur.
- `src/client/systems/weapon/MeleeHitDetection.luau`: raycast melee et signalement de la touche au serveur (type d'attaque, les dégâts sont calculés côté serveur).
- `src/client/systems/weapon/ScopeSystem.luau`: gestion du scope (FOV, affichage de la lunette, sensibilité caméra) pour les armes à lunette.
- `src/client/systems/weapon/ViewmodelSystem.luau`: gestion du viewmodel, des animations et des sons des armes en vue FPS.
- `src/client/systems/weapon/WeaponSystem.luau`: logique client des armes, munitions, recharge et vitesse liée à l'arme.
- `src/client/systems/weapon/WeaponThirdPersonView.luau`: rendu client des armes 3e personne de tous les personnages (décalage procédural du grip pour tir/recharge/switch, modèle 3P masqué pour soi en 1re personne) et tenue du haut du corps des personnages armés (Transform des Motor6D posé en `PreSimulation`, après l'Animator, #107).
- `src/client/ui/FeedbackScreen.luau`: écran Feedback (message de 10 à 500 caractères envoyé au serveur, ENVOYER se tire).
- `src/client/ui/HUDRules.luau`: règles pures du HUD (paliers de vitesse, timer, classement, emplacements de la barre d'armes, file et textes du kill feed).
- `src/client/ui/KillFeed.luau`: kill feed en haut à droite (4 lignes, 5 s), affiché en partie vivant ou mort (`HUDRules.killFeedVisible`).
- `src/client/ui/Hitmarker.luau`: marqueur de touche confirmée par le serveur (X blanc à contour noir, rouge sur un tir à la tête, plus grand sur un kill).
- `src/client/ui/InfosScreen.luau`: écran Infos (surfer, commandes, crédits, à propos), même disposition que les Réglages, onglets à tirer.
- `src/client/ui/MainMenu.luau`: menu d'accueil (salle des miroirs) où l'on choisit en tirant : titre, onglets, fiche d'arme et sélecteur en texte à ombre, hitmarker en guise de curseur, impacts de balles.
- `src/client/ui/MenuCursor.luau`: hitmarker qui remplace le curseur sur tous les écrans du menu.
- `src/client/ui/MenuPage.luau`: gabarit des écrans secondaires du menu (bloc centré sur un voile, titre en texte pour Réglages en partie, choix et action de sortie en texte).
- `src/client/ui/MenuShot.luau`: tir sur un élément du menu (impact, puis action) et choix en texte à ombre décalée.
- `src/client/ui/RoundHUD.luau`: HUD en jeu (timer et rang, classement Tab, écran de réapparition, écran de fin de round).
- `src/client/ui/ScopeOverlay.luau`: lunette des armes à scope, dessinée sans image (masque rond et réticule en Frames).
- `src/client/ui/SettingsMenu.luau`: écran Réglages par catégories (SOURIS, TOUCHES, GRAPHISMES), à même la scène dans le menu (on règle en tirant), sur un voile sombre sans tir en partie (touche P) : sensibilités, sens de la molette et touche de chaque arme, ombres du soleil sur le poste du joueur (`Lighting.GlobalShadows`), RÉTABLIR par catégorie. Valeurs conservées via `LocalSettings`.
- `src/client/systems/settings/LocalSettings.luau`: copie client des réglages du joueur (chargement depuis le serveur, abonnés prévenus à chaque changement, envoi différé) et libellé d'une touche selon la disposition du clavier.
- `src/client/ui/Speedometer.luau`: affichage de la vitesse du joueur.
- `src/client/ui/WeaponBar.luau`: barre d'armes (remplace le Backpack Roblox) : silhouettes des armes, équipement par les touches et la molette réglées par le joueur, au toucher et à la manette ; inactive pendant que l'écran Réglages est ouvert.
- `src/client/ui/Transition.luau`: volets de transition entre le menu et le jeu.
- `src/client/ui/UIKit.luau`: briques communes des écrans (création d'Instances, texte au thème, tweens, icônes, mise à l'échelle).
- `src/server/DebugPlaytest.luau`: helper de playtest (Studio uniquement) : déclenché par un attribut joueur, enchaîne spawn, équipement, cible immobile et attaque, avec un PASS/FAIL par étape.
- `src/server/FeedbackService.luau`: réception des feedbacks côté serveur (longueur, délai entre deux envois, limite hebdomadaire).
- `src/server/CharacterSync.luau`: position des joueurs côté serveur : validation de la position envoyée par le client, racine serveur déplacée, relais aux autres clients (cf. « Position des personnages »).
- `src/server/KillZone.luau`: mort par chute : tue le joueur dont la position validée par `CharacterSync` passe sous `Maps.Map.KillHeight`.
- `src/server/RoundManager.luau`: boucle de round FFA (timer, kills/deaths par participant, fin de round, diffusion résultat), testée avec un faux bot (`tests/specs/RoundManager.spec.luau`).
- `src/server/Participants.luau`: registre des participants au round, joueurs et bots (inscription, personnage, recherche depuis un personnage), cf. « Participants, joueurs et bots ».
- `src/server/SettingsStore.luau`: DataStore des réglages du joueur (`PlayerSettings_v1`) : chargement à l'arrivée, réponse à `GetSettings`, réception validée de `SaveSettings`, écriture différée et au départ.
- `src/server/SpawnManager.luau`: gestion du spawn différé (RequestSpawn remote, LoadCharacter, lancement depuis le soleil ou point au sol, ForceField de protection).
- `src/server/StatsStore.luau`: DataStore stats joueur (kills/deaths/rounds), save périodique + déconnexion, robustesse load.
- `src/server/Validator.luau`: décision serveur des touches melee et hitscan d'un participant, joueur ou bot (cible, arme en main, partie touchée, portée, cadence), calcul des dégâts depuis `WeaponConfig` (zone du corps pour le hitscan, backstab pour la mêlée) et qualification d'une touche (hit/kill).
- `src/server/init.server.luau`: point d'entrée serveur — crée tous les RemoteEvents, orchestre SpawnManager, RoundManager, StatsStore.
- `src/shared/CameraConfig.luau`: constantes caméra (FOV, sensibilité et bornes du slider, pitch min/max, hauteurs, lerp speed, multiplicateur lunette et ses bornes).
- `src/shared/ParticipantRules.luau`: règles pures de l'identité joueur/bot (préfixe `BOT`, ids négatifs des bots, comptage dans les stats persistantes), testées (`tests/specs/ParticipantRules.spec.luau`).
- `src/shared/PlayerSettings.luau`: règles pures des réglages du joueur (valeurs par défaut, validation des données reçues, touches proposées et réservées, échange de touches entre emplacements, sens de la molette), testées (`tests/specs/PlayerSettings.spec.luau`).
- `src/shared/ScopeSensitivity.luau`: sensibilité à la lunette = sensi de base × ratio du zoom (`tan(fov/2) / tan(DEFAULT_FOV/2)`) × multiplicateur du joueur, testée (`tests/specs/ScopeSensitivity.spec.luau`). `ScopeSystem` passe le FOV de chaque niveau de zoom à `FPSCamera.setScoped`.
- `src/shared/CharacterSyncRules.luau`: règles pures de la synchro de position (forme d'un paquet, déplacement plausible, tampon et interpolation des autres joueurs), testées (`tests/specs/CharacterSyncRules.spec.luau`).
- `src/shared/CharacterAnimator.luau`: pipeline d'animation 3e personne des joueurs (état de mouvement → piste, fondus, vitesse de lecture) ; alimenté par `MovementController` (client, répliqué via l'Animator). `isAirborneAnimationId` permet aux autres clients de déduire d'une piste répliquée qu'un personnage est en l'air.
- `src/shared/CharacterAppearance.luau`: rig de référence (`StarterPlayer.StarterCharacter`, cloné pour la cible du helper de playtest) et application du skin commun (BodyColors + vêtements) côté serveur.
- `src/shared/CharacterConfig.luau`: rig/skin communs (couleurs, ids d'images Shirt/Pants/visage) et animations 3e personne (ids, fallbacks, seuils de vitesse, fondus).
- `src/shared/DebugPlaytestRules.luau`: règles pures du helper de playtest (choix de l'outil, marqueurs et dégâts attendus, visée, rapport PASS/FAIL).
- `src/shared/PerfMarkers.luau`: repères `PerfMarkers.wrap(nom, callback)` posés sur les boucles par frame (mouvement, caméra, viewmodel, armes, armes 3P, menu, timer de round) : nommés dans le MicroProfiler, chronométrés pour l'overlay.
- `src/shared/PerfRules.luau`: règles pures de l'environnement de performance (droit d'accès, écarts mémoire, coût des repères), testées (`tests/specs/PerfRules.spec.luau`).
- `src/shared/MemoryTracker.luau`: relevés mémoire `[Perf] MEM` (client : démarrage, spawn, fin de round ; serveur : démarrage, fin de round, départ d'un joueur). Catégories lues seulement si `Stats.MemoryTrackingEnabled` (désactivé dans le client publié).
- `src/shared/FrameProbeRules.luau`: règles pures de la sonde de saccades (classement HITCH/STUTTER/ROTATION/TELEPORT, cause probable, bilan), testées (`tests/specs/FrameProbeRules.spec.luau`).
- `src/shared/GameConfig.luau`: constantes jeu (ROUND_DURATION=300, RESPAWN_DELAY=2.5, RESULT_DURATION=6, AUTO_SAVE_INTERVAL=120, SPAWN_PROTECTION=2.5).
- `src/shared/SpawnLaunch.luau`: règles pures du lancement depuis le soleil (vitesse, angles de caméra, noms des attributs posés sur le personnage), testées (`tests/specs/SpawnLaunch.spec.luau`).
- `src/shared/HitZones.luau`: zones du corps touchées (tête, torse, bras, jambes), multiplicateurs de dégâts des armes à distance et règle de calcul.
- `src/shared/LadderRules.luau`: règles pures des échelles (grimpe façon Source selon le regard, saut pour s'en détacher), testées (`tests/specs/LadderRules.spec.luau`).
- `src/shared/MapRules.luau`: règles pures de la map (volume et vitesse des boosts, hauteur de mort, tir balistique), testées (`tests/specs/MapRules.spec.luau`).
- `src/shared/MovementConfig.luau`: constantes physique du mouvement uniquement (vitesses, accel, friction, saut, pentes, bhop, réseau, hitbox).
- `src/shared/MovementState.luau`: structure d'état partagée pour le mouvement du joueur.
- `src/shared/NetworkProtocol.luau`: noms des RemoteEvents et helper getRemote(name). Remotes : MeleeDamage, HitscanDamage, HitConfirm, RequestSpawn, RoundState, ScoreUpdate, RoundResult, PlayerDied, CharacterSync (non fiable), WeaponAction, SendFeedback, FeedbackAck, DebugPlaytest (créé uniquement dans Studio).
- `src/shared/PhysicsUtils.luau`: fonctions utilitaires pour la physique.
- `src/shared/StepTiming.luau`: tick fixe du mouvement (64 Hz, #96) : ticks à jouer dans une frame rendue et fraction d'interpolation de l'affichage, testé (`tests/specs/StepTiming.spec.luau`).
- `src/shared/UITheme.luau`: tokens de style de l'interface (couleurs, polices, tailles, durées, courbes).
- `src/shared/WeaponConfig.luau`: définitions partagées des armes et de leurs paramètres par défaut (dont `ThirdPerson` : échelle, grip, pose 3P).
- `src/shared/WeaponThirdPerson.luau`: arme 3e personne des joueurs : construction du modèle 3P depuis `ViewModels`, grip soudé à la main, tenues du haut du corps (`POSES`, générées par `tools/anim/poses3p/export_pose.js`), actions répliquées en attributs (`Weapon3PAction`/`Weapon3PActionAt`), règles pures (grip, décalages d'action, cible de tenue par articulation, visibilité).

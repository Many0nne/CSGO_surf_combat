# Performance et saccades

## Les outils, et quand s'en servir

| Question | Outil |
|---|---|
| Le jeu tient-il ses FPS ? Est-ce le CPU, le GPU, la map ou nos scripts ? | overlay F3 (Studio et jeu publié) |
| Quel réglage de rendu coûte (ombres, Atmosphere, effets, translucides) ? | banc F4 (jeu publié de préférence) |
| Quelle frame saccade, et pourquoi ? | sonde `FrameProbe` (Studio) |
| Qu'est-ce qui coûte, à l'intérieur d'une frame lente ? | MicroProfiler (Ctrl+F6) : nos boucles y portent leur nom |
| La mémoire grimpe-t-elle au fil des spawns et des rounds ? | relevés `[Perf] MEM` (console F9, client et serveur) |
| Combien la map coûte-t-elle (pièces, ombres, transparences) ? | `lune run tools/perf/audit_map.luau` (sans Studio) |

Pour comparer deux postes : ouvrir l'overlay sur chacun et faire le même parcours dans le jeu publié, puis relever les
lignes `[Perf] BILAN` de la console F9 (onglet Log, filtre `[Perf]`). Le réglage graphique est dans la ligne : à
comparer à réglage égal (fixer la qualité à la main plutôt qu'« auto »).

## Overlay F3

`src/client/debug/PerfOverlay.luau`. Il s'ouvre et se ferme avec **F3** dans Studio, et dans le jeu publié pour le seul
créateur du jeu (`game.CreatorId`, jeu appartenant à un utilisateur ; un jeu de groupe ne l'a que dans Studio). Pour les
autres joueurs, rien n'est branché. Même effet par l'attribut joueur `PerfOverlay` (`true` ouvre, `false` ferme), utile
pour une mesure pilotée par le MCP Studio, dont la simulation de touches n'atteint pas le jeu :
`game.Players:GetPlayers()[1]:SetAttribute("PerfOverlay", true)` (contexte serveur, l'attribut est répliqué). Le texte est rafraîchi deux fois par seconde pour que l'overlay ne pèse pas sur la
mesure.

| Ligne | Lecture |
|---|---|
| `qualité`, résolution | réglage graphique du joueur (`auto` ou 1-10) et taille de la fenêtre |
| `FPS médian`, `p99`, `max` | sur les 600 dernières frames (environ 10 s) |
| `CPU rendu`, `GPU` | temps de préparation du rendu (CPU) et de dessin (GPU) d'une frame. Si le GPU dépasse 16 ms, c'est la scène qui limite (ombres, transparences, résolution) ; si c'est le CPU, ce sont les draw calls ou les scripts |
| `Heartbeat`, `Physique` | temps du pas Heartbeat (nos scripts compris) et de la simulation physique |
| `Draw calls`, `triangles` | scène et passe d'ombres séparées : une passe d'ombres proche de la scène signale des ombres à couper |
| `Instances`, `pièces` | totaux du jeu ; `mobiles` et `contacts` doivent rester proches de 0 (tout est ancré, le perso est déplacé par CFrame) |
| `Mémoire`, catégories | Mo par `Enum.DeveloperMemoryTag` (Lua, Instances, Textures, Pièces…). Le client publié ne suit pas la mémoire par catégorie (`Stats.MemoryTrackingEnabled` faux) : seul le total s'affiche. Lire une catégorie quand même écrit un warning par appel (22 000 en une session avant la correction) |
| `Scripts` | coût de nos boucles par frame (`PerfMarkers`) : ms/frame, appels/frame, max. **Plus d'un appel par frame pour une boucle signale une connexion branchée en double** (fuite au respawn, par exemple) |

Tant qu'il est ouvert, une ligne `[Perf] BILAN` résume toutes les 10 s FPS, p99, max, CPU/GPU, draw calls, mémoire, réglage
graphique et coût des scripts. À la fermeture, un dernier bilan est écrit.

## Banc F4

`src/client/debug/PerfBench.luau`, mêmes droits que l'overlay (Studio, ou créateur du jeu publié). **F4** coupe les
leviers de rendu l'un après l'autre, sur le seul poste qui le lance :

- ombres du soleil ;
- `Atmosphere` ;
- effets actifs de `Lighting` (Bloom, SunRays…) ;
- pièces translucides de chaque dossier de la map (`LocalTransparencyModifier`).

Puis tout ensemble, et une référence de contrôle. Chaque phase dure 8 s (2 s de stabilisation, 6 s mesurées) et écrit
une ligne `[Perf] BANC` : GPU moyen (écart à la référence), p95, CPU moyen, durée médiane et p99 des frames. Tout est
rétabli à la fin ; rappuyer sur F4 annule après la phase en cours. Attribut joueur `PerfBench` = true : même effet,
pour un banc piloté par le MCP.

Conditions : **en jeu, pas au menu** (avec `StreamingEnabled`, la map n'est pas chargée au menu, le banc le signale),
immobile, la fenêtre au premier plan du début à la fin. Une phase pendant laquelle la fenêtre a perdu le focus est
marquée `INVALIDE` : dans Studio, quitter la fenêtre pour écrire ailleurs suffit à fausser le banc (GPU à 0, 15 FPS).
Les écarts de moins de 2 ms entre phases sont du bruit, d'où la référence de contrôle en fin de banc.

## Repères de scripts (`PerfMarkers`)

`src/shared/PerfMarkers.luau` : `PerfMarkers.wrap("nom", callback)` entoure un callback sans valeur de retour (Heartbeat,
RenderStepped, BindToRenderStep). Le repère est toujours posé (`debug.profilebegin`, coût négligeable si le profiler est
fermé), et il est chronométré seulement quand l'overlay est ouvert. Repères posés : `mouvement`, `caméra`, `viewmodel`,
`armes`, `armes 3P`, `menu 3D`, `curseur menu` (client), `srv round` (serveur). Toute nouvelle boucle par frame doit
passer par `wrap`.

Dans le MicroProfiler (Ctrl+F6, puis pause pour figer une frame lente), ces noms apparaissent sous `Heartbeat` ou
`RenderStep` (`mouvement`, `caméra` et `viewmodel` sont sous `RenderStep`) : on voit si une frame lente vient de nos scripts ou du moteur (rendu, physique, GC).

## Relevés mémoire (fuites)

`src/shared/MemoryTracker.luau` écrit une ligne `[Perf] MEM` à chaque événement du cycle de vie :

- client (Studio ou créateur) : démarrage, 3 s après chaque spawn, 3 s après chaque fin de round, ouverture de l'overlay ;
- serveur (toujours actif, la console serveur n'est lisible que par les développeurs) : démarrage, fin de round (une fois
  les personnages détruits), 5 s après le départ d'un joueur.

Chaque ligne donne le total, l'écart depuis le relevé précédent et depuis le premier, le nombre d'Instances, le tas Lua et
les catégories qui ont le plus varié. Méthode : enchaîner une dizaine de morts et deux ou trois rounds. Une valeur qui
monte à chaque spawn sans jamais redescendre (Instances, `LuaHeap`, `Signals`) est une fuite ; une hausse unique au premier
spawn est un chargement (textures, sons).

## Audit statique de la map

```bash
lune run tools/perf/audit_map.luau                              # Dizzy par défaut
lune run tools/perf/audit_map.luau assets/rbx/Maps/<Nom>.rbxm
```

Par dossier : pièces, coins (`WedgePart`), pièces qui projettent une ombre, translucides, invisibles, `CanCollide`,
`CanQuery`, `CanTouch`, ombres de petites pièces (moins de 2 studs) et de pièces invisibles, matières distinctes. Puis les
lumières (ombres, portée) et les plus grandes surfaces translucides. Le chiffre ne dit pas le coût : à confirmer par
l'overlay (draw calls d'ombres, GPU) avant et après une modification.

## Diagnostiquer une saccade

Une saccade a trois origines possibles, et chacune se corrige différemment. Il faut la classer avant de chercher :

| Type | Ce qu'on mesure | Où chercher |
|---|---|---|
| `HITCH` : frame lente | un `dt` nettement au-dessus de la médiane | MicroProfiler (Ctrl+F6), onglet Scripts de la console F9, `gcΔ` (GC) |
| `STUTTER` : frames régulières, déplacement irrégulier | une vitesse rendue isolée alors que le `dt` est normal | la `source` de la ligne (ci-dessous) |
| `ROTATION` : rotation irrégulière | un pic isolé de vitesse de yaw | entrée souris, `FPSCamera.setAngles` |

Toujours refaire le même parcours dans le client Roblox publié avant de conclure. Studio ajoute sa propre charge
(Explorer, Properties, synchro Rojo, Output).

## Sonde `FrameProbe` (Studio uniquement)

`src/client/debug/FrameProbe.luau` contient la mesure, et `src/shared/FrameProbeRules.luau` les règles, testées.
Pendant un playtest, dans la barre de commande (contexte serveur ou client) :

```lua
game.Players:GetPlayers()[1]:SetAttribute("FrameProbe", true)  -- false pour arrêter (affiche un dernier bilan)
```

La sonde ne parle que pour une frame anormale, avec au plus une ligne tous les 0,25 s par type (les suivantes sont
comptées et annoncées à la ligne suivante). Elle écrit aussi un `BILAN` toutes les 10 s (FPS médian, p99, max,
nombre d'anomalies par type). Chaque ligne indique le temps écoulé depuis l'activation (`t=`) : on peut ainsi la
rapprocher du moment où la saccade a été ressentie.

Pas besoin de garder le playtest ouvert pour lire le résultat : Studio écrit toute la sortie Output dans
`%LOCALAPPDATA%\Roblox\logs\*_Studio_*_last.log` (un fichier par session Studio). Un script Roblox ne peut pas écrire
de fichier lui-même. Pour extraire la session : `grep "\[FrameProbe\]" <fichier> | grep -v SetAttribute`.

Champs : `dt` (frame rendue), `steps` (nombre de pas de mouvement depuis le rendu précédent, 1 attendu), `simDt`
(temps simulé pendant ces pas), `disp` (déplacement de la racine), `vRendue` (= `disp/dt`), `vSim` (vitesse du
MovementController), `yaw` (degrés/s), `gcΔ` (mémoire Lua, une forte baisse signale un passage du GC), `arme`.

Causes d'un `STUTTER` (`source=`) :

- `pas_physique_manquant` ou `pas_physique_double` : 0 ou 2 pas de mouvement entre deux rendus. Le perso avance de 0 ou
  de 2 pas sur une frame. Depuis que le mouvement tourne sur le rendu, seul un `HITCH` découpé en pas peut en donner 2.
- `simulation` : la vitesse simulée elle-même fait un pic (collision, rampe, boost, `commitMove`).
- `position_hors_simulation` : la racine a bougé autrement que ce que prévoyait la vitesse simulée (correction
  serveur, téléportation partielle, step-up ou éjection de `WallSlide`).
- `timing_rendu_vs_simulation` : un pas normal, mais le temps rendu diffère du temps simulé. Cause dominante quand le
  mouvement tournait sur Heartbeat (voir « Rythme du mouvement ») ; elle ne devrait plus apparaître.

Un pic isolé est une frame qui s'écarte de plus de 30 % de ses deux voisines, quand ces voisines s'accordent entre
elles à 15 % près. Une accélération progressive (surf, boost) n'est donc pas signalée. En dessous de 2 studs/s et de
20 °/s, rien n'est jugé.

## Rythme du mouvement (#88)

Le perso est déplacé par script (racine ancrée), dans `MovementController`. Sa boucle tourne **sur le rendu, juste
avant la caméra** (`BindToRenderStep`, priorité `Camera - 1`), avec le `dt` de la frame rendue : le déplacement affiché
correspond au temps affiché, et la caméra lit dans la même frame la position que le pas vient de poser.

- Avant (jusqu'au 06/11/2026), la boucle tournait sur `Heartbeat`. Son `dt` (de 14 à 21 ms) suit un autre chronomètre
  que le rendu, et le déplacement par image variait d'environ 30 % : plus d'un stud d'écart à 200 studs/s, d'où les
  saccades en surf rapide (54 `STUTTER` `timing_rendu_vs_heartbeat` sur 150 s, mesure du 03/11).
- La physique reste à `dt` variable, comme avant : le ressenti ne change pas à FPS stable. Piste écartée pour l'instant :
  un tick fixe (64 Hz, comme Source) avec interpolation de la caméra rendrait la physique indépendante du FPS, mais
  ajoute jusqu'à un tick de retard et change le ressenti au-dessus de 60 FPS.
- Une frame lente est découpée en pas de 1/30 s au plus (`StepTiming`, 6 pas au plus) au lieu d'être tronquée : le perso
  parcourt tout le temps écoulé, une frame lente ne se voit plus qu'une fois.
- Ne pas remettre d'interpolation de position dans `FPSCamera` : la position est déjà celle de la frame.

## Ombres de la map (#88)

Les ombres du soleil sont le premier coût de rendu de Dizzy : la passe d'ombres faisait plus de draw calls que la scène,
et la qualité graphique au maximum faisait ramer (retour du 06/11/2026). Corrections :

- `CastShadow` coupé par le générateur (règle et calcul : `docs/maps.md`, « Règles de construction ») sur les petites
  pièces et sur les pièces dont l'ombre ne se voit pas. Pièces qui projettent une ombre : de 15 319 à 1 949.
  Contrôle indépendant sur 20 000 points pris au hasard sur les surfaces, entre les points d'échantillonnage du
  calcul : 1 point perd son ombre (un liseré), aucun n'en gagne.
- Réglage « Ombres » dans Réglages : coupe `Lighting.GlobalShadows` sur le poste du joueur, pour les petites machines.
  Comme les autres réglages, il n'est pas sauvegardé (`SettingsStore` est vide).
- Nuages : 2 nappes translucides au lieu de 4.
- Armes : ni le viewmodel (`ViewmodelSystem`) ni l'arme en 3e personne (`WeaponThirdPerson.attach`) ne projettent
  d'ombre. Leurs maillages faisaient **108 000 des 111 000 triangles de la passe d'ombres** (AWP en main, banc
  ci-dessous), pour une ombre qu'on ne voit pas. Tout nouveau modèle cloné près de la caméra doit couper `CastShadow`.

Banc du 06/11/2026 (Studio au premier plan, qualité 10, fenêtre 1291×647, 3 vues fixes, chaque levier coupé l'un après
l'autre) : triangles d'ombre de 111k à 3k en coupant les ombres des armes. Mais le temps par image (15 à 24 ms) ne bouge
avec **aucun** levier (armes, Bloom et SunRays, nuages, habillage masqué, toutes les ombres du soleil) : il varie plus
d'une mesure à l'autre que d'un réglage à l'autre. En playtest Studio, client et serveur tournent dans le même
processus, avec l'éditeur : ce n'est pas le rendu de la map qui limite. **Le gain réel ne se juge que dans le client
publié.**

Piège de mesure : **Studio ne rend presque rien quand sa fenêtre n'est pas au premier plan** (pas de passe d'ombres,
GPU à 0, peu de triangles). Une mesure pilotée par le MCP pendant qu'on travaille dans une autre fenêtre ne vaut rien
pour le rendu : mesurer Studio au premier plan, ou dans le client publié.

## Mesure du 2026-11-06 (Studio, Dizzy, qualités 10, 5 et 1, après le passage du mouvement sur le rendu)

Ressenti inchangé par le passage du mouvement sur le rendu. Les saccades suivent la qualité graphique :

| Qualité | GPU | CPU rendu | p99 | Ressenti |
|---|---|---|---|---|
| 10/10 | 13,4 à 15 ms | 11 à 14,5 ms | 39 ms | lag, saccades en mouvement |
| 5/10 | 3 à 5 ms | 10 à 12,6 ms | 34 à 36 ms | moindre |
| 1/10 | 1,6 à 3 ms | 9 à 12 ms | 19 à 22 ms | quasi rien |

Ce sont de vraies frames perdues (CPU et GPU proches des 16,7 ms d'une frame), pas un déplacement irrégulier. La
géométrie n'y est pour rien : 16 à 32 draw calls, moins de 15k triangles. Dans Studio, le CPU de rendu est 3 à 4 fois
plus haut que dans le client publié (3 ms) : la qualité 10 reste à mesurer dans le client publié (banc F4). Banc dans
Studio à qualité 10 (MCP) : couper les ombres, l'Atmosphere ou les nuages ne fait rien gagner au-delà du bruit ; les
autres phases sont faussées par une perte de focus.

`Workspace` (réglé dans la place, pas dans `default.project.json`) : `StreamingEnabled` actif, `StreamingMinRadius` 64,
`StreamingTargetRadius` 1024, `StreamingIntegrityMode` `PauseOutsideLoadedArea`. En surf rapide, le perso peut sortir de
la zone chargée : chargements en continu pendant le mouvement, et pause du joueur si la zone n'est pas prête. Piste à
mesurer (#88).

## Mesure du 2026-11-06 (client publié, Dizzy, qualité auto, après #91)

Parcours au couteau et à l'AWP, overlay ouvert, 7 bilans de 10 s :

- 59 FPS médian (plafond à 60), p99 de 22 à 27 ms, max de 25 à 42 ms ; 73,6 ms au spawn.
- **Le rendu ne limite plus** : CPU de rendu 2,9 à 4,0 ms, GPU 5,9 à 15,0 ms, draw calls 20 à 31 (scène) et 12 à 98
  (ombres), triangles 10k à 70k.
- Nos scripts : `mouvement` 0,2 ms par frame, le reste moins de 0,05 ms.
- Mémoire client environ 1 540 Mo, stable entre les bilans. Serveur : +84 Mo et +683 Instances entre le démarrage et la
  première fin de round (un seul relevé : à suivre sur plusieurs rounds, #77).
- 22 000 warnings « Memory tracking is currently disabled » : l'overlay lisait les catégories de mémoire, que le client
  publié ne suit pas. Corrigé (`MemoryTracker.readTags`).

Conclusion : le GPU et la map ne sont plus en cause dans le client publié. La géométrie de la map (fusion des coins,
plafonds, faces jamais vues) n'est pas retouchée tant qu'une mesure ne la désigne pas. Les saccades ressenties viennent
du rythme du mouvement (section ci-dessus).

## Mesure du 2026-11-06 (Studio, Dizzy, fenêtre de jeu 1291×647, qualité auto, 5 morts, perso immobile)

Première mesure avec l'overlay, pilotée par le MCP. Le perso ne bouge pas, car la simulation de touches n'atteint pas
le jeu : surf et combat restent à mesurer à la main, dans le client publié.

- Rythme : 51 à 60 FPS médian, p99 de 24 à 47 ms. Les pics de 135 et 344 ms tombent sur les spawns (chargement du
  personnage et du viewmodel).
- **Le GPU limite, pas nos scripts** : GPU de 11 à 18 ms contre 4 à 5 ms de CPU de rendu, sur une petite fenêtre. En
  plein écran 1080p, le GPU dépasse probablement les 16 ms d'une frame à 60 FPS. Les draw calls de la passe d'ombres
  (15 à 78) dépassent ceux de la scène (13 à 33). Audit de la map : 15 300 pièces sur 16 000 projettent une ombre, dont
  6 300 de moins de 2 studs, et 4 nappes de nuages translucides de 3 000 × 3 000. Pistes à essayer en premier
  (#88) : `CastShadow` coupé sur les petites pièces et les plafonds, nappes de nuages.
- Nos boucles coûtent moins de 0,3 ms par frame au total (`mouvement` environ 0,1 ms, `menu 3D` 0,45 ms dans le menu).
- **Fuite confirmée** : `mouvement` passe à 2, puis 3,6, puis 4,9 appels par frame au fil des respawns. `MovementController.init`
  branche un nouveau Heartbeat à chaque spawn sans débrancher l'ancien (l'ancien sort tout de suite, car `hrp.Parent`
  vaut nil, mais garde en vie sa closure et l'ancien personnage). Le nombre d'Instances reste stable (71 625), donc les
  personnages sont bien détruits côté moteur. Le coût monte avec le nombre de morts dans une session (#77).
  Corrigé (#88) : la connexion est gardée et débranchée au spawn suivant.
- Mémoire client en Studio : de 1 650 à 2 150 Mo, dont l'essentiel en `Internal` et `LuaHeap` (Studio et plugins
  compris). Ce chiffre ne se compare qu'au client publié.

## Mesure du 2026-11-03 (Studio, carte ville, environ 150 s de jeu)

- 60 FPS médian, p99 entre 19 et 22 ms. 5 `HITCH` de 35 à 58 ms, sans passage du GC (`gcΔ` faible) : la performance
  n'est pas la cause principale.
- Cause dominante : 54 `STUTTER` signalés avec `timing_rendu_vs_heartbeat`. Le `dt` de Heartbeat (de 14 à 21 ms) varie
  indépendamment du `dt` rendu, et le perso avance de `vitesse × hbDt` à chaque image affichée. Le déplacement par
  image varie donc d'environ 30 %. C'est invisible à basse vitesse, mais à 200 studs/s cela fait plus d'un stud
  d'écart, d'où des saccades surtout en surf rapide, sans scénario reproductible.
- Cause secondaire : 13 `position_hors_simulation` au sol (déplacement 30 à 45 % supérieur à la vitesse simulée),
  probablement liés au step-up ou à la projection de pente.
- `ROTATION` : environ 3 alertes par seconde. Ce sont plus probablement les rapports de la souris répartis
  irrégulièrement entre les frames (souris 125 Hz à 60 FPS : 2 ou 3 rapports par frame) qu'un bug.

## Pièges connus

- Interpoler la position de la caméra entre deux `Heartbeat` (ancien `FPSCamera.updateRoot`, supprimé) crée des
  saccades : `Heartbeat` tourne une fois par frame, pas à 60 Hz fixe, donc l'`alpha` basé sur `os.clock()` varie d'une
  frame à l'autre. Le mouvement tourne maintenant sur le rendu, l'interpolation n'a plus lieu d'être.
- Tronquer `dt` (ancien `math.min(dt, 1/30)`) fait voir un `HITCH` deux fois : l'image fige, puis le déplacement est
  trop court. Découper en pas (`StepTiming`).

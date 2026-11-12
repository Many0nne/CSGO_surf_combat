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
| Combien coûte le serveur (bots, round) ? Quelle frame serveur est lente ? | sonde serveur `PerfServer` (lignes `[Perf] SRV`, console F9 > Server) |

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

## Sonde serveur `PerfServer` (#145)

`src/server/ServerPerf.luau`. Les repères `PerfMarkers` du serveur (`srv bots`, `srv round`…) ne sont chronométrés que
si `PerfMarkers.timing` est vrai ; l'overlay F3 ne le règle que sur le client. La sonde le règle sur le serveur :
`workspace:SetAttribute("PerfServer", true)` (`false` : dernier bilan puis arrêt). Toujours disponible, comme les
relevés mémoire du serveur : la console serveur n'est lisible que par les développeurs. Une ligne toutes les 10 s :

```
[Perf] SRV t=60s Heartbeat méd 28.2ms p99 57.9ms max 59.7ms | bots 5 (4 en jeu) | anti-triche 5 suivi(s) | mém … | scripts : srv bots 2.0ms×1.0 (max 7.8),
bots mouvement …, bots chemin …, bots cerveau …, srv round …
```

- `anti-triche N suivi(s)` : participants dont le `Validator` retient encore cadence, equip ou chargeur
  (`Validator.trackedCount`). Il doit retomber quand les bots sont retirés (`DebugBots` à 0) : s'il ne redescend pas,
  une table indexée par participant fuit (#218, `docs/anticheat.md` « Retrait d'un participant »). Un `require` du
  Validator depuis `execute_luau` ne lit pas ces tables (autre instance des modules) : lire cette ligne.

- `Heartbeat méd/p99/max` : durée des frames serveur. Dans Studio, elle suit le client (même processus) : ne vaut que
  pour comparer deux versions.
- Repères des bots : `srv bots` (total) = `bots mouvement` (physique, **recherche de chemin comprise**) + `bots
  cerveau` (perception, état) + apparitions ; `bots chemin` isole la recherche de chemin (appels par frame < 1 :
  une recherche étalée sur plusieurs ticks). `×N` = appels par frame, `(max …)` = pire appel en ms.
- Piège : le `max` dit ce qui fait la saccade, la moyenne non. Une moyenne de 2 ms cachait des pics de 150 ms.
- Méthode pour les bots : `workspace:SetAttribute("DebugBots", 5)`, la sonde, puis un run `DebugPlaytest` pour lancer
  la partie (le round démarre ; les bots, retirés pendant le run, reviennent à la fin), pas `RequestSpawn:FireServer()`
  (cf. `CLAUDE.md`) ; attendre 2 minutes de jeu après la fin du run.

## Coût de la population maximale de bots (#145, mesure du 2026-11-10)

Studio, Dizzy, 5 bots (`MAX_BOTS`), qualité 10, fenêtre de jeu 1291×647, joueur immobile, 2 min de jeu après
apparition, avec l'overlay F3 et la sonde `PerfServer`. Studio fait tourner client, serveur et éditeur dans un seul
processus : les chiffres en ms ne valent que pour comparer, le jugement final se fait dans le client publié.

| | Avant (A* complet) | Après (A* étalé, poids 2) |
|---|---|---|
| `srv bots` moyenne par frame | 2,0 à 4,5 ms | 1,8 à 3,5 ms |
| `srv bots` pire appel | 48 à 255 ms | 8 à 20 ms (28 ms à l'apparition des 5 bots) |
| `bots chemin` pire appel | 22 à 128 ms | 1,7 à 4 ms |
| `bots cerveau` moyenne / pire | 0,2 à 0,4 / 1 à 3 ms | idem |
| `Heartbeat` serveur méd / p99 | 28-34 / 59-107 ms | 27-38 / 55-81 ms |

- **Coût moyen des bots : environ 0,5 ms par bot et par frame** (mouvement 85 %, cerveau 12 %), soit 2 à 3,5 ms pour 5.
  La physique est celle du joueur (`CharacterMotor`, 64 Hz) : deux ticks par frame à 30 FPS, un à 60.
- Le `Heartbeat` serveur médian est le même **sans bot** en jeu (28,2 à 29 ms avant l'apparition) et avec 5 : les bots ne
  changent pas la cadence de Studio, qui est limitée par le rendu (GPU 23-30 ms dans cette petite fenêtre).
- **Pics corrigés** : à chaque nouvelle destination, `NavRules.findPath` explorait jusqu'aux 29 000 cases (80 à 150 ms
  dans Studio) ; voir `docs/bots.md` (« Suivi de chemin »). Le pic de 450 à 790 ms du `Heartbeat` à l'apparition du
  joueur est le chargement de son personnage (client), présent avant les bots.
- **Client** (overlay F3, avec 5 bots en jeu et leurs armes 3P) : `autres joueurs` 0,35 à 0,42 ms par frame, `armes 3P`
  0,25 à 0,40 ms, `tenue 3P` 0,15 à 0,2 ms (2 appels par frame : `PreAnimation` et `PreSimulation`, normal),
  `mouvement` 0,2 à 0,3 ms. Au total moins de 1,5 ms par frame pour les 5 bots, contre moins de 0,1 ms sans bot.
  FPS (34 à 35) et p99 (58 à 68 ms) identiques avec et sans bots dans Studio ; mémoire client stable (≈ +0 Mo entre
  les spawns, pas de fuite visible : Instances 73 086 à 73 287 d'un spawn à l'autre).
- Mémoire serveur : `Lua` autour de 30 à 45 Mo pendant les combats (apparitions et morts de bots), sans tendance.
- **Reste à faire dans le client publié** (le critère « aucune nouvelle saccade » ne se juge que là) : parcours de 2 à
  3 minutes avec 5 bots, overlay F3 ouvert, comparer `FPS médian`, `p99` et `max` des lignes `[Perf] BILAN` à ceux d'une
  partie sans bot (`DebugBots` = 0), même qualité fixée à la main.

## Streaming désactivé (#88)

`Workspace.StreamingEnabled` vaut **false**, fixé dans `default.project.json` (avant, réglage de la place : activé, rayon
minimal 64 studs, `PauseOutsideLoadedArea`). Avec le streaming, le client ne charge la map qu'autour du personnage : en
surf rapide (200 studs/s et plus), il charge et décharge en continu pendant le mouvement, et le moteur peut mettre le
joueur en pause s'il sort de la zone chargée. Le gain se voit **dans Studio** (client, serveur et éditeur dans le même
processus) : en mouvement à qualité 10, p99 de 39 à 31 ms et max de 49-70 à 37 ms. Dans le client publié, le ressenti
n'a pas changé : le chargement n'y posait pas problème. Une map de la taille de Dizzy (16 000 pièces) se charge en
entier sans difficulté, et le mouvement (raycasts côté client) a besoin de toute la géométrie autour du joueur. Ne pas
le réactiver sans mesurer en mouvement, dans Studio et dans le client publié.

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

Conditions : **en jeu**, pas au menu (si le streaming était réactivé, la map n'y serait pas chargée : le banc le signale),
immobile, la fenêtre au premier plan du début à la fin. Une phase pendant laquelle la fenêtre a perdu le focus est
marquée `INVALIDE` : dans Studio, quitter la fenêtre pour écrire ailleurs suffit à fausser le banc (GPU à 0, 15 FPS).
Les écarts de moins de 2 ms entre phases sont du bruit, d'où la référence de contrôle en fin de banc.

## Repères de scripts (`PerfMarkers`)

`src/shared/PerfMarkers.luau` : `PerfMarkers.wrap("nom", callback)` entoure un callback sans valeur de retour (Heartbeat,
RenderStepped, BindToRenderStep). Le repère est toujours posé (`debug.profilebegin`, coût négligeable si le profiler est
fermé), et il est chronométré seulement quand l'overlay est ouvert. Repères posés : `mouvement`, `caméra`, `viewmodel`,
`armes`, `armes 3P`, `tenue 3P` (sous `PreSimulation`), `menu 3D`, `curseur menu`, `autres joueurs` (client),
`srv round`, `srv bots` et ses sous-repères `bots mouvement`, `bots cerveau`, `bots chemin` (serveur, sonde `PerfServer`). Toute nouvelle boucle par frame doit
passer par `wrap`.

Dans le MicroProfiler (Ctrl+F6, puis pause pour figer une frame lente), ces noms apparaissent sous `Heartbeat` ou
`RenderStep` (`mouvement`, `caméra` et `viewmodel` sont sous `RenderStep`, `tenue 3P` sous `PreAnimation` et
`PreSimulation`) : on voit si une frame lente vient de nos scripts ou du moteur (rendu, physique, GC).

## Relevés mémoire (fuites)

`src/shared/MemoryTracker.luau` écrit une ligne `[Perf] MEM` à chaque événement du cycle de vie :

- client (Studio ou créateur) : démarrage, 3 s après chaque spawn, 3 s après chaque fin de round, ouverture de l'overlay ;
- serveur (toujours actif, la console serveur n'est lisible que par les développeurs) : démarrage, début de round (avant
  le premier personnage), fin de round (6 s après la destruction des personnages), 5 s après le départ d'un joueur.

Chaque ligne donne le total, l'écart depuis le relevé précédent et depuis le premier, le nombre d'Instances, le tas Lua et
les catégories qui ont le plus varié. Méthode : enchaîner une dizaine de morts et deux ou trois rounds. Une valeur qui
monte à chaque spawn sans jamais redescendre (Instances, `LuaHeap`, `Signals`) est une fuite ; une hausse unique au premier
spawn est un chargement (textures, sons).

### Mémoire serveur sur plusieurs rounds (#95)

Studio fausse la mémoire serveur : client, serveur et éditeur y partagent un seul processus. Un round y a donné +1 665
Instances et +270 Mo de `LuaHeap`. Il faut donc mesurer dans le jeu publié, et un round dure 5 min
(`GameConfig.ROUND_DURATION`). Pour enchaîner les rounds plus vite, l'attribut Workspace `RoundDuration` (en secondes,
10 au minimum, règle `PerfRules.roundDuration`) remplace cette durée à chaque démarrage de round. Sans l'attribut, rien
ne change.

1. Jeu publié, console F9 > Server, ligne de commande serveur : `workspace:SetAttribute("RoundDuration", 60)`.
2. Jouer trois ou quatre rounds, avec quelques morts par round. Revenir au menu à chaque fin de round.
3. F9 > Server > Log, filtre `[Perf] MEM` : une ligne au début et une à la fin de chaque round.
4. Lire l'écart entre deux `début de round` consécutifs. S'il retombe près de zéro après le premier round, ce n'est
   pas une fuite : c'est le chargement du premier round. S'il est du même ordre à chaque round, c'est une fuite : la
   catégorie qui monte indique où chercher.
5. Remettre la durée normale : `workspace:SetAttribute("RoundDuration", nil)`. L'attribut disparaît de toute façon au
   redémarrage du serveur.

L'attribut est lu au démarrage du round : le régler pendant un round ne change que les rounds suivants.

Mesure du 2026-11-06 (Studio, Dizzy, un joueur, un round de 300 s puis trois de 60 s) : **pas de fuite**.

| Relevé serveur | Total | Instances | Écart Instances |
|---|---|---|---|
| #1 démarrage | 1 703 Mo | 76 454 | |
| #2 début de round 1 | 2 358 Mo | 78 115 | +1 661 |
| #3 fin de round 1 | 2 599 Mo | 78 120 | +5 |
| #4 début de round 2 | 2 607 Mo | 78 120 | 0 |
| #5 fin de round 2 | 2 607 Mo | 78 120 | 0 |
| #6 début de round 3 | 2 614 Mo | 78 120 | 0 |
| #7 fin de round 3 | 2 615 Mo | 78 120 | 0 |

- Les +1 661 Instances et +238 Mo de `LuaHeap` (l'écart cité dans #95) arrivent **avant le premier round** : entrée du
  joueur et chargement du client. Dans Studio, client et serveur partagent un processus : les catégories du serveur
  comptent aussi le client. Le round 1 ajoute encore 241 Mo (dont `LuaHeap` +73, `Internal` +59), une seule fois.
- Ensuite, Instances fixes à 78 120 et total qui varie de -0,5 à +8,4 Mo d'un relevé à l'autre, sans tendance : ce que
  le serveur crée pendant un round (personnages, armes 3P) est bien détruit.
- Studio ajoute une charge constante (éditeur, plugins, client), pas une croissance par round : une courbe plate dans
  Studio suffit à écarter une fuite par round. Le jeu publié reste nécessaire pour juger le niveau absolu de la mémoire.
- Reste à vérifier, si un doute revient : plusieurs joueurs et beaucoup de morts par round (relevés `départ de …`).

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

Champs : `dt` (frame rendue), `steps` (ticks de mouvement depuis le rendu précédent : 0, 1 ou 2 à 60 FPS, c'est
normal), `simDt` (temps simulé pendant ces ticks), `disp` (déplacement affiché de la racine, interpolé), `vRendue`
(= `disp/dt`), `vSim` (vitesse du MovementController), `yaw` (degrés/s), `gcΔ` (mémoire Lua, une forte baisse signale
un passage du GC), `arme`.

Causes d'un `STUTTER` (`source=`) :

- `simulation` : la vitesse simulée elle-même fait un pic (collision, rampe, boost, `commitMove`).
- `position_hors_simulation` : la racine affichée a bougé autrement que `vSim × dt` (correction serveur, téléportation
  partielle, step-up ou éjection de `WallSlide`, ou interpolation cassée).
- `interpolation` : déplacement irrégulier qu'aucune des deux causes ci-dessus n'explique ; ne devrait pas apparaître.

Depuis le tick fixe (#96), le nombre de ticks par frame n'est plus une cause : l'affichage est interpolé au temps rendu.
Les anciennes causes `pas_physique_manquant`, `pas_physique_double` et `timing_rendu_vs_simulation` ont disparu.

Un pic isolé est une frame qui s'écarte de plus de 30 % de ses deux voisines, quand ces voisines s'accordent entre
elles à 15 % près. Une accélération progressive (surf, boost) n'est donc pas signalée. En dessous de 2 studs/s et de
20 °/s, rien n'est jugé.

## Rythme du mouvement (#88, #96)

Le perso est déplacé par script (racine ancrée), dans `MovementController`. Sa boucle tourne **sur le rendu, juste
avant la caméra** (`BindToRenderStep`, priorité `Camera - 1`). La physique avance par **ticks fixes de 1/64 s**
(`StepTiming`, comme Source) : à entrées égales, la trajectoire de surf est la même pour tous, quel que soit le FPS
(choix d'équité, #96). Chaque frame joue les ticks entiers contenus dans son temps (0, 1 ou plusieurs), puis pose la
racine **entre les deux derniers ticks**, au prorata du temps restant ; la caméra lit cette position dans la même frame.

- Coût : l'affichage a jusqu'à un tick (15,6 ms) de retard sur la simulation. La rotation de la caméra, elle, reste
  lue à chaque frame : seule la position est en retard.
- La simulation repart toujours de la position du dernier tick (`ownCFrame`), jamais de la position affichée ni de
  l'écho serveur. Toute téléportation client doit poser `ownCFrame` **et** `prevCFrame` (cf. `applyLaunch`), sinon la
  racine est interpolée depuis l'ancienne position pendant une frame.
- Avant (jusqu'au 06/11/2026), la boucle tournait sur `Heartbeat`. Son `dt` (de 14 à 21 ms) suit un autre chronomètre
  que le rendu, et le déplacement par image variait d'environ 30 % : plus d'un stud d'écart à 200 studs/s, d'où les
  saccades en surf rapide (54 `STUTTER` `timing_rendu_vs_heartbeat` sur 150 s, mesure du 03/11).
- Du 06/11 au tick fixe, la physique avançait au `dt` de chaque frame : un joueur à 144 FPS gagnait plus de vitesse en
  air strafe qu'un joueur à 60 FPS (l'air accelerate de Source dépend du pas). Pas d'ancien mode gardé activable.
- Une frame lente joue jusqu'à 13 ticks (0,2 s) ; au-delà (gel, fenêtre en arrière-plan), le retard est abandonné.
- Ne pas remettre d'interpolation de position dans `FPSCamera` : elle est déjà faite par `MovementController`.

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

Streaming : voir « Streaming désactivé » plus haut. Une fois coupé, en mouvement à qualité 10 : p99 de 39 à 31 ms,
max de 49-70 à 37 ms, « bien mieux » au ressenti ; restent de petites pertes de frames (CPU et GPU de rendu vers 15 ms
dans Studio, proches des 16,7 ms d'une frame). Ces chiffres ne valent que pour Studio (mesure publiée ci-dessous).

## Bilan #88 : banc F4 dans le client publié (2026-11-06, Dizzy, 1920×1080, qualité 10, écran 59 Hz)

| Phase | GPU moy | CPU moy | frame médiane | p99 |
|---|---|---|---|---|
| référence | 8,0 ms | 2,4 ms | 17,0 ms | 19,1 ms |
| sans ombres | 8,2 | 2,1 | 17,0 | 19 |
| sans Atmosphere | 7,8 | 2,1 | 16,9 | 19 |
| sans effets (SunRays, Bloom) | 8,2 | 2,1 | 16,9 | 19 |
| sans translucides (Geometry, Underside, Dressing) | 7,8 à 8,2 | 2,1 | 16,9 à 17,0 | 18,6 à 19,1 |
| tout coupé | 8,4 | 2,1 | 16,9 | 19 |
| référence (contrôle) | 7,9 | 2,2 | 16,9 | 19,3 |

- **Le client publié tient le rythme de l'écran (59 Hz) en qualité 10**, avec moitié de marge sur le GPU et 2 ms de
  CPU. Les pertes de frames restantes sont négligeables au ressenti.
- Aucun levier ne fait gagner plus de 0,4 ms, ce qui reste dans le bruit. Ombres, Atmosphere, effets, nuages et vitres
  ne coûtent rien de mesurable à cette résolution : ne pas les dégrader pour la performance.
- Les saccades et le lag ressentis venaient de Studio. Studio fait tourner client, serveur et éditeur dans un seul
  processus : son CPU de rendu monte à 9-15 ms au lieu de 2. Le streaming de la map pesait aussi. **Toujours juger la
  performance dans le client publié** ; Studio sert à comparer deux versions entre elles, pas à juger la fluidité.
- Avant/après sur la passe #88 (#90, #91, #92) :
  - pièces qui projettent une ombre : de 15 319 à 1 949 ;
  - triangles de la passe d'ombres, AWP en main : de 111k à 3k ;
  - fuite du Heartbeat de mouvement au respawn : corrigée ;
  - 22 000 warnings par session dans le client publié : supprimés ;
  - mouvement calé sur le rendu ;
  - streaming coupé ;
  - client publié en qualité 10 : 59 FPS médian, p99 19 ms.

## Mesure du 2026-11-06 (client publié, Dizzy, qualité auto, après #91)

Parcours au couteau et à l'AWP, overlay ouvert, 7 bilans de 10 s :

- 59 FPS médian (plafond à 60), p99 de 22 à 27 ms, max de 25 à 42 ms ; 73,6 ms au spawn.
- **Le rendu ne limite plus** : CPU de rendu 2,9 à 4,0 ms, GPU 5,9 à 15,0 ms, draw calls 20 à 31 (scène) et 12 à 98
  (ombres), triangles 10k à 70k.
- Nos scripts : `mouvement` 0,2 ms par frame, le reste moins de 0,05 ms.
- Mémoire client environ 1 540 Mo, stable entre les bilans. Serveur : +84 Mo et +683 Instances entre le démarrage et la
  première fin de round (un seul relevé ; suivi sur plusieurs rounds : pas de fuite, voir #95 plus haut).
- 22 000 warnings « Memory tracking is currently disabled » : l'overlay lisait les catégories de mémoire, que le client
  publié ne suit pas. Corrigé (`MemoryTracker.readTags`).

Conclusion : le GPU et la map ne sont plus en cause dans le client publié. La géométrie de la map (fusion des coins,
plafonds, faces jamais vues) n'est pas retouchée tant qu'une mesure ne la désigne pas. Le bilan en qualité 10
(ci-dessus) confirme que le client publié tient le rythme.

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
- Un ressort ou un amortisseur intégré par frame (Euler semi-implicite avec `dt` brut) diverge quand `ω·dt` dépasse
  environ 0,83 : le balancement du viewmodel (`SWAY_SPEED` 18) est parti à 1 000 000 studs sous ~22 i/s, par exemple
  fenêtre Studio sans le focus (#304). Toute intégration par frame se découpe en pas de ≤ 1/60 s (`SpringRules.step`,
  un seul pas à 60 i/s et plus, donc rendu inchangé) et se teste à 10 i/s. Tronquer `dt` ne suffit pas (cf. ci-dessus).

# Performance et saccades

## Les outils, et quand s'en servir

| Question | Outil |
|---|---|
| Le jeu tient-il ses FPS ? Est-ce le CPU, le GPU, la map ou nos scripts ? | overlay F3 (Studio et jeu publié) |
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
| `Mémoire`, catégories | Mo par `Enum.DeveloperMemoryTag` (Lua, Instances, Textures, Pièces…) |
| `Scripts` | coût de nos boucles par frame (`PerfMarkers`) : ms/frame, appels/frame, max. **Plus d'un appel par frame pour une boucle signale une connexion branchée en double** (fuite au respawn, par exemple) |

Tant qu'il est ouvert, une ligne `[Perf] BILAN` résume toutes les 10 s FPS, p99, max, CPU/GPU, draw calls, mémoire, réglage
graphique et coût des scripts. À la fermeture, un dernier bilan est écrit.

## Repères de scripts (`PerfMarkers`)

`src/shared/PerfMarkers.luau` : `PerfMarkers.wrap("nom", callback)` entoure un callback sans valeur de retour (Heartbeat,
RenderStepped, BindToRenderStep). Le repère est toujours posé (`debug.profilebegin`, coût négligeable si le profiler est
fermé), et il est chronométré seulement quand l'overlay est ouvert. Repères posés : `mouvement`, `caméra`, `viewmodel`,
`armes`, `armes 3P`, `menu 3D`, `curseur menu` (client), `srv round` (serveur). Toute nouvelle boucle par frame doit
passer par `wrap`.

Dans le MicroProfiler (Ctrl+F6, puis pause pour figer une frame lente), ces noms apparaissent sous `Heartbeat` ou
`RenderStep` : on voit si une frame lente vient de nos scripts ou du moteur (rendu, physique, GC).

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

Champs : `dt` (frame rendue), `steps` (nombre de Heartbeat depuis le rendu précédent, 1 attendu), `hbDt` (temps
simulé pendant ces Heartbeat), `disp` (déplacement de la racine), `vRendue` (= `disp/dt`), `vSim` (vitesse du
MovementController), `yaw` (degrés/s), `gcΔ` (mémoire Lua, une forte baisse signale un passage du GC), `arme`.

Causes d'un `STUTTER` (`source=`) :

- `pas_physique_manquant` ou `pas_physique_double` : 0 ou 2 Heartbeat entre deux rendus. Le perso avance de 0 ou de
  2 pas sur une frame.
- `simulation` : la vitesse simulée elle-même fait un pic (collision, rampe, boost, `commitMove`).
- `position_hors_simulation` : la racine a bougé autrement que ce que prévoyait la vitesse simulée (correction
  serveur, téléportation partielle, step-up ou éjection de `WallSlide`).
- `timing_rendu_vs_heartbeat` : un pas normal, mais le temps rendu diffère du temps simulé. La caméra suit un pas
  Heartbeat qui ne dure pas autant que la frame affichée.

Un pic isolé est une frame qui s'écarte de plus de 30 % de ses deux voisines, quand ces voisines s'accordent entre
elles à 15 % près. Une accélération progressive (surf, boost) n'est donc pas signalée. En dessous de 2 studs/s et de
20 °/s, rien n'est jugé.

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

- `FPSCamera` contient une interpolation de position (`updateRoot`) qui n'est appelée nulle part : la caméra lit
  directement `hrp.Position` au rendu. Si on la rebranche telle quelle, elle crée des saccades. `Heartbeat` tourne une
  fois par frame, pas à 60 Hz fixe, donc l'`alpha` basé sur `os.clock()` varie d'une frame à l'autre.
- `MovementController` plafonne `dt` à 1/30 : après une frame lente, le perso avance moins que le temps écoulé. Un
  `HITCH` se voit donc deux fois : l'image fige, puis le déplacement est trop court.

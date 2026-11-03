# Performance et saccades

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

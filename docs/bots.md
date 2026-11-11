# Bots

Spec et décisions : issue #133 (découpage en 9 étapes). Identité joueur/bot, apparition et mouvement serveur :
`docs/architecture.md` (« Participants, joueurs et bots », « Bots »). Ce document décrit la navigation (#140) et ce
qu'il faut savoir pour la modifier.

## Plan de navigation (#140)

Construit **automatiquement au démarrage du serveur** dans la vraie collision de la map jouée (`NavBuilder`, appelé par
`NavPlan.start` depuis `BotManager.init`), sans rien placer à la main : il marche pour une future map sans travail.

1. **Cases** : une colonne tous les `NAV_GRID` studs (4). Un rayon descend du haut de la map, puis repart sous chaque
   surface touchée (24 au plus par colonne) ; une surface marchable (`SURF_NORMAL_Y`) devient une case si une boîte de
   corps (`NAV_BODY_*`) y tient sans rien toucher (`GetPartsInPart`, murs d'air compris).
2. **Arêtes**, vers les 8 colonnes voisines :
   - marche : boîte du corps balayée (`Blockcast`) d'une case à l'autre, dans les deux sens ;
   - rebord : depuis une case vers la plus haute case plus basse qu'une marche d'une colonne qu'elle ne rejoint pas à
     pied. Trajet en L (avancer au-dessus du vide, puis descendre) : descente dans ce sens, et saut dans l'autre si le
     rebord fait au plus `NAV_JUMP_UP_MAX` (5 studs, sommet du saut à 6,6) ;
   - échelle : une arête du pied (devant le volume de `Maps.Map.Ladders`) au haut (derrière l'acrotère), à sens unique
     (on redescend par une descente) ;
   - rampe de surf : une arête par rampe et par sens, de la case d'entrée à la case de sortie, trajet simulé (cf.
     « Rampes de surf (#142) »).
3. **Cases gardées** : composante fortement connexe d'un point de `GroundSpawns` (on y va et on en revient). Écarte les
   dessus de murs et les fonds sans sortie. Calculée après les rampes : une corniche qu'on ne rejoint que par une rampe,
   et d'où l'on revient par l'autre sens, en fait partie.
4. **Points de passage** : cases regroupées par carré de `NAV_WAYPOINT_SIZE` studs et par étage (cases reliées à pied
   dans le carré), petites zones fondues dans leur voisine. Note fixe : vue (nombre de points visibles à hauteur des
   yeux, critère principal), hauteur, couvert (8 rayons), bonus de type (`rampe` : entrée ou sortie d'une arête de
   rampe à moins de `NAV_RAMP_DIST`, `echelle`, `escalier`, `fosse`, `couloir`, `piece`). Les murs d'air ne bloquent ni
   la vue ni le couvert.

Mesure sur Dizzy (09/11/2026) : 40 841 cases (29 319 gardées), 1 056 points, 294 000 arêtes de marche, 9 250
descentes, 4 500 sauts, 2 échelles ; **7,8 s** au démarrage (cases 4,0, marche 1,1, rebords 0,3, vue 2,1) avec
`NAV_BUILD_BUDGET` = 8 ms par frame ; **~45 Mo** de mémoire Lua serveur. Les bots attendent sur place que le plan soit
prêt (ils tombent du soleil pendant ce temps).

## Rampes de surf (#142)

Décision 3 de #133 : une rampe est un raccourci emprunté seulement s'il rapproche le bot de sa destination. Le surf
n'est **pas simulé par bot** : le trajet est **calculé une fois au démarrage** avec la vraie physique, puis rejoué.
Règles pures dans `RampRules` (et `NavRules.rampCost`), simulation dans `RampSim`, réglages `RAMP_*` de `BotConfig`.
- **Rampes** (`NavBuilder.findRamps`) : pièces `Part` en bloc (`Shape = Block`, pas de `WedgePart`), `CanCollide`, des dossiers `RAMPS_FOLDER` (`Ramps`, à toute profondeur) dont
  une face est dans la plage du surf (`SURF_NORMAL_MIN` à `SURF_NORMAL_Y`) et fait au moins `RAMP_MIN_AREA` studs² ;
  repère `RampRules.frameOf` (u le long de la rampe, v vers le haut de la pente, n la normale), une seule par rampe
  (`sameRamp`). Map sans rampe : aucune arête, rien d'autre ne change. `RAMP_ENABLED = false` les coupe toutes.
- **Entrée** : cases à moins de `RAMP_ENTRY_DIST` au-delà du bout de départ dont le sol tombe sur la face
  (`entryTarget` : point visé à `RAMP_ENTRY_INSET` du bout, `RAMP_ENTRY_RISE` au-dessus du sol). `RAMP_TRIES` cases
  essayées (`pickEntries` : les plus proches du point de passage, écartées de `RAMP_TRY_SPACING`).
- **Simulation** (`RampSim.simulate`, `CharacterMotor` du joueur sur un corps hors du Workspace, ticks de 64 Hz) :
  course vers le **point de passage** (`approachPoint` : au-delà du bout, devant la face) puis vers le point visé,
  saut près du point de passage ou au bord du vide ; sur la rampe, **appui vers la rampe** (direction horizontale
  opposée à la normale) : le glissement le garde sur la face et il y **monte doucement** à ~30 studs/s, comme un
  joueur ; au-delà du bout d'arrivée (ou décroché), case où il retomberait (`pickLanding` ; une case de bord,
  sans ses 8 voisines à pied, comptée `RAMP_EDGE_PENALTY` studs plus loin), rejointe en l'air
  (`landingVelocity`, `steer` à `RAMP_AIR_STEER`). Réussite : atterri à moins de `RAMP_LAND_RADIUS` d'une case, freiné
  jusqu'à sa vitesse de course sans en sortir (`RAMP_SETTLE_TIME` au plus : le bot rejoue ce freinage et repart à
  vitesse de course), assez de rampe parcourue (`RAMP_MIN_TRAVEL`), sous `RAMP_MAX_TIME` et `RAMP_MAX_SPEED`
  (`accept`). Échec immédiat s'il retombe avant la rampe (saut trop court). Le plus court trajet réussi devient
  l'arête ; `[Nav] rampe i, sens d : entrée → sortie, durée, vitesse` dans la console, ou la raison de chaque échec.
  La simulation rend la main à chaque tick quand la tranche `NAV_BUILD_BUDGET` est écoulée.
- **Voisins** : une arête de rampe ne relie pas deux points de passage dans `waypointEdges` (l'enquête fouille les
  points voisins, pas le bout d'une rampe à 150 studs).
- **Coût** : `NavRules.rampCost` = durée × `RUN_SPEED` + `RAMP_COST_EXTRA` (risque), lu par l'A* dans
  `graph.rampCost` au lieu de la longueur : une rampe n'est prise que si elle raccourcit le chemin.
- **Parcours** : arrivé au sol à moins de `RAMP_START_DIST` de la case d'entrée (`canStart`), `BotNavigator` renvoie
  l'intention `ride` ; `BotMotion` rejoue le trajet (`RampRules.sample` : pieds et vitesse à l'instant t), l'écart de
  départ résorbé en `RAMP_BLEND_TIME` (`blend`), regard et tir comme ailleurs, animation de surf. À la fin, il est
  posé sur la case de sortie avec sa vitesse horizontale et le chemin reprend (`rideFinished`) ; si sa destination a
  changé pendant le trajet, il repart de la case où il a atterri (comme après une chute).
- **Anti-triche** : la position d'un bot passe par `CharacterSync.relayBot`, sans validation (pas de `[CheatLog]`
  possible) ; le trajet reste quand même sous `RAMP_MAX_SPEED` (200, sous `MAX_SPEED_SERVER` = 450) comme un joueur.

**Sur Dizzy**, les deux rampes relient la plateforme du haut de l'escalier de la fosse (Y 70, bout fermé) à une
**corniche en cul-de-sac** au bout ouvert (Y 70, X 1722-1738 côté T, X 2259-2277 côté CT), qu'on ne rejoint pas
autrement : 4 arêtes (2 par rampe), la corniche entre dans les cases gardées (29 555 au lieu de 29 319, 1 068 points
au lieu de 1 056). Ce ne sont donc pas des raccourcis entre deux zones de la map, mais le seul chemin vers ces
corniches. Mesure (11/11/2026, Studio) :

| Rampe, sens | Entrée → sortie | Durée | Vitesse au plus |
|---|---|---|---|
| T, vers la corniche | (1874, 70, −409) → (1722, 71, −389) | 5,5 s | 72 studs/s |
| T, vers la plateforme | (1726, 71, −389) → (1886, 71, −393) | 6,4 s | 64 studs/s |
| CT, vers la corniche | (2126, 70, −113) → (2278, 71, −129) | 5,4 s | 72 studs/s |
| CT, vers la plateforme | (2274, 71, −129) → (2114, 71, −129) | 6,3 s | 65 studs/s |

Construction : 1,0 à 1,2 s de plus au démarrage (24 simulations).

## Suivi de chemin

`BotNavigator` (un par bot vivant) : destination tirée au hasard parmi les points (la note dynamique et les états
viennent avec #141), chemin A* de case en case (`NavRules.findPath`, coût pondéré par type d'arête), puis à chaque tick :
- cible = la case la plus lointaine qu'on rejoint en ligne droite (`NavRules.lookAhead`, arêtes de marche seulement) ;
- saut quand le rebord (milieu de l'arête) est à moins de `vitesse × NAV_JUMP_LEAD_TIME` + rayon ; en l'air, il ne vise
  sa cible que sur une arête de saut, de descente ou d'échelle (sinon pas d'air control hors bunny hop, cf. ci-dessous ;
  le surf n'est pas simulé). Descente visée depuis #142 : sans elle, un bot qui sautait du toit sur la corniche T de
  Dizzy (35 studs plus bas, 16 de large) gardait sa vitesse de course et la dépassait, dans le vide ;
- échelle : dans le volume, vitesse de `LadderRules.climbVelocity` en poussant vers le mur, comme le joueur ;
- gêne : sans se rapprocher de sa cible pendant `NAV_STUCK_TIME`, nouveau chemin ; après `NAV_MAX_REPATH` essais sur
  la même case, l'arête est écartée `NAV_BAN_TIME` s pour ce bot (warn `[Nav] arête … ratée`) et il change de
  destination ; tombé sous le trajet, il repart de là où il est.

Mesure (5 bots, 2 min 30) : 33 destinations atteintes, 0 arête ratée, 23 descentes, 9 sauts, 13 échelles franchis.

**La recherche de chemin est étalée sur plusieurs ticks (#145).** Sur Dizzy (29 000 cases), un A* complet coûtait
80 à 150 ms dans Studio : un pic de frame serveur à chaque nouvelle destination. `NavRules.newSearch` rend une recherche
reprenable (`run(budget)` : `"running"`, `"found"` ou `"none"`), que `BotNavigator._plan` fait avancer de
`NAV_SEARCH_BUDGET` cases par tick ; le bot attend sur place tant qu'elle court (de 1 à quelques ticks en général).
`NAV_PATH_WEIGHT` (2) pondère l'heuristique : bien moins de cases explorées, pour un chemin au plus 2 fois plus long
que l'optimal. `NavRules.findPath` reste la version d'une traite (tests, outils). Ne pas rappeler `findPath` depuis
le jeu : il fige la frame.

## Bunny hop et air strafe (#151)

Réglages `BHOP_*` de `BotConfig`, règles pures dans `BotRules` (strafe, vitesse visée) et `NavRules` (largeur,
portion de marche, avancée, virages). Le bot ne cherche pas de lignes droites : comme un joueur, il **tourne en
l'air** en strafant, et ne ralentit que pour les virages trop serrés pour sa vitesse.
- **Largeur de passage** (`NavRules.clearance`, au démarrage) : pas de marche jusqu'à la case de bord la plus proche
  (bord = moins de 8 voisines à pied : mur ou vide à côté). Les cases de bord coûtent plus à la recherche de chemin
  (`NAV_BORDER_COST`) : les chemins passent au milieu des passages au lieu de raser les murs.
- **Portion de marche** (`walkStretchEnd`) : jusqu'au prochain saut, échelle, descente de rebord ou à la destination
  (pentes et marches se survolent). Une série commence (tirage `BHOP_CHANCE` par portion) s'il reste au moins
  `BHOP_MIN_RUN` studs, et ressaute à chaque atterrissage, sans friction, tant que le saut suivant tient dans ce qui
  reste (`keepBhopping`). Sinon atterrissage normal. `BotNavigator:setBhopAllowed(false)` la coupe (états de #141).
- **Avancée** : en l'air, les cases passent selon l'avancée le long du chemin (`advanceAlong`, hauteur ignorée).
- **Poursuite** : il vise le point du chemin à `vitesse × BHOP_LOOK_TIME` devant (`pointAlong`), décalé de
  ±`BHOP_ZIGZAG_ANGLE` d'un saut à l'autre.
- **Vitesse visée** (`bhopTargetSpeed`) : au plus `BHOP_MAX_SPEED`, la vitesse des virages à `vitesse ×
  BHOP_BRAKE_TIME` devant (`cornerSpeed` : rayon mesuré sur `BHOP_CURVE_CELLS` cases, agrandi d'une part de la
  largeur, vitesse `√(2·L·R/dt) × BHOP_TURN_SAFETY`, `BHOP_NARROW_SPEED` le long d'un bord), et assez lente pour que
  la fin du saut et le suivant tiennent dans la portion. `BotRules.airStrafe` la tient : gain sous la vitesse visée,
  **freinage en l'air** au-dessus (viser à l'opposé de la vitesse retire jusqu'à `AIR_ACCEL·w·dt` par tick, `w` dosé
  pour perdre juste l'excès), plané ou virage sans gain (angle `acos(−L/|v|)`) à la vitesse visée.
- **Regard** : suit la vitesse (comme la caméra d'un joueur qui strafe), à `NAV_TURN_RATE`.
- Imperfections : `BHOP_STRAFE_NOISE` (écart à l'angle optimal), `BHOP_MISS_CHANCE` (saut en retard, avec friction).

Mesure sur Dizzy (09/11/2026, 5 bots, ~12 min) : 109 séries, 639 sauts (~6 par série), 90 studs/s au plus d'après
le bilan (pointes à ~100 mesurées par position), 67 destinations, 2 arêtes ratées (3 en 2 min 30 bhop coupé : arêtes
connues du plan, dont la marche en (1930, 69, −184)). Ce qui borne la vitesse visée : fin de portion ~55 %, plafond
~16 %, virages ~14 %, bord ~9 % ; les destinations tirées au hasard sont proches, les états de #141 changeront ça.
Une chute hors de la map (Y −94) vue une fois, non reproduite en 7 min 30 de capture.

## Comportement (#141)

`BotBrain` (un par bot vivant, appelé avant `BotMotion` à chaque Heartbeat), règles pures dans `BotBehaviorRules`,
réglages dans `BotConfig` (section « Comportement »). Il commande le suivi de chemin (`chooseDestination`,
`onArrive`, `setDestination`) et le regard de `BotMotion` (`gaze`).
- **Perception** (tous les `PERCEPTION_INTERVAL`) : un autre participant en vie est vu s'il est dans `VIEW_FOV` (100°)
  autour du regard, à moins de `VIEW_RANGE`, et si un rayon des yeux vers sa tête ou son torse n'est coupé que par
  lui (murs d'air ignorés). Cible : un humain plutôt qu'un bot, puis la plus proche.
- **Ouïe** : `BotManager.hearShot` (appelé par `relayShot` d'`init.server` pour un tir au fusil d'un joueur accepté par
  le serveur, remote `ShotFired`, #156 ; et par `BotBrain` pour les tirs des bots). Un coup de couteau ne s'entend pas,
  ni un tir écarté du relais (cadence, equip, chargeur : cf. `docs/anticheat.md` « Relais des tirs »). À moins de `HEARING_RADIUS` (200), position faussée d'au plus `HEARING_FUZZ` (20 %) de la distance.
- **Mémoire** : dernière position vue ou entendue par cible, oubliée après `MEMORY_TIME`.
- **États** (`nextState`) : combattre (cible vue) > se replacer (après un kill, ou touché sous `REPLACE_HEALTH` en
  combat) > enquêter (contact pas encore fouillé : dernière position, puis `INVESTIGATE_POINTS` points voisins) >
  chercher (note dynamique : note fixe, passage récent, autres bots, distance, hasard ; à l'arrivée, angle tenu avec
  `HOLD_CHANCE`, regard vers un point visible lointain, liste `visible` des points calculée par `NavBuilder`).
- **Biais vers les humains** : sans contact depuis `BIAS_DELAY` (15 s), bonus aux points proches d'une zone décalée
  de `BIAS_SPREAD` autour de l'humain le plus proche.
- **Combat sans poursuite** (choix de l'utilisateur) : le bot garde sa destination et son bhop. Il se tourne vers la
  cible (`COMBAT_TURN_RATE`), tire après `REACTION_TIME` + `COMBAT_AIM_TIME` (cf. « Combat »), puis rend son regard
  à sa course pendant `COMBAT_COOLDOWN`. En l'air, la visée coupe le gain d'air strafe (il glisse et garde sa vitesse).

Mesure (09/11/2026, 5 bots + 1 joueur immobile, 2 min) : 24 combats, 7 enquêtes, 281 sauts de bhop, 0 arête ratée.

## Combat (#143)

Règles pures dans `BotCombatRules`, armes dans `BotArsenal` (une par bot vivant), réglages dans `BotConfig` (section
« Combat » : c'est là que se règle la difficulté, un seul niveau).
- **Jamais d'arrêt** (choix de l'utilisateur) : en l'air comme au sol, le bot se tourne vers la cible, tire et reprend
  sa trajectoire, comme un joueur. Pas de pas de côté ni de poursuite ajoutés pour le duel.
- **Tir** : seulement sur une cible vue à ce regard (champ de vision et ligne de vue de #141), après `REACTION_TIME` +
  `COMBAT_AIM_TIME`, une fois son **cap réel** à moins de `FIRE_YAW_TOLERANCE` de la cible (le regard tourne à
  `COMBAT_TURN_RATE`, jamais de visée instantanée), et à moins de `FIRE_RANGE`. Le rayon part des yeux selon ce cap
  (`aimDirection`), visé au haut du torse, écarté dans un cône de `spread` (`scatter`).
- **Dispersion** : `AIM_SPREAD` + `AIM_SPREAD_SPEED` × vitesse de la cible (estimée entre deux regards, la racine
  étant ancrée), plafonnée à `AIM_SPREAD_MAX`. **Aucun malus selon la vitesse du bot**, ni en l'air ni en bhop :
  un joueur n'en a pas (choix de l'utilisateur).
- **Validation** : la touche passe par `Validator.authorizeHitscan` / `authorizeMelee` (arme en main, portée,
  cadence) puis le même `applyHit` qu'un joueur (`deps.hitscan`, `deps.melee` de `BotManager`) : dégâts par zone,
  kill feed, mort, ragdoll, caméra du tué. Le hitmarker n'est envoyé qu'à un tireur joueur. Chaque tir au fusil passe
  aussi par le relais des joueurs (`relayShot`, `onFire` de `BotArsenal`) : son chez les joueurs et recul de l'arme 3P
  (#215), jamais refusé ni compté pour un bot (`BotArsenal` tient son chargeur, `docs/anticheat.md` « Tirs comptés et
  touches rattachées »). Le coup de couteau pose son recul 3P dans `BotArsenal.fire`.
- **Armes** : AWP en main, couteau dans le dossier `BotBag` du personnage. Couteau sorti sous `KNIFE_RANGE`, fusil
  repris au-delà de `KNIFE_DROP_RANGE`. Temps de sortie, cadence, chargeur, réserve et rechargement de `WeaponConfig`
  (rechargement aussi quand il n'a rien à viser) ; vitesse de course selon l'arme (`BotMotion:setWeapon`).
- **Délai de grâce** : `SpawnManager.place` pose l'attribut serveur `SpawnedAt` (os.clock) sur tout personnage ; un
  bot ne tire pas sur un participant apparu depuis moins de `SPAWN_GRACE` (4 s, lancement depuis le soleil compris).
- **Cible** : un humain plutôt qu'un bot, puis la plus proche (`pickTarget` de #141) ; les bots se tirent dessus.

Mesure (09/11/2026, 5 bots + 1 joueur immobile au sol, 1 min) : 40 tirs, 23 touches, 22 kills (le joueur immobile
est tué environ toutes les 7 s une fois son délai de grâce passé), 0 coup de couteau (les bots ne poursuivent pas).

## Population (#144)

Règles pures dans `BotPopulationRules`, appliquées par `BotManager` (`adjustPopulation`, toutes les
`POPULATION_INTERVAL` s). Réglages `TARGET_POPULATION` (6), `MAX_BOTS` (5), `POPULATION_DUEL_TIME` (4 s).
- **Bots voulus** = `TARGET_POPULATION` − joueurs connectés, borné à `MAX_BOTS` ; aucun sans joueur. Ils apparaissent
  dès que le round est actif (un joueur a cliqué Play).
- **Retrait** à l'arrivée d'un joueur, **un bot par passage** : d'abord un bot hors du jeu (mort), sinon le vivant le plus
  longtemps sans contact avec une cible. Jamais un bot « en duel » (état combattre, ou contact depuis moins de
  `POPULATION_DUEL_TIME` s) : si tous le sont, le retrait est reporté au passage suivant. `lastContact` compte aussi un
  tir entendu, donc un bot qui vient d'entendre un tir est protégé quelques secondes (prudent, pas gênant).
- Noms : liste fixe `BotConfig.NAMES`, premier nom libre (préfixe `BOT` ajouté à l'affichage par `ParticipantRules`).
- **DebugPlaytest** : `BotManager.setPaused(true)` pendant un run retire tous les bots (forcé, même en duel), rétablis
  à la fin (compteur, plusieurs runs possibles).

## Debug (Studio)

- `workspace:SetAttribute("DebugBots", 5)` : fixe le nombre de bots (un round doit être actif : un joueur a demandé à
  apparaître). `"+"` / `"-"` : un de plus / de moins (l'attribut est remplacé par le nombre obtenu), `0` : aucun,
  `nil` ou `"auto"` : retour à la population automatique. Un nombre fixé retire sans attendre la fin des duels.
- `workspace:SetAttribute("DebugBotsFreeze", true)` : fige les bots (ni mouvement ni tir), `false` ou `nil` les relâche.
- `workspace:SetAttribute("DebugBotsGoto", Vector3.new(x, y, z))` : tous les bots vont au point de passage le plus
  proche (corniches de Dizzy : `(1730, 70.5, -350)` côté T, `(2268, 70.5, -170)` côté CT, plateformes
  `(1895, 70.5, -412)` et `(2110, 70.5, -115)`). Ordre prioritaire (`BotNavigator.pinDestination`) : enquête et repli
  ne le changent pas ; le comportement reprend la main à l'arrivée, ou si la destination devient injoignable (arête
  écartée). Remettre `nil` avant de renvoyer au même endroit (même valeur : pas de signal).
- `workspace:SetAttribute("DebugNav", true)` : points (couleur du rouge au vert et étiquette = numéro, type, note),
  arêtes entre points (gris marche, bleu descente, orange saut, vert échelle ; trait court = sens unique), trajet
  simulé de chaque arête de rampe en violet (boule à l'entrée), chemin
  restant de chaque bot en jaune, au-dessus de chaque bot son état, sa destination et sa cible (blanc chercher,
  jaune enquêter, rouge combattre, bleu se replacer), trait rouge vers la cible en combat. `"cases"` : en plus chaque case (vert gardée, rouge écartée), lourd (~40 000 pièces).
- Console : `[Nav] Dizzy : …` à la fin de la construction (durée par phase), `[Nav] bilan` et `[Bots] bilan`
  (combats, tirs, touches et kills, coups de couteau, visées retenues par le délai de grâce, tirs entendus, enquêtes,
  replis, angles tenus, destinations biaisées) toutes les 30 s.
- `workspace:SetAttribute("PerfServer", true)` : sonde de coût du serveur, une ligne `[Perf] SRV` toutes les 10 s
  (méthode et lecture : `docs/performance.md`).
- Le playtest démarre sans round : `ReplicatedStorage.RequestSpawn:FireServer()` en contexte Client fait apparaître
  le joueur et lance le round (piège du `require` depuis le MCP : `docs/architecture.md`).

## Pièges

- **Un rebord bas n'est pas une marche.** `NavRules.stepKind` classe en « marche » toute différence de hauteur
  inférieure à `walkRise` (marche + pente de 46° sur la distance : 5,3 studs sur 4), donc aussi un rebord vertical de
  4 studs, que le balayage refuse ensuite. Les rebords sont donc cherchés dans une passe à part, sur toute colonne non
  rejointe à pied ; sans elle, le plan n'avait aucune arête de saut.
- Le temps affiché est surtout de l'attente entre frames : le calcul est découpé par tranches de `NAV_BUILD_BUDGET`.
  Le monter raccourcit la construction mais charge les frames serveur du début de partie.
- Les dessus des murs d'air (escaliers) sont de vraies cases : c'est là que marchent les joueurs.
- **Air strafe : alterner pendant le saut, pas d'un saut à l'autre.** Avec `AIR_SPEED_CAP` = 6, un strafe à 90°
  tourne la vitesse d'environ 11° par tick à 30 studs/s : tenir un côté tout un saut fait une spirale. Le côté suit
  l'écart au cap à chaque tick, et le zigzag visible vient du cap visé décalé d'un saut à l'autre.
- **La fenêtre de gain est étroite** : le strafe ne fait gagner que si |v|·cos θ < L, soit ±asin(L/|v|) autour de 90°
  (±11° à 30, ±8° à 45). Au-delà il freine. Un bruit d'angle en degrés fixes (15°) faisait perdre de la vitesse :
  `BHOP_STRAFE_NOISE` est une part de cette fenêtre.
- **Pas de lignes droites.** Première version : bhop seulement si le saut suivant tenait dans une ligne droite du
  chemin, sinon atterrissage avec friction. Les chemins A* en grille zigzaguent et Dizzy a peu de longues lignes :
  ~2 sauts par série, 43 studs/s au plus. Le strafe fait tourner en gagnant de la vitesse (rayon ≈ |v|²·dt / L,
  26 studs à 100), et le freinage en l'air est presque instantané : suivre le chemin courbe à une vitesse réglée par
  ses virages suffit. Une portion qui s'arrêtait à chaque montée de plus d'une marche bridait encore les séries.
- **Une cible qui sort du champ n'est pas perdue.** En rendant son regard à sa course après un tir, le bot sort sa
  cible de son champ : la lâcher aussitôt relançait le temps de réaction et une enquête sur sa dernière position à
  chaque tir (45 combats et 44 enquêtes en 30 s, une poursuite de fait). Elle reste en tête `TARGET_KEEP_TIME`
  (regard vers sa dernière position vue, pas de tir sans la revoir), et une cible perdue n'est fouillée qu'avec
  `LOST_CHASE_CHANCE` ; un tir entendu l'est toujours.
- Gain par saut : environ 36 × 44 ticks ≈ 1 600 de |v|² en strafe parfait, donc 6 sauts de 30 à 100, pas 3.
- **Tests Lune : `Vector3` est en simple précision.** Un angle recalculé par `acos` d'un produit scalaire d'unitaires
  s'écarte de ~1e-5° de la valeur exacte : comparer les angles à 1e-3 près, pas à 1e-6.
- **Simulation de rampe et personnages présents.** `RampSim` utilise le `CharacterMotor` du joueur, dont les requêtes
  n'excluent que le corps simulé : un joueur ou un bot debout sur une entrée de rampe pendant la construction du plan
  (les premières secondes du serveur) peut gêner un essai. Les `RAMP_TRIES` essais par sens limitent le risque ; si une
  arête manque au démarrage (`[Nav] rampe … : aucun trajet`), relancer le serveur.
- **Une corniche gardée ouvre aussi ses autres accès.** Rendre une corniche joignable par une rampe (et d'où l'on
  revient) rend aussi utilisables les descentes qui y mènent (toit → corniche de Dizzy, 35 studs). Sans air control sur
  les descentes, le bot gardait sa vitesse de course et dépassait la corniche (16 studs de large) : la descente vise
  désormais sa case en l'air, comme un saut.
- **Atterrir au milieu, pas sur le rebord.** La première version visait la case la plus proche du point de chute : sur
  Dizzy, le rebord extérieur de la corniche CT (X 2278, 1 stud de large au-dessus du vide). Le bot y arrivait à sa
  vitesse de course vers l'extérieur et, le trajet fini, la friction ne l'arrêtait qu'au-delà : 2 chutes sur 4
  passages. `pickLanding` pénalise désormais les cases de bord (`RAMP_EDGE_PENALTY`) sans les interdire : une
  corniche étroite sous le point de chute reste préférée à un sol intérieur bien plus bas.

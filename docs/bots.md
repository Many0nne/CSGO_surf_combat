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
     (on redescend par une descente).
3. **Cases gardées** : composante fortement connexe d'un point de `GroundSpawns` (on y va et on en revient). Écarte les
   dessus de murs et les fonds sans sortie.
4. **Points de passage** : cases regroupées par carré de `NAV_WAYPOINT_SIZE` studs et par étage (cases reliées à pied
   dans le carré), petites zones fondues dans leur voisine. Note fixe : vue (nombre de points visibles à hauteur des
   yeux, critère principal), hauteur, couvert (8 rayons), bonus de type (`rampe`, `echelle`, `escalier`, `fosse`,
   `couloir`, `piece`). Les murs d'air ne bloquent ni la vue ni le couvert.

Mesure sur Dizzy (09/11/2026) : 40 841 cases (29 319 gardées), 1 056 points, 294 000 arêtes de marche, 9 250
descentes, 4 500 sauts, 2 échelles ; **7,8 s** au démarrage (cases 4,0, marche 1,1, rebords 0,3, vue 2,1) avec
`NAV_BUILD_BUDGET` = 8 ms par frame ; **~45 Mo** de mémoire Lua serveur. Les bots attendent sur place que le plan soit
prêt (ils tombent du soleil pendant ce temps).

## Suivi de chemin

`BotNavigator` (un par bot vivant) : destination tirée au hasard parmi les points (la note dynamique et les états
viennent avec #141), chemin A* de case en case (`NavRules.findPath`, coût pondéré par type d'arête), puis à chaque tick :
- cible = la case la plus lointaine qu'on rejoint en ligne droite (`NavRules.lookAhead`, arêtes de marche seulement) ;
- saut quand le rebord (milieu de l'arête) est à moins de `vitesse × NAV_JUMP_LEAD_TIME` + rayon ; en l'air, il ne vise
  sa cible que sur une arête de saut ou d'échelle (sinon pas d'air control hors bunny hop, cf. ci-dessous ; le surf n'est pas simulé) ;
- échelle : dans le volume, vitesse de `LadderRules.climbVelocity` en poussant vers le mur, comme le joueur ;
- gêne : sans se rapprocher de sa cible pendant `NAV_STUCK_TIME`, nouveau chemin ; après `NAV_MAX_REPATH` essais sur
  la même case, l'arête est écartée `NAV_BAN_TIME` s pour ce bot (warn `[Nav] arête … ratée`) et il change de
  destination ; tombé sous le trajet, il repart de là où il est.

Mesure (5 bots, 2 min 30) : 33 destinations atteintes, 0 arête ratée, 23 descentes, 9 sauts, 13 échelles franchis.

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
- **Ouïe** : `BotManager.hearShot` (appelé par `init.server` sur l'action `Shoot` d'un joueur, et par `BotBrain` pour
  les tirs des bots). À moins de `HEARING_RADIUS` (200), position faussée d'au plus `HEARING_FUZZ` (20 %) de la distance.
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
  kill feed, mort, ragdoll, caméra du tué. Le hitmarker n'est envoyé qu'à un tireur joueur.
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
- `workspace:SetAttribute("DebugNav", true)` : points (couleur du rouge au vert et étiquette = numéro, type, note),
  arêtes entre points (gris marche, bleu descente, orange saut, vert échelle ; trait court = sens unique), chemin
  restant de chaque bot en jaune, au-dessus de chaque bot son état, sa destination et sa cible (blanc chercher,
  jaune enquêter, rouge combattre, bleu se replacer), trait rouge vers la cible en combat. `"cases"` : en plus chaque case (vert gardée, rouge écartée), lourd (~40 000 pièces).
- Console : `[Nav] Dizzy : …` à la fin de la construction (durée par phase), `[Nav] bilan` et `[Bots] bilan`
  (combats, tirs, touches et kills, coups de couteau, visées retenues par le délai de grâce, tirs entendus, enquêtes,
  replis, angles tenus, destinations biaisées) toutes les 30 s.
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

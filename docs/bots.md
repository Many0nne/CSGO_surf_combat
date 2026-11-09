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
  sa cible que sur une arête de saut ou d'échelle (sinon pas d'air control, le surf n'est pas simulé) ;
- échelle : dans le volume, vitesse de `LadderRules.climbVelocity` en poussant vers le mur, comme le joueur ;
- gêne : sans se rapprocher de sa cible pendant `NAV_STUCK_TIME`, nouveau chemin ; après `NAV_MAX_REPATH` essais sur
  la même case, l'arête est écartée `NAV_BAN_TIME` s pour ce bot (warn `[Nav] arête … ratée`) et il change de
  destination ; tombé sous le trajet, il repart de là où il est.

Mesure (5 bots, 2 min 30) : 33 destinations atteintes, 0 arête ratée, 23 descentes, 9 sauts, 13 échelles franchis.

## Debug (Studio)

- `workspace:SetAttribute("DebugBots", 5)` : nombre de bots (un round doit être actif : un joueur a demandé à apparaître).
- `workspace:SetAttribute("DebugNav", true)` : points (couleur du rouge au vert et étiquette = numéro, type, note),
  arêtes entre points (gris marche, bleu descente, orange saut, vert échelle ; trait court = sens unique), chemin
  restant de chaque bot en jaune. `"cases"` : en plus chaque case (vert gardée, rouge écartée), lourd (~40 000 pièces).
- Console : `[Nav] Dizzy : …` à la fin de la construction (durée par phase), `[Nav] bilan` toutes les 30 s.

## Pièges

- **Un rebord bas n'est pas une marche.** `NavRules.stepKind` classe en « marche » toute différence de hauteur
  inférieure à `walkRise` (marche + pente de 46° sur la distance : 5,3 studs sur 4), donc aussi un rebord vertical de
  4 studs, que le balayage refuse ensuite. Les rebords sont donc cherchés dans une passe à part, sur toute colonne non
  rejointe à pied ; sans elle, le plan n'avait aucune arête de saut.
- Le temps affiché est surtout de l'attente entre frames : le calcul est découpé par tranches de `NAV_BUILD_BUDGET`.
  Le monter raccourcit la construction mais charge les frames serveur du début de partie.
- Les dessus des murs d'air (escaliers) sont de vraies cases : c'est là que marchent les joueurs.

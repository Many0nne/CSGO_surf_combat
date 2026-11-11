# Maps

Référence pour modifier une map ou en construire une autre. Seule map du jeu : **Dizzy** (réplique de ar_dizzy).
Les maps précédentes (l'Arène et la ville ensablée) ont été retirées : leurs leçons sont dans « Maps retirées ».

## Choisir la map jouée

Chaque map est un `.rbxm` de `assets/rbx/Maps` (aujourd'hui `Dizzy.rbxm`), toutes synchronisées dans
`Workspace.Maps`. Au démarrage, le serveur (`src/shared/MapSelection.luau`) garde celle de `GameConfig.ACTIVE_MAP` (nom
du `.rbxm`), détruit les autres et pose l'attribut `ActiveMap` sur `Workspace.Maps` ; le serveur (`SpawnManager`) et le
client (`BoostSystem`) retrouvent la map jouée par `MapSelection.waitForActive`. Nom absent : repli sur `Dizzy`. Tout
code qui lit la map doit passer par là, jamais par un nom de map en dur. Rotation par round et vote : pas faits (une map
à la fois, choisie dans le code).

## Dizzy (map par défaut)

Toit d'un gratte-ciel au-dessus des nuages, reproduit d'après `ar_dizzy` (CS:GO, port CS2 `ar_dizzy.vpk` de ModDB) :
pièces, escaliers, mât central, deux grandes rampes de surf dans les fosses d'angle. Habillage à nous (béton, enduit
blanc cassé à bande bleu clair, tôle ondulée, acier, fût de tour aux fenêtres allumées, mer de nuages au
crépuscule). Jouable à pied, apparition au sol (24 points, `info_player_*` de l'original, attribut `Team`), pas de
boosts, mouvement et gravité du jeu inchangés.

- **Échelle** : 10 studs par mètre en plan, 7 en hauteur (`H_SCALE`, `V_SCALE` de `extract_dizzy.py`), environ
  560 × 600 studs, toit à Y = 0. Rampes de surf à ~62° (69° dans l'original). Une v1 à 5 et 3,5 studs par mètre
  (~310 × 330) a été jugée trop petite.
- **Mort** : `KillHeight` = haut du `trigger_hurt` de l'original (−89 studs). Le fût et les nuages sont sans collision.
- **Décalage** : la map est posée à (2000, 0, 0) pour ne pas se superposer à une autre map en mode Edit.
- **Murs d'air gardés** (`playerclip`, deux `func_brush` à rendu désactivé) : pièces invisibles, `CanQuery` vrai. Ils
  font partie du jeu : pentes invisibles à 20-25° sur les escaliers (contremarches de 0,41 m = 2,9 studs, au-delà de
  `STEPUP_HEIGHT`), bords fermés.

### Relevé du plan (sans trou)

Le plan `tools/map/dizzy_layout.json` est produit par `tools/map/extract_dizzy.py` : ne pas l'éditer à la main. Sources
hors dépôt (propriété de Valve, dépôt public) : `worktrees/.archive/ar_dizzy.1/ar_dizzy.vpk`, extraction et Source 2
Viewer dans `worktrees/.tools`. Le dépôt ne contient que des cotes et des pièces, ni maillage ni texture de Valve.

1. Extraire (une fois) avec Source 2 Viewer (`worktrees/.tools/vrf/Source2Viewer-CLI.exe`) dans
   `worktrees/.tools/dizzy_out` : `-f maps/ar_dizzy/world_physics.vmdl_c --gltf_export_format glb -d` (collision du
   monde) et `--vpk_filepath maps/ar_dizzy/entities/ -o .../ents --gltf_export_format glb -d` (entités et brushes).
2. Relever : `blender -b --factory-startup --python tools/map/extract_dizzy.py -- ../.tools/dizzy_out tools/map/dizzy_layout.json`
   (Blender sans interface, ~10 s ; ne pas le lancer dans la session Blender de l'utilisateur, le calcul la fige).
3. Vérifier : `blender -b --factory-startup --python tools/map/verify_dizzy.py -- ../.tools/dizzy_out tools/map/dizzy_layout.json`.
   Mêmes rayons (~500 000, verticaux et horizontaux) tirés dans la collision d'origine et dans les pièces relevées ;
   liste les trous et les surplus groupés, avec la pièce responsable. État au relevé : 6 groupes de 3-4 rayons, sur une
   seule ligne (fente d'un angle rentrant, déjà là avant les règles de bord), 0,7 % de rayons en surplus (décor approché
   par sa boîte).
   Scintillement : `tools/map/zfight_dizzy.py` (mêmes arguments, puis la tolérance), cf. « Scintillement » ci-dessous.
4. Générer : `lune run tools/map/build_dizzy.luau` (sans Studio, plugin Rojo déconnecté de ce serveur) écrit
   `assets/rbx/Maps/Dizzy.rbxm`. Puis `rojo build default.project.json -o CSGO.rbxlx && lune run tools/rbxm/verify_place.luau`.
   Le générateur mesure les rampes de surf et refuse d'écrire la map s'il reste un rebord (cf. « Rampes de surf :
   surface continue ») ; même mesure à la main : `lune run tools/map/verify_ramps.luau`.

Méthode et pièges (pour ne pas les redécouvrir) :
- **La collision du monde n'est pas faite de blocs** : c'est un maillage fermé (le toit d'un seul tenant), sols et murs
  en surfaces. La v1 le relevait par rayons verticaux tous les 0,5 m : murs fins et bords ratés, d'où ses trous. Seul le
  petit décor est en blocs convexes.
- **Chaque face plane devient une dalle** collée à la face, épaissie vers l'intérieur (moitié de l'épaisseur locale au
  plus, pour que les deux faces d'un mur fin ne se chevauchent pas). Sols, plafonds et pentes sont retirés de `EPS`
  (0,03 stud) sous leur face ; les murs sont posés sur leur face et gardent les arêtes saillantes (cf. « Scintillement »).
  Rectangles quand le plan s'y prête, sinon deux `WedgePart` par triangle. Couverture sans trou par construction.
- **Jonctions en T** : un sommet posé au milieu de l'arête du voisin, partout. Regrouper les triangles par plan, pas
  par arête commune (sinon chaque triangle est isolé : 65 000 pièces). Une couverture en rectangles n'est acceptée que
  si son aire égale celle des triangles, contrôlée par morceau source : un contrôle par triangle refuse deux
  demi-rectangles qui forment un rectangle exact (40 000 coins).
- **Solides qui se recouvrent** : la collision d'origine superpose des solides (moulure de 2,85 studs encastrée dans
  un mur, gaine dans un plafond) dont les faces sont dans le même plan. Relevées morceau par morceau, elles donnaient deux
  dalles sur la même surface, qui scintillaient (bandes horizontales sur les façades, ~8 000 paires visibles). Les faces
  sont donc regroupées par plan sur toute la map, en amas de triangles qui se touchent (`plane_groups`), et l'union de
  l'amas est couverte une seule fois ; les triangles identiques sont écartés (faces confondues visibles : 19 600 →
  14 000 studs²). Sans effet visible notable : ce n'était pas la cause principale du scintillement (ci-dessous).
- **Décor** : un bloc devient sa boîte orientée s'il est petit (< 8 studs, tuyaux) ou la remplit à 60 % ; jamais un mur
  d'air. Exiger la convexité ou 85 % doublait le nombre de pièces pour un gain faible. Axes de la boîte : écarter les
  résidus de projection (float32), sinon les axes ne sont plus orthonormés et la boîte part à 100 studs.
- **Repère** : Blender x = y source, y = −x source (pouces × 0,0254), vérifié par raycast (les spawns tombent tous
  0,406 m au-dessus d'un sol). Roblox (X, Y, Z) = (x·10, (z − 198)·7, −y·10).
- Écartés : boîte de ciel (`physics_sky`), échelles, fût sous 190 m (remplacé par le décor du générateur).
- Environ 14 000 pièces ancrées, dont ~10 000 coins, surtout aux plafonds.

### Scintillement (résolu le 05/11/2026)

Dizzy scintillait à distance : bandes sombres dentelées sur les façades, rayures sur les rebords. Mesure de référence
(`zfight_dizzy.py`, TOL 0,1) : 245 000 studs² de faces superposées avant, 33 000 après, dont la moitié entre murs (même
couleur, invisible). Quatre causes, chacune traitée par une règle de `extract_dizzy.py` :

1. **Tranche aux arêtes saillantes** (la principale) : la tranche d'une dalle de sol ou de plafond tombait dans le plan
   du mur voisin, 0,03 stud devant lui et dans une autre couleur. Le mur garde maintenant le coin : posé sur sa face
   (sans `EPS`), il monte jusqu'au plan du sol ; le sol ou le plafond recule de l'épaisseur de la dalle du mur moins
   `EDGE_OVERLAP` (`edge_shift`, épaisseur lue dans l'index `WallSlabs`, la plus mince du bord). Arêtes mur/mur et angles
   rentrants : rien ne bouge. Conséquence visible : le haut d'un rebord prend la couleur du mur sur l'épaisseur du mur.
2. **Ailettes** : un dessus ou dessous encadré par deux murs, qui reculerait jusqu'à disparaître, est écarté quand les
   tranches des murs le couvrent (`covered_by_walls`) ; sinon il est gardé tel quel (scintillement résiduel).
3. **Plaques minces** (< `THIN`, 0,35 stud) : la face cachée de la dalle du dessous restait à quelques centièmes de la
   face du dessus et scintillait (jusqu'à 2 400 studs² par plaque, toits métalliques). Seule la dalle du dessus est
   gardée (`thin_below`) : le dessous prend la couleur du sol.
4. **Faces enfouies** dans un autre solide (solides d'origine qui se recouvrent) : invisibles, mais la tranche de leur
   dalle affleurait dans un sol. Écartées quand le devant de la face est dans un solide (`buried`, ~2 000 dalles).

Les « détails » des façades qui disparaissent avec le scintillement étaient pour l'essentiel ces tranches : les rebords
et moulures restent en relief (collision comprise), mais leur face avant est un mur, de la couleur du mur. Les redonner
à voir est un travail d'habillage (teinte propre aux murs de faible hauteur, par exemple), pas de relevé.

Pièges rencontrés :
- un recul qui laisse un jour, même de 0,05 stud, au dos du mur ouvre une fente sur le vide (vue d'en haut) : la dalle
  reculée passe sous le mur (`EDGE_OVERLAP`) ;
- l'index des murs doit tester un `WedgePart` sur sa moitié de boîte, sinon un bord croit avoir un mur sous lui ;
- prendre l'épaisseur du mur le plus épais le long d'un bord ouvre un trou au-dessus des parties plus minces ;
- `verify_dizzy.py` (grille de 1 stud) ne voit une fente de quelques centièmes que si un rayon tombe dedans : relancer
  après chaque changement de règle de bord et comparer au relevé précédent.

Restes connus : environ 10 000 studs² de paires de couleurs différentes (plaques de toit dont le mur ne longe qu'une
partie du bord : recul annulé pour ne pas ouvrir de trou ; une face enfouie non reconnue en (2257, 42, -393)) ; trous :
6 groupes sur la ligne (42…62, 71, -309), fente déjà présente avant (3 groupes).

Mesurer : `tools/map/zfight_dizzy.py` (faces de même sens dans le même plan à TOL près, qui se recouvrent et sont vues
depuis l'air ; 0,005 : faces confondues, 0,1 : aussi les tranches proches). Diagnostiquer en jeu : `ViewportPointToRay`
+ `Raycast` depuis la vue fautive (MCP Studio, mode Edit) donne la pièce touchée et sa position au centième.

| Essai | Résultat | Statut |
|---|---|---|
| `EPS` 0,03 → 0,15 (retrait adaptatif sur les murs fins) | Rien de visible ; élargit les fentes des angles rentrants | Rejeté |
| `SmoothPlastic` sur murs et plafonds, ombres coupées sur les dalles fines et les plafonds | Rien de visible | Rejeté |
| Ombres globales coupées (test) | Rien : ce n'est pas l'éclairage, malgré le soleil rasant (`ClockTime` 17,9) | Rejeté |
| Faces confondues fusionnées par plan (`plane_groups`) | Rien de visible, mais vraie correction (doublons, 9 → 3 groupes de trous) | Gardé |
| Une couleur pour sols, murs et plafonds (test Studio) | Plus de bandes, mais map vide visuellement | Rejeté (DA) |
| Bords décalés à toutes les arêtes (saillante : recul de 0,18 ; rentrante : avance de 0,08) | Plus de scintillement, mais détails des façades effacés et fentes claires aux angles rentrants | Rejeté |
| Recul ciblé : seul le sol ou plafond recule derrière la dalle du mur, mur sans `EPS` ; ailettes, plaques minces et faces enfouies écartées | Plus de scintillement visible (validé en jeu) ; façades unies | Gardé |

### Rampes de surf : surface continue (#136)

Les deux grandes rampes (T vers (1805, 47, -414), CT vers (2195, 47, -107), 130 × 104 studs, 62°) avaient un rebord sur
leurs bouts latéraux : le joueur qui les longeait s'arrêtait net. Origine, identique sur les deux rampes (relevé, pas
habillage ni retouche) :
- **bandes de rive** d'ar_dizzy : dalles d'acier de 1,5 et 4,6 studs de large à chaque bout, 0,17 et 0,34 stud plus
  hautes que la dalle principale. Un mur d'air (`playerclip` d'origine) couvre toute la rampe au niveau des rives : c'est
  lui la surface de glisse, l'acier du milieu est 0,34 plus bas (rebord visible) ;
- **tranche des murs** : les murs sont posés sur leur face sans retrait (règle anti-scintillement), alors que les dalles
  de pente et les murs d'air sont retirés de `EPS` (0,03) : la tranche des murs des bouts et des marches des rives
  dépasse de 0,03 stud sur 1,5 à 2,6 studs de large. Le mouvement fait des `Blockcast` avec une peau de 0,015 stud :
  0,03 suffit à arrêter le surfeur ;
- **angles aigus** du bas et du haut de la pente : une dalle de plafond (dessous de la rampe) ou de mur (dos de la crête)
  épaissie vers l'intérieur perce la pente sur 1 à 2 studs (+0,5 à +0,8).

Correctif : règle du générateur (`tools/map/RampEdges.luau`, appliquée après les retouches, testée), pas une retouche
par coordonnées. Par rampe : une **peau** d'acier d'un seul tenant (0,6 stud) couvre toute l'emprise au niveau des
rives ; toute autre pièce qui entre dans la peau est rognée à son dos, découpe exacte en coins (section perpendiculaire
à la longueur de la rampe). Le mur d'air d'origine, d'un seul tenant, reste. Une pièce qui monterait à plus de 1,5 stud
au-dessus de la surface (`MAX_RISE`, plus haut rebord rogné sur Dizzy : 0,99) traverse la rampe : la génération
s'arrête au lieu de la rogner. Mesure (`RampCheck`, rayons le long de la normale tous les 0,25 stud en longueur et
0,5 en pente, collision puis rendu, tolérance 0,02 stud ; signale rebords, creux et trous) :

| Rampe | Avant (collision / rendu) | Après |
|---|---|---|
| T | +0,52 et creux de 0,28, sur 1 140 studs² / +0,86 sur 2 120 studs² | 0,000 / 0,000, aucun trou |
| CT | +0,79 et creux de 0,28, sur 1 000 studs² / +1,13 sur 2 030 studs² | 0,000 / 0,000, aucun trou |

En jeu, lancé à 40 studs/s le long de chaque rampe vers chaque bout, en haut et en bas de la pente : vitesse constante
jusqu'au vide (bout ouvert) ou jusqu'au mur de la fosse (bout fermé, x 1870 et 2130 : mur relevé, pas un rebord),
hauteur au-dessus de la pente constante. Aucune pièce décorative n'est posée sur les rampes.

Pièges :
- **le joueur s'enfonce d'environ 0,3 stud** en atterrissant sur une rampe (mouvement, mesuré en jeu sur la rampe CT) :
  une face cachée juste sous la surface l'arrête. Première version rejetée : acier remonté au niveau des rives et seules
  les pièces qui dépassaient rognées ; la surface était plate, mais le joueur lancé en haut de la rampe CT s'arrêtait à
  8 studs du bout sur la tranche d'un mur enfoui (marche d'origine des rives). D'où la peau de 0,6 stud sans aucune
  face en travers dessous. Toute rampe de surf doit en être là ;
- une pièce qui dépasse sans être extrudée dans la longueur de la rampe n'est pas rognée : la mesure arrête alors la
  génération (bilan pièce par pièce). Le mur qui remonte après la crête de la rampe CT entre de quelques centièmes dans
  l'emprise (angle rentrant, parallèle au surf) : les rayons du bord sont tirés à 0,05 stud de l'arête ;
- un relevé neuf (`extract_dizzy.py`, Blender 5.2.3) ne redonne pas le `dizzy_layout.json` versionné (14 606 pièces
  au lieu de 14 019) : ne pas corriger les rampes en relançant le relevé sans comparer toute la map.

### Corriger un détail de Dizzy

La géométrie est régénérée en entier depuis le relevé : **une retouche faite dans Studio est perdue** (Rojo la supprime
à la connexion, la régénération l'écrase), et `dizzy_layout.json` est réécrit à chaque relevé. Selon le cas :
- **détail à un endroit** (fente, mur d'air gênant, bloc à ajouter ou à déplacer, teinte d'une salle) : une ligne dans
  `tools/map/dizzy_patches.luau`, voir ci-dessous. Ne demande que Lune (pas les sources de Valve) ;
- habillage d'un rôle (sols, murs, rampes, plafonds, décor) : tables `LOOK` et `DECOR` de `build_dizzy.luau` ;
- règle de relevé (échelle, épaisseur, simplification du décor) : constantes de `extract_dizzy.py`, puis relever,
  vérifier, générer (sources de Valve nécessaires, sur le poste qui les a).

**Retouches locales** (`tools/map/dizzy_patches.luau`, appliquées par `tools/map/DizzyPatches.luau`, testé) : une liste
de retouches appliquées dans l'ordre après le plan relevé, qui survivent à la régénération et à un nouveau relevé.
1. Repérer l'endroit dans Studio (Rojo connecté au worktree) : sélectionner la pièce, lire sa `Position`, ou poser le
   personnage dessus en playtest. Coordonnées du monde telles quelles (la map est décalée de 2000 en X).
2. Ajouter la retouche, avec un `why` qui dit pourquoi :
   - `remove` : retire les pièces dont le centre est dans une zone (`zone = { center, size }`), avec `folder` pour viser
     un seul dossier (`Clips` pour un mur d'air, `Floors`, `Walls`, `Ceilings`, `Ramps`, `Decor`) ;
   - `add` : ajoute une `Part` ou une `WedgePart` (`position`, `size`, `rotation` en degrés, `look` = rôle ou
     `decor:<groupe>`, `clip` pour un mur d'air) ;
   - `restyle` : rhabille les pièces d'une zone (`look`) ;
   - `group` (remove, restyle) : ne vise que les blocs de décor d'un groupe source (attribut `Group` : `metal`,
     `stucco`…), pour rhabiller une structure sans les objets posés dessous.
   **Toujours un `folder` quand la zone touche un mur d'air** : `restyle` sans dossier rend visible le `Clip` rhabillé
   (piège rencontré sur les planches de la fosse : 10 murs d'air pris dans la zone). Comparer le nombre de pièces
   affiché par la génération à celui attendu.
3. Plugin Rojo déconnecté, `lune run tools/map/build_dizzy.luau` (affiche le nombre de pièces touchées par chaque
   retouche), puis reconnecter et accepter le patch.
Une zone qui ne contient aucune pièce arrête la génération (coordonnées fausses, ou pièce disparue après un nouveau
relevé : revoir la retouche). Une pièce issue d'une retouche porte l'attribut `Patch` (son `why`), visible dans Studio.
Lecture de la position hors moteur : `CFrame.Position` (dans Lune, `Position` n'existe pas sur une pièce posée par
`CFrame`).

### Habillage détaillé (`tools/map/DizzyDressing.luau`)

Là où le relevé ne donne qu'une boîte ou un trou, l'objet est construit pièce par pièce par `DizzyDressing.build`
(dossier `Dressing` de la map), appelé par `build_dizzy.luau` après les retouches. Chaque objet est décrit une fois côté
T (tables `AIR_HANDLERS`, `GARAGES`, `WINDOWS`, `LAMPS`, coordonnées du plan relevé sans le décalage) et recopié côté CT
par `mirror` : la map est symétrique par un demi-tour autour de (0, -260,1).

- **Groupes de climatisation** (6 : deux par balcon de bord, un par toit haut) : remplacent les caissons relevés en
  boîtes empilées (retirés par `dizzy_patches.luau`). Même emprise (38 × 18) et même hauteur de caisson ; châssis sur
  longerons, portes de visite, grille d'aspiration, deux ventilateurs carénés, coffret électrique, tuyaux frigorifiques.
- **Extracteurs d'air « champignon »** (deux par estrade d'angle, une estrade par camp, au bord de la map) : remplacent
  les boîtes tournées relevées. Fût rond cerclé, bande d'aspiration à lames, chapeau en dôme.
- **Portes de garage** (une par camp) : auvent en tôle à tirants, deux lampes dessous, conduits et câble sur la façade.
- **Murs du milieu** (façades de part et d'autre de la fosse centrale) : les deux baies par mur, relevées comme des
  trous (tableau de 2 studs), sont vitrées (vitre, cadre à meneaux, appui) ; trois lampes murales sous les baies.
- **Bois** (retouches `restyle`, habillages `plywood`, `planks`, `timber` de `LOOK`) : plateau en contreplaqué et
  charpente des rampes sur pilotis, planches posées sur la fosse centrale. Les rampes de surf restent en acier.

- **Échelles** (une par camp, mur du bout des rampes sur pilotis) : relevées en boîtes (crinoline en morceaux de sol et
  de plafond, décollée du mur) et coiffées de murs d'air qui bloquaient la tête ; retirées par `dizzy_patches.luau` et
  reconstruites (`LADDERS` : rails, barreaux, pattes, crosses par-dessus l'acrotère, arceaux scellés au mur). Grimpables
  par un volume invisible de `Maps.Map.Ladders` (cf. « Ce que le code attend de la map »).
- **Objets rhabillés sur place** (`REDRESS`) : une boîte du relevé (repérée par zone, groupe source et volume) devient
  invisible mais garde sa collision, et reçoit un habillage sans collision : sacs de sable en rangs croisés (`stucco`),
  caisses en bois, parpaings, piles de plaques de plâtre, cales. Sert aux deux chantiers des étages et aux sacs sous la
  rampe CT. Une zone vide arrête la génération, comme une retouche.

- **Grue** (#166, unique, au bord nord) : socle en barricade de contreplaqué (`CRANE` : quatre faces de 4 × 3 panneaux,
  joints sombres, vis le long des chants, cornières et lisses en bois) ; mât en treillis jaune (membrures, entretoises,
  diagonales en zigzag), plateforme, flèche jusqu'au chariot relevé, contre-flèche lestée, cabine, pylône et tirants,
  câbles de levage jusqu'à la charge relevée. Le bloc du mât reste (invisible) pour la collision.
- **Bardage** (`CLADDING`) : pans de tôle ondulée (nervures tous les ~1,6 stud, bande de couleur, couvertine,
  cornières) sur tout le bloc garage + bâtiment du milieu : façade du garage éclairé, volume de l'échelle, mur de la
  zone de stockage, et depuis #189 la façade du milieu sur la fosse et le pan sud derrière le stockage. Un pan est un
  rectangle sur le nu du mur ; `holes` y laisse des ouvertures (baies de `WINDOWS` avec leur appui, bordées d'un cadre ;
  encoche sous la bande d'acier relevée en haut de la façade du milieu), découpées par `DizzyDressing.minus` en
  rectangles disjoints (jamais deux plaques l'une sur l'autre). Teinte (`CLAD_STYLE`, #189) : `white`, tôle blanc cassé
  à bande bleu clair de 3 à 9 studs au-dessus du bas du pan, comme les murs peints (retenu sur planche) ; `grey`, tôle
  grise à bande basse ocre de la hauteur `band` du pan (lot #166). Les lampes de la façade du milieu sont avancées sur
  les nervures.
- **Façades peintes** (#189) : tout l'enduit des murs relevés est blanc cassé (`PLASTER` de `build_dizzy.luau`,
  murets, acrotères et fût de la tour compris). Bande bleu clair (`BANDS`, `FACADE_BLUE`) sur les bâtiments non bardés
  (toit haut, cabane du bord sud, abri à porte unique), 3 à 9 studs au-dessus de leur sol : les dalles de mur relevées
  dont le centre est dans l'emprise sont **découpées** à la hauteur de la bande (`paintBands`), aucune plaque posée
  devant (pas de faces confondues, collision identique). Les coins (`WedgePart`) ne sont pas découpés : petites
  coupures possibles dans la bande là où le mur est fait de triangles (abri à porte surtout). Une emprise qui ne coupe
  aucun mur arrête la génération.
- **Porte** (`DOORS`) : double porte (bâti, vantaux à oculus, poignées, plaques de propreté, seuil, plaque jaune,
  lampe) sur l'aplat sombre relevé près de la rampe sur pilotis. Côté T, le relevé n'a que le vantail (pas d'aplat) :
  zone élargie en conséquence. Depuis #189, même porte sur l'aplat de la façade est du toit haut (1885, 115, -323),
  côté T seulement (`unique`) : aplat, vantail et seuil relevés cachés par `REDRESS`. Repère 0,28 devant le nu du mur
  (et non sur la face de l'aplat, 0,49 devant ici), pour que la plaque et la lampe touchent le mur.
- **Groupes du toit du garage** (`ROOF_UNITS`) : caisson blanc, ventilateur sur le dessus, capot à lames qui dépasse
  au-dessus de la façade, sur le socle relevé (gardé).
- **Zone de stockage** (chantiers des étages, contre le mur en tôle) : deux bobines de câble empilées à la place de la
  bobine relevée (environ 740 faces par côté, rendues invisibles), palette debout et palette au sol chargée de seaux
  (`BUCKETS`), sacs de ciment sur palette à la place des sacs de sable (`cement`). Piège : la bobine relevée a des faces
  jusqu'à 10 studs de son axe, dont des pentes rangées dans `Ramps` ; une zone carrée de 11 studs en laissait la moitié
  (restes beiges vus en jeu). Zone ronde (`zone.radius`) et `maxVolume` pour épargner le mur et les parpaings. Côté CT,
  elle n'est pas le symétrique exact du côté T (2 studs d'écart) : `REELS` donne une bobine par côté, pas `mirror`.

- **Fosse centrale** (#187, unique, sous la pergola) : fûts rouges cerclés à la place des cubes relevés (`barrel`, groupe
  `rock` de plus de 300 studs³, plus le fût isolé `metal_barrel`), parpaings creux (`hollowblock` : alvéoles ouvertes
  dans l'axe de la dimension moyenne, le bloc relevé peut être couché ou debout), piles de contreplaqué cerclées de
  feuillards (`plystack` ; une planche debout du relevé devient la tranche d'une pile), palettes et chevrons en bois.
  Six baladeuses sous cage (`PIT_LAMPS`, fil en guirlande sous les deux poutres longitudinales, SpotLight sans ombre).
- **Charge de la grue** (#187) : fagot de poutrelles en H sur deux rangs, cales en bois, deux élingues ceinturées et
  quatre brins jusqu'à la moufle (`CRANE.bundle` = boîte relevée, gardée invisible pour la collision). La moufle a été
  remontée (`CRANE.load` 98,55 → 125) pour que les brins tombent à ~45°.
- **Clôtures grillagées** (#187, groupes `passbullets_chainlink` et `chainlink`) : poteaux et lisses en tube
  galvanisé, grillage en losanges rendu par une `Texture` sur les deux faces d'un panneau invisible (`Transparency` 1 :
  la texture reste affichée). La boîte relevée garde sa collision. Image : `tools/map/chainlink.py` →
  `tools/map/chainlink.png`, publiée en Decal, id de l'image dans `DizzyDressing.CHAINLINK`. La planche Blender ne
  montre pas le grillage (pièce invisible) : le juger dans Studio.

Rhabillages sans habillage (`kind = "hide"` de `REDRESS`) : la boîte devient invisible et garde sa collision, l'objet
est construit à part (grue, porte, groupes du toit, bobines). `folders` vise d'autres dossiers que `Decor` (la bobine
relevée est faite de murs, sols et plafonds) ; sans `group`, toutes les pièces visibles dont le centre est dans la zone
sont prises : garder la zone serrée (le mur voisin y entrerait). Contrôle : la colonne `collide` de `audit_map` ne doit
pas bouger, sauf dans `Geometry/Walls` du fait des bandes (chaque dalle découpée compte trois pièces, même union).

Ombres : un objet plaqué contre un mur (bardage, barricade, porte) a l'ombre coupée (`flat`), elle se confond avec
celle du mur ; idem pour les barres fines du treillis. Sans ça, le lot #166 ajoutait 17 % de pièces qui projettent une
ombre (+3 % avec). Lot #189 (`audit_map`, avant/après) : 18 614 → 19 927 pièces (+7 %, surtout les nervures du bardage
blanc, coupées en trois par la bande), 2 074 → 2 135 pièces qui projettent une ombre (+3 %, murs découpés), une
lumière de plus (porte du toit haut).

Repérer les façades à habiller : les vues à hauteur d'œil de la planche (spawn, fosse, toits) disent mieux quels murs
se voient en jeu qu'un relevé des dalles par le calcul (murs fins en double face, flancs de la tour qui descendent
jusqu'au pied du toit) ; puis lire les cotes exactes des dalles de `Walls` (nu = centre ± demi-épaisseur) dans le
`dump_parts`.

#### Planche Blender d'un habillage

Avant d'intégrer un habillage dans Roblox, le faire valider sur une planche rendue depuis les points de vue des
captures de l'utilisateur, avec exactement les pièces du générateur :
1. `lune run tools/map/build_dizzy.luau` (plugin Rojo déconnecté de ce serveur), puis
   `lune run tools/map/dump_parts.luau -- <sortie.json> [x y z rayon]` (pièces visibles du `.rbxm` et leurs SpotLight ; blocs, coins, cylindres et boules seulement, les autres formes sont
   signalées et sautées au rendu).
2. Écrire les vues (`[{ "name", "position", "target", "fov"?, "res"?, "percent"? }]`, coordonnées du monde, FOV
   vertical 90 par défaut comme le jeu), puis
   `blender -b --factory-startup --python tools/map/render_dizzy.py -- <pièces.json> <vues.json> <dossier>`.
   Par défaut Workbench : couleurs des pièces, ombres dans la direction du soleil du jeu, ~1 s par vue. EEVEE
   (`DIZZY_EEVEE=1`, éclairage du crépuscule) prend 5 minutes par vue sur la carte graphique intégrée du poste (plus de
   30 min pour une planche de 7 vues, jugé trop long) : ne s'en servir que pour une image finale isolée. Les tuiles de
   la map à plus de `radius` studs de la caméra (300 par défaut) ne sont pas rendues.
3. Retrouver un point de vue d'une capture : la hauteur d'œil est à ~5 studs au-dessus du sol, le FOV vertical est 90 ;
   comparer la vue rapide à la capture et ajuster.
La planche n'a ni les textures des matières Roblox ni l'Atmosphere : elle juge la composition, pas le rendu final.

Repères : `DizzyDressing.aim(pos, look)`, jamais `CFrame.lookAt`. Sous Lune, `lookAt` a renvoyé un repère retourné
pour une visée vers +Z (auvent du garage enfoncé dans le mur, alors que les fenêtres visées vers ±X étaient justes) et
un repère invalide pour un tube vertical (pièce rejetée à y = -1 000 000). Contrôle : aucune pièce de `Dressing` hors
de la map, aucune derrière le nu du mur qu'elle habille.

Collision : seuls les volumes porteurs (caisson, châssis et viroles des groupes, fût et chapeau des extracteurs) la gardent ; tout le reste est sans
collision ni requête. Lumières : `SpotLight` sans ombre (19 au total).

Aperçu dans Studio sans reconnecter Rojo : le MCP refuse `HttpService` vers `localhost` (liste blanche de l'assistant),
donc pas de `loadstring` d'un fichier servi en local depuis `execute_luau` ; il faut envoyer le code lui-même. Les
captures (`screen_capture`) sont blanches tant que la fenêtre Studio n'est pas au premier plan.

## Maps retirées (leçons)

L'Arène (#71, anneau de dunes surfables face à face façon surf_japan, au-dessus du vide) et, avant elle, la ville
ensablée (#69, ville moderne à moitié engloutie par le sable) ont été retirées avec leurs générateurs, leurs matières
(`ArenaFacade`, `ArenaCliff`), le mesh des virages et le sable en Terrain (`DuneField`, `MapTerrain`). Récupérables dans
l'historique git (PR de retrait de l'Arène). Les mécaniques génériques restent : boosts, mort par chute, lancement
depuis le soleil (voir « Ce que le code attend de la map »).

- **Échelle** : la ville à ~1 000 × 1 100 studs était trop grande (à 8 on ne se croise pas) ; ~450 × 450 studs pour
  6 à 10 joueurs.
- **Plan** : une avenue droite bordée de blocs alignés est trop répétitive ; des rampes courtes et isolées ne
  permettent pas d'accumuler de la vitesse (d'où l'anneau de l'Arène, ~1 300 studs de rampe sans interruption).
- **Rampes en raccourcis, pas en passage obligé** dans une map où l'on se bat à pied.
- **Sable** : une texture générée (sable ondulé) a été jugée horrible, la matière Sand de Roblox est restée ; des
  bosses en calottes de sphère font trop « Roblox ». Le relief en Terrain suit exactement la surface visible (un mesh
  Blender aurait une collision approchée). Le sable ne doit jamais dépasser de la surface d'une rampe.
- **Pistes de plan gardées de côté** : « La Digue » et « L'Échangeur », maquettes dans
  `docs/maps/plans-arene-digue-echangeur.html`.

## Matières (MaterialVariant)

Dizzy n'en utilise pas ; `assets/rbx/Materials` reste versionné vide (`.gitkeep`) pour une future map.

- Générées dans Studio par le MCP (`generate_material`, une description par matière). Chaque génération donne
  4 variantes rangées dans un dossier de `MaterialService` : les comparer sur un mur d'échantillons, garder la
  meilleure à la racine de `MaterialService` sous son nom définitif, supprimer le reste. Les textures sont hébergées par
  Roblox, rien à publier.
- Versionnées dans `assets/rbx/Materials/<Nom>.rbxm` (Rojo : `MaterialService`), exportées par `studio_export.luau`
  (`lune run tools/rbxm/receive.luau`, `lune run tools/map/serve.luau`, puis dans Studio
  `return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/studio_export.luau"))()`, cf.
  `docs/assets.md`). Une MaterialVariant ajoutée à la main sans être exportée est supprimée à la connexion Rojo.
- Piège : `rojo serve` ignore un dossier `$path` créé après son démarrage. Il sert alors un `MaterialService` vide et,
  à chaque connexion, retire les matières de Studio sans les recréer. Relancer le serveur
  (`csgo-worktree.ps1 <branche> -Stop`, puis sans option). D'où le `.gitkeep`.
- La couleur de la pièce ne teinte presque pas une MaterialVariant : la teinte vient de la texture (et de la lumière
  du crépuscule). Pour changer la couleur, régénérer la matière.
- `verify_place.luau` échoue si une pièce de la map pointe vers une MaterialVariant absente (sinon elle retombe en
  silence sur sa matière de base), ou si une matière n'a pas de texture.

Rojo gère `Workspace.Maps` : un objet posé à la main dans une map est supprimé à la connexion s'il n'est pas dans son
`.rbxm`. Ne jamais réécrire un `.rbxm` de map pendant que Studio est connecté à ce serveur Rojo.

## Ce que le code attend de la map

- `Maps.Map.SunLaunch` : parties invisibles ; position = point d'apparition, `LookVector` = direction du lancement,
  attribut `Speed` (studs/s). `SpawnManager` en tire une au hasard, pose `LaunchOrigin` et `LaunchVelocity` sur le
  personnage ; `MovementController` les applique une fois (position, vitesse en l'air, caméra tournée vers la map,
  `SpawnLaunch.cameraAngles`).
- `Maps.Map.Ladders` : volumes invisibles (aucune collision ni requête), `LookVector` = normale sortante du mur. Dans
  le volume (marge `CHAR_RADIUS`), `MovementController` remplace la physique par `LadderRules.climbVelocity` : avancer
  monte (regard baissé : descend), reculer descend, de côté on glisse le long, saut = poussée hors du mur
  (`LADDER_*` de `MovementConfig`). Le volume doit dépasser le haut du mur d'environ une hauteur de corps, sinon on
  reste coincé sous l'acrotère ; aucun mur d'air ne doit avancer devant le mur à la hauteur de la grimpe.
- `Maps.Map.GroundSpawns` : repli quand la map n'a pas de lanceur.
- `Maps.Map.Boosts` : volumes invisibles (`CanCollide`, `CanQuery`, `CanTouch` faux), attribut `Kind` :
  `Geyser` / `Launcher` avec `Velocity` (Vector3 imposé), `Portal` avec `Boost` (studs/s ajoutés), `Cooldown`
  optionnel. Le client teste sa position dans la boîte (marge `CHAR_RADIUS`) à chaque frame : un portique doit être
  assez épais (14 studs) pour ne pas être traversé entre deux frames à 300 studs/s. Le visuel est à part
  (`BoostFx`).
- Attribut `KillHeight` sur `Maps.Map` : mort sous cette hauteur (absent : pas de mort par chute). C'est le client
  qui détecte la chute : **le serveur ne voit pas la position des joueurs** (racine ancrée, mouvement fait par le
  client ; côté serveur le personnage reste figé à son point d'apparition). Une première version qui testait la
  position côté serveur ne tuait jamais personne.
- La lumière est dans `default.project.json` (Lighting + Atmosphere), identique à celle du menu (`MenuScene`) :
  `ClockTime` 17.9 et latitude 0. Des lanceurs `SunLaunch` doivent viser `Lighting:GetSunDirection()` (Y retiré) pour
  qu'on sorte du soleil : changer l'heure oblige à les réorienter. Jugée un peu sombre le 06/11/2026 : éclaircie par
  les ambiances (`OutdoorAmbient` 122,110,130, `Ambient` 74,69,88), `Brightness` 3.6 et `ExposureCompensation` 0.35,
  sans toucher à l'heure ni à l'Atmosphere.

## Règles de construction

- **Pentes** : surfable entre 46° et 84° (`MovementConfig.SURF_NORMAL_Y`, `SURF_NORMAL_MIN`), marchable en dessous,
  mur au-delà. Viser 50-62° pour le surf, 30-40° pour une pente qu'on monte à pied.
- **Une rampe de surf est longue à l'horizontale, avec la pente en travers.** On surfe le long de la rampe, pas dans
  le sens de la pente. Piste rejetée : une tour penchée sur sa longueur (sommet en l'air) n'offre que sa largeur
  (~30 studs) dans le sens du surf. Une tour tombée se pose à l'horizontale, roulée sur son axe : une face à ~55°
  (surf, arêtes ambrées), la face voisine à ~35° (on y monte à pied).
- **Talus** : `WedgePart` dont le côté haut est le +Z local (vérifié par raycast).
- **Murs invisibles** : `CanQuery` doit rester vrai. Le mouvement est fait maison et détecte les collisions par
  raycast : un mur ignoré par les requêtes ne bloque pas le joueur.
- **Sol** : la `Baseplate` a été retirée du projet. Son dessus à y = 0 coïncidait avec le sol de la ville et
  scintillait.

- **Ombres : décidées par le générateur, pas à la main.** `build_dizzy.luau` coupe `CastShadow` à la fin de la
  génération (#88) :
  - sur toute pièce de moins de 2 studs dans toutes ses dimensions (`SMALL_SHADOW`), dont l'ombre est minuscule ;
  - sur toute pièce entièrement dans l'ombre d'autres pièces opaques (`tools/map/ShadowCulling.luau`). Son ombre tombe
    déjà dans celle de ses masques, donc rien ne change à l'image. Avec un soleil à 1,4° au-dessus de l'horizon, c'est
    le cas de la plupart des pièces : il reste 1 949 pièces qui projettent une ombre, sur 15 300.
  
  Le calcul suit la direction du soleil `SUN` de `build_dizzy.luau`, relevée dans Studio (`Lighting:GetSunDirection()`)
  pour `ClockTime` 17,9 et `GeographicLatitude` 0. Si l'heure change (`default.project.json`, `MenuScene`), il faut la
  relever de nouveau : le générateur refuse de tourner tant que `default.project.json` ne correspond plus. Seules les
  boîtes et les coins opaques servent de masque : un cylindre ou une boule, approchés par leur boîte, masqueraient trop.
  Une pièce ajoutée à la main dans Studio ne passe pas par ce calcul.
- **Nuages** : deux nappes translucides (quatre avant #88). Chaque nappe se dessine sur tout l'écran quand on regarde
  vers le bas, d'où un coût GPU par nappe ; l'opacité cumulée est gardée.

## Pièges

- **Captures en mode Edit** (`screen_capture`) : un viewport entièrement blanc, même sur une scène connue, vient de la
  fenêtre Studio réduite ou en arrière-plan. La mettre au premier plan.
- **Brume** : l'Atmosphere du crépuscule (densité 0.33) noie les vues aériennes ; pour juger un plan d'en haut, la
  vue au sol et à hauteur de toit est plus parlante qu'une vue de dessus.
- **Caméras de capture** : une caméra posée au hasard tombe souvent dans un bloc. Calculer les positions dans le
  repère du plan du générateur.

- **Virages en segments** : avec le ClipVelocity Source, chaque jointure entre deux WedgePart retire ≈ 1 - cos de
  l'angle entre segments, soit une perte en 1/N ; mesuré sur l'Arène à 36 segments par demi-tour : -14 % d'énergie
  sur un virage (#71). Correction possible plus tard, dans le mouvement : entre deux facettes de surf presque
  parallèles, réorienter la vitesse au lieu de la clipper (essai : -0,2 %). Mesure : sans perte, l'énergie
  (½v² + g·h) reste constante. Visuel lisse possible en mesh sans collision (`CanQuery` faux) par-dessus des
  segments de collision invisibles ; un recouvrement coplanaire entre mesh et rampe droite scintille.
  - **Pistes rejetées sans toucher au mouvement** : plus de segments (72 : instable, de -5 % à l'arrêt ; 144 : -90 %),
    tranches de collision en mesh (CollisionFidelity Hull, de 36 à 144 : le surfeur s'arrête dans tous les cas ;
    l'enveloppe flotte ~0,6 stud au-dessus de la vraie surface). Cause probable : collé à la pente, le balayage du
    personnage démarre souvent dans une pièce (que Roblox ignore alors) et touche la face de jointure de la voisine,
    prise pour un mur. Seule la correction du mouvement supprime la perte.
- **Muret plus bas que le centre du corps** (bord de Dizzy derrière les extracteurs, 3,6 studs) : la sonde de sol (sphère
  partie du centre du corps) accrochait son arête, prise pour un sol trop pentu, et le joueur passait en l'air à chaque
  frame, collé au muret au lieu de le longer. Un contact plus haut que `STEPUP_HEIGHT` au-dessus des pieds est ignoré et
  la sonde relancée depuis la hauteur de marche (`GroundDetection`, `PhysicsUtils.isSideContact`).
- **Rebord en bout de rampe** : un écart de plus de quelques dixièmes entre la fin d'une rampe et le dessus du mur
  voisin accroche le joueur ; le raccorder par une planche (retouche `add`) plutôt que de toucher au mur relevé.
- **Rebord sur une rampe de surf** : quelques centièmes de marche en travers du surf suffisent à arrêter le joueur, et
  il s'enfonce d'environ 0,3 stud à l'atterrissage. Sur une rampe de surf : une seule pièce en surface, aucune face en
  travers à moins de 0,6 stud dessous (`RampEdges`, cf. « Rampes de surf : surface continue »).
- **Décor sans collision** : toute pièce décorative (arêtes néon, bandes, colonnes de geyser) doit avoir `CanQuery`
  faux, sinon les raycasts du mouvement la prennent pour un mur ou une rampe.

## Reste à faire

- Plus tard : supprimer la perte de vitesse restante dans les virages (correction du mouvement, voir les pièges).
- Son et effet au déclenchement d'un boost.

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
pièces, escaliers, mât central, deux grandes rampes de surf dans les fosses d'angle. Habillage à nous (béton, enduit,
acier, fût de tour aux fenêtres allumées, mer de nuages au crépuscule). Jouable à pied, apparition au sol (24 points,
`info_player_*` de l'original, attribut `Team`), pas de boosts, mouvement et gravité du jeu inchangés.

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

Repères : `DizzyDressing.aim(pos, look)`, jamais `CFrame.lookAt`. Sous Lune, `lookAt` a renvoyé un repère retourné
pour une visée vers +Z (auvent du garage enfoncé dans le mur, alors que les fenêtres visées vers ±X étaient justes) et
un repère invalide pour un tube vertical (pièce rejetée à y = -1 000 000). Contrôle : aucune pièce de `Dressing` hors
de la map, aucune derrière le nu du mur qu'elle habille.

Collision : seuls les volumes porteurs (caisson, châssis et viroles des groupes, fût et chapeau des extracteurs) la gardent ; tout le reste est sans
collision ni requête. Lumières : `SpotLight` sans ombre (10 au total).

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
  qu'on sorte du soleil : changer l'heure oblige à les réorienter.

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
- **Décor sans collision** : toute pièce décorative (arêtes néon, bandes, colonnes de geyser) doit avoir `CanQuery`
  faux, sinon les raycasts du mouvement la prennent pour un mur ou une rampe.

## Reste à faire

- Plus tard : supprimer la perte de vitesse restante dans les virages (correction du mouvement, voir les pièges).
- Son et effet au déclenchement d'un boost.

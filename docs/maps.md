# Maps

Référence pour modifier une map ou en construire une autre. Map jouée par défaut : **Dizzy** (réplique de ar_dizzy).
Autres maps : l'« Arène » (versionnée, sélectionnable) ; la « ville ensablée » (#69), ancienne map, générateur gardé.

## Choisir la map jouée

Chaque map est un `.rbxm` de `assets/rbx/Maps` (`Map.rbxm` = l'Arène, `Dizzy.rbxm`), toutes synchronisées dans
`Workspace.Maps`. Au démarrage, le serveur (`src/shared/MapSelection.luau`) garde celle de `GameConfig.ACTIVE_MAP` (nom
du `.rbxm`), détruit les autres et pose l'attribut `ActiveMap` sur `Workspace.Maps` ; le serveur (`SpawnManager`) et le
client (`BoostSystem`) retrouvent la map jouée par `MapSelection.waitForActive`. Nom absent : repli sur `Map`. Tout code
qui lit la map doit passer par là, jamais par `Maps.Map`. Rotation par round et vote : pas faits (une map à la fois,
choisie dans le code).

## Dizzy (map par défaut)

Toit d'un gratte-ciel au-dessus des nuages, reproduit d'après `ar_dizzy` (CS:GO, port CS2 `ar_dizzy.vpk` de ModDB) :
pièces, escaliers, mât central, deux grandes rampes de surf dans les fosses d'angle. Habillage à nous (béton, enduit,
acier, fût de tour aux fenêtres allumées, mer de nuages au crépuscule). Jouable à pied, apparition au sol (24 points,
`info_player_*` de l'original, attribut `Team`), pas de boosts, mouvement et gravité du jeu inchangés.

- **Échelle** : 10 studs par mètre en plan, 7 en hauteur (`H_SCALE`, `V_SCALE` de `extract_dizzy.py`), environ
  560 × 600 studs, toit à Y = 0. Rampes de surf à ~62° (69° dans l'original). Une v1 à 5 et 3,5 studs par mètre
  (~310 × 330) a été jugée trop petite.
- **Mort** : `KillHeight` = haut du `trigger_hurt` de l'original (−89 studs). Le fût et les nuages sont sans collision.
- **Décalage** : la map est posée à (2000, 0, 0) pour ne pas se superposer à l'Arène en mode Edit.
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
   liste les trous et les surplus groupés, avec la pièce responsable. État au relevé : 3 groupes de 4 rayons (fentes de
   0,03 stud aux angles rentrants, laissées par `EPS`), 0,7 % de rayons en surplus (décor approché par sa boîte).
   Scintillement : `tools/map/zfight_dizzy.py` (mêmes arguments, puis la tolérance), cf. « Scintillement » ci-dessous.
4. Générer : `lune run tools/map/build_dizzy.luau` (sans Studio, plugin Rojo déconnecté de ce serveur) écrit
   `assets/rbx/Maps/Dizzy.rbxm`. Puis `rojo build` et `verify_place.luau` comme pour l'Arène.

Méthode et pièges (pour ne pas les redécouvrir) :
- **La collision du monde n'est pas faite de blocs** : c'est un maillage fermé (le toit d'un seul tenant), sols et murs
  en surfaces. La v1 le relevait par rayons verticaux tous les 0,5 m : murs fins et bords ratés, d'où ses trous. Seul le
  petit décor est en blocs convexes.
- **Chaque face plane devient une dalle** collée à la face, épaissie vers l'intérieur (moitié de l'épaisseur locale au
  plus, pour que les deux faces d'un mur fin ne se chevauchent pas), retirée de `EPS` (0,03 stud) sous la face pour ne
  pas scintiller avec la tranche d'une dalle voisine. Rectangles quand le plan s'y prête, sinon deux `WedgePart` par
  triangle. Couverture sans trou par construction.
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
- Environ 18 600 pièces ancrées, dont ~12 000 coins, surtout aux plafonds.

### Scintillement (non résolu)

Dizzy scintille à distance : bandes sombres dentelées sur les façades, rayures sur les rebords (signalé le 05/11/2026).
**Cause** : à chaque arête saillante (bord d'un renfoncement, d'un rebord, d'une fenêtre), la tranche d'une dalle de sol
ou de plafond tombe dans le plan de la face du mur voisin, `EPS` (0,03 stud) devant elle et dans une autre couleur.
Prouvé par rayons depuis la caméra (mur à x = 2064,99, tranche de plafond à 2065,02, vus à 180 studs) et par le test
décisif : recolorer sols et plafonds comme les murs dans Studio (temporaire) fait disparaître les bandes.

Mesurer : `tools/map/zfight_dizzy.py` (faces de même sens dans le même plan à TOL près, qui se recouvrent et sont vues
depuis l'air). État actuel : 14 000 studs² à 0,005 (faces confondues), 245 000 studs² à 0,1 (surtout tranches à
`EPS` devant une face). Diagnostiquer en jeu : `ViewportPointToRay` + `Raycast` depuis la vue fautive (MCP Studio,
mode Edit) donne la pièce touchée et sa position au centième.

| Essai | Résultat | Statut |
|---|---|---|
| `EPS` 0,03 → 0,15 (retrait adaptatif sur les murs fins) | Rien de visible ; élargit les fentes des angles rentrants | Rejeté |
| `SmoothPlastic` sur murs et plafonds, ombres coupées sur les dalles fines et les plafonds | Rien de visible | Rejeté |
| Ombres globales coupées (test) | Rien : ce n'est pas l'éclairage, malgré le soleil rasant (`ClockTime` 17,9) | Rejeté |
| Faces confondues fusionnées par plan (`plane_groups`) | Rien de visible, mais vraie correction (doublons, 9 → 3 groupes de trous) | Gardé |
| Une couleur pour sols, murs et plafonds (test Studio) | Plus de bandes, mais map vide visuellement | Rejeté (DA) |
| Bords de dalle décalés selon l'arête (`EDGE_ADJUST`) : saillante, la dalle recule de 0,18 pour cacher sa tranche ; rentrante, elle avance de 0,08 | Plus de scintillement, mais la moitié des détails des façades disparaît et des fentes claires s'ouvrent aux angles rentrants | Code gardé, désactivé |

Pistes restantes : retirer ou replacer les éléments qui gênent (retouches `remove` / `add` de `dizzy_patches.luau`,
après repérage avec `zfight_dizzy.py`) ; reprendre `EDGE_ADJUST` en ne décalant que la dalle dont la couleur diffère du
mur, sans toucher aux angles rentrants ; séparer rendu et collision (rendu en mesh, cf. virages de l'Arène), écarté tant
que le mesh serait tiré de la géométrie de Valve.

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
   - `restyle` : rhabille les pièces d'une zone (`look`).
3. Plugin Rojo déconnecté, `lune run tools/map/build_dizzy.luau` (affiche le nombre de pièces touchées par chaque
   retouche), puis reconnecter et accepter le patch.
Une zone qui ne contient aucune pièce arrête la génération (coordonnées fausses, ou pièce disparue après un nouveau
relevé : revoir la retouche). Une pièce issue d'une retouche porte l'attribut `Patch` (son `why`), visible dans Studio.
Lecture de la position hors moteur : `CFrame.Position` (dans Lune, `Position` n'existe pas sur une pièce posée par
`CFrame`).

## L'Arène

Même DA que la ville ensablée, plan refait pour le surf : la ville ne permettait pas d'accumuler de la vitesse
(rampes courtes et isolées, traversée en 3 s). Référence de jeu donnée par l'utilisateur : surf_japan (CS:GO),
rampes longues face à face avec une ligne de tir dégagée entre elles.

- **Plan** : un anneau fermé de dunes surfables à 55° (deux lignes droites de 340 studs, deux virages de 120 studs de
  rayon, environ 1 300 studs de rampe sans interruption), adossé à des gratte-ciel le long des lignes droites, autour
  d'une place (couverts : bus, kiosque, murets, petites dunes marchables). Passerelle des snipers à 78 studs entre les
  deux tours centrales.
- **Île au-dessus du vide** : les virages sont ouverts sur le vide ; sortir de l'île, c'est mourir (choix de
  l'utilisateur, comme sur surf_japan). Sous `Maps.Map.KillHeight`, le client signale sa chute (remote `FellOut`) et
  le serveur le tue (`src/server/KillZone.luau`).
- **Boosts** (`Maps.Map.Boosts`, règles dans `src/shared/MapRules.luau`, détection client dans
  `BoostSystem.luau`) : deux geysers sur la place (relance vers l'anneau, recharge 3 s), un lanceur vers la
  passerelle, un portique au milieu de chaque ligne droite (+40 studs/s dans le sens du mouvement, plafonné à
  `MAX_SPEED_SERVER`). Geysers et lanceurs imposent une vitesse balistique calculée par le générateur pour atteindre
  un point précis : on les règle en déplaçant la cible, pas la vitesse.
- **Pistes gardées de côté** : « La Digue » (bande au-dessus du vide, rampes jumelles, village aux toits surfables,
  la plus proche de surf_japan) et « L'Échangeur » (viaducs ensevelis, chaque viaduc est une rampe, saut au
  croisement). Maquettes 3D des trois plans : `docs/maps/plans-arene-digue-echangeur.html` (à ouvrir dans un
  navigateur).
- **Matières et décor** (#71, choix libres laissés à Claude) : deux MaterialVariant de `MaterialService`,
  `ArenaFacade` (tours, silhouettes) et `ArenaCliff` (falaise). Le sable (rampes, sol, toits, Terrain) garde la
  matière Sand de Roblox : une texture générée (`ArenaSand`, sable ondulé) a été jugée horrible par l'utilisateur.
  Tours : toit ensablé, enseignes penchées au néon à moitié éteint. Sous l'île : falaise qui s'effile en blocs de
  roche, mer de brume en nappes translucides d'où sortent des silhouettes à étages en retrait. Ce décor tire ses
  valeurs de `deco`, un second `Random` : le plan jouable (hauteurs des tours, place) reste identique.
- **Dunes en Terrain** (demande de l'utilisateur : un sol plat ne fait pas « sable », et des bosses en sphères font
  trop « Roblox ») : le sol de l'île est un champ de dunes en Terrain Roblox (matière Sand, teinte du sol). Relief (`src/shared/DuneField.luau`, testé) : grandes dunes transverses au vent, dos en
  pente douce, face d'éboulement raide, petites dunes obliques et rides par-dessus ; environ 21 % du sol en dunes
  (jusqu'à ~12 studs), le reste en couloirs presque plats (premier prototype jugé trop chargé). Plat autour des points
  d'apparition au sol et des dalles des geysers et lanceurs ; les dunes s'effacent avant le pied des rampes.
  - Le Terrain n'est pas dans `Map.rbxm` : `src/server/MapTerrain.luau` le reconstruit au démarrage du serveur depuis
    les attributs `DunesPlan` (repère du plan) et `DunesRing` (anneau) posés par le générateur, qui l'appelle aussi
    pour l'aperçu en mode Edit (code du jeu synchronisé dans Studio). Sans ces attributs (ancienne ville), rien.
  - Marchable partout : le test vérifie une pente max sous le seuil de surf, avec 3° de marge (mesuré : 40,6° pour
    45,6°). Augmenter la hauteur ou resserrer les dunes raidit les faces : relancer le test.
  - Le sable ne doit jamais dépasser de la surface d'une rampe : une congère au pied des rampes (prototype) y mordait
    et aurait cassé le surf.
  - Piste rejetée : bosses en calottes de sphère (parts), trop simplistes ; un mesh Blender aurait une collision
    approchée (décomposition convexe), alors que celle du Terrain suit exactement la surface visible.

### Matières (MaterialVariant)

- Générées dans Studio par le MCP (`generate_material`, une description par matière). Chaque génération donne
  4 variantes rangées dans un dossier de `MaterialService` : les comparer sur un mur d'échantillons, garder la
  meilleure à la racine de `MaterialService` sous son nom définitif, supprimer le reste. Les textures sont hébergées par
  Roblox, rien à publier.
- Versionnées dans `assets/rbx/Materials/<Nom>.rbxm` (Rojo : `MaterialService`), exportées avec la map par
  `studio_export.luau`. Une MaterialVariant ajoutée à la main sans être exportée est supprimée à la connexion Rojo.
- Piège : `rojo serve` ignore un dossier `$path` créé après son démarrage (ici `assets/rbx/Materials`, créé par le
  premier export). Il sert alors un `MaterialService` vide et, à chaque connexion, retire les matières de Studio sans
  les recréer. Relancer le serveur (`csgo-worktree.ps1 <branche> -Stop`, puis sans option).
- La couleur de la pièce ne teinte presque pas une MaterialVariant : la teinte vient de la texture (et de la lumière
  du crépuscule). Pour changer la couleur, régénérer la matière.
- `verify_place.luau` échoue si une pièce de la map pointe vers une MaterialVariant absente (sinon elle retombe en
  silence sur sa matière de base), ou si une matière n'a pas de texture.

## La ville ensablée (ancienne map)

Une ville moderne à moitié engloutie par le sable, au crépuscule, dans la direction « Ligne de mire » du menu
(`docs/ui.md`) : soleil bas, ciel bleu nuit, matière brun chaud, lignes ambrées, silhouettes sombres.

- **Échelle** : zone jouable d'environ 450 × 450 studs pour 6 à 10 joueurs (à pied on la traverse en ~15 s, en surf en
  3-4 s). Une première version à ~1 000 × 1 100 studs a été jugée trop grande : à 8 on ne se croise pas.
- **Plan non linéaire** : place centrale, avenue vers le soleil, rues en biais, ruelles qui bouclent entre elles. Le
  premier prototype, une avenue droite bordée de blocs alignés, a été rejeté : trop répétitif.
- **Rampes en raccourcis, pas en passage obligé** : on se bat à pied dans les rues et sur les toits ; le surf sert à
  traverser vite. Rampes : couloir de dunes (rue ouest, talus à 55° des deux côtés), tours tombées, arête de sable
  sur l'avenue (marchable côté place, surfable côté soleil), dunes contre les façades (marchables pour monter aux
  toits, ou surfables).
- **Limites** : ceinture de façades hautes le long d'un contour irrégulier, plus basses côté soleil pour garder
  l'horizon ; murs invisibles de 420 studs sur le contour ; silhouettes lointaines sans collision pour l'échelle.
- **Spawn** : le joueur sort du soleil (lanceurs `SunLaunch`), dans la continuité de la plongée vers le soleil du menu,
  avec 2,5 s d'invulnérabilité (`GameConfig.SPAWN_PROTECTION`).

Ancienne map (modèle du market, sans DA) : archivée hors du dépôt dans `worktrees/.archive/AncienneMap_market.rbxm`
(modèle tiers, dépôt public : ne pas la versionner).

## Générateur et export

La map est construite par `tools/map/build_arena.luau` (Arène) à partir des données en tête de fichier (anneau,
boosts, sorties du soleil, spawns) ; `tools/map/build_city.luau` reconstruit l'ancienne ville. Elle est exportée
en `assets/rbx/Maps/Map.rbxm`, synchronisé par Rojo vers
`Workspace.Maps.Map`. Même graine = même ville.

Itérer sur la map (depuis la racine du worktree, Studio en mode Edit, **plugin Rojo déconnecté**) :

1. `lune run tools/map/serve.luau` (sert les scripts sur le port 34992).
2. Modifier les données de `build_arena.luau`, puis dans Studio (MCP `execute_luau`, contexte Edit) :
   `return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/build_arena.luau"))()`.
   Le générateur remplace la map générée précédente ; il refuse d'écraser une map qui ne vient pas de lui.
3. Regarder le résultat (`screen_capture`, voir les pièges ci-dessous), recommencer.
4. Exporter : `lune run tools/rbxm/receive.luau`, puis dans Studio
   `return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/studio_export.luau"))()`
   (exporte aussi les armes et les matières, cf. `docs/assets.md` ; vérifier `git status`).
5. `rojo build default.project.json -o CSGO.rbxlx && lune run tools/rbxm/verify_place.luau` : vérifie que la map
   a des points d'apparition, que chaque lanceur a un attribut `Speed` et que chaque boost est configuré.
6. Reconnecter le plugin Rojo et accepter le patch.

Rojo gère `Workspace.Maps` : un objet posé à la main dans la map est supprimé à la connexion s'il n'est pas exporté.
Mêmes règles que les armes : ne jamais réécrire `Map.rbxm` pendant que Studio est connecté à ce serveur Rojo.

## Ce que le code attend de la map

- `Maps.Map.SunLaunch` : parties invisibles ; position = point d'apparition, `LookVector` = direction du lancement,
  attribut `Speed` (studs/s). `SpawnManager` en tire une au hasard, pose `LaunchOrigin` et `LaunchVelocity` sur le
  personnage ; `MovementController` les applique une fois (position, vitesse en l'air, caméra tournée vers la ville,
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
  `ClockTime` 17.9 et latitude 0 placent le soleil dans la direction `SUN_DIR` du générateur. Changer l'heure oblige
  à recalculer `SUN_DIR` (`Lighting:GetSunDirection()`, Y retiré) et à régénérer, sinon on ne sort plus du soleil.

## Règles de construction

- **Pentes** : surfable entre 46° et 84° (`MovementConfig.SURF_NORMAL_Y`, `SURF_NORMAL_MIN`), marchable en dessous,
  mur au-delà. Viser 50-62° pour le surf, 30-40° pour une pente qu'on monte à pied.
- **Une rampe de surf est longue à l'horizontale, avec la pente en travers.** On surfe le long de la rampe, pas dans
  le sens de la pente. Piste rejetée : une tour penchée sur sa longueur (sommet en l'air) n'offre que sa largeur
  (~30 studs) dans le sens du surf. Une tour tombée se pose à l'horizontale, roulée sur son axe : une face à ~55°
  (surf, arêtes ambrées), la face voisine à ~35° (on y monte à pied).
- **Talus** : `WedgePart` dont le côté haut est le +Z local (vérifié par raycast) ; le générateur l'oriente vers la
  façade.
- **Murs invisibles** : `CanQuery` doit rester vrai. Le mouvement est fait maison et détecte les collisions par
  raycast : un mur ignoré par les requêtes ne bloque pas le joueur.
- **Sol** : la `Baseplate` a été retirée du projet. Son dessus à y = 0 coïncidait avec le sol de la ville et
  scintillait.

## Pièges

- **Captures en mode Edit** (`screen_capture`) : un viewport entièrement blanc, même sur une scène connue, vient de la
  fenêtre Studio réduite ou en arrière-plan. La mettre au premier plan.
- **Brume** : l'Atmosphere du crépuscule (densité 0.33) noie les vues aériennes ; pour juger un plan d'en haut, la
  vue au sol et à hauteur de toit est plus parlante qu'une vue de dessus.
- **Caméras de capture** : une caméra posée au hasard dans la ville tombe souvent dans un bloc. Calculer les positions
  dans le repère du plan (même `base` que le générateur).

- **Virages en segments** : avec le ClipVelocity Source, chaque jointure entre deux WedgePart retire ≈ 1 - cos de
  l'angle entre segments, soit une perte en 1/N ; mesuré sur l'Arène à 36 segments par demi-tour : -14 % d'énergie
  sur un virage (#71). Correction possible plus tard, dans le mouvement : entre deux facettes de surf presque
  parallèles, réorienter la vitesse au lieu de la clipper (essai : -0,2 %). Mesurer un virage :
  `tools/map/measure_turn.luau` (servi par `serve.luau`, Rojo connecté au worktree) ; sans perte, l'énergie
  (½v² + g·h) reste constante, et la vitesse seule baisse normalement quand on monte la dune.
- **Virages en mesh** : le visuel d'un virage est un mesh Blender lisse (`tools/map/build_turn_mesh.py`, 256 segments,
  normales lissées le long de l'arc, arêtes vives ailleurs, UV en studs), sans collision ni raycast ; la collision
  reste faite de `ARC_SEGMENTS` (36) WedgePart invisibles (`Ramps.TurnCollision`). Les lignes droites s'arrêtent pile
  au début du mesh : un recouvrement coplanaire scintille.
  - Refaire le mesh : `blender -b --factory-startup --python tools/map/build_turn_mesh.py -- assets/map/ArenaTurn.blend`,
    puis `tools/export_mesh_fbx.py` (cf. `docs/assets.md`), `bash tools/publish_asset.sh assets/map/ArenaTurn.fbx
    Model SurfFFA_ArenaTurn`, et lire les ids des MeshParts (`InsertService:LoadAsset` en mode Edit) pour
    `TURN_BANK_MESH` / `TURN_RIDGE_MESH`. Le générateur crée les MeshParts par `AssetService:CreateMeshPartAsync`
    (un plugin ne peut pas écrire `MeshId`). Republier un mesh identique redonne les mêmes ids.
  - Le mesh est centré sur sa boîte englobante : le générateur le place depuis le centre du virage avec
    `Size.Z / 2` (arc côté +Z), et tourne le virage -Z d'un demi-tour.
  - **Pistes rejetées pour réduire la perte sans toucher au mouvement** (mesurées avec `measure_turn.luau`) : plus de
    segments (72 : instable, de -5 % à l'arrêt ; 144 : -90 %), tranches de collision en mesh aux bouts coupés selon le
    rayon (CollisionFidelity Hull, de 36 à 144 : le surfeur s'arrête dans tous les cas ; l'enveloppe flotte ~0,6 stud
    au-dessus de la vraie surface). Cause probable : collé à la pente, le balayage du personnage démarre souvent dans
    une pièce (que Roblox ignore alors) et touche la face de jointure de la voisine, prise pour un mur ; plus les
    pièces sont fines, plus ça arrive. Seule la correction du mouvement supprime la perte.
- **Décor sans collision** : toute pièce décorative (arêtes néon, bandes, colonnes de geyser) doit avoir `CanQuery`
  faux, sinon les raycasts du mouvement la prennent pour un mur ou une rampe.

## Reste à faire

- Arène (#71) : vrais modèles Blender pour la place (bus, kiosque, murets) et la passerelle des snipers. Valider en jeu la visée des
  geysers et des sorties du soleil.
- Plus tard : supprimer la perte de vitesse restante dans les virages (correction du mouvement, voir les pièges).
- Son et effet au déclenchement d'un boost.

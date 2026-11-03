# Maps

Référence pour modifier la map ou en construire une autre. Map actuelle : l'« Arène ». Première map originale,
remplacée : la « ville ensablée » (#69), gardée comme seconde map possible.

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
   (exporte aussi les armes, cf. `docs/assets.md` ; vérifier `git status`).
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

- **Virages en segments** : un virage fait de WedgePart en corde perd un peu de vitesse à chaque jointure (≈ 1 -
  cos de l'angle entre segments). 36 segments par demi-tour limitent la perte ; un mesh courbe (Blender) la supprime.
- **Décor sans collision** : toute pièce décorative (arêtes néon, bandes, colonnes de geyser) doit avoir `CanQuery`
  faux, sinon les raycasts du mouvement la prennent pour un mur ou une rampe.

## Reste à faire

- Arène : valider en jeu (vitesse sur l'anneau, perte dans les virages, visée des geysers et sorties du soleil),
  puis modéliser les virages en courbes dans Blender.
- Son et effet au déclenchement d'un boost.

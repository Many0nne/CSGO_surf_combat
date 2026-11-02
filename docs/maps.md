# Maps

Référence pour modifier la map ou en construire une autre. Première map originale : la « ville ensablée » (#69).

## La ville ensablée

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

La map est construite par `tools/map/build_city.luau` à partir des données en tête de fichier (contour, rues, tours
tombées, talus, lanceurs, spawns), puis exportée en `assets/rbx/Maps/Map.rbxm`, synchronisé par Rojo vers
`Workspace.Maps.Map`. Même graine = même ville.

Itérer sur la map (depuis la racine du worktree, Studio en mode Edit, **plugin Rojo déconnecté**) :

1. `lune run tools/map/serve.luau` (sert les scripts sur le port 34992).
2. Modifier les données de `build_city.luau`, puis dans Studio (MCP `execute_luau`, contexte Edit) :
   `return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/build_city.luau"))()`.
   Le générateur remplace la map générée précédente ; il refuse d'écraser une map qui ne vient pas de lui.
3. Regarder le résultat (`screen_capture`, voir les pièges ci-dessous), recommencer.
4. Exporter : `lune run tools/rbxm/receive.luau`, puis dans Studio
   `return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/studio_export.luau"))()`
   (exporte aussi les armes, cf. `docs/assets.md` ; vérifier `git status`).
5. `rojo build default.project.json -o CSGO.rbxlx && lune run tools/rbxm/verify_place.luau` : vérifie que la map
   a des points d'apparition et que chaque lanceur a un attribut `Speed`.
6. Reconnecter le plugin Rojo et accepter le patch.

Rojo gère `Workspace.Maps` : un objet posé à la main dans la map est supprimé à la connexion s'il n'est pas exporté.
Mêmes règles que les armes : ne jamais réécrire `Map.rbxm` pendant que Studio est connecté à ce serveur Rojo.

## Ce que le code attend de la map

- `Maps.Map.SunLaunch` : parties invisibles ; position = point d'apparition, `LookVector` = direction du lancement,
  attribut `Speed` (studs/s). `SpawnManager` en tire une au hasard, pose `LaunchOrigin` et `LaunchVelocity` sur le
  personnage ; `MovementController` les applique une fois (position, vitesse en l'air, caméra tournée vers la ville,
  `SpawnLaunch.cameraAngles`).
- `Maps.Map.GroundSpawns` : repli quand la map n'a pas de lanceur.
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

## Reste à faire

- Valider le plan gris en jeu (surf, lignes de tir, lancement), puis les matières et le décor définitifs.
- Modéliser les courbes (dune courbe, rampes en virage) dans Blender une fois le plan validé.

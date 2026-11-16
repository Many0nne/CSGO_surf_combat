# Mesurer un mouvement par le MCP Studio (#293)

Méthode qui a marché pour mesurer le saut depuis une échelle, réutilisable pour tout effet de mouvement localisé.

- **Placer le joueur :** en contexte `Client`, `ReplicatedStorage.PerfRouteTeleport:FireServer(Vector3)` (remote de
  `PerfReplay`, autorisé dans Studio) le replace par une correction serveur. Le premier envoi juste après l'apparition
  peut être perdu : relire la position et renvoyer si besoin.
- **Couper les bots avant :** `workspace:SetAttribute("DebugBots", 0)` une fois le round lancé (`DebugPlaytest`).
  Sinon un bot tue le joueur pendant la mesure et la réapparition fausse les positions.
- **Lire la position en appels séparés :** position A (`execute_luau`), puis l'appui (`user_keyboard_input`, avec un
  `wait` de 300 ms), puis position B (`execute_luau`). Une boucle `task.spawn` + `task.wait` lancée par un
  `execute_luau`, en parallèle de `user_keyboard_input`, a renvoyé des positions figées alors que le joueur bougeait :
  ne pas s'y fier.
- **Mesure « avant » :** remettre l'ancienne ligne dans `src/` le temps de la mesure (Rojo la synchronise en Edit,
  vérifier `Source` avant de lancer Play), puis rétablir le correctif et contrôler que `git diff` est vide.

Mesures de #293 (échelle de Dizzy x = 1902, normale +Z, 0,3 s après Espace) :

| Position | Avant | Après |
|---|---|---|
| Pied (y 66) | dz 7,76, dy −0,36 | dz 7,76, dy −0,36 |
| Mi-hauteur (y 86) | dz 0,00, dy 0,00 | dz 20,98, dy −19,93 |
| Haut (y 104) | non mesuré | dz 28,48, dy −37,77 |
| Mi-hauteur, Espace puis avancer 0,5 s | — | dz 0,26, dy −18,24 (retombe le long du mur, ne se raccroche pas) |

# Mesurer une cadence d'arme au clic tenu par le MCP (#473)

Méthode utilisée pour mesurer les actions répétées au maintien (tir, attaque secondaire, zoom), avant et après.

- **Clic tenu :** `user_mouse_input` (contexte `Client`) avec `mouseButtonDown`, `wait` (jusqu'à 10 s), `mouseButtonUp`.
  L'entrée atteint bien le jeu (`InputBegan` avec `gameProcessed = false`), sur le chemin réel (`Tool.Activated`,
  `InputModule`). Un premier `wait` de 7 s dans la même liste laisse finir le run `DebugPlaytest` lancé juste avant.
- **Relever les actions :** dans un `execute_luau` client, brancher `AnimationPlayed` de l'`Animator` du viewmodel
  (`workspace.CurrentCamera`, plus `DescendantAdded` pour un viewmodel recréé), et le FOV de la caméra (paliers 90, 40
  et 10) dans `RenderStepped`. Écrire dans un tampon `_G` et le relire par un appel suivant : la console est noyée par
  les journaux des bots.
- **Piège :** le premier run `DebugPlaytest` d'une session de jeu est suivi d'une réapparition (`MEM CLIENT #3 spawn`)
  qui laisse le joueur sans arme en main. Relancer `DebugPlaytest` avant de mesurer, et vérifier l'outil tenu.
- **Piège :** rejouer la même piste pendant qu'elle se termine (estoc répété) déclenche deux `AnimationPlayed` à la même
  milliseconde. Compter les coups réels avec les PV de `DebugDummy`, ou avec les lignes serveur
  `[DebugPlaytest] serveur : cible touchée`.
- **Avant / après sur le même Studio :** commit WIP sur la branche, puis `git show main:<fichier> > <fichier>` pour les
  fichiers concernés (Rojo synchronise), mesurer, puis `git show HEAD:<fichier> > <fichier>`. Relancer le playtest
  après chaque bascule : les scripts ne sont rechargés qu'au démarrage.

Résultats de #473 (M9 contre le mannequin, donc cadences d'un coup qui touche) :

| Action tenue | Avant | Après |
|---|---|---|
| AWP, clic gauche 5,3 s | 1 tir | 4 tirs, espacés de 1,464 à 1,468 s (`FireDelay` 1,455 s) |
| AWP, clic droit 2,3 s | 1 zoom | 8 zooms en boucle, un toutes les ~0,31 s (`ScopeRepeatDelay` 0,3 s) |
| M9, clic gauche 4,3 s | 1 coup | 9 coups, espacés de 0,50 à 0,52 s (`HitFireDelay` 0,5 s) |
| M9, clic droit 4,3 s | 1 estoc | 4 estocs, espacés de 1,10 à 1,12 s (`HitFireDelay` 1,1 s) |

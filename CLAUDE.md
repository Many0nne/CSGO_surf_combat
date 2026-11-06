# CSGO

## Overview

Projet Rojo qui synchronise une expérience Roblox depuis l'arborescence `src/`.

## Où trouver quoi

Lire le document du domaine avant de travailler dessus, et seulement celui-là.

| Sujet | Document |
|---|---|
| Où se trouve un comportement, rôle de chaque fichier | `docs/architecture.md` |
| Modifier ou ajouter une arme (`.rbxm`), publier un asset ou un mesh | `docs/assets.md` |
| Créer ou modifier un écran, direction artistique | `docs/ui.md` |
| Créer ou modifier une animation d'arme | `docs/animations.md` |
| Modifier la map (générateur, export, règles des rampes) | `docs/maps.md` |
| Saccades, performance, overlay F3, fuites mémoire, sonde `FrameProbe` | `docs/performance.md` |
| Retours d'expérience datés (historique, le document du domaine prime) | `docs/notes/` |

## Capitaliser

Quand une tâche révèle un piège, une règle ou une piste rejetée qui resservira, l'ajouter dans la même PR au document du domaine (créer `docs/<domaine>.md` si le sujet revient et n'a pas de document). N'ajouter à ce fichier qu'une règle utile à presque toutes les tâches. Si le code contredit une doc, corriger la doc.

## Workflow d'une tâche (feature, bug…)

1. Créer le worktree et démarrer son serveur Rojo : `.\scripts\csgo-worktree.ps1 <feature|fix>/<n>-<slug>` (le thread T3
   courant est inscrit comme propriétaire pour le nettoyage). Travailler uniquement dans ce worktree.
2. Implémenter, puis `bash tools/check.sh` dans le worktree. Vérifier en jeu via le MCP Studio si le changement le demande
   (Studio connecté au port du worktree, voir ci-dessous).
3. Besoin d'un avis de l'utilisateur (gameplay, rendu, UI) : lui donner le port Rojo du worktree (`34872+N`), la procédure
   de connexion Studio ci-dessous, et le scénario à suivre (étapes, ce qu'il faut observer). Attendre son retour.
4. Fonctionnement vérifié (et validé par l'utilisateur si l'étape 3 s'appliquait) : commit, push, `gh pr create --base main`
   avec `Closes #<n>` dans la description si une issue est liée, puis fermer le thread (settle via `t3_thread_organize`).
5. Pas de merge sans ordre explicite. Le nettoyage automatique arrête Rojo une fois le thread fermé, et supprime le worktree
   et la branche locale une fois la PR mergée (à la main : `.\scripts\csgo-worktree.ps1 <branche> -Remove`).

## Worktrees (travail en parallèle)

Une branche = un worktree `worktrees/csgo-<slug>/` (slug = branche avec `/` → `-`) = un `rojo serve` sur son propre port.
Script idempotent, à relancer au début de chaque tâche (PowerShell, depuis la racine du checkout principal) :

```powershell
.\scripts\csgo-worktree.ps1 feature/x             # crée/réutilise, lance rojo serve, vérifie [OK (200)]
.\scripts\csgo-worktree.ps1 fix/y -Base feature/x # nouvelle branche depuis une autre base (défaut : main)
.\scripts\csgo-worktree.ps1 feature/x -NoUp       # sans démarrer Rojo
.\scripts\csgo-worktree.ps1 feature/x -Stop       # arrête Rojo
.\scripts\csgo-worktree.ps1 feature/x -Remove     # arrête Rojo, supprime le worktree (branche gardée)
```

- Ports par slot N : checkout principal = slot 0 = `34872` (`rojo serve` lancé à la main), worktrees `34872+N` (34873, 34874…).
- Port, pid et journal du serveur d'un worktree : `worktrees/.run/<slug>.port|.pid|.log` (hors du worktree, rien de versionné).
- Connecter Studio à un worktree (le plugin Rojo ne se connecte qu'en mode **Edit** ; en Play il renvoie
  `Http requests can only be executed by game server`) :
  1. Studio en mode Edit (arrêter le playtest s'il tourne), Disconnect dans le plugin Rojo s'il est connecté ailleurs.
  2. Plugin Rojo : saisir le port du worktree (affiché par le script), Connect.
  3. Pour revenir au checkout principal : Disconnect, port `34872`, Connect.
- Une fenêtre Studio ne suit qu'un serveur Rojo à la fois : deux tâches qui doivent tester en jeu en même temps ont besoin
  de deux fenêtres Studio (le MCP cible alors l'instance choisie, voir `list_roblox_studios`), sinon elles se relaient.
- Lancer `bash tools/check.sh`, `rojo build` et `lune run …` depuis le worktree concerné.
- Nettoyage auto (registre `worktrees/.owners.json`) : `scripts/csgo-worktree-cleanup.ps1` arrête Rojo quand les threads T3
  du worktree ne sont plus actifs (settled, archivés), et supprime le worktree quand la PR de la branche est mergée
  (ou fermée sans merge) et que tout est poussé ; la branche locale est aussi supprimée si la PR est mergée. Fermer ou
  archiver un thread ne supprime jamais rien à lui seul. Tâche planifiée (toutes les 10 min, à réinstaller sur un nouveau
  poste) : `scripts/install-cleanup-task.ps1`. À chaque passage, elle avance aussi le checkout principal sur `origin/main`
  (fast-forward, seulement s'il est sur `main` sans modification).

## Rojo Mapping

- `src/shared` -> `ReplicatedStorage/Shared`
- `src/server` -> `ServerScriptService/Server`
- `src/client` -> `StarterPlayerScripts/Client`
- `assets/rbx/ViewModels/<Nom>.rbxm` -> `ReplicatedStorage/ViewModels/<Nom>` (viewmodels FPS, aussi clonés pour l'arme 3P)
- `assets/rbx/Tools/<Nom>.rbxm` -> `StarterPack/<Nom>` (Tools des armes, attribut `ViewmodelName`)
- `assets/rbx/Maps/<Nom>.rbxm` -> `Workspace/Maps/<Nom>` (une map par fichier, générées par `tools/map/build_*.luau`, map jouée : `GameConfig.ACTIVE_MAP`, cf. `docs/maps.md`)
- `assets/rbx/Materials/<Nom>.rbxm` -> `MaterialService/<Nom>` (MaterialVariant des maps, cf. `docs/maps.md`)

## Viewmodels et Tools (.rbxm)

Procédures complètes (export, ajout d'une arme, publication Open Cloud) : `docs/assets.md`. L'essentiel :

- Les viewmodels et les Tools sont des `.rbxm` versionnés (Git LFS) et synchronisés par Rojo. Toute modification faite dans Studio est perdue si elle n'est pas réexportée, et une instance ajoutée à la main y est supprimée à la connexion.
- **Ne jamais réécrire un `.rbxm` pendant que Studio est connecté à ce serveur Rojo** (export, `git checkout`, `git pull`…) : les `Model` perdent leur `PrimaryPart` et une instance créée à la main peut se retrouver en double.
- **Réparation : Disconnect puis Connect, et accepter le patch de rattrapage.** Ne pas sauvegarder la place avant.

## Interface et direction artistique

Avant de créer ou modifier un écran, lire `docs/ui.md` : direction « Ligne de mire », pistes rejetées, construction du menu, pièges
et écrans restant à refaire. L'essentiel : l'interface est faite de la matière du jeu, et une idée 3D se prototype dans le moteur.

## Animations de viewmodel

Avant de créer ou modifier une animation d'arme, lire `docs/animations.md` (méthode, outils, pièges). L'essentiel :

- Partir d'une vidéo de référence fournie par l'utilisateur et ne pas itérer sur des descriptions.
- Faire valider les poses, puis le mouvement avec une vidéo côte à côte (`tools/anim/side_by_side.py`), **avant de publier**,
  même si l'utilisateur demande de finir. Des images fixes justes ne garantissent pas un mouvement juste.
- Rendre dans Studio au FOV du jeu (90°) et juger le cadrage en 16:9, pas dans Blender avec un volume à la place de l'arme.

## Notes

- Garder `default.project.json` synchronisé avec l'arborescence `src/` (mappings Rojo).
- Consigne de lecture : pour les revues de code, analyses ou demandes de modification, ne lire que les fichiers strictement concernés par l'étape ou la demande.
- Évitez d'analyser ou d'indexer l'ensemble du dépôt sauf si la tâche l'exige explicitement. Quand vous consultez des fichiers, précisez lesquels dans votre message ou votre PR.

## Common Commands

```bash
rojo serve                  # checkout principal, port 34872 (worktrees : scripts/csgo-worktree.ps1)
rojo build -o "CSGO.rbxlx"
bash tools/check.sh         # selene + stylua --check + luau-lsp analyze sur src/, puis tests Lune
lune run tests/run.luau     # tests unitaires seuls
bash tools/check.sh --fix   # idem, en appliquant le formatage StyLua
```

## Outillage qualité

- Outils gérés par Rokit (`rokit.toml`) : `rojo`, `stylua`, `selene`, `luau-lsp`, `lune`. Binaires dans `~/.rokit/bin` ; installer avec `rokit install`.
- Configs : `stylua.toml` (tabs, guillemets doubles, 120 colonnes), `selene.toml` (std roblox, règles par défaut), `.luaurc` (mode `nonstrict`).
- Les fichiers de constantes (`CameraConfig`, `GameConfig`, `MovementConfig`) sont exclus de StyLua via `-- stylua: ignore` pour garder l'alignement en colonnes : respecter cet alignement à la main quand on les modifie.
- Après toute modification de code `.luau`, lancer `bash tools/check.sh` et ne pas introduire de nouvel avertissement.
- Tests unitaires (Lune, hors Roblox) dans `tests/specs/*.spec.luau` : chaque spec retourne `function(T, Loader)`. `Loader.new({ Players = mock }):require("src/...")` charge un module de `src/` en simulant `game:GetService` et le `require` d'Instances Rojo ; les services non simulés lèvent une erreur. Seuls les modules sans raycast/`workspace` sont testables (physique pure, `Validator`). Ajouter un test pour toute correction de bug physique.
- Git LFS : les binaires d'assets (`*.blend`, `*.fbx`, `*.obj`, images, sons) sont suivis par LFS via `.gitattributes`. Installer `git lfs` puis `git lfs install` avant de cloner. Un nouveau format binaire doit être ajouté à `.gitattributes` avant son premier commit. Les `.rbxm` de `assets/rbx/` sont aussi en LFS (le checkout de la CI utilise `lfs: true`).
- CI GitHub Actions (`.github/workflows/ci.yml`) : sur chaque PR et push sur `main`, lance `tools/check.sh`, `rojo build`, puis `tools/rbxm/verify_place.luau`. Les définitions de types luau-lsp sont téléchargées pour la version déclarée dans `rokit.toml`.

## Roblox Studio MCP

- Le serveur MCP `Roblox_Studio` (officiel, intégré à Studio) est configuré en scope local. Studio doit être ouvert avec "Enable Studio as MCP server" activé.
- **Ne jamais modifier de scripts via le MCP** (`multi_edit`, `execute_luau` qui écrit dans `Source`, etc.) : la synchro Rojo va uniquement des fichiers vers Studio, toute modification de script faite dans Studio sera écrasée ou perdue. Le code se modifie exclusivement dans `src/`.
- Usages du MCP : inspecter la scène (`search_game_tree`, `inspect_instance`), construire la map et les objets du workspace (rampes de surf, spawns, décor), chercher et insérer des assets, playtester (`start_stop_play`, simulation d'input, `get_console_output`, `screen_capture`) pour vérifier un comportement.
- Les éléments créés dans le workspace via le MCP ne sont pas dans `src/` : penser à sauvegarder la place dans Studio.
- Helper de playtest (Studio uniquement, inactif hors Studio) : vérifie en une commande l'équipement, l'attaque, le son et les dégâts d'une arme. Playtest lancé, en contexte `Server` (`execute_luau`), avec un nom d'outil ou un numéro de slot (ordre alphabétique) :
  ```lua
  game.Players:GetPlayers()[1]:SetAttribute("DebugPlaytest", "AWP")
  ```
  Puis `get_console_output`, lignes préfixées `[DebugPlaytest]` : un `PASS`/`FAIL` par étape (SPAWN, EQUIP, TARGET, AIM, VIEWMODEL, ATTACK, SOUND, DAMAGE, STILL_EQUIPPED) et un `RESULT` final. `VIEWMODEL` échoue si le viewmodel n'est pas devant la caméra ou si son modèle source est abîmé (`PrimaryPart` absent, enfant en double, joint cassé). L'attribut revient à nil en fin de run. La cible `DebugDummy` reste en jeu jusqu'au run suivant.

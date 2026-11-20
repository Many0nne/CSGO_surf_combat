# Plugin Rojo « CSGO autoconnect »

Le plugin Rojo officiel ne se pilote que par son interface : un agent ne peut ni changer de port ni cliquer sur Connect.
Ce dossier contient un patch du plugin officiel qui suit le verrou Studio (`scripts/csgo-worktree.ps1`) tout seul.
Le plugin est installé pour tout le poste, donc chargé dans chaque fenêtre Studio : chaque fenêtre ne suit que la cible
de **sa** place (`game.PlaceId`), ce qui permet à d'autres projets Rojo du poste de s'en servir aussi (#589).

## Fonctionnement

- Un seul serveur de commande pour tous les projets : `control-server.luau` (Lune, `http://localhost:34870`), démarré
  par le premier script qui réserve Studio. Registre, journal (`control.log`) et pid dans le dossier commun
  `%LOCALAPPDATA%\RojoAutoconnect`.
- `-AcquireStudio` écrit le port du worktree dans `worktrees/.run/studio.target` (`{ port, rev }`), inscrit CSGO au
  registre (`projects/csgo.json`, place `91817475928288`) et démarre au besoin le serveur de commande.
- Le plugin interroge `GET /target?placeId=<sa place>` chaque seconde (en mode Edit). Quand `rev` change : Disconnect,
  port cible, Connect, et **patch de connexion accepté sans fenêtre** (comme un Accept manuel : une instance ajoutée à
  la main est supprimée). Il renvoie l'état de sa session (`POST /status?placeId=…`), écrit dans `worktrees/.run/studio.status`.
- Place inconnue du registre, place jamais publiée (`PlaceId` 0), serveur arrêté ou fichier cible absent : le plugin de
  cette fenêtre se comporte comme l'officiel.
- La libération (`-ReleaseStudio`, `-Stop`, `-Remove`) renvoie Studio sur `34872` si le `rojo serve` du checkout principal
  répond, sinon le déconnecte.
- Une connexion manuelle est respectée : le plugin n'agit qu'au changement suivant de la cible.
- Son de notification coupé (`plugin/src/soundPlayer.lua`) : son asset (`rbxassetid://203785492`) n'est plus un audio
  chargeable et sortait 6 erreurs `Asset type does not match requested type` à chaque playtest (#93, #472).
- `-AcquireStudio` attend jusqu'à 15 s la connexion et sinon affiche la procédure manuelle (Studio fermé, en Play,
  ou plugin officiel).
- Diagnostic : `http://localhost:34870/projects` liste les projets inscrits, `/health` la version (`rojo-control 3`).

## Utiliser l'auto-connexion depuis un autre projet

Prérequis : `install.ps1` lancé une fois sur le poste (plugin + copie du serveur dans `%LOCALAPPDATA%\RojoAutoconnect`).

1. **S'inscrire** : écrire `%LOCALAPPDATA%\RojoAutoconnect\projects\<projet>.json` (UTF-8 sans BOM, BOM toléré ; nom de
   fichier propre au projet) :

   ```json
   { "name": "fad", "placeIds": ["88580736516669"], "mainPort": 34900,
     "target": "C:\\…\\FlingADummy\\worktrees\\.run\\studio.target",
     "status": "C:\\…\\FlingADummy\\worktrees\\.run\\studio.status" }
   ```

   - `placeIds` : place(s) du projet, en texte (un nombre JSON est accepté) ; une place n'appartient qu'à un projet.
   - `mainPort` : port du `rojo serve` du checkout principal, où le script renvoie Studio à la libération (informatif
     pour le serveur, qui ne s'en sert pas lui-même).
   - `target`, `status` : chemins absolus des fichiers cible et état du projet, où il veut.
   - Réécrire l'inscription à chaque publication de cible (fichier temporaire puis renommage) : elle suit le checkout.
2. **Publier une cible** (réservation ou libération) : écrire dans `target` `{"port":"34901","rev":"<nouvelle valeur>"}`
   (`port` en texte ; `""` = déconnecter). Le plugin n'agit que si `rev` change (ex. `(Get-Date).Ticks`).
3. **Démarrer le serveur s'il ne répond pas**, sous le mutex système `Local\rojo-autoconnect-control` (commun à tous les
   projets, pris pour toute l'étape, 60 s d'attente au plus) : si `GET http://localhost:34870/health` renvoie
   `rojo-control N` avec N ≥ 3, garder ce serveur (un N plus grand vient d'un projet plus récent). Sinon, arrêter
   le processus `lune` qui écoute sur 34870 (ancienne version) et le pid de `control.pid` seulement si sa ligne de
   commande cite `control-server.luau` (pid recyclé après un redémarrage), puis lancer, depuis un dossier dont le
   `rokit.toml` fournit `lune` et qui n'est pas un worktree :
   `lune run "%LOCALAPPDATA%\RojoAutoconnect\control-server.luau" "%LOCALAPPDATA%\RojoAutoconnect"`
   (en arrière-plan, sortie dans `control.log`, pid dans `control.pid` du dossier commun), et attendre que `/health`
   réponde avant de rendre le mutex. Ne jamais arrêter un serveur de version ≥ 3 : il sert les autres fenêtres.
   CSGO met cette copie commune à jour avec celle de son dépôt avant chaque lancement.
4. **Attendre la connexion** (facultatif) : lire `status` jusqu'à `{"rev":"<rev publiée>","state":"connected","port":"<port>"}`.

## Installation (par poste)

```powershell
.\tools\rojo-plugin\install.ps1             # compile (tag Rojo de rokit.toml + patch), remplace Plugins\Rojo.rbxm, copie le serveur
.\tools\rojo-plugin\install.ps1 -BuildOnly  # compile seulement
.\tools\rojo-plugin\install.ps1 -Uninstall  # remet le plugin officiel (sauvegarde %LOCALAPPDATA%\Roblox\Rojo.official.rbxm)
```

Redémarrer Studio. Au premier appel, Studio peut demander d'autoriser l'accès du plugin à `localhost` : accepter.

## Pièges

- `rojo plugin install` (ou une mise à jour du plugin par Studio) réinstalle l'officiel : relancer `install.ps1`.
- Montée de version de Rojo dans `rokit.toml` : relancer `install.ps1`. Si le patch ne s'applique plus, cloner le nouveau
  tag, reporter les modifications dans `plugin/src/App/init.lua` et `plugin/src/soundPlayer.lua` (repérer `CSGO autoconnect`) et régénérer le patch
  avec `git diff > autoconnect.patch`.
- Changement du protocole du serveur : incrémenter sa version (`VERSION` dans `control-server.luau`, `$controlVersion`
  dans `csgo-worktree.ps1`) en restant compatible avec les versions précédentes : un script garde tout serveur de
  version supérieure ou égale à la sienne, et le premier qui en attend une plus récente le remplace.
- Ancien plugin (avant #589, sans `placeId`) : le serveur v3 lui répond 400, il ne suit plus rien. Relancer `install.ps1`
  et redémarrer Studio.
- Ne pas garder de copie `.rbxm` du plugin dans le dossier `Plugins` : Studio charge tous les `.rbxm` et deux Rojo
  se disputeraient la session.

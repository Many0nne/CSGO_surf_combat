# Plugin Rojo « CSGO autoconnect »

Le plugin Rojo officiel ne se pilote que par son interface : un agent ne peut ni changer de port ni cliquer sur Connect.
Ce dossier contient un patch du plugin officiel qui suit le verrou Studio (`scripts/csgo-worktree.ps1`) tout seul.

## Fonctionnement

- `-AcquireStudio` écrit le port du worktree dans `worktrees/.run/studio.target` (`{ port, rev }`) et démarre au besoin
  `control-server.luau` (Lune, `http://localhost:34870/target`, journal `worktrees/.run/rojo-control.log`).
- Le plugin interroge ce point chaque seconde (en mode Edit). Quand `rev` change : Disconnect, port cible, Connect, et
  **patch de connexion accepté sans fenêtre** (comme un Accept manuel : une instance ajoutée à la main est supprimée).
- La libération (`-ReleaseStudio`, `-Stop`, `-Remove`) renvoie Studio sur `34872` si le `rojo serve` du checkout principal
  répond, sinon le déconnecte.
- Une connexion manuelle est respectée : le plugin n'agit qu'au changement suivant de la cible.
- Serveur de commande arrêté ou fichier cible absent : le plugin se comporte comme l'officiel.
- `-AcquireStudio` attend jusqu'à 15 s la connexion et sinon affiche la procédure manuelle (Studio fermé, en Play,
  ou plugin officiel).

## Installation (par poste)

```powershell
.\tools\rojo-plugin\install.ps1             # compile (tag Rojo de rokit.toml + patch) et remplace Plugins\Rojo.rbxm
.\tools\rojo-plugin\install.ps1 -BuildOnly  # compile seulement
.\tools\rojo-plugin\install.ps1 -Uninstall  # remet le plugin officiel (sauvegarde %LOCALAPPDATA%\Roblox\Rojo.official.rbxm)
```

Redémarrer Studio. Au premier appel, Studio peut demander d'autoriser l'accès du plugin à `localhost` : accepter.

## Pièges

- `rojo plugin install` (ou une mise à jour du plugin par Studio) réinstalle l'officiel : relancer `install.ps1`.
- Montée de version de Rojo dans `rokit.toml` : relancer `install.ps1`. Si le patch ne s'applique plus, cloner le nouveau
  tag, reporter les modifications dans `plugin/src/App/init.lua` (repérer `CSGO autoconnect`) et régénérer le patch
  avec `git diff > autoconnect.patch`.
- Ne pas garder de copie `.rbxm` du plugin dans le dossier `Plugins` : Studio charge tous les `.rbxm` et deux Rojo
  se disputeraient la session.

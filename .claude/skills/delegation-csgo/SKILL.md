---
name: delegation-csgo
description: Regles de delegation propres au depot CSGO (Roblox) - classer chaque tache selon son besoin de Studio, au plus 2 taches Studio en parallele, une seule reservation Studio par tache, en fin de tache. Use when delegating or parallelizing CSGO tasks (/delegate, /triage, lots d'issues, supervision de nuit), or when writing a brief for a CSGO worktree.
---

# Delegation dans le depot CSGO

Complete `/delegate` et `/triage` (skills globaux) pour ce depot : une seule fenetre Studio sert tous les worktrees
(verrou `worktrees/.run/studio.lock`, cf. « Studio et Blender partages » du `CLAUDE.md`). Quand trop de taches en ont
besoin en meme temps, elles attendent le verrou 20 a 30 min, puis renvoient la verification en jeu a l'utilisateur.

## 1. Classer chaque tache avant de la lancer

| Classe | Critere | Exemples |
|---|---|---|
| `sans-studio` | verifiable par `check.sh`, tests Lune, `rojo build`, Blender `-b` | doc, outillage, logique pure testee, generateur de map sans rendu |
| `studio` | verification en jeu (MCP, `DebugPlaytest`, capture) ou avis de l'utilisateur dans Studio | gameplay, armes, UI, animation, bots, rendu |

Doute : `studio`. Indiquer la classe dans le rapport de `/triage` et en tete du brief (`Studio : oui/non`).

## 2. Limiter le parallelisme

- Au plus **2 taches `studio`** en cours en meme temps : une qui verifie dans Studio pendant que l'autre code.
- Les taches `sans-studio` ne comptent pas dans cette limite (seule la limite globale du poste s'applique).
- Une tache `studio` qui attend l'avis de l'utilisateur garde le verrou : elle compte jusqu'a son retour. Lancer la
  suivante seulement quand une des deux a libere Studio (thread ferme, ou `-StudioStatus` montre un autre detenteur).
- Lot plus grand : lancer d'abord les `sans-studio`, puis les `studio` par vagues de 2.

## 3. Ce que le brief d'une tache `studio` impose

Ajouter au brief, section regles :

- Tout faire sans Studio d'abord (code, `bash tools/check.sh` lu en entier, tests Lune, `rojo build`).
- **Une seule reservation Studio, en fin de tache** : `.\scripts\csgo-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20`,
  puis toutes les verifications en jeu d'un coup (playtest, captures, mesures avant/apres), puis `-ReleaseStudio`
  immediatement. Pas de reservation « pour voir » en cours de tache.
- Verification qui echoue : liberer Studio, corriger hors Studio, puis une nouvelle reservation (2 au plus ; au-dela,
  statut `BLOQUE` avec ce qui echoue).
- Avis de l'utilisateur necessaire : regrouper toutes les questions dans une seule demande, faite pendant la reservation
  finale, et garder le verrou jusqu'a la reponse.
- `-WaitStudio` expire (code 2) : ne pas renvoyer la verification a l'utilisateur par defaut ; noter dans le compte rendu
  ce qui reste a verifier en jeu et le scenario exact, statut `BLOQUE`.

## 4. Compte rendu

Le script de worktree autorise la session a ecrire dans `worktrees/.briefs` et `%TEMP%`
(`.claude/settings.local.json` du worktree) : le compte rendu s'ecrit a la fin du brief, sans script de contournement.
Le script doit donc avoir tourne avant le demarrage de la session deleguee. Si l'ecriture est quand meme refusee,
relancer `.\scripts\csgo-worktree.ps1 <branche> -NoUp` depuis la racine (qui reecrit ce fichier) et le signaler dans la
session : ne pas contourner par un script.

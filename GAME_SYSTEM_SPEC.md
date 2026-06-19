# Game System Spec — CSGO (FFA + surf movement)

> Statut : **PRÊT POUR IMPLÉMENTATION** (affiné via `/interview-me`, 2026-06-17).
> Source de vérité pour la couche "jeu". Le moteur de mouvement (surf/bhop/air) existe déjà et n'est pas refait ici.

---

## 1. Concept

- **Le surf est la mécanique de déplacement centrale et unique, pas l'objectif.**
- Le jeu est un **FFA (free-for-all) deathmatch** : faire le plus de kills avant la fin du timer.
- Au join, le joueur **ne spawn pas** : il voit un menu d'accueil **Play / Infos**.
- Le combat réutilise les systèmes d'armes existants (`WeaponSystem`, `MeleeHitDetection`, etc.).

### Décision d'architecture clé : modèle de serveurs Roblox
- **Place ≠ serveur.** Roblox **duplique automatiquement les instances serveur** d'un même place selon l'affluence. On ne crée jamais X places pour la capacité.
- Chaque instance serveur est **isolée en mémoire** → le **leaderboard par instance** est gratuit et automatique.
- **Cette spec vise un SEUL place** (architecture « single-place, menu overlay ») :
  - Join → menu Play/Infos, perso non spawné.
  - Play → spawn dans l'arène du serveur courant.
  - Round / timer / leaderboard gérés par le serveur courant.
- Le **multi-map via `TeleportService`** (1 place par map) est **Phase 2**, documenté §11, et ne casse rien de la Phase 1.

---

## 2. Périmètre

### Dans le périmètre (Phase 1)
- Menu d'accueil (lobby overlay) : **Play**, **Infos**.
- Spawn différé contrôlé par Play.
- Boucle de round FFA à durée fixe (timer serveur).
- Kills/deaths validés serveur.
- Leaderboard d'instance (en mémoire) + HUD (timer + leaderboard Tab).
- Stats persistantes par joueur (DataStore) + réglages.
- Respawn automatique à points de spawn aléatoires.
- Fin de round : annonce gagnant → retour au menu.

### Hors périmètre (explicite)
- **Loadout / sélection d'arme** : on garde le comportement d'armes actuel tel quel. Pas de sélection, pas de pickups.
- Multi-map / TeleportService (→ Phase 2, §11).
- Monnaie / XP / progression / déblocages.
- Killfeed et widget score perso (non retenus au HUD).
- Classement global persistant inter-serveurs (leaderboard = instance seulement).
- Matchmaking, serveurs réservés.

---

## 3. Flux joueur (state machine client)

```
JOIN
  └─> MENU (perso non spawné, caméra fixe/lobby)
        ├─ [Play]  ─> SPAWN ─> IN_ROUND
        └─ [Infos] ─> INFOS (overlay) ─> retour MENU

IN_ROUND
   ├─ mort ─> RESPAWN auto (délai court) ─> IN_ROUND
   └─ fin du timer ─> RESULT (annonce gagnant) ─> MENU
```

États : `MENU`, `INFOS`, `SPAWNING`, `IN_ROUND`, `DEAD`, `RESULT`.

### Spawn différé
- À l'entrée, le personnage **n'est pas spawné** : `Players.CharacterAutoLoads = false` côté serveur.
- Play envoie une requête serveur `RequestSpawn`. Le serveur valide (joueur pas déjà vivant, round joignable) puis `LoadCharacter()` à un spawn aléatoire.
- Caméra de lobby pendant `MENU` (caméra fixe sur la map ou point dédié) ; `FPSCamera` reprend au spawn.

---

## 4. Boucle de round

- **Durée : 5 minutes** (constante config, ajustable).
- **Démarrage : dès 1 joueur** a cliqué Play. Pas d'attente de joueurs.
- **Timer global continu côté serveur** : autorité serveur unique, répliqué au client pour affichage. Le client n'est jamais source de vérité du temps.
- **Join mid-round** : spawn **immédiat** dans le round en cours, 0 kill, joue le temps restant.
- **Fin de round** :
  1. Calcul du gagnant = plus de kills de l'instance (égalité → départage par deaths, puis ordre d'obtention).
  2. **Annonce du gagnant** (bannière, quelques secondes).
  3. **Tous les joueurs renvoyés au menu** Play/Infos avec le résultat. Reset des scores d'instance.
  4. Il faut **recliquer Play** pour le round suivant.
- Un nouveau round démarre selon la même règle (1er Play).

---

## 5. Combat & autorité serveur (anti-triche)

- **Modèle : serveur valide.** Le client signale tir/hit ; le **serveur valide avant d'appliquer dégâts/kill**.
- Étendre `Validator.luau` avec, au minimum :
  - Plausibilité de **position** du tireur et de la cible (cohérence avec dernière position connue + vitesse max).
  - **Ligne de vue** (raycast serveur tireur→cible, pas d'obstacle).
  - **Distance** plausible selon l'arme.
  - **Cadence de tir** (rate limit par arme, anti-rapidfire).
- Le serveur tient l'**autorité sur HP, morts et attribution du kill**.
- Le mouvement reste **client-authoritative** (surf existant) ; la validation combat s'appuie sur les positions répliquées + bornes de vitesse connues (`MovementConfig`), pas sur une re-simulation complète.
- Réticule/feedback de hit côté client = cosmétique, confirmé par le serveur.

> Note : modèle « raisonnable Roblox », pas anti-triche parfait. Suffisant pour le périmètre actuel.

---

## 6. Respawn

- **Respawn automatique** après un court délai à la mort (constante, ex. 2–3 s).
- **Points de spawn aléatoires** sur la map (set de `SpawnLocation` / points dédiés).
- Anti-spawnkill : **non retenu** en Phase 1 (peut être ajouté : invuln. brève + choix de spawn éloigné). Flag §12.

---

## 7. Leaderboard, stats & HUD

### Leaderboard d'instance (en mémoire)
- Par serveur : liste des joueurs présents avec **kills / deaths (/ K/D)** du round courant.
- Réinitialisé à chaque nouveau round.
- Affiché via **maintien de Tab** (overlay).

### HUD en jeu (retenu)
- **Timer du round** (haut de l'écran), piloté par le serveur.
- **Leaderboard (Tab)**.
- *(Non retenus : killfeed, widget score perso/killstreak.)*
- Cohabite avec le `Speedometer` existant.

### Stats persistantes (DataStore) — par joueur, cumulées sur la vie du compte
- **Kills / Deaths / K/D total.**
- **Parties jouées / victoires** (victoire = meilleur score à la fin d'un round).
- **Réglages joueur** (sensibilité, options) — voir §8 (unification avec `SettingsStore` à trancher).

---

## 8. Persistance (DataStore)

- **Stratégie de sauvegarde : à la déconnexion (`PlayerRemoving`) + auto-save périodique** (toutes les X min, filet anti-crash).
- **Retry avec backoff** sur échec d'écriture.
- **Robustesse au chargement (décision d'ingénierie, défaut sûr) :**
  - Si le **load échoue**, **ne pas écraser** avec des stats par défaut → marquer le profil « non chargé » et **désactiver la sauvegarde** pour cette session (évite d'effacer la progression).
  - **Session-lock léger** recommandé pour éviter les écritures concurrentes (un joueur n'est que sur un serveur à la fois, mais reconnexions rapides possibles).
- **Schéma de données** (versionné, champ `schemaVersion`) :
  ```
  Profile {
    schemaVersion: number,
    stats: { kills, deaths, roundsPlayed, roundsWon, playTime?, bestKillstreak? },
    settings: { ... }   -- ou délégué à SettingsStore
  }
  ```
- **À trancher** : unifier la persistance avec `SettingsStore` existant (un seul profil joueur regroupant stats + réglages) **ou** garder deux DataStores séparés. → §12.

---

## 9. UI / UX

- **Direction visuelle : minimaliste neutre** (sobre, peu de couleurs, focus lisibilité, itérable rapidement). Aucun GUI n'existe → tout est à créer.
- **Mode de production des GUI : en code Luau dans `src/client/ui/`** (ScreenGui/Frame/TextButton créés au runtime). Versionné Git, synchronisé par Rojo, cohérent avec le repo. **Pas de construction d'UI via le MCP** (le `.rbxlx` n'est pas la source de vérité). Le MCP Roblox sert uniquement à **tester / inspecter / screenshot** en Play mode, pas à stocker l'UI.
- **Écrans à créer :**
  1. **Menu d'accueil** : titre/jeu, boutons **Play** et **Infos**.
  2. **Infos** (overlay, contenu retenu) :
     - **Comment surfer** (mécanique de mouvement : strafe, contrôle de vitesse, sauts/bhop).
     - **Contrôles / touches** (déplacement, saut, crouch, tir, recharge, Tab leaderboard).
     - **Crédits / version**.
     - *(« But du jeu / règles FFA » non explicitement retenu — optionnel, à ajouter si souhaité.)*
  3. **HUD** : timer + leaderboard (Tab).
  4. **Bannière de fin de round** (gagnant + résultat) avant retour menu.
- Accessibilité/i18n : non prioritaire (textes FR, à structurer pour traduction future si besoin).

---

## 10. Edge cases & failure modes

- **0 joueur spawné** : pas de round actif ; le round démarre au 1er Play.
- **Dernier joueur quitte en plein round** : round s'arrête/se met en veille ; redémarre au prochain Play.
- **Mort exactement à la fin du timer** : la fin de round prime (pas de respawn, on va au RESULT).
- **Égalité de kills en fin de round** : départage deaths puis ordre d'obtention (§4).
- **Échec DataStore (load)** : profil non chargé, sauvegarde désactivée pour la session, stats non écrasées (§8).
- **Échec DataStore (save)** : retry backoff ; dernier essai à `PlayerRemoving` / `BindToClose`.
- **Spam du bouton Play / Play alors que déjà vivant** : ignoré côté serveur (idempotent).
- **Exploit position/teleport pour kills** : capté par la validation §5 (bornes de vitesse `MovementConfig`).
- **Serveur qui ferme** (`game:BindToClose`) : flush des sauvegardes en attente.

---

## 11. Phase 2 — Multi-map (TeleportService)

> Documenté pour préparer la migration ; **hors périmètre Phase 1**.

- 1 **place par map** (contenu distinct), build Rojo dédié par place depuis le même repo (un `*.project.json` par place, ou un projet séparé — choix d'organisation).
- Le **lobby** peut devenir un place dédié, ou rester le même place avec un sélecteur de map.
- **Play** ouvre alors un **sélecteur de map** puis `TeleportService:Teleport(placeId, player)` ; Roblox instancie/choisit le serveur cible automatiquement.
- Passage d'état via `TeleportData` (ex. provenance, préférences).
- Le code Phase 1 doit isoler la logique de round/leaderboard du « comment on arrive sur la map » pour brancher ça proprement.

---

## 12. Questions ouvertes / à trancher avant ou pendant l'implémentation

1. **Persistance unifiée ?** Fusionner stats + réglages dans un seul profil DataStore avec/à côté de `SettingsStore`, ou garder séparé.
2. **Anti-spawnkill** : ajouter invulnérabilité brève + spawn éloigné des ennemis (non retenu en P1).
3. **« But du jeu / règles FFA »** dans l'écran Infos : à inclure ou non.
4. **Délai exact de respawn** et **durée de la bannière de fin de round** (valeurs à fixer).
5. **Points de spawn** : liste de `SpawnLocation` à placer sur la map existante.

---

## 13. Découpage d'implémentation suggéré (pour la prochaine session)

1. **Serveur — gating spawn** : `CharacterAutoLoads=false`, remote `RequestSpawn`, `LoadCharacter` à spawn aléatoire.
2. **Client — menu d'accueil** (Play/Infos) + caméra lobby + machine d'état §3.
3. **Serveur — RoundManager** : timer 5 min, démarrage au 1er Play, fin → gagnant → retour menu, reset.
4. **Combat serveur-validé** : étendre `Validator.luau`, autorité HP/kills, remotes hit.
5. **Leaderboard d'instance + HUD** (timer + Tab).
6. **Persistance** : profil DataStore (stats + réglages), save déconnexion + périodique, robustesse load.
7. **Écran Infos** (surf / contrôles / crédits).
8. **Bannière de fin de round.**
9. **Réglages restants** §12.

### Nouveaux fichiers probables (indicatif, à confirmer)
- `src/server/RoundManager.luau` — boucle de round, timer, gagnant.
- `src/server/SpawnManager.luau` — gating spawn + spawns aléatoires.
- `src/server/StatsStore.luau` — DataStore stats (ou fusion `SettingsStore`).
- `src/server/CombatValidator.luau` — ou extension de `Validator.luau`.
- `src/client/ui/MainMenu.luau` — menu Play/Infos.
- `src/client/ui/InfosScreen.luau` — écran Infos.
- `src/client/ui/RoundHUD.luau` — timer + leaderboard Tab.
- `src/client/systems/game/GameStateController.luau` — machine d'état client.
- `src/shared/GameConfig.luau` — constantes (durée round, délai respawn, etc.).
- Extensions `NetworkProtocol.luau` — remotes : RequestSpawn, RoundState, Hit, ScoreUpdate.
```

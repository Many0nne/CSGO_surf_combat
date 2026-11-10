# Anti-triche

État des lieux, menaces classées et plan d'implémentation (#160). Rien de ce document n'est encore implémenté, sauf ce
qui est décrit dans « Aujourd'hui ». Les issues proposées sont à la fin, dans « Plan ».

## Principe

Un tricheur contrôle tout son client (exécuteur Lua) : il lit et modifie les scripts locaux et le DataModel local, appelle
n'importe quel remote, à n'importe quel débit, avec n'importe quels arguments (sauf le `Player`), déplace son personnage
et change son mouvement ([Security tactics](https://create.roblox.com/docs/scripting/security/security-tactics),
[Movement validation](https://create.roblox.com/docs/scripting/security/network-ownership)). Donc :

- ce qui compte (dégâts, mort, score, position utilisée par le serveur) se décide ou se vérifie sur le serveur ;
- le client ne reçoit que ce dont il a besoin, et tout ce qui est répliqué peut être lu ;
- chaque remote est pensé pour le pire cas : arguments forgés, appel 1 000 fois par seconde, coût serveur au pire.

Ce que le serveur ne peut pas empêcher : un client qui vise ou réagit mieux qu'un humain (aimbot, triggerbot) tout en
envoyant des données plausibles. Là, on ne peut que détecter statistiquement, puis réagir.

## Ce qui est déjà en place

| Domaine | Validation actuelle | Où |
|---|---|---|
| Mêlée | Cible = autre participant vivant, arme de mêlée réellement en main, distance des racines ≤ 10 studs, dégâts et cadence lus dans `WeaponConfig` selon le type d'attaque, backstab recalculé sur les positions serveur (#47) | `src/server/Validator.luau:119-137` |
| Tir | Cible valide, arme à distance en main, partie touchée appartenant à la cible, distance des racines ≤ 250 studs, cadence `FireDelay` à 0,15 s près, dégâts calculés par le serveur selon la zone | `src/server/Validator.luau:97-115` |
| Position | Forme (Vector3 et angle finis, coordonnées ≤ 1e5), débit ≤ 2 × 20 Hz, distance ≤ `MAX_SPEED_SERVER` × durée + `MAX_DELTA_POS`, personnage vivant | `src/server/CharacterSync.luau:69-88` |
| Réglages | Réglages entièrement assainis par `PlayerSettings.sanitize`, une écriture DataStore au plus toutes les 10 s | `src/server/SettingsStore.luau:113-130` |
| Feedback | Type `string`, longueur 10 à 500, délai de 60 s après un envoi réussi, 5 envois par semaine (DataStore) | `src/server/FeedbackService.luau:76-104` |
| Debug | Remote `DebugPlaytest` créé seulement dans Studio | `src/server/DebugPlaytest.luau:365-372` |

Les bots (`src/server/bots/`) passent par le même `Validator` (`src/server/init.server.luau:285-292`) : leurs tirs sont
des raycasts serveur (`src/server/bots/BotArsenal.luau:184`), leurs munitions et leur temps de sortie sont gérés par
`BotArsenal` (`:110`, `:116-122`, `:142-148`). Toute nouvelle parade doit donc soit valoir aussi pour eux sans les gêner,
soit être réservée aux joueurs (`participant.isBot`), ce qui est indiqué pour chaque parade.

## Classement des menaces

Impact : ce que gagne le tricheur et ce que subissent les autres. Coût : serveur, réseau et complexité de la parade.

| # | Menace | Impact aujourd'hui | Coût de la parade | Priorité |
|---|---|---|---|---|
| T1 | Tir sans viser, à travers les murs, hitbox agrandie (« silent aim ») | **Critique** : un tir accepté par cible à 250 studs, 1 par 1,46 s, tête choisie (460 dégâts) | Faible serveur, moyen en complexité | P1 |
| D1 | Vitesse et téléportation | **Critique** : ~400 à 800 studs/s soutenus, téléportation de 300 studs par seconde de silence | Faible | P1 |
| M1 | Coup de couteau dans toutes les directions (« kill aura ») | **Élevé** : one-shot de dos à 10 studs, cumulable avec D1 | Faible | P2 |
| R1 | Remotes sans débit ni garde (respawn, feedback) | **Moyen** : respawn en 0,3 s au lieu de 2,5 s, quota DataStore du serveur épuisable | Faible | P1 |
| T2 | Munitions et durée d'equip | **Moyen** : tir dès l'equip (#159), pas de rechargement | Faible | P2 |
| D2 | Vol et noclip | **Moyen** : survivre au vide, passer les murs | Faible serveur, moyen en réglage (surf) | P2 |
| A1 | Aimbot, triggerbot | **Élevé** mais seulement détectable | Moyen, faux positifs | P3 |
| E1 | Wallhack, ESP | **Élevé** mais non bloquable à coût raisonnable | Très élevé | P4 (accepté) |

Les sections suivantes détaillent chaque menace : ce que fait le code, le risque, la parade, son coût et son impact.

## Tir

### T1. Ligne de vue, direction, distance, compensation de latence

**Aujourd'hui.** Le client fait le raycast depuis la caméra (`src/client/systems/weapon/HitscanSystem.luau:57-59`) et
envoie seulement `(targetChar, hitPart)` (`:78`). Le serveur vérifie la cible, l'arme, l'appartenance de la partie
et la distance des racines (`src/server/Validator.luau:103-110`) ; il ne sait pas d'où ni vers où le tir est parti.

**Risque.** Un client modifié envoie `HitscanDamage(n'importe quel ennemi, sa Head)` sans le regarder ni le voir :
l'AWP fait 115 × 4 = 460 dégâts à la tête (`src/shared/WeaponConfig.luau:13`, `src/shared/HitZones.luau:16`), donc
un mort par tir (100 PV, valeur par défaut du Humanoid), toutes les 1,46 s, sur tous les participants à moins de 250 studs, à travers les murs. Agrandir
localement les hitbox des autres (« hitbox expander ») marche aussi : le serveur ne regarde pas la géométrie.

**Parade.** Le client envoie aussi ce qu'il a tiré, et le serveur vérifie que ce tir pouvait toucher :

1. Arguments : `origin: Vector3`, `direction: Vector3` (unitaire), `hitPos: Vector3`, `shotTime: number`
   (`workspace:GetServerTimeNow()` au tir), en plus de `targetChar` et `hitPart`. Types et finitude vérifiés comme
   `CharacterSyncRules.isWellFormed`.
2. Rembobinage : le serveur garde (à créer, il n'existe pas) un historique des positions acceptées de chaque
   personnage, une seconde à 20 Hz, alimenté là où elles sont posées : joueurs dans `onClientPosition`
   (`src/server/CharacterSync.luau:89-91`), bots dans `relayBot` (`:117-118`).
   Le tireur voyait la cible à `shotTime - INTERP_DELAY` (`src/shared/CharacterSyncRules.luau:14`, 0,1 s) ; ce
   temps est borné à `[now - 0,4 s, now]` pour qu'un client ne puisse pas réclamer une position ancienne.
3. Origine : à moins de `5 + vitesse du tireur × 0,1` studs de la position du tireur à `shotTime` (il est en avance
   sur le serveur de sa propre latence, et peut aller à 200 studs/s en surf).
4. Direction : le rayon `origin + direction × t` passe à moins de `rayon de la zone + tolérance` de la position
   rembobinée de la partie annoncée (tête : sphère sur la tête rembobinée ; corps : capsule autour de la racine).
   Les offsets des parties sont pris sur le rig serveur, la tolérance couvre l'accroupi et l'interpolation.
5. Ligne de vue : raycast serveur de `origin` à `hitPos` limité à la géométrie de la map (`Workspace.Maps`, en
   inclusion), qui ignore donc les personnages et les objets mobiles, comme conseillé sur le DevForum
   ([Shooting backend validation](https://devforum.roblox.com/t/shooting-backend-validation-inaccuracies/4633077)).
   Un obstacle = tir refusé. Si la pénétration est implémentée un jour (`WeaponConfig.luau:19`, TODO), ce test
   devra en tenir compte.
6. Distance : `|hitPos - origin|` ≤ portée de l'arme.

Modèle : [RollbackHitbox](https://devforum.roblox.com/t/rollbackhitbox-server-authoritative-lag-compensation-for-roblox-shooters-open-source/4553295)
(rembobinage borné à 0,5 s, interpolation entre deux relevés). Limite connue : le client peut mentir sur `shotTime`
dans la borne de rembobinage, d'où la borne courte
([Making exploiter-proof guns](https://devforum.roblox.com/t/making-exploiter-proof-guns/235423)).

**Bots.** Leurs tirs sont des raycasts serveur depuis leurs yeux (`BotArsenal.luau:184`) : rembobinage à 0, origine
et ligne de vue vraies par construction. Garder pour eux le chemin actuel (`participant.isBot`) et le couvrir par un
test pour qu'un bot ne voie aucun tir refusé.

**Coût.** Serveur : 1 raycast et quelques calculs vectoriels par tir accepté, négligeable à 41 coups/min. Mémoire :
20 relevés par personnage. Réseau : ~60 octets de plus par tir. Complexité : moyenne (historique, tolérances à régler).

**Impact.** Supprime le silent aim, le tir à travers les murs et le hitbox expander. Reste l'aimbot (vraie visée).

**Faux positifs.** Gros ping, gigue, cible en surf rapide. Lancer d'abord la validation en mode « journal seul »
(tirs comptés comme refusables mais appliqués), mesurer, puis l'activer.

### Distance

`MAX_HITSCAN_RANGE = 250` (`src/server/Validator.luau:9`) alors que le client tire à 2 048 studs
(`HitscanSystem.luau:58`) : un tir légitime au-delà de 250 studs est refusé sans retour au tireur. Les bots tirent à 240
au plus pour cette raison (`src/shared/BotConfig.luau:108`). À trancher avec la taille des maps (voir « Trouvé » du
compte rendu de #160) ; la borne reste nécessaire contre T1.

### T2. Cadence, munitions, durée d'equip

**Cadence (fait).** Une seule cadence par arme et par participant, à 0,15 s près (`Validator.luau:13`, `:79-93`),
remise à zéro à l'apparition (`src/server/init.server.luau:150`). Un tir refusé ne relance pas la cadence : le spam est
sans effet.

**Munitions, aujourd'hui.** Suivies seulement par le client (`src/client/systems/weapon/WeaponSystem.luau:52-54`,
`:211`, `:233`) : un client modifié ne recharge jamais. Avec #165 (réserve illimitée), seule la contrainte du chargeur
compte : 5 tirs, puis `ReloadTime` = 3,7 s (`WeaponConfig.luau:16-18`).

**Munitions, risque.** Moyen : le tricheur tire toutes les 1,46 s sans la pause de 3,7 s tous les 5 tirs.

**Munitions, parade.** Après #165 : le serveur compte les tirs **acceptés** par arme (`magazine`), refuse le 6e tant
qu'un rechargement n'a pas duré `ReloadTime - tolérance`. Le début du rechargement est l'action `Reload` déjà envoyée
par le client (`init.server.luau:127-140`) ; un changement d'arme l'annule, comme côté client. Pas de réserve à suivre.
Bots : exclus (`BotArsenal` fait déjà respecter chargeur et rechargement, `BotArsenal.luau:116-148`), ou bien
`BotArsenal._startReload` appelle le même point d'entrée serveur. Coût : un compteur par participant et par arme.

**Durée d'equip, aujourd'hui.** Le client bloque tir et lunette pendant `EQUIPPING` (`canAct`,
`WeaponSystem.luau:43-45`, état posé `:257-271`), avec une durée tirée de la longueur de l'animation et non de
`EquipTime` (`:263-266`) ; #159 constate pourtant une visée et un tir possibles avant la fin de l'animation. Le serveur
ne contrôle rien.

**Durée d'equip, risque.** Moyen : un client modifié tire dès la sortie de l'arme (AWP : 1,58 s de gagnées,
`WeaponConfig.luau:23`), ce qui compte en duel après un changement d'arme.

**Durée d'equip, parade.** Le serveur voit déjà l'arrivée de l'outil dans le personnage (`ChildAdded`,
`init.server.luau:114-118`) : y noter `equippedAt`, et refuser une touche avant `equippedAt + EquipTime - tolérance`.
Valable pour les bots sans effet (ils attendent déjà `EquipTime`, `BotArsenal.luau:110`). Coût : nul. À faire avec #159.

## Mêlée

### M1. Orientation et ligne de vue

**Aujourd'hui.** #47 a réglé dégâts, cadence et arme en main (`Validator.luau:119-137`). Restent : la distance est
mesurée entre racines (10 studs, `:10`, alors que l'arme porte à 7,5, `WeaponConfig.luau:76`), sans regarder la
direction du tireur ni les obstacles.

**Risque.** « Kill aura » : un client modifié frappe toute cible à 10 studs, dans n'importe quelle direction, à travers
un mur fin. Frappée dans le dos, elle prend 50 × 2 = 100 dégâts (`WeaponConfig.luau:62`, `:77`), soit un mort. Couplé à
la téléportation (D1), c'est un kill par 0,4 s sur toute la map.

**Parade.** (1) Angle entre le cap du tireur (yaw de sa racine serveur, mis à jour à 20 Hz) et la direction vers la
cible ≤ ~70° dans le plan horizontal (le pitch n'est pas connu) ; (2) raycast serveur racine → racine limité à la map ;
(3) rembobinage de la cible avec l'historique de T1. Bots : orientation vraie par construction (`BotMotion`), test à
ajouter. Coût : un produit scalaire et un raycast par coup accepté.

**Impact.** Supprime le kill aura ; la portée reste un peu généreuse (tolérance latence), acceptable.

## Déplacement

Le mouvement est calculé par le client sur une racine ancrée ; il envoie position et cap à 20 Hz, le serveur valide puis
pose la racine et relaie (`src/server/CharacterSync.luau:1-7`). Le serveur n'a aucune physique à lui : il ne peut que
juger les positions reçues.

**Contrainte surf et bhop.** Les vitesses légitimes sont grandes : 90 studs/s mesurés en bhop de bots
(`docs/bots.md:80`), 200 studs/s et plus en surf (`docs/performance.md:98`), d'où `MAX_SPEED_SERVER = 300`
(`src/shared/MovementConfig.luau:47`). Le gain de vitesse en l'air vient de l'air strafe, pas d'une limite fixe : une
borne de vitesse seule ne peut pas être serrée. S'y ajoutent les boosts de la map (`Maps.Map.Boosts`, geysers et
lanceurs à vitesse imposée, portiques qui ajoutent `Boost` studs/s, `docs/maps.md:251-254`), détectés et appliqués par
le client seul (`src/client/systems/movement/BoostSystem.luau:1-2`) : une parade qui juge la vitesse ou la gravité
doit les connaître (règles pures dans `src/shared/MapRules.luau`, réutilisables par le serveur). La règle actuelle :
`|new - last| ≤ 300 × max(écoulé, 0,05) + 5` (`src/shared/CharacterSyncRules.luau:35-38`).

### D1. Vitesse et téléportation

**Aujourd'hui, failles de la règle.**

1. Le minimum de 0,05 s et la marge de 5 studs s'appliquent à **chaque** paquet, et le serveur accepte un paquet toutes
   les 0,025 s (`CharacterSync.luau:81`) : 20 studs par paquet, soit ~400 studs/s à 20 Hz et ~800 studs/s à 40 Hz.
2. Un paquet refusé ne met à jour ni `lastPos` ni `lastAt` (`CharacterSync.luau:85-90`) : après `T` secondes de silence
   ou de refus, le serveur accepte un saut de `300 × T + 5` studs. Il suffit de se taire une seconde pour se téléporter
   de 300 studs, dans n'importe quelle direction, y compris dans le dos d'une cible (M1).
3. Le refus ne corrige pas le client (`CharacterSync.luau:5`) : client et serveur divergent, ce qui ne pénalise que le
   joueur honnête qui a laggé.

**Risque.** Critique : vitesse plus que doublée en continu, et téléportation n'importe où en se taisant. La position
acceptée est celle que le `Validator` utilise pour la portée (`Validator.luau:65-67`) : se téléporter dans le dos d'une
cible rend le kill aura (M1) praticable sur toute la map.

**Parade.**

1. Paquets groupés : remplacer le minimum par paquet par un **seau qui fuit** (leaky bucket, conseillé par la doc
   Roblox, [Movement validation](https://create.roblox.com/docs/scripting/security/network-ownership)) : budget de
   distance qui se remplit à `MAX_SPEED_SERVER` studs/s, plafonné (ex. 0,25 s de budget), consommé par chaque
   déplacement accepté. La marge `MAX_DELTA_POS` est un plafond du seau, pas un bonus par paquet.
2. Silence : plafonner la durée prise en compte (ex. 0,5 s). Au-delà, refuser et **corriger** : le serveur renvoie au
   client sa dernière position acceptée (remote ou attribut), le client s'y replace avec vitesse nulle. Le
   [modèle d'autorité serveur](https://create.roblox.com/docs/projects/server-authority) fait la même chose en natif.
3. Apparitions et lancement depuis le soleil : déjà gérés (la piste repart de la racine posée par `SpawnManager`,
   `CharacterSync.luau:32-42`) ; tout futur téléport de gameplay devra passer par le serveur et réinitialiser la piste.
4. Option : borne d'accélération plutôt que de vitesse (la vitesse ne peut croître que de `AIR_ACCEL`/gravité × dt),
   plus serrée mais délicate avec les rampes ; à n'envisager qu'après mesure.

**Bots.** Non concernés : leurs positions viennent du serveur (`relayBot`, `CharacterSync.luau:117-128`).

**Coût.** Nul côté serveur (quelques nombres par joueur), un remote de correction rare. Complexité faible, sauf la
correction côté `MovementController`, à tester en jeu (lag réel, surf rapide).

**Impact.** Ramène le tricheur à 300 studs/s au plus et supprime la téléportation, qui est l'aide principale du kill
aura et de l'ESP actif.

### D2. Vol et noclip

**Aujourd'hui.** Rien : une position est acceptée si elle respecte la distance, qu'elle soit en l'air depuis 30 s ou
de l'autre côté d'un mur. La mort par chute (`src/server/KillZone.luau:23-32`) ne teste que les positions acceptées :
un client qui flotte au-dessus du vide, ou qui n'envoie jamais de position sous `KillHeight`, ne meurt pas.

**Risque.** Moyen : rester en l'air hors d'atteinte, se cacher dans un mur, ne jamais mourir de chute.

**Parade.**

- **Noclip** : raycast serveur `lastPos → newPos` limité à la map. Un segment qui traverse une paroi épaisse est refusé
  et corrigé (D1). Le rayon part du centre du personnage, qui ne traverse jamais une paroi chez un client honnête (il
  entre en collision avec son rayon `CHAR_RADIUS`) ; tolérance pour les arêtes de rampe frôlées, et parois sans
  collision (`CanCollide` faux, volumes de boost) exclues du raycast.
- **Vol** : suivre le temps passé sans support. Un shapecast court sous le joueur (ou autour, pour le surf, où le
  joueur glisse sur une rampe inclinée) dit s'il est près d'une surface. Loin de toute surface, la vitesse verticale
  doit baisser d'environ `GRAVITY × dt` (`MovementConfig.luau:18`, -110) à la tolérance près ; sinon, point de
  suspicion. Échelles (`LADDER_CLIMB_SPEED`), boosts et lancement depuis le soleil exemptés.
- **Vide** : si la position n'est pas mise à jour pendant plus de N secondes alors que le joueur était en chute libre,
  le considérer comme tombé.

**Coût.** 1 à 2 raycasts par paquet accepté et par joueur (20/s/joueur) : quelques centaines par seconde à pleine
partie, acceptable. Complexité moyenne : le surf est le cas difficile, à régler en mode journal seul.

**Impact.** Moyen : le vol et le noclip donnent surtout des positions de tir hors d'atteinte, que T1 (ligne de vue)
limite déjà en partie.

## Remotes

### Inventaire

Créés dans `src/server/init.server.luau:40-58`, noms dans `src/shared/NetworkProtocol.luau`. Seuls les remotes écoutés
par le serveur (C→S) sont une surface d'attaque ; un `FireServer` sur un remote S→C n'a pas d'écouteur et est ignoré.

| Remote | Sens | Arguments | Validation actuelle | Manque |
|---|---|---|---|---|
| `MeleeDamage` | C→S | `targetChar, attackKind` | Cible, arme, portée, type d'attaque, cadence, dégâts serveur (`Validator.luau:119-137`) | Orientation, ligne de vue (M1), equip (T2), tireur vivant |
| `HitscanDamage` | C→S | `targetChar, hitPart` | Cible, arme, partie de la cible, portée 250, cadence (`Validator.luau:97-115`) | Origine, direction, ligne de vue, rembobinage (T1), munitions, equip (T2), tireur vivant |
| `CharacterSync` (non fiable) | C→S puis S→C | `pos, yaw` | Forme, débit 40 Hz, distance (`CharacterSync.luau:69-88`) | Seau et silence (D1), noclip, vol (D2), correction |
| `WeaponAction` | C→S | `action` | Valeur `Shoot`/`Reload`, outil en main, 0,05 s mini (`init.server.luau:127-139`) | `Shoot` non lié à la cadence de l'arme : 20 faux tirs/s attirent les bots (`hearShot`, `:143`) et, avec #156, déclencheraient 20 sons chez tous |
| `RequestSpawn` | C→S | aucun | Refusé si personnage en place ou bannière de fin (`init.server.luau:189-206`) | Délai de réapparition non vérifié, appels en vol (voir R1) |
| `SendFeedback` | C→S | `text` | Type, longueur, 60 s après un succès, 5 par semaine (`FeedbackService.luau:76-104`) | Débit en mémoire indépendant du succès (voir R1) |
| `SaveSettings` | C→S | table | `PlayerSettings.sanitize`, écriture différée de 10 s (`SettingsStore.luau:113-130`) | Débit (coût CPU seulement, faible) |
| `GetSettings` (RemoteFunction) | C→S | aucun | Attend le chargement, 20 s au plus (`SettingsStore.luau:101-109`) | Appels simultanés non bornés pendant le chargement (fils qui attendent) |
| `DebugPlaytest` | C→S | `id, ok, detail, data` | Studio seulement, id attendu et propriétaire (`DebugPlaytest.luau:365-378`) | Rien en jeu publié |
| `HitConfirm`, `RoundState`, `ScoreUpdate`, `RoundResult`, `PlayerDied`, `FeedbackAck` | S→C | — | — | `PlayerDied` donne la position de la victime à tous (`RoundManager.luau:162-173`) : sans effet tant que l'ESP est accepté (E1) |

### R1. Garde commune et failles constatées

**Respawn (risque moyen : 2,2 s gagnées par mort).** Le personnage mort est détruit 0,3 s après la mort (`init.server.luau:165-169`) ; `canSpawn` ne teste que
`player.Character.Parent` (`:191`). Un client modifié qui envoie `RequestSpawn` après 0,3 s réapparaît tout de suite au
lieu d'attendre `RESPAWN_DELAY` = 2,5 s (`src/shared/GameConfig.luau:5`). Puis la réapparition programmée par le serveur
(`RoundManager.luau:215-219`) rappelle `SpawnManager.spawnPlayer` (`init.server.luau:175`) sans vérifier qu'il est
déjà en vie : son personnage est remplacé par un neuf. Le client légitime n'envoie `RequestSpawn` que depuis le menu
(`src/client/systems/game/GameStateController.luau:242-250`). Parade : `canSpawn` refuse un participant mort depuis moins
de `RESPAWN_DELAY` dans un round actif, et la réapparition programmée ne fait rien si le joueur a déjà un personnage
vivant ; un seul `LoadCharacterAsync` en vol par joueur.

**Feedback (risque moyen : déni de service DataStore).** `lastSent` n'est écrit qu'après un envoi réussi au webhook (`FeedbackService.luau:117`), alors que
chaque demande valide lit (et écrit) le DataStore (`:100`). Sans webhook configuré, ou une fois la limite
hebdomadaire atteinte, un client qui spamme provoque un `GetAsync` par appel : il épuise le budget DataStore du
serveur, partagé avec `SettingsStore` et `StatsStore`, dont le chargement échoue alors pour tout le monde
(`SettingsStore.luau:73-75` coupe la sauvegarde pour la session). De plus, si `GetAsync` échoue, la liste lue est vide
(`FeedbackService.luau:41-48`) et le `SetAsync` qui suit l'écrase par `{ now }` (`:67-70`) : une panne DataStore remet
le quota hebdomadaire à zéro. Parade : délai en mémoire posé à chaque demande qui atteint le DataStore, quel que soit le
résultat, et pas d'écriture du quota quand la lecture a échoué.

**Garde commune.** Un petit module serveur `RemoteGuard` (pur, testable sous Lune) : seau à jetons par joueur et par
remote (débit et rafale), vérification de types simple (`"Instance"`, `"Vector3"` fini, `"string"` borné, valeur
d'énumération). Un dépassement de débit est ignoré ; un argument de type impossible pour un client honnête est
journalisé comme violation forte (voir « Réponse »). Roblox limite déjà le débit client → serveur par type de remote,
mais globalement, et sans le dire au jeu : la limite par remote est à faire soi-même
([Remote events](https://create.roblox.com/docs/scripting/events/remote),
[Rate limiter module](https://devforum.roblox.com/t/rate-limiter-module-for-remotes/616268)).

**`WeaponAction`.** Ne relayer (#156) et ne faire entendre aux bots que des tirs acceptés par le serveur : brancher le
relais du son sur `Validator.authorizeHitscan` (et sur un tir « dans le vide » validé : cadence, munitions, equip), pas
sur l'action visuelle du client.

**Coût.** Négligeable. **Impact.** Ferme deux failles réelles et donne le point d'entrée commun de la journalisation.

## Aimbot et triggerbot (A1)

**Aujourd'hui.** Rien. Le serveur ne connaît pas l'orientation verticale de la caméra (seul le cap est envoyé,
`src/client/systems/network/CharacterSync.luau:95-102`).

**Risque.** Élevé : après T1, l'aimbot reste la triche la plus efficace, et elle envoie des données valides.

**Parade : détection, jamais blocage.** Statistiques par joueur, calculées sur le serveur :

- taux de tirs à la tête parmi les touches, et taux de touches parmi les tirs (tirs connus grâce à T1/T2) ;
- vitesse angulaire de la visée juste avant le tir (« flick ») : demande d'envoyer le pitch avec le cap dans
  `CharacterSync` (9 octets de plus par paquet) ou la direction de visée dans le tir ;
- temps de réaction entre l'apparition d'une cible et le tir : demande un calcul de visibilité, trop cher (voir E1),
  écarté.

Seuils relatifs à la population (ex. > 3 écarts-types sur au moins 30 touches) et uniquement en journal pour revue
humaine. Sur un FPS à l'AWP, les très bons joueurs ont naturellement beaucoup de tirs à la tête : risque de faux positif
élevé, pas de sanction automatique. Bots exclus des statistiques. Coût : faible serveur, moyen en analyse.

## Wallhack et ESP (E1)

**Aujourd'hui.** Toutes les positions sont envoyées à tous :

- le relais `CharacterSync` envoie à chaque autre joueur la position de chacun, sans filtre
  (`src/server/CharacterSync.luau:94-98`, `:124`) ;
- le serveur pose la racine de chaque personnage (`:91`), propriété répliquée nativement à tous les clients ;
- les personnages sont dans `Workspace`, sans streaming (`default.project.json:43`) ;
- `PlayerDied` donne la position de chaque mort (`RoundManager.luau:162-173`), et #156 relaiera les tirs.

**Risque.** Élevé : un ESP n'a qu'à lire `Workspace`. Indétectable côté serveur.

**Parade envisagée et écartée pour l'instant.** Un filtrage serveur par visibilité (comme la doc Roblox le recommande
pour les données confidentielles,
[Access control](https://create.roblox.com/docs/scripting/security/access-control)) demanderait : un test de
visibilité par paire de participants à ~10 Hz (20 participants = 3 800 raycasts/s), une marge de latence pour ne pas
faire « surgir » les ennemis, et surtout de ne plus répliquer la racine serveur (positions gardées dans une table,
personnages retirés ou cachés pour chaque client), ce qui casse le modèle actuel (`CharacterSync`, ragdoll, arme 3P).
Les maps de surf sont ouvertes, avec de longues lignes de vue : le gain serait faible pour un coût très élevé. Le
[modèle d'autorité serveur](https://create.roblox.com/docs/projects/server-authority) de Roblox n'aide pas ici
(il exige `StreamingEnabled`, mais les personnages proches restent répliqués).

**Coût.** Serveur : élevé (raycasts par paire, croît comme le carré du nombre de participants). Réseau : un peu moins
de positions envoyées. Complexité : très élevée (refonte de `CharacterSync` et de la réplication des personnages).
**Impact** : partiel, un ESP garderait les adversaires visibles ou presque, et les sons de tir (#156) les trahissent.

**Décision proposée.** Accepter le risque, le réévaluer si le jeu grossit. Pas d'issue dans ce plan.

## Réponse aux triches

### Journaliser

Module serveur `CheatLog` : chaque parade y signale une violation `(participant, catégorie, gravité, détail)`.

- `warn` limité (comme `CharacterSync.luau:44-58`) pour la console serveur en développement ;
- compteurs par joueur et par catégorie, avec un score qui décroît dans le temps (seau qui fuit) ;
- en jeu publié, résumé envoyé au départ du joueur s'il a des violations (webhook comme `FeedbackService`, ou
  DataStore/MemoryStore à relire) : nom, UserId, compteurs, pire violation.
- bots ignorés (`participant.isBot`), Studio : journal seulement.

### Classer les violations

| Gravité | Exemples | Faux positifs possibles |
|---|---|---|
| Forte | Argument d'un type impossible pour notre client (`Vector3` NaN, `targetChar` non Instance, `attackKind` inconnu), remote de debug appelé en jeu, tir alors que l'arme n'est pas en main | Quasi nuls : notre client n'envoie jamais ça. Seul risque : un bug de notre code, à couvrir par des tests |
| Moyenne | Tir sans ligne de vue, origine trop loin, noclip, téléport refusé | Ping élevé, gigue, perte de paquets, surf rapide sur une arête |
| Faible | Paquet au-delà du débit, tir avant la cadence de peu, flick suspect | Fréquents : rafales réseau, horloge, très bons joueurs |

### Kick

`player:Kick(raison)` :

- 3 violations fortes dans une session (pas 1 : laisse une marge à nos propres bugs, le temps de les voir au journal) ;
- score de violations moyennes au-dessus d'un seuil (ex. 20 points en 30 s, décroissance 1 point/s) : seuil fixé
  **après** une période en journal seul, à partir des scores observés chez les joueurs honnêtes ;
- jamais pour les violations faibles : elles sont ignorées (paquet ou tir refusé) et seulement comptées.

### Bannissement

[`Players:BanAsync`](https://create.roblox.com/docs/reference/engine/classes/Players#BanAsync), avec détection des
comptes secondaires ([annonce de la Ban API](https://devforum.roblox.com/t/introducing-the-ban-api-and-alt-account-detection/3039740)) :

- d'abord **manuel**, depuis le Creator Hub, à la lecture du journal (le DevForum rapporte une détection des comptes
  secondaires imparfaite, et elle ne marche pas dans Studio) ;
- automatique plus tard, seulement pour des violations fortes répétées sur plusieurs sessions, avec des durées
  croissantes (1 jour, 7 jours, puis définitif) ;
- aucune sanction automatique sur les statistiques d'aimbot (A1).

Pour mémoire, Roblox propose aussi une [API de confiance de l'appareil](https://create.roblox.com/docs/scripting/security/device-trust)
(niveau de confiance au join, sans action de Roblox) : à considérer plus tard pour isoler les appareils douteux, elle
ne remplace aucune validation serveur.

## Pistes écartées

- **Modèle d'autorité serveur de Roblox** ([doc](https://create.roblox.com/docs/projects/server-authority)) : il
  supprime vitesse et vol à la racine, mais impose le mouvement dans `BindToSimulation` sur des pièces simulées,
  `StreamingEnabled`, les `InputAction`, et ne gère pas bien les `Tool`. Notre mouvement façon Source est un contrôleur
  maison sur une racine ancrée : ce serait une réécriture complète. À revoir si les validations D1/D2 ne suffisent pas.
- **Noms de remotes obscurcis** : la doc Roblox le suggère contre les scripts tout faits, mais un exécuteur lit les
  scripts clients décompilés ; gain nul pour un coût de lisibilité.
- **Anti-triche côté client** (détection d'exécuteur dans un LocalScript) : contournable par définition.
- **Filtrage ESP par visibilité** : voir E1.

## Plan

Issues proposées, dans l'ordre d'implémentation. **À valider avant création sur GitHub.** Chaque parade passe d'abord en
mode « journal seul » (violation comptée, action appliquée quand même) quand elle risque des faux positifs, puis en
mode bloquant une fois mesurée.

### 1. Anti-triche : journal des violations et garde des remotes — P1

- **Résumé.** Module `CheatLog` (violations, score décroissant, résumé au départ) et module pur `RemoteGuard` (seau à
  jetons par joueur et remote, vérifications de type). Branché sur tous les remotes C→S de l'inventaire.
- **Critères.** Tous les `OnServerEvent`/`OnServerInvoke` passent par `RemoteGuard` ; un argument de type impossible est
  journalisé « fort » ; kick à 3 violations fortes ; bots et Studio sans sanction ; tests Lune du seau et des types.
- **Dépendances.** Aucune. **Priorité.** P1 (socle des suivantes).

### 2. Corriger le contournement du délai de réapparition et le spam du feedback — P1

- **Résumé.** Les deux failles de R1.
- **Critères.** `RequestSpawn` refusé moins de `RESPAWN_DELAY` après la mort pendant un round actif ; la réapparition
  programmée ne remplace jamais un personnage vivant ; un seul chargement en vol par joueur ; `SendFeedback` limité en
  mémoire avant tout accès DataStore, quel que soit le résultat ; tests.
- **Dépendances.** Peut se faire avant 1 (correctif autonome), journalisation branchée ensuite. **Priorité.** P1.

### 3. Déplacement : seau de distance, durée de silence plafonnée, correction serveur — P1

- **Résumé.** D1 : remplacer le minimum par paquet par un seau qui fuit, plafonner le temps de silence, renvoyer le
  client à sa dernière position acceptée après un refus.
- **Critères.** Plus de ~300 studs/s soutenus, plus de téléportation après silence ; correction appliquée par
  `MovementController` (vitesse nulle) ; surf à 200+ studs/s et bhop sans refus en jeu (test utilisateur) ;
  tests Lune de `CharacterSyncRules` (paquets groupés, silence, rafale légitime) ; bots non concernés.
- **Dépendances.** 1 pour journaliser. **Priorité.** P1.

### 4. Historique des positions serveur (rembobinage) — P1

- **Résumé.** Tampon par personnage (joueurs et bots) des positions acceptées, horodatées serveur, une seconde ;
  fonction pure `sampleAt(t)` bornée à `[now - MAX_REWIND, now]`.
- **Critères.** Alimenté par `CharacterSync` et `relayBot` ; nettoyé à la mort et au départ (pas de fuite, cf.
  `docs/performance.md`) ; tests Lune (interpolation, bornes).
- **Dépendances.** Aucune. **Priorité.** P1 (préalable de 5 et 7).

### 5. Tir : origine, direction, ligne de vue et distance validées par le serveur — P1

- **Résumé.** T1 : le client envoie origine, direction, point d'impact et instant du tir ; le serveur vérifie origine,
  direction contre la cible rembobinée, ligne de vue sur la map, distance.
- **Critères.** Un tir sur une cible non visée ou derrière un mur est refusé ; journal seul pendant une phase de mesure,
  puis bloquant ; tirs des bots inchangés (test) ; tolérances documentées ici ; décider la portée (250 vs 2 048).
- **Dépendances.** 4 ; 1 pour journaliser. **Priorité.** P1.

### 6. Tir : durée d'equip et chargeur vérifiés par le serveur — P2

- **Résumé.** T2 : `equippedAt` noté à l'arrivée de l'outil, touche refusée avant `EquipTime` ; compteur de chargeur
  serveur et rechargement de `ReloadTime` déclenché par l'action `Reload`.
- **Critères.** Tir pendant l'equip refusé (volet serveur de #159) ; 6e tir sans rechargement refusé ; bots exclus ou
  branchés sur le même point d'entrée, sans tir refusé ; tests `Validator.spec.luau`.
- **Dépendances.** #165 (réserve illimitée : seul le chargeur est suivi), #159 (volet client). **Priorité.** P2.

### 7. Mêlée : orientation et ligne de vue — P2

- **Résumé.** M1 : angle horizontal entre le cap du tireur et la cible, raycast racine → racine sur la map, cible
  rembobinée.
- **Critères.** Coup dans le dos du tireur ou à travers un mur refusé ; coups légitimes en mouvement acceptés (test en
  jeu) ; bots inchangés ; tests.
- **Dépendances.** 4. **Priorité.** P2.

### 8. Déplacement : noclip et vol — P2

- **Résumé.** D2 : raycast `lastPos → newPos`, suivi du temps sans support et de la gravité, chute dans le vide sans
  paquet.
- **Critères.** Traverser un mur ou flotter est refusé et corrigé ; surf, échelles, boosts, lancement depuis le soleil sans
  faux positif (journal seul d'abord, puis test utilisateur) ; coût mesuré avec la sonde `ServerPerf`.
- **Dépendances.** 3 (correction). **Priorité.** P2.

### 9. Relais des tirs aux autres clients sur tirs validés seulement — P2 (dans #156)

- **Résumé.** Pas d'issue séparée : contrainte à ajouter à #156. Le relais part d'un tir accepté par le serveur
  (cadence, munitions, equip), jamais de l'action visuelle `WeaponAction` du client ; `hearShot` des bots aussi.
- **Dépendances.** 6 de préférence. **Priorité.** suit #156.

### 10. Statistiques de visée (aimbot) — P3

- **Résumé.** A1 : taux de tirs à la tête, taux de touches, vitesse angulaire avant le tir ; pitch ajouté à la synchro.
- **Critères.** Statistiques au journal, seuils relatifs à la population, aucune sanction automatique, bots exclus.
- **Dépendances.** 1, 5. **Priorité.** P3.

### 11. Bannissement — P3

- **Résumé.** `Players:BanAsync` pour les récidives de violations fortes sur plusieurs sessions, durées croissantes ;
  bannissement manuel documenté en attendant.
- **Critères.** Jamais en Studio ni sur des statistiques ; raison privée explicite ; procédure de levée documentée.
- **Dépendances.** 1, et des semaines de journal en production. **Priorité.** P3.

Non proposé : filtrage ESP par visibilité (E1), modèle d'autorité serveur (voir « Pistes écartées »).

## Sources

- Roblox Creator Hub : [Security tactics](https://create.roblox.com/docs/scripting/security/security-tactics),
  [Movement validation et network ownership](https://create.roblox.com/docs/scripting/security/network-ownership),
  [Access control et confidentialité](https://create.roblox.com/docs/scripting/security/access-control),
  [Server authority](https://create.roblox.com/docs/projects/server-authority),
  [Remote events](https://create.roblox.com/docs/scripting/events/remote),
  [Players:BanAsync](https://create.roblox.com/docs/reference/engine/classes/Players#BanAsync),
  [Device trust](https://create.roblox.com/docs/scripting/security/device-trust).
- DevForum : [Ban API et comptes secondaires](https://devforum.roblox.com/t/introducing-the-ban-api-and-alt-account-detection/3039740),
  [RollbackHitbox (compensation de latence)](https://devforum.roblox.com/t/rollbackhitbox-server-authoritative-lag-compensation-for-roblox-shooters-open-source/4553295),
  [Shooting backend validation](https://devforum.roblox.com/t/shooting-backend-validation-inaccuracies/4633077),
  [Making exploiter-proof guns](https://devforum.roblox.com/t/making-exploiter-proof-guns/235423),
  [Rate limiter module for remotes](https://devforum.roblox.com/t/rate-limiter-module-for-remotes/616268).

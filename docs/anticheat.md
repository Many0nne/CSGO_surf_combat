# Anti-triche

État des lieux, menaces classées et plan d'implémentation (#160). Est implémenté ce qui est décrit dans « Ce qui est
déjà en place », dans les paragraphes « Aujourd'hui », dans « Journaliser » (#170 : `CheatLog`, `RemoteGuard`) et
dans les parades marquées « fait » ; le reste est à faire. Les issues proposées sont à la fin, dans « Plan ».

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
| Mêlée | Cible = autre participant vivant, arme de mêlée réellement en main, distance des racines ≤ 10 studs, dégâts et cadence lus dans `WeaponConfig` selon le type d'attaque, backstab recalculé sur les positions serveur (#47) ; pour un joueur, durée d'equip (#175, voir T2), instant du coup borné par le ping (#214, journal seul), orientation et ligne de vue vers la cible rembobinée à cet instant, pose comprise (#176, #213, journal seul, voir M1) | `src/server/Validator.luau` (`authorizeMelee`), `src/server/ShotRules.luau` |
| Tir | Cible valide (vivante), arme à distance en main, partie touchée appartenant à la cible, distance des racines ≤ `Validator.MAX_HITSCAN_RANGE` (~2 256 studs ; bots : 250), cadence `FireDelay` à 0,15 s près, dégâts calculés par le serveur selon la zone ; pour un joueur, forme, instant du tir borné par le ping (#214, journal seul), origine, visée sur la cible rembobinée dans sa pose (cap, accroupi, #213), portée et ligne de vue (#174, voir T1), durée d'equip et chargeur (#175, voir T2 ; l'equip vaut aussi pour la mêlée), touche rattachée à son `ShotFired` par `shotTime` (#216, journal seul) | `src/server/Validator.luau` (`authorizeHitscan`, `validateShot`), `src/server/ShotRules.luau`, `src/server/ShotLinkRules.luau` |
| Position | Forme (Vector3 et angle finis, coordonnées ≤ 1e5, accroupi booléen), personnage vivant, seau de distance (450 studs/s soutenus, client plafonné à 420 horizontaux, silence plafonné), refus journalisé et corrigé (#172) ; noclip et vol journalisés (#177, journal seul), joueur silencieux au-dessus du vide déclaré tombé | `src/server/CharacterSync.luau` (`refuse`, `judgeGuard`, `onClientPosition`), `src/shared/CharacterSyncRules.luau` (`tryMove`), `src/shared/MovementGuardRules.luau` |
| Réglages | Réglages entièrement assainis par `PlayerSettings.sanitize`, une écriture DataStore au plus toutes les 10 s | `src/server/SettingsStore.luau` (`onSaveSettings`) |
| Feedback | Type `string`, longueur 10 à 500, délai de 60 s après un envoi réussi, 5 envois par semaine (DataStore) | `src/server/FeedbackService.luau` (`init`, `COOLDOWN`, `consumeWeeklyQuota`) |
| Inventaire (#267) | Le serveur seul donne les Tools : `StarterPack` vide, sac rempli des seuls Tools possédés (inventaire par défaut, sauvegardé, admin) à chaque apparition ; un Tool non possédé arrivé en main est journalisé (`Inventory`, faible) et retiré, sans equip ni modèle 3P ; une arme en main non possédée ne tire (touche, relais `ShotFired`), ne frappe ni ne recharge (`weaponInHand`, joueurs et bots). L'attribut `OwnedItems` du Player est informatif, jamais relu. Équipement (#280) : le sac ne reçoit que l'arme de chaque emplacement (SNIPER, COUTEAU) ; `EquipItem` refusé hors du menu (personnage vivant), avant le chargement, pour un item non possédé, une arme d'un autre emplacement ou le skin d'une autre arme (ces derniers journalisés, `Inventory`, faible) ; un choix enregistré qui n'est plus possédé est remplacé par l'équipement par défaut. L'attribut `EquippedItems` est informatif, jamais relu | `src/server/InventoryStore.luau` (`ownsTool`, `syncTools`, `equip`), `src/shared/InventoryRules.luau` (`equip`, `resolveEquipped`), `trackWeapon3P` de `src/server/init.server.luau`, `Validator.setOwnership` |
| Rôles (#266) | Rôle décidé par le serveur (listes d'UserId + `game.CreatorId`), jamais lu du client ; l'attribut `Role` du Player est informatif, les contrôles passent par `Roles.hasRole` | `src/server/Roles.luau` (`hasRole`) |
| Debug | Remote `DebugPlaytest` créé seulement dans Studio | `src/server/DebugPlaytest.luau` (`DebugPlaytest.init`) |
| Relais des tirs (son et recul 3P chez les autres) | Tireur vivant, arme à distance en main prête (equip, chargeur), forme, origine près du tireur, cadence de l'arme (#156) ; tir accepté compté dans le chargeur (#215) | `src/server/ShotRelayRules.luau`, `Validator.isReadyToFire`, `Validator.noteShotFired`, `relayShot` de `src/server/init.server.luau` |
| Statistiques de visée (#178) | Par joueur : tirs acceptés, touches (rattachées à leur tir par `shotTime` ou orphelines, #216), têtes, flicks suivis d'une touche ; z-score contre les autres joueurs du serveur, journal seul (A1) | `src/server/AimStats.luau`, branchement dans `src/server/init.server.luau` |
| Tous les remotes C→S | Garde commune (#170) : débit par joueur et par remote, types des arguments, violations journalisées, kick à 3 violations fortes | `src/server/RemoteGuard.luau`, `src/server/CheatLog.luau` |

Les bots (`src/server/bots/`) passent par le même `Validator` (`BotManager.init` dans `src/server/init.server.luau`) : leurs tirs sont
des raycasts serveur (`src/server/bots/BotArsenal.luau`, tir du bot), leurs munitions et leur temps de sortie sont gérés par
`BotArsenal` (`equip`, `_startReload`, `isReady`). Toute nouvelle parade doit donc soit valoir aussi pour eux sans les gêner,
soit être réservée aux joueurs (`participant.isBot`), ce qui est indiqué pour chaque parade.

## Classement des menaces

Impact : ce que gagne le tricheur et ce que subissent les autres. Coût : serveur, réseau et complexité de la parade.

| # | Menace | Impact aujourd'hui | Coût de la parade | Priorité |
|---|---|---|---|---|
| T1 | Tir sans viser, à travers les murs, hitbox agrandie (« silent aim ») | **Critique** : un tir accepté par cible à 250 studs, 1 par 1,46 s, tête choisie (460 dégâts) | Faible serveur, moyen en complexité | P1 |
| D1 | Vitesse et téléportation | Fermé (#172, #212) : 450 studs/s soutenus au plus, saut borné à 337,5 studs après un silence, refus corrigé | Faible | Fait |
| M1 | Coup de couteau dans toutes les directions (« kill aura ») | Détecté (#176, journal seul) : coup hors du cap ou à travers un mur journalisé ; **élevé** tant qu'il n'est pas en `block` | Faible | P2 |
| R1 | Remotes sans débit ni garde (respawn, feedback) | Fermé (#170, #171) : garde commune, délai de réapparition et feedback limité en mémoire | Faible | Fait |
| T2 | Munitions et durée d'equip | Fermé (#175, #215) : touche refusée pendant l'equip ; chaque tir, touché ou manqué, compté : 6e tir refusé sans rechargement | Faible | Fait |
| D2 | Vol et noclip | Détecté (#177) : noclip et vol au journal (journal seul), vide fermé | Faible serveur, moyen en réglage (surf) | Fait (journal) |
| A1 | Aimbot, triggerbot | Détecté statistiquement (#178, journal seul) : tête, touches et flicks comparés aux autres joueurs ; **élevé**, rien n'est bloqué | Moyen, faux positifs | P3 |
| E1 | Wallhack, ESP | **Élevé** mais non bloquable à coût raisonnable | Très élevé | P4 (accepté) |

Les sections suivantes détaillent chaque menace : ce que fait le code, le risque, la parade, son coût et son impact.

## Tir

### T1. Ligne de vue, direction, distance, compensation de latence

**Avant #174.** Le client faisait le raycast depuis la caméra et envoyait seulement `(targetChar, hitPart)` ; le
serveur vérifiait la cible, l'arme, l'appartenance de la partie et la distance des racines, sans savoir d'où ni vers où
le tir était parti. **Fait (#174)** : la parade ci-dessous, détails dans « Tolérances et modes ».

**Risque.** Un client modifié envoie `HitscanDamage(n'importe quel ennemi, sa Head)` sans le regarder ni le voir :
l'AWP fait 115 × 4 = 460 dégâts à la tête (`Damage` de l'AWP dans `src/shared/WeaponConfig.luau`, `HitZones.Multipliers` dans `src/shared/HitZones.luau`), donc
un mort par tir (100 PV, valeur par défaut du Humanoid), toutes les 1,46 s, sur tous les participants à moins de 250 studs, à travers les murs. Agrandir
localement les hitbox des autres (« hitbox expander ») marche aussi : le serveur ne regarde pas la géométrie.

**Parade.** Le client envoie aussi ce qu'il a tiré, et le serveur vérifie que ce tir pouvait toucher :

1. Arguments : `origin: Vector3`, `direction: Vector3` (unitaire), `hitPos: Vector3`, `shotTime: number`
   (`workspace:GetServerTimeNow()` au tir), en plus de `targetChar` et `hitPart`. Types et finitude vérifiés comme
   `CharacterSyncRules.isWellFormed`, par les fonctions de `MathRules` (une seule copie de la règle « fini »).
2. Rembobinage : le serveur garde un historique des positions acceptées de chaque personnage, une seconde à 20 Hz,
   alimenté là où elles sont posées : joueurs dans `onClientPosition` (après acceptation), bots dans `relayBot`.
   **Fait (#173)** : module pur `src/shared/PositionHistory.luau` (tampon circulaire de 35 relevés, un relevé au plus
   tous les 0,03 s soit 20 Hz nominal et 33 Hz au plus, avec marge pour la gigue et le relais des bots, horloge
   `workspace:GetServerTimeNow()`, la dernière position acceptée est toujours gardée à part ; `sampleAt(history, t, now)`
   interpole et borne `t` à `[now - MAX_REWIND, now]`, `MAX_REWIND` = 0,4 s ≤ `DURATION` = 1 s ; entre deux relevés
   distants de plus de `MAX_GAP` = 0,25 s, le plus proche est pris au lieu d'une ligne droite). Un historique par `Model` (joueurs et bots, vide à
   chaque réapparition), supprimé à `Destroying` du personnage (mort, départ, bot retiré). Point d'entrée pour #174 et
   #176 : `CharacterSync.positionAt(char, t)` (nil sans historique). Depuis #213, chaque relevé garde aussi la **pose** :
   cap (`yaw`, rad, interpolé par le plus court chemin) et accroupi (pris au relevé le plus proche) ; `positionAt` rend
   `(position, cap, accroupi)`. L'accroupi vient du client (4e argument de `CharacterSync`, `CrouchSystem.isCrouching`),
   les bots sont toujours debout. Tests : `tests/specs/PositionHistory.spec.luau`.
   Le tireur voyait la cible à `shotTime - INTERP_DELAY` (`CharacterSyncRules.INTERP_DELAY`, 0,1 s) ; ce
   temps est borné à `[now - 0,4 s, now]` pour qu'un client ne puisse pas réclamer une position ancienne.
3. Origine : à moins de `5 + vitesse du tireur × 0,1` studs de la position du tireur à `shotTime` (il est en avance
   sur le serveur de sa propre latence, et peut aller à 200 studs/s en surf).
4. Direction : le rayon `origin + direction × t` passe à moins de `rayon de la zone + tolérance` de la position
   rembobinée de la partie annoncée (tête : sphère sur la tête rembobinée ; corps : capsule autour de la racine).
   Les offsets des parties sont pris sur le rig serveur, la tolérance couvre l'accroupi et l'interpolation.
5. Ligne de vue : raycast serveur de `origin` à `hitPos` limité à la géométrie de la map (`Workspace.Maps`, en
   inclusion), qui ignore donc les personnages et les objets mobiles, comme conseillé sur le DevForum
   ([Shooting backend validation](https://devforum.roblox.com/t/shooting-backend-validation-inaccuracies/4633077)).
   Un obstacle = tir refusé. Si la pénétration est implémentée un jour (`Penetration` de l'AWP dans `WeaponConfig.luau`, TODO), ce test
   devra en tenir compte.
6. Distance : `|hitPos - origin|` ≤ portée de l'arme.

Modèle : [RollbackHitbox](https://devforum.roblox.com/t/rollbackhitbox-server-authoritative-lag-compensation-for-roblox-shooters-open-source/4553295)
(rembobinage borné à 0,5 s, interpolation entre deux relevés). Limite connue : le client peut mentir sur `shotTime`
dans la borne de rembobinage, d'où la borne courte
([Making exploiter-proof guns](https://devforum.roblox.com/t/making-exploiter-proof-guns/235423)).

**Bots.** Leurs tirs sont des raycasts serveur depuis leurs yeux (tir du bot dans `BotArsenal.luau`) : rembobinage à 0, origine
et ligne de vue vraies par construction. Ils gardent le chemin sans `shot` (`participant.isBot` dans
`Validator.authorizeHitscan`), couvert par le test « ne refuse aucun tir de bot, tous contrôles bloquants »
(`tests/specs/Validator.spec.luau`).

**Coût.** Serveur : 1 raycast et quelques calculs vectoriels par tir accepté, négligeable à 41 coups/min. Mémoire :
35 relevés par personnage au plus. Réseau : ~60 octets de plus par tir. Complexité : moyenne (historique, tolérances à régler).

**Impact.** Supprime le silent aim, le tir à travers les murs et le hitbox expander. Reste l'aimbot (vraie visée).

**Faux positifs.** Gros ping, gigue, cible en surf rapide. Lancer d'abord la validation en mode « journal seul »
(tirs comptés comme refusables mais appliqués), mesurer, puis l'activer.

### Tolérances et modes (#174)

Le client envoie `HitscanDamage(targetChar, hitPart, origin, direction, hitPos, shotTime)`
(`src/client/systems/weapon/HitscanSystem.luau`) : origine et direction de la caméra, point d'impact de son raycast,
`workspace:GetServerTimeNow()` pris juste avant. La garde commune vérifie les types (Vector3 et nombre finis) ; un ancien
client à deux arguments est une violation forte `RemoteArgs`. Puis `Validator.authorizeHitscan` (après cible, arme,
partie et cadence, donc un tir refusé ne relance pas la cadence) applique les règles pures de `src/server/ShotRules.luau`.
Les accès au monde (horloge serveur, `CharacterSync.positionAt`, raycast, `CheatLog`) sont branchés par
`Validator.setShotWorld` dans `init.server.luau`, et simulés dans les tests.

| Contrôle | Règle (constantes de `ShotRules`) | Mode livré | Gravité |
|---|---|---|---|
| `shape` | Trois Vector3 finis et ≤ 1e5 (`MAX_COORD`), `|direction|` = 1 à `UNIT_TOLERANCE` (1e-3) près, `shotTime` fini | `block` | forte |
| `ping` | `now - shotTime` ≤ ping du tireur × `PING_FACTOR` (2) + `PING_MARGIN` (0,1 s), et ≥ `-CLOCK_TOLERANCE` (0,05 s) ; ping = `Player:GetNetworkPing()` (aller-retour). Ping inconnu : pas de borne (#214) | `log` | moyenne |
| `origin` | À moins de `ORIGIN_BASE` (5) + vitesse du tireur × `ORIGIN_SPEED_FACTOR` (0,1) studs de sa racine actuelle ou de sa position à `shotTime` (borné à `[now - 0,4 s, now]`). La caméra est à 2,5 studs au-dessus de la racine | `log` | moyenne |
| `direction` | Impact sur le rayon (à `HIT_ON_RAY` = 0,5 stud près, devant l'origine) ; rayon et impact à moins de rayon englobant de la partie (`Size.Magnitude / 2`) + `DIRECTION_BASE` (2) + vitesse de la cible × `DIRECTION_SPEED_FACTOR` (0,05) de la partie rembobinée. Partie rembobinée = racine à `shotTime - INTERP_DELAY` (borné à `[now - 0,4 s, now]`) + décalage de la partie pris sur le rig serveur dans le repère de sa racine, tourné au cap rembobiné et corrigé de l'accroupi (`posedPartCenter`, #213). Main ou bras (`*Hand`, `*LowerArm`, `*UpperArm`) : la partie est remplacée par la sphère d'allonge de son épaule (centre = articulation de l'épaule rembobinée, rayon = `ShotRules.limbRadius`, voir « Membres (#240) ») | `log` | moyenne |
| `distance` | `|hitPos - origin|` ≤ `WeaponConfig.HITSCAN_RANGE` (2 048, la portée du client) + `RANGE_TOLERANCE` (10) | `block` | moyenne |
| `lineOfSight` | Raycast serveur de `origin` jusqu'à `LINE_OF_SIGHT_END_MARGIN` (0,5 stud) avant `hitPos` (avant la partie rembobinée si l'impact n'est pas sur elle : un impact forgé près de l'origine ne raccourcit pas le segment), limité à `Workspace.Maps` (inclusion) : aucun obstacle | `log` | moyenne |

- Ancienne borne gardée en journal seul : un échec `origin` ou `lineOfSight` en mode `log` refuse quand même le tir si
  les racines sont à plus de `LOG_ONLY_RANGE` = 250 studs (`ShotRules.refuses`, détail « refusé : au-delà de 250
  studs »). Avant #174 tout tir au-delà était refusé : la phase de mesure n'ouvre donc pas le tir à travers les murs à
  2 000 studs. `direction` n'y est pas soumis (faux positif mesuré, voir plus bas) : un tir lointain légitime ne tombe
  pas dessus. Retirer un contrôle de `LOG_ONLY_RANGE_CHECKS` quand il passe en `block`, la liste devient alors inutile.
- Vitesses : estimées dans l'historique (#173) sur une fenêtre de `SPEED_WINDOW` = 0,1 s autour de l'instant voulu,
  décalée pour tenir dans la borne de rembobinage et divisée par sa vraie durée (`ShotRules.speedWindow`) ; 0 sans
  historique (cible `DebugDummy`, personnage tout juste apparu).
- Monde non branché (`Validator.setShotWorld` jamais appelé) : tout tir de joueur est refusé, avec un warn unique.
  Jamais de validation qui passe tout en silence.
- Cible vivante : vérifiée avant le rembobinage (`isValidTarget`) : `positionAt` répond encore entre la mort et la
  destruction du corps (`CORPSE_HANDOFF_DELAY`), un tir sur le corps est refusé avant.
- Journal : catégorie `Hitscan`, source `Hitscan:<contrôle>` (un contrôle ne compte qu'une violation forte par seconde
  pour le kick), détail suffixé « (journal seul) » en mode `log`. Le détail d'un échec `direction` donne la partie, la
  vitesse de la cible et le rembobinage, pour régler les tolérances.
- Relais aux autres clients (#156) : pas depuis `HitscanDamage`, qui n'arrive que pour une touche. Chaque tir, touché
  ou manqué, est annoncé par `ShotFired` juste avant (voir « Relais des tirs » dans « Remotes »).

**Mesure en Studio (#174, 2026-11-11).** 32 tirs honnêtes simulés depuis le client (raycast de `HitscanSystem` sur les
bots tels que le client les affiche, bhop jusqu'à 77 studs/s, 1 à 280 studs, Studio donc sans latence) : 1 violation
`direction` (rayon à 6,0 studs de la partie pour 5,0 permis), aucune autre. Tirs truqués : silent aim (`direction`),
tir à travers un mur à 414 studs (`lineOfSight`), direction non unitaire (`shape`, refusé) tous signalés. Après la
revue, 15 tirs honnêtes de plus (10 à 139 studs) sans aucune violation, et un impact forgé collé à l'origine vers une
cible masquée à 366 studs refusé (ligne de vue testée jusqu'à la partie, `LOG_ONLY_RANGE`). À refaire en jeu publié
avec du vrai ping avant de bloquer. Méthode : en Play, contexte `Client` d'`execute_luau`, rejouer le raycast de
`HitscanSystem` vers la tête d'un bot et appeler `HitscanDamage:FireServer` avec les six arguments (joueur rendu
résistant côté serveur, `DebugDummy` détruit), puis lire les lignes `[CheatLog]` (une par 2 s au plus par joueur).

**Piège des tests Lune.** Une Instance de `@lune/roblox` lue par une propriété (`part.Parent`, `FindFirstChild`)
est un nouvel userdata : `==` marche, mais elle ne retrouve pas une clé de table posée avec une autre référence au
même objet (`t[part.Parent]` vaut nil). Passer les personnages tels que le code les a obtenus (`resolveAttack` renvoie
`aChar`) plutôt que de les relire par `Parent`. Et une `Part` neuve n'a pas de `Position` par défaut sous Lune (erreur
à la lecture) : la poser dans les tests (`addPart` de `Validator.spec.luau`). Enfin `CFrame.lookAt(p, p + Vector3.new(0,
0, 1))` rend sous Lune un cap **-Z** (cas dégénéré, vu avec #213) : pour une orientation vers +Z, construire
`CFrame.new(p) * CFrame.Angles(0, yaw, 0)`.

**Limites connues de #174, traitées depuis** : pose non rembobinée (#213) et instant choisi par le client
(« backtrack », #214), voir « Instant annoncé et pose rembobinée » ci-dessous.

**Passer un contrôle en `block`.** 1. Laisser tourner en jeu publié en `log` (au moins quelques centaines de tirs, dont
du surf rapide et des joueurs à fort ping). 2. Lire les relevés agrégés `CheatLog` du webhook (#297, voir « Lire un
taux » dans « Journaliser ») : taux du contrôle (`Hitscan:direction : N / D touches`), additionné sur les relevés, et
dans les résumés des joueurs en cause le ping et l'écart au maximum permis donné par les détails. 3. Si besoin,
élargir la tolérance en cause (`ORIGIN_*`, `DIRECTION_*`) jusqu'à ne plus en avoir, sans dépasser ce qui laisse passer
un hitbox expander utile (rester sous ~2 fois le rayon d'une tête). 4. Passer le contrôle à `"block"` dans
`ShotRules.MODES`, mettre à jour le tableau ci-dessus et le test « livre origine, direction et ligne de vue en journal
seul » (`tests/specs/Validator.spec.luau`). Les tests « mode block » couvrent déjà le refus.

### Instant annoncé et pose rembobinée (#214, #213)

**Backtrack (#214).** Avant, `shotTime` était seulement ramené dans `[now - 0,4 s, now]` : un client modifié choisissait
librement où rembobiner la cible dans ces 0,4 s (viser là où elle **était**, quel que soit son ping). Désormais le
contrôle `ping` (`ShotRules.checkShotDelay`) borne `now - shotTime` (et `now - hitTime` pour la mêlée, voir M1) :

- **Source du ping : `Player:GetNetworkPing()`**, l'aller-retour réseau (s) mesuré par le moteur, hors traitement
  ([doc](https://create.roblox.com/docs/reference/engine/classes/Player#GetNetworkPing)), lu par `pingOf` du monde
  (`init.server.luau`, `pcall`, nil pour un bot). Écarté : un RTT mesuré par `CharacterSync`, qui n'existe pas (il
  faudrait un écho horodaté), et que le client pourrait gonfler en retardant sa réponse ; `GetNetworkPing` ne dépend
  d'aucun script du client.
- **Borne** : `ping × PING_FACTOR (2) + PING_MARGIN (0,1 s)` sur `now - shotTime`. `INTERP_DELAY` n'y figure pas :
  il ne retarde pas l'arrivée du tir, il s'ajoute après coup au rembobinage (`rewindTime` : `shotTime -
  INTERP_DELAY`) ; le rembobinage accepté vaut donc au plus `ping × 2 + 0,1 + INTERP_DELAY`, la formule du brief. Un tir honnête arrive un aller simple (≈ ping / 2)
  plus la frame du tir, le tick réseau du client et le Heartbeat du serveur après `shotTime`. Facteur 2 (relevé en
  revue) : `HitscanDamage` comme `MeleeDamage` sont fiables, un paquet perdu est renvoyé (un aller-retour de plus) ;
  un aller peut être plus lent que le retour ; et `GetNetworkPing` est une moyenne, dont des retours du DevForum disent
  qu'elle vaut la moitié de l'aller-retour (la doc dit l'aller-retour). La marge couvre les frames et l'erreur de
  `GetServerTimeNow`. Avance tolérée (`shotTime` dans le futur) : `CLOCK_TOLERANCE` (0,05 s). Avec 30 ms de ping, un
  tricheur ne remonte plus qu'à 0,16 s (+ `INTERP_DELAY`) au lieu de 0,4 s.
- **Journal seul** (`ping` = `"log"`). Faux positifs restants : pic de latence au-dessus de la moyenne, deux pertes de
  suite. À lire dans les résumés `CheatLog` avant de bloquer, en comparant `GetNetworkPing` au ping affiché (F3) en jeu
  publié pour trancher le facteur. Le rembobinage lui-même n'est pas raccourci à la borne en mode journal (sinon un faux positif
  déplacerait la cible, et la ligne de vue au-delà de `LOG_ONLY_RANGE` refuserait le tir) ; en `block`, le tir ou le
  coup est refusé. Piste au moment de bloquer (relevée en revue) : ramener plutôt le rembobinage à
  `max(shotTime, now - maxShotDelay(ping))`, ce qui retire le gain du backtrack sans refuser la touche. Détail :
  écart, borne, ping (« instant 0.40 s avant l'arrivée (max 0.16 s, ping 30 ms) »). Ping inconnu (`pingOf` absent ou en erreur) : pas de borne.
- **Bots** : pas concernés (tirs et coups serveur, sans `shot` ni `hitTime`).

**Pose (#213).** Avant, seule la racine était rembobinée : le décalage de la partie touchée était pris sur le rig
serveur à l'arrivée du tir, dans le cap actuel de la cible ; une cible qui tournait entre le tir et sa réception avait
ses membres déplacés (cause probable du faux positif `direction` mesuré par #174 sur une main, 6,0 studs pour 5,0).
Désormais l'historique garde le cap et l'accroupi, et `ShotRules.posedPartCenter` replace la partie : décalage dans le
repère de la racine du rig serveur, tourné au cap rembobiné, posé sur la racine rembobinée.

- **Accroupi : sans effet sur les parties aujourd'hui.** Le rig 3P ne s'accroupit pas (`CharacterConfig.ANIMATIONS` :
  `CROUCH_IDLE` et `CROUCH_WALK` vides, repli sur `IDLE` et `WALK`, #120) : un tireur voit sa cible debout, accroupie
  ou non. `ShotRules.CROUCH_DROP` (baisse des parties au-dessus de la racine quand l'accroupi diffère entre le tir et
  maintenant) vaut donc 0. **Piège** : publier une piste d'accroupi 3P demande de régler `CROUCH_DROP` sur la baisse de
  la tête qu'elle montre, sinon tous les tirs sur une cible qui vient de s'accroupir ou de se relever sortent en
  `direction` ; le test « CROUCH_DROP suit la piste 3P » (`tests/specs/ShotRules.spec.luau`) échoue tant que ce n'est
  pas fait. L'accroupi sert déjà à l'œil du tireur en mêlée (voir M1).
- **Coût.** Deux tableaux de plus par historique (35 caps, 35 booléens), un octet de plus par paquet `CharacterSync`.
  Repère `srv historique` de la sonde `PerfServer` (relevé de chaque position acceptée, joueurs et bots), mesuré en
  Studio (voir « Mesure en Studio (#213, #214) »).
- **Tolérances `DIRECTION_BASE` (2) et `DIRECTION_SPEED_FACTOR` (0,05) gardées** : voir la mesure ci-dessous ; Studio
  n'a ni latence ni gigue, et ce sont elles que ces marges couvrent ; les membres ont un défaut à part (tenue de
  l'arme). À resserrer d'après le journal du jeu publié (procédure « Passer un contrôle en `block` »).

**Mesure en Studio (#213, #214, 2026-11-11).** Studio sans latence (`GetNetworkPing` ≈ 0,5 ms, borne 0,10 s).

- `DebugPlaytest` AWP : PASS 9/9 (deux fois) ; M9Bayonet : PASS 9/9 (coup du vrai client, `hitTime` compris, validé
  sans ligne `[CheatLog]`). Un premier run AWP a échoué à `VIEWMODEL` pendant la construction du plan de navigation
  (19 s, frames lentes), puis est passé sans changement : hors périmètre.
- **Tirs honnêtes** (méthode de #174 : raycast de `HitscanSystem` depuis la caméra vers une partie d'un bot, tête,
  torse, mains, bras, jambes, `ShotFired` puis `HitscanDamage` au même `shotTime`, `Reload` tous les 5 tirs ; joueur
  à 1e7 PV, 3 bots en mouvement jusqu'à 61 studs/s, 4 à 171 studs) : 17 touches, **aucune violation `ping`**, aucune
  `origin`/`lineOfSight`/`shotLink`/`magazine`. **3 violations `direction`**, toutes sur un membre : main gauche
  (4,0 studs pour 3,9 permis ; 6,8 pour 6,2 à 61 studs/s) et avant-bras gauche (3,4 pour 3,4, bot immobile).
- **Cause, mesurée** : pas le cap ni l'accroupi. Dans le repère de la racine, la main gauche d'un bot est à
  (-3,0 ; -1,1 ; 0,1) sur le rig serveur (bras le long du corps) et à (0,1 ; 2,2 ; -3,3) chez le client : la tenue de
  l'arme du haut du corps (#107) est posée par chaque client (`WeaponThirdPersonView`, Motor6D locaux), jamais sur le
  rig serveur. Environ 4 studs d'écart sur une main, alors que la tête concorde (≈ 0,2 stud). C'est aussi la cause
  probable du faux positif de #174 (une main). **Fait (#240)** : les membres sont jugés dans la sphère d'allonge de
  leur épaule, voir « Membres (#240) » ; les tolérances `DIRECTION_*` n'ont pas été élargies (elles valent pour la
  tête).
- **Backtrack forgé** : un tir annoncé 0,35 s en arrière est signalé `ping : instant 0.38 s avant l'arrivée (max
  0.10 s, ping 0 ms) (journal seul)`.
- **Coups honnêtes** (méthode de #176 : boucle serveur qui envoie au client `aim` vers le bot le plus proche et
  `attack` à moins de 6,5 studs, `W` maintenu, 90 s, 5 bots) : 13 coups reçus, **aucune violation `Melee`**
  (`ping`, `orientation`, `meleeLineOfSight`). Une violation `Movement` « vol : 2,2 studs au-dessus de la trajectoire
  balistique » pendant la poursuite (caméra pilotée par `aim`, hors périmètre, voir D2).
- **Bots** : aucune ligne `[CheatLog]` (ils sont ignorés par le journal et ne passent pas par ces contrôles).
- **Coût** (`PerfServer`, 1 joueur, 5 bots, 80 s) : repère `srv historique` 0,011 à 0,018 ms par relevé, ~2,5 relevés
  par frame, soit 0,03 à 0,09 ms/frame (`srv bots` : 1,6 à 3 ms) ; pas de hausse notable.
- **Valeurs gardées** : `DIRECTION_BASE`, `DIRECTION_SPEED_FACTOR`, `MELEE_MAX_ANGLE`, `PING_*`. Studio n'a ni latence ni
  gigue, ce que couvrent ces marges, et les seuls faux positifs mesurés viennent de la tenue des bras, qu'une marge ne
  doit pas absorber. À revoir sur les résumés `CheatLog` du jeu publié.

### Membres (#240)

**Problème.** La tenue de l'arme du haut du corps (#107) est posée par chaque client (`WeaponThirdPersonView`, Motor6D
locaux), jamais sur le rig serveur : une main est à ~4 studs de là où le tireur la voit (mesure #213), d'où des
violations `direction` sur des tirs honnêtes visant un bras.

**Règle (piste A).** Pour une touche sur une main ou un bras (zone `ARMS` de `HitZones`, côté lu dans le nom :
`ShotRules.limbSide`), `Validator.validateShot`
remplace la partie par une sphère : centre = articulation de l'épaule du même côté sur le rig serveur
(`UpperTorso` + `C0` du Motor6D `*Shoulder`, `limbArm`), replacée dans la pose rembobinée comme toute partie
(`posedPartCenter`) ; rayon = `ShotRules.limbRadius` à la place du rayon englobant de la partie, la tolérance
(`DIRECTION_BASE` + vitesse × `DIRECTION_SPEED_FACTOR`) s'ajoute inchangée. Rayon dérivé du rig, rien en dur :

- `armReach` : plus grande distance entre l'épaule et un point du bras dans n'importe quelle pose, articulations du
  rig serveur (`C0`/`C1` de `*Shoulder`, `*Elbow`, `*Wrist`) et tailles des parties : épaule-coude + coude-poignet +
  coin de la main le plus loin du poignet (bras tendu), ou coin d'une partie plus haute s'il est plus loin. Borne
  exacte par l'inégalité triangulaire, vérifiée sur 500 poses au hasard (`tests/specs/ShotRules.spec.luau`).
- `holdShoulderShift` : la tenue tourne aussi la taille (`Waist` de la tenue `Rifle` : 40°), ce qui déplace
  l'épaule chez le client, alors que le centre de la sphère suit la taille du rig serveur (sa `Transform`, animée
  pour un bot). Plus grand écart entre l'épaule tournée par une tenue de `WeaponThirdPerson.POSES` et l'épaule du rig
  serveur, vue de l'articulation `Waist` (~0,7 stud pour une épaule à 1 stud de l'axe et une taille serveur au repos).
  Les rotations de taille des tenues sont lues une fois au chargement de `ShotRules`. Limite : pendant le fondu de la
  tenue (`HOLD_FADE_TIME`), le client part de **sa** taille animée, qui peut différer de celle du serveur (phase
  d'animation, joueur dont le serveur ne joue pas les pistes) ; l'écart restant est couvert par `DIRECTION_BASE`
  (aucun faux positif mesuré, voir la mesure), à surveiller dans les résumés `CheatLog` du jeu publié (détail « jugé
  dans l'allonge de l'épaule »).

Quand la sphère s'applique, le détail du journal indique « <partie> jugé dans l'allonge de l'épaule ». Rig incomplet
(Motor6D ou partie du bras absents, partie hors du personnage) : règle de la partie (rayon englobant de la partie
elle-même, plus petit que l'allonge), détail avec le nom seul. Les autres parties (tête, torse, jambes) gardent la
règle de la partie.

**Ce qu'un tricheur y gagne (limite connue).** Une touche annoncée sur un bras passe si le rayon passe à moins de
l'allonge + tolérance de l'épaule : la cible est en pratique grossie d'environ un bras autour du haut du corps
(~1,5 stud de plus que la sphère du torse), et les bras valent ×1 comme le torse (`HitZones`). Un tir truqué loin de
la cible (silent aim) reste signalé, la tête garde sa règle (pas de ×4 gagné). De même, la ligne de vue s'arrête à
l'impact annoncé s'il est dans la sphère : un impact forgé jusqu'à l'allonge devant l'épaule raccourcit le segment
d'autant (un mur collé à la cible peut être sauté, `lineOfSight` est en journal seul). Ces deux marges ne se
referment qu'en reproduisant la tenue côté serveur (piste B, #240 l'a écartée) ; la sphère est la plus petite qui
contienne le bras quels que soient les angles de ses articulations (rotations seules, comme les pistes et les tenues).

**Tests.** `tests/specs/ShotRules.spec.luau` (« membres jugés dans l'allonge de l'épaule ») : parties concernées,
allonge exacte et contenant le bras dans toute pose, déplacement de l'épaule par la taille, membre au bout de
l'allonge accepté, hors de l'allonge refusé, tolérances inchangées ; `tests/specs/Validator.spec.luau` (« membre
(#240) ») : main vue tenue acceptée en mode `block` (refusée avant #240), silent aim refusé, tête et main sans rig
inchangées.

**Mesure en Studio (#240, 2026-11-11).** Méthode de #174/#213 : en Play, contexte `Client`, raycast de `HitscanSystem`
depuis la caméra vers une partie de bras d'un bot telle que le client l'affiche (tenue comprise), `ShotFired` puis
`HitscanDamage` au même `shotTime` ; joueur et bots à 1e6 PV ou plus (sinon chaque touche tue le bot et la boucle attend
les réapparitions), `DebugDummy` détruit, 3 bots en mouvement (bhop jusqu'à 81 studs/s), 7 à 347 studs. Compteurs posés
côté `Server` (`OnServerEvent` de `HitscanDamage` : touche appliquée si les PV de la cible baissent, `MessageOut` pour
les lignes `[CheatLog]`). `DebugPlaytest` AWP : PASS 9/9.

- Rig du `StarterCharacter` (échelle ~1,59) : allonge `armReach` = 3,81 studs ; déplacement de l'épaule
  `holdShoulderShift` relevé de 0,56 à 1,71 stud selon la taille animée du bot, d'où un rayon de 4,4 à 5,5 studs
  (+ 2 + vitesse × 0,05 de tolérance).
- **Tirs honnêtes : 50 touches jugées, dont 42 sur un membre** (mains, avant-bras, bras, deux côtés) et 8 sur la
  tête ou le torse ; 45 appliquées, 5 refusées par `magazine` (voir plus bas) : **aucune violation `direction`**. À
  titre indicatif, 26 des 42 impacts sur un membre étaient à plus de l'ancienne limite (rayon de la partie + 2) de la
  position serveur actuelle de la partie, jusqu'à 4,4 studs au-delà.
  Autres lignes : 5 `magazine` (script de mesure qui n'attendait que 4,2 s après `Reload`, alors que le rechargement
  ne compte qu'à partir de la cadence du dernier tir : attendre 5,5 s) et 1 `ping` (`instant 0.11 s avant l'arrivée
  (max 0.10 s, ping 0 ms)`, frame lente de Studio, hors périmètre).
- **Tirs truqués** (silent aim sur un membre) : 4 rayons à 9 à 13 studs du torse vu, tous signalés (« rayon à 8.3 à
  11.5 studs de la partie (max 7.7 à 9.2) ; <membre> jugé dans l'allonge de l'épaule »), et un à 10 studs de la partie
  vue (10,4 pour 8,6). Trois rayons décalés de 6,5 à 8 studs de la partie **vue** sont passés : la partie tenue étant
  devant le corps, ce décalage les ramenait à moins de l'allonge + tolérance de l'épaule (bots à 20-36 studs/s, soit
  1 à 1,8 stud de tolérance de vitesse en plus) ; c'est la marge décrite plus haut.
- **Piège de la méthode** : `DebugPlaytest` range l'arme en fin de run ; sans arme en main, les touches sont refusées
  avant la validation, sans journal. Rééquiper (`Humanoid:EquipTool`) avant de tirer et vérifier que les touches sont
  appliquées. La manche dure 300 s : au-delà, le joueur repasse au menu et les bots disparaissent. Borner les boucles
  par `workspace:GetServerTimeNow()`, pas par `os.clock()` (temps CPU dans Studio, la boucle ne s'arrête pas).

### Distance (tranché, #174)

La portée du serveur est celle du client : `WeaponConfig.HITSCAN_RANGE` = 2 048 studs, tirée par `HitscanSystem` et
vérifiée par le contrôle `distance` (+ 10 studs). L'ancienne borne de 250 studs entre racines, qui refusait sans retour
un tir légitime lointain, devient pour les joueurs `Validator.MAX_HITSCAN_RANGE` ≈ 2 256 studs (portée +
`MAX_SPEED_SERVER` × `MAX_REWIND`, chemin possible de la cible pendant le rembobinage, + hauteur de caméra + 25 de
marge, calculé depuis ces constantes). Un échec `origin` ou `lineOfSight` au-delà de 250 studs reste refusé pendant la
mesure (`LOG_ONLY_RANGE`, voir plus haut). Les bots gardent 250 studs (`BOT_HITSCAN_RANGE`, tirs inchangés) : ils
visent à 240 au plus (`src/shared/BotConfig.luau`), mais leur rayon serveur porte à `WeaponConfig.HITSCAN_RANGE` = 2 048 studs (lu par `BotArsenal`)
et toucherait sinon un joueur lointain derrière une cible manquée.

### T2. Cadence, munitions, durée d'equip

**Cadence (fait).** Une seule cadence par arme et par participant, à 0,15 s près (`CADENCE_TOLERANCE`, `isCadenceReady`
et `recordAttack` de `Validator.luau`), remise à zéro à l'apparition (`Validator.forget` dans `onParticipantCharacter`). Un tir refusé ne relance pas la cadence : le spam est
sans effet.

**Munitions et durée d'equip (fait, #175).** Avant #175, le chargeur et l'equip n'étaient suivis que par le client
(`WeaponSystem`) : un client modifié ne rechargeait jamais (pas de pause de 3,7 s tous les 5 tirs) et tirait dès la
sortie de l'arme (AWP : 1,58 s gagnées). Désormais, pour les joueurs, `Validator.authorizeHitscan` et
`Validator.authorizeMelee` appliquent, après cible, arme et cadence (un refus ne relance donc pas la cadence), deux
contrôles de plus. Règles pures dans `src/server/ShotRules.luau` (`checkEquip`, `checkMagazine`, `startReload`,
`cancelReload`, `settleReload`), état (instants, compteurs) dans `Validator`, mêmes modes et même journal que T1.

| Contrôle | Règle | Mode livré | Gravité |
|---|---|---|---|
| `equip` | Touche acceptée à partir de `equippedAt + EquipTime - EQUIP_TOLERANCE` (0,2 s). `equippedAt` = arrivée de l'outil dans le personnage vue par le serveur (`ChildAdded` de `trackWeapon3P`, `Validator.noteEquip`). Outil en main sans arrivée notée : refusé (« sans equip vu par le serveur »), jamais accepté en silence. Tir et mêlée (catégorie `Melee` pour le couteau) | `block` | moyenne |
| `magazine` | Arme à `Magazine` : **tirs** comptés par participant et par arme depuis #215 (chaque `ShotFired` accepté, touché ou manqué, et chaque touche orpheline, voir « Tirs comptés et touches rattachées ») ; le `Magazine`+1e tir est refusé sans rechargement fini (`ShotFired` non relayé, touche refusée), et tout tir est refusé pendant un rechargement qui n'a pas encore duré `ReloadTime - RELOAD_TOLERANCE` (0,2 s). Début du rechargement : action `Reload` du remote `WeaponAction` (`Validator.noteReload`), lue avant les filtres de la pose 3P (intervalle de 0,05 s, modèle 3P attaché) qui pourraient écarter une action honnête | `block` | moyenne |

- **Borne d'equip.** Le client honnête n'est jamais prêt avant `EquipTime` (#184 : il attend le chargement de la piste
  puis sa durée), sauf piste plus courte qu'`EquipTime` : couteau 1 s / 1,3 = 0,769 s pour 0,77 (couvert par la
  tolérance). AWP : piste étirée à 1,58 s (`docs/animations.md`). **Raccourcir une piste `Equip` sous `EquipTime - 0,2`
  ferait refuser des tirs honnêtes** : baisser `EquipTime` avec.
- **Tolérances.** Equip et rechargement : 0,2 s chacun, la gigue entre deux paquets fiables (arrivée de l'outil ou action
  `Reload`, puis la touche) ; même ordre que `CADENCE_TOLERANCE` (0,15 s). Un tricheur gagne au plus 0,2 s sur 1,58 s
  (equip) ou 3,7 s (rechargement). Livrés en `block` sans phase de mesure : Studio n'a pas de latence, mais un paquet
  retardé de plus de 0,2 s ne coûte au pire qu'une touche, la première après l'equip ou le rechargement, sans
  cascade. Si les résumés `CheatLog` du jeu publié montrent des `equip`/`magazine` sur des joueurs honnêtes (détail :
  écart à la borne), élargir `EQUIP_TOLERANCE`/`RELOAD_TOLERANCE` ou repasser le contrôle en `"log"` dans `ShotRules.MODES`.
- **Rechargement.** Fini paresseusement à la touche suivante (ou au prochain `Reload`/changement d'arme) s'il a duré
  assez : le chargeur repart à zéro. Une touche **pendant** un rechargement inachevé est refusée, même chargeur non vide
  (le client ne tire pas en `RELOADING`) : sinon un client qui renvoie `Reload` toutes les 3,5 s en tirant à pleine
  cadence verrait son compteur remis à zéro sans jamais faire de pause (piste rejetée en revue : retrancher seulement
  les touches faites pendant le rechargement ne suffit pas). Un `Reload` pendant un rechargement inachevé le redémarre. Un `Reload` pendant l'equip ne compte qu'à partir de la fin de l'equip (le client
  ne peut pas recharger avant). Changement ou rangement d'arme (`ChildRemoved`, `Validator.noteUnequip`) : rechargement
  inachevé annulé, rechargement fini acquis, à `RELOAD_CANCEL_TOLERANCE` (1 s) près : sinon un `Reload` arrivé en
  retard, suivi d'un changement d'arme juste après la fin du rechargement côté client, ferait refuser tout le chargeur
  suivant. Un tricheur n'y gagne rien (ressortir l'AWP coûte 1,38 s d'equip au moins). Depuis #215, chaque tir est
  compté une fois : à son `ShotFired` accepté, ou à sa touche si elle est orpheline (`ShotFired` écarté par le relais) ;
  un `ShotFired` refusé n'est pas compté. Le compteur serveur reste ≤ celui du client, jamais plus strict.
- **Bots.** Exclus des deux contrôles (`attacker.isBot`) : `BotArsenal` fait déjà respecter equip, chargeur et
  rechargement, et ses tirs sont des raycasts serveur. Leur equip n'est pas noté (`trackWeapon3P`) : rien à retenir, et
  `Validator.forget` est appelé à l'apparition d'un bot et à son retrait (#218, voir « Retrait d'un participant »).
  Tests : 12 tirs de bot d'affilée et tir dès la sortie acceptés.
- **Ordre.** Les contrôles T1 (`validateShot`) passent avant equip et chargeur, et tous sont évalués : un tir refusé
  pour l'equip garde ses violations d'origine ou de ligne de vue au journal (phase de mesure de T1).
- **Réapparition et départ.** `Validator.forget` efface cadences, equip et chargeurs ; il précède le suivi des armes du
  nouveau personnage (`onParticipantCharacter`). Un outil qui entre ou sort de l'ancien corps (ragdoll) ne touche plus
  au participant.
- **Retrait d'un participant (#218).** `forgetCombatState` (`init.server.luau`) = `Validator.forget` +
  `ShotRelayRules.forget`, appelé à l'apparition, au départ d'un joueur, au retour au menu (`LeaveRound`) et, par
  `BotManager.removeAt` (dépendance `forget`), au retrait d'un bot : sans cela, chaque bot retiré laissait des entrées (clés fortes du Validator) qui
  grossissaient avec le va-et-vient de la population. `AimStats` et `CheatLog` ignorent les bots, `RoundManager` est
  déjà prévenu, l'historique de positions part avec le corps (`Destroying`) : rien d'autre à oublier. **Règle : toute
  nouvelle table indexée par participant (ou par bot) doit être vidée par `forgetCombatState`.** Contrôle : test
  `tests/specs/BotManager.spec.luau` (aucune entrée après retrait, y compris 20 va-et-vient), et la ligne
  `[Perf] SRV` de la sonde serveur (`anti-triche N suivi(s)`, `Validator.trackedCount`) qui doit retomber après
  `workspace:SetAttribute("DebugBots", 0)`.
- **Mesure en Studio (#175, 2026-11-11).** `DebugPlaytest` AWP et M9Bayonet : PASS 9/9. Client honnête (chemin réel
  `Tool:Activate`) : 5 touches, rechargement, 3 touches, aucune ligne `[CheatLog]`. Tir forgé envoyé 0,25 s après un
  ré-equip : refusé, journalisé `Hitscan … equip : touche 0.25 s après l'equip (min 1.38 s)`. Studio sans latence : à
  surveiller dans les résumés `CheatLog` du jeu publié (catégories `Hitscan`/`Melee`, contrôles `equip` et `magazine`).
  Méthode : `workspace:SetAttribute("DebugBots", 0)` d'abord (sinon les bots tuent le joueur et la réapparition remet
  le chargeur à zéro), un run `DebugPlaytest` AWP pour équiper et viser la cible, puis en contexte `Client` une boucle
  `tool:Activate()` lancée par `task.spawn` (appels MCP courts : un `execute_luau` qui attend longtemps a figé Studio
  des heures). À l'époque, espacer les clics de 2 s : `ShootAnimTime` (1,63 s) dépassait `FireDelay`, un clic à 1,6 s
  était ignoré par le client (état `FIRING`). Depuis #221, `ShootAnimTime` = `FireDelay` (invariant testé par
  `tests/specs/WeaponConfig.spec.luau`) : cadence client et serveur identiques.
- **Début du rechargement borné.** Un `Reload` ne compte qu'à partir de la fin de l'equip et de la cadence du dernier
  tir accepté de l'arme (`max(arrivée, equip + EquipTime - 0,2, dernier tir + FireDelay - 0,2)`, dernier tir = touche
  acceptée ou, depuis #215, tir compté même manqué : `Magazine.lastShotAt`) : le client ne peut pas recharger avant, un
  client modifié qui recharge dès son tir ne gagne pas `FireDelay` (1,46 s) sur la pause.

### Tirs comptés et touches rattachées (#215, #216)

**Avant.** Le chargeur serveur ne comptait que les touches : un client modifié pouvait faire entendre un tir par
cadence sans jamais recharger, ou rater 4 tirs puis toucher les 5 suivants. Le recul 3P (`WeaponAction` « Shoot ») était
posé sur la parole du client, sans cadence. `AimStats` rattachait une touche au **dernier** tir relayé de moins de
0,5 s : un tricheur qui ne déclarait que ses tirs réussis gonflait son taux de touches.

**Fait.** Registre des tirs récents par participant et par arme (`Validator`, règles pures dans
`src/server/ShotLinkRules.luau`), joueurs seulement :

1. **Annonce du tir.** Le client envoie `ShotFired(origin, direction, shotTime)` (`HitscanSystem.resolveHit`),
   `shotTime` = `workspace:GetServerTimeNow()` pris une fois par tir, le même que dans `HitscanDamage`.
2. **Tir compté.** `relayShot` (`init.server.luau`) : `Validator.isReadyToFire` (equip, chargeur), puis
   `ShotRelayRules.admit` (forme, origine, cadence), puis `Validator.noteShotFired` : le tir est compté dans le chargeur
   (`ShotRules.countShot`) et inscrit au registre. Un `ShotFired` refusé n'est ni relayé (son, recul 3P) ni compté,
   ni journalisé (sans dégâts, il ne rapporte rien).
3. **Touche rattachée.** `Validator.authorizeHitscan` cherche dans le registre le tir d'instant `shot.shotTime`
   (`ShotLinkRules.find`, à `LINK_TOLERANCE` près, encore libre) : rattachée, la touche ne passe pas le contrôle
   `magazine` (son tir l'a déjà passé) et n'est pas recomptée ; une seule touche par tir. Elle renvoie l'instant du tir
   rattaché, que `AimStats.noteHit` utilise (taux de touches, flick sur le cap figé à **ce** tir).
4. **Touche orpheline** (aucun tir libre de cet instant) : contrôle `shotLink`, puis contrôle `magazine` et comptage
   comme avant #215 (sinon un client qui tait ses `ShotFired` aurait un chargeur infini). Elle entre au registre : un
   `ShotFired` du même instant arrivé après elle y est rattaché, relayé même chargeur plein, et pas recompté.

| Contrôle | Règle (constantes de `ShotLinkRules`) | Mode livré | Gravité |
|---|---|---|---|
| `shotLink` | Touche rattachée à un `ShotFired` accepté, de même `shotTime` à `LINK_TOLERANCE` (1 ms) près, arrivé depuis moins de `MAX_AGE` (1 s), pas encore touché. Journalisé seulement si la touche passe tous les autres contrôles (un chargeur vide explique déjà le `ShotFired` écarté) ; catégorie `Hitscan`, source `Hitscan:shotLink` | `log` | faible |

- **Tolérance.** Le client envoie la même valeur dans les deux remotes, transmise en double : l'écart honnête est nul.
  1 ms couvre une conversion de flottant et reste 1 000 fois sous l'écart entre deux tirs acceptés (AWP : `FireDelay`
  - `CADENCE_TOLERANCE` = 1,31 s) : une touche ne se rattache jamais au tir voisin. `MAX_AGE` (1 s) : la touche part
  dans la même frame que son tir ; reste sous la cadence de l'AWP, donc un tir n'est pas gardé jusqu'au suivant.
  `MAX_ENTRIES` (16) borne la mémoire.
- **Ordre des remotes (vérifié).** La doc Roblox ([Remote events](https://create.roblox.com/docs/scripting/events/remote))
  garantit que les messages d'une connexion arrivent dans l'ordre d'envoi, y compris entre deux `RemoteEvent`
  différents, même retardés par la limite de débit ; l'ordre vaut au démarrage des handlers (aucun des deux ne yield
  avant d'avoir décidé). Une touche avant son `ShotFired` ne vient donc que d'un client modifié : pas de délai
  d'attente, elle est orpheline (journal), et son `ShotFired` tardif n'est pas recompté (test « HitscanDamage avant son
  `ShotFired` »). Ne vaut pas pour un `UnreliableRemoteEvent` ni une `RemoteFunction`.
- **Pourquoi `log`.** Un `ShotFired` honnête peut être écarté par le relais (cadence à 0,15 s près, deux tirs groupés
  par une coupure réseau ; origine à plus de 185 studs) : sa touche devient orpheline. Elle reste appliquée et comptée
  dans le chargeur, et `AimStats` l'exclut du taux de touches. Passer en `block` (procédure de T1) après lecture des
  résumés `CheatLog` : aucune violation `shotLink` chez les joueurs honnêtes.
- **Recul 3P.** Posé par `relayShot` (`WeaponThirdPerson.setAction(char, "Shoot")`) pour tout tir accepté, joueur ou
  bot, donc à la cadence de l'arme. Notre client n'envoie plus `WeaponAction` « Shoot » pour une arme à distance
  (`onToolActivated` de `WeaponSystem`) ; le serveur l'ignore s'il en reçoit un (`isMeleeTool`). Le couteau garde
  `WeaponAction` « Shoot » : un coup manqué n'a pas de remote de tir, sa pose 3P ne peut venir que de là (sans enjeu :
  pas de son ni de dégâts). La garde accepte toujours « Shoot » (couteau).
- **Bots.** Même point d'entrée (`relayShot` depuis `BotArsenal.fire`, `onFire`), jamais refusés : `isReadyToFire` est
  vrai pour un bot armé, `noteShotFired` ne compte rien (`BotArsenal` tient son chargeur), leurs touches gardent le
  chemin sans `shot` (pas de rattachement). Le recul 3P d'un tir de bot vient du relais ; `BotArsenal.fire` le pose lui-même si le
  relais écarte le tir (`onFire` renvoie false), le rayon partant quand même.
- **Oubli.** Le registre est vidé par `Validator.forget` (réapparition, départ, retrait d'un bot : règle de #218) et
  compté par `Validator.trackedCount`.
- **Limite connue.** `shotTime` est choisi par le client. Celui d'une touche est borné par le ping depuis #214
  (contrôle `ping` de T1, journal seul) ; celui de `ShotFired` ne l'est pas (le relais ne rembobine rien). Un tricheur
  qui annonce un autre instant, le même dans les deux remotes, ne gagne rien sur le chargeur ni sur le taux de
  touches.
- **Tests.** `tests/specs/ShotLinkRules.spec.luau` (tolérance, tir voisin, une touche par tir, âge, taille, touche
  avant son tir) ; « tirs comptés et touches rattachées » de `tests/specs/Validator.spec.luau` (6e `ShotFired` refusé
  après 4 tirs manqués, rechargement puis tir, bon tir, orpheline en `log` et en `block`, deux touches pour un tir,
  ordre inversé, rechargement borné par un tir manqué, bots) ; `tests/specs/AimStats.spec.luau` (rattachement,
  orphelines comptées comme un tir qui touche, violation au-delà du seuil #246, flick sur le bon tir). Dans
  `Validator.spec.luau`, l'enveloppe `authorizeHitscan` envoie
  d'abord le `ShotFired` de notre client (paramètre `noShotFired` pour une touche seule).
- **Mesure en Studio (2026-11-11).** `DebugPlaytest` AWP et M9Bayonet : PASS 9/9. Client honnête à l'AWP (chemin réel
  `Tool:Activate`, un clic toutes les 2 s, `DebugDummy` levé de 80 studs un tir sur trois pour des tirs manqués) :
  12 `ShotFired` reçus et relayés (12 reculs 3P posés), 9 touches, 2 rechargements, aucune ligne `[CheatLog]` ;
  relevé `[AimStats] … tirs 14 but 10 (71%) touches 10 orph 0` (toutes les touches rattachées). `DebugBots` 3 pendant
  plus d'une minute (joueur sous `ForceField` invisible) : 18 tirs de bots relayés au client, recul 3P vu sur le modèle
  3P du bot (C0 du grip décalé 0,05 s après le relais) pour 15 d'entre eux (les autres : tir suivi aussitôt du
  rechargement, l'attribut est déjà passé à `Reload`), aucune ligne `[CheatLog]`. Méthode : compteurs posés par
  `execute_luau` (contexte `Server` : `OnServerEvent` de `ShotFired`/`HitscanDamage`, attribut `Weapon3PActionAt` du
  joueur ; contexte `Client` : `ShotFired.OnClientEvent`), boucles lancées par `task.spawn`. Studio sans latence : à
  surveiller dans les résumés `CheatLog` du jeu publié (contrôle `shotLink`).

## Mêlée

### M1. Orientation et ligne de vue

**Avant #176.** #47 a réglé dégâts, cadence et arme en main (`Validator.authorizeMelee`). Restaient : la distance est
mesurée entre racines (10 studs, `MAX_MELEE_RANGE` de `Validator.luau`, alors que l'arme porte à 7,5, `MeleeRange` dans `WeaponConfig.luau`), sans regarder la
direction du tireur ni les obstacles.

**Risque.** « Kill aura » : un client modifié frappe toute cible à 10 studs, dans n'importe quelle direction, à travers
un mur fin. Frappée dans le dos, elle prend 50 × 2 = 100 dégâts (`Damage` du M9 Bayonet dans `WeaponConfig.luau`, `HitZones.Multipliers`), soit un mort. Couplé à
la téléportation (D1), c'est un kill par 0,4 s sur toute la map.

**Parade.** (1) Angle entre le cap du tireur (yaw de sa racine serveur, mis à jour à 20 Hz) et la direction vers la
cible ≤ ~70° dans le plan horizontal (le pitch n'est pas connu) ; (2) raycast serveur racine → racine limité à la map ;
(3) rembobinage de la cible avec l'historique de T1. Bots : orientation vraie par construction (`BotMotion`), test à
ajouter. Coût : un produit scalaire et un raycast par coup accepté.

**Impact.** Supprime le kill aura ; la portée reste un peu généreuse (tolérance latence), acceptable.

**Fait (#176).** `Validator.authorizeMelee` applique aux joueurs, après cible, arme, portée de 10 studs et cadence (un
refus ne relance donc pas la cadence), deux contrôles de plus, avant l'equip (#175), tous évalués comme pour le tir.
Règles pures dans `src/server/ShotRules.luau`, accès au monde par `Validator.setShotWorld` (même horloge, même
historique `positionAt`, même raycast limité à `Workspace.Maps`, même journal que T1), catégorie `Melee`, source
`Melee:<contrôle>`.

| Contrôle | Règle (constantes de `ShotRules`) | Mode livré | Gravité |
|---|---|---|---|
| `ping` | `now - hitTime` borné par le ping comme `shotTime` (#214, voir T1 « Instant annoncé et pose rembobinée ») | `log` | moyenne |
| `orientation` | Angle horizontal entre le cap de la racine serveur du tireur (`LookVector`, relayé à 20 Hz, celui de sa caméra : `MovementController`) et la direction de la racine de la cible ≤ `MELEE_MAX_ANGLE` (70°) + `asin(MELEE_BODY_RADIUS / distance)` (2 studs : 15° à 7,5 studs, 90° au contact ; distance 3D, sinon une cible à 2,5 studs à l'horizontale mais 6 studs plus bas ouvrait 124°). Cible à l'aplomb (à moins de `MELEE_BODY_RADIUS` à l'horizontale) et à plus de `MELEE_BODY_RADIUS` au-dessus ou au-dessous : acceptée quel que soit le cap (regard vers le bas, tireur sur sa tête) ; à même hauteur, l'angle permis s'applique, un coup dans le dos reste refusé | `log` | moyenne |
| `meleeLineOfSight` | Raycast sur la map de la racine du tireur à celle de la cible, ou de son œil (`CAM_HEIGHT_STAND`) à la tête de la cible (décalage de `Head` sur le rig serveur, 1,5 stud à défaut : pas au-dessus de la tête, sinon un mur juste plus haut que la cible laisserait passer), pour un obstacle bas par-dessus lequel la caméra frappe ; jusqu'à `LINE_OF_SIGHT_END_MARGIN` avant : un segment dégagé suffit | `log` | moyenne |

- **Instant du coup (#214).** Avant #214, `MeleeDamage` n'envoyait pas d'instant : la cible était cherchée à `now`,
  `now - 0,05`, … `now - MAX_REWIND` (9 positions), et le coup passait si **une** position était devant le cap. Un
  tricheur qui fixait une direction touchait donc toute cible dont le sillage des 0,4 dernières secondes avait croisé
  son cône. Désormais le client envoie `hitTime` (`workspace:GetServerTimeNow()` au raycast de `MeleeHitDetection`,
  comme `shotTime`), la garde l'exige (nombre fini ; sans lui, contrôle `shape`, refusé) et le serveur rembobine la
  cible à **cet** instant seul (`ShotRules.rewindTime` : `hitTime - INTERP_DELAY`, borné à `[now - 0,4 s, now]`).
  `hitTime` est borné par le ping comme `shotTime` (contrôle `ping`, catégorie `Melee`, journal seul). Position
  rembobinée à plus de 10 studs du tireur (`MAX_MELEE_RANGE`) : position actuelle à la place (piège relevé en revue de
  #176 : une cible en surf, à découvert à 30 studs il y a 0,3 s, ne se frappe pas maintenant à 5 studs derrière un
  mur). Deux raycasts au plus par coup (racine à racine, œil à tête). Sans historique (`DebugDummy`), position
  actuelle.
- **Pose (#213).** La tête de la cible (segment « œil à tête ») est replacée dans sa pose rembobinée
  (`posedPartCenter`, comme pour le tir) ; l'œil du tireur suit son accroupi : `CAM_HEIGHT_CROUCH` (1,2) au lieu de
  `CAM_HEIGHT_STAND` (2,5) s'il est accroupi sur tous ses relevés des `CROUCH_EYE_SETTLE` dernières secondes
  (≈ 0,21 s, temps pour que la caméra, qui descend en approche exponentielle à `CAM_LERP_SPEED`, arrive à 0,1 stud de
  sa hauteur accroupie ; `eyeSettledCrouched` de `Validator.luau`), debout sinon (piège relevé en revue : juste après
  l'appui, la caméra est encore haute). Un obstacle bas que la caméra debout survolait bloque désormais un tireur
  accroupi.
- **Tolérance d'angle.** La géométrie seule demande `asin(2 / 7,5)` ≈ 15° à portée : les 70° restants couvrent le
  retard du cap relayé (un paquet de position toutes les 50 ms, plus la gigue), soit ~1 000°/s de rotation. Un coup
  dans le dos (180°) reste refusé même collé (160° permis au plus). Le cap du **tireur** reste le dernier reçu, pas
  celui de son historique à `hitTime` : un relevé est horodaté à son arrivée, donc le cap de `hitTime` n'arrive au
  mieux qu'avec le coup. Le dernier paquet de position (non fiable, 20 Hz) est parti au plus 50 ms avant le coup, ou
  plus tôt s'il s'est perdu : c'est ce retard que couvre la tolérance. À l'inverse, un paquet parti **après** le coup
  peut arriver avant lui (non fiable contre fiable, sans ordre garanti) : le cap reçu en dernier est alors déjà tourné.
  Les caps de l'historique un et deux paquets avant l'arrivée du coup (`MELEE_YAW_PACKETS`, relevé en revue) sont donc
  testés aussi ; un seul devant la cible suffit, un cap plus ancien ne compte pas. Depuis #214, la cible n'est plus cherchée sur
  9 instants : une cible en mouvement est prise exactement où le tireur la voyait, mais rien n'absorbe plus un cap
  très en retard. **Valeur gardée (#213)** : la mesure en Studio n'a pas de latence (voir « Mesure en
  Studio (#213, #214) »), elle ne dit rien du retard du cap ; à resserrer seulement d'après le journal du jeu publié. Le
  cap serveur n'avance qu'avec les paquets de position acceptés : un joueur dont le mouvement est refusé (D1) ou dont
  les paquets (non fiables) se perdent garde un cap ancien et peut être journalisé à tort ; le détail du journal permet
  de les écarter.
- **Position du tireur.** Racine serveur actuelle, sans rembobinage : le client est en avance de sa latence, l'écart
  est couvert par la tolérance d'angle et la portée de 10 studs (contre 7,5 côté client).
- **Backstab.** Toujours jugé sur les positions et le cap **actuels** de la cible (`tRoot.CFrame`), pas sur sa pose
  rembobinée : la juger à `hitTime` changerait les dégâts vus par les joueurs (décision de gameplay hors #213).
- **Cible vivante.** Vérifiée avant (`isValidTarget`) : un corps dont l'historique répond encore est refusé.
- **Bots.** Exclus (`attacker.isBot`) : ils frappent depuis le serveur, tournés vers leur cible (`BotMotion`). Test :
  coup de bot dos à la cible et à travers un mur accepté, rien au journal, contrôles bloquants.
- **Monde non branché.** Comme pour le tir : coups de mêlée de joueurs refusés, warn unique.
- **Tests.** `tests/specs/ShotRules.spec.luau` (angle, angle permis, positions, segments, modes) et
  `tests/specs/Validator.spec.luau` (« orientation et ligne de vue de la mêlée » : dos et mur journalisés en `log`,
  refusés en `block` ; cible qui contourne, tireur qui tourne, cible collée, obstacle bas acceptés ; rembobinage
  borné ; bots).

**Mesure en Studio (#176, 2026-11-11).** `DebugPlaytest` M9Bayonet : PASS 9/9 (cible `DebugDummy` sans historique).
Coups honnêtes sur des bots en mouvement (chemin réel `Tool:Activate`, caméra qui suit le bot) : 11 coups reçus,
angle au cap serveur de 0 à 63°, distance des racines de 4,3 à 10,6 studs, aucune ligne `[CheatLog]` ; 10 appliqués,
le 11e refusé par la portée de 10 studs **déjà en place** (racines actuelles, bot qui s'éloigne ; piste hors
périmètre de #176 : mesurer aussi la portée sur les positions rembobinées). Studio sans latence : à surveiller dans les résumés `CheatLog` du jeu publié. Méthode, les bots ne
venant pas d'eux-mêmes au contact : joueur protégé par un `ForceField` invisible, boucle serveur (`task.spawn` dans
`execute_luau`, contexte `Server`) qui envoie au client par le remote `DebugPlaytest` la commande `aim` vers la racine
du bot le plus proche toutes les 0,05 s et `attack` (`{ tool = "M9Bayonet" }`) quand il est à moins de 6,5 studs,
et `W` maintenu par `user_keyboard_input` (tranches de 10 s) ; compter les coups par une connexion de plus sur
`MeleeDamage.OnServerEvent`. Un `require` depuis `execute_luau` charge une autre instance des modules du jeu (registre
`Participants` vide) : passer par les remotes et les attributs, pas par les modules.

**Passer en `block`.** Même procédure que T1 (« Tolérances et modes ») : en jeu publié, lire dans les résumés
`CheatLog` les violations `Melee` `orientation`/`meleeLineOfSight` de joueurs honnêtes (le détail donne l'angle, le
maximum permis, la distance et le rembobinage de la position la plus proche), élargir `MELEE_MAX_ANGLE` ou
`MELEE_BODY_RADIUS` si besoin, puis passer le contrôle à `"block"` dans `ShotRules.MODES` et mettre à jour ce tableau
et le test « livre orientation et ligne de vue de la mêlée en journal seul » (`ShotRules.spec.luau`). Les tests en
mode `block` (`Validator.spec.luau`) couvrent déjà le refus.

## Déplacement

Le mouvement est calculé par le client sur une racine ancrée ; il envoie position et cap à 20 Hz, le serveur valide puis
pose la racine et relaie (commentaire d'en-tête de `src/server/CharacterSync.luau`). Le serveur n'a aucune physique à lui : il ne peut que
juger les positions reçues.

**Contrainte surf et bhop.** Les vitesses légitimes sont grandes : 90 studs/s mesurés en bhop de bots
(`docs/bots.md:80`), 200 studs/s et plus en surf (`docs/performance.md:98`). Le gain de vitesse en l'air vient de l'air
strafe, pas d'une limite fixe : une borne de vitesse seule ne peut pas être serrée. Depuis #212, le client plafonne donc
sa vitesse comme Source, et le serveur se place juste au-dessus (voir « Plafond du client et limite du serveur » en
D1). S'y ajoutent les boosts de la map (`Maps.Map.Boosts`, geysers et lanceurs à vitesse imposée, portiques qui
ajoutent `Boost` studs/s, `docs/maps.md:251-254`), détectés et appliqués par le client seul (commentaire d'en-tête de
`src/client/systems/movement/BoostSystem.luau`) : une parade qui juge la vitesse ou la gravité doit les connaître
(règles pures dans `src/shared/MapRules.luau`, réutilisables par le serveur). Un geyser ou un lanceur impose sa vitesse
(`Velocity`) et le lancement depuis le soleil prend l'attribut `Speed`, mais tous deux sont ramenés à
`MAX_SPEED_SERVER` (450 studs/s, norme 3D) au plus (`MapRules.imposedVelocity`, `SpawnLaunch.velocity`, #212), sans
avertissement, puis le client plafonne l'horizontale à 420 : une map ne peut pas, par erreur, faire refuser un joueur
par le seau de D1. Un lanceur réglé au-delà (ou à plus de 420 horizontaux) n'atteint plus son point de chute calculé.
Le serveur borne la vitesse verticale d'un geyser de la même façon pour l'enveloppe du vol (D2).

### D1. Vitesse et téléportation (fait, #172)

**Avant #172, failles de la règle** `|new - last| ≤ 300 × max(écoulé, 0,05) + 5`.

1. Le minimum de 0,05 s et la marge de 5 studs s'appliquent à **chaque** paquet, et le serveur accepte un paquet toutes
   les 0,025 s : 20 studs par paquet, soit ~400 studs/s à 20 Hz et ~800 studs/s à 40 Hz.
2. Un paquet refusé ne met à jour ni `lastPos` ni `lastAt` : après `T` secondes de silence
   ou de refus, le serveur accepte un saut de `300 × T + 5` studs. Il suffit de se taire une seconde pour se téléporter
   de 300 studs, dans n'importe quelle direction, y compris dans le dos d'une cible (M1).
3. Le refus ne corrigeait pas le client : client et serveur divergent, ce qui ne pénalise que le
   joueur honnête qui a laggé.

**Risque.** Critique : vitesse plus que doublée en continu, et téléportation n'importe où en se taisant. La position
acceptée est celle que le `Validator` utilise pour la portée (`resolveAttack` de `Validator.luau`) : se téléporter dans le dos d'une
cible rend le kill aura (M1) praticable sur toute la map.

**Parade en place (#172).**

1. **Seau qui fuit** (leaky bucket, conseillé par la doc Roblox,
   [Movement validation](https://create.roblox.com/docs/scripting/security/network-ownership)), règle pure
   `CharacterSyncRules.tryMove` : chaque paquet a pour budget `stored + MAX_SPEED_SERVER × min(écoulé, MAX_SILENCE)`,
   `écoulé` = temps depuis le paquet précédent jugé (accepté **ou refusé**). Un déplacement accepté consomme son budget,
   le reste est gardé dans `stored`, plafonné à `MAX_DELTA_POS`. Un refus ne consomme rien, mais son temps est compté :
   se taire ou se faire refuser n'accumule rien. Constantes (`src/shared/MovementConfig.luau`) :
   `MAX_SPEED_SERVER` = 450 studs/s, `MAX_DELTA_POS` = 112,5 studs (0,25 s mises de côté, pour la gigue et les paquets
   groupés), `MAX_SILENCE` = 0,5 s (valeurs de #212, voir plus bas ; 300 et 75 avant). Bornes : 450 studs/s soutenus
   quel que soit le débit d'envoi, saut d'un paquet ≤ 112,5 + 225 = 337,5 studs après n'importe quel silence. Le délai minimal de 0,025 s entre deux paquets a été retiré :
   des paquets groupés passent tous, chacun consomme le seau, le débit reste borné par la garde commune (40/s).
2. **Refus** : journalisé `CheatLog` (`Movement`, gravité moyenne : un vrai lag peut en produire un), puis **correction**
   : le serveur envoie au client, par le remote fiable `MovementCorrection`, `(personnage, dernière position acceptée,
   numéro)`. `MovementController` s'y replace, vitesse nulle, sans interpolation, état recalculé au tick suivant. Le
   client joint à chaque paquet `CharacterSync` le numéro de la dernière correction appliquée ; tant qu'il est
   inférieur à la correction en attente, ses paquets (partis d'une position déjà refusée) sont ignorés sans être jugés
   ni journalisés : **pas de boucle de corrections**. Le numéro exigé reste en place après l'accusé : un paquet plus
   ancien arrivé en retard (non fiable, donc parfois en désordre) est aussi ignoré. Correction renvoyée au premier
   paquet périmé reçu plus d'1 s après le dernier envoi (filet). Un numéro forgé ne fait que reprendre la validation : il ne donne aucun budget ; un client
   qui n'accuse jamais réception reste figé côté serveur à sa dernière position acceptée.
   **Mode journal seul** : `CharacterSyncRules.ENFORCE_MOVEMENT = false` garde le journal mais applique le
   déplacement refusé (seau vidé), sans correction. À utiliser si des joueurs honnêtes sont corrigés en surf.
3. Apparitions et lancement depuis le soleil : la piste (et le seau, plein) repart de la racine posée par
   `SpawnManager` à chaque nouveau personnage ; tout futur téléport de gameplay devra passer par le serveur et
   réinitialiser la piste.
4. Option non faite : borne d'accélération plutôt que de vitesse (la vitesse ne peut croître que de `AIR_ACCEL`/gravité
   × dt), plus serrée mais délicate avec les rampes ; à n'envisager qu'après mesure.

**Plafond du client et limite du serveur (#212).** Avant #212, rien ne plafonnait la vitesse horizontale du client,
et un surfeur honnête au-delà de 300 studs/s (vitesse 3D) aurait été corrigé. Faute de map de surf pour mesurer un bon
surfeur, la règle de Source a été reprise :

- **Client** : `MAX_HORIZONTAL_SPEED` = 420 studs/s, soit `sv_maxvelocity` (3 500 unités/s) × 0,12 (ratio unités
  Source → studs déjà pris pour `RUN_SPEED`). Appliqué dans `CharacterMotor.move` (`PhysicsUtils.clampHorizontal`)
  avant et après le déplacement, au sol, en l'air et en surf, pour le joueur comme pour les bots. Sous 420, rien ne
  change (vecteur rendu tel quel). En surf, tout le vecteur est réduit (pas seulement l'horizontale) : réduire la
  seule horizontale sortirait la vitesse du plan de la rampe (vers la rampe en descente, ce qui freine au
  ClipVelocity suivant ; vers le vide en montée, ce qui peut décrocher). Source plafonne chaque axe ; ici seule la norme horizontale l'est, la verticale
  reste bornée par `MAX_FALL_SPEED` (130) hors surf.
- **Serveur** : `MAX_SPEED_SERVER` = ⌈√(420² + 130²)⌉ + 10 = 450 studs/s, calculé dans `MovementConfig` depuis les
  deux plafonds du client, et `MAX_DELTA_POS` = 0,25 × 450 = 112,5 studs. Saut d'un paquet après un silence ≤ 112,5
  + 225 = 337,5 studs (au lieu de 225). Un tricheur reste à 450 studs/s au plus.
- **Reste non couvert** : sur une rampe de surf, la chute n'est pas plafonnée (comme Source). À 420 studs/s
  horizontaux, une glissade qui descend à plus de ~160 studs/s dépasse 450 en 3D ; le seau (112,5 studs) absorbe
  l'excédent quelques secondes (à 250 studs/s de descente, ~2,9 s, soit ~700 studs de dénivelé), ce qu'aucune map
  actuelle ne permet. Un joueur honnête corrigé en surf : repli `CharacterSyncRules.ENFORCE_MOVEMENT = false`
  (journal seul), puis mesurer avant de relever la marge.
- **Consommateurs de `MAX_SPEED_SERVER`** élargis volontairement (une cible honnête peut aller à 450 studs/s pendant
  le rembobinage) : `ShotRelayRules.ORIGIN_MAX` 125 → 185 studs (son du tir seulement), `Validator.MAX_HITSCAN_RANGE`
  2 196 → 2 256 studs, majoration de la vitesse de décollage de D2 (`takeoffVy`) 338 → 488 studs/s, plafond des
  vitesses imposées (`MapRules.imposedVelocity`, `SpawnLaunch.velocity`) aucun → 450 (norme 3D ; l'horizontale
  repasse ensuite à 420 au tick suivant). Les portiques (`MapRules.velocityAfter`) plafonnent à
  `MAX_HORIZONTAL_SPEED` (420) au lieu de 300.

**Pièges.** Une correction ne doit **jamais** remplir le seau : un tricheur qui enchaîne refus et numéro forgé
gagnerait un seau plein à chaque cycle (40 cycles/s). Le numéro de correction est croissant sur toute la session du
joueur (pas remis à zéro à la réapparition) pour qu'un ancien accusé ne valide pas une correction récente.

**Réutiliser.** Une nouvelle règle de déplacement se branche dans `onClientPosition`, après le seau, et appelle
`refuse(player, track, détail, now)` (`src/server/CharacterSync.luau`) : journal et correction compris. C'est ce que
fait D2 (#177, `judgeGuard`) ; `refuse` repart aussi l'enveloppe du vol de la position de correction.

**Bots.** Non concernés : leurs positions viennent du serveur (`relayBot`), qui ne passe pas par le seau.

**Vérifié.** Tests `tests/specs/CharacterSyncRules.spec.luau` (limite dérivée des plafonds du client, 420 studs/s
horizontaux et chute à `MAX_FALL_SPEED` avec 80 ms de gigue acceptés, 520 studs/s corrigés, 300 studs/s soutenus, surf
à 220 studs/s avec 80 ms de gigue, paquets groupés, rafale à 40 Hz, tricheur borné à 20 et 40 Hz, silences, suite de refus, reprise après
correction). En jeu (Studio, latence nulle) : bhop sans refus ; un paquet forgé de 400 studs pendant une course est
refusé une fois, journalisé, corrigé, et la course reprend sans seconde correction. #212 (Studio) : un lanceur
temporaire imposant 600 studs/s donne au plus 420 horizontaux et 426 en 3D vus par le serveur, sans refus ni
correction ; bhop sans refus. Reste à observer en jeu publié :
surf rapide avec un vrai ping (journal `Movement` des joueurs honnêtes).

**Impact.** Ramène le tricheur à 450 studs/s au plus et supprime la téléportation, qui est l'aide principale du kill
aura et de l'ESP actif.

### D2. Vol et noclip (fait en journal seul, #177)

**Avant #177.** Une position était acceptée si elle respectait la distance, qu'elle soit en l'air depuis 30 s ou de
l'autre côté d'un mur. La mort par chute (`KillZone`) ne testait que les positions acceptées : un client qui flotte
au-dessus du vide, ou qui n'envoie jamais de position sous `KillHeight`, ne mourait pas.

**Risque.** Moyen : rester en l'air hors d'atteinte, se cacher dans un mur, ne jamais mourir de chute.

**Parade en place.** Règles pures dans `src/shared/MovementGuardRules.luau` (testées sous Lune) ; la géométrie est
fournie par `CharacterSync` (`buildGeometry`) : rayons et requêtes limités à la map jouée (`Include`) et à ses pièces
qui collisionnent (`RespectCanCollide` : décor fantôme, volumes d'échelle et de boost exclus). Une position acceptée
par le seau (D1) passe par `MovementGuardRules.judge` (`judgeGuard`, `src/server/CharacterSync.luau`).

1. **Noclip** (`crossesWall`) : raycast `lastPos → newPos` (centre du personnage, qui chez un client honnête reste à
   `CHAR_RADIUS` des parois). Touché : quatre détours sont essayés (milieu du segment décalé vers le haut, le bas et les
   côtés de `NOCLIP_DETOUR_BASE` + `NOCLIP_DETOUR_RATIO` × longueur, deux raycasts chacun). Un détour libre = virage
   serré autour d'un coin ou arête de rampe passée à grande vitesse (la corde coupe l'angle, pas la trajectoire) ;
   aucun = traversée. Pas testé sur le premier paquet d'un personnage (son point de départ est la racine posée par le
   serveur). Un raycast qui part de l'intérieur d'une pièce ne la touche pas : l'entrée dans un mur est vue, la sortie
   non.
2. **Vol** (`observe`) : un paquet est **porté** si une pièce de la map passe à moins de `SUPPORT_REACH` (6 studs) d'un
   point du segment (pas de `SUPPORT_STEP`), sous le centre ou à côté et inclinée vers le haut (`supports` : point le
   plus proche de la boîte orientée ; un mur vertical ne porte pas, une rampe de surf si ; un `WedgePart` est pris pour
   sa boîte, plus large), ou si le segment passe dans un volume d'échelle. Porté : rien à juger. Au premier paquet en
   l'air, une **enveloppe balistique** part de lui : vitesse verticale majorée (montée depuis le paquet précédent sur
   `MIN_PACKET_INTERVAL` = demi-intervalle d'envoi, ou vitesse imposée d'un geyser, d'un lanceur ou du lancement depuis
   le soleil, plus `JUMP_VELOCITY`), gravité, chute plafonnée à `MAX_FALL_SPEED`. Plus haute position permise = maximum
   de l'enveloppe sur `[τ - FLIGHT_TIME_SLACK, τ + FLIGHT_TIME_SLACK]` (gigue, paquets groupés) +
   `FLIGHT_HEIGHT_TOLERANCE`. Sous l'enveloppe, elle est **resserrée** à chaque paquet : la hauteur gagnée depuis le
   premier paquet en l'air, en au moins `max(n × MIN_PACKET_INTERVAL, (n - 1) × SEND_INTERVAL)` secondes (n = paquets
   reçus moins deux, marge pour le désordre), majore la vitesse actuelle (`maxVyAfter` + `REFINE_MARGIN`, jamais sous
   `-MAX_FALL_SPEED`) ; juste après un resserrement en descente, un paquet plus ancien arrivé en retard peut être plus
   haut de la chute faite pendant `REORDER_TIME` (0,1 s) à la vitesse de l'ancre plus deux `REFINE_MARGIN`, toléré
   (pas une chute plafonnée : 13 studs laisseraient un tricheur osciller sans être vu). **Deux paquets au-dessus à moins de
   `SUSPECT_WINDOW` (2) paquets d'écart** = vol (un seul : paquet ancien arrivé après un plus récent ; l'alternance
   haut/bas d'un tricheur est prise). Un vol bloquant passe avant un noclip en journal seul. Après un vol signalé,
   l'enveloppe repart du point atteint, vitesse nulle : un joueur qui plane encore est signalé environ deux fois par
   seconde, pas à chaque paquet. Lancement depuis le soleil : la vitesse `LaunchVelocity` du personnage ouvre
   l'enveloppe. Correction (D1 ou D2) : enveloppe repartie de la position de correction avec la vitesse d'un saut.
3. **Vide** (`fellIntoVoid`, boucle `checkVoid` toutes les 0,25 s) : joueur en l'air (dernier paquet jugé non porté),
   sans paquet reçu depuis `VOID_SILENCE` (2 s ; un paquet ignoré en attente d'accusé compte comme signe de vie pendant
   `VOID_SILENCE` après le refus, pas au-delà), dont même la plus haute position de l'enveloppe est passée sous
   `KillHeight`, et sans aucune pièce de la map ni volume d'échelle ou de boost dans la zone où il a pu atterrir
   (`voidProbe` : boîte de la hauteur de mort au sommet de l'enveloppe, large de sa vitesse horizontale majorée plus
   `RUN_SPEED` fois le temps écoulé, `GetPartBoundsInBox`) : journalisé (`Movement`, gravité faible, une coupure réseau
   en produit aussi) et tué (`KillZone.kill`). Un client corrigé au-dessus du vide qui n'accuse jamais réception y passe
   aussi. La zone est volontairement large : un joueur qui se tait juste au bord de l'île n'est pas déclaré tombé (il a
   pu revenir s'y poser) ; il reste figé côté serveur à sa dernière position. Une zone découpée dans le temps (hauteur
   possible et distance parcourue à chaque instant) serait plus serrée, sans distinguer non plus ce cas.

**Modes** (`MovementGuardRules.ENFORCE_NOCLIP`, `ENFORCE_FLIGHT`, `ENFORCE_VOID`) : `ENFORCE_NOCLIP = false` et `ENFORCE_FLIGHT = false` : journal
seul (violation `Movement` moyenne comptée, position appliquée). `ENFORCE_VOID = true` : un joueur dans ce cas tombait
de toute façon (false : journal seul, un signalement par `VOID_SILENCE`).

**Passer en bloquant.** Laisser tourner en jeu publié, puis lire le journal `Movement` des joueurs honnêtes (résumé
webhook, ou console serveur `[CheatLog] … noclip :` / `vol :`), surtout en surf rapide, sur les échelles et aux
boosts. Sans faux positif : `ENFORCE_NOCLIP = true` puis `ENFORCE_FLIGHT = true` (une PR chacun). Le refus passe par
`refuse` (journal, correction, paquets périmés ignorés) ; les tests Lune couvrent les deux modes. Faux positifs
constatés : vol → relever `FLIGHT_HEIGHT_TOLERANCE` ou `FLIGHT_TIME_SLACK` (gigue), `REFINE_MARGIN` (après une rampe) ;
noclip → relever `NOCLIP_DETOUR_BASE` ou `NOCLIP_DETOUR_RATIO`.

**Limites connues.** Un joueur qui plane à moins de `SUPPORT_REACH` d'une surface (ou le long d'une rampe, d'un bord de
mur) n'est pas signalé ; au décollage, l'enveloppe accorde une marge (vitesse estimée doublée, plus un saut) épuisée en
quelques dixièmes de seconde de vol libre ; un `WedgePart`, un cylindre ou une `MeshPart` portent sur toute leur boîte ;
un volume de geyser ou de lanceur touché compte comme support et donne sa vitesse au décollage suivant même en
recharge (oubliée au premier paquet porté hors du volume). Ces écarts vont dans le sens du joueur honnête. Coût : les
volumes d'échelle et de boost sont parcourus à chaque paquet (2 échelles sur Dizzy) ; une map qui en a des dizaines
devrait les chercher par une requête spatiale.

**Pièges.**

- Les paquets non fiables peuvent arriver dans le désordre et groupés : jamais d'estimation de vitesse sur l'heure
  d'arrivée de deux paquets successifs. Le seul temps sûr côté client est l'intervalle minimal entre deux envois :
  `CharacterSync.send` (client) ne reporte qu'une demi-période au plus, donc deux envois sont séparés d'au moins
  `SEND_INTERVAL / 2`, même après une saccade (avant #177, le report d'une période entière permettait deux envois à
  une frame d'écart). Ne pas relever ce plafond sans revoir `MIN_PACKET_INTERVAL`.
- En chute plafonnée (`MAX_FALL_SPEED`), une parabole ne vaut plus : une borne de vitesse déduite d'une parabole doit
  être ramenée à `-MAX_FALL_SPEED` au plus bas.
- Raycasts `Include` sur la map et `RespectCanCollide` : un client honnête collisionne aussi avec les pièces `CanQuery`
  sans collision ; le serveur, plus permissif, ne s'en plaint pas.
- Vérifier en Studio : un paquet forgé s'envoie en contexte Client avec un numéro de correction élevé
  (`CharacterSync:FireServer(pos, 0, 1000, false)`, l'accroupi est exigé depuis #213) ; un client figé s'obtient avec
  `RunService:UnbindFromRenderStep("MovementStep")` (plus de mouvement ni d'envoi) ; une apparition à un endroit choisi,
  en déplaçant les points de `Maps.Dizzy.GroundSpawns` pendant le Play.

**Coût** (sonde `PerfServer`, Studio, 1 joueur, Dizzy, 5 bots) : repère `srv anti-vol` 0,01 à 0,07 ms/frame à 20
paquets/s (0,1 à 0,4 ms par paquet au pire, un pic à 0,85 ms), `srv vide` 0,001 ms/frame. Quelques dixièmes de ms par
frame à pleine partie.

**Vérifié.** Tests `tests/specs/MovementGuardRules.spec.luau` : traversée d'un mur, chute à travers un sol, virage
serré autour d'un coin à 100 studs/s, arête de rampe à 300 studs/s, saut, 10 s de bhop avec 80 ms de gigue, chute de
300 studs, bhop et chute à 15/30/45/144 FPS sur 10 graines de gigue, surf sur une rampe à 60° puis sortie à 130 studs/s
vers le haut, échelle (et la même montée sans échelle signalée), geyser, lancement depuis le soleil au premier paquet
tardif, geyser dépassé à pied, vol stationnaire, vol en alternance haut/bas, descente lente, les deux modes (journal
seul, bloquant sans boucle de corrections, vol bloquant prioritaire sur un noclip en journal seul), vide (sol cherché
devant un saut par-dessus un trou, paquets en attente d'accusé). En jeu (Studio, latence nulle) : bhop et strafes,
montée à l'échelle jusqu'au toit sans violation ; client figé au-dessus du vide déclaré tombé après 2 s (deux fois,
avant et après les revues) ; paquet forgé à travers un mur journalisé (`noclip`, puis le retour du vrai client), refusé
et corrigé une seule fois en mode bloquant ; vol stationnaire forgé journalisé (`vol`). Non vérifié en jeu : surf
(Dizzy n'a pas de rampe de surf), boosts et lancement depuis le soleil (absents de Dizzy), vrai ping. Point ouvert : un
`vol` journalisé une fois pendant une session où le personnage avait été apparu par script avec le client resté sur le
menu (positions envoyées non physiques), non reproduit.

**Impact.** Le vide est fermé ; le noclip et le vol sont visibles au journal, bloquants après mesure. Le vol et le
noclip donnent surtout des positions de tir hors d'atteinte, que T1 (ligne de vue) limite déjà en partie.

## Remotes

### Inventaire

Créés dans `src/server/init.server.luau`, noms dans `src/shared/NetworkProtocol.luau`. Seuls les remotes écoutés
par le serveur (C→S) sont une surface d'attaque ; un `FireServer` sur un remote S→C n'a pas d'écouteur et est ignoré.
Depuis #170, chaque remote C→S de ce tableau (sauf `DebugPlaytest`, Studio seulement) passe d'abord par la garde
commune (débit et types, voir R1) ; la colonne « Validation actuelle » décrit ce que fait ensuite le handler.

| Remote | Sens | Arguments | Validation actuelle | Manque |
|---|---|---|---|---|
| `MeleeDamage` | C→S | `targetChar, attackKind, hitTime` | Cible, arme, portée, type d'attaque, cadence, dégâts serveur, durée d'equip (T2, #175), instant du coup borné par le ping (#214), orientation et ligne de vue vers la cible rembobinée à cet instant (M1, #176, #213 ; journal seul) (`Validator.authorizeMelee`) | Passage en `block` après mesure (M1, `ping`), tireur vivant |
| `HitscanDamage` | C→S | `targetChar, hitPart, origin, direction, hitPos, shotTime` | Cible, arme, partie de la cible, portée des racines, cadence ; forme, instant borné par le ping (#214, journal seul), origine, visée rembobinée (pose comprise, #213), portée 2 048, ligne de vue (T1, #174 : origine, visée et ligne de vue en journal seul) ; durée d'equip et chargeur (T2, #175) ; rattachée à son `ShotFired` par `shotTime`, sinon orpheline comptée dans le chargeur (#215, #216 : `shotLink` en journal seul) | Passage en `block` après mesure (T1, `shotLink`), tireur vivant |
| `CharacterSync` (non fiable) | C→S puis S→C | `pos, yaw, ack, crouching` (relais : `char, pos, yaw, stamp`) | Forme, débit 40 Hz (garde), seau de distance et silence plafonné, refus corrigé (D1, `CharacterSync.luau`, `onClientPosition`) ; noclip et vol au journal, vide (D2, #177) | Noclip et vol en mode bloquant après mesure (D2) |
| `MovementCorrection` | S→C | `char, pos, seq` | — | — |
| `WeaponAction` | C→S | `action` | Valeur `Shoot`/`Reload`, outil en main, 0,05 s mini (`init.server.luau`) ; `Reload` démarre le rechargement suivi par le serveur avant ces filtres (T2, #175) ; `Shoot` ignoré pour une arme à distance (#215 : recul 3P posé par le relais de `ShotFired`) | `Shoot` du couteau non lié à la cadence : pose 3P seulement (un coup manqué n'a pas d'autre remote) |
| `ShotFired` | C→S puis S→C | `origin, direction, shotTime` ; relais : `char, weaponName, origin, direction` | Garde (5/s, `shotTime` nombre fini), tireur vivant, arme à distance prête (`Validator.isReadyToFire` : equip, chargeur), forme, origine à `ORIGIN_MAX` (185 studs) de la racine, cadence `FireDelay` à 0,15 s près (`ShotRelayRules`, #156) ; accepté : compté dans le chargeur et inscrit au registre des tirs (`Validator.noteShotFired`, #215, #216), recul 3P posé ; refus non journalisé | `shotTime` non borné par le ping (celui de la touche l'est, #214) |
| `RequestSpawn` | C→S | aucun | `SpawnRules.request` : spawn en vol, personnage en place, bannière de fin, mort depuis moins de `RESPAWN_DELAY` en round actif (`SpawnManager.init`, handler de `RequestSpawn`) | Rien (R1 fermé, #171) |
| `LeaveRound` | C→S | aucun | Retour au menu (#157) : `RoundManager.withdraw` (score de la manche effacé, coups en attente du joueur oubliés, disparition du personnage non comptée), puis `SpawnManager.withdraw` (personnage détruit, plus de réapparition, prochain `RequestSpawn` accepté sans `RESPAWN_DELAY`) (handler de `leaveRoundRmt` dans `init.server.luau`, `SpawnManager.withdraw`). Touché depuis moins de `GameConfig.LEAVE_DEATH_WINDOW` (5 s) : le départ compte comme une mort, kill au dernier attaquant (#217, `LeaveRules.countsAsDeath`) | Fuite d'une mort imminente fermée (#217) tant que le coup date de moins de 5 s ; un joueur au bord du vide sans coup reçu peut toujours éviter sa chute. Réapparaître plus tôt reste possible : il perd à chaque fois tout son score de la manche, comme un joueur qui quitte le jeu |
| `SendFeedback` | C→S | `text` | Type, longueur, 60 s en mémoire après toute demande valide (posé avant le DataStore, quel que soit le résultat), 5 par semaine (`UpdateAsync`), rien d'écrit si la lecture échoue (`FeedbackService.init`, handler de `SendFeedback`) | Rien (R1 fermé, #171) |
| `SaveSettings` | C→S | table | `PlayerSettings.sanitize`, écriture différée de 10 s (`SettingsStore.onSaveSettings`) | Débit (coût CPU seulement, faible) |
| `GetSettings` (RemoteFunction) | C→S | aucun | Attend le chargement, 20 s au plus (`SettingsStore.onGetSettings`) | Appels simultanés non bornés pendant le chargement (fils qui attendent) |
| `EquipItem` (#280) | C→S | `slot, weaponId, skinId` (`""` : d'origine) | Garde (3/s, rafale 8 ; emplacement connu, ids ≤ 64 octets), inventaire chargé, au menu seulement (ni personnage présent ni chargement en vol, `SpawnManager.isSpawning`), `InventoryRules.equip` : arme possédée de cet emplacement, skin possédé de cette arme ; refus d'item journalisé (`Inventory`, faible). Écriture DataStore une toutes les 6 s au plus, clics réunis (`InventoryStore.equip`) | « Au menu » se lit sur le personnage (absent ou détruit) : pendant la réapparition d'un joueur mort en partie (corps détruit après 0,3 s, `RESPAWN_DELAY`), un client modifié peut changer d'arme entre deux vies, parmi celles qu'il possède. Sans gain (mêmes armes qu'un autre loadout possédé), non fermé |
| `DebugPlaytest` | C→S | `id, ok, detail, data` | Studio seulement, id attendu et propriétaire (`DebugPlaytest.init`) | Rien en jeu publié |
| `HitConfirm`, `RoundState`, `ScoreUpdate`, `RoundResult`, `PlayerDied`, `FeedbackAck` | S→C | — | — | `PlayerDied` donne la position de la victime à tous (`RoundManager.announceDeath`) : sans effet tant que l'ESP est accepté (E1) |

### R1. Garde commune et failles constatées

**Respawn (fait, #171).** Avant : le personnage mort est détruit 0,3 s après la mort (`CORPSE_HANDOFF_DELAY`,
`init.server.luau`) et `canSpawn` ne testait que `player.Character.Parent` ; un client modifié qui envoyait
`RequestSpawn` après 0,3 s réapparaissait tout de suite au lieu d'attendre `RESPAWN_DELAY` = 2,5 s
(`GameConfig.RESPAWN_DELAY`), puis la réapparition programmée (`RoundManager.onCharacterDied`) remplaçait son
personnage par un neuf. Le client légitime n'envoie `RequestSpawn` que depuis le menu
(`src/client/systems/game/GameStateController.luau`, `requestPlay`). Parade en place :

- `SpawnManager.noteDeath` retient l'heure de la mort (Humanoid.Died, joueurs seulement) ;
- `SpawnRules.request` (pur, `tests/specs/SpawnRules.spec.luau`) refuse, dans l'ordre : un `LoadCharacterAsync` déjà en
  vol (`spawning`), en round actif une mort de moins de `RESPAWN_DELAY` (`early`, même si le corps est encore en
  place), un personnage en place (`alive`, corps compris), la bannière de fin (`result`). Une mort hors round actif ne compte pas : la bannière dure plus que le
  délai, le premier spawn du round suivant n'est pas gêné ;
- refus au journal, catégorie `Spawn` : `early` moyen (notre client n'est pas au menu pendant un round où il est mort),
  `spawning` et `alive` faibles (course réseau possible), `result` sans violation (Play cliqué pendant la bannière) ;
- la réapparition programmée passe par `SpawnManager.respawn` : rien si le joueur a déjà un personnage vivant
  (`SpawnRules.isAlive` : en place et PV > 0) ou un chargement en vol ; `SpawnManager.spawnPlayer` ne lance qu'un
  `LoadCharacterAsync` à la fois par joueur (pcall, connexion `CharacterAdded` rendue en cas d'échec) ;
- chaque demande admise reçoit une réponse (#219, `SpawnRules.reply`) ; le client légitime renvoie sa demande sans
  réponse ou après un refus temporaire (`SpawnRequestRules`, au plus un envoi toutes les 1,2 s, sous le débit de
  `RemoteGuard`). Ces renvois peuvent ajouter au journal des refus `spawning` ou `alive` faibles (réponse en route
  pendant un gel du serveur) ; les refus `result` répétés pendant la bannière n'y vont pas. Un `alive` sur un
  personnage vivant n'est plus journalisé : le client le reprend et le serveur le remet au round (`beforeSpawn`, sans
  effet sur un joueur déjà inscrit) ; seul un `alive` sur un corps l'est encore. Une demande `spawning` est servie à la
  fin du chargement en vol (nouveau chargement s'il a échoué), comme le retour du menu de #157 ;
- les bots ne passent pas par là : `BotManager` gère leur réapparition (`diedAt` + `RESPAWN_DELAY`) et leur passe un
  rappel vide.

Retour au menu en partie (#157, remote `LeaveRound`) : `SpawnManager.withdraw` efface l'heure de la mort et annule la
réapparition programmée, donc un mort qui revient au menu puis clique JOUER n'est ni refusé `early` ni journalisé ; il a
perdu son score de la manche (`RoundManager.withdraw`). Si sa réapparition programmée chargeait encore, sa demande est
servie à la fin de ce chargement (`SpawnRules.rejoinsInFlight`) au lieu d'être refusée `spawning`.

**Fuite d'une mort par le menu (fait, #217).** Un départ moins de `GameConfig.LEAVE_DEATH_WINDOW` (5 s) après un coup
reçu compte comme une mort (`LeaveRules.countsAsDeath`, lu par `RoundManager.withdraw`) : kill au dernier attaquant
(mort entre-temps : crédité ; parti : départ libre), `PlayerDied`, stats comme une mort normale (`onDeathCounted`). Un
coup absorbé par la protection d'apparition garde le tueur mais pas l'instant (`LastHit.at` nil). Limites assumées :
quitter le jeu (déconnexion) n'est pas couvert ; un départ compté comme une mort ne retient pas `RESPAWN_DELAY`.
Vérifié pour #219 : ce départ ne laisse pas de refus `early` à JOUER (`SpawnManager.withdraw` efface l'heure de la
mort, `RoundManager.withdraw` ne passe pas par `noteDeath` ; test « départ par MENU PRINCIPAL compté comme une mort »).
Si `RESPAWN_DELAY` y était un jour imposé, le client attendrait le délai annoncé (`retryIn`) au lieu de rester bloqué.
Vérification Studio (2026-11-11) : joueur passé à 1000 PV côté serveur (un tir d'AWP de bot ne le tue pas), menu en
partie ouvert d'avance (`DebugInGameMenu`), attente du coup bornée à 6 s en contexte `Client`, puis clic sur
MENU PRINCIPAL (`user_mouse_input` aux coordonnées `AbsolutePosition` + taille / 2, `InGameMenu` ignore l'inset). Départ
1,6 s après le coup : `PlayerDied` reçu (tueur le bot, arme AWP) ; départ sans coup : rien.

**Feedback (fait, #171).** Avant : `lastSent` n'était écrit qu'après un envoi réussi au webhook, alors que chaque
demande valide lisait (et écrivait) le DataStore : sans webhook, ou la limite hebdomadaire atteinte, un spam provoquait
un `GetAsync` par appel et épuisait le budget DataStore du serveur, partagé avec `SettingsStore` et `StatsStore`
(dont le chargement échoue alors pour tout le monde). Et si `GetAsync` échouait, la liste lue était vide et le
`SetAsync` suivant remettait le quota hebdomadaire à zéro. Parade en place (`FeedbackService.luau`, testée par
`tests/specs/FeedbackService.spec.luau`) :

- après la garde commune et la longueur, `lastAttempt` (en mémoire, par joueur et par serveur) refuse toute demande à
  moins de 60 s de la précédente, et est posé **avant** tout accès DataStore, quel que soit le résultat (succès, webhook
  en échec, quota atteint, DataStore en panne, pas de webhook) : au plus un accès par minute et par joueur. Il survit
  au départ du joueur tant que le délai court (une reconnexion ne le remet pas à zéro) ;
- l'URL du webhook est lue avant le DataStore : sans webhook, ni accès ni quota consommé ;
- quota en un seul `UpdateAsync` (un accès au lieu de `GetAsync` + `SetAsync`, et atomique entre serveurs) : la
  décision est `FeedbackService.weeklyQuota` (pure, valeurs non numériques ignorées), qui annule l'écriture à la limite.
  Un `UpdateAsync` en erreur n'écrit rien (lecture échouée ≠ liste vide) et le feedback est refusé ;
- un envoi au webhook en échec est rendu au quota (au mieux, second `UpdateAsync`) : une panne du webhook ne bloque pas
  le joueur une semaine.

Pas de catégorie `CheatLog` pour ces refus : un joueur honnête qui réessaie après une erreur tombe dessus.

**Garde commune (fait, #170).** `src/server/RemoteGuard.luau` (pur, testé par `tests/specs/RemoteGuard.spec.luau`) :
seau à jetons par joueur et par remote (débit et rafale), contrôles de type (`instance`, `vector3` fini, `number` fini,
`string` bornée, `enum`, `table`). Les règles de chaque remote sont dans `RemoteGuard.RULES`, branchées par
`CheatLog.admit(player, nomDuRemote, ...)` en tête de chaque handler (`init.server.luau`, `CharacterSync`,
`SpawnManager`, `FeedbackService`, `SettingsStore`). Débit d'abord (un appel en trop n'est pas analysé), puis types :

- débit dépassé : appel ignoré, violation faible `RemoteRate` ;
- type impossible pour notre client : appel ignoré, violation forte `RemoteArgs` ;
- Instance absente (`nil`) : appel ignoré **sans** violation. Une Instance qui n'existe que chez le client (corps en
  ragdoll cloné localement par `DeathRagdoll`, décor du menu) arrive en `nil` au serveur : un client honnête qui tire
  sur un corps local en envoie. Ne jamais traiter un `nil` d'Instance comme une triche.

Débits (`RemoteGuard.RULES`, en appels/s et rafale) calibrés au-dessus du client honnête, rafale réseau comprise :
`MeleeDamage` 5/5 (couteau : 2,5/s au plus), `HitscanDamage` et `ShotFired` 5/5 (AWP : 0,7/s), `WeaponAction` 8/8 (un `Shoot` par coup
de couteau, plus par tir depuis #215, un `Reload`), `CharacterSync` 40/60 (20 Hz, 3 s de paquets groupés après une coupure), `RequestSpawn` 1/3, `LeaveRound` 1/3,
`SendFeedback` 0,5/3, `SaveSettings` 2/5 (1 envoi/s au plus), `GetSettings` 0,2/3 (une demande au démarrage ; borne
aussi les demandes en attente du chargement), `EquipItem` 3/8 (un clic par arme ou skin à l'accueil, #280). **Une nouvelle arme plus rapide (automatique) demande de relever
`HitscanDamage`, `ShotFired` et `WeaponAction`**, et un nouveau remote C→S doit avoir sa règle (sinon tout appel est refusé, sans
violation, avec un warn `remote sans règle`) et un cas dans le test « accepte les appels de notre client ». Un appel
arrivé après le départ du joueur (`player.Parent` nil, ex. juste après un kick) est ignoré sans rien recréer.
Roblox limite déjà le débit client → serveur par type de remote, mais globalement, et sans le dire au jeu : la limite
par remote est à faire soi-même ([Remote events](https://create.roblox.com/docs/scripting/events/remote),
[Rate limiter module](https://devforum.roblox.com/t/rate-limiter-module-for-remotes/616268)).

**Relais des tirs (fait, #156).** Le son d'un tir chez les autres et l'ouïe des bots ne partent plus de l'action
visuelle `WeaponAction` mais d'un tir accepté par le serveur. Le client annonce chaque tir à distance, touché ou manqué,
par `ShotFired(origin, direction, shotTime)` (#216 pour `shotTime`) (`HitscanSystem`, juste avant `HitscanDamage` : les remotes fiables d'un client
arrivent dans l'ordre) ; les bots par `BotArsenal` (`onFire`, avant leur raycast). `relayShot` (`init.server.luau`)
vérifie tireur vivant, arme à distance en main prête (`Validator.isReadyToFire` : equip et chargeur de T2, en lecture
seule, sans journal), puis `ShotRelayRules.admit` : forme (Vector3 bornés, direction unitaire), origine à moins de
`ORIGIN_MAX` (5 + 450 × 0,4 = 185 studs) de la racine serveur, cadence `FireDelay` à `CADENCE_TOLERANCE` (0,15 s) près,
propre au relais (un tir refusé ne la relance pas, elle ne touche pas celle des touches). Accepté : relayé par
`FireClient` à tous les joueurs sauf le tireur (`ShotRelayRules.recipients`), et entendu par les bots
(`BotManager.hearShot`, joueurs seulement : ceux des bots passent par `BotBrain`). Pas de journal sur un refus : un tir
sans dégâts ne rapporte rien, et un faux positif (gigue) n'a pas à compter. Depuis #215, un tir relayé est compté
dans le chargeur et pose le recul 3P : plus de tir entendu sans rechargement (voir « Tirs comptés et touches
rattachées » en T2). Limites : la cadence est jugée à l'arrivée, comme celle des touches : deux tirs groupés par une
coupure réseau, le second est muet ; une touche peut être acceptée alors que son `ShotFired` a été écarté (son muet,
dégâts appliqués, touche orpheline au journal en `log`, comptée dans le chargeur). Un coup de couteau n'est plus
entendu par les bots (il passait par `WeaponAction`). Tests : `tests/specs/ShotRelayRules.spec.luau`, « tir relayé » de
`tests/specs/Validator.spec.luau`.

**Coût.** Négligeable. **Impact.** Ferme deux failles réelles et donne le point d'entrée commun de la journalisation.

## Aimbot et triggerbot (A1)

**Aujourd'hui (fait, #178, journal seul).** Statistiques par joueur et par session, calculées sur le serveur par
`src/server/AimStats.luau` (règles pures, `tests/specs/AimStats.spec.luau`), branchées dans `src/server/init.server.luau` :

- **tirs** : chaque tir à distance accepté par le relais `ShotFired` (#156, touché ou manqué) ;
- **touches** et **têtes** : chaque touche à distance acceptée par le `Validator` **qui a fait des dégâts** (pas un
  corps déjà mort pendant le ragdoll, pas un ForceField) ; depuis #216, une touche est rattachée au tir que le
  `Validator` lui a trouvé par `shotTime` (registre de « Tirs comptés et touches rattachées », troisième valeur de
  `authorizeHitscan`), une seule par tir ; sans tir rattaché, elle est **orpheline** (« orph » au résumé, anomalie déjà
  journalisée `shotLink` par le `Validator`). Taux de touches = tirs rattachés / tirs, l'orpheline comptant comme un tir qui touche (#246) ; taux de
  tête = têtes / touches (toutes) ;
- **flick** : rotation horizontale entre le dernier cap accepté par `CharacterSync` (`CharacterSync.lastYaw`, cap de la
  caméra, 20 Hz) et la direction **de la touche** (`HitscanDamage`, vérifiée par le `Validator`), si ce cap date d'au
  plus `FLICK_MAX_AGE` (0,1 s). Le cap est **figé à l'arrivée de `ShotFired`** (juste avant la touche) : un paquet de
  position (non fiable) arrivé entre le tir et sa touche (fiable) ne compte pas, sinon le recul ou le retour de visée
  après un tir d'AWP ferait des faux flicks. Figé **par tir** (`AimStats.ShotRecord`, #216) : la touche prend le cap
  de son tir, pas celui du dernier. Pas la direction de `ShotFired` : rien ne la compare à la touche, un
  aimbot y enverrait son cap courant. Flick = au moins `FLICK_MIN_ANGLE` (30°) en 0,1 s au plus, soit 300 °/s
  minimum : au-dessus d'un air strafe de surf ordinaire (100 à 250 °/s, environ 10° par paquet). Touche sans tir
  rattaché (orpheline) : pas de mesure. Statistique jugée : part des touches précédées d'un flick. La vitesse maximale (`pic`, °/s,
  durée bornée à `MIN_SPEED_DT` = 1/20 s) est affichée, pas jugée (trop bruitée par la gigue réseau). Le pitch n'est
  pas mesuré (le serveur ne reçoit que le cap) : un flick vertical passe inaperçu. **Indice faible** : le cap vient du
  client ; un paquet de position parti dans la frame du tir (caméra déjà tournée) donne un écart nul, et un aimbot qui
  fait tourner la racine sur 2 ou 3 paquets n'en produit aucun. Les flicks sont donc sous-comptés, jamais inventés ;
- **bots exclus** : ni comptés, ni dans la population. Les touches de mêlée ne comptent pas.

**Seuils.** Un joueur est jugé quand il a `MIN_HITS` (30) touches, et seulement contre les **autres** joueurs jugeables
du serveur, s'ils sont au moins `MIN_POPULATION` (5) : en dessous (serveur de 2 joueurs), personne n'est signalé. Une
statistique est signalée si elle dépasse la moyenne des autres de `Z_THRESHOLD` (3) écarts-types (écart-type
d'échantillon, divisé par n - 1, plus large et donc plus prudent sur 5 joueurs ; au moins `MIN_SPREAD`, 0,05) **et** son plancher absolu `FLOOR` : tête 60 %, touches 75 %, flick touché 30 %. Valeurs de
départ, à revoir sur le journal de production.

**Où le lire.**

- Console serveur, toutes les `AIM_REPORT_INTERVAL` (120 s) : une ligne `[AimStats] <nom> (<UserId>) : …` par joueur
  qui a tiré depuis la précédente, et `[AimStats] fin de session, …` au départ.
- `CheatLog`, catégorie `Aim`, gravité faible, **seulement pour un joueur signalé** (à chaque résumé périodique où il
  l'est, et au départ). Un seul signalement suffit au résumé de fin de session (webhook), qui reprend le dernier
  relevé (« Visée (dernier relevé, revue humaine) »). Le relevé final passe par `CheatLog.onClosing`, avant la clôture
  du bilan.
- Format (compact : le détail de `CheatLog` est coupé à 160 octets) : `SIGNALÉ z tête+8.1 | tirs 100 but 40 (40%)
  touches 41 orph 1 tête 36 (88%) flick 2 (5%) mesurés 38 pic 1240°/s | z touches +0.2 flick -0.3` (« mesurés » :
  touches dont le flick a pu être mesuré). « but » = tirs qui ont touché, rattachés ou orphelins (taux de touches), « touches » =
  toutes les touches acceptées (seuil `MIN_HITS`, base du taux de tête), « orph » = touches sans tir rattaché (#216) ; le z d'une statistique signalée est en tête, les autres à la fin. « non jugé (12/30 touches) » ou « non
  jugé (population trop petite) » quand il n'y a pas de quoi comparer.
- Un joueur signalé une fois a aussi son relevé **final** au journal, même redevenu normal : le « dernier relevé » du
  résumé est donc vraiment le dernier. À l'arrêt du serveur, tous les joueurs restants sont jugés ensemble contre la
  même population (rappels `CheatLog.onClosing` appelés avec la liste et `shuttingDown`), puis les statistiques sont
  gelées (`AimStats.freeze`) : un tir pendant l'attente de l'arrêt ne recrée pas de relevé partiel. Limite : des départs un par un (fin de partie)
  font fondre la population, et les derniers partis sont « non jugés » au départ ; leurs résumés périodiques (toutes
  les 120 s) les ont jugés tant que la population était là.

**Limites connues** (à garder en tête à la lecture) :

- le nombre de tirs vient de `ShotFired`, que le client choisit d'envoyer : un tricheur peut faire baisser son taux de
  touches en envoyant des tirs sans touche (cadence et chargeur respectés depuis #215). Taire ses tirs manqués ne le
  fait plus monter (#216) : ses touches deviennent orphelines et journalisées ; depuis #246, une orpheline compte comme
  un tir qui touche et lève une violation au-delà du seuil (voir ci-dessous). Un « orph » élevé est à regarder ; quelques-uns s'expliquent par un `ShotFired` écarté par le relais (gigue) ;
- un client qui n'envoie **jamais** `ShotFired` n'a aucun flick mesuré (aucun cap figé) ; depuis #246 il ne sort plus
  du taux de touches ni de la violation : chaque touche orpheline compte comme un tir qui touche (`shots` et `hitShots`
  +1), et `AimStats.orphanAlert` lève une violation `Hitscan:orphanRate` (gravité moyenne, journal seul) dès
  `ORPHAN_MIN_HITS` (5) orphelines **et** plus de `ORPHAN_MAX_RATE` (25 %) des touches, sur au moins
  `ORPHAN_MIN_TOUCHES` (20) touches, puis à chaque nouveau palier de 5 (journal borné, pas de rattrapage si le seuil est
  franchi tard). Limite : un `ShotFired` arrivé après sa touche orpheline (client modifié seulement) est compté comme
  un second tir. Justification : Roblox garantit l'ordre des remotes d'une connexion, un client honnête n'a d'orphelines
  que par un `ShotFired` écarté par le relais (rare). Chaque touche reste aussi une violation `shotLink` faible
  (`SUMMARY_MIN_LOW`) et « orph » égale « touches » au relevé. Contrepartie : un tricheur qui tait ses tirs manqués
  gonfle son taux de touches, mais il franchit le seuil d'orphelines ;
- les touches sur les bots comptent : un joueur qui ne joue que contre des bots peut ressortir face à des joueurs qui
  jouent entre eux. Regarder le contexte de la partie avant de conclure ;
- le jugement recalcule la population pour chaque joueur (O(n²) toutes les 120 s) : négligeable aux tailles de
  serveur actuelles.

**Comment le lire.** Un signalement est un indice à regarder, pas une preuve : un très bon joueur à l'AWP vise la tête.
Plus parlant : plusieurs statistiques signalées ensemble (tête et flick touché), sur plusieurs sessions, avec un taux de
touches élevé. **Jamais de sanction** sur ces chiffres (voir « Bannissement ») ; aucun tir n'est refusé, rien dans
`AimStats` ne renvoie de verdict sur un tir.

**Écarté.** Temps de réaction entre l'apparition d'une cible et le tir : demande un calcul de visibilité, trop cher
(voir E1). Envoyer le pitch dans `CharacterSync` : 9 octets de plus par paquet, gardé pour plus tard si les flicks
horizontaux ne suffisent pas.

**Coût.** Serveur : négligeable (quelques additions par tir, un jugement en O(n²) toutes les 120 s). Analyse : humaine.

## Wallhack et ESP (E1)

**Aujourd'hui.** Toutes les positions sont envoyées à tous :

- le relais `CharacterSync` envoie à chaque autre joueur la position de chacun, sans filtre
  (`onClientPosition` et `CharacterSync.relayBot` dans `src/server/CharacterSync.luau`) ;
- le serveur pose la racine de chaque personnage (`root.CFrame` dans `onClientPosition`), propriété répliquée nativement à tous les clients ;
- les personnages sont dans `Workspace`, sans streaming (`StreamingEnabled = false` sous `Workspace` dans `default.project.json`) ;
- `PlayerDied` donne la position de chaque mort (`RoundManager.announceDeath`), et #156 relaiera les tirs.

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

### Journaliser (fait, #170)

Module serveur `src/server/CheatLog.luau` (testé par `tests/specs/CheatLog.spec.luau`). API pour les parades :

```lua
CheatLog.report(participant, CheatLog.Category.MOVEMENT, CheatLog.Severity.MEDIUM, "téléport de 300 studs", check?)
CheatLog.admit(player, NetworkProtocol.Names.X, ...) -- garde des remotes : true si le handler peut continuer
CheatLog.judged(participant, CheatLog.Judged.SHOT) -- un élément jugé par une parade (dénominateur, #297)
CheatLog.summary(participant.id) -- bilan (compteurs, score présent, pire violation, jugés, ping), nil sans violation
CheatLog.session(participant.id) -- jugés et ping d'un joueur, avec ou sans violation
```

- **Gravités** (`CheatLog.Severity`) : `LOW`, `MEDIUM`, `HIGH`, au sens de « Classer les violations » ci-dessous.
- **Catégories** (`CheatLog.Category`) : `RemoteRate`, `RemoteArgs` (garde des remotes), et réservées aux parades
  suivantes : `Spawn` (#171, branchée : refus de `RequestSpawn`), `Movement` (#172), `Hitscan` (#174, branchée : contrôles du tir ; #175 : equip et chargeur ; #216 : touche orpheline `shotLink`), `Melee` (#175, branchée : equip du couteau ; #176 : orientation et ligne de vue), `Aim` (#178, branchée :
  statistiques de visée signalées, toujours faible ; un relevé, pas une violation : hors du total, du score, de la
  « pire » violation et du warn limité, mais compté dans sa catégorie et suffisant pour le résumé), `Inventory` (#267,
  branchée : Tool non possédé arrivé en main, faible : notre client ne peut pas en obtenir, c'est un écart serveur à
  lire plutôt qu'une triche ; #280 : `EquipItem` d'un item non possédé, d'un autre emplacement ou d'un skin étranger,
  faible : notre client ne montre que les items possédés). Une nouvelle parade
  ajoute sa catégorie à `CheatLog.Category` et ici, pour garder des noms stables dans le journal.
- `warn` `[CheatLog]` limité à un toutes les `WARN_INTERVAL` (2 s) par joueur, le suivant dit combien ont été tus ;
  détail coupé à `MAX_DETAIL` octets sans couper de caractère, octets non UTF-8 remplacés par `?` (il peut contenir une
  valeur forgée par le client, et `HttpService:JSONEncode` du webhook échoue sur du texte non UTF-8).
- Compteurs par joueur, catégorie et gravité, et **par contrôle** (#297) : le 5e argument `check` de `report` nomme le
  contrôle, compté sous `Catégorie:check` (la catégorie seule sans `check`, ou si `check` vaut la catégorie). Noms
  livrés : `Hitscan:`/`Melee:` + contrôle de `ShotRules.Check` (`direction`, `origin`, `equip`…) et `Hitscan:orphanRate`
  (taux de touches orphelines, #246) ; `Movement:speed` (seau de distance), `Movement:noclip`, `Movement:flight`,
  `Movement:void` ; `RemoteRate:<remote>` et `RemoteArgs:<remote>` (garde) ; `Spawn`, `Inventory` et `Aim` sans
  contrôle nommé. Score en seau qui fuit (poids `SCORE_WEIGHT` : 1, 5, 20 ; décroissance `SCORE_DECAY` = 1 point/s),
  score maximal gardé au bilan. Le kick sur score moyen n'est pas branché (voir « Kick »).
- **Pire violation** (#297) : la plus grave ; à gravité égale, celle du contrôle qui en compte le plus à cette gravité
  (une répétition dit plus qu'un incident isolé), avec le dernier détail de ce contrôle (le plus récent en cas
  d'égalité). Avant #297 : la première de la gravité la plus haute, souvent un incident réseau isolé.
- Kick (`player:Kick`) à `KICK_HIGH_COUNT` = 3 violations fortes dans la session, une seule fois. Un même contrôle
  (`Catégorie:check`, le remote pour la garde) ne compte qu'une violation forte par `HIGH_SOURCE_INTERVAL` (1 s) : un
  bug de notre client sur un remote à 20 Hz (position NaN) laisse le temps de le voir au journal au lieu d'expulser en
  150 ms. Toutes restent comptées au journal et au score.
- **Dénominateurs** (#297) : chaque parade compte ce qu'elle juge, par joueur, avec ou sans violation
  (`CheatLog.judged`) : `shot` = touche de joueur soumise aux contrôles du tir (`Validator.authorizeHitscan`, après
  cible, portée et cadence ; touches refusées comprises), `melee` = coup de mêlée soumis aux contrôles
  (`authorizeMelee`), `position` = paquet `CharacterSync` jugé par le seau, le noclip et le vol (pas les paquets
  antérieurs à une correction). Dénominateur d'une catégorie (`CheatLog.DENOMINATOR`) : `Hitscan` → touches, `Melee` →
  coups, `Movement` → positions, sauf `Movement:void` (jugé par passage de boucle) et `Hitscan:orphanRate` (signalé
  une fois par palier d'orphelines ; le taux par touche est celui de `Hitscan:shotLink`), listés dans
  `NO_DENOMINATOR`. Les autres catégories n'en ont pas : nombres bruts. Deux approximations, majorant le dénominateur
  de quelques éléments seulement : `Movement:noclip` et `Movement:flight` ne jugent pas un paquet déjà refusé par le
  seau (mode `block`) ni ceux d'avant le chargement de la géométrie de la map ; `Hitscan:shotLink` ne juge pas une
  touche déjà refusée par un autre contrôle en `block` (forme, distance, equip, chargeur).
- **Ping** (#297) : `Player:GetNetworkPing` de chaque joueur toutes les `PING_SAMPLE_INTERVAL` (5 s), en histogramme
  (classes de `PING_BUCKET_MS` = 10 ms : médiane à 5 ms près, maximum exact, mémoire fixe quelle que soit la durée de
  la session). Médiane et maximum de la session au résumé du joueur, de la période au relevé.
- Au départ d'un joueur qui a une violation moyenne ou forte, au moins `SUMMARY_MIN_LOW` (10) violations faibles
  (en dessous, une rafale réseau ne fait pas de bruit au webhook), ou un signalement `Aim` (#178) : résumé (nom,
  UserId, compteurs par catégorie et par contrôle avec leur taux sur ses jugés, jugés, ping, score max, pire violation,
  kick) posté au webhook en jeu publié, par `src/server/Webhook.luau` (mécanisme de `FeedbackService`) :
  StringValue `CheatLogWebhookUrl` dans ServerScriptService, sinon `FeedbackWebhookUrl`. Pas de cumul entre sessions
  (DataStore/MemoryStore) : il relève du bannissement (#179). À l'arrêt du serveur, les résumés des joueurs encore là sont envoyés
  et attendus (`CLOSE_TIMEOUT`, 20 s). Une violation signalée pour un joueur déjà parti est ignorée.
- **Envoi au webhook** (#297) : jusqu'à `WEBHOOK_ATTEMPTS` (3) essais, attente `WEBHOOK_RETRY_DELAY` × n° d'essai
  (2 s, puis 4 s) entre deux (`Webhook.postWithRetry`), sauf refus définitif (HTTP 4xx autre que 429,
  `Webhook.isRetryable`) ; après le dernier échec, ou sans webhook configuré, le message entier part en console serveur
  (`[CheatLog] résumé de <nom> (repli console)`). Avant #297, un échec ne laissait qu'un `warn` avec l'erreur : le
  résumé était perdu. À l'arrêt, les essais tiennent dans `CLOSE_TIMEOUT` sauf si chaque requête met longtemps à
  échouer. Champs et description bornés sous les limites de Discord (`MAX_FIELD_VALUE`, `MAX_DESCRIPTION`) : les
  lignes en trop deviennent `… (+N)` au lieu d'un refus 400.
- **Relevé agrégé du serveur** (#297) : toutes les `REPORT_INTERVAL` (600 s), à l'arrêt du serveur, et à la demande
  (attribut Workspace `CheatLogReport` = true, en contexte Server, remis à nil après), un message « Anti-triche : relevé
  du serveur » au webhook **dédié** `CheatLogWebhookUrl` seulement (`REPORT_WEBHOOK_NAMES` : sans lui, console
  serveur, jamais le salon du feedback ; console dans Studio) : durée de la période et raison, joueurs vus (dont ceux
  avec violation), jugés de tous les joueurs, ping de la période, relevés de visée signalés (à part : pas des
  violations), puis une ligne par contrôle en violation, `Hitscan:direction : 2 / 10 touches (20.00 %)`, ou le nombre
  seul sans dénominateur. Les compteurs repartent de zéro à chaque relevé (périodes additionnables entre serveurs, sans
  double compte) ; un joueur parti en cours de période y reste. Pied : `JobId` du serveur. Rien n'est émis pour une
  période sans joueur. Après le dernier relevé de l'arrêt (`CheatLog.close`), plus rien n'est compté : un
  `PlayerRemoving` traité ensuite ne recrée ni bilan ni second résumé.
- **Lire un taux.** Taux = violations du contrôle ÷ éléments jugés de sa catégorie, tous joueurs confondus : un
  contrôle absent du relevé a 0 violation sur ces jugés. Additionner numérateurs et dénominateurs sur plusieurs relevés
  avant de diviser (pas de moyenne de pourcentages). Un taux sur moins de quelques centaines de jugés ne dit rien. Un
  taux non nul chez des joueurs honnêtes est un faux positif à expliquer (ping du relevé et du résumé du joueur, détails)
  avant tout passage en `block` ; un taux porté par un seul joueur se lit dans son résumé (même contrôle, son taux).
  Un `RemoteArgs:` non nul n'a pas de dénominateur mais doit être nul chez nos clients.
- Bots ignorés (`participant.isBot`, ni violations ni jugés ni ping) ; Studio : journal seulement (aucun kick, résumé
  et relevé affichés en console au lieu du webhook).
- **Coût** (#297) : un compteur par paquet de position, touche ou coup jugé, une lecture du ping par joueur toutes les
  5 s. Mesure `PerfServer` avant et après : voir le compte rendu de la PR de #297.

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

- d'abord **manuel** (#179, procédure ci-dessous), depuis le Creator Hub, à la lecture du journal (le DevForum rapporte
  une détection des comptes secondaires imparfaite, et elle ne marche pas dans Studio) ;
- automatique plus tard, seulement pour des violations fortes répétées sur plusieurs sessions, avec des durées
  croissantes (1 jour, 7 jours, puis définitif) : voir « À faire plus tard » ci-dessous ;
- aucune sanction automatique sur les statistiques d'aimbot (A1).

#### Où lire le journal

Ce que le code envoie vraiment (`src/server/CheatLog.luau`, `src/server/Webhook.luau`) :

- **Résumé au webhook**, posté au départ d'un joueur qui a au moins une violation moyenne ou forte, 10 violations
  faibles ou plus (`SUMMARY_MIN_LOW`), ou un signalement des statistiques de visée (`Aim`, #178), et à l'arrêt du
  serveur pour les joueurs encore là. Webhook : StringValue
  `CheatLogWebhookUrl` dans ServerScriptService, sinon `FeedbackWebhookUrl`. Contenu : titre « Anti-triche : <nom> »,
  total des violations, nombre de fortes comptées pour le kick, jugés (touches, coups, positions), ping médian et
  maximal, pire violation (contrôle, gravité, détail), mention « Expulsé pendant la session » le cas échéant, un champ
  par catégorie (« forte N · moyenne N · faible N », puis une ligne par contrôle avec son taux sur les jugés du
  joueur), et en pied de page le nom et le **UserId**. C'est la source de référence : un résumé = une session.
  Un envoi en échec est réessayé, puis écrit en entier dans la console serveur (repli).
- **Relevé agrégé du serveur** au webhook dédié `CheatLogWebhookUrl` (console sans lui), toutes les 10 min et à
  l'arrêt (#297) : taux de violations par contrôle,
  tous joueurs confondus, joueurs sans violation compris. C'est la source pour mesurer les faux positifs avant un
  passage en `block` (voir « Lire un taux » ci-dessus), jamais une base de ban : il est anonyme.
- **Console serveur** : lignes `[CheatLog]` au fil de l'eau (une par 2 s au plus et par joueur, avec le nombre de
  lignes tues), et `[CheatLog] <nom> (<UserId>) expulsé : N violations fortes` au kick. Utile pendant une session
  suivie en direct, sinon voir les journaux du serveur dans le Creator Hub (libellé à vérifier).
- **Pas de cumul entre sessions** : rien ne l'additionne (ni DataStore ni MemoryStore). Le décompte multi-sessions se
  fait à la main, en relisant les résumés du salon du webhook et en filtrant sur le UserId du pied de page.
- En Studio, le résumé va dans la console (`[CheatLog] résumé de …`) et rien n'est posté : **jamais de bannissement
  sur une trace de Studio**.

#### Décider

Identifier le joueur par son **UserId** (le pied de page du résumé), jamais par le nom affiché, qui change. Seuils
indicatifs, à ajuster avec l'expérience du journal :

| Situation | Décision |
|---|---|
| Violations fortes (`RemoteArgs`, tir sans arme en main…) sur **au moins 2 sessions** différentes, ou kick (3 fortes) sur au moins 2 sessions | Candidat au bannissement : lire les détails avant |
| Une seule session avec kick | Rien tant qu'une 2e session ne le confirme ; relire le détail (un bug de notre client peut sortir comme forte, voir « Classer les violations ») |
| Violations moyennes seules (ligne de vue, origine, noclip, vol, téléport refusé) | Pas de ban : faux positifs au ping, au surf, sur une arête. Seulement avec des fortes en plus |
| Un contrôle en mode `log` isolé (tableau ci-dessous) | **Jamais** : c'est en mesure, le tir ou le déplacement est passé |
| Violations faibles, débit, « flick suspect », statistiques d'aimbot (A1) | **Jamais** : fréquent chez les joueurs honnêtes, aucune preuve |
| Même détail forgé répété d'une session à l'autre (même remote, même argument impossible) | Preuve forte d'un exécuteur : ban justifié |

Les contrôles livrés et leur mode, pour savoir ce qu'une ligne du journal prouve (état du code, constantes
`ShotRules.MODES`, `CharacterSyncRules.ENFORCE_MOVEMENT`, `MovementGuardRules.ENFORCE_*`) :

| Parade | Mode | Lecture au journal |
|---|---|---|
| Seau de distance (#172) | `block` (`ENFORCE_MOVEMENT = true`) | Refus corrigé : un téléport franc est déjà arrêté, un gros ping aussi peut en produire |
| Tir : `shape`, `distance` (#174) | `block` | `shape` : client forgé quasi certain ; `distance` : tir refusé |
| Tir : `origin`, `direction`, `lineOfSight` (#174), `ping` (#214, tir et mêlée) | `log` | Tir accepté (sauf au-delà de 250 studs) : **indice seulement**, jamais une base de ban seule |
| Equip et chargeur (#175, #215) | `block` | Touche ou `ShotFired` refusé ; un paquet en retard peut coûter une touche honnête |
| Touche sans tir rattaché (#216, `shotLink`) | `log` | Touche appliquée : **indice seulement** (un `ShotFired` écarté par le relais en produit) |
| Mêlée orientation et ligne de vue (#176, M1) | `log` (`ShotRules.MODES` : `orientation`, `meleeLineOfSight`) | Coup appliqué : **indice seulement** |
| Statistiques de visée (#178, A1) | journal seul (aucun mode `block`) | Indice pour revue humaine, **jamais** une base de ban |
| Noclip et vol (#177) | `log` (`ENFORCE_NOCLIP = ENFORCE_FLIGHT = false`) | Indice seulement |
| Vide (#177) | actif (`ENFORCE_VOID = true`) | Joueur silencieux au-dessus du vide déclaré tombé |

#### Bannir dans le Creator Hub

Le libellé exact des menus n'est pas vérifié ici : il change, à confirmer à l'écran.

1. Ouvrir le Creator Hub (create.roblox.com), l'expérience concernée, puis son espace de **modération des
   utilisateurs / bannissements** (menu de modération de l'expérience, libellé à vérifier).
2. Ajouter un bannissement par **UserId** (pas par nom d'utilisateur).
3. Choisir la durée, renseigner la **raison privée** (visible des seuls modérateurs, pas du joueur), éventuellement
   une raison affichée au joueur ; vérifier dans la doc officielle de `Players:BanAsync` ce que gèrent les deux champs
   (`DisplayReason`, `PrivateReason`) et l'option des comptes secondaires (`ExcludeAltAccounts`), dont l'équivalent
   dans l'interface est à confirmer.
4. Durées recommandées : **1 jour** à la première sanction, **7 jours** à la récidive, **définitif** à la troisième
   ou d'emblée pour une preuve nette d'exécuteur (même détail forgé sur plusieurs sessions).
5. Raison privée explicite, format : `anticheat #179 | UserId | dates des sessions | catégorie et contrôle | détail
   copié du résumé | lien du message du webhook`. Elle doit permettre à quelqu'un d'autre de rejuger sans nous.
6. Un bannissement ne se fait jamais depuis Studio ni sur une trace de Studio.

**Lever un bannissement** : même espace du Creator Hub, retrouver le joueur par UserId, révoquer le bannissement
(libellé à vérifier). Lever sans attendre si le joueur conteste et que le détail du journal ne prouve rien (cas
moyen ou `log` seul, bug de notre client). Noter la levée à la suite de la raison privée ou dans le salon du webhook.
Après une levée due à un faux positif, relever la tolérance en cause (voir « Passer un contrôle en `block` »).

#### À faire plus tard

Rien de ci-dessous n'est codé ; l'issue #179 reste ouverte pour cela.

- **`Players:BanAsync` automatique**, avec `ApplyToUniverse` et la détection des comptes secondaires
  (`ExcludeAltAccounts = false`), durées croissantes 1 jour, 7 jours, définitif.
- **Cumul entre sessions** (DataStore ou MemoryStore) du nombre de violations fortes par UserId : prérequis, car
  aujourd'hui le journal est par session.
- **Conditions de déclenchement** : (1) plusieurs semaines de journal en production, pour connaître le taux de fortes
  chez les joueurs honnêtes (il doit être nul ou expliqué) ; (2) seulement des violations fortes, sur au moins 2
  sessions ; (3) jamais en Studio ni sur les statistiques d'aimbot ; (4) raison privée écrite automatiquement avec
  le détail ; (5) procédure de levée testée ; (6) le premier mois, bannissement proposé au webhook et validé à la
  main plutôt qu'appliqué.

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

### 1. Anti-triche : journal des violations et garde des remotes — P1 (fait, #170)

- **Résumé.** Module `CheatLog` (violations, score décroissant, résumé au départ) et module pur `RemoteGuard` (seau à
  jetons par joueur et remote, vérifications de type). Branché sur tous les remotes C→S de l'inventaire.
- **Critères.** Tous les `OnServerEvent`/`OnServerInvoke` passent par `RemoteGuard` ; un argument de type impossible est
  journalisé « fort » ; kick à 3 violations fortes ; bots et Studio sans sanction ; tests Lune du seau et des types.
- **Dépendances.** Aucune. **Priorité.** P1 (socle des suivantes).

### 2. Corriger le contournement du délai de réapparition et le spam du feedback — P1 (fait, #171)

- **Résumé.** Les deux failles de R1.
- **Critères.** `RequestSpawn` refusé moins de `RESPAWN_DELAY` après la mort pendant un round actif ; la réapparition
  programmée ne remplace jamais un personnage vivant ; un seul chargement en vol par joueur ; `SendFeedback` limité en
  mémoire avant tout accès DataStore, quel que soit le résultat ; tests.
- **Dépendances.** Peut se faire avant 1 (correctif autonome), journalisation branchée ensuite. **Priorité.** P1.

### 3. Déplacement : seau de distance, durée de silence plafonnée, correction serveur — P1 (fait, #172)

- **Résumé.** D1 : remplacer le minimum par paquet par un seau qui fuit, plafonner le temps de silence, renvoyer le
  client à sa dernière position acceptée après un refus.
- **Critères.** Plus de ~300 studs/s soutenus (450 depuis #212, client plafonné à 420 horizontaux), plus de téléportation après silence ; correction appliquée par
  `MovementController` (vitesse nulle) ; surf à 200+ studs/s et bhop sans refus en jeu (test utilisateur) ;
  tests Lune de `CharacterSyncRules` (paquets groupés, silence, rafale légitime) ; bots non concernés.
- **Dépendances.** 1 pour journaliser. **Priorité.** P1.

### 4. Historique des positions serveur (rembobinage) — P1

- **Résumé.** Tampon par personnage (joueurs et bots) des positions acceptées, horodatées serveur, une seconde ;
  fonction pure `sampleAt(t)` bornée à `[now - MAX_REWIND, now]`.
- **Critères.** Alimenté par `CharacterSync` et `relayBot` ; nettoyé à la mort et au départ (pas de fuite, cf.
  `docs/performance.md`) ; tests Lune (interpolation, bornes).
- **Dépendances.** Aucune. **Priorité.** P1 (préalable de 5 et 7).

### 5. Tir : origine, direction, ligne de vue et distance validées par le serveur — P1 (fait, #174)

- **Résumé.** T1 : le client envoie origine, direction, point d'impact et instant du tir ; le serveur vérifie origine,
  direction contre la cible rembobinée, ligne de vue sur la map, distance.
- **Critères.** Un tir sur une cible non visée ou derrière un mur est refusé ; journal seul pendant une phase de mesure,
  puis bloquant ; tirs des bots inchangés (test) ; tolérances documentées ici ; décider la portée (250 vs 2 048).
- **Dépendances.** 4 ; 1 pour journaliser. **Priorité.** P1.

### 6. Tir : durée d'equip et chargeur vérifiés par le serveur — P2 (fait, #175)

- **Résumé.** T2 : `equippedAt` noté à l'arrivée de l'outil, touche refusée avant `EquipTime` ; compteur de chargeur
  serveur et rechargement de `ReloadTime` déclenché par l'action `Reload`.
- **Critères.** Tir pendant l'equip refusé (volet serveur de #159) ; 6e tir sans rechargement refusé ; bots exclus ou
  branchés sur le même point d'entrée, sans tir refusé ; tests `Validator.spec.luau`.
- **Dépendances.** #165 (réserve illimitée : seul le chargeur est suivi), #159 (volet client). **Priorité.** P2.

### 7. Mêlée : orientation et ligne de vue — P2 (fait, #176 : journal seul, voir M1)

- **Résumé.** M1 : angle horizontal entre le cap du tireur et la cible, raycast racine → racine sur la map, cible
  rembobinée.
- **Critères.** Coup dans le dos du tireur ou à travers un mur refusé ; coups légitimes en mouvement acceptés (test en
  jeu) ; bots inchangés ; tests.
- **Dépendances.** 4. **Priorité.** P2.

### 8. Déplacement : noclip et vol — P2 (fait en journal seul, #177)

- **Résumé.** D2 : raycast `lastPos → newPos`, suivi du temps sans support et de la gravité, chute dans le vide sans
  paquet.
- **Critères.** Traverser un mur ou flotter est refusé et corrigé ; surf, échelles, boosts, lancement depuis le soleil sans
  faux positif (journal seul d'abord, puis test utilisateur) ; coût mesuré avec la sonde `ServerPerf`.
- **Dépendances.** 3 (correction). **Priorité.** P2.

### 9. Relais des tirs aux autres clients sur tirs validés seulement — P2 (fait, #156)

- **Résumé.** Pas d'issue séparée : contrainte ajoutée à #156. Le relais part d'un tir accepté par le serveur
  (cadence, munitions, equip), jamais de l'action visuelle `WeaponAction` du client ; `hearShot` des bots aussi.
  Fait : remote `ShotFired`, voir « Relais des tirs » dans « Remotes ». Suite (#215, #216, fait) : chaque `ShotFired`
  accepté compté dans le chargeur, recul 3P posé par le relais, touche rattachée à son tir par `shotTime` (voir
  « Tirs comptés et touches rattachées » en T2). Puis `shotTime` et `hitTime` bornés par le ping (#214) et pose rembobinée (#213), faits, voir T1 et M1.
- **Dépendances.** 6 de préférence. **Priorité.** suit #156.

### 10. Statistiques de visée (aimbot) — P3 (fait, #178 : journal seul, voir A1)

- **Résumé.** A1 : taux de tirs à la tête, taux de touches, flicks (cap de `CharacterSync` contre la direction du tir,
  le pitch n'a pas été ajouté) suivis d'une touche.
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

**Auto-bhop désactivable (#255).** Le réglage `autoBhop` est purement client : il ne retire que des sauts forcés. Les validations serveur (vitesse, saut borné, enveloppe) portent sur la position et la vitesse déclarées, jamais sur le déclenchement du saut : désactiver l'auto-bhop ne lève aucune violation et aucune règle n'en dépend.

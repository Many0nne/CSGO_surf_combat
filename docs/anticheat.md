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
| Mêlée | Cible = autre participant vivant, arme de mêlée réellement en main, distance des racines ≤ 10 studs, dégâts et cadence lus dans `WeaponConfig` selon le type d'attaque, backstab recalculé sur les positions serveur (#47) ; pour un joueur, durée d'equip (#175, voir T2) | `src/server/Validator.luau` (`authorizeMelee`) |
| Tir | Cible valide (vivante), arme à distance en main, partie touchée appartenant à la cible, distance des racines ≤ `Validator.MAX_HITSCAN_RANGE` (~2 196 studs ; bots : 250), cadence `FireDelay` à 0,15 s près, dégâts calculés par le serveur selon la zone ; pour un joueur, forme, origine, visée sur la cible rembobinée, portée et ligne de vue (#174, voir T1), durée d'equip et chargeur (#175, voir T2 ; l'equip vaut aussi pour la mêlée) | `src/server/Validator.luau` (`authorizeHitscan`, `validateShot`), `src/server/ShotRules.luau` |
| Position | Forme (Vector3 et angle finis, coordonnées ≤ 1e5), personnage vivant, seau de distance (300 studs/s soutenus, silence plafonné), refus journalisé et corrigé (#172) ; noclip et vol journalisés (#177, journal seul), joueur silencieux au-dessus du vide déclaré tombé | `src/server/CharacterSync.luau:186-275`, `src/shared/CharacterSyncRules.luau:49-60`, `src/shared/MovementGuardRules.luau` |
| Réglages | Réglages entièrement assainis par `PlayerSettings.sanitize`, une écriture DataStore au plus toutes les 10 s | `src/server/SettingsStore.luau:113-130` |
| Feedback | Type `string`, longueur 10 à 500, délai de 60 s après un envoi réussi, 5 envois par semaine (DataStore) | `src/server/FeedbackService.luau:76-104` |
| Debug | Remote `DebugPlaytest` créé seulement dans Studio | `src/server/DebugPlaytest.luau:365-372` |
| Tous les remotes C→S | Garde commune (#170) : débit par joueur et par remote, types des arguments, violations journalisées, kick à 3 violations fortes | `src/server/RemoteGuard.luau`, `src/server/CheatLog.luau` |

Les bots (`src/server/bots/`) passent par le même `Validator` (`BotManager.init` dans `src/server/init.server.luau`) : leurs tirs sont
des raycasts serveur (`src/server/bots/BotArsenal.luau:184`), leurs munitions et leur temps de sortie sont gérés par
`BotArsenal` (`:110`, `:116-122`, `:142-148`). Toute nouvelle parade doit donc soit valoir aussi pour eux sans les gêner,
soit être réservée aux joueurs (`participant.isBot`), ce qui est indiqué pour chaque parade.

## Classement des menaces

Impact : ce que gagne le tricheur et ce que subissent les autres. Coût : serveur, réseau et complexité de la parade.

| # | Menace | Impact aujourd'hui | Coût de la parade | Priorité |
|---|---|---|---|---|
| T1 | Tir sans viser, à travers les murs, hitbox agrandie (« silent aim ») | **Critique** : un tir accepté par cible à 250 studs, 1 par 1,46 s, tête choisie (460 dégâts) | Faible serveur, moyen en complexité | P1 |
| D1 | Vitesse et téléportation | Fermé (#172) : 300 studs/s soutenus au plus, saut borné à 225 studs après un silence, refus corrigé | Faible | Fait |
| M1 | Coup de couteau dans toutes les directions (« kill aura ») | **Élevé** : one-shot de dos à 10 studs, cumulable avec D1 | Faible | P2 |
| R1 | Remotes sans débit ni garde (respawn, feedback) | Fermé (#170, #171) : garde commune, délai de réapparition et feedback limité en mémoire | Faible | Fait |
| T2 | Munitions et durée d'equip | Fermé (#175) : touche refusée pendant l'equip et au 6e tir sans rechargement | Faible | Fait |
| D2 | Vol et noclip | Détecté (#177) : noclip et vol au journal (journal seul), vide fermé | Faible serveur, moyen en réglage (surf) | Fait (journal) |
| A1 | Aimbot, triggerbot | **Élevé** mais seulement détectable | Moyen, faux positifs | P3 |
| E1 | Wallhack, ESP | **Élevé** mais non bloquable à coût raisonnable | Très élevé | P4 (accepté) |

Les sections suivantes détaillent chaque menace : ce que fait le code, le risque, la parade, son coût et son impact.

## Tir

### T1. Ligne de vue, direction, distance, compensation de latence

**Avant #174.** Le client faisait le raycast depuis la caméra et envoyait seulement `(targetChar, hitPart)` ; le
serveur vérifiait la cible, l'arme, l'appartenance de la partie et la distance des racines, sans savoir d'où ni vers où
le tir était parti. **Fait (#174)** : la parade ci-dessous, détails dans « Tolérances et modes ».

**Risque.** Un client modifié envoie `HitscanDamage(n'importe quel ennemi, sa Head)` sans le regarder ni le voir :
l'AWP fait 115 × 4 = 460 dégâts à la tête (`src/shared/WeaponConfig.luau:13`, `src/shared/HitZones.luau:16`), donc
un mort par tir (100 PV, valeur par défaut du Humanoid), toutes les 1,46 s, sur tous les participants à moins de 250 studs, à travers les murs. Agrandir
localement les hitbox des autres (« hitbox expander ») marche aussi : le serveur ne regarde pas la géométrie.

**Parade.** Le client envoie aussi ce qu'il a tiré, et le serveur vérifie que ce tir pouvait toucher :

1. Arguments : `origin: Vector3`, `direction: Vector3` (unitaire), `hitPos: Vector3`, `shotTime: number`
   (`workspace:GetServerTimeNow()` au tir), en plus de `targetChar` et `hitPart`. Types et finitude vérifiés comme
   `CharacterSyncRules.isWellFormed`.
2. Rembobinage : le serveur garde un historique des positions acceptées de chaque personnage, une seconde à 20 Hz,
   alimenté là où elles sont posées : joueurs dans `onClientPosition` (après acceptation), bots dans `relayBot`.
   **Fait (#173)** : module pur `src/shared/PositionHistory.luau` (tampon circulaire de 35 relevés, un relevé au plus
   tous les 0,03 s soit 20 Hz nominal et 33 Hz au plus, avec marge pour la gigue et le relais des bots, horloge
   `workspace:GetServerTimeNow()`, la dernière position acceptée est toujours gardée à part ; `sampleAt(history, t, now)`
   interpole et borne `t` à `[now - MAX_REWIND, now]`, `MAX_REWIND` = 0,4 s ≤ `DURATION` = 1 s ; entre deux relevés
   distants de plus de `MAX_GAP` = 0,25 s, le plus proche est pris au lieu d'une ligne droite). Un historique par `Model` (joueurs et bots, vide à
   chaque réapparition), supprimé à `Destroying` du personnage (mort, départ, bot retiré). Point d'entrée pour #174 et
   #176 : `CharacterSync.positionAt(char, t)` (nil sans historique), aucun consommateur branché. Tests :
   `tests/specs/PositionHistory.spec.luau`.
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
| `origin` | À moins de `ORIGIN_BASE` (5) + vitesse du tireur × `ORIGIN_SPEED_FACTOR` (0,1) studs de sa racine actuelle ou de sa position à `shotTime` (borné à `[now - 0,4 s, now]`). La caméra est à 2,5 studs au-dessus de la racine | `log` | moyenne |
| `direction` | Impact sur le rayon (à `HIT_ON_RAY` = 0,5 stud près, devant l'origine) ; rayon et impact à moins de rayon englobant de la partie (`Size.Magnitude / 2`) + `DIRECTION_BASE` (2) + vitesse de la cible × `DIRECTION_SPEED_FACTOR` (0,05) de la partie rembobinée. Partie rembobinée = racine à `shotTime - INTERP_DELAY` (borné à `[now - 0,4 s, now]`) + décalage de la partie sur le rig serveur | `log` | moyenne |
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
- Point de branchement du relais aux autres clients (#156) : le handler `HitscanDamage` de `init.server.luau`, quand
  `damage` n'est pas nil (tir validé).

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
à la lecture) : la poser dans les tests (`addPart` de `Validator.spec.luau`).

**Limites connues (à traiter avant `block` si la mesure les montre).** (1) Seule la racine est rembobinée : le
décalage de la partie touchée est pris sur le rig serveur à l'arrivée du tir, pas dans la pose (accroupi, animation,
cap) que voyait le tireur ; c'est la cause probable du faux positif mesuré sur une main. Piste : garder aussi le cap
et l'état accroupi dans l'historique, ou élargir `DIRECTION_BASE` pour les membres. (2) `shotTime` est choisi par le
client dans `[now - 0,4 s, now]` : un client modifié peut viser une position de la cible jusqu'à 0,4 s en arrière
(« backtrack »). Piste : borner `now - shotTime` par la latence mesurée du joueur (RTT de `CharacterSync` ou
`Player:GetNetworkPing()`) plus une marge.

**Passer un contrôle en `block`.** 1. Laisser tourner en jeu publié en `log` (au moins quelques centaines de tirs, dont
du surf rapide et des joueurs à fort ping). 2. Lire les résumés `CheatLog` du webhook : compter les violations
`Hitscan` de joueurs honnêtes par contrôle, et relever dans les détails l'écart au maximum permis. 3. Si besoin,
élargir la tolérance en cause (`ORIGIN_*`, `DIRECTION_*`) jusqu'à ne plus en avoir, sans dépasser ce qui laisse passer
un hitbox expander utile (rester sous ~2 fois le rayon d'une tête). 4. Passer le contrôle à `"block"` dans
`ShotRules.MODES`, mettre à jour le tableau ci-dessus et le test « livre origine, direction et ligne de vue en journal
seul » (`tests/specs/Validator.spec.luau`). Les tests « mode block » couvrent déjà le refus.

### Distance (tranché, #174)

La portée du serveur est celle du client : `WeaponConfig.HITSCAN_RANGE` = 2 048 studs, tirée par `HitscanSystem` et
vérifiée par le contrôle `distance` (+ 10 studs). L'ancienne borne de 250 studs entre racines, qui refusait sans retour
un tir légitime lointain, devient pour les joueurs `Validator.MAX_HITSCAN_RANGE` ≈ 2 196 studs (portée +
`MAX_SPEED_SERVER` × `MAX_REWIND`, chemin possible de la cible pendant le rembobinage, + hauteur de caméra + 25 de
marge, calculé depuis ces constantes). Un échec `origin` ou `lineOfSight` au-delà de 250 studs reste refusé pendant la
mesure (`LOG_ONLY_RANGE`, voir plus haut). Les bots gardent 250 studs (`BOT_HITSCAN_RANGE`, tirs inchangés) : ils
visent à 240 au plus (`src/shared/BotConfig.luau`), mais leur rayon serveur porte à 2 048 studs (`BotArsenal.MAX_RAY`)
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
| `magazine` | Arme à `Magazine` : touches **acceptées** comptées par participant et par arme ; la `Magazine`+1e est refusée sans rechargement fini, et toute touche est refusée pendant un rechargement qui n'a pas encore duré `ReloadTime - RELOAD_TOLERANCE` (0,2 s). Début du rechargement : action `Reload` du remote `WeaponAction` (`Validator.noteReload`), lue avant les filtres de la pose 3P (intervalle de 0,05 s, modèle 3P attaché) qui pourraient écarter une action honnête | `block` | moyenne |

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
  suivant. Un tricheur n'y gagne rien (ressortir l'AWP coûte 1,38 s d'equip au moins). Seules les touches sont comptées (les tirs manqués n'arrivent pas au
  serveur) : le compteur serveur est toujours ≤ celui du client, jamais plus strict.
- **Bots.** Exclus des deux contrôles (`attacker.isBot`) : `BotArsenal` fait déjà respecter equip, chargeur et
  rechargement, et ses tirs sont des raycasts serveur. Leur equip n'est pas noté (`trackWeapon3P`) : rien à retenir, et
  `BotManager` ne rappelle pas `Validator.forget` au retrait d'un bot. Tests : 12 tirs de bot d'affilée et tir dès la
  sortie acceptés.
- **Ordre.** Les contrôles T1 (`validateShot`) passent avant equip et chargeur, et tous sont évalués : un tir refusé
  pour l'equip garde ses violations d'origine ou de ligne de vue au journal (phase de mesure de T1).
- **Réapparition et départ.** `Validator.forget` efface cadences, equip et chargeurs ; il précède le suivi des armes du
  nouveau personnage (`onParticipantCharacter`). Un outil qui entre ou sort de l'ancien corps (ragdoll) ne touche plus
  au participant.
- **Mesure en Studio (#175, 2026-11-11).** `DebugPlaytest` AWP et M9Bayonet : PASS 9/9. Client honnête (chemin réel
  `Tool:Activate`) : 5 touches, rechargement, 3 touches, aucune ligne `[CheatLog]`. Tir forgé envoyé 0,25 s après un
  ré-equip : refusé, journalisé `Hitscan … equip : touche 0.25 s après l'equip (min 1.38 s)`. Studio sans latence : à
  surveiller dans les résumés `CheatLog` du jeu publié (catégories `Hitscan`/`Melee`, contrôles `equip` et `magazine`).
  Méthode : `workspace:SetAttribute("DebugBots", 0)` d'abord (sinon les bots tuent le joueur et la réapparition remet
  le chargeur à zéro), un run `DebugPlaytest` AWP pour équiper et viser la cible, puis en contexte `Client` une boucle
  `tool:Activate()` lancée par `task.spawn` (appels MCP courts : un `execute_luau` qui attend longtemps a figé Studio
  des heures). Espacer les clics de 2 s : `ShootAnimTime` (1,63 s) dépasse `FireDelay`, un clic à 1,6 s est ignoré
  par le client (état `FIRING`).
- **Début du rechargement borné.** Un `Reload` ne compte qu'à partir de la fin de l'equip et de la cadence du dernier
  tir accepté de l'arme (`max(arrivée, equip + EquipTime - 0,2, dernier tir + FireDelay - 0,2)`) : le client ne peut pas
  recharger avant, un client modifié qui recharge dès son tir ne gagne pas `FireDelay` (1,46 s) sur la pause.

## Mêlée

### M1. Orientation et ligne de vue

**Aujourd'hui.** #47 a réglé dégâts, cadence et arme en main (`Validator.authorizeMelee`). Restent : la distance est
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
doit les connaître (règles pures dans `src/shared/MapRules.luau`, réutilisables par le serveur). Attention : un
geyser ou un lanceur impose sa vitesse (`Velocity`) sans la borner à `MAX_SPEED_SERVER` (`MapRules.velocityAfter`), et
le lancement depuis le soleil prend l'attribut `Speed` tel quel : au-delà de 300 studs/s, le seau de D1 refuserait le
joueur. Dizzy n'a ni boost ni `SunLaunch` aujourd'hui ; une map qui en ajoute doit rester sous 300 studs/s ou relever
`MAX_SPEED_SERVER`.

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
   `MAX_SPEED_SERVER` = 300 studs/s, `MAX_DELTA_POS` = 75 studs (0,25 s mises de côté, pour la gigue et les paquets
   groupés), `MAX_SILENCE` = 0,5 s. Bornes : 300 studs/s soutenus quel que soit le débit d'envoi, saut d'un paquet
   ≤ 75 + 150 = 225 studs après n'importe quel silence. Le délai minimal de 0,025 s entre deux paquets a été retiré :
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

**Pièges.** Une correction ne doit **jamais** remplir le seau : un tricheur qui enchaîne refus et numéro forgé
gagnerait un seau plein à chaque cycle (40 cycles/s). Le numéro de correction est croissant sur toute la session du
joueur (pas remis à zéro à la réapparition) pour qu'un ancien accusé ne valide pas une correction récente.

**Réutiliser.** Une nouvelle règle de déplacement se branche dans `onClientPosition`, après le seau, et appelle
`refuse(player, track, détail, now)` (`src/server/CharacterSync.luau:186`) : journal et correction compris. C'est ce que
fait D2 (#177, `judgeGuard`) ; `refuse` repart aussi l'enveloppe du vol de la position de correction.

**Bots.** Non concernés : leurs positions viennent du serveur (`relayBot`), qui ne passe pas par le seau.

**Vérifié.** Tests `tests/specs/CharacterSyncRules.spec.luau` (300 studs/s soutenus, surf à 220 studs/s avec 80 ms de
gigue, paquets groupés, rafale à 40 Hz, tricheur borné à 20 et 40 Hz, silences, suite de refus, reprise après
correction). En jeu (Studio, latence nulle) : bhop sans refus ; un paquet forgé de 400 studs pendant une course est
refusé une fois, journalisé, corrigé, et la course reprend sans seconde correction. Reste à observer en jeu publié :
surf rapide avec un vrai ping (journal `Movement` des joueurs honnêtes).

**Impact.** Ramène le tricheur à 300 studs/s au plus et supprime la téléportation, qui est l'aide principale du kill
aura et de l'ESP actif.

### D2. Vol et noclip (fait en journal seul, #177)

**Avant #177.** Une position était acceptée si elle respectait la distance, qu'elle soit en l'air depuis 30 s ou de
l'autre côté d'un mur. La mort par chute (`KillZone`) ne testait que les positions acceptées : un client qui flotte
au-dessus du vide, ou qui n'envoie jamais de position sous `KillHeight`, ne mourait pas.

**Risque.** Moyen : rester en l'air hors d'atteinte, se cacher dans un mur, ne jamais mourir de chute.

**Parade en place.** Règles pures dans `src/shared/MovementGuardRules.luau` (testées sous Lune) ; la géométrie est
fournie par `CharacterSync` (`buildGeometry`) : rayons et requêtes limités à la map jouée (`Include`) et à ses pièces
qui collisionnent (`RespectCanCollide` : décor fantôme, volumes d'échelle et de boost exclus). Une position acceptée
par le seau (D1) passe par `MovementGuardRules.judge` (`judgeGuard`, `src/server/CharacterSync.luau:200`).

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
   reçus moins deux, marge pour le désordre), majore la vitesse actuelle (`maxVyAfter` + `REFINE_MARGIN`). **Deux
   paquets de suite** au-dessus = vol (un seul : paquet ancien arrivé après un plus récent). Après un vol signalé,
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

**Modes** (`src/shared/MovementGuardRules.luau:23-27`) : `ENFORCE_NOCLIP = false` et `ENFORCE_FLIGHT = false` : journal
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
  d'arrivée de deux paquets successifs. Le seul temps sûr côté client est l'intervalle minimal entre deux envois
  (`CharacterSync.send` reporte le reste : au moins une demi-période, quelle que soit la cadence d'images).
- En chute plafonnée (`MAX_FALL_SPEED`), une parabole ne vaut plus : une borne de vitesse déduite d'une parabole doit
  être ramenée à `-MAX_FALL_SPEED` au plus bas.
- Raycasts `Include` sur la map et `RespectCanCollide` : un client honnête collisionne aussi avec les pièces `CanQuery`
  sans collision ; le serveur, plus permissif, ne s'en plaint pas.
- Vérifier en Studio : un paquet forgé s'envoie en contexte Client avec un numéro de correction élevé
  (`CharacterSync:FireServer(pos, 0, 1000)`) ; un client figé s'obtient avec
  `RunService:UnbindFromRenderStep("MovementStep")` (plus de mouvement ni d'envoi) ; une apparition à un endroit choisi,
  en déplaçant les points de `Maps.Dizzy.GroundSpawns` pendant le Play.

**Coût** (sonde `PerfServer`, Studio, 1 joueur, Dizzy, 5 bots) : repère `srv anti-vol` 0,01 à 0,07 ms/frame à 20
paquets/s (0,1 à 0,4 ms par paquet au pire, un pic à 0,85 ms), `srv vide` 0,001 ms/frame. Quelques dixièmes de ms par
frame à pleine partie.

**Vérifié.** Tests `tests/specs/MovementGuardRules.spec.luau` : traversée d'un mur, chute à travers un sol, virage
serré autour d'un coin à 100 studs/s, arête de rampe à 300 studs/s, saut, 10 s de bhop avec 80 ms de gigue, chute de
300 studs, bhop et chute à 15/30/45/144 FPS sur 10 graines de gigue, surf sur une rampe à 60° puis sortie à 130 studs/s
vers le haut, échelle (et la même montée sans échelle signalée), geyser, lancement depuis le soleil au premier paquet
tardif, vol stationnaire, descente lente, les deux modes (journal seul, bloquant sans boucle de corrections), vide. En
jeu (Studio, latence nulle) : bhop et strafes, montée à l'échelle jusqu'au toit sans violation ; client figé au-dessus
du vide déclaré tombé après 2,1 s ; paquet forgé à travers un mur journalisé (`noclip`, puis le retour du vrai client),
refusé et corrigé une seule fois en mode bloquant ; vol stationnaire forgé journalisé (`vol`). Non vérifié en jeu :
surf (Dizzy n'a pas de rampe de surf), boosts et lancement depuis le soleil (absents de Dizzy), vrai ping.

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
| `MeleeDamage` | C→S | `targetChar, attackKind` | Cible, arme, portée, type d'attaque, cadence, dégâts serveur, durée d'equip (T2, #175) (`Validator.authorizeMelee`) | Orientation, ligne de vue (M1), tireur vivant |
| `HitscanDamage` | C→S | `targetChar, hitPart, origin, direction, hitPos, shotTime` | Cible, arme, partie de la cible, portée des racines, cadence ; forme, origine, visée rembobinée, portée 2 048, ligne de vue (T1, #174 : origine, visée et ligne de vue en journal seul) ; durée d'equip et chargeur (T2, #175) | Passage en `block` après mesure (T1), tireur vivant |
| `CharacterSync` (non fiable) | C→S puis S→C | `pos, yaw, ack` | Forme, débit 40 Hz (garde), seau de distance et silence plafonné, refus corrigé (D1, `CharacterSync.luau:113-165`) | Noclip, vol (D2) |
| `MovementCorrection` | S→C | `char, pos, seq` | — | — |
| `WeaponAction` | C→S | `action` | Valeur `Shoot`/`Reload`, outil en main, 0,05 s mini (`init.server.luau`) ; `Reload` démarre le rechargement suivi par le serveur avant ces filtres (T2, #175) | `Shoot` non lié à la cadence de l'arme : 20 faux tirs/s attirent les bots (`BotManager.hearShot` dans le handler `WeaponAction`) et, avec #156, déclencheraient 20 sons chez tous |
| `RequestSpawn` | C→S | aucun | `SpawnRules.request` : spawn en vol, personnage en place, bannière de fin, mort depuis moins de `RESPAWN_DELAY` en round actif (`SpawnManager.luau:137-169`) | Rien (R1 fermé, #171) |
| `SendFeedback` | C→S | `text` | Type, longueur, 60 s en mémoire après toute demande valide (posé avant le DataStore, quel que soit le résultat), 5 par semaine (`UpdateAsync`), rien d'écrit si la lecture échoue (`FeedbackService.luau:113-150`) | Rien (R1 fermé, #171) |
| `SaveSettings` | C→S | table | `PlayerSettings.sanitize`, écriture différée de 10 s (`SettingsStore.luau:113-130`) | Débit (coût CPU seulement, faible) |
| `GetSettings` (RemoteFunction) | C→S | aucun | Attend le chargement, 20 s au plus (`SettingsStore.luau:101-109`) | Appels simultanés non bornés pendant le chargement (fils qui attendent) |
| `DebugPlaytest` | C→S | `id, ok, detail, data` | Studio seulement, id attendu et propriétaire (`DebugPlaytest.luau:365-378`) | Rien en jeu publié |
| `HitConfirm`, `RoundState`, `ScoreUpdate`, `RoundResult`, `PlayerDied`, `FeedbackAck` | S→C | — | — | `PlayerDied` donne la position de la victime à tous (`RoundManager.luau:162-173`) : sans effet tant que l'ESP est accepté (E1) |

### R1. Garde commune et failles constatées

**Respawn (fait, #171).** Avant : le personnage mort est détruit 0,3 s après la mort (`CORPSE_HANDOFF_DELAY`,
`init.server.luau`) et `canSpawn` ne testait que `player.Character.Parent` ; un client modifié qui envoyait
`RequestSpawn` après 0,3 s réapparaissait tout de suite au lieu d'attendre `RESPAWN_DELAY` = 2,5 s
(`src/shared/GameConfig.luau:5`), puis la réapparition programmée (`RoundManager.onCharacterDied`) remplaçait son
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
- les bots ne passent pas par là : `BotManager` gère leur réapparition (`diedAt` + `RESPAWN_DELAY`) et leur passe un
  rappel vide.

Le futur bouton de retour au menu (#157) devra en tenir compte : un mort qui revient au menu et clique Play avant
`RESPAWN_DELAY` est refusé (et journalisé `early`) ; la réapparition programmée le fait de toute façon revenir.

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
`MeleeDamage` 5/5 (couteau : 2,5/s au plus), `HitscanDamage` 5/5 (AWP : 0,7/s), `WeaponAction` 8/8 (un `Shoot` par tir
ou coup, un `Reload`), `CharacterSync` 40/60 (20 Hz, 3 s de paquets groupés après une coupure), `RequestSpawn` 1/3,
`SendFeedback` 0,5/3, `SaveSettings` 2/5 (1 envoi/s au plus), `GetSettings` 0,2/3 (une demande au démarrage ; borne
aussi les demandes en attente du chargement). **Une nouvelle arme plus rapide (automatique) demande de relever
`HitscanDamage` et `WeaponAction`**, et un nouveau remote C→S doit avoir sa règle (sinon tout appel est refusé, sans
violation, avec un warn `remote sans règle`) et un cas dans le test « accepte les appels de notre client ». Un appel
arrivé après le départ du joueur (`player.Parent` nil, ex. juste après un kick) est ignoré sans rien recréer.
Roblox limite déjà le débit client → serveur par type de remote, mais globalement, et sans le dire au jeu : la limite
par remote est à faire soi-même ([Remote events](https://create.roblox.com/docs/scripting/events/remote),
[Rate limiter module](https://devforum.roblox.com/t/rate-limiter-module-for-remotes/616268)).

**`WeaponAction`.** Ne relayer (#156) et ne faire entendre aux bots que des tirs acceptés par le serveur : brancher le
relais du son sur `Validator.authorizeHitscan` (et sur un tir « dans le vide » validé : cadence, munitions, equip), pas
sur l'action visuelle du client.

**Coût.** Négligeable. **Impact.** Ferme deux failles réelles et donne le point d'entrée commun de la journalisation.

## Aimbot et triggerbot (A1)

**Aujourd'hui.** Rien. Le serveur ne connaît pas l'orientation verticale de la caméra (seul le cap est envoyé,
`src/client/systems/network/CharacterSync.luau:120-127`).

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
  (`src/server/CharacterSync.luau:158-163`, `:197`) ;
- le serveur pose la racine de chaque personnage (`:155`), propriété répliquée nativement à tous les clients ;
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

### Journaliser (fait, #170)

Module serveur `src/server/CheatLog.luau` (testé par `tests/specs/CheatLog.spec.luau`). API pour les parades :

```lua
CheatLog.report(participant, CheatLog.Category.MOVEMENT, CheatLog.Severity.MEDIUM, "téléport de 300 studs", source?)
CheatLog.admit(player, NetworkProtocol.Names.X, ...) -- garde des remotes : true si le handler peut continuer
CheatLog.summary(participant.id) -- bilan (compteurs, score présent, pire violation), nil sans violation
```

- **Gravités** (`CheatLog.Severity`) : `LOW`, `MEDIUM`, `HIGH`, au sens de « Classer les violations » ci-dessous.
- **Catégories** (`CheatLog.Category`) : `RemoteRate`, `RemoteArgs` (garde des remotes), et réservées aux parades
  suivantes : `Spawn` (#171, branchée : refus de `RequestSpawn`), `Movement` (#172), `Hitscan` (#174, branchée : contrôles du tir ; #175 : equip et chargeur), `Melee` (#175, branchée : equip du couteau ; #176). Une nouvelle parade
  ajoute sa catégorie à `CheatLog.Category` et ici, pour garder des noms stables dans le journal.
- `warn` `[CheatLog]` limité à un toutes les `WARN_INTERVAL` (2 s) par joueur, le suivant dit combien ont été tus ;
  détail coupé à `MAX_DETAIL` octets sans couper de caractère, octets non UTF-8 remplacés par `?` (il peut contenir une
  valeur forgée par le client, et `HttpService:JSONEncode` du webhook échoue sur du texte non UTF-8).
- Compteurs par joueur, catégorie et gravité ; score en seau qui fuit (poids `SCORE_WEIGHT` : 1, 5, 20 ; décroissance
  `SCORE_DECAY` = 1 point/s), score maximal gardé au bilan. Le kick sur score moyen n'est pas branché (voir « Kick »).
- Kick (`player:Kick`) à `KICK_HIGH_COUNT` = 3 violations fortes dans la session, une seule fois. Une même source
  (5e argument `source` de `report`, le remote pour la garde, la catégorie par défaut) ne compte qu'une violation forte
  par `HIGH_SOURCE_INTERVAL` (1 s) : un bug de notre client sur un remote à 20 Hz (position NaN) laisse le temps de
  le voir au journal au lieu d'expulser en 150 ms. Toutes restent comptées au journal et au score.
- Au départ d'un joueur qui a une violation moyenne ou forte, ou au moins `SUMMARY_MIN_LOW` (10) violations faibles
  (en dessous, une rafale réseau ne fait pas de bruit au webhook) : résumé (nom, UserId, compteurs par catégorie,
  score max, pire violation, kick) posté au webhook en jeu publié, par `src/server/Webhook.luau` (mécanisme de `FeedbackService`) :
  StringValue `CheatLogWebhookUrl` dans ServerScriptService, sinon `FeedbackWebhookUrl`. Pas de cumul entre sessions
  (DataStore/MemoryStore) : il relève du bannissement (#179). À l'arrêt du serveur, les résumés des joueurs encore là sont envoyés
  et attendus (`CLOSE_TIMEOUT`, 20 s). Une violation signalée pour un joueur déjà parti est ignorée.
- Bots ignorés (`participant.isBot`) ; Studio : journal seulement (aucun kick, résumé affiché en console au lieu du
  webhook).

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

### 7. Mêlée : orientation et ligne de vue — P2

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

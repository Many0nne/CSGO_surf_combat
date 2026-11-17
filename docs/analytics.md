# Analytics (#527)

Savoir à quelle étape les joueurs décrochent (ils quittent le jeu) ou restent bloqués, avec les tableaux de bord de
Roblox (`AnalyticsService`, Creator Hub), sans service externe. Le gameplay ne change pas d'après ces données dans la
même tâche : une issue par correction, une fois les premières données collectées.

## Architecture

| Rôle | Fichier |
|---|---|
| Seul appelant de `AnalyticsService` : état de chaque joueur, funnels, économie, événements | `src/server/analytics/Analytics.luau` |
| Constantes : écrans, étapes, noms d'événements et de champs, classes bornées (pur, testé) | `src/shared/AnalyticsRules.luau` |
| Écran courant du client, relevé toutes les 0,5 s, envoyé au changement | `src/client/systems/analytics/AnalyticsClient.luau` |
| Branchement (remote, rappels, morts, manches, départs) | `src/server/init.server.luau` |
| Tests (faux `AnalyticsService`, horloge simulée) | `tests/specs/Analytics.spec.luau` |

- **Le client ne décide rien.** Il signale seulement son écran (remote `AnalyticsScreen`, une valeur de
  `AnalyticsRules.SCREENS`, garde `RemoteGuard` : énumération, 3/s, rafale 6). Funnels, durées et événements sont tirés
  par le serveur de cet écran et de ce qu'il sait déjà (apparition, tirs acceptés, dégâts, morts, achats, reçus). Un
  client modifié ne peut que fausser ses propres étapes de menu, pas l'économie ni les étapes de partie.
- **Studio n'envoie rien** : `init.server` ne donne pas le service au module, qui écrit chaque envoi en console
  (`[Analytics] <joueur> funnel Session 2 Menu`, `[Analytics] <joueur> événement Mort = 1 [B3, chute]`…). Playtests et
  `DebugPlaytest` restent donc hors des tableaux de bord, et ces lignes servent à vérifier un branchement.
- **Jamais d'erreur dans le jeu** : chaque point d'entrée est sous `pcall` ; un appel refusé par `AnalyticsService`
  (limite de débit, argument) est signalé une fois par méthode (`[Analytics] LogFunnelStepEvent refusé : …`).
- **Cardinalité** : aucun identifiant libre ni position brute dans les champs. Valeurs possibles : écrans (11), zones de
  la map (16), causes de mort (3), classes de manches (5), ancienneté (3), ids de caisses et de packs (quelques-uns).
  Trois champs au plus par événement (`CustomField01..03`).

## Écrans signalés par le client

`loading` (écran de chargement), `playing` (en partie : arrivée, vivant, mort ou bannière, précisé par le serveur),
`menu_home`, `menu_shop`, `menu_infos`, `menu_learn`, `menu_settings`, `menu_feedback`, `shop_detail` (détail d'une
caisse), `crate_opening` (animation d'ouverture), `credit_packs` (fenêtre des packs Robux). Composés dans
`init.client` (`LoadingScreen.isCovering`, `GameStateController.getState`, `ShopScreen.analyticsScreen`,
`MainMenu.getPage`). Un écran tenu moins de 0,5 s peut ne pas être vu.

## Funnels

Une étape n'est envoyée qu'une fois par funnel (par session, par visite du shop). Les tableaux de bord comptent les
joueurs (ou sessions) qui ont atteint chaque étape : la chute d'une étape à la suivante montre où l'on décroche.

### Onboarding (`LogOnboardingFunnelStepEvent`)

Seulement pour un **nouveau joueur** : aucune statistique enregistrée au chargement (`StatsStore.isNewcomer`). Les étapes
atteintes avant la fin du chargement sont gardées puis envoyées dans l'ordre ; rien pour un habitué, ni si le
chargement échoue, ni sur un serveur d'entraînement. Un joueur dont la visite n'a rien enregistré dans ses
statistiques (ni kill ni mort comptés, aucune manche finie ; une mort par un bot ne compte pas, une chute oui) est encore
« nouveau » à sa visite suivante ; ses étapes déjà atteintes sont alors renvoyées.

| Étape | Nom | Émise par |
|---|---|---|
| 1 | Chargement terminé | premier écran autre que `loading` (`Analytics.screen`) |
| 2 | Menu affiché | premier écran du menu |
| 3 | Clic sur JOUER | passage d'un écran du menu à `playing` (l'enchaînement des manches reste en `playing`) |
| 4 | Premier spawn | personnage gardé (`onCharacterAdded`, `Analytics.spawned`) |
| 5 | Premier tir | `ShotFired` relayé, ou coup de couteau (`WeaponAction` Shoot) |
| 6 | Premier dégât infligé | touche qui fait baisser des PV (`onHitVerdict`) |
| 7 | Premier kill | tueur joueur d'une mort comptée (`onDeathCounted`) |
| 8 | Première mort | victime joueur d'une mort comptée |
| 9 | Première manche finie | `onRoundEnd` de `RoundManager`, joueur en jeu |
| 10 | Deuxième manche commencée | apparition après une manche finie |

### Session (`LogFunnelStepEvent`, funnel `Session`)

Un `funnelSessionId` par visite (GUID à l'arrivée).

| Étape | Nom | Émise par |
|---|---|---|
| 1 | Arrivée | `PlayerAdded` |
| 2 | Menu | premier écran du menu |
| 3 | En partie | première apparition |
| 4 | 1 manche jouée | première fin de manche |
| 5 | 3 manches jouées | troisième fin de manche |
| 6 | Retour au menu | `LeaveRound` (MENU PRINCIPAL du menu en partie) |
| 7 | Départ | `PlayerRemoving` |

### Shop (funnel `Shop`)

Une visite = entrée dans un écran du shop depuis un autre écran (onglet, détail, ouverture, packs) ; l'ouverture et le
retour au détail restent dans la visite.

| Étape | Nom | Émise par |
|---|---|---|
| 1 | Onglet SHOP | entrée dans le shop |
| 2 | Détail d'une caisse | écran `shop_detail` |
| 3 | ACHETER | toute demande `BuyCrate` traitée (refus compris : solde insuffisant, restreint…) |
| 4 | Caisse ouverte | achat réussi (`CrateService.init`, rappel `onBought`) |
| 5 | Skin équipé | `EquipItem` accepté d'un skin obtenu par une caisse achetée pendant la session (rappel de `InventoryStore.init`), compté dans la visite de l'achat |

### Packs Robux (funnel `PacksRobux`)

Une visite = une ouverture de la fenêtre des packs. Champ 1 des étapes 2 et 3 : id du pack.

| Étape | Nom | Émise par |
|---|---|---|
| 1 | Packs affichés | écran `credit_packs` |
| 2 | Prompt d'achat | prompt Roblox ouvert par le serveur (`ReceiptService`, rappel `onPrompted`) |
| 3 | Reçu traité | crédits d'un reçu écrits (`ReceiptService.handle`, rappel `onCredited` ; pas un reçu rejoué) |

## Économie (`LogEconomyEvent`, monnaie `Credits`)

| Flux | Type de transaction | Objet (SKU) | Émis par |
|---|---|---|---|
| Source | `Gameplay` | `jeu` | gain en jouant crédité (kill, manche, victoire ; `CreditGains`, dépendance `credit` de `init.server`) |
| Source | `IAP` | id du pack | crédits d'un reçu écrits |
| Sink | `Shop` | id de la caisse | achat de caisse réussi (prix) |
| Source | `Shop` | id de la caisse | remboursement d'un doublon tiré |

Solde final : `WalletStore.balance` après l'opération (pour la dépense d'une caisse remboursée : solde final moins le
remboursement, le flux réel étant débit puis remboursement).

## Événements personnalisés (`LogCustomEvent`)

| Événement | Valeur | Champ 1 | Champ 2 | Champ 3 |
|---|---|---|---|---|
| `Depart` | durée de la session (s) | endroit au départ | manches jouées (`0`, `1`, `2-3`, `4-9`, `10+`) | ancienneté (`nouveau`, `habitue`, `inconnu`) |
| `TempsEcran` | temps sur l'écran quitté (s), ≥ 2 s, 100 par session au plus | écran (`partie_<phase>` en partie) | | |
| `MenuAvantJouer` | temps entre la première arrivée au menu et le premier clic sur JOUER (s), une fois | ancienneté | | |
| `MortsSansKill` | longueur de la série, aux paliers 3, 5 et 10 | ancienneté | | |
| `Mort` | 1 | zone de la map (`A1`…`D4`) | cause (`chute`, `bot`, `joueur`) | |

- **Endroit au départ** : l'écran du client, ou en partie `partie_arrivee` (apparition en cours, retour au menu),
  `partie_vivant`, `partie_mort`, `partie_resultat` (bannière de fin de manche).
- **Zone** : grille 4 × 4 de la boîte englobante (X, Z) de la map jouée, colonnes `A`→`D` selon X croissant, lignes
  `1`→`4` selon Z croissant (`AnalyticsRules.zone`). Position de la racine au moment de la mort : pour une chute, là où
  le joueur a quitté la map à peu près. Pour situer une zone : `AnalyticsRules.zone` sur une position relevée en jeu.
- Rien de `Mort` ni de `MortsSansKill` sur un serveur d'entraînement.

## Lire les tableaux de bord

Creator Hub → l'expérience → **Analytics** :

- **Funnels** : l'onboarding (où décrochent les nouveaux), puis les funnels récurrents `Session`, `Shop`, `PacksRobux`
  (conversion d'une étape à l'autre).
- **Economy** : sources et puits de `Credits` par type de transaction et SKU.
- **Custom events** : `Depart` découpé par le champ 1 donne où l'on quitte le jeu (ex. beaucoup de `menu_home` avec
  `0` manche : bloqués au menu) ; `Mort` découpé par zone et cause montre la rampe où l'on tombe le plus ; `TempsEcran`
  et `MenuAvantJouer` donnent les temps moyens.

Les données apparaissent avec un délai (de l'ordre de quelques heures) et seulement depuis le jeu publié.

## Pièges

- Un nouvel écran du menu doit être ajouté à `AnalyticsRules.Screen` **et** à `SCREENS` (sinon la garde du remote le
  refuse comme malformé et le journalise en violation forte), puis à `AnalyticsRules.menuScreen` ou à
  `ShopScreen.analyticsScreen`.
- Ajouter un champ à un événement : trois au plus, et seulement des valeurs bornées (classes, pas de nombres bruts).
- Les étapes d'un funnel ne se renumérotent pas une fois publiées : les tableaux de bord mélangeraient deux définitions.
  Ajouter une étape en fin de funnel, ou créer un funnel nouveau.

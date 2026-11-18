# Économie : crédits, packs Robux, objets aléatoires payants

Règles d'argent réel du jeu (#395). Stockage des crédits, contrat de `InventoryStore.transact` et achat d'une caisse :
`docs/architecture.md` (« Crédits », « Achat d'une caisse »). Interface : `docs/ui.md` (« Packs de crédits »).

## Solde de départ

Un nouveau joueur commence avec 250 crédits (`WalletRules.STARTING_BALANCE`, compté dans `earned`, hors plafond du
jour). Une caisse coûte 500 et les gains en jouant plafonnent à 250 par jour : à 0, la première caisse n'arrivait qu'au
jour 2, ce qui nuit à la rétention. Avec 250, elle s'ouvre dès le jour 1, une fois le plafond du jour atteint.
Piste rejetée : 500 (caisse ouverte dès l'arrivée), car le joueur n'aurait pas d'abord joué avec le couteau de base.
Seuls les portefeuilles absents (nouveau joueur, enregistrement d'avant #396) ou illisibles reçoivent ce solde : un
solde déjà enregistré n'est pas modifié.

## Manche jouée : activité réelle (#401)

Barème et plafonds des gains en jouant (#394) : `docs/architecture.md` (« Gains en jouant »). Une manche jouée
rapporte +15. Avant #401, 120 s en vie suffisaient sans kill : un joueur immobile que les bots ne tuaient pas
atteignait le plafond du jour (250) en ~17 manches sans jouer.

- Règle (`EconomyRules.played`) : au moins un kill, **ou** `PLAYED_ALIVE_SECONDS` (120 s) cumulées en vie dans la
  manche **et** une activité réelle (`EconomyRules.isActive`) : une portée d'au moins `PLAYED_MIN_REACH` studs, ou
  `PLAYED_MIN_HITS` (1) touche. Avec un kill, rien ne change.
- Tout est mesuré par le serveur, jamais déclaré par le client (`CreditGains.onMove`, `onHit`) :
  - **portée** : plus grand écart horizontal au point d'apparition de chaque vie, additionné sur les vies de la
    manche (un joueur actif souvent tué la cumule).
    L'écart est la **somme des seuls pas propres** (vecteurs `to - from` reçus de `CharacterSync.setMoveListener`,
    paquet accepté **sans signalement** : seau de distance, noclip, vol, y compris en journal seul), pas une
    différence de positions absolues : un pas signalé, une téléportation (`CharacterSync.teleport`) ou le saut entre
    deux vies ne sont jamais ajoutés, même par le paquet propre qui suit. Pas une distance de chemin non plus : un
    aller-retour de quelques studs répété (script, tremblement sur une pente) ne la fait pas monter. Hauteur ignorée
    (chute, saut sur place) ;
  - **touche** : tir ou coup de mêlée validé par le `Validator` **et** qui a fait des dégâts (`applyHit` non nil : pas
    un corps, pas une cible sous ForceField). Un tir dans le vide ne compte pas : sinon un seul tir en l'air par
    manche suffirait à un AFK ;
  - seulement pendant une vie dans une manche active, avec le personnage de cette vie : rien au menu, mort, pendant la
    bannière de fin, ni pour un paquet tardif d'un ancien personnage.
- Limite connue : un script qui déplace le personnage loin de son point d'apparition passe. Le plafond du jour borne
  ce cas.
- Studio : la ligne `[CreditGains] fin de manche …` donne kills, temps en vie, portée (studs) et touches.
- Tests : `tests/specs/EconomyRules.spec.luau` (règle, seuil, écart horizontal), `tests/specs/CreditGains.spec.luau`
  (« activité réelle » : AFK immobile ou qui tourne sur place non crédité, aller-retour non crédité, actif par portée
  ou touche crédité, kill comme avant, origine reprise à chaque vie et portée additionnée, pas signalé non compté, hors vie et hors manche
  ignorés).

Mesures (Studio, map jouée, `[CreditGains]`) :

| Scénario (150 s en vie, aucun kill ni touche) | Portée | Avant #401 | Après #401 |
|---|---|---|---|
| Surf : piste enregistrée `Dizzy` rejouée (`PerfRun`, 137 s, bots passifs) | 538 studs | +15 | +15 |
| Immobile (rejeu interrompu, bots passifs) | 0 stud | +15 | +0 |

- Mesure du 16/11/2026, Studio, map `Dizzy`, manche de 150 s (`RoundDuration`). « Avant » se déduit de la même ligne
  `[CreditGains]` (150 s en vie suffisaient) : la règle de `main` n'a pas été rejouée à part.
- La portée d'un surf reste modeste : la map fait ~560 × 600 studs, et un surf revient souvent près de son départ.
  Pendant ce rejeu honnête, l'anti-vol (journal seul) a signalé une vingtaine de paquets : ces pas sont exclus,
  la portée réelle est un peu plus grande. D'où **`PLAYED_MIN_REACH` = 150** : ~3,5 fois sous le surf mesuré, loin
  au-dessus de l'immobile (0 : sans paquet de position différent, rien ne s'ajoute, tourner sur place ne change que
  le cap).
- Un joueur qui campe à moins de 150 studs de son apparition sans toucher personne pendant toute la manche ne gagne
  plus la manche jouée : cas assumé, il n'est pas distinguable d'un AFK par ces mesures.

## Packs de crédits (Developer Products)

- Config : `src/shared/CreditPacks.luau` (`PACKS` : id du pack, `productId`, crédits, prix affiché, nom du produit).
  Valeurs : 500 crédits à 99 R$, 1 100 à 199 R$, 3 000 à 499 R$.
- **Developer Products créés** (dashboard Creator, expérience > Monetization > Developer Products) : 500 crédits
  `3732001755`, 1 100 crédits `3732001894`, 3 000 crédits `3732001987`. Le prix réel est celui du dashboard ; `robux`
  n'est que l'affichage, à garder égal (un changement de prix se fait aux deux endroits).
- Nouveau pack : créer d'abord le produit sur le dashboard, puis l'ajouter à `CreditPacks.PACKS`. Un pack qui garde un
  id provisoire (3 950 001 à 3 950 003, `CreditPacks.isReady`) masque « + CRÉDITS » et fait refuser le prompt
  (`unavailable`) hors de Studio ; un test vérifie que la config livrée n'en a plus.
- **Affichage (#409)** : le client lit `PriceInRobux` par `GetProductInfo` (pcall, en différé, un appel réussi par
  produit gardé en cache) ; en attendant ou en cas d'échec, `robux` de la config (`CreditPacks.displayRobux`). Les crédits
  accordés restent ceux de la config. Le prompt Robux ouvert plus de `PROMPT_TIMEOUT` (120 s) garde les prix inactifs
  jusqu'à `PromptProductPurchaseFinished` : le délai de secours ne rend les prix que si le serveur n'a jamais confirmé
  l'ouverture du prompt (`PurchaseGuard`), ou après `PROMPT_FINAL_TIMEOUT` (30 min) si Roblox n'a jamais signalé sa fin. Limite : un prompt jamais confirmé puis terminé très tard, pour le même
  produit qu'un achat relancé depuis, termine ce dernier avant l'heure (la fin n'a pas d'id d'achat).
  « GAINS DU JOUR » (MainMenu) est aussi repeint par une minuterie calée sur le prochain minuit UTC.
- Prompt refusé (`full`) si le pack ferait dépasser `WalletRules.MAX_BALANCE` : ses crédits seraient écrêtés.
- Ne jamais retirer de la config un produit déjà vendu : ses reçus en attente ne seraient plus jamais accordés.
- Crédits achetés : compteur `purchased` du portefeuille, hors plafond du jour (#394).

## Reçus : `ProcessReceipt` (`src/server/ReceiptService.luau`, règles pures `ReceiptRules.luau`)

Ce que dit Roblox (doc de `MarketplaceService.ProcessReceipt`, relue le 15/11/2026) :

- un seul callback, posé une fois par un seul script serveur, pour tous les produits ;
- il est rappelé pour un reçu non résolu **seulement** au prochain achat du joueur ou à sa prochaine connexion
  (« ProcessReceipt has no time-based retry mechanism »), et peut tourner sur deux serveurs en même temps ;
- pas de délai imposé à un callback qui attend (« no timeout for yielded callbacks ») ;
- « Unresolved developer product purchases are not removed or refunded after the escrow period expires » : un reçu
  laissé en `NotProcessedYet` garde les Robux du joueur sans rien lui donner, indéfiniment ;
- un produit peut s'acheter hors du jeu (onglet Store de la page de l'expérience).

Règles du jeu :

- `PurchaseGranted` seulement après la `InventoryStore.transact` réussie qui ajoute les crédits dans `purchased` **et**
  inscrit le PurchaseId dans `wallet.receipts`, dans la même `UpdateAsync`. PurchaseId déjà inscrit : `PurchaseGranted`
  sans rien ajouter (rejeu de Roblox, deux serveurs, écriture passée mais signalée en échec).
- `NotProcessedYet` : produit inconnu, PurchaseId invalide (vide, plus de `WalletRules.MAX_RECEIPT_LENGTH`), joueur
  absent, inventaire pas chargé (attendu 30 s : le reçu arrive souvent pendant la connexion, et Roblox ne le
  rejouerait qu'à la suivante) ou pas sauvegardable, écriture en échec.
- Solde au plafond (`WalletRules.MAX_BALANCE`) : crédits écrêtés et reçu accordé, jamais laissé en attente (Robux pris
  sans rien donner). Le prompt est déjà refusé près du plafond ; ce cas demande un solde monté entre le prompt et le reçu.
- Le journal note un joueur restreint d'après le cache de `PaidRandomPolicy` seulement : un reçu n'attend jamais
  PolicyService.
- Une écriture en échec est retentée dans le callback (3 transactions espacées de 5 s, tant que le joueur est là) : sans
  risque, le PurchaseId rend chaque tour idempotent, et Roblox ne rejouerait pas le reçu avant longtemps.
- Le thread qui appelle `transact` n'est jamais annulé (cf. pièges de `transact`).
- Chaque reçu est journalisé, préfixe `[Receipts]` : `PurchaseGranted` (accordé, accordé après une écriture rejouée,
  déjà traité) en sortie normale, `NotProcessedYet` avec son motif en avertissement.
- **Taille de `receipts` : `WalletRules.MAX_RECEIPTS` = 100.** Un reçu n'est rejoué que s'il est resté non résolu, et
  Roblox le rappelle au prochain achat (« after a successful purchase ») ou à la prochaine connexion du joueur. Pour
  qu'il soit crédité deux fois, il faudrait que 100 autres reçus du même joueur soient écrits entre l'écriture du
  premier et son rejeu, alors que chacun de ces achats déclenche lui-même le rejeu. 100 PurchaseId font ~4 Ko, loin de
  la limite de 4 Mo d'une clé. Inchangée par #395, donc pas de relèvement de `InventoryRules.SCHEMA_VERSION`.
- Studio : le prompt de Roblox ne se clique pas depuis le MCP, et un `require` depuis le MCP charge une autre instance
  du module. Pour un reçu simulé passé par le vrai traitement : attribut Player `DebugReceipt` = `"pack.500|test-1"`
  (contexte serveur), puis la console (`[Receipts]` et `[DebugReceipt] … → PurchaseGranted`). Rejouer la même valeur
  montre le reçu déjà traité. Sans « Enable Studio Access to API Services », poser d'abord `DebugCredits` (solde de
  session), sinon le reçu reste `NotProcessedYet` (profil pas sauvegardable).
- Tests : `tests/specs/ReceiptRules.spec.luau` (opération, décision), `tests/specs/WalletStore.spec.luau` « Reçus Robux »
  (même reçu rejoué, écriture en échec puis rejouée, écriture passée signalée en échec, joueur absent ou parti, produit
  inconnu, reçu à la connexion, chargement en échec, deux serveurs, joueur restreint).

## Objets aléatoires payants (`src/server/PaidRandomPolicy.luau`)

Les caisses du shop en sont : elles se paient en crédits, et les crédits s'achètent en Robux. Ce que dit Roblox
([Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items), relu le 15/11/2026) :

- « This includes random items purchased with paid in-game currency. »
- « When ArePaidRandomItemsRestricted is true, the user cannot interact with paid random item generators » ; pour ces
  joueurs, l'un des traitements : « Offering an unpaid, earnable path to acquiring the random item », « Removing or
  hiding the paid random item from the game », « Blocking the purchase of the paid random item with an error
  message »…
- Chances : « Odds must be displayed as a probability percentage », « the probability percentages of all final outcomes
  must sum to exactly 100% », montrées avant de dépenser la monnaie (« before they spend the in-game currency »).

**Choix : caisses bloquées pour un joueur restreint** (« INDISPONIBLE DANS TA RÉGION »). La doc ne traite pas d'une
monnaie à la fois gagnable et achetable : son exemple de chemin gratuit est un objet donné en jouant (« Mystery eggs
are granted for free at milestones of gameplay »), pas une monnaie dont une partie a été payée, et la seule réponse
sur ce cas dans le fil du DevForum (« Clarifying requirements for paid random items », pas d'un employé de Roblox) le
range dans les objets payants. Dans le doute, le brief de #395 demandait le blocage. Payer les caisses avec les seuls
crédits `earned` reste possible plus tard si Roblox le confirme : `CratePurchaseRules.operation` est le seul endroit
du débit, et le remboursement d'un doublon rend déjà les crédits au compteur d'où ils viennent (ci-dessous).

- Restriction lue par `PolicyService:GetPolicyInfoForPlayerAsync` (champ `ArePaidRandomItemsRestricted`), dans un
  `pcall`, demandée à l'arrivée du joueur et mise en cache pour la session. **Appel en échec ou réponse sans le champ
  = restreint** ; un échec est redemandé d'office 30 s plus tard (le client, qui masque alors les achats, ne rappelle
  plus le serveur : sans cela, une panne passagère à l'arrivée bloquait le joueur toute la session).
- Côté serveur : `BuyCrate` refusé `region` avant tout tirage (`CrateService`) ; prompt d'un pack refusé `region`
  (`ReceiptService.promptFor`, le prompt est ouvert par le serveur).
- Côté client (attribut informatif `PaidRandomRestricted`, absent tant que la réponse n'est pas arrivée) : « + CRÉDITS »
  masqué (absent compris), ACHETER inactif avec l'étiquette « INDISPONIBLE DANS TA RÉGION » (true seulement).
- **Reçu d'un joueur restreint : accordé** (choix de l'utilisateur, #395) et signalé dans le journal. Il ne peut venir
  que d'un achat hors du jeu ou d'un client modifié ; le refuser garderait ses Robux sans remboursement, et ses crédits
  achetés ne mènent à aucun objet aléatoire puisque les caisses lui sont bloquées.
- L'ouverture de test (admin et Studio, gratuite) n'est pas un objet payant : non bloquée.
- Studio : attribut Player `DebugPaidRandomRestricted` (true/false, contexte serveur) remplace la réponse de
  PolicyService ; nil la redemande.
- `IsPaidItemTradingAllowed` : sans objet, il n'y a pas d'échange entre joueurs. À brancher avec un futur échange.

**Remboursement d'un doublon dans le même compteur** (`CratePurchaseRules`) : d'abord `purchased`, à hauteur de ce que
cet achat en a débité, le reste dans `earned`, toujours hors plafond du jour. Avant #395, tout allait dans `earned` :
un achat payé en crédits achetés puis remboursé convertissait des crédits achetés en crédits gagnés (et aurait ouvert
un chemin « gratuit » payé en Robux si les caisses étaient un jour payées en `earned` seuls).

**Chances affichées** (vue détail du shop, #393, `ShopCatalog.chances`) : en pour cent, deux décimales au plus (centièmes,
#430), somme exactement 100 % (plus fort reste), visibles avant ACHETER. Caisses actuelles : 80 / 16 / 3,2 / 0,8 % par
rareté, partagés entre les skins (AWP · SÉRIE 1 : 5,34 / 5,33 / 5,33 % pour trois RARE). Piège : avec des chances qui ne
tombent pas juste au centième, le plus fort reste décale un affichage d'au plus 0,01 point, et une chance sous 0,005 %
s'afficherait « 0 % » ; Roblox demande alors plus de
décimales (quatre de plus que le premier chiffre non nul) ou la mention « Probabilities are rounded… ».

**Gain du jour affiché** (#446) : tout écran qui montre `LocalWallet.dailyEarned()` (« GAINS DU JOUR » du shop, bandeau
« PLAFOND DU JOUR ATTEINT » du `RoundHUD`) passe par `LocalWallet.observeDaily` : repeint à l'attribut `DailyCredits` et au
changement de jour UTC (une minuterie partagée sur l'heure serveur). Piège : lire `dailyEarned()` seulement à ses propres
événements laissait un affichage périmé à cheval sur minuit. Ne pas ajouter de minuterie par écran.

## Tenues de personnage : achat direct (#543)

Les tenues (#521) se vendent au portant du shop, **sans tirage** : le joueur choisit la tenue qu'il paie, au prix
affiché (`price` dans `InventoryRules.ITEMS`). Ce n'est donc pas un objet aléatoire payant : pas de chances à
afficher, pas de blocage pour un joueur restreint (`PaidRandomPolicy` n'est pas consulté), payable en crédits gagnés
comme achetés (achetés débités d'abord, comme partout).

- Toute tenue du catalogue qui a un prix est en vente (`OutfitPurchaseRules.order`) ; une tenue sans prix est
  refusée `unavailable` (réservée, par exemple à l'admin). Aucune tenue n'est écrite en dur dans l'achat.
- Le prix se règle par tenue, dans le catalogue seulement (MERCURE, exceptionnelle : 2 500) : ni le serveur ni le
  client n'en gardent de copie.
- Pas de doublon possible, donc pas de remboursement : une tenue déjà possédée est refusée avant l'écriture (session),
  ou trouvée par l'opération dans l'enregistrement stocké (achetée sur un autre serveur) : rien de débité, mais
  l'enregistrement est réécrit tel quel pour que la session apprenne qu'elle la possède.
- Code : `src/server/OutfitService.luau`, `src/server/OutfitPurchaseRules.luau` ; détail dans `docs/architecture.md`
  (« Achat d'une tenue »).
- Piège : si une tenue devait un jour se gagner au hasard (caisse de tenues), elle redevient un objet aléatoire payant
  et suit la section « Objets aléatoires payants » (blocage `region`, chances à 100 %).

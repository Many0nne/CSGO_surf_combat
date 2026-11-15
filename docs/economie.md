# Économie : crédits, packs Robux, objets aléatoires payants

Règles d'argent réel du jeu (#395). Stockage des crédits, contrat de `InventoryStore.transact` et achat d'une caisse :
`docs/architecture.md` (« Crédits », « Achat d'une caisse »). Interface : `docs/ui.md` (« Packs de crédits »).

## Packs de crédits (Developer Products)

- Config : `src/shared/CreditPacks.luau` (`PACKS` : id du pack, `productId`, crédits, prix affiché, nom du produit).
  Valeurs : 500 crédits à 99 R$, 1 100 à 199 R$, 3 000 à 499 R$.
- **Ids provisoires** (3 950 001 à 3 950 003) tant que les produits n'existent pas : les créer sur le dashboard Creator
  (expérience > Monetization > Developer Products), puis coller leurs ids dans `CreditPacks.PACKS`. Le prix réel est
  celui du dashboard ; `robux` n'est que l'affichage, à garder égal.
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
  rejouerait qu'à la suivante) ou pas sauvegardable, refus de l'opération (solde au plafond), écriture en échec.
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
  = restreint** ; un échec est redemandé au plus toutes les 30 s.
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

**Chances affichées** (vue détail du shop, #393, `ShopCatalog.chances`) : en pour cent, une décimale au plus, somme
exactement 100 % (plus fort reste), visibles avant ACHETER. Caisses actuelles : 70 %, 25 %, 5 %, un skin par rareté,
donc aucun arrondi. Piège : avec des chances qui ne tombent pas juste au dixième, le plus fort reste décale un
affichage d'au plus 0,1 point, et une chance sous 0,05 % s'afficherait « 0 % » ; Roblox demande alors plus de
décimales (quatre de plus que le premier chiffre non nul) ou la mention « Probabilities are rounded… ».

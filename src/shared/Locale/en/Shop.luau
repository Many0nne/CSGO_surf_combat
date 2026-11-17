-- Traductions anglaises (#518, cf. Locale) : texte français affiché -> texte anglais.
-- Shop et achats : ShopScreen, ShopScene, ShopCatalog (raretés, noms de caisses), packs de crédits, états d'achat.
-- Les noms de skins sont des noms propres, gardés tels quels (hors table).
return {
	-- Raretés (ShopCatalog.RARITIES ; aussi lues par l'écran ARMES)
	["COMMUN"] = "COMMON",
	["RARE"] = "RARE",
	["EXCEPTIONNEL"] = "EXCEPTIONAL",
	["LÉGENDAIRE"] = "LEGENDARY",

	-- Noms de caisses (ShopCatalog.CRATES)
	["AWP · SÉRIE 1"] = "AWP · SERIES 1",
	["AWP · SÉRIE 2"] = "AWP · SERIES 2",
	["M9 · SÉRIE 1"] = "M9 · SERIES 1",
	["M9 · SÉRIE 2"] = "M9 · SERIES 2",
	["CAISSE  ·  {n} SKINS  ·  UN PAR OUVERTURE"] = "CRATE  ·  {n} SKINS  ·  ONE PER OPENING",

	-- Vitrine et vue détail (ShopScreen)
	["CAISSES"] = "CRATES",
	["{n} EN VENTE  ·  UNE PAR ARME ET PAR SÉRIE"] = "{n} ON SALE  ·  ONE PER WEAPON AND SERIES",
	["VOIR LE CONTENU ET ACHETER"] = "VIEW CONTENTS AND BUY",
	["‹  SHOP"] = "‹  SHOP",
	["CAISSE  {n} / {total}"] = "CRATE  {n} / {total}",
	["CHANCE"] = "ODDS",
	["SI DOUBLON"] = "IF DUPLICATE",
	["SURVOL"] = "HOVER",
	["VOIR UN SKIN"] = "PREVIEW A SKIN",
	["LE GARDER"] = "KEEP IT",
	["GLISSER"] = "DRAG",
	["LE TOURNER"] = "ROTATE IT",

	-- Achat et ouverture
	["ACHETER"] = "BUY",
	["ACHAT…"] = "BUYING…",
	["ACHAT ÉCRIT"] = "PURCHASE RECORDED",
	["OUVERTURE DE TEST  ·  GRATUITE"] = "TEST OPENING  ·  FREE",
	["TOUT OBTENU"] = "ALL OWNED",
	["OBTENU"] = "OBTAINED",
	["DOUBLON"] = "DUPLICATE",
	["DOUBLON  ·  +{amount} CRÉDITS"] = "DUPLICATE  ·  +{amount} CREDITS",
	["CONTINUER"] = "CONTINUE",

	-- Refus d'achat (ShopScreen, CreditPackWindow, PurchaseStatus)
	["ACHAT DÉJÀ EN COURS"] = "PURCHASE ALREADY IN PROGRESS",
	["INVENTAIRE EN CHARGEMENT"] = "INVENTORY LOADING",
	["RÉSERVÉ"] = "RESERVED",
	["CAISSE INCONNUE"] = "UNKNOWN CRATE",
	["CAISSE VIDE"] = "EMPTY CRATE",
	["CRÉDITS INSUFFISANTS"] = "NOT ENOUGH CREDITS",
	["ÉCHEC"] = "FAILED",
	["PATIENTE"] = "PLEASE WAIT",
	["INDISPONIBLE DANS TA RÉGION"] = "NOT AVAILABLE IN YOUR REGION",
	["ACHAT IMPOSSIBLE  ·  RÉESSAIE PLUS TARD"] = "PURCHASE FAILED  ·  TRY AGAIN LATER",

	-- Packs de crédits (CreditPackWindow, CreditPacks)
	["+ CRÉDITS"] = "+ CREDITS",
	["PACKS DE CRÉDITS"] = "CREDIT PACKS",
	["PAIEMENT EN ROBUX  ·  LES CRÉDITS ARRIVENT DÈS QUE ROBLOX CONFIRME L'ACHAT"] = "PAID IN ROBUX  ·  CREDITS ARRIVE AS SOON AS ROBLOX CONFIRMS THE PURCHASE",
	["+{amount} CRÉDITS"] = "+{amount} CREDITS",
	["PACK INCONNU"] = "UNKNOWN PACK",
	["PACKS PAS ENCORE EN VENTE"] = "PACKS NOT ON SALE YET",
	["SOLDE AU MAXIMUM"] = "BALANCE AT MAXIMUM",
	["SAUVEGARDE INDISPONIBLE  ·  RÉESSAIE PLUS TARD"] = "SAVING UNAVAILABLE  ·  TRY AGAIN LATER",
	-- Noms des Developer Products (Creator Hub, jamais affichés dans le jeu)
	["500 crédits"] = "500 credits",
	["1 100 crédits"] = "1,100 credits",
	["3 000 crédits"] = "3,000 credits",
}

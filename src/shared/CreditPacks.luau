-- Packs de crédits achetés en Robux (#395) : un Developer Product par pack. Lu par le client (fenêtre des packs du
-- shop) et par le serveur (ReceiptService : crédits accordés selon le produit du reçu ; prompt d'achat). Testé
-- (tests/specs/CreditPacks.spec.luau). Règles d'économie et des objets aléatoires payants : docs/economie.md.
--
-- **Ids provisoires** : les `productId` ci-dessous ne correspondent à aucun produit. Créer les trois Developer Products
-- sur le dashboard Creator (Monetization > Developer Products, noms et prix ci-dessous), puis coller leurs ids ici ;
-- d'ici là, les packs ne sont proposés que dans Studio (`isReady`).
-- Un reçu d'un produit inconnu reste en attente (`NotProcessedYet`) : ne jamais retirer un pack déjà vendu, Roblox
-- rejouerait ses reçus en attente sans que personne ne les accorde.
local CreditPacks = {}

export type Pack = {
	id: string, -- id stable du pack (remote du prompt d'achat)
	productId: number, -- Developer Product (dashboard Creator)
	credits: number, -- crédits ajoutés au compteur `purchased`
	robux: number, -- prix affiché (le prix réel est celui du produit sur le dashboard)
	name: string, -- nom du produit sur le dashboard
}

CreditPacks.PACKS = {
	{ id = "pack.500", productId = 3_950_001, credits = 500, robux = 99, name = "500 crédits" },
	{ id = "pack.1100", productId = 3_950_002, credits = 1_100, robux = 199, name = "1 100 crédits" },
	{ id = "pack.3000", productId = 3_950_003, credits = 3_000, robux = 499, name = "3 000 crédits" },
} :: { Pack }

-- Ids provisoires ci-dessus : tant qu'un pack en porte un, les packs sont masqués et le prompt refusé hors de Studio
-- (`isReady`), pour qu'une publication faite avant de coller les vrais ids ne montre pas un achat qui échoue.
local PLACEHOLDER_IDS = { [3_950_001] = true, [3_950_002] = true, [3_950_003] = true }

-- Cette méthode permet de savoir si tous les packs ont un vrai Developer Product lorsque le shop montre « + CRÉDITS »
-- ou que le serveur ouvre un prompt (hors Studio).
function CreditPacks.isReady(): boolean
	for _, pack in CreditPacks.PACKS do
		if PLACEHOLDER_IDS[pack.productId] then
			return false
		end
	end
	return true
end

-- Attribut informatif du Player (booléen), posé par le serveur (PaidRandomPolicy) : true si le joueur ne doit pas
-- toucher aux objets aléatoires payants (`ArePaidRandomItemsRestricted`, appel en échec compris) ; absent tant que la
-- réponse de PolicyService n'est pas arrivée. Le client masque les packs (absent compris) et bloque ACHETER (true).
CreditPacks.RESTRICTED_ATTRIBUTE = "PaidRandomRestricted"

-- Cette méthode permet de trouver un pack par son id lorsqu'un client demande son prompt d'achat ; nil si inconnu.
function CreditPacks.byId(id: any): Pack?
	for _, pack in CreditPacks.PACKS do
		if pack.id == id then
			return pack
		end
	end
	return nil
end

-- Cette méthode permet de trouver un pack par son Developer Product lorsqu'un reçu arrive ; nil si le produit est inconnu.
function CreditPacks.byProduct(productId: any): Pack?
	for _, pack in CreditPacks.PACKS do
		if pack.productId == productId then
			return pack
		end
	end
	return nil
end

-- Cette méthode permet d'écrire le prix d'un pack (« 99 R$ ») lorsque la fenêtre des packs l'affiche.
function CreditPacks.priceLabel(pack: Pack): string
	return string.format("%d R$", pack.robux)
end

return CreditPacks

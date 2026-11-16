-- Solde de crédits des joueurs, la monnaie du jeu (#391) : façade sur l'enregistrement de l'inventaire (#396), qui
-- garde le portefeuille dans `PlayerInventory_v1` (clé `wallet`) pour qu'un achat écrive solde et objets ensemble.
-- Règles pures dans `WalletRules`, stockage et écritures dans `InventoryStore`.
-- Seul le serveur change un solde : `add` (gain) et `spend` (dépense) ; aucun remote n'en donne le droit au client, qui
-- lit l'attribut informatif `Credits` du Player (gagnés + achetés, LocalWallet).
-- Un gain part avec la prochaine écriture de l'inventaire (lot numéroté, quelques secondes plus tard) ; une dépense
-- s'écrit tout de suite (`InventoryStore.transact`) et n'aboutit que si le solde stocké suffit : `spend` attend
-- l'écriture et rend son issue. Un achat qui donne aussi un objet (#393) appelle directement `InventoryStore.transact`.
-- Studio : attribut Player `DebugCredits` (nombre, posé en contexte serveur) ajouté au solde (négatif : retiré), puis
-- remis à nil ; sans accès aux API (chargement en échec), le solde devient un solde de session, jamais sauvegardé.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage.Shared.WalletRules)
local InventoryStore = require(ServerScriptService.Server.InventoryStore)
local TransactOutcome = require(ServerScriptService.Server.TransactOutcome)

local DEBUG_ATTRIBUTE = "DebugCredits"

-- Issue d'une dépense : débitée (`ok`), solde stocké insuffisant (`insufficient`), solde pas chargé ou pas
-- sauvegardable (`loading`), écriture en échec (`failed`, rien de débité), montant invalide (`invalid`)
export type SpendStatus = "ok" | "insufficient" | "loading" | "failed" | "invalid"

local WalletStore = {}

-- Cette méthode permet de lire le solde d'un joueur (stocké plus gains pas encore écrits) lorsqu'un système serveur le
-- consulte ; nil tant que le solde n'est pas chargé (ou si son chargement a échoué).
function WalletStore.balance(player: Player): number?
	return InventoryStore.credits(player)
end

-- Cette méthode permet de savoir si le solde d'un joueur peut changer lorsqu'un système serveur s'apprête à donner ou
-- faire payer (à vérifier avant un tirage ou un don, comme InventoryStore.canGrant).
function WalletStore.canChange(player: Player): boolean
	return InventoryStore.canChangeCredits(player)
end

-- Cette méthode permet de créditer un joueur hors plafond du jour (debug ; un gain en jouant passe par `addPlayGain`) ;
-- false si le montant est invalide ou si le solde ne peut pas changer, solde écrêté à WalletRules.MAX_BALANCE.
function WalletStore.add(player: Player, amount: number): boolean
	return InventoryStore.addCredits(player, amount)
end

-- Cette méthode permet de créditer un gain en jouant (#394, kill, manche jouée, victoire) du jour UTC `day`, soumis au
-- plafond du jour (EconomyRules.DAILY_CAP) ; renvoie le montant crédité (0 au plafond), nil si le solde ne peut pas changer.
function WalletStore.addPlayGain(player: Player, amount: number, day: number): number?
	return InventoryStore.addPlayCredits(player, amount, day)
end

-- Cette méthode permet de débiter un joueur lorsqu'il paie, achetés d'abord puis gagnés : écriture immédiate qui
-- vérifie le solde stocké ; bloquante, renvoie l'issue (SpendStatus) une fois l'écriture terminée.
function WalletStore.spend(player: Player, amount: number): SpendStatus
	if not WalletRules.isAmount(amount) then
		return "invalid"
	end
	local status, reason = InventoryStore.transact(player, function(record)
		local wallet, why = WalletRules.debit(record.wallet, amount)
		if not wallet then
			return nil, why
		end
		record.wallet = wallet
		return record, nil
	end)
	return TransactOutcome.translate(status, reason)
end

-- Cette méthode permet, dans Studio, d'ajouter au solde l'attribut `DebugCredits` posé en contexte serveur (négatif :
-- retiré, jusqu'à 0), puis de le remettre à nil ; sans accès aux API, le solde devient un solde de session.
function WalletStore.applyDebug(player: Player)
	local value = player:GetAttribute(DEBUG_ATTRIBUTE)
	if value == nil then
		return
	end
	player:SetAttribute(DEBUG_ATTRIBUTE, nil)
	if type(value) ~= "number" or value ~= math.floor(value) then
		warn("[DebugCredits] valeur invalide :", value)
		return
	end
	-- Chargement en échec (Studio sans « Enable Studio Access to API Services ») : solde de session à 0
	InventoryStore.startSessionWallet(player)
	local before = WalletStore.balance(player)
	if before == nil then
		warn("[DebugCredits] solde pas encore chargé pour", player.Name)
		return
	end
	local result: any = "rien à changer"
	if value > 0 then
		result = WalletStore.add(player, value)
	elseif value < 0 and before > 0 then
		result = WalletStore.spend(player, math.min(-value, before))
	end
	print("[DebugCredits]", player.Name, value, result, before, "→", WalletStore.balance(player))
end

return WalletStore

-- Packs de crédits achetés en Robux (#395) : **seul** callback `MarketplaceService.ProcessReceipt` du jeu, et prompt
-- d'achat demandé par le client (remote `BuyCreditPack`). Règles d'économie : docs/economie.md.
--
-- Reçu : `PurchaseGranted` seulement après la `InventoryStore.transact` réussie qui ajoute les crédits du pack dans
-- `purchased` **et** inscrit le PurchaseId dans `wallet.receipts` (ReceiptRules) ; PurchaseId déjà inscrit →
-- `PurchaseGranted` sans rien ajouter. `NotProcessedYet` (Roblox rejoue le reçu au prochain achat ou à la prochaine
-- connexion du joueur, sans délai programmé ni remboursement) : produit inconnu, PurchaseId invalide, joueur absent,
-- inventaire pas chargé (attendu LOAD_WAIT s, le reçu arrive souvent à la connexion) ou pas sauvegardable, écriture en
-- échec (WRITE_ROUNDS tours espacés de ROUND_GAP s, sans risque : le PurchaseId rend chaque tour idempotent) ou refus
-- de l'opération. Chaque reçu est journalisé (accordé, rejoué, refusé, motif). Le thread qui appelle `transact` n'est
-- jamais annulé (Roblox n'impose pas de délai à ProcessReceipt).
--
-- Joueur restreint (objets aléatoires payants, PaidRandomPolicy) : le prompt lui est refusé (`region`) et le bouton des
-- packs lui est masqué ; un reçu qui arrive quand même (achat par l'onglet Store de la page du jeu, client modifié) est
-- **accordé** et journalisé : Roblox ne rembourse jamais un reçu en attente, et les caisses lui sont bloquées
-- (CrateService), ses crédits achetés ne mènent donc à aucun objet aléatoire (choix de l'utilisateur, #395).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreditPacks = require(ReplicatedStorage.Shared.CreditPacks)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local InventoryStore = require(ServerScriptService.Server.InventoryStore)
local PaidRandomPolicy = require(ServerScriptService.Server.PaidRandomPolicy)
local ReceiptRules = require(ServerScriptService.Server.ReceiptRules)
local WalletStore = require(ServerScriptService.Server.WalletStore)

local LOAD_WAIT = 30 -- s d'attente au plus de la fin du chargement de l'inventaire
local LOAD_POLL = 0.5 -- s entre deux regards pendant cette attente
local WRITE_ROUNDS = 3 -- transactions au plus pour un reçu dont l'écriture échoue (trois essais DataStore chacune)
local ROUND_GAP = 5 -- s entre deux de ces transactions

export type Reply = { ok: boolean, reason: string? }

local ReceiptService = {}

-- Cette méthode permet de journaliser un reçu (décision, motif, joueur, produit, PurchaseId) lorsqu'il est traité :
-- accordé en sortie normale, refusé en avertissement.
local function logReceipt(verdict: ReceiptRules.Verdict, why: string, info: any, extra: string?)
	local line = string.format(
		"[Receipts] %s : %s — joueur %s, produit %s, PurchaseId %s%s",
		if verdict == "granted" then "PurchaseGranted" else "NotProcessedYet",
		why,
		tostring(info.PlayerId),
		tostring(info.ProductId),
		tostring(info.PurchaseId),
		if extra then " — " .. extra else ""
	)
	if verdict == "granted" then
		print(line)
	else
		warn(line)
	end
end

-- Cette méthode permet d'attendre la fin du chargement de l'inventaire d'un joueur (LOAD_WAIT au plus, tant qu'il est
-- là) lorsqu'un reçu arrive pendant sa connexion.
local function waitLoaded(player: Player)
	local waited = 0
	while not InventoryStore.isLoaded(player) and player.Parent and waited < LOAD_WAIT do
		task.wait(LOAD_POLL)
		waited += LOAD_POLL
	end
end

-- Cette méthode permet de décider d'un reçu (crédits écrits avec le PurchaseId, ou reçu laissé en attente) lorsque
-- Roblox appelle ProcessReceipt ; bloquante jusqu'à l'écriture. Renvoie la décision, le motif et un détail journalisé.
function ReceiptService.handle(info: any): (ReceiptRules.Verdict, string, string?)
	local pack = CreditPacks.byProduct(info.ProductId)
	if not pack then
		return "retry", "produit inconnu"
	end
	if not ReceiptRules.isPurchaseId(info.PurchaseId) then
		return "retry", "PurchaseId invalide"
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return "retry", "joueur absent du serveur"
	end
	waitLoaded(player)
	if not (player.Parent and WalletStore.canChange(player)) then
		return "retry", "profil pas chargé ou pas sauvegardable"
	end
	local extra = string.format("+%d crédits", pack.credits)
	if PaidRandomPolicy.isRestricted(player) then
		-- Accordé quand même (voir l'en-tête) : signalé pour qu'on sache d'où viennent ces achats
		extra ..= ", joueur restreint (objets aléatoires payants)"
	end
	local verdict, why = "retry", "écriture en échec"
	for round = 1, WRITE_ROUNDS do
		local status, result = InventoryStore.transact(player, ReceiptRules.operation(info.PurchaseId, pack.credits))
		verdict, why = ReceiptRules.decide(status, result)
		if status ~= "failed" or round == WRITE_ROUNDS or not player.Parent then
			break
		end
		task.wait(ROUND_GAP)
	end
	return verdict, why, extra
end

-- Cette méthode permet de traiter un reçu pour Roblox lorsque ProcessReceipt est appelé : décision journalisée, et
-- `NotProcessedYet` sur une erreur imprévue (le reçu sera rejoué).
function ReceiptService.processReceipt(info: any): Enum.ProductPurchaseDecision
	local ok, verdict, why, extra = pcall(ReceiptService.handle, info)
	if not ok then
		verdict, why, extra = "retry", "erreur : " .. tostring(verdict), nil
	end
	logReceipt(verdict, why, info, extra)
	return if verdict == "granted"
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Cette méthode permet de décider d'une demande de prompt d'achat d'un pack lorsque le client clique sur un pack :
-- pack connu, joueur non restreint ; renvoie la réponse au client et le pack à proposer.
function ReceiptService.promptFor(player: Player, packId: string): (Reply, CreditPacks.Pack?)
	local pack = CreditPacks.byId(packId)
	if not pack then
		return { ok = false, reason = "unknown" }, nil
	end
	if PaidRandomPolicy.isRestricted(player) then
		return { ok = false, reason = "region" }, nil
	end
	return { ok = true }, pack
end

-- Cette méthode permet de poser le callback ProcessReceipt (une seule fois dans le jeu) et de brancher le remote du
-- prompt d'achat lorsque le serveur démarre ; le prompt est ouvert par le serveur après la garde commune.
function ReceiptService.init(buyPackRemote: RemoteFunction)
	local MarketplaceService = game:GetService("MarketplaceService")
	MarketplaceService.ProcessReceipt = ReceiptService.processReceipt
	buyPackRemote.OnServerInvoke = function(player: Player, packId: any): Reply
		if not CheatLog.admit(player, buyPackRemote.Name, packId) then
			return { ok = false, reason = "rate" }
		end
		local reply, pack = ReceiptService.promptFor(player, packId)
		if pack then
			local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, pack.productId)
			if not ok then
				warn("[Receipts] prompt impossible pour", player.Name, ":", err)
				return { ok = false, reason = "failed" }
			end
		end
		return reply
	end
end

return ReceiptService

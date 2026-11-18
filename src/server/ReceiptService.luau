-- Packs de crédits achetés en Robux (#395) : **seul** callback `MarketplaceService.ProcessReceipt` du jeu, et prompt
-- d'achat demandé par le client (remote `BuyCreditPack`). Règles d'économie : docs/economie.md.
--
-- Reçu : `PurchaseGranted` seulement après la `InventoryStore.transact` réussie qui ajoute les crédits du pack dans
-- `purchased` **et** inscrit le PurchaseId dans `wallet.receipts` (ReceiptRules) ; PurchaseId déjà inscrit →
-- `PurchaseGranted` sans rien ajouter. `NotProcessedYet` (Roblox rejoue le reçu au prochain achat ou à la prochaine
-- connexion du joueur, sans délai programmé ni remboursement) : produit inconnu, PurchaseId invalide, joueur absent,
-- inventaire pas chargé (attendu LOAD_WAIT s, le reçu arrive souvent à la connexion) ou pas sauvegardable, écriture en
-- échec (WRITE_ROUNDS tours espacés de ROUND_GAP s, sans risque : le PurchaseId rend chaque tour idempotent) ou refus
-- de l'opération (`invalid`). Solde au plafond : crédits écrêtés, reçu accordé (ReceiptRules). Chaque reçu est
-- journalisé (accordé, rejoué, refusé, motif). Le thread qui appelle `transact` n'est jamais annulé (Roblox n'impose
-- pas de délai à ProcessReceipt).
--
-- Joueur restreint (objets aléatoires payants, PaidRandomPolicy) : le prompt lui est refusé (`region`) et le bouton des
-- packs lui est masqué ; un reçu qui arrive quand même (achat par l'onglet Store de la page du jeu, client modifié) est
-- **accordé** et journalisé : Roblox ne rembourse jamais un reçu en attente, et les caisses lui sont bloquées
-- (CrateService), ses crédits achetés ne mènent donc à aucun objet aléatoire (choix de l'utilisateur, #395).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CreditPacks = require(ReplicatedStorage.Shared.CreditPacks)
local WalletRules = require(ReplicatedStorage.Shared.WalletRules)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local InventoryStore = require(ServerScriptService.Server.InventoryStore)
local PaidRandomPolicy = require(ServerScriptService.Server.PaidRandomPolicy)
local ReceiptRules = require(ServerScriptService.Server.ReceiptRules)
local WalletStore = require(ServerScriptService.Server.WalletStore)

local LOAD_WAIT = 30 -- s d'attente au plus de la fin du chargement de l'inventaire
local LOAD_POLL = 0.5 -- s entre deux regards pendant cette attente
local WRITE_ROUNDS = 3 -- transactions au plus pour un reçu dont l'écriture échoue (trois essais DataStore chacune)
local ROUND_GAP = 5 -- s entre deux de ces transactions
-- Studio seulement : attribut Player « idDuPack|PurchaseId » (contexte serveur), reçu simulé passé par processReceipt
local DEBUG_RECEIPT = "DebugReceipt"

export type Reply = { ok: boolean, reason: string? }
-- Rappels des analytics (#527) : prompt ouvert, crédits d'un reçu écrits (crédits réellement ajoutés)
export type Observers = {
	onPrompted: ((player: Player, packId: string) -> ())?,
	onCredited: ((player: Player, packId: string, credits: number) -> ())?,
}

local observers: Observers = {}

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
	local extra = string.format("pack de %d crédits", pack.credits)
	-- Lecture du cache seule : le reçu n'attend pas PolicyService pour une note du journal
	if PaidRandomPolicy.cached(player) == true then
		-- Accordé quand même (voir l'en-tête) : signalé pour qu'on sache d'où viennent ces achats
		extra ..= ", joueur restreint (objets aléatoires payants)"
	end
	local verdict, why = "retry", "écriture en échec"
	local status, result
	for round = 1, WRITE_ROUNDS do
		status, result = InventoryStore.transact(player, ReceiptRules.operation(info.PurchaseId, pack.credits))
		verdict, why = ReceiptRules.decide(status, result)
		if status ~= "failed" or round == WRITE_ROUNDS or not player.Parent then
			break
		end
		task.wait(ROUND_GAP)
	end
	-- Crédits écrits par ce reçu (pas un reçu rejoué ni une écriture retrouvée sans résultat) : comptés par les analytics
	if status == "ok" and type(result) == "table" and type(result.credits) == "number" and observers.onCredited then
		observers.onCredited(player, pack.id, result.credits)
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
	-- Pack retiré de la vente : ses reçus restent accordés, mais il n'est plus proposé
	if not pack or pack.retired then
		return { ok = false, reason = "unknown" }, nil
	end
	if PaidRandomPolicy.isRestricted(player) then
		return { ok = false, reason = "region" }, nil
	end
	-- Chargement fini mais solde pas modifiable (lecture en échec, format refusé) : chaque reçu attendrait la prochaine
	-- partie du joueur, ne pas lui faire payer un pack qu'il ne recevrait pas dans cette session
	if InventoryStore.isLoaded(player) and not WalletStore.canChange(player) then
		return { ok = false, reason = "loading" }, nil
	end
	-- Ids provisoires : produit inexistant, le prompt échouerait (Studio l'accepte, ses achats sont simulés)
	if not (CreditPacks.isReady() or RunService:IsStudio()) then
		return { ok = false, reason = "unavailable" }, nil
	end
	-- Un reçu au-delà du plafond serait écrêté (Robux payés pour moins de crédits) : ne pas proposer l'achat. Solde pas
	-- encore connu : proposé, le reçu attendra le chargement
	local balance = WalletStore.balance(player)
	if balance and balance + pack.credits > WalletRules.MAX_BALANCE then
		return { ok = false, reason = "full" }, nil
	end
	return { ok = true }, pack
end

-- Cette méthode permet, dans Studio, de faire passer un reçu simulé par le même traitement que ProcessReceipt lorsque
-- l'attribut `DebugReceipt` du joueur vaut « idDuPack|PurchaseId » (contexte serveur) ; remis à nil, décision affichée.
local function watchDebugReceipt(player: Player)
	player:GetAttributeChangedSignal(DEBUG_RECEIPT):Connect(function()
		local value = player:GetAttribute(DEBUG_RECEIPT)
		if type(value) ~= "string" then
			return
		end
		player:SetAttribute(DEBUG_RECEIPT, nil)
		local packId, purchaseId = string.match(value, "^([^|]+)|(.+)$")
		local pack = CreditPacks.byId(packId)
		local info = {
			PlayerId = player.UserId,
			ProductId = if pack then pack.productId else -1,
			PurchaseId = purchaseId,
		}
		task.spawn(function()
			local decision = ReceiptService.processReceipt(info)
			print("[DebugReceipt]", value, "→", decision.Name)
		end)
	end)
end

-- Cette méthode permet de poser le callback ProcessReceipt (une seule fois dans le jeu) et de brancher le remote du
-- prompt d'achat lorsque le serveur démarre ; le prompt est ouvert par le serveur après la garde commune.
-- `hooks` : rappels des analytics (#527), optionnels.
function ReceiptService.init(buyPackRemote: RemoteFunction, hooks: Observers?)
	observers = hooks or {}
	local MarketplaceService = game:GetService("MarketplaceService")
	MarketplaceService.ProcessReceipt = ReceiptService.processReceipt
	if RunService:IsStudio() then
		Players.PlayerAdded:Connect(watchDebugReceipt)
		for _, player in Players:GetPlayers() do
			watchDebugReceipt(player)
		end
	end
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
			if observers.onPrompted then
				observers.onPrompted(player, pack.id)
			end
		end
		return reply
	end
end

return ReceiptService

-- Inventaire des joueurs (#267), décidé par le serveur : items possédés = inventaire par défaut (Ka-Bar, AWP) + items
-- sauvegardés (DataStore `PlayerInventory_v1`) + tout le catalogue pour un admin (`Roles`, #266). Règles pures dans
-- `InventoryRules`. Le serveur ne place dans le sac que les Tools possédés, copiés de `ReplicatedStorage.Tools` (le
-- StarterPack est vide : rien n'est donné d'office), à chaque apparition et à chaque changement d'inventaire ; un Tool
-- non possédé qui arrive en main est retiré (`init.server`, `trackWeapon3P`) et le Validator refuse ses tirs et coups.
-- Lecture DataStore en échec (ou données d'une version plus récente) : inventaire par défaut (et admin), sauvegarde
-- coupée pour la session. Écriture par UpdateAsync qui réunit les ids déjà enregistrés et ceux de la session (un
-- inventaire ne fait que grandir) : une sauvegarde en retard ou d'un autre serveur n'efface rien.
-- Équipement (#280) : une arme par emplacement (SNIPER, COUTEAU) et son skin, choisis à l'accueil (remote `EquipItem`,
-- refusé en partie) et enregistrés dans le même DataStore (`equipped`) ; seules les armes équipées vont dans le sac.
-- Le choix est résolu contre les items possédés : un item qui ne l'est plus laisse la place à l'équipement par défaut.
-- Studio seulement : attribut Player `DebugInventory` = "default" (posé en contexte serveur), le joueur est traité
-- comme un non-admin, pour vérifier l'inventaire par défaut avec le compte propriétaire.
-- Crédits (#396) : le portefeuille (`wallet`, WalletRules) est dans le même enregistrement. Les gains de la session
-- partent en lots numérotés avec chaque écriture (`addCredits`) ; un débit ou un achat passe par `transact`, une
-- UpdateAsync immédiate qui applique une opération pure à l'enregistrement stocké et rend son résultat après
-- l'écriture. Les écritures d'un joueur (sauvegarde ou transaction) passent une à la fois, dans l'ordre d'arrivée.
-- Façade de l'API des crédits : WalletStore. Contrat de `transact` : docs/architecture.md (« Crédits »).
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPack = game:GetService("StarterPack")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local WalletRules = require(ReplicatedStorage.Shared.WalletRules)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local Participants = require(ServerScriptService.Server.Participants)
local Roles = require(ServerScriptService.Server.Roles)

local DEBUG_ATTRIBUTE = "DebugInventory"
local BACKPACK_WAIT = 5 -- s d'attente maximale du sac d'un personnage qui vient d'apparaître
local CLOSE_WAIT = 25 -- s d'attente maximale des sauvegardes en vol à l'arrêt du serveur (budget Roblox : 30 s)
local SAVE_RETRY_DELAY = 60 -- s avant un nouvel essai d'une sauvegarde en échec (panne passagère du DataStore)
local MAX_SAVE_FAILURES = 5 -- échecs d'affilée (de 3 essais chacun) avant d'abandonner l'écriture d'un profil
-- s minimum entre deux écritures d'un même profil après un changement d'équipement : Roblox limite les écritures d'une
-- clé (une toutes les 6 s), des clics rapprochés sont réunis en une seule écriture
local EQUIP_SAVE_SPACING = 6
-- s entre un gain de crédits et son écriture (#396) : les gains rapprochés (une manche) partent ensemble ; au moins
-- EQUIP_SAVE_SPACING, l'espacement entre deux écritures est donc toujours tenu
local GAINS_SAVE_DELAY = 6

-- owned : items possédés, recalculés à chaque changement (setup, chargement, déblocage, debug) et lus à chaque tir.
-- equipped : choix relu puis modifié (#280, nil tant que rien n'est choisi ni relu) ; chosen : emplacements choisis dans
-- cette session, seuls écrits (un autre serveur garde les siens) ; resolved : équipement appliqué, recalculé avec owned.
-- Portefeuille (#396) : wallet, dernier état stocké connu ; session/seq, id de cette session et dernier numéro de lot
-- donné ; batches, lots de gains envoyés et pas encore confirmés (renvoyés tels quels) ; gains, gagnés depuis le dernier
-- lot ; sessionOnly, solde de session de Studio (DebugCredits sans accès aux API), jamais écrit.
-- saving : une écriture du profil est en cours ; waiters : transactions en attente de leur tour (FIFO).
type Profile = {
	stored: { string },
	owned: InventoryRules.Owned,
	equipped: InventoryRules.Equipped?,
	chosen: InventoryRules.Equipped,
	resolved: InventoryRules.Equipped,
	loaded: boolean,
	dirty: boolean,
	saving: boolean,
	waiters: { thread },
	lastSaveAt: number,
	canSave: boolean,
	failures: number,
	wallet: WalletRules.Wallet,
	session: string,
	seq: number,
	batches: { WalletRules.Batch },
	gains: number,
	sessionOnly: boolean,
}

-- Issue d'une transaction : écrite (`ok`, opération appliquée ou déjà appliquée par un essai signalé en échec), refusée
-- par l'opération selon l'état stocké (`rejected`, rien d'écrit), inventaire pas chargé ou pas sauvegardable
-- (`loading`), écriture en échec (`failed`, rien d'appliqué)
export type TransactStatus = "ok" | "rejected" | "loading" | "failed"

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
-- Sauvegardes en cours, attendues par BindToClose (celles lancées au départ d'un joueur comprises)
local savesInFlight = 0
-- Sauvegardes programmées plus tard (espacement, nouvel essai), lancées tout de suite par BindToClose : le joueur peut
-- être déjà parti (plus dans `profiles`)
local pendingSaves: { [Profile]: { player: Player, due: number } } = {}
-- Chargement d'un personnage en vol (SpawnManager.isSpawning), branché par init
local spawningCheck: (Player) -> boolean = function(_player: Player)
	return false
end
-- Arrêt du serveur en cours (BindToClose) : une sauvegarde en échec est retentée tout de suite, pas après un délai
local closing = false
-- Inventaire des bots (#267) : celui par défaut, jamais sauvegardé
local BOT_OWNED = InventoryRules.resolve(nil, false)

local InventoryStore = {}

-- Cette méthode permet d'ouvrir le DataStore une seule fois lorsque le premier joueur arrive ; nil si les services
-- d'API sont coupés (Studio sans « Enable Studio Access to API Services »).
local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "PlayerInventory_v1")
	if ok then
		store = result
	end
	return store
end

-- Cette méthode permet de lire ou d'écrire le DataStore avec trois essais espacés lorsque le réseau ou les quotas
-- refusent une requête ; renvoie la réussite et le résultat.
local function withRetry(fn: () -> any): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < 3 then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

-- Cette méthode permet de savoir si un joueur compte comme admin pour l'inventaire lorsqu'il est calculé : rôle Admin,
-- sauf en Studio sous `DebugInventory` = "default" (simulation d'un non-admin).
local function isAdmin(player: Player): boolean
	if RunService:IsStudio() and player:GetAttribute(DEBUG_ATTRIBUTE) == "default" then
		return false
	end
	return Roles.hasRole(player, Roles.ADMIN)
end

-- Cette méthode permet de lire les items possédés d'un joueur lorsqu'un système serveur en a besoin ; joueur inconnu
-- (parti, pas encore inscrit) : l'inventaire par défaut (et tout pour un admin).
function InventoryStore.owned(player: Player): InventoryRules.Owned
	local profile = profiles[player]
	return if profile then profile.owned else InventoryRules.resolve(nil, isAdmin(player))
end

-- Cette méthode permet de savoir si un participant possède un Tool lorsque le serveur valide un equip, un tir ou un
-- coup (Validator) : inventaire du joueur, inventaire par défaut pour un bot.
function InventoryStore.ownsTool(participant: Participants.Participant, toolName: string): boolean
	local player = participant.player
	local owned = if participant.isBot or not player then BOT_OWNED else InventoryStore.owned(player)
	return InventoryRules.ownsTool(owned, toolName)
end

-- Cette méthode permet de lire l'équipement appliqué d'un joueur (#280) lorsqu'un système serveur en a besoin ; joueur
-- inconnu : l'équipement par défaut.
function InventoryStore.equipped(player: Player): InventoryRules.Equipped
	local profile = profiles[player]
	return if profile then profile.resolved else InventoryRules.resolveEquipped(nil, InventoryStore.owned(player))
end

-- Cette méthode permet de lister les Tools du joueur (sac et main) lorsqu'ils sont comparés à son inventaire.
local function presentTools(player: Player): { Tool }
	local tools: { Tool } = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					table.insert(tools, child)
				end
			end
		end
	end
	return tools
end

-- Cette méthode permet de mettre le sac d'un joueur en accord avec son équipement lorsqu'il apparaît, qu'un nouveau sac
-- lui est donné ou que son inventaire change : Tools des armes équipées (#280) copiés de ReplicatedStorage.Tools, les
-- autres retirés (main comprise). Idempotente : sans effet si le sac est déjà juste.
function InventoryStore.syncTools(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return -- au menu ou mort (corps encore en place) : le sac sera rempli à l'apparition
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", BACKPACK_WAIT)
	if not (backpack and backpack:IsA("Backpack")) or player.Character ~= character then
		return
	end
	local tools = presentTools(player)
	local names = {}
	for _, tool in tools do
		table.insert(names, tool.Name)
	end
	local wanted = InventoryRules.equippedTools(InventoryStore.equipped(player))
	local give, remove = InventoryRules.toolChanges(wanted, names)
	for _, tool in tools do
		if table.find(remove, tool.Name) then
			tool:Destroy()
		end
	end
	local folder = ReplicatedStorage:FindFirstChild("Tools")
	for _, name in give do
		local source = folder and folder:FindFirstChild(name)
		if source and source:IsA("Tool") then
			source:Clone().Parent = backpack
		else
			warn("[InventoryStore] Tool " .. name .. " introuvable dans ReplicatedStorage.Tools")
		end
	end
end

-- Cette méthode permet de recalculer et publier l'inventaire et l'équipement d'un joueur (attributs informatifs
-- `OwnedItems` et `EquippedItems`, lus par l'accueil et les Réglages du client) et de remettre son sac en accord
-- lorsqu'ils changent (chargement, déblocage, équipement, debug Studio).
local function refresh(player: Player, profile: Profile)
	profile.owned = InventoryRules.resolve(profile.stored, isAdmin(player))
	profile.resolved = InventoryRules.resolveEquipped(profile.equipped, profile.owned)
	if not player.Parent then
		return
	end
	player:SetAttribute(InventoryRules.ATTRIBUTE, InventoryRules.encode(profile.owned))
	player:SetAttribute(InventoryRules.EQUIPPED_ATTRIBUTE, InventoryRules.encodeEquipped(profile.resolved))
	task.spawn(InventoryStore.syncTools, player)
end

-- Cette méthode permet de savoir si le solde d'un profil est connu et peut changer : inventaire chargé et
-- sauvegardable, ou solde de session de Studio.
local function walletReady(profile: Profile?): boolean
	return profile ~= nil and profile.loaded and (profile.canSave or profile.sessionOnly)
end

-- Cette méthode permet de calculer le solde d'un profil (stocké connu, plus lots pas encore confirmés et gains pas
-- encore mis en lot) lorsqu'un système serveur ou l'attribut du Player le lit.
local function walletBalance(profile: Profile): number
	local pending = profile.gains
	for _, batch in profile.batches do
		pending += batch.earned
	end
	return WalletRules.clamp(WalletRules.balance(profile.wallet) + pending)
end

-- Cette méthode permet de poser l'attribut informatif `Credits` (gagnés + achetés) lorsque le solde change ou est
-- relu ; rien tant que le solde n'est pas connu, pour que le menu affiche « — » plutôt qu'un 0 trompeur.
local function publishWallet(player: Player, profile: Profile)
	if walletReady(profile) and profiles[player] == profile and player.Parent then
		player:SetAttribute(WalletRules.ATTRIBUTE, walletBalance(profile))
	end
end

-- Cette méthode permet d'adopter le portefeuille stocké relu ou écrit lorsqu'une écriture se termine : les lots que
-- sa marque de session couvre y sont déjà, ils ne sont plus à renvoyer.
local function adoptWallet(profile: Profile, raw: any)
	profile.wallet = WalletRules.read(raw)
	local applied = WalletRules.appliedSeq(profile.wallet, profile.session)
	local remaining: { WalletRules.Batch } = {}
	for _, batch in profile.batches do
		if batch.seq > applied then
			table.insert(remaining, batch)
		end
	end
	profile.batches = remaining
end

-- Cette méthode permet de préparer la part portefeuille d'une écriture lorsqu'elle part : les gains en attente forment
-- un nouveau lot, une transaction reçoit son propre numéro (`upTo`) ; les lots partent tous jusqu'à confirmation.
local function walletChange(profile: Profile, forOperation: boolean): InventoryRules.WalletChange
	if profile.gains > 0 then
		profile.seq += 1
		table.insert(profile.batches, { seq = profile.seq, earned = profile.gains })
		profile.gains = 0
	end
	if forOperation then
		profile.seq += 1
	end
	return { session = profile.session, batches = table.clone(profile.batches), upTo = profile.seq }
end

local saveProfile: (Player, Profile) -> ()

-- Cette méthode permet de programmer une seule écriture d'un profil (espacée d'EQUIP_SAVE_SPACING, ou après `delay`),
-- l'échéance la plus proche l'emportant, lorsqu'un changement ne peut pas partir tout de suite ; BindToClose l'avance.
local function queueSave(player: Player, profile: Profile, delay: number?)
	local wait = delay or math.max(0, profile.lastSaveAt + EQUIP_SAVE_SPACING - os.clock())
	local due = os.clock() + wait
	local current = pendingSaves[profile]
	if current and current.due <= due then
		return
	end
	local entry = { player = player, due = due }
	pendingSaves[profile] = entry
	task.delay(wait, function()
		if pendingSaves[profile] == entry then
			pendingSaves[profile] = nil
			saveProfile(player, profile)
		end
	end)
end

-- Cette méthode permet de prendre le tour d'écriture d'un profil lorsqu'une transaction arrive : tout de suite s'il est
-- libre, sinon après les écritures déjà en cours ou en attente (le tour est passé par `release`).
local function acquire(profile: Profile)
	if profile.saving then
		table.insert(profile.waiters, coroutine.running())
		coroutine.yield()
	else
		profile.saving = true
	end
end

-- Cette méthode permet de rendre le tour d'écriture d'un profil lorsqu'une écriture se termine : à la transaction
-- suivante s'il y en a une (elle écrit aussi ce qui reste), sinon une sauvegarde de ce qui a changé entre-temps est
-- programmée (tout de suite à l'arrêt, après SAVE_RETRY_DELAY après un échec, sinon espacée d'EQUIP_SAVE_SPACING).
local function release(player: Player, profile: Profile)
	local waiter = table.remove(profile.waiters, 1)
	if waiter then
		task.spawn(waiter)
		return
	end
	profile.saving = false
	if not (profile.dirty and profile.canSave) or profile.failures >= MAX_SAVE_FAILURES then
		return
	end
	if closing then
		saveProfile(player, profile)
	elseif profile.failures > 0 then
		queueSave(player, profile, SAVE_RETRY_DELAY)
	else
		queueSave(player, profile)
	end
end

-- Cette méthode permet de signaler une écriture en échec lorsqu'elle a épuisé ses essais : le profil reste à écrire
-- (lots de gains compris), retenté par `release` MAX_SAVE_FAILURES fois au plus, joueur parti compris.
local function noteFailure(player: Player, profile: Profile)
	profile.dirty = true
	profile.failures += 1
	if profile.failures >= MAX_SAVE_FAILURES then
		warn("[InventoryStore] sauvegarde abandonnée pour", player.Name, "après", profile.failures, "échecs")
	elseif closing then
		warn("[InventoryStore] sauvegarde impossible pour", player.Name, "— nouvel essai avant l'arrêt")
	else
		warn("[InventoryStore] sauvegarde impossible pour", player.Name, "— nouvel essai dans", SAVE_RETRY_DELAY, "s")
	end
end

-- Cette méthode permet de couper la sauvegarde d'un profil lorsqu'une écriture trouve un format stocké que cette
-- version ne sait pas réécrire (écrit entre-temps par un serveur plus récent).
local function noteRefused(player: Player, profile: Profile)
	profile.canSave = false
	warn("[InventoryStore] format enregistré inconnu pour", player.Name, "— inventaire et crédits non sauvegardés")
end

-- Cette méthode permet d'écrire l'inventaire d'un profil s'il a changé (item obtenu, équipement, gains, départ, arrêt),
-- une écriture à la fois (InventoryRules.mergeForSave) ; un changement arrivé pendant l'écriture en relance une.
function saveProfile(player: Player, profile: Profile)
	local ds = getStore()
	if not (ds and profile.loaded and profile.canSave and profile.dirty) or profile.saving then
		return
	end
	profile.saving = true
	profile.dirty = false
	-- Au départ de l'écriture : les clics qui arrivent pendant qu'elle part se calent sur EQUIP_SAVE_SPACING
	profile.lastSaveAt = os.clock()
	savesInFlight += 1
	local stored = profile.stored
	-- Seuls les emplacements choisis dans cette session : ceux relus au chargement ne réécrasent pas un autre serveur
	local chosen = table.clone(profile.chosen)
	local change = walletChange(profile, false)
	local status: InventoryRules.MergeStatus = "refused"
	local ok, written = withRetry(function()
		return ds:UpdateAsync(tostring(player.UserId), function(old)
			local record
			record, status = InventoryRules.mergeForSave(old, stored, chosen, change)
			return record
		end)
	end)
	savesInFlight -= 1
	if ok and status == "refused" then
		noteRefused(player, profile)
	elseif ok then
		profile.failures = 0
		adoptWallet(profile, written and written.wallet)
		publishWallet(player, profile)
	else
		noteFailure(player, profile)
	end
	release(player, profile)
end

-- Cette méthode permet d'appliquer une opération à l'enregistrement stocké d'un joueur, dans une seule UpdateAsync
-- immédiate (débit, achat : portefeuille et objets ensemble), après les écritures déjà en cours de ce joueur ; renvoie
-- l'issue (TransactStatus) et le résultat de l'opération, une fois l'écriture terminée. Contrat : docs/architecture.md.
function InventoryStore.transact(player: Player, op: InventoryRules.Operation): (TransactStatus, any)
	local profile = profiles[player]
	local ds = getStore()
	if not (ds and profile and profile.loaded and profile.canSave) then
		return "loading", nil
	end
	local p = profile :: Profile
	acquire(p)
	if not p.canSave then
		-- Format inconnu trouvé par l'écriture précédente pendant l'attente
		release(player, p)
		return "loading", nil
	end
	local wasDirty = p.dirty
	p.dirty = false
	p.lastSaveAt = os.clock()
	savesInFlight += 1
	local stored = p.stored
	local chosen = table.clone(p.chosen)
	local change = walletChange(p, true)
	local status: InventoryRules.MergeStatus = "refused"
	local result: any = nil
	local seen: any = nil
	local key = tostring(player.UserId)
	local ok, written = withRetry(function()
		return ds:UpdateAsync(key, function(old)
			local record
			record, status, result = InventoryRules.mergeForSave(old, stored, chosen, change, op)
			seen = old
			return record
		end)
	end)
	if not ok then
		-- Tous les essais signalés en échec : l'un d'eux a pu passer (réponse perdue). La marque de l'opération le dit.
		local readOk, data = pcall(function()
			return ds:GetAsync(key)
		end)
		local wallet = WalletRules.read(if readOk and type(data) == "table" then data.wallet else nil)
		if readOk and WalletRules.appliedSeq(wallet, p.session) >= change.upTo then
			ok, written, status, result = true, data, "replayed", nil
		end
	end
	savesInFlight -= 1
	local outcome: TransactStatus
	if ok and status == "refused" then
		p.dirty = wasDirty
		noteRefused(player, p)
		outcome = "loading"
	elseif ok and status == "rejected" then
		-- Rien d'écrit : l'état stocké relu remplace la copie locale, le reste de la session reste à écrire
		adoptWallet(p, if type(seen) == "table" then seen.wallet else nil)
		p.dirty = wasDirty or #p.batches > 0
		outcome = "rejected"
	elseif ok then
		p.failures = 0
		adoptWallet(p, written and written.wallet)
		local items = InventoryRules.sanitizeStored(written and written.items, math.huge)
		if #items ~= #p.stored then
			p.stored = items
			refresh(player, p)
		end
		outcome = "ok"
	else
		noteFailure(player, p)
		outcome = "failed"
	end
	publishWallet(player, p)
	release(player, p)
	return outcome, result
end

-- Cette méthode permet d'écrire l'inventaire d'un joueur inscrit s'il a changé (cf. saveProfile).
function InventoryStore.save(player: Player)
	local profile = profiles[player]
	if profile then
		saveProfile(player, profile)
	end
end

-- Cette méthode permet d'inscrire un joueur lorsqu'il arrive, avant le chargement DataStore : inventaire par défaut (et
-- admin) publié tout de suite, pour que le client n'attende pas le DataStore ; un nouveau sac (réapparition) est
-- resynchronisé.
function InventoryStore.setup(player: Player)
	local profile: Profile = {
		stored = {},
		owned = {},
		equipped = nil,
		chosen = {},
		resolved = {},
		loaded = false,
		dirty = false,
		saving = false,
		waiters = {},
		lastSaveAt = -math.huge,
		canSave = false,
		failures = 0,
		wallet = WalletRules.empty(),
		session = HttpService:GenerateGUID(false),
		seq = 0,
		batches = {},
		gains = 0,
		sessionOnly = false,
	}
	profiles[player] = profile
	refresh(player, profile)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			task.spawn(InventoryStore.syncTools, player)
		end
	end)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
			if profiles[player] == profile then
				refresh(player, profile)
			end
		end)
	end
end

-- Cette méthode permet de charger l'inventaire sauvegardé d'un joueur lorsqu'il arrive ; un échec de lecture (ou des
-- données d'une version plus récente) garde l'inventaire par défaut et coupe la sauvegarde pour la session, pour ne pas
-- écraser ses vraies données.
function InventoryStore.load(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local ds = getStore()
	local ok, data = false, nil
	if ds then
		ok, data = withRetry(function()
			return ds:GetAsync(tostring(player.UserId))
		end)
	end
	if profiles[player] ~= profile then
		return -- parti pendant le chargement
	end
	local stored, canSave, equipped, wallet = InventoryRules.loadOutcome(ok, data)
	profile.stored = stored
	profile.canSave = canSave
	profile.wallet = wallet
	-- Rien d'enregistré : nil, pour qu'une sauvegarde garde l'équipement qu'un autre serveur aurait écrit entre-temps
	profile.equipped = if next(equipped) ~= nil then equipped else nil
	profile.loaded = true
	if not canSave then
		-- Pas d'attribut `Credits` non plus : le menu reste sur « — »
		warn("[InventoryStore] chargement impossible pour", player.Name, "— inventaire par défaut, non sauvegardé")
	end
	refresh(player, profile)
	publishWallet(player, profile)
end

-- Cette méthode permet de lire le solde de crédits d'un joueur (stocké connu plus gains pas encore écrits) lorsqu'un
-- système serveur le consulte (WalletStore.balance) ; nil tant qu'il n'est pas chargé ou si son chargement a échoué.
function InventoryStore.credits(player: Player): number?
	local profile = profiles[player]
	if not walletReady(profile) then
		return nil
	end
	return walletBalance(profile :: Profile)
end

-- Cette méthode permet de savoir si le solde d'un joueur peut changer lorsqu'un système serveur s'apprête à donner ou
-- faire payer (WalletStore.canChange).
function InventoryStore.canChangeCredits(player: Player): boolean
	return walletReady(profiles[player])
end

-- Cette méthode permet de créditer des gains à un joueur lorsqu'il en gagne (WalletStore.add) : ajoutés à `earned` par
-- la prochaine écriture (lot numéroté, GAINS_SAVE_DELAY s plus tard), écrêtés au plafond ; false si le montant est
-- invalide ou si le solde ne peut pas changer.
function InventoryStore.addCredits(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not (WalletRules.isAmount(amount) and walletReady(profile)) then
		return false
	end
	local p = profile :: Profile
	local room = WalletRules.MAX_BALANCE - walletBalance(p)
	if room <= 0 then
		return true
	end
	local gain = math.min(amount, room)
	if p.sessionOnly then
		p.wallet.earned += gain
	else
		p.gains += gain
		p.dirty = true
		queueSave(player, p, GAINS_SAVE_DELAY)
	end
	publishWallet(player, p)
	return true
end

-- Cette méthode permet, dans Studio sans accès aux API (chargement en échec), de passer le portefeuille d'un joueur en
-- solde de session (départ, jamais écrit) lorsque `DebugCredits` est posé ; sans effet si le solde est déjà connu.
function InventoryStore.startSessionWallet(player: Player)
	local profile = profiles[player]
	if profile and profile.loaded and not profile.canSave and not profile.sessionOnly then
		profile.sessionOnly = true
		profile.wallet = WalletRules.empty()
		publishWallet(player, profile)
	end
end

-- Cette méthode permet de débiter le solde de session de Studio lorsqu'une dépense arrive sans accès aux API (pas
-- d'écriture) ; renvoie l'issue comme `transact` ("ok", "rejected" avec le motif, "loading" hors solde de session).
function InventoryStore.debitSession(player: Player, amount: number): (TransactStatus, any)
	local profile = profiles[player]
	if not (profile and profile.sessionOnly) then
		return "loading", nil
	end
	local wallet, reason = WalletRules.debit(profile.wallet, amount)
	if not wallet then
		return "rejected", reason
	end
	profile.wallet = wallet
	publishWallet(player, profile)
	return "ok", nil
end

-- Cette méthode permet de savoir si les crédits d'un joueur passent par le solde de session de Studio (jamais écrit)
-- lorsqu'une dépense arrive.
function InventoryStore.isSessionWallet(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.sessionOnly
end

-- Cette méthode permet de savoir si un item obtenu serait gardé lorsqu'une ouverture de caisse (#332) va le tirer :
-- inventaire chargé et sauvegardable (sinon `grant` refuse et le tirage serait perdu).
function InventoryStore.canGrant(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.loaded and profile.canSave
end

-- Cette méthode permet de donner un item à un joueur lorsqu'il l'obtient (boutique, déblocage : à venir, hors #267) :
-- ajouté, publié, sac mis à jour, écrit tout de suite. Refusé (false) tant que l'inventaire n'est pas chargé ou s'il ne
-- peut pas être sauvegardé (l'item serait perdu au départ), ou si l'id est inconnu ou déjà possédé.
function InventoryStore.grant(player: Player, id: string): boolean
	local profile = profiles[player]
	if not (profile and profile.loaded and profile.canSave) then
		return false
	end
	local stored, changed = InventoryRules.grant(profile.stored, id)
	if not changed then
		return false
	end
	profile.stored = stored
	profile.dirty = true
	refresh(player, profile)
	task.spawn(saveProfile, player, profile)
	return true
end

-- Cette méthode permet d'équiper une arme et son skin (nil : d'origine) lorsque le joueur clique à l'accueil (#280),
-- refusé avant le chargement, personnage en jeu ou item invalide (InventoryRules.equip) ; renvoie l'acceptation, le motif.
function InventoryStore.equip(player: Player, slot: any, weaponId: any, skinId: any): (boolean, string?)
	local profile = profiles[player]
	if not (profile and profile.loaded) then
		return false, "loading"
	end
	-- Personnage en jeu (vivant ou corps pas encore détruit) ou en chargement : on ne change d'équipement qu'au menu.
	-- Limite : mort en partie, corps détruit, avant la réapparition, un client modifié passe (docs/anticheat.md)
	local character = player.Character
	if (character and character.Parent) or spawningCheck(player) then
		return false, "in_round"
	end
	local equipped, reason = InventoryRules.equip(profile.equipped or {}, profile.owned, slot, weaponId, skinId)
	if not equipped then
		return false, reason
	end
	profile.equipped = equipped
	profile.chosen[slot] = equipped[slot]
	refresh(player, profile)
	if profile.canSave then
		profile.dirty = true
		-- Tout de suite si la dernière écriture date d'EQUIP_SAVE_SPACING, sinon une seule pour les clics rapprochés
		queueSave(player, profile)
	end
	return true
end

-- Cette méthode permet de vider le StarterPack lorsque le serveur démarre : une place Studio enregistrée avant #267 peut
-- encore y garder les Tools, que Roblox donnerait à tout joueur à chaque apparition.
local function clearStarterPack()
	for _, child in StarterPack:GetChildren() do
		if child:IsA("Tool") then
			warn("[InventoryStore] Tool " .. child.Name .. " retiré du StarterPack (distribué selon l'inventaire)")
			child:Destroy()
		end
	end
end

-- Motifs de refus d'un `EquipItem` qu'un client honnête n'envoie pas (il ne montre que les items possédés de chaque
-- emplacement) : journalisés. Les autres (chargement en cours, personnage en partie) tiennent au moment du clic.
local SUSPECT_REFUSALS = { unknown = true, wrong_slot = true, not_owned = true, wrong_skin = true }

-- Cette méthode permet de brancher le remote d'équipement (#280), le départ des joueurs et l'arrêt du serveur lorsque le
-- serveur démarre ; à l'arrêt, il attend les sauvegardes en vol (CLOSE_WAIT au plus).
function InventoryStore.init(equipRemote: RemoteEvent, isSpawning: (Player) -> boolean)
	clearStarterPack()
	spawningCheck = isSpawning
	equipRemote.OnServerEvent:Connect(function(player: Player, slot: any, weaponId: any, skinId: any)
		-- Garde commune (#170) : débit, emplacement connu, ids bornés
		if not CheatLog.admit(player, equipRemote.Name, slot, weaponId, skinId) then
			return
		end
		local ok, reason = InventoryStore.equip(player, slot, weaponId, if skinId == "" then nil else skinId)
		if not ok and reason and SUSPECT_REFUSALS[reason] then
			CheatLog.report(
				Participants.fromPlayer(player),
				CheatLog.Category.INVENTORY,
				CheatLog.Severity.LOW,
				string.format("équipement refusé (%s) : %s %s %s", reason, slot, weaponId, skinId)
			)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			saveProfile(player, profile)
		end
	end)
	game:BindToClose(function()
		closing = true
		-- Écritures programmées plus tard (joueurs partis compris) : lancées maintenant
		for profile, entry in pendingSaves do
			pendingSaves[profile] = nil
			task.spawn(saveProfile, entry.player, profile)
		end
		for player, profile in profiles do
			task.spawn(saveProfile, player, profile)
		end
		local deadline = os.clock() + CLOSE_WAIT
		while savesInFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return InventoryStore

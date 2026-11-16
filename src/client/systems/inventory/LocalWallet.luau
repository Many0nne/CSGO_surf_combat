-- Copie client du solde de crédits du joueur (#391) : lue dans l'attribut informatif `Credits` posé par le serveur
-- (WalletStore), pour le solde de la barre du menu (MainMenu). N'ouvre aucun droit : seul le serveur change un solde.
-- Sans attribut (pas encore chargé, ou chargement en échec) : nil, affiché « — ». Lit aussi la restriction des objets
-- aléatoires payants (#395, attribut `PaidRandomRestricted`), informative elle aussi : le serveur refuse de son côté.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WalletRules"))
local EconomyRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyRules"))
local CreditPacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CreditPacks"))

local LocalWallet = {}

local player = Players.LocalPlayer

-- Cette méthode permet de lire les gains en jouant du jour UTC (#394, attribut `DailyCredits`) lorsque le shop ou l'écran
-- de fin de manche les affiche ; jour pris à l'heure du serveur, 0 après minuit UTC, nil tant que ce n'est pas chargé.
function LocalWallet.dailyEarned(): number?
	local today = EconomyRules.day(workspace:GetServerTimeNow())
	return EconomyRules.decodeDaily(player:GetAttribute(EconomyRules.DAILY_ATTRIBUTE), today)
end

local DAY_MARGIN = 1 -- s après minuit UTC avant de prévenir les écrans (le jour a bien changé côté serveur)

-- Abonnés au changement de jour : un jeton par abonnement (la même fonction peut s'abonner deux fois)
local dayListeners: { [{}]: () -> () } = {}
local dayTimerRunning = false

-- Cette méthode permet de prévenir les écrans abonnés au gain du jour lorsque minuit UTC est passé (une seule
-- minuterie partagée, relancée sur l'heure serveur à chaque jour, jamais de boucle par frame) ; sans abonné, le fil
-- s'arrête à son prochain réveil, et un abonné qui échoue n'empêche ni les autres ni les jours suivants.
local function runDayTimer()
	if dayTimerRunning then
		return
	end
	dayTimerRunning = true
	task.spawn(function()
		while next(dayListeners) ~= nil do
			task.wait(EconomyRules.secondsUntilNextDay(workspace:GetServerTimeNow()) + DAY_MARGIN)
			for _, listener in table.clone(dayListeners) do
				task.spawn(listener)
			end
		end
		dayTimerRunning = false
	end)
end

-- Cette méthode permet d'appeler `callback` maintenant, à chaque changement de l'attribut des gains du jour et à
-- chaque changement de jour UTC lorsqu'un écran affiche `dailyEarned` ; renvoie une fonction de désabonnement.
function LocalWallet.observeDaily(callback: () -> ()): () -> ()
	local token = {}
	local conn = player:GetAttributeChangedSignal(EconomyRules.DAILY_ATTRIBUTE):Connect(callback)
	dayListeners[token] = callback
	runDayTimer()
	-- Premier appel protégé : une erreur est relancée à part, sans perdre le désabonnement
	local ok, err = pcall(callback)
	if not ok then
		task.spawn(error, err)
	end
	return function()
		conn:Disconnect()
		dayListeners[token] = nil
	end
end

-- Cette méthode permet de lire le solde du joueur lorsqu'un écran l'affiche ; nil tant qu'il n'est pas chargé.
function LocalWallet.balance(): number?
	return WalletRules.decode(player:GetAttribute(WalletRules.ATTRIBUTE))
end

-- Cette méthode permet d'appeler `callback` avec le solde maintenant puis à chaque changement lorsqu'un écran suit le
-- solde ; renvoie la connexion.
function LocalWallet.observe(callback: (number?) -> ()): RBXScriptConnection
	callback(LocalWallet.balance())
	return player:GetAttributeChangedSignal(WalletRules.ATTRIBUTE):Connect(function()
		callback(LocalWallet.balance())
	end)
end

-- Cette méthode permet de lire si le joueur est restreint pour les objets aléatoires payants (#395, attribut
-- `PaidRandomRestricted` posé par le serveur) lorsque le shop peint ses achats ; nil tant que ce n'est pas connu.
function LocalWallet.restricted(): boolean?
	local value = player:GetAttribute(CreditPacks.RESTRICTED_ATTRIBUTE)
	return if type(value) == "boolean" then value else nil
end

-- Cette méthode permet d'appeler `callback` maintenant puis à chaque changement de la restriction lorsqu'un écran
-- montre ou bloque un achat ; renvoie la connexion.
function LocalWallet.observeRestricted(callback: (boolean?) -> ()): RBXScriptConnection
	callback(LocalWallet.restricted())
	return player:GetAttributeChangedSignal(CreditPacks.RESTRICTED_ATTRIBUTE):Connect(function()
		callback(LocalWallet.restricted())
	end)
end

return LocalWallet

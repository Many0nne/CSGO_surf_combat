-- Copie client du solde de crédits du joueur (#391) : lue dans l'attribut informatif `Credits` posé par le serveur
-- (WalletStore), pour le solde de la barre du menu (MainMenu). N'ouvre aucun droit : seul le serveur change un solde.
-- Sans attribut (pas encore chargé, ou chargement en échec) : nil, affiché « — ».
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WalletRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WalletRules"))
local EconomyRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyRules"))

local LocalWallet = {}

local player = Players.LocalPlayer

-- Cette méthode permet de lire les gains en jouant du jour UTC (#394, attribut `DailyCredits`) lorsque le shop ou l'écran
-- de fin de manche les affiche ; jour pris à l'heure du serveur, 0 après minuit UTC, nil tant que ce n'est pas chargé.
function LocalWallet.dailyEarned(): number?
	local today = EconomyRules.day(workspace:GetServerTimeNow())
	return EconomyRules.decodeDaily(player:GetAttribute(EconomyRules.DAILY_ATTRIBUTE), today)
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

return LocalWallet

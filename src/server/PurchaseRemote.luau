-- Garde d'achat commune aux services serveur à remote d'achat (CrateService, OutfitService) : un seul achat en vol par
-- joueur (`busy`), achat sous `pcall` (`failed` + `warn` sur erreur, verrou toujours rendu) et branchement du remote
-- (garde `CheatLog.admit` → `rate`, achat, rappel `onBought`, réponse). Le thread d'un achat n'est jamais annulé (il
-- porte l'écriture, cf. InventoryStore.transact) : pas de timeout ici. Le type de réponse reste celui du service, qui
-- fournit son `refuse`.
local ServerScriptService = game:GetService("ServerScriptService")

local CheatLog = require(ServerScriptService.Server.CheatLog)

local PurchaseRemote = {}

-- Cette méthode permet de créer l'achat gardé d'un service lorsqu'il démarre : verrou « un achat en vol par joueur »
-- (retiré à la fin de l'achat, erreur comprise), `purchase` sous `pcall`, et `refuse("busy")` / `refuse("failed")`.
function PurchaseRemote.guard<A, R>(
	label: string,
	refuse: (reason: string) -> R,
	purchase: (player: Player, arg: A) -> R
): (player: Player, arg: A) -> R
	-- Joueurs dont un achat attend son écriture (au plus un chacun)
	local buying: { [Player]: boolean } = {}
	return function(player: Player, arg: A): R
		if buying[player] then
			return refuse("busy")
		end
		buying[player] = true
		local ok, result = pcall(purchase, player, arg)
		buying[player] = nil
		if not ok then
			warn("[" .. label .. "] achat en erreur pour", player.Name, ":", result)
			return refuse("failed")
		end
		return result
	end
end

-- Cette méthode permet de brancher un remote d'achat lorsque le serveur démarre : `admit` (CheatLog.admit) sinon
-- `refuse("rate")`, puis `buy`, puis `onBought` s'il existe (avant la réponse au client), puis la réponse.
function PurchaseRemote.connect<A, R>(
	remote: RemoteFunction,
	refuse: (reason: string) -> R,
	buy: (player: Player, arg: A) -> R,
	onBought: ((player: Player, arg: A, result: R) -> ())?
)
	remote.OnServerInvoke = function(player: Player, arg: any): R
		-- `arg` vient du client : `CheatLog.admit` en contrôle le type avant tout achat
		if not CheatLog.admit(player, remote.Name, arg) then
			return refuse("rate")
		end
		local result = buy(player, arg)
		if onBought then
			onBought(player, arg, result)
		end
		return result
	end
end

return PurchaseRemote

-- Traduction pure de l'issue de `InventoryStore.transact` (#410) en motif d'achat, partagée par `WalletStore.spend` et
-- `CratePurchaseRules.reply` pour qu'un nouveau motif ne diverge pas entre les deux. Testée (tests/specs/TransactOutcome.spec.luau).
local TransactOutcome = {}

-- Issue d'un achat : écrit (`ok`), solde stocké trop bas (`insufficient`), pas chargé ou pas sauvegardable (`loading`),
-- écriture en échec ou refus autre que le solde (`failed`, rien d'appliqué sauf la limite documentée de `transact`)
export type Status = "ok" | "insufficient" | "loading" | "failed"

-- Cette méthode permet de traduire l'issue de `InventoryStore.transact` (`status`, `result` = motif si `rejected`) en
-- `Status` lorsqu'un achat se termine ; seul un solde stocké trop bas est le fait du joueur, tout autre refus est un bug serveur.
function TransactOutcome.translate(status: string, result: any): Status
	if status == "ok" then
		return "ok"
	elseif status == "rejected" then
		return if result == "insufficient" then "insufficient" else "failed"
	elseif status == "loading" then
		return "loading"
	end
	return "failed"
end

return TransactOutcome

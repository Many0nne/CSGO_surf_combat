-- Refus d'achat côté client (#410), partagés par ShopScreen (caisses) et CreditPackWindow (packs) : libellés communs et
-- message temporaire sous le bouton d'achat. Un écran n'ajoute que ses propres motifs ou textes (`labels`).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local C = UITheme.Colors

local PurchaseStatus = {}

local STATUS_TIME = 3 -- s d'affichage d'un message
local FALLBACK = "ÉCHEC"

-- Libellés des motifs communs aux deux écrans (CrateService, ReceiptService)
PurchaseStatus.REFUSALS = {
	rate = "PATIENTE",
	region = "INDISPONIBLE DANS TA RÉGION",
	-- Pas « rien n'est débité » : une écriture passée dont la vérification échoue est aussi `failed` (InventoryStore)
	failed = "ACHAT IMPOSSIBLE  ·  RÉESSAIE PLUS TARD",
}

-- Cette méthode permet de construire la table de libellés d'un écran lorsqu'il charge : les libellés communs, puis ses
-- propres motifs (`own`) qui l'emportent sur les communs.
function PurchaseStatus.labels(own: { [string]: string }): { [string]: string }
	local merged = table.clone(PurchaseStatus.REFUSALS)
	for reason, text in own do
		merged[reason] = text
	end
	return merged
end

-- Cette méthode permet de lire le libellé d'un refus lorsque le serveur répond : « ÉCHEC » si le motif est inconnu.
function PurchaseStatus.text(labels: { [string]: string }, reason: any): string
	return labels[reason] or FALLBACK
end

-- Cette méthode permet de créer le `showStatus` d'un écran lorsqu'il construit son étiquette : le message s'affiche
-- STATUS_TIME s (refus en rouge d'impact, `ok` en ambre), un message plus récent remplace le précédent. `text` est
-- le français (gabarit `{nom}` + `args` si besoin) : il est traduit à l'affichage et suit la langue.
function PurchaseStatus.presenter(
	getLabel: () -> TextLabel
): (text: string, ok: boolean?, args: { [string]: any }?) -> ()
	local token = 0
	return function(text: string, ok: boolean?, args: { [string]: any }?)
		local status = getLabel()
		token += 1
		local mine = token
		Locale.apply(status, text, args)
		status.BackgroundColor3 = if ok then C.Accent else C.HitRed
		status.TextColor3 = if ok then C.Ground else C.Bone
		status.Visible = true
		task.delay(STATUS_TIME, function()
			if mine == token then
				status.Visible = false
			end
		end)
	end
end

return PurchaseStatus

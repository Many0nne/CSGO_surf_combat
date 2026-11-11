-- Règles pures du retour au menu en pleine partie (#217) : un départ par MENU PRINCIPAL juste après un coup reçu compte
-- comme une mort, pour qu'on ne puisse pas fuir une mort imminente. Testées (tests/specs/LeaveRules.spec.luau).
local LeaveRules = {}

-- Cette méthode permet de décider si un départ par MENU PRINCIPAL compte comme une mort lorsque le joueur quitte le
-- round : coup reçu il y a moins de `window` s, auteur toujours inscrit (mort ou vif ; parti : départ libre).
function LeaveRules.countsAsDeath(lastHitAt: number?, now: number, window: number, attackerPresent: boolean): boolean
	return lastHitAt ~= nil and attackerPresent and now - lastHitAt < window
end

return LeaveRules

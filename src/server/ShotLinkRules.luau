-- Rattachement d'une touche à son tir (#215, #216, docs/anticheat.md « Tirs comptés et touches rattachées ») : règles
-- pures, sans service ni workspace, testées sous Lune (tests/specs/ShotLinkRules.spec.luau).
-- Le client annonce chaque tir à distance par ShotFired(origin, direction, shotTime), puis, s'il touche, envoie
-- HitscanDamage(…, shotTime) avec le même instant. Le serveur tient, par participant et par arme, un registre des tirs
-- récents : un ShotFired accepté y entre (compté dans le chargeur), une touche s'y rattache par shotTime. Une touche
-- sans tir rattaché est une anomalie (contrôle "shotLink" de ShotRules, journal seul) ; elle entre aussi au registre,
-- pour qu'un ShotFired du même instant arrivé après elle ne soit pas compté deux fois.

local ShotLinkRules = {}

-- Écart maximal (s) entre le shotTime d'une touche et celui de son tir. Notre client envoie la même valeur
-- (workspace:GetServerTimeNow() pris une fois par tir) dans les deux remotes, transmise en double sans arrondi : un
-- écart nul est attendu. 1 ms couvre une conversion de flottant, et reste très loin de l'écart entre deux tirs (AWP :
-- FireDelay - CADENCE_TOLERANCE = 1,31 s au moins entre deux tirs acceptés) : une touche ne peut pas se rattacher au
-- tir voisin.
ShotLinkRules.LINK_TOLERANCE = 0.001
-- Âge maximal (s, horloge d'arrivée du serveur) d'un tir à qui rattacher une touche. Les deux remotes fiables d'un
-- client arrivent dans l'ordre d'envoi (doc Roblox « Remote events », y compris entre deux RemoteEvent différents) et
-- partent dans la même frame : la touche suit son tir de quelques millisecondes. 1 s couvre un handler retardé
-- (débit de Roblox, frame serveur lente) sans garder de tir plus vieux que la cadence de l'AWP (1,46 s).
ShotLinkRules.MAX_AGE = 1
-- Entrées gardées au plus par registre : borne la mémoire même si l'horloge passée ne fait rien vieillir (le débit de
-- ShotFired et HitscanDamage, 5/s chacun, en laisse ~10 en MAX_AGE).
ShotLinkRules.MAX_ENTRIES = 16

-- Un tir du registre : instant annoncé, arrivée sur le serveur (os.clock), ShotFired reçu, touche rattachée. Une
-- entrée créée par une touche orpheline a fired = false jusqu'à l'arrivée éventuelle de son ShotFired. data : ce que
-- l'appelant garde avec le tir (AimStats : cap figé à l'arrivée du tir).
export type Entry = { shotTime: number, at: number, fired: boolean, hit: boolean, data: any? }
export type Ledger = { Entry }

-- Cette méthode permet de créer un registre vide lorsqu'un participant tire pour la première fois avec une arme.
function ShotLinkRules.new(): Ledger
	return {}
end

-- Cette méthode permet de retirer les tirs trop anciens (arrivés il y a plus de MAX_AGE, ou venus du futur après un
-- changement d'horloge) lorsque le registre est lu ou complété.
function ShotLinkRules.prune(ledger: Ledger, now: number)
	for i = #ledger, 1, -1 do
		local age = now - ledger[i].at
		if age > ShotLinkRules.MAX_AGE or age < 0 then
			table.remove(ledger, i)
		end
	end
end

-- Cette méthode permet d'ajouter un tir au registre lorsqu'un ShotFired est accepté (fired) ou qu'une touche orpheline
-- est appliquée (hit) ; le plus ancien est oublié au-delà de MAX_ENTRIES.
function ShotLinkRules.record(
	ledger: Ledger,
	shotTime: number,
	now: number,
	fired: boolean,
	hit: boolean,
	data: any?
): Entry
	ShotLinkRules.prune(ledger, now)
	local entry = { shotTime = shotTime, at = now, fired = fired, hit = hit, data = data }
	table.insert(ledger, entry)
	while #ledger > ShotLinkRules.MAX_ENTRIES do
		table.remove(ledger, 1)
	end
	return entry
end

-- Cette méthode permet de trouver le tir d'instant shotTime (à LINK_TOLERANCE près) encore libre pour le champ donné
-- lorsqu'une touche cherche son tir ("hit" : ShotFired reçu, pas encore touché) ou qu'un ShotFired cherche une touche
-- arrivée avant lui ("fired" : touche orpheline sans ShotFired) ; le plus proche, puis le plus récent. nil sinon.
function ShotLinkRules.find(ledger: Ledger, shotTime: any, now: number, field: "hit" | "fired"): Entry?
	if type(shotTime) ~= "number" or shotTime ~= shotTime then
		return nil
	end
	ShotLinkRules.prune(ledger, now)
	local best: Entry? = nil
	local bestGap = math.huge
	for i = #ledger, 1, -1 do
		local entry = ledger[i]
		local free = if field == "hit" then entry.fired and not entry.hit else entry.hit and not entry.fired
		local gap = math.abs(entry.shotTime - shotTime)
		if free and gap <= ShotLinkRules.LINK_TOLERANCE and gap < bestGap then
			best, bestGap = entry, gap
		end
	end
	return best
end

return ShotLinkRules

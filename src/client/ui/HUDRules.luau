-- Règles pures du HUD (sans Instance ni service) : paliers de vitesse, timer, classement, barre d'armes.
-- Testées sous Lune (tests/specs/HUDRules.spec.luau).
local HUDRules = {}

-- Seuils des paliers de vitesse en studs/s horizontaux (course ≈ 30) ; le dernier passe le compteur au rouge
HUDRules.SPEED_TIERS = {
	{ min = 0, name = "—" },
	{ min = 30, name = "RUN" },
	{ min = 70, name = "FAST" },
	{ min = 120, name = "SURF" },
	{ min = 180, name = "MACH" },
}

-- Vitesse à laquelle la ligne du speedometer est pleine (entrée du dernier palier)
HUDRules.SPEED_FILL_MAX = 180

HUDRules.LOW_TIME_THRESHOLD = 30

-- Secondes sans changement d'arme avant que la barre ne garde que l'arme en main
HUDRules.WEAPON_BAR_FADE_DELAY = 2.5

export type Score = { name: string, isBot: boolean?, kills: number, deaths: number }

-- Cette méthode permet de trouver l'index du palier atteint lorsque le speedometer reçoit une vitesse.
function HUDRules.speedTier(speed: number): number
	local index = 1
	for i, tier in HUDRules.SPEED_TIERS do
		if speed >= tier.min then
			index = i
		end
	end
	return index
end

-- Cette méthode permet de calculer la part remplie (0 à 1) de la ligne du speedometer lorsque la vitesse change.
function HUDRules.speedFill(speed: number): number
	return math.clamp(speed / HUDRules.SPEED_FILL_MAX, 0, 1)
end

-- Cette méthode permet de formater un nombre de secondes en « m:ss » lorsque le timer de round est mis à jour.
function HUDRules.formatTimer(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Cette méthode permet de savoir si le timer doit passer en alerte lorsque la fin du round approche.
function HUDRules.isLowTime(seconds: number): boolean
	return seconds <= HUDRules.LOW_TIME_THRESHOLD
end

-- Cette méthode permet de trier les scores du meilleur au moins bon lorsque le classement est reconstruit :
-- plus de kills d'abord, puis moins de morts, puis ordre alphabétique pour un affichage stable.
function HUDRules.sortScores(scores: { [any]: Score }): { Score }
	local sorted = {}
	for _, score in pairs(scores) do
		table.insert(sorted, score)
	end
	table.sort(sorted, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return a.name < b.name
	end)
	return sorted
end

-- Cette méthode permet de retrouver le rang d'un joueur dans un classement trié lorsque le HUD affiche « rang/total ».
function HUDRules.rankOf(sorted: { Score }, name: string): number?
	for i, score in sorted do
		-- Un bot peut porter le même nom qu'un joueur : le rang affiché est celui du joueur
		if score.name == name and not score.isBot then
			return i
		end
	end
	return nil
end

-- Cette méthode permet de formater le ratio kills/morts lorsque la colonne K/D est remplie (morts nulles = kills).
function HUDRules.formatKD(kills: number, deaths: number): string
	if deaths == 0 then
		return string.format("%.2f", kills)
	end
	return string.format("%.2f", kills / deaths)
end

-- Cette méthode permet de calculer les secondes entières restantes avant réapparition lorsque l'overlay de mort tourne.
function HUDRules.secondsLeft(endTime: number, now: number): number
	return math.max(0, math.ceil(endTime - now))
end

-- Cette méthode permet de trouver l'emplacement d'arme voisin (en bouclant) lorsque la molette ou L1/R1 change d'arme ;
-- sans arme en main, on part du premier emplacement vers l'avant et du dernier vers l'arrière.
function HUDRules.cycleSlot(current: number?, count: number, step: number): number?
	if count <= 0 then
		return nil
	end
	if not current then
		return step > 0 and 1 or count
	end
	return (current - 1 + step) % count + 1
end

-- Cette méthode permet de transformer le nom d'un outil en libellé de la barre d'armes lorsqu'un emplacement est créé :
-- espace avant une majuscule qui suit une minuscule ou un chiffre (« M9Bayonet » → « M9 BAYONET »), puis majuscules.
function HUDRules.weaponLabel(toolName: string): string
	local spaced = string.gsub(toolName, "([%l%d])(%u)", "%1 %2")
	return string.upper(spaced)
end

-- Cette méthode permet de formater la réserve du compteur de munitions lorsque le HUD se met à jour :
-- « / ∞ » pour une réserve illimitée (math.huge), « / n » sinon.
function HUDRules.formatReserve(reserve: number): string
	if reserve == math.huge then
		return "/ ∞"
	end
	return "/ " .. tostring(reserve)
end

-- Cette méthode permet de trier les noms d'outils dans l'ordre des emplacements (alphabétique, comme le helper
-- DebugPlaytest) lorsque la barre d'armes est reconstruite.
function HUDRules.slotOrder(names: { string }): { string }
	local sorted = table.clone(names)
	table.sort(sorted)
	return sorted
end

-- Cette méthode permet de savoir si le HUD de jeu (vitesse, barre d'armes, lunette) est affiché lorsque l'état client change :
-- seulement en partie avec un personnage vivant (IN_ROUND), pas au menu, à la mort ni au résultat.
function HUDRules.gameHudVisible(state: string): boolean
	return state == "IN_ROUND"
end

-- Cette méthode permet de savoir si le crosshair de la visée simplifiée (#195) est affiché lorsque le réglage, l'état du
-- HUD de jeu, la lunette ou l'écran Réglages changent : réglage actif, HUD de jeu visible, ni lunette ni Réglages ouverts.
function HUDRules.crosshairVisible(enabled: boolean, hudVisible: boolean, scoped: boolean, menuOpen: boolean): boolean
	return enabled and hudVisible and not scoped and not menuOpen
end

-- Affichage des touches (#197) : une entrée par touche, placée sur une grille (colonne, rangée, largeur en cases).
-- `keys` : noms d'Enum.KeyCode (une des touches suffit à l'allumer), reflet des liaisons fixes d'InputModule.KEY_MAP ;
-- `mouse` : bouton de souris (« 1 » ou « 2 ») ; `label` : libellé fixe, sinon celui de la disposition du clavier.
-- `full` : l'entrée n'apparaît qu'en mode « full » ; le mode « simple » garde les directions et le saut.
export type KeyDisplayEntry = {
	id: string,
	keys: { string }?,
	mouse: number?,
	label: string?,
	col: number,
	row: number,
	width: number,
	full: boolean,
}

-- stylua: ignore
local KEY_DISPLAY_ENTRIES: { KeyDisplayEntry } = {
	{ id = "forward", keys = { "W" },                         col = 1, row = 0, width = 1, full = false },
	{ id = "left",    keys = { "A" },                         col = 0, row = 1, width = 1, full = false },
	{ id = "back",    keys = { "S" },                         col = 1, row = 1, width = 1, full = false },
	{ id = "right",   keys = { "D" },                         col = 2, row = 1, width = 1, full = false },
	{ id = "jump",    keys = { "Space" }, label = "ESPACE",   col = 0, row = 2, width = 3, full = false },
	{ id = "fire",    mouse = 1,          label = "M1",       col = 4, row = 0, width = 1, full = true },
	{ id = "aim",     mouse = 2,          label = "M2",       col = 5, row = 0, width = 1, full = true },
	{ id = "reload",  keys = { "R" },                         col = 4, row = 1, width = 1, full = true },
	{ id = "inspect", keys = { "F" },                         col = 5, row = 1, width = 1, full = true },
	{ id = "crouch",  keys = { "LeftControl", "RightControl" }, label = "CTRL", col = 4, row = 2, width = 1, full = true },
	{ id = "walk",    keys = { "LeftShift", "RightShift" },   label = "MAJ",    col = 5, row = 2, width = 1, full = true },
}

-- Cette méthode permet de lister les touches à afficher lorsque le mode d'affichage des touches est appliqué : aucune en
-- « off », directions et saut en « simple », toutes (accroupi, marche lente, tir, visée, recharge, inspection) en « full ».
function HUDRules.keyDisplayEntries(mode: string): { KeyDisplayEntry }
	local result = {}
	if mode ~= "simple" and mode ~= "full" then
		return result
	end
	for _, entry in KEY_DISPLAY_ENTRIES do
		if mode == "full" or not entry.full then
			table.insert(result, entry)
		end
	end
	return result
end

-- Cette méthode permet de savoir si l'affichage des touches est montré lorsque le réglage, l'état du HUD de jeu ou l'écran
-- Réglages changent : mode actif, HUD de jeu visible (donc ni menu, ni mort, ni résultat), Réglages fermé.
function HUDRules.keyDisplayVisible(mode: string, hudVisible: boolean, menuOpen: boolean): boolean
	return (mode == "simple" or mode == "full") and hudVisible and not menuOpen
end

-- Cette méthode permet de savoir si le kill feed est affiché lorsque l'état client change : en partie, vivant ou mort
-- (le joueur tué y voit sa propre ligne), pas au menu ni au résultat.
function HUDRules.killFeedVisible(state: string): boolean
	return state == "IN_ROUND" or state == "DEAD"
end

-- Kill feed (#102) : lignes affichées au plus, durée d'affichage d'une ligne (s)
HUDRules.KILL_FEED_MAX = 4
HUDRules.KILL_FEED_DURATION = 5

export type KillFeedEntry = {
	killer: string?, -- nil : mort sans tueur (chute)
	killerIsBot: boolean?,
	victim: string,
	victimIsBot: boolean?,
	weapon: string?,
	headshot: boolean,
	mine: boolean, -- le joueur local est le tueur ou la victime
	at: number,
}

-- Cette méthode permet d'échapper un nom de joueur ou de bot avant de l'insérer dans un texte RichText.
function HUDRules.escapeRichText(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Mort annoncée par le serveur (PlayerDied), lue sans Player : un bot n'en a pas (#137)
export type Death = {
	victimId: number,
	victim: string,
	victimIsBot: boolean,
	killerId: number?,
	killer: string?, -- nil : mort sans tueur (chute) ou tueur parti
	killerIsBot: boolean,
	weapon: string?,
	headshot: boolean,
	direction: Vector3?,
	mine: boolean, -- le joueur local est le tueur ou la victime
}

-- Cette méthode permet de lire une annonce de mort (PlayerDied) lorsqu'elle arrive du serveur : nil si elle est mal
-- formée ; les noms viennent de l'annonce, le joueur local se reconnaît à son UserId.
function HUDRules.readDeath(data: any, localUserId: number): Death?
	if type(data) ~= "table" or type(data.victimId) ~= "number" or type(data.victimName) ~= "string" then
		return nil
	end
	local killerId = if type(data.killerId) == "number" then data.killerId else nil
	local killer = if killerId and type(data.killerName) == "string" then data.killerName else nil
	return {
		victimId = data.victimId,
		victim = data.victimName,
		victimIsBot = data.victimIsBot == true,
		killerId = if killer then killerId else nil,
		killer = killer,
		killerIsBot = killer ~= nil and data.killerIsBot == true,
		weapon = if type(data.weapon) == "string" then data.weapon else nil,
		headshot = data.headshot == true,
		direction = if typeof(data.direction) == "Vector3" then data.direction else nil,
		mine = data.victimId == localUserId or (killer ~= nil and killerId == localUserId),
	}
end

-- Cette méthode permet de décrire l'arme d'une ligne de kill feed ou de l'écran de mort lorsqu'une mort arrive :
-- libellé de l'arme, « TÊTE » si tir à la tête, « CHUTE » sans tueur.
function HUDRules.killDetail(killer: string?, weapon: string?, headshot: boolean): string
	if not killer then
		return "CHUTE"
	end
	local label = if weapon then HUDRules.weaponLabel(weapon) else ""
	if headshot then
		return if label ~= "" then label .. " · TÊTE" else "TÊTE"
	end
	return label
end

-- Cette méthode permet d'ajouter une ligne au kill feed lorsqu'une mort arrive : plus récente en premier, les lignes
-- expirées et celles au-delà de KILL_FEED_MAX sont retirées.
function HUDRules.pushKillFeed(entries: { KillFeedEntry }, entry: KillFeedEntry, now: number): { KillFeedEntry }
	local result = { entry }
	for _, existing in HUDRules.pruneKillFeed(entries, now) do
		if #result >= HUDRules.KILL_FEED_MAX then
			break
		end
		table.insert(result, existing)
	end
	return result
end

-- Cette méthode permet de retirer les lignes du kill feed affichées depuis plus de KILL_FEED_DURATION lorsque le feed
-- est rafraîchi.
function HUDRules.pruneKillFeed(entries: { KillFeedEntry }, now: number): { KillFeedEntry }
	local result = {}
	for _, entry in entries do
		if now - entry.at < HUDRules.KILL_FEED_DURATION then
			table.insert(result, entry)
		end
	end
	return result
end

-- Cette méthode permet de savoir si le résultat de round doit être affiché lorsque RoundResult arrive : seulement si le
-- joueur est en partie (IN_ROUND ou DEAD), sinon l'état bloquerait en RESULT au menu ou pendant le spawn (#110).
function HUDRules.acceptsRoundResult(state: string): boolean
	return state == "IN_ROUND" or state == "DEAD"
end

return HUDRules

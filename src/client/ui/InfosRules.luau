-- Règles pures de l'écran Infos (#290) : composition des textes qui citent des touches, sans Instance ni service.
-- Les touches viennent de KeyBindings via les entrées de HUDRules.keyDisplayEntries (une seule liste d'actions) et des
-- réglages du joueur ; le libellé de chaque touche est celui de `keyText` (LocalSettings.keyText, disposition du clavier).
-- Testées sous Lune (tests/specs/InfosRules.spec.luau).
local InfosRules = {}

-- Entrée de HUDRules.keyDisplayEntries (seuls les champs lus ici)
export type Entry = {
	id: string,
	keys: { string }?,
	mouse: number?,
	label: string?,
	col: number,
	row: number,
	width: number,
	full: boolean,
}

-- Contexte de composition : entrées d'actions (mode « full »), libellé d'une touche, touche du menu, réglages d'armes
export type Context = {
	entries: { Entry },
	keyText: (keyName: string) -> string,
	menuKey: string,
	slotKeys: { string },
	defaultSlotKeys: { string },
	wheel: string,
}

export type KeyRow = { key: string, action: string }

-- Description de chaque action affichée ; `move` regroupe les quatre directions sur une ligne
local ACTION_TEXT = {
	jump = "Sauter / bhop (auto-bhop réglable dans Réglages)",
	crouch = "S'accroupir",
	walk = "Marche lente",
	fire = "Tirer",
	aim = "Viser avec la lunette / estoc au couteau",
	reload = "Recharger",
	inspect = "Inspecter le couteau",
}

-- Ordre d'affichage des actions (les directions viennent d'abord, en une ligne)
local ACTION_ORDER = { "jump", "crouch", "walk", "fire", "aim", "reload", "inspect" }

local MOUSE_LABELS = { [1] = "CLIC GAUCHE", [2] = "CLIC DROIT" }

-- Touche affichée du classement : Tab est fixé par Roblox (liste des joueurs), pas par KeyBindings
local SCOREBOARD_LABEL = "TAB"

-- Cette méthode permet de retrouver une entrée d'action lorsqu'une ligne est composée.
local function entryOf(entries: { Entry }, id: string): Entry?
	for _, entry in entries do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- Cette méthode permet de donner le libellé de la première touche d'une action lorsqu'un texte la cite (AZERTY : Q pour
-- la touche « gauche »).
local function actionKey(ctx: Context, id: string): string
	local entry = entryOf(ctx.entries, id)
	local name = entry and entry.keys and entry.keys[1]
	return name and ctx.keyText(name) or "?"
end

-- Cette méthode permet de donner le libellé d'une entrée d'action lorsqu'une ligne de COMMANDES est composée : bouton de
-- souris, libellé fixe (ESPACE, CTRL, MAJ), sinon la touche telle qu'imprimée sur le clavier du joueur.
local function entryLabel(ctx: Context, entry: Entry): string
	if entry.mouse then
		return MOUSE_LABELS[entry.mouse] or ("SOURIS " .. entry.mouse)
	end
	if entry.label then
		return entry.label
	end
	return actionKey(ctx, entry.id)
end

-- Cette méthode permet de composer les touches des armes lorsque la ligne « changer d'arme » est affichée : « 1 – 9 »
-- pour les touches par défaut, sinon la liste réglée par le joueur (Réglages > TOUCHES).
local function slotKeysLabel(ctx: Context): string
	local texts = {}
	for _, name in ctx.slotKeys do
		table.insert(texts, ctx.keyText(name))
	end
	local isDefault = #ctx.slotKeys == #ctx.defaultSlotKeys
	for i, name in ctx.slotKeys do
		if name ~= ctx.defaultSlotKeys[i] then
			isDefault = false
		end
	end
	if isDefault and #texts > 1 then
		return texts[1] .. " – " .. texts[#texts]
	end
	return table.concat(texts, " ")
end

-- Cette méthode permet de composer les lignes « touche → action » de la section COMMANDES lorsque l'écran Infos s'ouvre
-- ou que les réglages changent.
function InfosRules.commandRows(ctx: Context): { KeyRow }
	local rows: { KeyRow } = {}
	local move = {}
	for _, id in { "forward", "left", "back", "right" } do
		table.insert(move, actionKey(ctx, id))
	end
	table.insert(rows, { key = table.concat(move, " "), action = "Se déplacer" })

	for _, id in ACTION_ORDER do
		local entry = entryOf(ctx.entries, id)
		if entry then
			table.insert(rows, { key = entryLabel(ctx, entry), action = ACTION_TEXT[id] })
		end
	end

	table.insert(rows, { key = slotKeysLabel(ctx), action = "Changer d'arme" })
	if ctx.wheel ~= "off" then
		table.insert(rows, { key = "MOLETTE", action = "Changer d'arme (réglable dans Réglages)" })
	end
	table.insert(rows, { key = SCOREBOARD_LABEL, action = "Classement" })
	table.insert(rows, { key = ctx.keyText(ctx.menuKey), action = "Menu en partie (réglages, retour au menu)" })
	return rows
end

-- Cette méthode permet de composer les conseils de la section SURFER lorsque l'écran Infos s'ouvre : les touches citées
-- (gauche, droite, avant) suivent la disposition du clavier du joueur.
function InfosRules.surfLines(ctx: Context): { string }
	local left, right, forward = actionKey(ctx, "left"), actionKey(ctx, "right"), actionKey(ctx, "forward")
	return {
		"Approche une rampe et place-toi PARALLÈLE à sa surface.",
		string.format(
			"Maintiens %s ou %s pour appuyer contre la rampe. Ne touche jamais à %s pendant le surf.",
			left,
			right,
			forward
		),
		"Oriente-toi avec la souris dans le sens de la rampe pour gagner de la vitesse.",
		"Reste sur la bonne zone de la rampe : ni trop haut, ni trop bas.",
		string.format(
			"Enchaîne les rampes en douceur, avec des air strafes (%s/%s + souris) entre elles.",
			left,
			right
		),
		"Ne saute jamais sur une rampe : laisse la gravité t'y amener.",
	}
end

return InfosRules

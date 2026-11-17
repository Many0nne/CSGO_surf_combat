-- Règles pures de l'écran Infos (#290) : composition des textes qui citent des touches, sans Instance ni service ; aussi
-- les conseils de l'écran de mort des débutants (#291, deathTips).
-- Les touches viennent de KeyBindings via les entrées de HUDRules.keyDisplayEntries (une seule liste d'actions) et des
-- réglages du joueur ; le libellé de chaque touche est celui de `keyText` (LocalSettings.keyText, disposition du clavier).
-- Testées sous Lune (tests/specs/InfosRules.spec.luau).
-- Les textes sont rendus en français, sous forme de gabarits `{nom}` accompagnés de leurs arguments (touches) : l'écran
-- les traduit à l'affichage (InfosContext.text / InfosContext.apply, #518), les règles ne connaissent pas la langue.
local InfosRules = {}

-- Entrée de HUDRules.keyDisplayEntries (seuls les champs lus ici)
export type Entry = {
	id: string,
	keys: { string }?,
	mouse: number?,
	pad: string?,
	label: string?,
	col: number,
	row: number,
	width: number,
	full: boolean,
}

-- Contexte de composition : entrées d'actions (mode « full »), libellé d'une touche, touche du menu, réglages d'armes,
-- auto-bhop réglé (légende de la démo de bhop ; absent : activé, la valeur par défaut)
export type Context = {
	entries: { Entry },
	keyText: (keyName: string) -> string,
	menuKey: string,
	slotKeys: { string },
	defaultSlotKeys: { string },
	wheel: string,
	autoBhop: boolean?,
}

-- Ligne « touche → action » : `key` et `action` sont des textes français (`key` : gabarit `{nom}` + `keyArgs` pour un
-- bouton de souris numéroté ; une lettre de touche reste telle quelle à la traduction)
export type KeyRow = { key: string, keyArgs: { [string]: any }?, action: string }

-- Description de chaque action affichée (les quatre directions tiennent sur une ligne « Se déplacer »)
local ACTION_TEXT = {
	jump = "Sauter / bhop (auto-bhop réglable dans Réglages)",
	crouch = "S'accroupir",
	walk = "Marche lente",
	fire = "Tirer",
	aim = "Viser avec la lunette / estoc au couteau",
	reload = "Recharger",
	inspect = "Inspecter l'arme",
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
-- la touche « gauche ») ; ne lit que les entrées et `keyText`, communs à Context et TipContext.
local function actionKey(ctx: { entries: { Entry }, keyText: (keyName: string) -> string }, id: string): string
	local entry = entryOf(ctx.entries, id)
	local name = entry and entry.keys and entry.keys[1]
	return name and ctx.keyText(name) or "?"
end

-- Cette méthode permet de donner le libellé du saut (fixe, ESPACE, sinon la touche du clavier du joueur) lorsqu'un
-- texte de bhop est composé.
local function jumpLabel(ctx: { entries: { Entry }, keyText: (keyName: string) -> string }): string
	local entry = entryOf(ctx.entries, "jump")
	return if entry and entry.label then entry.label else actionKey(ctx, "jump")
end

-- Cette méthode permet de donner le libellé d'une entrée d'action lorsqu'une ligne de COMMANDES est composée : bouton de
-- souris, libellé fixe (ESPACE, CTRL, MAJ), sinon la touche telle qu'imprimée sur le clavier du joueur ; le deuxième
-- résultat donne les arguments d'un libellé à gabarit (« SOURIS {n} »).
local function entryLabel(ctx: Context, entry: Entry): (string, { [string]: any }?)
	if entry.mouse then
		local known = MOUSE_LABELS[entry.mouse]
		if known then
			return known, nil
		end
		return "SOURIS {n}", { n = entry.mouse }
	end
	if entry.label then
		return entry.label, nil
	end
	return actionKey(ctx, entry.id), nil
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
	return #texts > 0 and table.concat(texts, " ") or "?"
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
			local key, keyArgs = entryLabel(ctx, entry)
			table.insert(rows, { key = key, keyArgs = keyArgs, action = ACTION_TEXT[id] })
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

-- Démo rejouée de l'écran Apprendre (#285) : `id` nomme le module de données (ui/DemoClips), `title` le sélecteur,
-- `caption` le geste en une ligne, posé sur le clip (gabarit français `{nom}` rempli par `captionArgs`, les touches)
export type DemoClip = { id: string, title: string, caption: string, captionArgs: { [string]: any } }

-- Cette méthode permet de composer les démos de l'écran Apprendre et leurs légendes lorsqu'il s'ouvre,
-- touches telles qu'imprimées sur le clavier du joueur ; plusieurs démos donnent un sélecteur, une seule n'en a pas.
-- Une seule pour l'instant (Dizzy n'a pas de rampe assez longue pour le surf ni l'enchaînement) : bhop et air strafe,
-- jouée avec l'auto-bhop (saut tenu) ; sans auto-bhop, la légende dit d'appuyer à chaque atterrissage.
function InfosRules.demoClips(ctx: Context): { DemoClip }
	local left, right, forward = actionKey(ctx, "left"), actionKey(ctx, "right"), actionKey(ctx, "forward")
	local caption = if ctx.autoBhop == false
		then "Appuie sur {jump} à chaque atterrissage (démo en auto-bhop), puis en l'air {left} en tournant la souris à gauche, {right} à droite, sans {forward}."
		else "Garde {jump} (auto-bhop), puis en l'air {left} en tournant la souris à gauche, {right} à droite, sans {forward}."
	return {
		{
			id = "bhop",
			title = "BHOP",
			caption = caption,
			captionArgs = { jump = jumpLabel(ctx), left = left, right = right, forward = forward },
		},
	}
end

-- Contexte des conseils de l'écran de mort (#291) : entrées d'actions, libellé d'une touche, auto-bhop réglé (le conseil
-- de bhop en dépend)
export type TipContext = {
	entries: { Entry },
	keyText: (keyName: string) -> string,
	autoBhop: boolean,
}

-- Conseil de l'écran de mort : thème (affiché en ambre) et phrase, en français : `text` est un gabarit `{nom}` rempli
-- par `args` (les touches), traduit à l'affichage
export type Tip = { topic: string, text: string, args: { [string]: any } }

-- Cette méthode permet de composer les conseils de l'écran de mort d'un débutant (#291) lorsqu'un conseil est choisi :
-- surf, bhop (selon l'auto-bhop) et air strafe, touches telles qu'imprimées sur le clavier du joueur. Bhop et air strafe
-- renvoient à leur démo (#285, onglet APPRENDRE du menu) : « Démo : APPRENDRE. » en fin de phrase.
function InfosRules.deathTips(ctx: TipContext): { Tip }
	local left, right, forward = actionKey(ctx, "left"), actionKey(ctx, "right"), actionKey(ctx, "forward")
	local jump = jumpLabel(ctx)
	local bhop = if ctx.autoBhop ~= false
		then "garde {jump} enfoncé, tu ressautes dès que tu touches le sol. Démo : APPRENDRE."
		else "appuie sur {jump} à chaque fois que tu touches le sol. Démo : APPRENDRE."
	local args = { jump = jump, left = left, right = right, forward = forward }
	return {
		{
			topic = "SURF",
			text = "maintiens {left} ou {right} contre la rampe, ne touche jamais à {forward}.",
			args = args,
		},
		{ topic = "BHOP", text = bhop, args = args },
		{
			topic = "AIR STRAFE",
			text = "en l'air, tiens {left} en tournant la souris à gauche, {right} à droite. Démo : APPRENDRE.",
			args = args,
		},
	}
end

return InfosRules

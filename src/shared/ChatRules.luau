-- Règles pures du chat (#541, docs/moderation.md) : nettoyage et longueur d'un message, débit (seau à jetons), fondu
-- des lignes du fil, analyse des commandes admin, choix du joueur visé et droits. Sans service ni Instance : testées
-- sous Lune (tests/specs/ChatRules.spec.luau). Le client s'en sert pour son fil (ui/ChatFeed) et pour ne pas envoyer
-- un message que le serveur refuserait ; le serveur (ChatService) pour décider de la diffusion.
local ChatRules = {}

-- Longueur maximale d'un message, en caractères (le champ de saisie coupe au-delà, le serveur refuse au-delà)
ChatRules.MAX_LENGTH = 120
-- Débit : un message regagné toutes les 1 / RATE secondes, BURST messages d'affilée au plus
ChatRules.RATE = 1
ChatRules.BURST = 4
-- Le serveur tolère un message de plus que le client : les messages arrivent plus serrés qu'ils ne sont partis
-- (gigue réseau), un joueur qui respecte la limite de son client n'est jamais refusé
ChatRules.SERVER_BURST = ChatRules.BURST + 1

-- Fil : lignes visibles d'un coup, lignes gardées pour le défilement, délai et durée du fondu (s)
ChatRules.FEED_VISIBLE = 7
ChatRules.FEED_KEEP = 60
ChatRules.FADE_DELAY = 8
ChatRules.FADE_TIME = 1.5

-- Commandes admin (rôle Admin de Roles) : alias tapé dans le chat -> nom de la commande
ChatRules.COMMANDS = {
	["/mute"] = "mute",
	["/unmute"] = "unmute",
	["/kick"] = "kick",
} :: { [string]: Command }

-- Usage de chaque commande (traduit par le client)
ChatRules.USAGES = {
	mute = "/mute <joueur>",
	unmute = "/unmute <joueur>",
	kick = "/kick <joueur> [motif]",
} :: { [Command]: string }

-- Retours à l'admin (gabarits français traduits par le client, #518) et message d'expulsion
ChatRules.Notice = {
	MUTED = "{name} ne peut plus écrire dans le chat.",
	UNMUTED = "{name} peut de nouveau écrire dans le chat.",
	KICKED = "{name} a été expulsé.",
	NOT_FOUND = "Aucun joueur ne correspond à « {query} ».",
	AMBIGUOUS = "Plusieurs joueurs correspondent à « {query} ».",
	USAGE = "Usage : {usage}",
	RATE = "Trop de messages, patiente un instant.",
}
ChatRules.KICK_MESSAGE = "Expulsé par un modérateur."
ChatRules.KICK_MESSAGE_REASON = "Expulsé par un modérateur : {reason}"

export type Command = "mute" | "unmute" | "kick"
export type Verdict = "ok" | "empty" | "long" | "rate" | "muted"
export type Bucket = { tokens: number, at: number }
export type Candidate = { userId: number, name: string, displayName: string }
export type TargetProblem = "empty" | "none" | "ambiguous"

-- Cette méthode permet de nettoyer un message lorsqu'il va être envoyé ou contrôlé : retours à la ligne et
-- tabulations deviennent des espaces, les espaces en trop au début et à la fin sont retirés.
function ChatRules.clean(text: string): string
	local flat = string.gsub(text, "[%c]", " ")
	return (string.match(flat, "^%s*(.-)%s*$") or "")
end

-- Cette méthode permet de compter les caractères d'un message lorsque sa longueur est contrôlée ; un texte qui n'est
-- pas de l'UTF-8 valide compte ses octets.
function ChatRules.length(text: string): number
	return utf8.len(text) or #text
end

-- Cette méthode permet de couper un texte à MAX_LENGTH caractères lorsque le joueur tape dans le champ de saisie.
function ChatRules.clip(text: string): string
	local count = utf8.len(text)
	if not count then
		return string.sub(text, 1, ChatRules.MAX_LENGTH)
	end
	if count <= ChatRules.MAX_LENGTH then
		return text
	end
	return string.sub(text, 1, (utf8.offset(text, ChatRules.MAX_LENGTH + 1) :: number) - 1)
end

-- Cette méthode permet de créer un seau plein lorsqu'un joueur écrit pour la première fois.
function ChatRules.newBucket(now: number, burst: number?): Bucket
	return { tokens = burst or ChatRules.BURST, at = now }
end

-- Cette méthode permet de décider si un message passe lorsqu'il est envoyé (client) ou reçu (serveur) : sourdine,
-- message vide, trop long, puis débit. Seul un message accepté consomme un jeton du seau.
function ChatRules.admit(bucket: Bucket, text: string, now: number, muted: boolean, burst: number?): Verdict
	if muted then
		return "muted"
	end
	local cleaned = ChatRules.clean(text)
	if cleaned == "" then
		return "empty"
	end
	if ChatRules.length(cleaned) > ChatRules.MAX_LENGTH then
		return "long"
	end
	local cap = burst or ChatRules.BURST
	bucket.tokens = math.min(cap, bucket.tokens + math.max(now - bucket.at, 0) * ChatRules.RATE)
	bucket.at = now
	if bucket.tokens < 1 then
		return "rate"
	end
	bucket.tokens -= 1
	return "ok"
end

-- Entités posées par TextChatService dans le texte d'un message (texte riche échappé) ; &amp; en dernier
local ENTITIES = { { "&lt;", "<" }, { "&gt;", ">" }, { "&quot;", '"' }, { "&apos;", "'" }, { "&#39;", "'" } }

-- Cette méthode permet de rendre le texte lisible lorsqu'un message reçu est affiché sans texte riche : les entités
-- échappées par TextChatService redeviennent des caractères.
function ChatRules.unescape(text: string): string
	for _, pair in ENTITIES do
		text = string.gsub(text, pair[1], pair[2])
	end
	return (string.gsub(text, "&amp;", "&"))
end

-- Cette méthode permet de donner la transparence d'une ligne du fil lorsqu'il est redessiné : opaque saisie ouverte
-- ou pendant FADE_DELAY s après son arrivée, puis effacée en FADE_TIME s.
function ChatRules.lineTransparency(age: number, open: boolean): number
	if open or age <= ChatRules.FADE_DELAY then
		return 0
	end
	return math.clamp((age - ChatRules.FADE_DELAY) / ChatRules.FADE_TIME, 0, 1)
end

-- Cette méthode permet de borner le défilement du fil (en lignes depuis le bas) lorsque la molette le fait bouger,
-- saisie ouverte : de 0 (dernier message en bas) au plus ancien message gardé en haut.
function ChatRules.clampScroll(scroll: number, count: number): number
	return math.clamp(scroll, 0, math.max(count - ChatRules.FEED_VISIBLE, 0))
end

-- Cette méthode permet de reconnaître une commande admin lorsqu'un message commence par « / » : renvoie la commande,
-- le joueur visé (mot suivant) et le reste (motif d'un kick), ou nil pour un texte qui n'en est pas une.
function ChatRules.parseCommand(text: string): (Command?, string?, string?)
	local alias, rest = string.match(ChatRules.clean(text), "^(/%S+)%s*(.*)$")
	if not alias then
		return nil, nil, nil
	end
	local command = ChatRules.COMMANDS[string.lower(alias)]
	if not command then
		return nil, nil, nil
	end
	local target, reason = string.match(rest :: string, "^(%S+)%s*(.*)$")
	if reason == "" then
		reason = nil
	end
	return command, target, reason
end

-- Cette méthode permet de trouver le joueur visé par une commande lorsque l'admin tape un nom : nom d'utilisateur ou
-- nom affiché, sans tenir compte de la casse ni d'un « @ » devant ; égalité exacte d'abord, sinon début de nom unique.
function ChatRules.findTarget(query: string?, candidates: { Candidate }): (number?, TargetProblem?)
	local stripped = string.gsub(query or "", "^@", "")
	local wanted = string.lower(stripped)
	if wanted == "" then
		return nil, "empty"
	end
	for _, candidate in candidates do
		if string.lower(candidate.name) == wanted or string.lower(candidate.displayName) == wanted then
			return candidate.userId, nil
		end
	end
	local found: number? = nil
	for _, candidate in candidates do
		local name, display = string.lower(candidate.name), string.lower(candidate.displayName)
		if string.sub(name, 1, #wanted) == wanted or string.sub(display, 1, #wanted) == wanted then
			if found and found ~= candidate.userId then
				return nil, "ambiguous"
			end
			found = candidate.userId
		end
	end
	if found then
		return found, nil
	end
	return nil, "none"
end

-- Cette méthode permet de savoir si un joueur peut lancer une commande admin lorsqu'il en tape une : rôle Admin, ou
-- attribut de debug posé par le serveur dans Studio (joueurs de test d'un serveur local, sans compte propriétaire).
function ChatRules.canModerate(isAdmin: boolean, isStudio: boolean, debugAdmin: boolean): boolean
	return isAdmin or (isStudio and debugAdmin)
end

-- Cette méthode permet de donner l'usage d'une commande lorsque l'admin l'a tapée sans joueur visé.
function ChatRules.usage(command: Command): string
	return ChatRules.USAGES[command]
end

return ChatRules

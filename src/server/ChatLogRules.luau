-- Règles pures du journal du chat (#541, docs/moderation.md) : entrées en attente, mise en forme d'une ligne et
-- découpe en messages Discord (un embed par envoi, description bornée). Sans service : testées sous Lune
-- (tests/specs/ChatLogRules.spec.luau). L'envoi périodique et le webhook sont dans ChatService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChatRules = require(ReplicatedStorage.Shared.ChatRules)

local ChatLogRules = {}

-- Secondes entre deux envois : quelques messages par minute et par serveur, sous la limite de débit de Discord même
-- avec plusieurs serveurs sur le même webhook
ChatLogRules.FLUSH_INTERVAL = 15
-- Description d'un embed : 4096 caractères chez Discord, marge pour le texte d'en-tête
ChatLogRules.MAX_DESCRIPTION = 3800
-- Entrées gardées en attente au plus (webhook en panne : elles repartent à l'envoi suivant) ; au-delà, les plus
-- anciennes sont abandonnées, et comptées
ChatLogRules.MAX_PENDING = 400
-- Texte d'un message coupé au-delà (un message accepté en fait au plus ChatRules.MAX_LENGTH)
ChatLogRules.MAX_TEXT = 300

ChatLogRules.TITLE = "Journal du chat"
ChatLogRules.COLOR = 7506394

export type Kind = "message" | "mute" | "unmute" | "kick"
export type Entry = {
	at: number, -- os.time() à l'envoi du message ou à la commande
	kind: Kind,
	userId: number,
	name: string,
	text: string?, -- message (texte filtré) ou motif filtré d'un kick
	targetId: number?,
	targetName: string?,
	-- Texte encore en cours de filtrage : l'entrée garde sa place, l'envoi s'arrête devant elle
	pending: boolean?,
}
export type Batch = { entries: { Entry }, dropped: number }

-- Cette méthode permet de créer un lot vide lorsque le service démarre.
function ChatLogRules.newBatch(): Batch
	return { entries = {}, dropped = 0 }
end

-- Cette méthode permet d'ajouter une entrée au lot lorsqu'un message est délivré ou qu'une commande est appliquée ;
-- au-delà de MAX_PENDING, la plus ancienne est abandonnée (comptée dans `dropped`).
function ChatLogRules.push(batch: Batch, entry: Entry)
	table.insert(batch.entries, entry)
	while #batch.entries > ChatLogRules.MAX_PENDING do
		table.remove(batch.entries, 1)
		batch.dropped += 1
	end
end

-- Cette méthode permet de neutraliser la mise en forme Discord (gras, code, citation…) lorsqu'un texte de joueur est
-- recopié dans le journal : il s'affiche tel quel, sur une ligne.
function ChatLogRules.escape(text: string): string
	return (string.gsub(ChatRules.clean(text), "([\\%*_~`|>#%[%]%(%)<@])", "\\%1"))
end

-- Cette méthode permet de couper un texte trop long (sans casser un caractère UTF-8) lorsqu'il entre dans une ligne.
local function clipText(text: string): string
	local clipped = ChatRules.clip(text, ChatLogRules.MAX_TEXT)
	return if clipped == text then text else clipped .. "…"
end

-- Cette méthode permet d'écrire un joueur (nom et UserId) lorsqu'une ligne du journal le cite.
local function who(name: string, userId: number): string
	return string.format("**%s** (`%d`)", ChatLogRules.escape(name), userId)
end

-- Cette méthode permet de mettre en forme une entrée lorsqu'elle part au journal : heure UTC, auteur, puis message ou
-- commande avec le joueur visé et le motif.
function ChatLogRules.formatLine(entry: Entry): string
	local time = os.date("!%H:%M:%S", entry.at)
	local head = string.format("`%s` %s", time, who(entry.name, entry.userId))
	if entry.kind == "message" then
		return head .. " : " .. ChatLogRules.escape(clipText(entry.text or ""))
	end
	local target = who(entry.targetName or "?", entry.targetId or 0)
	local line = string.format("%s **/%s** %s", head, entry.kind, target)
	if entry.text and entry.text ~= "" then
		line ..= " — " .. ChatLogRules.escape(clipText(entry.text))
	end
	return line
end

-- Cette méthode permet de préparer l'embed du prochain envoi lorsque le moment d'envoyer est venu, sans rien retirer :
-- lignes dans l'ordre, jusqu'à la limite ou une entrée encore filtrée. Renvoie l'embed (nil si rien) et son nombre d'entrées.
function ChatLogRules.peek(batch: Batch, jobId: string): ({ [string]: any }?, number)
	local lines: { string } = {}
	if batch.dropped > 0 then
		table.insert(lines, string.format("*%d entrée(s) perdue(s) (webhook indisponible)*", batch.dropped))
	end
	local size = if #lines > 0 then #lines[1] + 1 else 0
	local count = 0
	for _, entry in batch.entries do
		if entry.pending then
			break
		end
		local line = ChatLogRules.formatLine(entry)
		-- Une ligne seule ne dépasse jamais la limite (texte coupé à MAX_TEXT) : la première part toujours
		if #lines > 0 and size + #line + 1 > ChatLogRules.MAX_DESCRIPTION then
			break
		end
		table.insert(lines, line)
		size += #line + 1
		count += 1
	end
	if #lines == 0 then
		return nil, 0
	end
	return {
		title = ChatLogRules.TITLE,
		description = table.concat(lines, "\n"),
		color = ChatLogRules.COLOR,
		footer = { text = "JobId " .. (if jobId == "" then "Studio" else jobId) },
	},
		count
end

-- Cette méthode permet de retirer du lot les `count` premières entrées et le compte des pertes lorsque l'envoi préparé
-- par peek a réussi ; un envoi en échec ne retire rien, tout repart au suivant.
function ChatLogRules.commit(batch: Batch, count: number)
	for _ = 1, math.min(count, #batch.entries) do
		table.remove(batch.entries, 1)
	end
	batch.dropped = 0
end

return ChatLogRules

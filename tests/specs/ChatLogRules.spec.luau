-- Journal du chat (#541) : lot en attente, mise en forme d'une ligne, découpe en embeds Discord.
return function(T, Loader)
	local ChatLogRules = Loader.new():require("src/server/ChatLogRules")

	-- Cette méthode permet de créer une entrée de message lorsqu'un cas remplit un lot.
	local function message(text: string, at: number?): any
		return { at = at or 0, kind = "message", userId = 42, name = "Bob", text = text }
	end

	T.describe("ChatLogRules.formatLine", function()
		T.it("écrit l'heure UTC, l'auteur, son UserId et le texte", function()
			local line = ChatLogRules.formatLine(message("salut", 3661))
			T.expectEqual(line, "`01:01:01` **Bob** (`42`) : salut")
		end)

		T.it("neutralise la mise en forme Discord d'un texte de joueur", function()
			local line = ChatLogRules.formatLine(message("**gras** `code` @everyone"))
			T.expect(string.find(line, "\\*\\*gras\\*\\* \\`code\\` \\@everyone", 1, true) ~= nil, line)
		end)

		T.it("écrit une commande avec le joueur visé et le motif", function()
			local line = ChatLogRules.formatLine({
				at = 0,
				kind = "kick",
				userId = 1,
				name = "Admin",
				targetId = 2,
				targetName = "Bob",
				text = "spam",
			})
			T.expectEqual(line, "`00:00:00` **Admin** (`1`) **/kick** **Bob** (`2`) — spam")
			local mute = ChatLogRules.formatLine({
				at = 0,
				kind = "mute",
				userId = 1,
				name = "Admin",
				targetId = 2,
				targetName = "Bob",
			})
			T.expectEqual(mute, "`00:00:00` **Admin** (`1`) **/mute** **Bob** (`2`)")
		end)

		T.it("coupe un texte trop long", function()
			local line = ChatLogRules.formatLine(message(string.rep("a", ChatLogRules.MAX_TEXT + 50)))
			T.expect(#line < ChatLogRules.MAX_TEXT + 40, "ligne bornée")
		end)
	end)

	T.describe("ChatLogRules.peek / commit", function()
		T.it("ne renvoie rien pour un lot vide", function()
			local embed, receipt = ChatLogRules.peek(ChatLogRules.newBatch(), "job", 0)
			T.expectEqual(embed, nil)
			T.expectEqual(#receipt.entries, 0)
		end)

		T.it("regroupe les messages dans l'ordre, avec le JobId en pied, et ne retire qu'au commit", function()
			local batch = ChatLogRules.newBatch()
			ChatLogRules.push(batch, message("un"))
			ChatLogRules.push(batch, message("deux"))
			local embed, receipt = ChatLogRules.peek(batch, "abc", 0)
			T.expectEqual(#receipt.entries, 2)
			T.expectEqual(#batch.entries, 2, "rien retiré avant l'envoi")
			T.expect(string.find(embed.description, "un\n", 1, true) ~= nil, "premier message en tête")
			T.expectEqual(embed.footer.text, "JobId abc")
			ChatLogRules.commit(batch, receipt)
			T.expectEqual(#batch.entries, 0, "lot vidé après l'envoi")
			ChatLogRules.push(batch, message("trois"))
			T.expectEqual(ChatLogRules.peek(batch, "", 0).footer.text, "JobId Studio")
		end)

		T.it("un envoi en échec (pas de commit) garde ses entrées pour le suivant", function()
			local batch = ChatLogRules.newBatch()
			ChatLogRules.push(batch, message("gardé"))
			ChatLogRules.peek(batch, "j", 0)
			local embed, receipt = ChatLogRules.peek(batch, "j", 0)
			T.expectEqual(#receipt.entries, 1)
			T.expect(string.find(embed.description, "gardé", 1, true) ~= nil)
		end)

		T.it("commit ne retire que les entrées envoyées, même si le lot a bougé pendant l'envoi", function()
			local batch = ChatLogRules.newBatch()
			for i = 1, ChatLogRules.MAX_PENDING do
				ChatLogRules.push(batch, message("m" .. i))
			end
			local _, receipt = ChatLogRules.peek(batch, "j", 0)
			local sent = #receipt.entries
			-- Pendant l'envoi : 3 nouveaux messages font tomber les 3 plus anciens (déjà dans l'envoi)
			for i = 1, 3 do
				ChatLogRules.push(batch, message("nouveau" .. i))
			end
			T.expectEqual(batch.dropped, 3)
			ChatLogRules.commit(batch, receipt)
			T.expectEqual(#batch.entries, ChatLogRules.MAX_PENDING - sent + 3, "les non envoyés restent")
			T.expectEqual(batch.entries[#batch.entries].text, "nouveau3")
			T.expectEqual(batch.dropped, 3, "pertes survenues pendant l'envoi encore à signaler")
		end)

		T.it("s'arrête devant une entrée encore en filtrage, sauf délai dépassé ou envoi forcé", function()
			local batch = ChatLogRules.newBatch()
			ChatLogRules.push(batch, message("avant", 100))
			local pending = message("brut", 100)
			pending.pending = true
			ChatLogRules.push(batch, pending)
			ChatLogRules.push(batch, message("après", 100))
			local embed, receipt = ChatLogRules.peek(batch, "j", 105)
			T.expectEqual(#receipt.entries, 1, "seulement l'entrée prête avant")
			T.expect(string.find(embed.description, "après", 1, true) == nil, "ordre gardé")
			ChatLogRules.commit(batch, receipt)
			T.expectEqual((ChatLogRules.peek(batch, "j", 105)), nil, "rien tant que le filtrage court")
			local late, lateReceipt = ChatLogRules.peek(batch, "j", 100 + ChatLogRules.PENDING_TIMEOUT)
			T.expectEqual(#lateReceipt.entries, 2, "délai dépassé : l'entrée part")
			T.expect(string.find(late.description, "filtrage trop long", 1, true) ~= nil, "texte de remplacement")
			T.expect(string.find(late.description, "brut", 1, true) == nil, "jamais le texte brut")
			local forced = ChatLogRules.peek(batch, "j", 105, true)
			T.expect(forced ~= nil, "envoi forcé à l'arrêt")
		end)

		T.it("découpe un gros lot en plusieurs envois sous la limite de Discord", function()
			local batch = ChatLogRules.newBatch()
			for i = 1, 100 do
				ChatLogRules.push(batch, message(string.rep("x", 100) .. i))
			end
			local total = 0
			local sends = 0
			while true do
				local embed, receipt = ChatLogRules.peek(batch, "j", 0)
				if not embed then
					break
				end
				T.expect(#embed.description <= ChatLogRules.MAX_DESCRIPTION, "description bornée")
				ChatLogRules.commit(batch, receipt)
				total += #receipt.entries
				sends += 1
			end
			T.expectEqual(total, 100, "aucune entrée perdue")
			T.expect(sends > 1, "plusieurs envois")
		end)

		T.it("abandonne les plus anciennes au-delà de MAX_PENDING et le signale", function()
			local batch = ChatLogRules.newBatch()
			for i = 1, ChatLogRules.MAX_PENDING + 3 do
				ChatLogRules.push(batch, message("m" .. i))
			end
			T.expectEqual(#batch.entries, ChatLogRules.MAX_PENDING)
			T.expectEqual(batch.dropped, 3)
			T.expectEqual(batch.entries[1].text, "m4", "les plus anciennes partent")
			local embed, receipt = ChatLogRules.peek(batch, "j", 0)
			T.expect(string.find(embed.description, "3 entrée(s) perdue(s)", 1, true) ~= nil, "perte signalée")
			T.expectEqual(batch.dropped, 3, "compte gardé tant que l'envoi n'a pas réussi")
			ChatLogRules.commit(batch, receipt)
			T.expectEqual(batch.dropped, 0)
		end)
	end)
end

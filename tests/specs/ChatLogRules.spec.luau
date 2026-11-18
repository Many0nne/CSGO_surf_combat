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

	T.describe("ChatLogRules.take", function()
		T.it("ne renvoie rien pour un lot vide", function()
			local embed, taken = ChatLogRules.take(ChatLogRules.newBatch(), "job")
			T.expectEqual(embed, nil)
			T.expectEqual(taken, 0)
		end)

		T.it("regroupe les messages dans l'ordre, avec le JobId en pied", function()
			local batch = ChatLogRules.newBatch()
			ChatLogRules.push(batch, message("un"))
			ChatLogRules.push(batch, message("deux"))
			local embed, taken = ChatLogRules.take(batch, "abc")
			T.expectEqual(taken, 2)
			T.expectEqual(#batch.entries, 0, "lot vidé")
			T.expect(string.find(embed.description, "un\n", 1, true) ~= nil, "premier message en tête")
			T.expectEqual(embed.footer.text, "JobId abc")
			T.expectEqual((ChatLogRules.take(ChatLogRules.newBatch(), "")), nil)
		end)

		T.it("découpe un gros lot en plusieurs envois sous la limite de Discord", function()
			local batch = ChatLogRules.newBatch()
			for i = 1, 100 do
				ChatLogRules.push(batch, message(string.rep("x", 100) .. i))
			end
			local total = 0
			local sends = 0
			while true do
				local embed, taken = ChatLogRules.take(batch, "j")
				if not embed then
					break
				end
				T.expect(#embed.description <= ChatLogRules.MAX_DESCRIPTION, "description bornée")
				total += taken
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
			local embed = ChatLogRules.take(batch, "j")
			T.expect(string.find(embed.description, "3 entrée(s) perdue(s)", 1, true) ~= nil, "perte signalée")
			T.expectEqual(batch.dropped, 0)
		end)
	end)
end
